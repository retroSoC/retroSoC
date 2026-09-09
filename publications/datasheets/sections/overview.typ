#import "../style.typ": *
#import "../figures.typ": *

// Publication status is explicit; successful build/tests do not change these marks.
#let artifact-status = (
  (name:"Available",selected:true),
  (name:"Functional",selected:false),
  (name:"Reproduced",selected:false),
  (name:"Tapedout",selected:false),
)

#cover(evaluation:artifact-status)[
#text(9pt, weight: "semibold", fill: gold)[PRODUCT DATASHEET / #doc.status]
#v(rhythm.cover-gap)
#text(30pt, weight: "semibold")[retroSoC Mini]
#linebreak()
#text(23pt, weight: "semibold", fill: gold)[Gen2/Gen2+]
#v(rhythm.cover-gap)
#text(13pt)[An Open-Source, Linux-Capable Asymmetric Dual-Core SoC]
#v(rhythm.cover-meta-gap)
#grid(columns: (1fr, 1fr),
  [*#doc.document_id* · v#doc.version \ #doc.date],
  align(right)[#doc.author \ #doc.maintainer],
)
#v(rhythm.cover-rule-gap)
#line(length:100%, stroke:1.1pt + gold)

= Product Brief
== Features
#columns(2, gutter: rhythm.cover-gutter)[
  #set par(leading: rhythm.cover-leading, spacing: rhythm.cover-spacing)
  #set list(tight:false,spacing:rhythm.cover-list-spacing,body-indent:rhythm.cover-list-indent)
  *Compute and control*
  - Hazard3 LP: boot, clocks, resource ownership and fault recovery.
  - Dual-issue VexiiRiscv HP: RV32IMAFDC + Zicbom, Sv32.
  - JTAG debug; fixed EXT-L control and EXT-H AXI64 slots.

  *Memory and interconnect*
  - 32 KiB banked SRAM in this profile; 4/16/32/64/128 KiB build options.
  - AXI32 control, native AXI64 data paths and APB4 registers.
  - SDRAM, QPI PSRAM and OPI/HyperBus-style external-memory controllers.
  - XPI: four chip selects, 16 LUT sequences, 1/2/4-bit SDR transfers.
  - Eight DMA channels; linked-list TCDs, 16-beat bursts and stream endpoints.

  *Platform services*
  - Two 32-bit timers with 16-bit prescalers; four-channel PWM.
  - 64-bit RTC, two alarms and periodic wake.
  - Window watchdog with early warning and retained reset cause.
  - LP/HP local interrupts, PLIC and mailbox.
  - ARCHINFO, SYSCTRL/RCU, resource ownership and first-fault/performance monitoring.

  #colbreak()
  *Connectivity*
  - 32 GPIOs: atomic outputs, pin interrupts and two alternate-function selections.
  - Two UARTs with 64-byte TX/RX FIFOs; UART0 DMA and RTS/CTS.
  - Two I2C controllers: 7/10-bit addressing and 16-entry command/RX FIFOs.
  - SPI-SD, two 1/4-bit SDR SDIO hosts and bidirectional PS/2.
  - USB2: 8 endpoints, 16 host channels, 16 KiB packet RAM; external ULPI PHY.
  - WS2812: 24-bit GRB with programmable pulse/reset timing.

  *Media and data processing*
  - Stereo 16/24-bit I2S master; 8-bit RGB565/YUV422 DVP with crop/snapshot capture.
  - Baseline JPEG encode/decode up to 2048 × 2048, with private DMA.
  - Coreless APU WAV/FLAC job infrastructure; production qualification incomplete.
  - AES-128/192/256, SHA-224/256 and raw RSA-2048; programmable CRC.
  - RNG source remains unqualified for production entropy.

  *Development*
  - Freestanding CRT/HAL and reference apps; simulation, synthesis and timing flows.
  - Experimental Linux integration with separate qualification gates.
]
#v(1fr)
#note(below: 0pt)[This draft describes a reviewed RTL/configuration snapshot. It does not establish silicon
speed grades, electrical limits, production availability or certification. Gen2/Gen2+ is the
retained document title; no separate derivative specifications are inferred.]
]

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
