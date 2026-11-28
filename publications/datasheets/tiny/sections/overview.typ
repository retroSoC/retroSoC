#import "../style.typ": *
#import "../diagrams.typ": architecture, clock-tree, diagram, overview, flow
#import "../feature-highlights.typ": cover-chip, cover-chip-size, feature-highlights, r1-product-line
#import "../waveforms.typ": timing

#cover(evaluation:((name:"Available",fill:"full"),(name:"Functional",fill:"left-half"),(name:"Reproduced",fill:"empty"),(name:"Tapedout",fill:"empty")))[
  #text(9pt,weight:"semibold",fill:gold)[PRODUCT DATASHEET / #doc.status]
  #v(rhythm.cover-gap)
  #text(30pt,weight:"semibold")[retroSoC TINY]
  #linebreak()
  #text(23pt,weight:"semibold",fill:gold)[Gen1]
  #v(rhythm.cover-gap)
  #text(13pt)[An Open-Source, Single-Core RISC-V MCU]
  #v(rhythm.cover-meta-gap)
  #change-start("tiny-v02-cover-chip-20261124-cover-chip", "Cover chip artwork")
  #change-start("tiny-v02-r1-chip-marks-20261125-cover-chip-mark", "ICsprout removal from cover chip")
  #grid(columns:(1fr,1fr),
    [#text(font:("Inter","Noto Sans CJK SC"),weight:"bold",top-edge:0.7275390625em)[#doc.brand_name（#doc.brand_name_zh）] · v#doc.version \ #doc.date],
    align(right)[#place(top + right, dy: -(cover-chip-size + 3mm), cover-chip())#doc.author#link("mailto:"+doc.author_email)[(#doc.author_email)] \ #doc.maintainer])
  #change-end("tiny-v02-r1-chip-marks-20261125-cover-chip-mark")
  #change-end("tiny-v02-cover-chip-20261124-cover-chip")
  #v(rhythm.cover-rule-gap)
  #line(length:100%,stroke:1.1pt+gold)
= Product Brief
#change-start("tiny-v02-piolite-integration-20261127-features", "GPIO and PIOLITE on the TINY feature list")
== Features
#change-end("tiny-v02-piolite-integration-20261127-features")
  #columns(2,gutter:rhythm.cover-gutter)[
    #set par(leading:rhythm.cover-leading,spacing:rhythm.cover-spacing)
    #set list(tight:false,spacing:rhythm.cover-list-spacing,body-indent:rhythm.cover-list-indent,marker:([•],[▪]))
    *Compute and debug*
    - One Hazard3 hart with *RV32IMC* hardware. Default firmware targets RV32IM.
    - Independent local instruction and data paths connect the CPU to on-chip SRAM.
    - JTAG halt, resume and hart reset with retained debug state.
    - *1 MHz CLINT timebase* with machine timer and software interrupts.

    *Memory and interconnect*
    - *128 KiB SRAM* in four 32 KiB groups with 32 physical 4 KiB banks.
    - AXI32 fabric with CPU slow, central DMA and SDIO initiators and APB4 controls.
    - Four XPI chip-select slots and *16 LUT sequences* for 1/2/4-bit SDR transfers.
    - NSS0 NOR boot. Optional *8 MiB NSS1 PSRAM* with explicit initialization.
    - *Eight DMA channels*, 64-byte aligned TCDs, up to 16-beat bursts and stream endpoints.

    *Platform and configuration*
    - ICS55 SAFE24 boot with PLL parked off and functional PLL192/240 profiles.
    - IHP130 no-PLL profile. RCU switches clocks and controls leaf gates and resets.
    - Two 32-bit timers with 16-bit prescalers. Four PWM outputs with capture/fault.
    - 64-bit RTC with subsecond time and alarms. Window watchdog with early warning.
    - SYSCTRL first-fault capture and ARCHINFO.

    #colbreak()
    *Wired connectivity*
    - *32 GPIOs* with atomic outputs, pin IRQs, two alternate modes and PIOLITE USER ownership.
    - UART0 with *64-byte TX/RX FIFOs*, fractional baud and central-DMA requests.
    - I2C0 controller with 7/10-bit addressing and command and receive FIFOs.
    - SPI0 master modes 0–3 with *8/16-bit frames* and guarded V2.2 DMA admission.
    - 1/4-bit SDR SDIO with private AXI32 DMA.
    - WS2812 24-bit RGB output with programmable pulse and reset timing.

    *Media and data processing*
    - Stereo 16/24-bit I2S master with separate TX/RX streams and AUDIO clock domain.
    - *8-bit DVP* captures RGB565/YUV422 with snapshot and crop controls.
    - PPALite finite-frame sampling and luma extraction before the first memory write.
    - AES-128/192/256, SHA-224/256 and raw RSA-2048 with 24 KiB private storage.
    - Programmable CRC and RNG health status. Entropy qualification remains open.

    *Development and applications*
    - Freestanding CRT/HAL and reference apps.
    - Bounded camera, display, audio and SD workloads with shared pin ownership.
    - Application
      #list(
        [*Wearables*, IoT services, E-readers],
        [Education, ASIC Prototype],
      )
  ]
  #v(1fr)
  #note(below:0pt)[This DRAFT describes an implemented *prototype*. SAFE24 and PLL profiles are digital capabilities,
    *not timing-qualified operating points*. Electrical, package, thermal, power and silicon qualification remain unprovided.
    The partial Functional mark does not establish complete protocol or physical qualification.]
]

