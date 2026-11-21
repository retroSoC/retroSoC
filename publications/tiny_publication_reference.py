"""Tiny publication navigation and diagnostics, without changing the hardware ABI."""
from __future__ import annotations

import re
from pathlib import Path

from publications.structure_reference import content_text


def smartwatch_reference(gpio: list[dict], facts: dict) -> dict:
    """Resolve the example board's pin ownership and validate its alternate functions."""
    pads = {row["pin"]: row for row in gpio}
    used: dict[int, str] = {}

    def bind(pin: int, mode: str, signal: str, *, output: str | None = None, input_: str | None = None) -> str:
        name = f"GPIO{pin}"
        if pin in used or pin not in pads:
            raise ValueError(f"Tiny smartwatch: invalid or shared {name} for {signal}")
        used[pin] = signal
        if mode == "gpio":
            return f"{name} (GPIO output) {signal}"
        alt = pads[pin][mode]
        if (alt["inputs"] != ([input_] if input_ else [])
                or alt["do"] != (output or "1'b0") or (alt["oe"] != "1'b0") != (output is not None)):
            raise ValueError(f"Tiny smartwatch: {name} {mode.upper()} does not route {signal}")
        return f"{name} {mode.upper()} {signal}"

    xin_mhz = int(facts["profile"]["EXT_CLK_HZ"]) // 1_000_000
    boot_cs, ram_cs = "NSS0", "NSS1"
    reference = {
        "power": dict(
            title="Power and clock", rails="Core / I/O", clock=f"{xin_mhz} MHz",
            connections=[f"Battery → external charger / PMIC → Core and I/O rails. External {xin_mhz} MHz clock → XIN."],
        ),
        "memory": dict(
            title="XPI memory", bus="XPI", boot_cs=boot_cs, ram_cs=ram_cs,
            connections=[f"Dedicated {boot_cs} → boot NOR.",
                         f"{bind(29, 'alt0', ram_cs, output='xpi.nss_o[1]')} → optional PSRAM. Initialize explicitly before use."],
        ),
        "display": dict(
            title="LCD and backlight", bus="SPI0", pwm="PWM0",
            connections=[
                " · ".join((bind(27, "alt0", "SCK", output="s_spi_sck"),
                            bind(28, "alt1", "MOSI", output="s_spi_mosi"),
                            bind(31, "alt1", "CS_N", output="s_spi_cs_n"))),
                " · ".join((bind(30, "gpio", "D/C"), bind(25, "gpio", "panel reset"),
                            bind(18, "alt0", "PWM0", output="u_pwm_if.pwm_o[0]") + " → backlight driver.")),
            ],
        ),
        "sensing": dict(
            title="Touch and sensors", bus="I²C0",
            connections=[" · ".join((
                bind(10, "alt0", "SCL", input_="u_i2c0_if.scl_i", output="u_i2c0_if.scl_o"),
                bind(11, "alt0", "SDA", input_="u_i2c0_if.sda_i", output="u_i2c0_if.sda_o"),
            )) + " → shared bus."],
        ),
        "ble": dict(
            title="External BLE (optional)", bus="UART0",
            connections=[
                bind(8, "alt0", "TX", output="u_uart0_if.tx_o") + " → BLE RX · "
                + bind(9, "alt0", "RX", input_="u_uart0_if.rx_i") + " ← BLE TX.",
                "Use a separate configuration for the UART0 console when BLE is fitted.",
            ],
        ),
        "audio": dict(
            title="External audio (optional)", bus="I²S", ref_clock="AUDIO ref.",
            connections=[
                " · ".join((bind(12, "alt0", "SCLK", output="u_i2s_if.sclk_o"),
                            bind(13, "alt0", "LRCK", output="u_i2s_if.lrck_o"),
                            bind(14, "alt0", "DACDAT", output="u_i2s_if.dacdat_o"))),
                " · ".join((bind(15, "alt0", "ADCDAT (in)", input_="u_i2s_if.adcdat_i"),
                            bind(16, "alt0", "MCLK (out)", output="u_i2s_if.mclk_o"))),
                "Independent AUDIO clock → " + bind(17, "alt0", "AUDIO.CLKIN", input_="s_audio_pad_clk") + ".",
            ],
        ),
    }
    return dict(
        hardware_isa=facts["hardware_isa"],
        sram_kib=facts["sram"]["CapacityKiB"],
        axi_width=facts["sram"]["DataWidth"],
        dma_channels=facts["dma"]["NumChannels"],
        links=reference,
    )


