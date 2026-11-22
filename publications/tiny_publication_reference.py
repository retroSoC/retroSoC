"""Tiny publication navigation and diagnostics, without changing the hardware ABI."""
from __future__ import annotations

import re
from pathlib import Path

from publications.structure_reference import content_text


def smartwatch_reference(gpio: list[dict], facts: dict) -> dict:
    """Resolve the common wiring and the two exclusive assembly options."""
    pads = {row["pin"]: row for row in gpio}
    if len(gpio) != 32 or set(pads) != set(range(32)):
        raise ValueError("Tiny smartwatch requires the complete 32-pad GPIO map")

    def alt(pin: int, mode: str, signal: str, *, output: str | None = None, input_: str | None = None) -> dict:
        route = pads[pin][mode]
        if (route["inputs"] != ([input_] if input_ else [])
                or route["do"] != (output or "1'b0") or (route["oe"] != "1'b0") != (output is not None)):
            raise ValueError(f"Tiny smartwatch: GPIO{pin} {mode.upper()} does not route {signal}")
        direction = "I/O" if input_ and output else "in" if input_ else "out"
        return dict(pin=pin, mode=mode.upper(), signal=signal, direction=direction)

    def gpio_pin(pin: int, signal: str, direction: str) -> dict:
        return dict(pin=pin, mode="GPIO", signal=signal, direction=direction)

    def connected(pin: dict) -> str:
        mode = "" if pin["mode"] == "GPIO" else f" {pin['mode']}"
        return f"GPIO{pin['pin']}{mode} {pin['signal']} ({pin['direction']})"

    def span(pins: list[dict], signals: str = "") -> str:
        span_mode = f"GPIO{pins[0]['pin']}–{pins[-1]['pin']} {pins[0]['mode']}"
        return f"{span_mode} {signals}" if signals else span_mode

    xin_mhz = int(facts["profile"]["EXT_CLK_HZ"]) // 1_000_000
    boot_cs, ram_cs = "NSS0", "NSS1"
    memory = [alt(29, "alt0", ram_cs, output="xpi.nss_o[1]")]
    sd = [
        alt(0, "alt0", "CLK", output="u_sdio_if.sck_o"),
        alt(1, "alt0", "CMD", output="u_sdio_if.cmd_do_o", input_="u_sdio_if.cmd_di_i"),
        *(alt(i + 2, "alt0", f"DAT{i}", output=f"u_sdio_if.dat_do_o[{i}]", input_=f"u_sdio_if.dat_di_i[{i}]")
          for i in range(4)),
        gpio_pin(6, "SD_CD_N", "in"),
        gpio_pin(7, "SD_PWR_EN", "out"),
    ]
    serial = [
        alt(8, "alt0", "TX", output="u_uart0_if.tx_o"),
        alt(9, "alt0", "RX", input_="u_uart0_if.rx_i"),
    ]
    i2c = [
        alt(10, "alt0", "SCL", output="u_i2c0_if.scl_o", input_="u_i2c0_if.scl_i"),
        alt(11, "alt0", "SDA", output="u_i2c0_if.sda_o", input_="u_i2c0_if.sda_i"),
    ]
    audio = [
        alt(12, "alt0", "SCLK", output="u_i2s_if.sclk_o"),
        alt(13, "alt0", "LRCK", output="u_i2s_if.lrck_o"),
        alt(14, "alt0", "DACDAT", output="u_i2s_if.dacdat_o"),
        alt(15, "alt0", "ADCDAT", input_="u_i2s_if.adcdat_i"),
        alt(16, "alt0", "MCLK", output="u_i2s_if.mclk_o"),
        alt(17, "alt0", "AUDIO.CLKIN", input_="s_audio_pad_clk"),
    ]
    pwm = [alt(18 + i, "alt0", f"PWM{i}", output=f"u_pwm_if.pwm_o[{i}]") for i in range(4)]
    expansion = [*pwm[2:], alt(22, "alt0", "PWM_FAULT", input_="u_pwm_if.fault_i"),
                 alt(23, "alt0", "PWM_SYNC", input_="u_pwm_if.sync_i")]
    key = [gpio_pin(24, "FUNCTION_KEY", "in")]
    rgb = [alt(26, "alt0", "WS2812", output="u_ws2812_if.dat_o")]
    display = [
        alt(27, "alt0", "SCK", output="s_spi_sck"),
        alt(28, "alt1", "MOSI", output="s_spi_mosi"),
        alt(31, "alt1", "CS_N", output="s_spi_cs_n"),
        gpio_pin(30, "D/C", "out"),
        gpio_pin(25, "LCD_RESET_N", "out"),
    ]
    camera = [
        *(alt(12 + i, "alt1", f"D{i}", input_=f"u_dvp_if.dat_i[{i}]") for i in range(8)),
        alt(20, "alt1", "PCLK", input_="u_dvp_if.pclk_i"),
        alt(21, "alt1", "HREF", input_="u_dvp_if.href_i"),
        alt(22, "alt1", "VSYNC", input_="u_dvp_if.vsync_i"),
        alt(23, "alt1", "CAM_XCLK", output="s_clkout"),
    ]
    common = [*sd, *serial, *i2c, *key, *rgb, *display, *memory]
    profiles = {"watch": [*common, *audio, *pwm[:2], *expansion], "camera": [*common, *camera]}
    for name, pins in profiles.items():
        if sorted(pin["pin"] for pin in pins) != list(range(32)):
            raise ValueError(f"Tiny smartwatch: {name} assembly has duplicate or unassigned GPIOs")
        profiles[name] = sorted(pins, key=lambda pin: pin["pin"])

    options = {"ble": "BLE", "wifi": "Wi-Fi", "service": "USB-UART"}
    sensors = ["6-axis IMU", "3-axis magnetometer", "Ambient light", "Optical front end"]
    attachments = {"nfc": "NFC reader", "gnss": "GPS / GNSS"}
    links = dict(
        power=dict(clock=f"{xin_mhz} MHz", rails="Core / I/O"),
        memory=dict(bus="XPI", boot_cs=boot_cs, ram_cs=ram_cs),
        sd=dict(bus="SDIO0", width="4-bit"),
        serial=dict(bus="UART0", selection="Fit one", options=options),
        sensing=dict(bus="I²C0", sensors=sensors, **attachments),
        audio=dict(bus="I²S", adc=audio[3]["signal"], dac=audio[2]["signal"], ref_clock="AUDIO"),
        display=dict(bus="SPI0", backlight=pwm[0]["signal"]),
        actuation=dict(motor=pwm[1]["signal"], rgb=rgb[0]["signal"]),
        io=dict(expansion=span(expansion)),
        camera=dict(bus="DVP", pads=span(camera), clock_out=camera[-1]["signal"]),
    )

    def row(title: str, assignments: list[str], notes: str) -> dict:
        return dict(title=title, assignments=assignments, notes=notes)

    rows = [
        row("Power / clock / reset", [f"Core and I/O rails. External {xin_mhz} MHz → XIN.", "Dedicated RESET_N input."],
            "USB-C VBUS goes through ESD / OVP to the charger and battery connector. A load switch feeds both LDOs. "
            "The supervisor holds RESET_N low until power and XIN are valid. The reset key asserts RESET_N."),
        row("Boot and expansion memory", [f"Dedicated {boot_cs} (out).", connected(memory[0])],
            f"XPI boot NOR on {boot_cs}. Optional {ram_cs} PSRAM requires explicit initialization."),
        row("TF / microSD", [span(sd[:6], "CLK (out), CMD and DAT0–3 (I/O)."), *map(connected, sd[6:])],
            "Native 4-bit SDIO. Card detect is active low. SD_PWR_EN controls an external card load switch. "
            "Use private SDIO DMA with SRAM bounce buffers."),
        row("Wireless / service console", list(map(connected, serial)),
            f"Fit {options['ble']}, {options['wifi']} or the {options['service']} bridge. Cross TX and RX at the "
            "selected module and isolate the other links. Feed the console bridge from D+/D− at USB-C."),
        row("JTAG / NOR programming", ["Dedicated JTAG access"],
            "Use an external probe for debug and the SRAM loader for NOR programming."),
        row("Touch and sensors / NFC / GNSS", [span(i2c, "SCL and SDA (I/O, open-drain)")],
            "Touch via FPC, " + ", ".join(sensors) + ", NFC polling and an I²C GNSS host port. "
            "Check addresses, I/O levels and external pull-ups."),
        row("I²S audio", [
            span(audio[:3], "SCLK, LRCK, DACDAT (out)."),
            *map(connected, audio[3:]),
        ], "MEMS mic → codec ADC → ADCDAT. DACDAT → codec DAC → amp → speaker. "
           "Provide a separate AUDIO reference clock. Audio uses DMA6/7."),
        row("LCD and backlight", [connected(pin) for pin in (*display, pwm[0])],
            "Write-only SPI0 LCD and GPIO controls via FPC. PWM0 controls the external backlight driver in the watch assembly."),
        row("Vibration and RGB", [connected(pwm[1]), connected(rgb[0])],
            "External motor driver on PWM1 and addressable RGB LED on WS2812."),
        row("Function key / expansion", [
            connected(key[0]),
            span(expansion, "PWM2/3 (out), PWM_FAULT and PWM_SYNC (in)."),
        ], "Function key is independent of RESET_N. The header reserves the four expansion pads."),
        row("Camera assembly option", [
            span(camera[:8], "D0–D7 (in)."), span(camera[8:11], "PCLK, HREF, VSYNC (in)."),
            connected(camera[11]) + " via RCU CLKOUT.",
        ], "Fit in place of the watch audio, PWM and expansion group. Keep inactive drivers isolated. "
           "I²C sensor control shares I²C0. SPI LCD remains available with a fixed external backlight setting. "
           "RAW DVP or PPALite PROCESS uses DMA2 to SRAM or initialized PSRAM."),
    ]
    return dict(
        hardware_isa=facts["hardware_isa"],
        sram_kib=facts["sram"]["CapacityKiB"],
        axi_width=facts["sram"]["DataWidth"],
        dma_channels=facts["dma"]["NumChannels"],
        links=links,
        profiles=profiles,
        rows=rows,
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
