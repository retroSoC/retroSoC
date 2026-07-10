from __future__ import annotations

import hashlib
import io
import json
import re
import signal
import subprocess
import sys
import tarfile
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
FILELIST_SCRIPT_DIR = ROOT / "rtl/mini/script"
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(FILELIST_SCRIPT_DIR))

from filelist import atomic_write, parse_filelists, write_filelist  # noqa: E402
from generate_filelist import generate_all  # noqa: E402
from scripts.analyze_warnings import normalize  # noqa: E402
from scripts.dependency_lock import LockError, load_lock  # noqa: E402
from scripts.install_toolchain import safe_extract  # noqa: E402
from scripts.setup_helpers import download_file, ensure_git_repo  # noqa: E402


def run(*command: str, cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        cwd=cwd or ROOT,
        text=True,
        capture_output=True,
        check=True,
    )


def test_atomic_write_preserves_unchanged_mtime(tmp_path: Path) -> None:
    output = tmp_path / "output.fl"
    assert atomic_write(output, "same\n") is True
    first_mtime = output.stat().st_mtime_ns
    assert atomic_write(output, "same\n") is False
    assert output.stat().st_mtime_ns == first_mtime


def test_nested_filelist_and_space_path_round_trip(tmp_path: Path) -> None:
    include_dir = tmp_path / "include files"
    include_dir.mkdir()
    source = tmp_path / "source file.sv"
    library = tmp_path / "library file.v"
    source.write_text("module source_file; endmodule\n", encoding="utf-8")
    library.write_text("module library_file; endmodule\n", encoding="utf-8")

    nested = tmp_path / "nested.fl"
    nested.write_text(
        f'"{source}"\n-v "{library}"\n',
        encoding="utf-8",
    )
    top = tmp_path / "top.fl"
    top.write_text(
        f'+define+TEST=1\n"+incdir+{include_dir}"\n-f "{nested}"\n',
        encoding="utf-8",
    )

    parsed = parse_filelists([top])
    assert parsed.defines == ["+define+TEST=1"]
    assert parsed.incdirs == [include_dir.resolve()]
    assert parsed.files == [source.resolve()]
    assert parsed.library_files == [library.resolve()]

    output = tmp_path / "round trip.fl"
    write_filelist(output, parsed)
    assert parse_filelists([output]) == parsed


def test_generate_all_is_stable_and_expands_paths(tmp_path: Path) -> None:
    defines = ["+define+PDK_IHP130", "+define+CORE_HAZARD3"]
    generated = generate_all(tmp_path, defines)
    mtimes = {path: path.stat().st_mtime_ns for path in generated}
    generate_all(tmp_path, defines)
    assert {path: path.stat().st_mtime_ns for path in generated} == mtimes
    assert (tmp_path / "def.fl").read_text(encoding="utf-8") == " ".join(defines) + "\n"
    cluster = (tmp_path / "clusterip.fl").read_text(encoding="utf-8")
    assert str(ROOT / "rtl/clusterip") in cluster


def test_prepare_norflash_and_missing_firmware(tmp_path: Path) -> None:
    models = tmp_path / "models"
    models.mkdir()
    for name in ("SECSI.TXT", "SFDP.TXT", "SREG.TXT"):
        (models / name).write_text(name, encoding="utf-8")
    firmware = tmp_path / "firmware.hex"
    firmware.write_text("00\n", encoding="utf-8")
    sim_dir = tmp_path / "sim"
    script = ROOT / "rtl/mini/script/prepare_norflash.py"

    run(
        sys.executable,
        str(script),
        "--sim-dir",
        str(sim_dir),
        "--models-dir",
        str(models),
        "--firmware",
        str(firmware),
    )
    assert (sim_dir / "MEM.TXT").resolve() == firmware.resolve()
    assert (sim_dir / "SFDP.TXT").read_text(encoding="utf-8") == "SFDP.TXT"

    firmware.unlink()
    result = subprocess.run(
        [
            sys.executable,
            str(script),
            "--sim-dir",
            str(sim_dir),
            "--models-dir",
            str(models),
            "--firmware",
            str(firmware),
        ],
        text=True,
        capture_output=True,
    )
    assert result.returncode != 0
    assert "firmware image not found" in result.stderr


