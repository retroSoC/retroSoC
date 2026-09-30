from __future__ import annotations

import json
import re
import shlex
from pathlib import Path
from urllib.parse import unquote, urlsplit


ROOT = Path(__file__).resolve().parents[1]
AGENTS_ROOT = ROOT / ".agents"
SKILLS_ROOT = AGENTS_ROOT / "skills"
FEATURE_SKILLS = {
    "retrosoc-feature-design",
    "retrosoc-feature-implementation",
    "retrosoc-feature-review",
}
ENGINEERING_SKILLS = {
    "retrosoc-datasheet",
    "retrosoc-dependency-maintenance",
    "retrosoc-physical-flow",
}
EXPECTED_SKILLS = FEATURE_SKILLS | ENGINEERING_SKILLS
ENGINEERING_DEFAULTS = {
    "retrosoc-datasheet": ("inspect", {"Target SoCs"}),
    "retrosoc-dependency-maintenance": ("inspect", {"Scope"}),
    "retrosoc-physical-flow": ("preflight", {"Target SoCs", "Profile", "Flow", "Stage"}),
}
HANDBOOKS = ("feature-development-prompts.md", "engineering-workflow-prompts.md")


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


def test_repository_has_feature_and_engineering_skills() -> None:
    assert FEATURE_SKILLS.isdisjoint(ENGINEERING_SKILLS)
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
        short = re.search(r'^  short_description: "([^\"]+)"', document, re.MULTILINE)
        assert short is not None and 25 <= len(short.group(1)) <= 64
        prompt = re.search(r'^  default_prompt: "([^\"]+)"', document, re.MULTILINE)
        assert prompt is not None
        assert f"${directory.name}" in prompt.group(1)
        if directory.name in FEATURE_SKILLS:
            assert "Target SoCs:" in prompt.group(1)
            assert "Feature slug:" in prompt.group(1)
            assert "Stage:" in prompt.group(1) or "Mode:" in prompt.group(1)
        else:
            mode, fields = ENGINEERING_DEFAULTS[directory.name]
            assert re.search(rf"\bMode:\s*{mode}\b", prompt.group(1))
            for field in fields:
                assert f"{field}:" in prompt.group(1), (directory, field)
            assert "Feature slug:" not in prompt.group(1)
            assert "Phase:" not in prompt.group(1)
        assert re.search(r"^  allow_implicit_invocation: true$", document, re.MULTILINE)


def test_eval_corpora_have_valid_cases_and_fixtures() -> None:
    for directory in skill_directories():
        document = json.loads((directory / "evals/evals.json").read_text(encoding="utf-8"))
        assert document["skill_name"] == directory.name
        evals = document["evals"]
        assert isinstance(evals, list)
        assert len(evals) >= (6 if directory.name in ENGINEERING_SKILLS else 2)
        identifiers: set[int] = set()
        prompts: set[str] = set()
        for case in evals:
            assert set(case) == {"id", "prompt", "expected_output", "files"}
            assert type(case["id"]) is int and case["id"] > 0
            assert case["id"] not in identifiers
            identifiers.add(case["id"])
            for field in ("prompt", "expected_output"):
                assert isinstance(case[field], str) and case[field].strip()
            assert case["prompt"] not in prompts
            prompts.add(case["prompt"])
            assert isinstance(case["files"], list)
            for relative in case["files"]:
                assert isinstance(relative, str) and relative.strip()
                fixture = (directory / "evals" / relative).resolve()
                assert fixture.is_relative_to(ROOT) and fixture.is_file()
        assert any(len(case["prompt"]) <= 120 for case in evals)


