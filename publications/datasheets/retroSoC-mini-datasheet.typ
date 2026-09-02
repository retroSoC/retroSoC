#set document(
  title: "retroSoC Mini Gen2 Datasheet",
  author: "Yuchi Miao",
  keywords: "retroSoC",
)
#set page(
  header: align(center)[
    https://github.com/retroSoC
  ],
  numbering: "1/1",
  columns: 1,
)

#set par(justify: true)
#set text(font: "Inter", size: 11pt)
#set heading(numbering: "1.")


#show title: set text(size: 17pt)
#show link: underline

#title[
  retroSoC Mini Series Gen2/Gen2+
]

#place(
  top + right,
  dx: 0pt,
  // square(size: 36pt, fill: none, stroke: black),
  rect(height: 66pt, width: 140pt, fill: none, stroke: black),
)

Datasheet (rev.3 – 2026.02.15) \
*Author:* Yuchi Miao (#link("miaoyuchi@ict.ac.cn")) \
*Maintained by* _ECOS Team, ICT, CAS_

#line(length: 100%)
A *Lightweight* RV32I/EMC *MCU Framework* with *128KiB* OCM, 1xXPI, 2xSPISD/SDIO, 2xPSRAM(SDR/DTR), 1xSDRAM, 24xGPIO, 1xDMA, 3xTIMER, 1xRTC, 1xWDG, 4xPWM, 2xUART, 2xI2C, 1xONEWIRE, 1xPS2, 1xARCHINFO, 1xSYSCTRL, 1xRCU, 1xRNG, 1xCRC, 1xI2S, 1xDVP, 1xAPU\*, 1xGA\*, 1xCRC, 1xRNG
#line(length: 100%)


= Product Brief
#place(
  top + right,
  dx: 0pt,
  dy: 168pt,
  grid(
    columns: auto,
    align: center,
    gutter: 3pt,
    // stroke: black,
    rect(height: 27pt, width: 250pt, fill: white, stroke: black, radius: 6pt)[
      #grid(
        columns: (1fr, 1fr, 1fr, 1fr),
        align: center,
        gutter: 3pt,
        // stroke: black,
        text("Available", size: 8pt, weight: "medium"),
        text("Functional", size: 8pt, weight: "medium"),
        text("Reproduced", size: 8pt, weight: "medium"),
        text("Tapedout", size: 8pt, weight: "medium"),
        circle(radius: 4pt, stroke: black, fill: yellow.lighten(60%)),
        circle(radius: 4pt, stroke: black, fill: white),
        circle(radius: 4pt, stroke: black, fill: white),
        circle(radius: 4pt, stroke: black, fill: white),
      )
    ],
    text("Artifact Evaluation", size: 7pt, weight: "medium")
  ),
)

== Feature
#columns(2)[

  - Core – PicoRV32/Hazard3
    - *196MHz* maximum frequency
    - 2-pipeline RV32I/E\[MAC\], 16xIRQ
    - Hardware multiplication and division

  - Memories
    - *0\~128KiB* On-Chip-RAM *(OCM)*
    - *32MiB* XPI NOR Flash Controller
    - *8/32MiB* PSRAM Controller
    - *64MiB* 16bit SDRAM Controller

  - Bus – Async. *No-burst* Protocol
    - Native Memory Interface *(NMI)*
    - AXI4-Lite master, APB3 slave
    - NMI, AXI4L, APB3 Interconnect

  - Reset Clock Unit *(RCU)*
    - *4\~50MHz* Active Crystal Oscillator
    - PLL for core clock *(24\~192MHz)*
    - PLL or Bypass mode

  - XPI *(SDR mode only)*
    - Half-duplex, SPI/DPI/QSPI/QPI mode
    - 32x32b TX/RX dual FIFO Integrated
    - Register/Memory-mapped/DMA

  - SPISD/SDIO (SDHC, 4\~32GB)
    - *1GiB* Memory-mapped access
    - 1/4-wire SPI or SDIO mode *(SDv2.0)*
    - 512B cache, 50MHz maximum freq.

  - I2S (HQ, Hi-Res audio)
    - Stereo input/output mode
    - max *24b/96KHz* format support
    - Full-duplex, I2S Phillips only

  #colbreak()

  - DVP (Camera interface)
    - 8-bit parallel input mode
    - max *2M* image sensor support
    - RGB565 format support only

  - APU/GA\* *(Experimental integrate)*
    - Audio Keyword Wake-Up (CNN)
    - Simple 2D/3D graphics render
    - High performance DMA engine

  - Other Communication Interfaces
    - 2xUARTs (FIFO/No FIFO)
    - 3xTIMER, 1xRTC, 1xWDG, 4xPWM
    - 1xRNG, 1xARCHINFO, 1xSYSCTRL
    - 1xONEWIRE, 1xCRC, 1xI2C, 1xPS2

  - *GDS Merge Template*
    - *0\~32* master designs (Core)
    - *0\~256* slave designs (digital module)
    - 16xGPIO, max 5000 cells per design

  - Development
    - *Open source* and full synthesizable
    - Static synchronous design
    - *ICS55*, IHP130 PDK support
    - RV32I/E\[MAC\] C Running Time *(CRT)*

  - Tools & Flows
    - VCS, Verilator, iVerilog (TBD)
    - Yosys, ECC, Pristine (TBD)
    - *QFN128* (12.3x12.3mm) Package

  - Application
    - *Wearables*;, IoT services, E-readers
    - Education, ASIC Prototype
]


#figure(
  image(
    "retroSoC-mini-block-diagram.svg",
    width: 100%,
  ),
  caption: [
    *_retroSoC Mini Gen2/Gen2+_* block diagram
  ],
)<block-diagram>


