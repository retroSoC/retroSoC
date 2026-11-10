#import "../style.typ": *
#import "../diagrams.typ": architecture, clock-tree, overview, flow
#import "../waveforms.typ": timing

#cover(evaluation:((name:"Available",fill:"full"),(name:"Functional",fill:"left-half"),(name:"Reproduced",fill:"empty"),(name:"Tapedout",fill:"empty")))[
  #text(9pt,weight:"semibold",fill:gold)[PRODUCT DATASHEET / #doc.status]
  #v(rhythm.cover-gap)
  #text(30pt,weight:"semibold")[retroSoC Tiny]
  #linebreak()
  #text(23pt,weight:"semibold",fill:gold)[Gen1]
  #v(rhythm.cover-gap)
  #text(13pt)[An Open-Source, Single-Core RISC-V MCU]
  #v(rhythm.cover-meta-gap)
  #grid(columns:(1fr,1fr),
    [#text(font:("Inter","Noto Sans CJK SC"),weight:"bold",top-edge:0.7275390625em)[#doc.brand_name（#doc.brand_name_zh）] · v#doc.version \ #doc.date],
    align(right)[#doc.author#link("mailto:"+doc.author_email)[(#doc.author_email)] \ #doc.maintainer])
  #v(rhythm.cover-rule-gap)
  #line(length:100%,stroke:1.1pt+gold)
= Product Brief
== Features
  #columns(2,gutter:rhythm.cover-gutter)[
    #set par(leading:rhythm.cover-leading,spacing:rhythm.cover-spacing)
    #set list(spacing:rhythm.cover-list-spacing)
*Compute and debug*
    - One Hazard3 hart: *RV32IMC*, A disabled; default RV32IM firmware.
    - Independent local instruction/data paths; JTAG halt, resume and hart reset.
    *Memory and interconnect*
    - *128 KiB SRAM*: four 32 KiB groups, 32 physical 4 KiB banks.
    - AXI32 fabric with CPU slow, central-DMA and SDIO initiators; APB4 controls.
    - XPI NOR boot; optional *8 MiB NSS1 PSRAM* after explicit initialization.
    *DMA and platform control*
    - *Eight DMA channels*, stream endpoints and SPI V2.2 admission.
    - RCU source switching, leaf gates/reset, rate snapshots and fault recovery.
    - SYSCTRL diagnostics; ARCHINFO discovery; 1 MHz CLINT timebase.
    #colbreak()
    *Wired connectivity*
    - *32 GPIOs*; one FIFO UART and one controller-mode I2C.
    - Native 1/4-bit SDIO with private DMA; general 8/16-bit SPI master.
    - Four-slot SDR XPI; GPIO-routed chip selects retain shared pin ownership.
    *Media and services*
    - Stereo 16/24-bit I2S; DVP snapshot/crop; PPALite sampling/luma; WS2812.
    - AES/SHA2/raw RSA, programmable CRC and an unqualified RNG source.
    - Two general timers, four PWM outputs, RTC and window watchdog.
    *Configuration and evidence*
    - *ICS55 default*: SAFE24 boot, PLL parked off; functional PLL192/240 profiles.
    - Explicit IHP130/no-PLL compatibility; hardware qualification remains separate.
    - Freestanding SDK and bounded camera, display, audio and SD workloads.

  ]
  #v(1fr)
  #note(below:0pt)[This DRAFT describes an implemented *prototype*. SAFE24 and PLL profiles are digital capabilities,
    *not timing-qualified operating points*. Electrical, package, thermal, power and silicon qualification remain unprovided.
    The partial Functional mark does not establish complete protocol or physical qualification.]
]

#pagebreak()
== Overview <tiny-overview>
retroSoC Tiny Gen1 is a wired MCU with one Hazard3 hart, separate local instruction and data paths, and a 32-bit AXI fabric for shared resources.
#overview()
#let compat = data.compatibility.first()
#ds-table("reference-configuration",[Document reference configuration],([Property],[Reference]),(
  ([Main profile],code(doc.profile)),
  ([Reviewed source],code(doc.source_revision.slice(0,12))),
  ([Boot clock],reference-boot(data.facts)),
  ([Main SRAM],[#data.facts.sram.CapacityKiB KiB]),
  ([Compatibility],[#code(compat.profile_path), #reference-boot(compat)])),widths:(1.05fr,2.55fr))
See @tiny-configuration for profile differences and @tiny-core for the functional architecture.
