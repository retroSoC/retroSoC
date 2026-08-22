"""Tests for optional simulator backend wiring and filelist translation."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
FILELIST_SCRIPT = ROOT / "rtl/mini/script/gen_sim_filelist.py"


def run_filelist(tmp_path: Path, simulator: str) -> str:
    tmp_path.mkdir(parents=True, exist_ok=True)
    source = tmp_path / "design.sv"
    include = tmp_path / "include"
    include.mkdir()
    source.write_text("module top; endmodule\n", encoding="utf-8")
    base = tmp_path / "base.fl"
    base.write_text(
        "# comment\n+define+FEATURE=1\n+incdir+"
        + str(include)
        + "\n"
        + str(source)
        + "\n",
        encoding="utf-8",
    )
    output = tmp_path / f"{simulator}.fl"
    result = subprocess.run(
        [
            sys.executable,
            str(FILELIST_SCRIPT),
            "--format",
            simulator,
            "--filelist",
            str(base),
            "--define",
            "+define+EXTRA=1",
            "--exclude-pattern",
            "does-not-match",
            "--output",
            str(output),
        ],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    assert result.returncode == 0, result.stderr
    return output.read_text(encoding="utf-8")


def test_simulator_filelist_formats_are_tool_specific(tmp_path: Path) -> None:
    xezim = run_filelist(tmp_path / "xezim", "xezim")
    cvc = run_filelist(tmp_path / "cvc", "cvc")

    assert "-DFEATURE=1" in xezim
    assert "-DEXTRA=1" in xezim
    assert f"-I{(tmp_path / 'xezim/include').resolve()}" in xezim
    assert "+define+FEATURE=1" in cvc
    assert "+incdir+" in cvc
    assert "# comment" not in xezim
    assert "design.sv" in cvc


def test_optional_simulators_do_not_replace_default_backend() -> None:
    makefile = (ROOT / "Makefile").read_text(encoding="utf-8")
    mini_makefile = (ROOT / "rtl/mini/Makefile").read_text(encoding="utf-8")
    cvc_makefile = (ROOT / "rtl/mini/mk/cvc.mk").read_text(encoding="utf-8")

    assert "SIMU         ?= VCS" in makefile
    assert "VALID_SIMU          := VCS VERILATOR IVERILOG XEZIM CVC" in makefile
    assert "include $(RTL_PATH)/mk/xezim.mk" in mini_makefile
    assert "include $(RTL_PATH)/mk/cvc.mk" in mini_makefile
    assert "CVC_TIMING_OPTS ?= +nospecify +notimingchecks" in cvc_makefile
    assert "-- $(CVC) -q -Ogate $(CVC_TIMING_OPTS) -o simv" in cvc_makefile
    assert "-- ./simv +sim_timeout=$(RTL_SIM_TIMEOUT)" in cvc_makefile
    assert cvc_makefile.count("$(CVC_TIMING_OPTS)") == 1
