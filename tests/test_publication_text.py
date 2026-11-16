"""A non-UTF-8 host locale must not corrupt scientific symbols in source text."""
import json
from pathlib import Path

from publications import chapter_reference


def test_feature_json_is_utf8_even_when_host_default_is_gbk(tmp_path, monkeypatch):
    root = tmp_path / "publications/datasheets"
    root.mkdir(parents=True)
    (root / "ip-content.json").write_text(json.dumps({"jpeg": {"register_family": "jpeg"}}), encoding="utf-8")
    (root / "features.json").write_text(json.dumps({"jpeg": ["Images up to 2048 × 2048"]},
                                                 ensure_ascii=False), encoding="utf-8")
    original = Path.read_text

    def local_read(path, encoding=None, errors=None):
        return original(path, encoding=encoding or "gbk", errors=errors)

    monkeypatch.setattr(chapter_reference, "ROOT", tmp_path)
    monkeypatch.setattr(Path, "read_text", local_read)
    assert chapter_reference.collect_chapters({})["jpeg"]["features"] == ["Images up to 2048 × 2048"]