== Overview
_*retroSoC*_ is a fully open-source and customizable ASIC framework for _*“retro-style”*_ applications(handheld game consoles, system). And of ECOS Team.\
(story, target, my thinking, be dedicated to retro multimedia area, full open source, focus on funny)
(insert a retro poster/diagram to descripte the motivation[why])

- *Open source*: It is both straightforward to use and highly compatible with EDA toolchains — specifically targeting open-source EDA *(iEDA, OpenROAD, etc)*.

- *HW-SW co*:

- *Time to market*: focus on the funcitonality, seprate into 4 series

- *Lower the price*: Additionally, retroSoC can also serve as a flexible, reconfigurable *SoC template* for end customers or students who want to integrate their own design into a shared fabrication wafer *(shuttle)*.

- *Well documented*: balba

The _*retroSoC Mini Series*_ is a family of highly integrated, lightweight MCU designed for Internet of Things *(IoT)* scenarios. _*retroSoC Mini Gen2/Gen2+*_ adopts the PicoRV32/Hazard3 core and integrates DMA, SPISD/SDIO, SDRAM, I2S and XPI IPs. It can be used for a wide variety of applications as wearables, education or ASIC prototype verification.
#lorem(380)

== Product Series
#lorem(100)
#figure(
  image(
    "retroSoC-Product-Series.svg",
    width: 100%,
  ),
  caption: [
    *_retroSoC_* Product series
  ],
)<product-series>

== Roadmap
#lorem(100)
#figure(
  image(
    "retroSoC-Roadmap.svg",
    width: 100%,
  ),
  caption: [
    *_retroSoC_* Roadmap
  ],
)<product-rodamap>


== Revision History

#set table(
  stroke: black,
  gutter: 0em,
  fill: (x, y) => if y == 0 { yellow.lighten(60%) },
)

#show table.cell: it => {
  if it.y == 0 {
    set text(black)
    strong(it)
  } else if it.body == [] {
    pad(..it.inset)[_N/A_]
  } else {
    it
  }
}

#table(
  columns: (1fr, 1fr, 1fr, 1fr),
  [Date], [Version], [Release Note], [Author],
  [2025-09-28], [v0.1], [Create document], [Yuchi Miao],
  [2025-12-02], [v0.2], [Initial draft], [Yuchi Miao],
  [2026-02-15], [v0.3], [Initial release], [Yuchi Miao],
)

== License
#lorem(60)
#pagebreak()

#outline()

= System Architecture
== Introduction
=== SoC Architecture
=== Management Processor
==== PicoRV32
==== Hazard3

== Interconnect
=== Native Memory Interface *(NMI)*
=== Interconnect Matrix
=== Address Mapping

== Clock and Reset
=== Architecture
=== Reset and Logic

== Interrupt System
== Packaging
=== Pin Mapping
=== Package Dimensions
=== Graded Reflow Soldering
=== Ordering Information

== Peripherals

=== Memory Interface
==== Non-Volatile Memory *(NVM)*
===== XPI Universal Controller *(XPI)*
===== SPI SD Card Controller *(SPISD)*
===== SD Card Controller *(SDIO0)*
==== Volatile Memory *(VM)*
===== On Chip Memory *(OCM)*
===== PSRAM Controller *(PSRAM)*
===== SDRAM Controller *(SDRAM)*

=== General-Purpose Input Output *(GPIO)*
==== System IO *(GPIO0)*
==== User Custom IO *(GPIO1)*

=== Direct Memory Access *(DMA)*
==== Architecture
==== Hardware Trigger Channels

=== Timers
==== General-Purpose Timer *(TIM0, TIM1)*
==== Advanced Timer *(TIM2)*
==== Real Time Clock *(RTC)*
==== Watchdog *(WDG)*
==== Pulse Width Modulation *(PWM)*

=== IO Interface
==== Universal Async. Receiver/Transmitter *(UART)*
===== Simple No-FIFO Version *(UART0)*
===== Advanced FIFO Version *(UART1)*
==== Inter-Integrated Circuit *(I2C)*
==== One Wire Serial Bus *(ONEWIRE)*
==== Personal System/2 *(PS2)*
==== SDIO Controller *(SDIO1)*
==== Architecture Information *(ARCHINFO)*
==== System Controller *(SYSCTRL)*
==== Reset Clock Unit *(RCU)*

=== Multimedia
==== Inter-Integrated Circuit Sound *(I2S)*
==== Extended Peripheral Interface *(XPI)*
==== Digital Video Port *(DVP)*
==== Audio Processing Unit\* *(APU)*
==== Graphic Accelerator\* *(GA)*

=== Encryption
==== Cyclic Redundancy Check *(CRC)*
==== Random Number Generator *(RNG)*

== Software
=== Boot Sequence
=== TinySDK and TinyShell
=== Application

== SoC Template
=== Architecture
=== User Guide

== Implementation
=== SoC Integration
=== RTL Simulation
=== FPGA Verification
=== Physical Design
=== PCB Hardware

= Technical Report (ongoing)
== First Shuttle *(2026.06.01, ICS55nm)*

Overview(written in SystemVerilog)

1. Introduction (arch info first)

1.1 core(info, wavedorm)

1.2 bus(nmi intro, matrix, addr mmap)

1.3 clock&reset (block diagram, wavedorm)

1.4 IO/Package(voltage, IO pad speed, IO pos)

2. Peripherals

2.1 Memory

2.2 DMA

2.3 Timer

2.4 IO perip

2.5 Encryption

3. Software

3.1 boot sequ.

3.2 application

4.  SoC Template

4.1 intro four mode(bakcend GDS)

4.2 how to integrate 'core' or 'IP design'

5. Implemention

5.1 FPGA

5.2 Backend(SDC, ICS55 example)

5.3 PCB+ 

6. Resource & 

6.1