def test_dependency_helpers_are_idempotent(tmp_path: Path) -> None:
    source = tmp_path / "source"
    run("git", "init", str(source))
    run("git", "config", "user.email", "test@example.com", cwd=source)
    run("git", "config", "user.name", "Test", cwd=source)
    run("git", "config", "commit.gpgsign", "false", cwd=source)
    (source / "dependency.txt").write_text("pinned\n", encoding="utf-8")
    run("git", "add", "dependency.txt", cwd=source)
    run("git", "commit", "-m", "pinned", cwd=source)
    revision = run("git", "rev-parse", "HEAD", cwd=source).stdout.strip()

    destination = tmp_path / "checkout"
    ensure_git_repo(str(source), destination, revision)
    first_head = run("git", "rev-parse", "HEAD", cwd=destination).stdout.strip()
    ensure_git_repo(str(source), destination, revision)
    assert run("git", "rev-parse", "HEAD", cwd=destination).stdout.strip() == first_head

    payload = tmp_path / "payload.bin"
    payload.write_bytes(b"verified")
    digest = hashlib.sha256(payload.read_bytes()).hexdigest()
    downloaded = tmp_path / "downloaded.bin"
    download_file(payload.as_uri(), downloaded, digest)
    first_mtime = downloaded.stat().st_mtime_ns
    download_file(payload.as_uri(), downloaded, digest)
    assert downloaded.stat().st_mtime_ns == first_mtime


def test_make_dry_run_and_validation_do_not_write_filelists() -> None:
    def build_state() -> dict[str, tuple[int, int]]:
        build = ROOT / "build"
        if not build.exists():
            return {}
        return {
            str(path.relative_to(build)): (path.stat().st_size, path.stat().st_mtime_ns)
            for path in build.rglob("*")
            if path.is_file()
        }

    before = build_state()
    run("make", "-n", "help")
    run("make", "-n", "SIMU=IVERILOG", "comp")
    run(
        "make",
        "-n",
        "CONFIG=configs/ci/hazard3-rv32im-ihp130.mk",
        "SIMU=IVERILOG",
        "RTL_SIM_TIMEOUT=5200000",
        "sim-asm",
    )
    assert build_state() == before

    invalid = subprocess.run(
        ["make", "SIMU=UNKNOWN", "help"],
        cwd=ROOT,
        text=True,
        capture_output=True,
    )
    assert invalid.returncode != 0
    assert "Invalid SIMU='UNKNOWN'" in invalid.stderr


def test_dependency_lock_and_config_key_are_deterministic(tmp_path: Path) -> None:
    lock = load_lock(ROOT / "config/dependencies.lock.json")
    assert lock["schema_version"] == 1
    assert len(lock["sources"]["mpw"]["revision"]) == 40

    command = (
        sys.executable,
        str(ROOT / "scripts/config_key.py"),
        "--lock",
        str(ROOT / "config/dependencies.lock.json"),
        "--profile",
        "unit",
        "--value",
        "CORE=HAZARD3",
        "--value",
        "PDK=IHP130",
    )
    first = run(*command).stdout.strip()
    second = run(*command).stdout.strip()
    assert first == second
    assert first.startswith("unit-")

    broken = tmp_path / "broken.json"
    broken.write_text('{"schema_version": 1}\n', encoding="utf-8")
    try:
        load_lock(broken)
    except LockError as error:
        assert "missing or empty" in str(error)
    else:
        raise AssertionError("invalid dependency lock was accepted")


def test_run_flow_writes_structured_result(tmp_path: Path) -> None:
    log = tmp_path / "flow.log"
    result = tmp_path / "result.json"
    run(
        sys.executable,
        str(ROOT / "scripts/run_flow.py"),
        "--tool",
        "unit",
        "--log",
        str(log),
        "--result",
        str(result),
        "--",
        sys.executable,
        "-c",
        "print('flow output')",
    )
    data = json.loads(result.read_text(encoding="utf-8"))
    assert data["status"] == "passed"
    assert data["exit_code"] == 0
    assert data["duration_seconds"] >= 0
    assert log.read_text(encoding="utf-8") == "flow output\n"