def test_skill_mentions_and_guide_links_resolve() -> None:
    sources = [path for path in AGENTS_ROOT.rglob("*") if path.suffix in {".md", ".yaml"}]
    sources.extend((ROOT / "docs").rglob("*.md"))
    for source in sources:
        text = source.read_text(encoding="utf-8")
        for name in re.findall(r"[$@](retrosoc-[a-z0-9-]+)", text):
            assert (SKILLS_ROOT / name / "SKILL.md").is_file(), (source, name)

    guide = (AGENTS_ROOT / "README.md").read_text(encoding="utf-8")
    for handbook in HANDBOOKS:
        assert (AGENTS_ROOT / handbook).is_file()
        assert f"({handbook})" in guide
    for name in EXPECTED_SKILLS:
        assert f"(skills/{name}/SKILL.md)" in guide


def test_documented_profiles_exist() -> None:
    profiles: set[str] = set()
    for source in AGENTS_ROOT.rglob("*.md"):
        profiles.update(re.findall(r"configs/[a-zA-Z0-9_./-]+\.mk", source.read_text("utf-8")))
    assert profiles
    for profile in profiles:
        assert (ROOT / profile).is_file(), profile


def test_engineering_handbook_covers_each_public_mode() -> None:
    handbook = (AGENTS_ROOT / HANDBOOKS[1]).read_text(encoding="utf-8")
    prompts = re.findall(r"```text\n(.*?)```", handbook, re.DOTALL)
    expected_modes = {
        "retrosoc-datasheet": {"inspect", "update", "validate"},
        "retrosoc-dependency-maintenance": {"inspect", "restore", "upgrade"},
        "retrosoc-physical-flow": {"preflight", "run", "resume", "summarize"},
    }
    for name, modes in expected_modes.items():
        found: set[str] = set()
        for prompt in prompts:
            if f"${name}" not in prompt:
                continue
            # Both field-based prompts and direct English actions are public examples.
            for mode in modes:
                if re.search(rf"(?:Mode:\s*|\${name}\s+){mode}\b", prompt, re.IGNORECASE):
                    found.add(mode)
        assert found == modes, (name, found)


def test_shared_engineering_references_are_reachable() -> None:
    implementation = SKILLS_ROOT / "retrosoc-feature-implementation"
    review = (SKILLS_ROOT / "retrosoc-feature-review/SKILL.md").read_text("utf-8")
    entrypoint = (implementation / "SKILL.md").read_text("utf-8")
    for name in ("regression.md", "rtl-migration.md"):
        assert (implementation / "references" / name).is_file()
        assert f"(references/{name})" in entrypoint
        assert f"(../retrosoc-feature-implementation/references/{name})" in review


def test_engineering_command_examples_use_existing_entrypoints() -> None:
    sources = [AGENTS_ROOT / HANDBOOKS[1]]
    for name in ENGINEERING_SKILLS | {"retrosoc-feature-implementation"}:
        sources.extend((SKILLS_ROOT / name / "references").glob("*.md"))
    makefiles = [
        ROOT / "Makefile",
        ROOT / "physical/librelane/mini/Makefile",
        ROOT / "physical/librelane/tiny/Makefile",
        ROOT / "physical/ecc/Makefile",
    ]
    recipes = "\n".join(path.read_text("utf-8") for path in makefiles)
    checked = 0
    for source in sources:
        for block in re.findall(r"```sh\n(.*?)```", source.read_text("utf-8"), re.DOTALL):
            for line in block.replace("\\\n", " ").splitlines():
                parts = shlex.split(line, comments=True)
                if len(parts) < 2:
                    continue
                if parts[0] in {"python", "python3"} and parts[1].endswith(".py"):
                    entrypoint = (ROOT / parts[1]).resolve()
                    assert entrypoint.is_relative_to(ROOT) and entrypoint.is_file(), (source, line)
                    checked += 1
                elif parts[0] == "make":
                    # These examples use root Make and explicit assignments, not -C or -f.
                    targets = [part for part in parts[1:] if "=" not in part]
                    assert targets and all(not part.startswith("-") for part in targets)
                    for target in targets:
                        assert re.search(rf"^{re.escape(target)}\s*:", recipes, re.MULTILINE), (
                            source,
                            target,
                        )
                    checked += 1
    assert checked > 0
