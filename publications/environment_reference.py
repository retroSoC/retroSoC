"""Publication facts for the repository's supported development environment."""
from __future__ import annotations

import json
from pathlib import Path
import re

ENVIRONMENT_SOURCES = (
    "dependencies/dependencies.lock.json", "docker/Dockerfile", "flake.nix",
    "scripts/development_environment.py", "docs/development-environment.md",
    ".github/workflows/development-environment.yml", "docs/engineering.md",
)


def development_environment(root: Path) -> dict:
    lock = json.loads((root / ENVIRONMENT_SOURCES[0]).read_text(encoding="utf-8"))
    docker = (root / "docker/Dockerfile").read_text(encoding="utf-8")
    nix = (root / "flake.nix").read_text(encoding="utf-8")
    workflow = (root / ".github/workflows/development-environment.yml").read_text(encoding="utf-8")
    python = re.findall(r"\bpython(\d)(\d+)Full\b", nix)
    java_nix = re.findall(r"\bjdk(\d+)_headless\b", nix)
    java_docker = re.findall(r"\bopenjdk-(\d+)-jre-headless\b", docker)
    system = re.findall(r'\bsystem\s*=\s*"([^"]+)";', nix)
    ubuntu = re.findall(r'base\.name="ubuntu:([\d.]+)"', docker)
    if (len(python) != 1 or len(java_nix) != 1 or java_nix != java_docker
            or system != ["x86_64-linux"] or ubuntu != ["22.04"]):
        raise ValueError("review the published development environment runtime/platform contract")
    if any("scripts/development_environment.py" not in text for text in (docker, nix)):
        raise ValueError("development entrypoints no longer share the documented bootstrap")
    if "--behavioral-only" not in workflow:
        raise ValueError("review the environment workflow's published runtime evidence boundary")
    return {
        "platform": "Linux x86_64", "ubuntu": ubuntu[0],
        "python": ".".join(python[0]), "java": java_nix[0],
        "sbt": lock["toolchains"]["ubuntu-22.04"]["sbt"]["version"],
        "sources": list(ENVIRONMENT_SOURCES),
    }
