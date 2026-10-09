"""Tests for the padless ICS55 ECC hardening adapter."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
from types import SimpleNamespace

try:
    import tomllib
except ModuleNotFoundError:
    import tomli as tomllib


ROOT = Path(__file__).resolve().parents[1]
ECC_ROOT = ROOT / "physical/ecc"


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def write_pdk(root: Path) -> None:
    tech = root / "prtech/techLEF/N551P6M_ecos.lef"
    lef = root / "IP/STD_cell/ics55_LLSC_H7C_V1p10C100/ics55_LLSC_H7CR/lef/ics55_LLSC_H7CR_ecos.lef"
    tech.parent.mkdir(parents=True)
    lef.parent.mkdir(parents=True)
    tech.write_text("VERSION 5.8 ;\n", encoding="utf-8")
    lef.write_text("VERSION 5.8 ;\n", encoding="utf-8")


def write_sdc(path: Path) -> None:
    path.write_text(
        "\n".join(
            [
                f"create_clock -name {name} -period 10 [get_ports clk]"
                for name in (
                    "clk_external",
                    "clk_system",
                    "clk_audio",
                    "clk_jtag",
                    "clk_dvp",
                    "clk_usb2_ulpi",
                )
            ]
            + ["set_clock_groups -name retrosoc_async -asynchronous"]
        )
        + "\n",
        encoding="utf-8",
    )


def test_ecc_config_is_padless_and_uses_the_full_clock_inventory(tmp_path: Path) -> None:
    module = load_module("retrosoc_ecc_config", ECC_ROOT / "scripts/generate_config.py")
    pdk = tmp_path / "pdk"
    write_pdk(pdk)
    rtl = tmp_path / "input/retrosoc_asic_sources.sv"
    rtl.parent.mkdir()
    rtl.write_text("module retrosoc_core; endmodule\n", encoding="utf-8")
    sdc = tmp_path / "input/retrosoc_core.sdc"
    write_sdc(sdc)
    liberty = tmp_path / "cache/ics55_h7cr_ss.lib"
    liberty.parent.mkdir()
    liberty.write_text("library (h7cr) {}\n", encoding="utf-8")
    output = tmp_path / "project/ecc.toml"
    args = SimpleNamespace(
        rtl=rtl,
        sdc=sdc,
        pdk_root=pdk,
        h7cr_liberty=liberty,
        ext_clk_hz=72_000_000,
        output=output,
    )

    config = module.render(args)
    output.parent.mkdir()
    output.write_text(config, encoding="utf-8")
    document = tomllib.loads(config)

    assert document["design"]["name"] == "retrosoc_core"
    assert document["design"]["top"] == "retrosoc_core"
    assert document["design"]["clock_port"] == "extclk_i_pad"
    assert document["design"]["frequency_mhz"] == 72.0
    assert document["pdk"]["name"] == "ics55"
    assert document["flow"]["preset"] == "harden"
    assert document["params"]["floorplan"]["core_util"] == 0.60
    assert document["params"]["place"]["target_density"] == 0.55
    overrides = document["pdk"]["overrides"]
    assert len(overrides["lefs"]) == 1
    assert "H7CR" in overrides["lefs"][0]
    assert len(overrides["libs"]) == 1
    assert "h7cr" in overrides["libs"][0].lower()
    assert "IO" not in " ".join(overrides["lefs"] + overrides["libs"])
    assert "PAD" not in config
    assert "bondpad" not in config


def test_ecc_doctor_rejects_single_clock_or_pad_collateral(tmp_path: Path) -> None:
    module = load_module("retrosoc_ecc_doctor", ECC_ROOT / "scripts/doctor.py")
    sdc = tmp_path / "retrosoc_core.sdc"
    write_sdc(sdc)
    config = {
        "design": {
            "name": "retrosoc_core",
            "top": "retrosoc_core",
            "clock_port": "extclk_i_pad",
        },
        "pdk": {
            "name": "ics55",
            "overrides": {
                "tech": "prtech/techLEF/N551P6M_ecos.lef",
                "lefs": ["IP/STD_cell/H7CR/lef/ics55_LLSC_H7CR_ecos.lef"],
                "libs": ["cache/ics55_h7cr_ss.lib"],
                "sdc": "retrosoc_core.sdc",
                "site_core": "core7",
                "tap_cell": "FILLTAPH7R",
                "end_cap": "FILLTAPH7R",
                "fillers": ["FILLER1H7R"],
            },
        },
        "flow": {"preset": "harden"},
    }

    errors, details = module.validate_config(config, sdc)
    assert not errors
    assert details["top"] == "retrosoc_core"
    config["pdk"]["overrides"]["lefs"] = ["IP/IO/ics55_pad.lef"]
    errors, _ = module.validate_config(config, sdc)
    assert any("exactly one H7CR" in error for error in errors)
    assert any("IO, PAD, or bondpad" in error for error in errors)


def test_ecc_flow_is_on_demand_with_upstream_installation() -> None:
    makefile = (ECC_ROOT / "Makefile").read_text(encoding="utf-8")
    root_makefile = (ROOT / "Makefile").read_text(encoding="utf-8")
    lock = json.loads((ROOT / "dependencies/dependencies.lock.json").read_text(encoding="utf-8"))

    assert "ecc-core:" in makefile
    assert "ecc-package:" in makefile
    assert "ecc-all" not in makefile
    assert "--librelane-safe" in makefile
    assert "include physical/ecc/Makefile" in root_makefile
    assert "ecc-core" not in (ROOT / "scripts/regress.py").read_text(encoding="utf-8")
    assert "ecc_cli_linux_x86_64" not in lock["archives"]
    assert "ecc-input: ecc-setup" not in makefile
    assert "ecc-doctor: ecc-setup" not in makefile


def test_ecc_binary_uses_upstream_home_and_xdg_defaults(tmp_path, monkeypatch):
    module = load_module("retrosoc_ecc_setup", ECC_ROOT / "scripts/setup.py")
    monkeypatch.setenv("HOME", str(tmp_path))
    monkeypatch.delenv("XDG_BIN_HOME", raising=False)
    assert module.default_binary() == tmp_path / ".local/bin/ecc"
    monkeypatch.setenv("XDG_BIN_HOME", "")
    assert module.default_binary() == tmp_path / ".local/bin/ecc"
    monkeypatch.setenv("XDG_BIN_HOME", str(tmp_path / "custom bin"))
    assert module.default_binary() == tmp_path / "custom bin/ecc"


def test_ecc_setup_always_streams_installer_and_checks_runtime(tmp_path, monkeypatch):
    import subprocess

    module = load_module("retrosoc_ecc_setup", ECC_ROOT / "scripts/setup.py")
    monkeypatch.setenv("XDG_BIN_HOME", str(tmp_path))
    binary = tmp_path / "ecc"
    binary.write_text("#!/bin/sh\n")
    binary.chmod(0o755)
    calls = []

    def run(command, **kwargs):
        assert kwargs["check"]
        assert "env" not in kwargs  # Upstream owns directory and toolchain selection.
        calls.append(command)
        return subprocess.CompletedProcess(command, 0, stdout='{"version":"test"}')

    monkeypatch.setattr(module.subprocess, "run", run)
    for _ in range(2):
        assert module.install() == binary
    expected = [
        "bash",
        "-o",
        "pipefail",
        "-c",
        "curl -fsSL http://release.openecos.com/installers/ecc/latest/ecc-installer.sh"
        " | sh -s -- --with-toolchain",
    ]
    assert calls == [expected, [str(binary), "--version"], [str(binary), "version", "--json"]] * 2
    assert list(tmp_path.iterdir()) == [binary]


def test_ecc_pipeline_propagates_curl_and_installer_failures(tmp_path, monkeypatch):
    import os
    import subprocess
    import pytest

    module = load_module("retrosoc_ecc_setup", ECC_ROOT / "scripts/setup.py")
    tools = tmp_path / "bin"
    tools.mkdir()
    monkeypatch.setenv("PATH", str(tools) + ":" + os.environ["PATH"])
    monkeypatch.setenv("XDG_BIN_HOME", str(tmp_path / "installed"))
    curl = tools / "curl"
    curl.write_text("#!/bin/sh\nexit 22\n")
    curl.chmod(0o755)
    with pytest.raises(subprocess.CalledProcessError) as error:
        module.install()
    assert error.value.returncode == 22  # Empty sh succeeds, but pipefail catches curl.
    curl.write_text("#!/bin/sh\nprintf 'exit 7\\n'\n")
    with pytest.raises(subprocess.CalledProcessError) as error:
        module.install()
    assert error.value.returncode == 7
    assert not (tmp_path / "installed").exists()


def test_ecc_setup_is_profile_independent_and_honors_binary_override(tmp_path):
    import subprocess

    result = subprocess.run(
        ["make", "-n", "ecc-setup"], cwd=ROOT, text=True, capture_output=True, check=True
    )
    assert "physical/ecc/scripts/setup.py" in result.stdout
    assert "physical/pdk/setup.py" not in result.stdout
    assert "requires PDK" not in result.stdout
    binary = tmp_path / "ecc"
    binary.touch()
    result = subprocess.run(
        ["make", "-n", f"ECC_BIN={binary}", str(binary)],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=True,
    )
    assert "setup.py" not in result.stdout


def test_ecc_doctor_works_without_cli_lock_or_fixed_version(tmp_path, monkeypatch):
    import sys

    module = load_module("retrosoc_ecc_doctor", ECC_ROOT / "scripts/doctor.py")
    project = tmp_path / "project"
    project.mkdir()
    (project / "ecc.toml").write_text("")
    pdk = tmp_path / "pdk"
    write_pdk(pdk)
    (pdk / ".git").mkdir()
    binary = tmp_path / "ecc"
    binary.touch()
    binary.chmod(0o755)
    output = tmp_path / "doctor.json"
    monkeypatch.setattr(
        module,
        "load_lock",
        lambda _: {"sources": {"pdk_ics55": {"revision": "test-revision"}}, "archives": {}},
    )
    monkeypatch.setattr(module, "ecc_version", lambda *args: "ecc future-release")
    monkeypatch.setattr(module, "command_output", lambda *args: "test-revision")
    monkeypatch.setattr(module, "validate_config", lambda *args: ([], {}))
    monkeypatch.setattr(
        module.subprocess,
        "run",
        lambda *args, **kwargs: SimpleNamespace(stdout='{"status":"passed"}'),
    )
    monkeypatch.setattr(
        sys,
        "argv",
        [
            "doctor",
            "--root",
            str(tmp_path),
            "--lock",
            "unused",
            "--ecc",
            str(binary),
            "--project",
            str(project),
            "--pdk-root",
            str(pdk),
            "--sdc",
            str(tmp_path / "test.sdc"),
            "--output",
            str(output),
        ],
    )
    assert module.main() == 0
    result = json.loads(output.read_text())
    assert result["details"]["ecc_version"] == "ecc future-release"
    assert "ecc_archive_sha256" not in result["details"]
