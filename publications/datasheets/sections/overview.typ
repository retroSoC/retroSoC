#import "../style.typ": *
#import "../figures.typ": *

#text(9pt, weight: "semibold", fill: gold)[PRODUCT DATASHEET / #doc.status]
#v(9pt)
#text(30pt, weight: "semibold")[retroSoC Mini]
#linebreak()
#text(23pt, weight: "semibold", fill: gold)[Gen2/Gen2+]
#v(9pt)
#text(13pt)[An open, asymmetric RISC-V SoC for embedded control and multimedia]
#v(10pt)
#grid(columns: (1fr, 1fr),
  [*#doc.document_id* · v#doc.version \ #doc.date],
  align(right)[#doc.author \ #doc.maintainer],
)
#v(8pt)
#line(length:100%, stroke:1.1pt + gold)

= Product Brief
== Features
#columns(2, gutter: 7mm)[
  *Compute and control*
  - Hazard3 LP management hart.
  - VexiiRiscv HP application hart: RV32IMAFDC + Zicbom, Sv32.
  - Fixed EXT-L and EXT-H extension slots.
  - JTAG debug and LP-owned lifecycle control.

  *Memory and interconnect*
  - 32 KiB SRAM in the reference profile; 4/16/32/64/128 KiB configuration choices.
  - SDRAM, QPI PSRAM, OPI and XPI interfaces for external devices.
  - AXI32 control and native AXI64 data paths; APB4 register islands.
  - Eight central-DMA channel contexts.

  *Platform services*
  - Two general timers, PWM, RTC and watchdog.
  - ARCHINFO, SYSCTRL/RCU and Fabric Monitor.
  - Resource ownership and LP/HP interrupt routing.

  #colbreak()
  *Connectivity*
  - 32 GPIOs with two alternate-function selections.
  - Two UARTs and two I2C controllers.
  - SPI-SD, two SDIO hosts and PS/2.
  - USB 2.0 digital controller with an external ULPI PHY.
  - WS2812-compatible GRB transmitter.

  *Media and data processing*
  - Stereo I2S master and parallel DVP capture.
  - Baseline JPEG encoder/decoder with private DMA.
  - Coreless APU with WAV/FLAC job infrastructure; production qualification remains incomplete.
  - AES, SHA-2, raw RSA and CRC engines.
  - RNG controller; current entropy source is unqualified.

  *Development*
  - Freestanding CRT, HAL and applications.
  - Behavioral simulation, synthesis and timing flows.
  - Linux boot integration with separate qualification gates.
]
#note[This draft describes a reviewed RTL/configuration snapshot. It does not establish silicon
speed grades, electrical limits, production availability or certification. Gen2/Gen2+ is the
retained document title; no separate derivative specifications are inferred.]

#pagebreak()
== Overview
retroSoC Mini combines a small management processor with an application processor and shared
memory and I/O. Hazard3 retains authority over startup, clock transitions, resource ownership
and fault recovery. VexiiRiscv supplies the application-side compute and Linux integration.
The design is intended for embedded control, basic human-machine interfaces, retro multimedia
experimentation, education and ASIC prototyping.

#figure(product-diagram(), caption:[Integrated Mini PRODUCT IP inventory, organized by function.])<product-diagram>

#ds-table("profile", [Document reference configuration],
  ([Property], [Reference]),
  (
    ([Product profile], code(doc.profile)),
    ([Hardware source], code(doc.source_revision.slice(0,12))),
    ([Technology / SRAM], [IHP130 / 32 KiB, macro interface enabled]),
    ([Reset roots], [LP: REF24 at 24 MHz; HP: external 72 MHz]),
    ([Audio / PLL], [18.432 MHz input / PLL disabled]),
    ([HP boot example], code(doc.hp_profile)),
    ([MPW compatibility], code(doc.mpw_profile)),
  ), widths:(0.8fr,1.9fr),
)
