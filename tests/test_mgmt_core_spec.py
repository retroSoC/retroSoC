"""Keep the boot display aligned with the fixed Hazard3 management-core integration."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BOOTER = ROOT / "crt/src/service/booter.c"
SOFTWARE_MAKE = ROOT / "rtl/mini/mk/software.mk"
MGMT_CORE = ROOT / "rtl/mini/top/mgmt_core_wrapper.sv"
MGMT_DEBUG = ROOT / "rtl/mini/top/mgmt_debug_wrapper.sv"
AHBL_TO_AXI4 = ROOT / "rtl/mini/top/ahbl2axi4.sv"


def test_booter_prints_the_fixed_hazard3_specification() -> None:
    booter = BOOTER.read_text(encoding="utf-8")
    software_make = SOFTWARE_MAKE.read_text(encoding="utf-8")
    management_core = MGMT_CORE.read_text(encoding="utf-8")
    management_debug = MGMT_DEBUG.read_text(encoding="utf-8")
    ahbl_to_axi4 = AHBL_TO_AXI4.read_text(encoding="utf-8")

    assert "DEF_VAL += -DRS_SOC_MGMT_JTAG_IDCODE=0x$(JTAG_IDCODE)U" in software_make
    assert "Management-Core Specification:" in booter
    assert "Management Processor:" not in booter
    assert "User Processors:" in booter
    assert "Core: Hazard3(single hart), 3-stage pipeline" in booter
    assert "Base: RV32IMAC_Zicsr" in booter
    assert "Bit manipulation: Zba_Zbb_Zbc_Zbkb_Zbkx_Zbs" in booter
    assert "Other: Zifencei_Zilsd_Xh3BextM_Xh3IRQ" in booter
    assert "Not present: U-mode PMP Zcb_Zclsd_Zcmp_Xh3PMPM_Xh3Power" in booter
    assert "IRQ: 30 external + software + timer; Xh3IRQ, 4 priority levels" in booter
    assert "AHB5 manager -> AHB-Lite/AXI4 fabric" in booter
    assert "Single-beat access; no burst or exclusive transactions" in booter
    assert "RS_SOC_MGMT_JTAG_IDCODE" in booter
    assert "RISC-V JTAG DTM/DM, IDCODE 0x%08x" in booter
    assert "One hart: halt/resume, 2 breakpoints; no system-bus access" in booter
    assert "AHB-Lite NSEQ subset" not in booter
    assert "external cache/coherency handshake" not in booter
    assert "TCK/TMS/TDI/TRST_n/TDO" not in booter
    assert "instruction injection" not in booter
    assert "exact execute-address hardware breakpoints" not in booter

    for parameter in (
        ".EXTENSION_A        (1)",
        ".EXTENSION_C        (1)",
        ".EXTENSION_M        (1)",
        ".EXTENSION_ZBA      (1)",
        ".EXTENSION_ZBB      (1)",
        ".EXTENSION_ZBC      (1)",
        ".EXTENSION_ZBKB     (1)",
        ".EXTENSION_ZBKX     (1)",
        ".EXTENSION_ZBS      (1)",
        ".EXTENSION_ZIFENCEI (1)",
        ".EXTENSION_ZILSD    (1)",
        ".EXTENSION_XH3BEXTM (1)",
        ".EXTENSION_XH3IRQ   (1)",
        ".U_MODE             (0)",
        ".PMP_REGIONS        (0)",
        ".BREAKPOINT_TRIGGERS(2)",
        ".NUM_IRQS           (30)",
        ".IRQ_PRIORITY_BITS  (2)",
    ):
        assert parameter in management_core

    assert ".HAVE_SBA(0)" in management_debug
    assert "ahbl.htrans == AHBL_TRANS_NSEQ" in ahbl_to_axi4
    assert "axi4.awlen    = 8'd0;" in ahbl_to_axi4
    assert "axi4.arlen    = 8'd0;" in ahbl_to_axi4
    assert "axi4.awlock   = `AXI4_LOCK_NORM;" in ahbl_to_axi4
    assert "axi4.arlock   = `AXI4_LOCK_NORM;" in ahbl_to_axi4
