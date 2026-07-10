from __future__ import annotations

import hashlib
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
FILELIST_SCRIPT_DIR = ROOT / "rtl/mini/script"
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(FILELIST_SCRIPT_DIR))

from filelist import FileList, atomic_write, parse_filelists, write_filelist  # noqa: E402
from generate_filelist import generate_all  # noqa: E402
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
    generated_def = ROOT / "rtl/mini/.generated_fl/def.fl"
    before = generated_def.stat().st_mtime_ns if generated_def.exists() else None
    run("make", "-n", "help")
    run("make", "-n", "SIMU=IVERILOG", "comp")
    after = generated_def.stat().st_mtime_ns if generated_def.exists() else None
    assert after == before

    invalid = subprocess.run(
        ["make", "SIMU=UNKNOWN", "help"],
        cwd=ROOT,
        text=True,
        capture_output=True,
    )
    assert invalid.returncode != 0
    assert "Invalid SIMU='UNKNOWN'" in invalid.stderr


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
    )
    assert not generated.exists()
    assert (dependency / "model.v").is_file()
