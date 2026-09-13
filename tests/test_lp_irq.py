"""Phase 1 LP interrupt vector, metadata, and SDK backend tests."""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TOPOLOGY = ROOT / "rtl/mini/integration/soc_topology.json"
GENERATOR = ROOT / "rtl/mini/integration/generate_soc_topology.py"
MEMORY_MAP = ROOT / "rtl/mini/address_map/memory_map.json"


def generate(output_dir: Path, *, external_irq_count: int = 62) -> None:
    subprocess.run(
        [
            sys.executable,
            str(GENERATOR),
            "--map",
            str(TOPOLOGY),
            "--memory-map",
            str(MEMORY_MAP),
            "--output-dir",
            str(output_dir),
            "--external-irq-count",
            str(external_irq_count),
        ],
        check=True,
    )


def test_phase1_generates_64bit_vector_and_sdk_metadata(tmp_path: Path) -> None:
    generate(tmp_path)

    irq_config = (tmp_path / "rtl/soc_irq_config.svh").read_text(encoding="utf-8")
    irq_wiring = (tmp_path / "rtl/soc_irq_wiring.svh").read_text(encoding="utf-8")
    irq_sva = (tmp_path / "rtl/soc_irq_sva.svh").read_text(encoding="utf-8")
    metadata = (
        tmp_path / "include/retrosoc/generated/irq_metadata.h"
    ).read_text(encoding="utf-8")

    assert "`define SOC_IRQ_VECTOR_WIDTH 64" in irq_config
    assert "`define SOC_USER_IRQ_MASK 64'h00000000004EFBFC" in irq_config
    assert "s_irq[31] = s_apb4_periph_irq[23];" in irq_wiring
    assert "s_irq[32]" not in irq_wiring
    assert "irq_i[32] == 1'b0" in irq_sva
    assert "irq_i[63] == 1'b0" in irq_sva
    assert "RS_SOC_IRQ_VECTOR_WIDTH UINT32_C(64)" in metadata
    assert "RS_SOC_EXTERNAL_IRQ_COUNT UINT32_C(62)" in metadata
    assert "RS_SOC_ALLOCATED_IRQ_COUNT UINT32_C(30)" in metadata
    assert "RS_SOC_EXT_IRQ_APU UINT32_C(29)" in metadata
    assert "RS_SOC_IRQ_GA2D" not in metadata


def test_phase1_supports_32bit_compatibility_metadata(tmp_path: Path) -> None:
    generate(tmp_path, external_irq_count=30)
    metadata = (
        tmp_path / "include/retrosoc/generated/irq_metadata.h"
    ).read_text(encoding="utf-8")
    assert "RS_SOC_IRQ_VECTOR_WIDTH UINT32_C(64)" in metadata
    assert "RS_SOC_EXTERNAL_IRQ_COUNT UINT32_C(30)" in metadata


def test_csr_disabled_external_irq_api_is_a_polling_stub(tmp_path: Path) -> None:
    compiler = shutil.which("cc")
    if compiler is None:
        return

    source = tmp_path / "irq_nocsr_test.c"
    source.write_text(
        """
#include <retrosoc/core/irq.h>

static void handler(uintptr_t mcause, uintptr_t stack_pointer) {
    (void)mcause;
    (void)stack_pointer;
}

int main(void) {
    return (rs_irq_register_external(0U, handler) == RS_ENOTSUP &&
            rs_irq_enable_external(61U, handler) == RS_ENOTSUP &&
            rs_irq_disable_external(61U) == RS_ENOTSUP &&
            rs_irq_set_external_priority(61U, 3U) == RS_ENOTSUP) ? 0 : 1;
}
""",
        encoding="utf-8",
    )
    executable = tmp_path / "irq_nocsr_test"
    subprocess.run(
        [
            compiler,
            "-std=gnu11",
            "-Wall",
            "-Wextra",
            "-I",
            str(ROOT / "crt/include"),
            str(ROOT / "crt/src/core/irq_nocsr.c"),
            str(source),
            "-o",
            str(executable),
        ],
        check=True,
    )
    subprocess.run([str(executable)], check=True)


def test_phase1_wrapper_and_backend_contracts() -> None:
    wrapper = (ROOT / "rtl/mini/top/core_wrapper.sv").read_text(encoding="utf-8")
    management = (ROOT / "rtl/mini/top/mgmt_core_wrapper.sv").read_text(encoding="utf-8")
    top = (ROOT / "rtl/mini/top/retrosoc.sv").read_text(encoding="utf-8")
    handler = (ROOT / "crt/src/core/system_irq_handler.c").read_text(encoding="utf-8")
    csr = (ROOT / "crt/include/retrosoc/arch/riscv/system_csr.h").read_text(encoding="utf-8")
    firmware = (ROOT / "app/apps/ci_smoke/main.c").read_text(encoding="utf-8")

    assert "parameter int ExternalIrqCount = 30" in wrapper
    assert "parameter int ExternalIrqCount = 30" in management
    assert ".NUM_IRQS           (ExternalIrqCount)" in management
    assert ".IRQ_INPUT_BYPASS   ({ExternalIrqCount{1'b0}})" in management
    assert "localparam int ManagementExternalIrqCount = `SOC_IRQ_VECTOR_WIDTH - 2" in top
    assert ".ExternalIrqCount(ManagementExternalIrqCount)" in top
    assert "assign s_management_irq = s_irq[ManagementExternalIrqCount+1:0]" in top
    assert ".irq_i         (s_management_irq)" in top
    assert "RS_EXTERNAL_IRQ_COUNT RS_SOC_EXTERNAL_IRQ_COUNT" in handler
    assert "rs_irq_dispatch_external(mcause, stack_pointer)" in handler
    assert "CSR_HAZARD3_MEIEA         0xbe0" in csr
    assert "CSR_HAZARD3_MEINEXT       0xbe4" in csr
    assert "CSR_HAZARD3_MEICONTEXT    0xbe5" in csr
    assert "{0U, 15U, 16U, 29U, 30U, 31U, 32U, 61U}" in firmware
    assert "rs_irq_register_external(62U" in firmware
    assert "rs_irq_set_external_priority(29U, UINT8_C(0))" in firmware
    assert "rs_irq_set_external_priority(30U, UINT8_C(1))" in firmware
    assert "rs_irq_set_external_priority(31U, UINT8_C(2))" in firmware
    assert "rs_irq_set_external_priority(32U, UINT8_C(3))" in firmware
    assert "rs_irq_set_external_priority(15U, UINT8_C(3))" in firmware
    assert "rs_irq_set_external_priority(15U, UINT8_C(4))" in firmware
    assert "rs_ci_smoke_timer_irq_handler" in firmware
    assert "rs_ci_smoke_software_irq_handler" in firmware


def test_phase1_generated_irq_routing_simulates(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    if iverilog is None or vvp is None:
        return

    generate(tmp_path / "topology")
    simulation = tmp_path / "soc_irq_topology_tb"
    subprocess.run(
        [
            iverilog,
            "-g2012",
            "-I",
            str(tmp_path / "topology/rtl"),
            "-s",
            "soc_irq_topology_tb",
            "-o",
            str(simulation),
            str(ROOT / "tests/rtl/soc_irq_topology_tb.sv"),
        ],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], check=True, capture_output=True, text=True)
    assert "SoC topology IRQ routing test passed" in result.stdout
