#!/usr/bin/env python3

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.dependency_lock import DEFAULT_LOCK, load_lock  # noqa: E402


def component(name: str, kind: str, spec: dict[str, object]) -> dict[str, object]:
    license_name = str(spec.get("license", "NOASSERTION"))
    license_value = (
        {"name": license_name}
        if license_name == "NOASSERTION" or license_name.startswith("LicenseRef-")
        else {"id": license_name}
    )
    item: dict[str, object] = {
        "type": "library" if kind != "toolchain" else "application",
        "name": name,
        "licenses": [{"license": license_value}],
        "externalReferences": [{"type": "distribution", "url": spec["url"]}],
    }
    if "revision" in spec:
        item["version"] = spec["revision"]
        item["properties"] = [{"name": "vcs:revision", "value": spec["revision"]}]
        if "nar_hash" in spec:
            item["properties"].append({"name": "nix:narHash", "value": spec["nar_hash"]})
    else:
        item["version"] = spec.get("version", spec.get("sha256", "unknown"))
        item["hashes"] = [{"alg": "SHA-256", "content": spec["sha256"]}]
    return item


def container_component(name: str, spec: dict[str, object]) -> dict[str, object]:
    license_name = str(spec.get("license", "NOASSERTION"))
    license_value = (
        {"name": license_name}
        if license_name == "NOASSERTION" or license_name.startswith("LicenseRef-")
        else {"id": license_name}
    )
    digest = str(spec["digest"])
    return {
        "type": "container",
        "name": f"container/{name}",
        "version": digest.removeprefix("sha256:"),
        "licenses": [{"license": license_value}],
        "externalReferences": [{"type": "distribution", "url": spec["url"]}],
        "hashes": [{"alg": "SHA-256", "content": digest.removeprefix("sha256:")}],
        "properties": [{"name": "oci:image", "value": spec["image"]}],
    }


def make_sbom(lock: dict[str, object]) -> dict[str, object]:
    components = [component(name, "source", spec) for name, spec in lock["sources"].items()]
    components.extend(component(name, "archive", spec) for name, spec in lock["archives"].items())
    components.extend(
        container_component(name, spec) for name, spec in lock["container_images"].items()
    )
    components.extend(
        component(f"nix/{name}", "source", spec) for name, spec in lock["nix_inputs"].items()
    )
    for platform, tools in lock["toolchains"].items():
        components.extend(
            component(f"{platform}/{name}", "toolchain", spec) for name, spec in tools.items()
        )
    return {
        "bomFormat": "CycloneDX",
        "specVersion": "1.5",
        "version": 1,
        "components": components,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Create retroSoC source deliverables")
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--lock", type=Path, default=DEFAULT_LOCK)
    parser.add_argument("--variant-root", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    root = args.root.resolve()
    manifest_path = args.variant_root.resolve() / "meta/manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    config = manifest["configuration"]
    lock = load_lock(args.lock)
    args.output_dir.parent.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(
        prefix="retrosoc-package-", dir=args.output_dir.parent
    ) as temp:
        staging = Path(temp) / "package"
        staging.mkdir()
        timing_contract = Path(temp) / "commercial_timing_contract.tcl"
        subprocess.run(
            [
                "python3",
                str(
                    root
                    / "physical/commercial/scripts/generate_timing_contract.py"
                ),
                "--domains",
                str(root / "rtl/mini/integration/clock_reset_domains.json"),
                "--pin-map",
                str(root / "rtl/mini/pin_map/pin_map.json"),
                "--output",
                str(timing_contract),
            ],
            cwd=root,
            check=True,
        )
        command = [
            "python3",
            str(root / "physical/smoke/syn/tools/export_soc_sources.py"),
            "sv",
            "--output-dir",
            str(staging),
            "--pdk",
            config["PDK"],
            "--simu",
            config["SIMU"],
            "--jtag-idcode",
            config.get("JTAG_IDCODE", "DEADBEEF"),
            "--ext-clk-hz",
            str(config.get("EXT_CLK_HZ", 72_000_000)),
            "--aud-clk-hz",
            str(config.get("AUD_CLK_HZ", 18_432_000)),
            "--clint-timebase-hz",
            str(config.get("CLINT_TIMEBASE_HZ", 1_000_000)),
            "--dynamic-core-filelist",
            str(args.variant_root / "generated/mpw" / config["SIMU"].lower() / "core/core.fl"),
            "--dynamic-ip-filelist",
            str(args.variant_root / "generated/mpw" / config["SIMU"].lower() / "ip/ip.fl"),
            "--memory-map-filelist",
            str(args.variant_root / "generated/memory_map/memory_map.fl"),
            "--soc-topology-filelist",
            str(args.variant_root / "generated/soc_topology/soc_topology.fl"),
            "--user-extensions-filelist",
            str(args.variant_root / "generated/user_extensions/user_extensions.fl"),
            "--pin-map-filelist",
            str(args.variant_root / "generated/pin_map/pin_map.fl"),
            "--archinfo-incdir",
            str(args.variant_root / "generated/archinfo"),
            "--metadata-file",
            "contracts/commercial_timing_contract.tcl={0}".format(timing_contract),
        ]
        for key, flag in (
            ("HAVE_PLL", "--have-pll"),
            ("HAVE_SRAM_IF", "--have-sram-if"),
            ("HAVE_SRAM_MACRO", "--have-sram-macro"),
            ("HAVE_SVA", "--have-sva"),
        ):
            if config.get(key) == "YES":
                command.append(flag)
        subprocess.run(command, cwd=root, check=True)
        command[2] = "tar"
        subprocess.run(command, cwd=root, check=True)
        shutil.copy2(args.lock, staging / "dependencies.lock.json")
        shutil.copy2(manifest_path, staging / "manifest.json")
        (staging / "sbom.cdx.json").write_text(
            json.dumps(make_sbom(lock), indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        checksums = []
        for path in sorted(item for item in staging.iterdir() if item.is_file()):
            checksums.append(f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.name}")
        (staging / "SHA256SUMS").write_text("\n".join(checksums) + "\n", encoding="utf-8")
        if args.output_dir.exists():
            shutil.rmtree(args.output_dir)
        shutil.copytree(staging, args.output_dir)
    print(f"package: {args.output_dir.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
