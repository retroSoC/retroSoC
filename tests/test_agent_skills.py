from __future__ import annotations

import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SKILLS_ROOT = ROOT / ".agents/skills"
EXPECTED_SKILLS = {
    "retrosoc-mini-feature-design",
    "retrosoc-mini-feature-implementation",
    "retrosoc-mini-feature-review",
}


def load_skill(path: Path) -> tuple[dict[str, object], str]:
    text = path.read_text(encoding="utf-8")
    assert text.startswith("---\n")
    _, frontmatter, body = text.split("---", 2)
    metadata: dict[str, object] = {}
    for line in frontmatter.splitlines():
        if not line.strip():
            continue
        key, separator, value = line.partition(":")
        assert separator and key in {"name", "description"}
        metadata[key] = value.strip()
    assert set(metadata) == {"name", "description"}
    return metadata, body


def test_repository_has_exact_feature_skill_set() -> None:
    directories = {path.name for path in SKILLS_ROOT.iterdir() if path.is_dir()}
    assert directories == EXPECTED_SKILLS


def test_skill_metadata_and_local_references_are_valid() -> None:
    names: list[str] = []
    for directory in sorted(SKILLS_ROOT.iterdir()):
        metadata, body = load_skill(directory / "SKILL.md")
        assert metadata["name"] == directory.name
        description = metadata["description"]
        assert isinstance(description, str)
        assert "retroSoC Mini" in description
        assert 100 <= len(description) <= 800
        assert len(body.splitlines()) < 500
        names.append(str(metadata["name"]))

        for target in re.findall(r"\[[^]]+\]\((references/[^)]+)\)", body):
            assert (directory / target).is_file(), target

    assert len(names) == len(set(names))


def test_openai_metadata_exposes_each_skill() -> None:
    for directory in sorted(SKILLS_ROOT.iterdir()):
        document = (directory / "agents/openai.yaml").read_text(encoding="utf-8")
        assert document.startswith("interface:\n")
        assert '  display_name: "retroSoC Mini' in document
        assert "  short_description:" in document
        assert directory.name in document
        assert "Feature slug:" in document
        assert "Stage:" in document or "Mode:" in document
        assert "\npolicy:\n  allow_implicit_invocation: true\n" in document


def test_skill_eval_corpora_are_complete() -> None:
    for directory in sorted(SKILLS_ROOT.iterdir()):
        document = json.loads((directory / "evals/evals.json").read_text(encoding="utf-8"))
        assert document["skill_name"] == directory.name
        evals = document["evals"]
        assert len(evals) >= 5
        assert len({item["id"] for item in evals}) == len(evals)
        for item in evals:
            assert set(item) == {"id", "prompt", "expected_output", "files"}
            assert isinstance(item["id"], int)
            assert len(item["prompt"]) >= 40
            assert len(item["expected_output"]) >= 40
            assert item["files"] == []
        assert any(
            marker in item["expected_output"].lower()
            for item in evals
            for marker in ("refusal", "blocked", "refuses", "conflict")
        )
        assert any(len(item["prompt"]) <= 120 for item in evals)


def test_skills_define_manual_input_and_constraint_contracts() -> None:
    for directory in sorted(SKILLS_ROOT.iterdir()):
        body = (directory / "SKILL.md").read_text(encoding="utf-8")
        assert "## Resolve inputs" in body
        assert "## Additional constraints" in body
        assert "explicit fields in the current prompt" in body
        for marker in ("`MUST`", "`MUST NOT`", "`PREFER`", "`DEFER`", "`ACCEPTANCE`"):
            assert marker in body


def test_spec_template_requires_stable_phase_contract() -> None:
    template = (
        SKILLS_ROOT
        / "retrosoc-mini-feature-design/references/ip-spec-template.md"
    ).read_text(encoding="utf-8")
    assert "`Phase N - Title`" in template
    assert "Do not rename, renumber, or reuse a phase" in template


def test_english_prompt_handbook_is_linked_and_manual_only() -> None:
    guide = (ROOT / ".agents/README.md").read_text(encoding="utf-8")
    handbook_path = ROOT / ".agents/feature-development-prompts.md"
    assert "[Manual Feature Development Prompts](feature-development-prompts.md)" in guide
    handbook = handbook_path.read_text(encoding="utf-8")
    for marker in (
        "Stage: research",
        "Stage: freeze",
        "Stage: preflight",
        "Stage: implement",
        "Mode: diagnose",
        "Mode: review",
        "Mode: finalize",
        "--netsim-boot-only",
    ):
        assert marker in handbook
    for forbidden in ("codex-action", "OPENAI_API_KEY", "workflow_dispatch"):
        assert forbidden not in handbook
    assert "running the review skill in ChatGPT Work" in handbook
    assert "`$retrosoc-mini-feature-review`" in handbook
    assert "`@retrosoc-mini-feature-review`" in handbook
    assert "`MERGE` remains a human action" in handbook


def test_agent_directory_guide_mentions_all_skills_and_full_flow() -> None:
    guide = (ROOT / ".agents/README.md").read_text(encoding="utf-8")
    for name in EXPECTED_SKILLS:
        assert name in guide
    assert "--suite pr --pdk IHP130 --netsim-boot-only" in guide
    assert "behavioral-only" in guide
    assert "Every Work and Codex stage is started manually" in guide
    assert "post review comments" in guide