#pagebreak()
== Overview <tiny-overview>
retroSoC TINY Gen1 is a wired MCU with one Hazard3 hart, separate local instruction and data paths, and a 32-bit AXI fabric for shared resources.
#overview()
#let compat = data.compatibility.first()
#ds-table("reference-configuration",[Document reference configuration],([Property],[Reference]),(
  ([Main profile],code(doc.profile)),
  ([Reviewed source],code(doc.source_revision.slice(0,12))),
  ([Boot clock],reference-boot(data.facts)),
  ([Main SRAM],[#data.facts.sram.CapacityKiB KiB]),
  ([Compatibility],[#code(compat.profile_path), #reference-boot(compat)])),widths:(1.05fr,2.55fr))
#change-start("tiny-v02-r1-roadmap-20261126-overview-link", "Overview link to the R1 family roadmap")
See @tiny-configuration for profile differences, @tiny-core for the functional architecture and @tiny-r1-roadmap-figure for the R1 family schedule.
#change-end("tiny-v02-r1-roadmap-20261126-overview-link")

#pagebreak()
#{
  show figure: set block(above: 0pt, below: 0pt, breakable: false)
  let highlights = block(width: 100%, above: 0pt, below: 0pt, breakable: false)[
    #change-start("tiny-v02-overview-highlights-20261123-feature-highlights", "TINY Gen1 feature highlights", category: "added")
    #change-start("tiny-v02-chip-mark-20261124-chip-mark", "Figure 2 chip markings and logo placeholders")
    #change-start("tiny-v02-chip-logos-20261124-chip-logos", "Figure 2 white ECOS and ICsprout logos")
    #change-start("tiny-v02-feature-card-layout-20261126-feature-highlights", "Figure 2 feature card layout")
    #change-start("tiny-v02-feature-card-columns-20261126-feature-highlights", "Figure 2 column alignment and card contents")
    #diagram("tiny-gen1-highlights", feature-highlights(data), [TINY Gen1 feature highlights.],
      figure-label: "tiny-gen1-highlights")
    #change-end("tiny-v02-feature-card-columns-20261126-feature-highlights")
    #change-end("tiny-v02-feature-card-layout-20261126-feature-highlights")
    #v(rhythm.figure-space)
    #align(center)[#text(size: 9pt, fill: muted)[Applications are illustrative. I²S and DVP share GPIOs and use alternate pin configurations.]]
    #change-end("tiny-v02-chip-logos-20261124-chip-logos")
    #change-end("tiny-v02-chip-mark-20261124-chip-mark")
    #change-end("tiny-v02-overview-highlights-20261123-feature-highlights")
  ]
  let plates(product-line) = block(width: 100%, above: 0pt, below: 0pt, breakable: false)[
    #change-start("tiny-v02-r1-product-line-20261124-r1-product-line", "Figure 2 layout and R1 product line")
    #change-start("tiny-v02-r1-warm-yellow-20261125-r1-product-line", "Warm-yellow accents for the right R1 group")
    #change-start("tiny-v02-r1-chip-marks-20261125-r1-product-line", "ICsprout removal from product line chips")
    #change-start("tiny-v02-r1-product-cards-20261125-r1-product-line", "R1 product descriptions and status cards")
    #change-start("tiny-v02-r1-compact-cards-20261125-r1-product-line", "Compact R1 card typography and alignment")
    #change-start("tiny-v02-r1-reference-layout-20261125-r1-product-line", "R1 figure page placement and card finish")
    #change-start("tiny-v02-r1-chip-alignment-20261125-r1-product-line", "R1 chip scale and status pill alignment")
    #change-start("tiny-v02-pdk-highlights-20261125-overview-figures", "ICSprout55 PDK tile, chip marks and semibold R1 highlights")
    #change-start("tiny-v02-r1-weight-450-20261126-r1-product-line", "R1 product highlights at weight 450")
    #change-start("tiny-v02-piolite-r1-badges-20261128-overview", "PIOLITE feature tile and R1 product line badges")
    #stack(dir: ttb, spacing: rhythm.figure-space,
      highlights,
      diagram("tiny-r1-product-line", product-line, [R1 product line.],
        figure-label: "tiny-r1-product-line"),
    )
    #change-end("tiny-v02-piolite-r1-badges-20261128-overview")
    #change-end("tiny-v02-r1-weight-450-20261126-r1-product-line")
    #change-end("tiny-v02-pdk-highlights-20261125-overview-figures")
    #change-end("tiny-v02-r1-chip-alignment-20261125-r1-product-line")
    #change-end("tiny-v02-r1-reference-layout-20261125-r1-product-line")
    #change-end("tiny-v02-r1-compact-cards-20261125-r1-product-line")
    #change-end("tiny-v02-r1-product-cards-20261125-r1-product-line")
    #change-end("tiny-v02-r1-chip-marks-20261125-r1-product-line")
    #change-end("tiny-v02-r1-warm-yellow-20261125-r1-product-line")
    #change-end("tiny-v02-r1-product-line-20261124-r1-product-line")
  ]
  layout(size => {
    // Reserve the figure height after measuring the captions, highlights and spacing.
    let probe = block(width: 172mm, height: 40mm, above: 0pt, below: 0pt)
    let fixed-height = measure(plates(probe), width: size.width).height - 40mm
    let slot-height = size.height - fixed-height
    let art-offset = 2.1mm
    // Offset the plate and its layout anchor into the 3.2 mm side overhang.
    plates(block(width: 100%, height: slot-height, above: 0pt, below: 0pt, breakable: false)[
      #place(top + left, dx: -3.2mm, dy: art-offset, r1-product-line(slot-height + 3mm - art-offset))
    ])
  })
}