def test_run_flow_records_interruption(tmp_path: Path) -> None:
    log = tmp_path / "interrupted.log"
    result = tmp_path / "interrupted.json"
    process = subprocess.Popen(
        [
            sys.executable,
            str(ROOT / "scripts/run_flow.py"),
            "--tool",
            "unit",
            "--log",
            str(log),
            "--result",
            str(result),
            "--",
            sys.executable,
            "-c",
            "import time; time.sleep(30)",
        ],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    for _ in range(50):
        if log.exists():
            break
        time.sleep(0.02)
    process.send_signal(signal.SIGINT)
    process.communicate(timeout=10)
    assert process.returncode == 130
    data = json.loads(result.read_text(encoding="utf-8"))
    assert data["status"] == "failed"
    assert data["exit_code"] == 130
    assert data["error"] == "interrupted"


def test_simulation_success_marker_and_failure_detection(tmp_path: Path) -> None:
    log = tmp_path / "sim.log"
    result = tmp_path / "result.json"
    log.write_text(
        "retroSoC: A Customized ASIC for Retro Stuff\nSimulation complete\n",
        encoding="utf-8",
    )
    run(
        sys.executable,
        str(ROOT / "scripts/check_simulation.py"),
        "--log",
        str(log),
        "--result",
        str(result),
    )
    assert json.loads(result.read_text(encoding="utf-8"))["status"] == "passed"

    log.write_text(
        "retroSoC: A Customized ASIC for Retro Stuff\nTEST FAILED\n",
        encoding="utf-8",
    )
    failed = subprocess.run(
        [
            sys.executable,
            str(ROOT / "scripts/check_simulation.py"),
            "--log",
            str(log),
            "--result",
            str(result),
        ],
        text=True,
        capture_output=True,
    )
    assert failed.returncode != 0
    assert json.loads(result.read_text(encoding="utf-8"))["status"] == "failed"


def test_warning_baseline_rejects_new_signature(tmp_path: Path) -> None:
    profile = "unit-profile"
    log = tmp_path / "variant/sim/verilator/verilating.log"
    log.parent.mkdir(parents=True)
    log.write_text(
        f"%Warning-WIDTH: {tmp_path}/rtl/top.sv:12: width mismatch\n",
        encoding="utf-8",
    )
    baseline = tmp_path / f"quality/warnings/{profile}/verilator.json"
    run(
        sys.executable,
        str(ROOT / "scripts/analyze_warnings.py"),
        "baseline",
        "--root",
        str(tmp_path),
        "--profile",
        profile,
        "--tool",
        "verilator",
        "--log",
        str(log),
        "--output",
        str(baseline),
    )
    report = tmp_path / "warnings.json"
    run(
        sys.executable,
        str(ROOT / "scripts/analyze_warnings.py"),
        "check",
        "--root",
        str(tmp_path),
        "--profile",
        profile,
        "--variant-root",
        str(tmp_path / "variant"),
        "--tool",
        "verilator",
        "--output",
        str(report),
    )

    log.write_text(
        log.read_text(encoding="utf-8")
        + f"%Warning-UNUSED: {tmp_path}/rtl/top.sv:20: unused signal\n",
        encoding="utf-8",
    )
    failed = subprocess.run(
        [
            sys.executable,
            str(ROOT / "scripts/analyze_warnings.py"),
            "check",
            "--root",
            str(tmp_path),
            "--profile",
            profile,
            "--variant-root",
            str(tmp_path / "variant"),
            "--tool",
            "verilator",
            "--output",
            str(report),
        ],
        text=True,
        capture_output=True,
    )
    assert failed.returncode != 0
    assert json.loads(report.read_text(encoding="utf-8"))["failed_tools"] == ["verilator"]


def test_warning_normalization_keeps_ranges_and_removes_variant_hash(tmp_path: Path) -> None:
    message = (
        f"{tmp_path}/build/profile-deadbeef/generated/core.sv:42: "
        "Bit extraction of var[7:0] is too wide"
    )
    normalized = normalize(tmp_path, "WIDTH", message)
    assert normalized == (
        "WIDTH:$BUILD/generated/core.sv:<line>: "
        "Bit extraction of var[7:0] is too wide"
    )


def test_metrics_collection_and_observe_policy(tmp_path: Path) -> None:
    variant = tmp_path / "variant"
    (variant / "sw").mkdir(parents=True)
    (variant / "sw/firmware.bin").write_bytes(b"1234")
    report_dir = variant / "syn/yosys/rpt"
    report_dir.mkdir(parents=True)
    (report_dir / "retrosoc_asic_area.rpt").write_text(
        "  42 1.23E+02 retrosoc_asic\n"
        "Chip area for top module '\\retrosoc_asic': 123.0\n",
        encoding="utf-8",
    )
    (report_dir / "retrosoc_asic_area.json").write_text(
        json.dumps({"design": {"area": 124.0, "num_cells": 43}}),
        encoding="utf-8",
    )
    timing_dir = variant / "sta/opensta"
    timing_dir.mkdir(parents=True)
    (timing_dir / "timing_metrics.rpt").write_text("-1.0\n-2.0\n-3.0\n-4.0\n", encoding="utf-8")
    (variant / "result-unit.json").write_text(
        json.dumps({"status": "passed", "duration_seconds": 1.25}),
        encoding="utf-8",
    )
    metrics = tmp_path / "metrics.json"
    run(
        sys.executable,
        str(ROOT / "scripts/metrics.py"),
        "collect",
        "--variant-root",
        str(variant),
        "--output",
        str(metrics),
    )
    data = json.loads(metrics.read_text(encoding="utf-8"))
    assert data["firmware"]["firmware.bin"]["bytes"] == 4
    assert data["synthesis"] == {"top_area": 124.0, "top_cells": 43}
    assert data["timing"]["wns_min"] == -1.0

    policy = tmp_path / "policy.json"
    policy.write_text('{"mode": "observe"}\n', encoding="utf-8")
    run(
        sys.executable,
        str(ROOT / "scripts/metrics.py"),
        "check",
        "--metrics",
        str(metrics),
        "--policy",
        str(policy),
    )


def test_safe_extract_rejects_parent_traversal(tmp_path: Path) -> None:
    archive = tmp_path / "unsafe.tar"
    with tarfile.open(archive, "w") as bundle:
        member = tarfile.TarInfo("../outside")
        payload = b"unsafe"
        member.size = len(payload)
        bundle.addfile(member, io.BytesIO(payload))
    try:
        safe_extract(archive, tmp_path / "output")
    except ValueError as error:
        assert "unsafe archive member" in str(error)
    else:
        raise AssertionError("unsafe archive was extracted")
    assert not (tmp_path / "outside").exists()


def test_ci_actions_are_pinned_to_commits() -> None:
    action_files = [
        *sorted((ROOT / ".github/workflows").glob("*.yml")),
        *sorted((ROOT / ".github/actions").glob("*/action.yml")),
    ]
    remote_uses = []
    for path in action_files:
        for line in path.read_text(encoding="utf-8").splitlines():
            match = re.match(r"\s*-?\s*uses:\s*([^\s#]+)", line)
            if match and not match.group(1).startswith("./"):
                remote_uses.append((path, match.group(1)))
    assert remote_uses
    for path, value in remote_uses:
        assert re.fullmatch(r"[^@]+@[0-9a-f]{40}", value), f"unpinned action in {path}: {value}"


def test_python_requirements_are_hash_locked() -> None:
    for path in sorted((ROOT / "requirements").glob("*.txt")):
        content = path.read_text(encoding="utf-8")
        assert "--require-hashes" in content
        assert "--only-binary=:all:" in content
        requirements = [
            line for line in content.splitlines() if line and not line.startswith(("#", "--"))
        ]
        assert requirements
        for requirement in requirements:
            assert re.search(r"==[^ ]+ --hash=sha256:[0-9a-f]{64}$", requirement), (
                f"unlocked requirement in {path}: {requirement}"
            )


def test_clean_all_stays_within_repository(tmp_path: Path) -> None:
    fake_root = tmp_path / "repository"
    (fake_root / ".git").mkdir(parents=True)
    (fake_root / "Makefile").write_text("all:\n", encoding="utf-8")
    generated = fake_root / "rtl/mini/.iverilog_build"
    generated.mkdir(parents=True)
    (generated / "simv").write_text("generated", encoding="utf-8")
    dependency = fake_root / "rtl/ip/3rd-party"
    dependency.mkdir(parents=True)
    (dependency / "model.v").write_text("dependency", encoding="utf-8")

    run(
        sys.executable,
        str(ROOT / "scripts/clean.py"),
        "--root",
        str(fake_root),
        "--path",
        str(generated),
    )
    assert not generated.exists()
    assert (dependency / "model.v").is_file()

    outside = subprocess.run(
        [
            sys.executable,
            str(ROOT / "scripts/clean.py"),
            "--root",
            str(fake_root),
            "--path",
            str(tmp_path / "outside"),
        ],
        text=True,
        capture_output=True,
    )
    assert outside.returncode != 0

    external = tmp_path / "external"
    external.mkdir()
    link = fake_root / "build-link"
    link.symlink_to(external, target_is_directory=True)
    run(
        sys.executable,
        str(ROOT / "scripts/clean.py"),
        "--root",
        str(fake_root),
        "--path",
        str(link),
    )
    assert not link.exists()
    assert external.is_dir()
