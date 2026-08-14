"""Repository layout invariants for self-owned IP and dependency inputs."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_self_owned_ip_is_flattened_and_dependency_lock_is_distinct() -> None:
    assert not (ROOT / "rtl/ip/ribp").exists()
    assert (ROOT / "rtl/ip/peripheral").is_dir()
    assert (ROOT / "rtl/ip/serial").is_dir()
    assert not (ROOT / "config").exists()
    assert (ROOT / "dependencies/dependencies.lock.json").is_file()
    assert (ROOT / "configs/ci/ihp130.mk").is_file()


def test_active_sources_do_not_reference_removed_paths() -> None:
    roots = (ROOT / "rtl/mini", ROOT / "scripts", ROOT / "tests", ROOT / "docs")
    removed_ip_path = "rtl/ip/" + "ribp"
    removed_filelist_path = "/ip/" + "ribp"
    removed_lock_path = "config/" + "dependencies.lock.json"
    for search_root in roots:
        for path in search_root.rglob("*"):
            if path == Path(__file__):
                continue
            if not path.is_file() or path.suffix not in {".fl", ".mk", ".json", ".md", ".py"}:
                continue
            text = path.read_text(encoding="utf-8")
            assert removed_ip_path not in text
            assert removed_filelist_path not in text
            assert removed_lock_path not in text
