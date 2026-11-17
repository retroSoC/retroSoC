#!/usr/bin/env python3
"""Restore and diagnose the complete hosted-Pytest fixture set from local locks."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from scripts.dependency_lock import load_lock  # noqa: E402
from scripts.flow_control import utc_now, write_json  # noqa: E402
from scripts.install_toolchain import safe_extract  # noqa: E402
from scripts.setup_helpers import atomic_write, download_file, sha256  # noqa: E402
from scripts.worktree_bootstrap import restore_sources  # noqa: E402
from scripts.worktree_registry import git  # noqa: E402

HOSTED_PYTEST_SOURCES = (
    "mpw",
    "hazard3",
    "openc906",
    "third_party_ip",
    "publication_media",
    "pdk_ihp130",
    "pdk_ics55",
    "pdk_ics55_pll",
    "apu_mlperf_tiny",
    "apu_kws_mfcc",
    "apu_tfds",
    "apu_tensorflow",
    "apu_gemmlowp",
)
HOSTED_PYTEST_ARCHIVES = (
    "apu_libflac",
    "apu_flac_corpus",
    "apu_kws_pcm",
    "npu_vww_dataset",
    "pdk_ics55_h7cr_liberty",
)
HOSTED_PYTEST_TOOLS = ("verilator", "sv2v", "iverilog", "yosys", "riscv_gnu")
TOOL_PLATFORM = "ubuntu-22.04"


def fixture_profile(root: Path, reference_root: Path | None) -> dict[str, Any]:
    root = root.resolve()
    reference_root = reference_root.resolve() if reference_root is not None else None
    lock = load_lock(root / "dependencies/dependencies.lock.json")
    names = [*HOSTED_PYTEST_SOURCES, *sorted(name for name in lock["sources"] if name.startswith("cluster_"))]
    sources = []
    for name in names:
        source = lock["sources"].get(name)
        if not isinstance(source, dict):
            raise ValueError(f"hosted fixture source is missing from the lock: {name}")
        sources.append({"name": name, **source})

    archive_names = [
        *HOSTED_PYTEST_ARCHIVES,
        *sorted(name for name in lock["archives"] if name.startswith("pdk_ics55_sram_")),
    ]
    archives = []
    for name in archive_names:
        spec = lock["archives"].get(name)
        if not isinstance(spec, dict):
            raise ValueError(f"hosted fixture archive is missing from the lock: {name}")
        destination = spec["destination"]
        archives.append(
            {
                "name": name,
                "kind": "archive",
                "destination": destination,
                "sha256": spec["sha256"],
                "reference": str(reference_root / destination) if reference_root is not None else None,
            }
        )

    tools = lock["toolchains"].get(TOOL_PLATFORM)
    if not isinstance(tools, dict):
        raise ValueError(f"toolchain platform is missing: {TOOL_PLATFORM}")
    for name in HOSTED_PYTEST_TOOLS:
        spec = tools.get(name)
        if not isinstance(spec, dict):
            raise ValueError(f"hosted fixture tool is missing from the lock: {name}")
        relative = f".cache/retrosoc/downloads/{spec['archive']}"
        archives.append(
            {
                "name": f"toolchain:{name}",
                "kind": "toolchain",
                "destination": relative,
                "sha256": spec["sha256"],
                "reference": str(reference_root / relative) if reference_root is not None else None,
            }
        )

    for name, spec in lock["archives"].items():
        package_name = spec.get("package_name")
        if package_name is None:
            continue
        relative = f".cache/retrosoc/publications/downloads/{package_name}-{spec['version']}.tar.gz"
        archives.append(
            {
                "name": f"publication:{name}",
                "kind": "publication_package",
                "destination": relative,
                "sha256": spec["sha256"],
                "reference": str(reference_root / relative) if reference_root is not None else None,
            }
        )

    tool_paths = [
        str(root / ".cache/retrosoc/toolchains" / f"{name}-{tools[name]['version']}" / tools[name]["path"])
        for name in HOSTED_PYTEST_TOOLS
    ]
    return {
        "schema_version": 1,
        "profile": "hosted-pytest",
        "source_revision": git(root, "rev-parse", "HEAD").stdout.strip(),
        "network_policy": "locked local references only; Git subprocesses allow file protocol only",
        "sources": sources,
        "archives": archives,
        "tools": HOSTED_PYTEST_TOOLS,
        "tool_paths": tool_paths,
        "commands": setup_commands(reference_root),
    }


def setup_commands(reference_root: Path | None) -> list[list[str]]:
    reference = str(reference_root) if reference_root is not None else "<reference-root>"
    return [
        [sys.executable, "setup.py"],
        [sys.executable, "scripts/setup_openc906.py"],
        [sys.executable, "rtl/managed/clusterip/setup.py"],
        [sys.executable, "rtl/ip/setup.py"],
        [sys.executable, "tests/publication_history.py", "prepare", "--reference-root", reference],
        ["make", "CONFIG=configs/ci/ihp130.mk", "setup-pdk"],
        ["make", "CONFIG=configs/ci/ics55-tiny.mk", "SOC=TINY", "PDK=ICS55", "setup-pdk"],
        ["make", "setup-apu-reference", "setup-apu-kws-reference", "setup-npu-reference"],
        [
            sys.executable,
            "scripts/install_toolchain.py",
            "--lock",
            "dependencies/dependencies.lock.json",
            "--platform",
            TOOL_PLATFORM,
            "--cache",
            ".cache/retrosoc",
            *[item for name in HOSTED_PYTEST_TOOLS for item in ("--tool", name)],
        ],
    ]


TOOL_EXECUTABLES = {
    "verilator": "verilator",
    "sv2v": "sv2v",
    "iverilog": "iverilog",
    "yosys": "yosys",
    "riscv_gnu": "riscv32-unknown-elf-gcc",
}


def discover_tool_archive(spec: dict[str, Any]) -> Path | None:
    name = spec["name"].removeprefix("toolchain:")
    executable_name = TOOL_EXECUTABLES.get(name)
    if executable_name is None:
        return None
    executable = shutil.which(executable_name)
    if executable is None:
        return None
    installed = Path(executable).resolve()
    for directory in dict.fromkeys((installed.parent, installed.parent.parent, installed.parent.parent.parent)):
        candidate = directory / Path(spec["destination"]).name
        if candidate.is_file() and not candidate.is_symlink():
            return candidate
    return None


def restore_archive(root: Path, spec: dict[str, Any]) -> dict[str, Any]:
    destination = root / spec["destination"]
    reference_value = spec.get("reference")
    if not isinstance(reference_value, str) or not reference_value:
        raise ValueError(f"archive reference is required: {spec['name']}")
    reference = Path(reference_value)
    if destination.is_symlink() or reference.is_symlink():
        raise RuntimeError(f"archive paths must not be symlinks: {spec['name']}")
    if destination.exists():
        if not destination.is_file() or sha256(destination) != spec["sha256"]:
            raise RuntimeError(f"existing archive differs from its lock: {spec['name']}")
        mode = "local-archive"
    else:
        mode = "locked-copy"
        if not reference.is_file() and spec.get("kind") == "toolchain":
            discovered = discover_tool_archive(spec)
            if discovered is not None:
                reference = discovered
                mode = "locked-copy-host-cache"
        if not reference.is_file() or sha256(reference) != spec["sha256"]:
            raise RuntimeError(f"local archive reference is missing or invalid: {spec['name']}")
        download_file(reference.as_uri(), destination, spec["sha256"], retries=1, timeout=30)
    return {
        **spec,
        "reference": str(reference),
        "bytes": destination.stat().st_size,
        "restore_mode": mode,
        "status": "VERIFIED",
    }


def restore_pcm_corpus(root: Path, archive_sha256: str) -> None:
    archive = root / ".cache/retrosoc/downloads/apu/kws-pcm-speech-commands-test-v0.02.tar.gz"
    destination = root / ".cache/retrosoc/sources/apu-kws-pcm"
    marker = destination / ".retrosoc-archive-sha256"
    if marker.is_file() and marker.read_text(encoding="utf-8").strip() == archive_sha256:
        return
    if destination.exists():
        raise RuntimeError("PCM corpus destination is stale or incomplete; preserve it for review")
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".apu-kws-pcm-", dir=destination.parent) as temporary:
        extracted = Path(temporary) / "content"
        extracted.mkdir()
        safe_extract(archive, extracted)
        atomic_write(extracted / ".retrosoc-archive-sha256", archive_sha256 + "\n")
        if destination.exists():
            raise RuntimeError("PCM corpus destination appeared during restoration")
        extracted.replace(destination)


def doctor(root: Path, profile: dict[str, Any]) -> dict[str, Any]:
    root = root.resolve()
    issues = []
    checks = []
    for source in profile["sources"]:
        destination = root / source["destination"]
        actual = git(destination, "rev-parse", "HEAD").stdout.strip()
        dirty = git(destination, "status", "--porcelain", "--untracked-files=all").stdout.strip()
        issue = None
        if actual != source["revision"]:
            issue = f"revision mismatch: expected {source['revision']}, got {actual or 'missing'}"
        elif dirty:
            issue = "locked source has local changes"
        checks.append({"name": source["name"], "path": source["destination"], "revision": actual or None, "issue": issue})
        if issue:
            issues.append(f"{source['name']}: {issue}")
    for archive in profile["archives"]:
        path = root / archive["destination"]
        actual = sha256(path) if path.is_file() and not path.is_symlink() else None
        issue = None if actual == archive["sha256"] else "archive is missing or differs from its lock"
        checks.append({"name": archive["name"], "path": archive["destination"], "sha256": actual, "issue": issue})
        if issue:
            issues.append(f"{archive['name']}: {issue}")
    try:
        lock = load_lock(root / "dependencies/dependencies.lock.json")
    except ValueError as error:
        issues.append(str(error))
        lock = {"toolchains": {}, "archives": {}}
    tools = lock["toolchains"].get(TOOL_PLATFORM, {})
    for name in profile["tools"]:
        spec = tools.get(name)
        if not isinstance(spec, dict):
            issues.append(f"{name}: toolchain lock entry is missing")
            checks.append({"name": name, "path": None, "issue": "toolchain lock entry is missing"})
            continue
        destination = root / ".cache/retrosoc/toolchains" / f"{name}-{spec['version']}"
        marker = destination / ".complete"
        issue = None
        if not marker.is_file() or marker.read_text(encoding="utf-8").strip() != spec["sha256"]:
            issue = "toolchain completion marker is missing or invalid"
        elif not (destination / spec["path"]).is_dir():
            issue = "toolchain executable path is missing"
        checks.append({"name": name, "path": str(destination), "issue": issue})
        if issue:
            issues.append(f"{name}: {issue}")
    pcm = root / ".cache/retrosoc/sources/apu-kws-pcm/.retrosoc-archive-sha256"
    pcm_expected = lock["archives"].get("apu_kws_pcm", {}).get("sha256")
    if not pcm.is_file() or pcm.read_text(encoding="utf-8").strip() != pcm_expected:
        issues.append("apu_kws_pcm: extracted corpus marker is missing or invalid")
    return {
        "schema_version": 1,
        "profile": profile["profile"],
        "source_revision": git(root, "rev-parse", "HEAD").stdout.strip(),
        "source_dirty": bool(git(root, "status", "--porcelain", "--untracked-files=all").stdout.strip()),
        "created_at": utc_now(),
        "status": "READY" if not issues else "BLOCKED",
        "issue_count": len(issues),
        "issues": issues,
        "checks": checks,
        "tool_paths": profile["tool_paths"],
    }


def restore(root: Path, reference_root: Path, output: Path) -> dict[str, Any]:
    root = root.resolve()
    reference_root = reference_root.resolve()
    if root == reference_root:
        raise ValueError("fixture restoration requires distinct target and reference worktrees")
    profile = fixture_profile(root, reference_root)
    document = {
        **profile,
        "created_at": utc_now(),
        "execution": "execute",
        "reference_root": str(reference_root),
        "status": "RESTORING",
        "restored_sources": [],
        "restored_archives": [],
        "setup_results": [],
    }

    def record() -> None:
        write_json(output, document)

    try:
        record()
        document["restored_sources"] = restore_sources(
            reference_root,
            root,
            profile["source_revision"],
            [source["name"] for source in profile["sources"]],
            False,
        )
        record()
        for archive in profile["archives"]:
            document["restored_archives"].append(restore_archive(root, archive))
            record()
        pcm_sha256 = next(
            archive["sha256"] for archive in profile["archives"] if archive["name"] == "apu_kws_pcm"
        )
        restore_pcm_corpus(root, pcm_sha256)
        environment = os.environ.copy()
        environment["GIT_ALLOW_PROTOCOL"] = "file"
        for command in profile["commands"]:
            completed = subprocess.run(command, cwd=root, env=environment, check=False)
            result = {"command": command, "exit_code": completed.returncode, "status": "PASS" if completed.returncode == 0 else "FAIL"}
            document["setup_results"].append(result)
            record()
            if completed.returncode:
                raise RuntimeError(f"fixture setup command failed with exit {completed.returncode}: {command}")
        verdict = doctor(root, profile)
        document["doctor"] = verdict
        if verdict["status"] != "READY":
            raise RuntimeError("restored fixture set did not pass doctor")
        document["status"] = "READY"
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        document["status"] = "FAILED"
        document["error"] = str(error)
        record()
        raise
    record()
    return document


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    for name in ("plan", "restore", "doctor"):
        command = subparsers.add_parser(name)
        command.add_argument("--root", type=Path, default=ROOT)
        command.add_argument("--reference-root", type=Path)
        command.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        if args.command == "restore":
            if args.reference_root is None:
                raise ValueError("restore requires --reference-root")
            result = restore(args.root, args.reference_root, args.output)
        else:
            profile = fixture_profile(args.root, args.reference_root)
            if args.command == "doctor":
                result = doctor(args.root, profile)
            else:
                if args.reference_root is None:
                    raise ValueError("plan requires --reference-root")
                result = {**profile, "created_at": utc_now(), "execution": "dry-run", "status": "PLANNED"}
            write_json(args.output, result)
        print(json.dumps({"status": result["status"], "output": str(args.output.resolve())}, sort_keys=True))
        return int(result["status"] == "BLOCKED")
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"fixture control: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
