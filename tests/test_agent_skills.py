from __future__ import annotations

import json
import re
from pathlib import Path
from urllib.parse import unquote, urlsplit


ROOT = Path(__file__).resolve().parents[1]
AGENTS_ROOT = ROOT / ".agents"
SKILLS_ROOT = AGENTS_ROOT / "skills"
EXPECTED_SKILLS = {
    "retrosoc-feature-design",
    "retrosoc-feature-implementation",
    "retrosoc-feature-review",
}


def skill_directories() -> list[Path]:
    return sorted(path.parent for path in SKILLS_ROOT.glob("*/SKILL.md"))


def load_skill(path: Path) -> tuple[dict[str, str], str]:
    # These entrypoints use single-line name/description fields. The skill
    # creator's quick_validate.py additionally validates the full YAML format.
    text = path.read_text(encoding="utf-8")
    assert text.startswith("---\n")
    frontmatter, separator, body = text[4:].partition("\n---\n")
    assert separator
    metadata: dict[str, str] = {}
    for line in frontmatter.splitlines():
        if not line.strip():
            continue
        key, separator, value = line.partition(":")
        assert separator and key in {"name", "description"}
        assert key not in metadata, f"duplicate field: {path}: {key}"
        metadata[key] = value.strip()
    assert set(metadata) == {"name", "description"}
    return metadata, body


def test_repository_has_three_general_feature_skills() -> None:
    assert {path.name for path in skill_directories()} == EXPECTED_SKILLS


def test_skill_metadata_is_discoverable() -> None:
    names: list[str] = []
    for directory in skill_directories():
        metadata, body = load_skill(directory / "SKILL.md")
        assert metadata["name"] == directory.name
        assert re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", metadata["name"])
        assert len(metadata["name"]) < 64
        description = metadata["description"]
        assert "retroSoC" in description
        assert 0 < len(description) <= 1024
        assert body.strip() and len(body.splitlines()) < 500
        names.append(metadata["name"])
    assert len(names) == len(set(names))


def test_local_markdown_links_resolve() -> None:
    for source in AGENTS_ROOT.rglob("*.md"):
        body = source.read_text(encoding="utf-8")
        for target in re.findall(r"\[[^\]\n]+\]\(([^)\n]+)\)", body):
            target = target.strip().strip("<>")
            parsed = urlsplit(target)
            if parsed.scheme or not parsed.path:
                continue
            destination = (source.parent / unquote(parsed.path)).resolve()
            assert destination.is_relative_to(ROOT), (source, target)
            assert destination.is_file(), (source, target)


def test_openai_metadata_routes_to_the_registered_skill() -> None:
    for directory in skill_directories():
        document = (directory / "agents/openai.yaml").read_text(encoding="utf-8")
        assert document.startswith("interface:\n")
        for field in ("display_name", "short_description", "default_prompt"):
            assert re.search(rf'^  {field}: "[^\"]+', document, re.MULTILINE)
        prompt = re.search(r'^  default_prompt: "([^\"]+)"', document, re.MULTILINE)
        assert prompt is not None
        assert f"${directory.name}" in prompt.group(1)
        assert "Target SoCs:" in prompt.group(1)
        assert "Feature slug:" in prompt.group(1)
        assert "Stage:" in prompt.group(1) or "Mode:" in prompt.group(1)
        assert re.search(r"^  allow_implicit_invocation: true$", document, re.MULTILINE)


def test_eval_corpora_remain_valid_after_renaming() -> None:
    for directory in skill_directories():
        document = json.loads((directory / "evals/evals.json").read_text(encoding="utf-8"))
        assert document["skill_name"] == directory.name
        evals = document["evals"]
        assert evals
        identifiers: set[int] = set()
        for case in evals:
            assert set(case) == {"id", "prompt", "expected_output", "files"}
            assert type(case["id"]) is int and case["id"] not in identifiers
            identifiers.add(case["id"])
            for field in ("prompt", "expected_output"):
                assert isinstance(case[field], str) and case[field].strip()
            assert isinstance(case["files"], list)
            for relative in case["files"]:
                fixture = (directory / "evals" / relative).resolve()
                assert fixture.is_relative_to(ROOT) and fixture.is_file()
        assert any(len(case["prompt"]) <= 120 for case in evals)


def test_skill_mentions_and_guide_links_survive_migration() -> None:
    sources = [path for path in AGENTS_ROOT.rglob("*") if path.suffix in {".md", ".yaml"}]
    sources.extend((ROOT / "docs").rglob("*.md"))
    for source in sources:
        text = source.read_text(encoding="utf-8")
        for name in re.findall(r"[$@](retrosoc-[a-z0-9-]+)", text):
            assert (SKILLS_ROOT / name / "SKILL.md").is_file(), (source, name)

    guide = (AGENTS_ROOT / "README.md").read_text(encoding="utf-8")
    assert "(feature-development-prompts.md)" in guide
    for name in EXPECTED_SKILLS:
        assert f"(skills/{name}/SKILL.md)" in guide


def test_documented_profiles_exist() -> None:
    handbook = (AGENTS_ROOT / "feature-development-prompts.md").read_text(encoding="utf-8")
    profiles = set(re.findall(r"configs/[a-zA-Z0-9_./-]+\.mk", handbook))
    assert profiles
    for profile in profiles:
        assert (ROOT / profile).is_file(), profile