def validate_navigation(contract: dict, headings: list[dict]) -> None:
    if contract.get("state") != "frozen" or contract.get("depth") != 5:
        raise ValueError("Tiny navigation must use the reviewed five-level contract")
    actual = []
    for row in headings:
        if not row.get("outlined", True) or row["level"] > 5:
            continue
        anchor = row.get("label")
        actual.append(dict(level=row["level"],
                           title=" ".join(content_text(row["title"]).split()),
                           anchor=None if anchor in (None, "none") else anchor.strip("<>")))
    if actual != contract["entries"]:
        expected = contract["entries"]
        mismatch = next((i for i, pair in enumerate(zip(actual, expected)) if pair[0] != pair[1]),
                        min(len(actual), len(expected)))
        raise ValueError("Tiny five-level navigation differs from its reviewed contract: "
                         f"entry {mismatch}, actual={actual[mismatch:mismatch + 1]}, expected={expected[mismatch:mismatch + 1]}")


def validate_chapter_pages(headings: list[dict], ip_pages: list[dict], index: list[dict]) -> None:
    """Keep group headings and actual first IP headings on their recorded page."""
    records = [r for r in ip_pages if isinstance(r, dict) and r.get("kind") == "ip-start"]
    starts = {r["id"]: r["page"] for r in records}
    if len(records) != len(starts) or set(starts) != {r["id"] for r in index}:
        raise ValueError("Tiny IP page metadata missing or duplicated")
    for row in index:
        actual = [h for h in headings if h.get("label") == "<" + row["id"] + ">"]
        if len(actual) != 1 or actual[0]["page"] != starts[row["id"]] or actual[0]["level"] != row["depth"]:
            raise ValueError("Tiny IP heading page/depth differs from chapter metadata")
    first = {"Peripherals": "xpi", "Memory Interface": "xpi", "Non-Volatile Memory (NVM)": "xpi",
             "Volatile Memory (VM)": "sram", "Timers": "timer", "IO Interface": "uart0",
             "Universal Asynchronous Receiver/Transmitter (UART)": "uart0", "Multimedia": "i2s",
             "Encryption and Data Integrity": "crypto"}
    for title, identifier in first.items():
        rows = [h for h in headings if content_text(h["title"]) == title and h.get("outlined", True)]
        if len(rows) != 1 or rows[0]["page"] != starts[identifier]:
            raise ValueError(f"Tiny category is separated from its first IP: {title}")


def diagnostics(root: Path, references: dict) -> dict:
    sdk = (root / "crt/include/retrosoc/core/status.h").read_text(encoding="utf-8")
    meanings = {
        "RS_OK": "Operation succeeded at the API's documented completion boundary.",
        "RS_EINVAL": "Invalid argument.", "RS_ENOMEM": "Memory unavailable.",
        "RS_ENOSPC": "Insufficient capacity.", "RS_ETIMEOUT": "Polling budget expired; work may remain active.",
        "RS_EIO": "I/O failure.", "RS_ENOTSUP": "Operation unsupported by the selected path.",
        "RS_EFORMAT": "Invalid data format.", "RS_EBUSY": "Resource or operation busy.",
    }
    values = [(name, int(value)) for name, value in re.findall(r"\b(RS_[A-Z]+)\s*=\s*(-?\d+)", sdk)]
    if dict(values) != dict(zip(meanings, range(0, -9, -1), strict=True)):
        raise ValueError("Tiny SDK status namespace changed")
    spi = (root / "crt/include/retrosoc/hal/spi_regs.h").read_text(encoding="utf-8")
    spi_values = [(name, int(value)) for name, value in re.findall(
        r"^#define\s+(RS_SPI_ABI_FAULT_\w+)\s+(\d+)U", spi, re.M)]
    if [name.removeprefix("RS_SPI_ABI_FAULT_") for name, _ in spi_values] != [
            "NONE", "ROUTE", "READINESS", "DMA", "CREDIT", "QUOTA"] or [v for _, v in spi_values] != list(range(6)):
        raise ValueError("Tiny SPI fault namespace changed")
    selected = {
        "sysctrl": ["FAULT_STATUS", "FAULT_MASTER", "FAULT_DETAIL", "FAULT_COUNT"],
        "rcu": ["FAULT", "RESET_CAUSE"], "dma": ["ERROR_STATUS"],
        "spi": ["FAULT_CODE", "FAULT_FRAME"], "sdio": ["DMA_ERROR", "ERROR_STATUS"],
        "dvp": ["ERROR_STATUS"],
    }
    rows = []
    for family, names in selected.items():
        for name in names:
            found = [r for r in references[family]["registers"] if r["name"] == name]
            if len(found) != 1:
                raise ValueError(f"Tiny diagnostic register missing or ambiguous: {family}.{name}")
            row = found[0]
            rows.append({**row, "owner": family.upper(), "family": family})
    return {"sdk": [dict(name=n, value=v, meaning=meanings[n]) for n, v in values],
            "spi": [dict(name=n, value=v) for n, v in spi_values], "registers": rows}
