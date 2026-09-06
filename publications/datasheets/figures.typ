#import "@preview/cetz:0.5.2"
#import "style.typ": ink, gold, pale-gold, gray, muted, data

// Coordinates are centimetres at final size. Text is never scaled down.
#let box(x, y, w, h, body, fill: gray) = {
  import cetz.draw: rect, content
  rect((x, y), (x + w, y + h), fill: fill, stroke: 0.6pt + ink, radius: 0.06)
  content((x + w / 2, y + h / 2), block(width: w * 1cm - 8pt)[
    #set text(size: 9pt)
    #set par(leading: 0.4em)
    #align(center, body)
  ])
}
#let wire(points, dashed: false) = {
  import cetz.draw: *
  line(..points, stroke: (paint: ink, thickness: 0.65pt,
    dash: if dashed { "dashed" } else { "solid" }), mark: (end: ">"))
}

#let product-diagram() = cetz.canvas({
  import cetz.draw: rect, content
  let top = 0
  for row in range(3) {
    let groups = data.overview_groups.slice(row * 3, row * 3 + 3)
    let height = calc.max(..groups.map(g => calc.ceil(g.items.len() / 2) * 1.0 + 0.95))
    for (column, group) in groups.enumerate() {
      let x = column * 5.7
      rect((x, top - height), (x + 5.35, top), stroke:0.6pt+gold, fill:white, radius:0.08)
      content((x + 2.675, top - 0.4), text(9.5pt, weight:"semibold", group.title))
      for (n, item) in group.items.enumerate() {
        let bx = x + 0.15 + calc.rem(n,2) * 2.575
        let by = top - 1.7 - calc.floor(n/2) * 1.0
        box(bx,by,2.475,0.9,item,fill:gray)
      }
    }
    top -= height + 0.3
  }
})

#let fabric-diagram() = cetz.canvas({
  box(0, 7.4, 4.8, 1.2, [*Hazard3 LP* \ AHB-Lite to AXI32], fill: pale-gold)
  box(6.1, 7.4, 4.8, 1.2, [*VexiiRiscv HP* \ I-cache / D-cache], fill: pale-gold)
  box(12.2, 7.4, 4.8, 1.2, [*Device masters* \ DMA · I/O A/B · JPEG · EXT-H])
  box(0, 4.9, 4.8, 1.35, [*LP management router* \ APB / MMIO control \ Memory via LP gateway])
  box(6.1, 4.9, 10.9, 1.35, [*AXI64 crossbar (HP domain)* \ Per-target read/write arbitration \ IDs · admission policy · fault capture], fill: pale-gold)
  wire(((2.4,7.4),(2.4,6.25)))
  wire(((8.5,7.4),(8.5,6.25)))
  wire(((14.6,7.4),(14.6,6.25)))
  wire(((4.8,5.65),(6.1,5.65)))
  box(0, 2.6, 4.8, 1.3, [*PCLK domain* \ APB4 peripheral island \ APB4 system island])
  box(6.1, 2.6, 4.8, 1.3, [*SRAM* \ Native AXI64 / ID6 \ HP clock domain])
  box(12.2, 2.6, 4.8, 1.3, [*Memory bridges* \ HP-to-memory CDC \ AXI64-to-32 adapters])
  wire(((2.4,4.9),(2.4,3.9)))
  wire(((8.5,4.9),(8.5,3.9)))
  wire(((14.6,4.9),(14.6,3.9)))
  box(6.1, 0.2, 10.9, 1.35, [*External memory targets* \ SDRAM x16 · QPI PSRAM · OPI/HyperBus-style · XPI \ QPI and OPI share pads; XPI data-plane access is read-only])
  wire(((14.6,2.6),(14.6,1.55)))
})

#let matrix-diagram() = cetz.canvas({
  import cetz.draw: *
  let names = ("HP I-cache", "HP D-cache", "Central DMA", "I/O gateway A", "I/O gateway B", "LP gateway", "JPEG", "EXT-H")
  let targets = ("SRAM", "SDRAM", "QPI", "OPI", "XPI")
  box(0, 6.9, 5, 0.85, [*Initiator / target*], fill: pale-gold)
  for (n,t) in targets.enumerate() { box(5 + n * 3.65, 6.9, 3.65, 0.85, text(weight:"semibold",t), fill:pale-gold) }
  for (n,p) in data.policies.enumerate() {
    let y = 6.9 - (n + 1) * 0.82
    box(0, y, 5, 0.82, names.at(n))
    for (j,t) in data.targets.enumerate() {
      let r = t in p.read_targets
      let w = t in p.write_targets
      box(5 + j * 3.65, y, 3.65, 0.82,
        if r and w { [R / W] } else if r { [R] } else if w { [W] } else { [-] },
        fill: if w { pale-gold } else { white })
    }
  }
})

#let clock-diagram() = cetz.canvas({
  box(0, 6, 4.8, 1.0, [*REF24 input* \ AON · 24 MHz], fill:pale-gold)
  box(6.1, 6, 4.8, 1.0, [*External safe clock* \ 72 MHz], fill:pale-gold)
  box(12.2, 6, 4.8, 1.0, [*Audio input* \ 18.432 MHz profile], fill:pale-gold)
  box(0, 3.6, 4.8, 1.35, [*LP root selection* \ Reset: REF24 \ Controlled division from HP])
  box(6.1, 3.6, 4.8, 1.35, [*HP safe selection* \ Reset: external 72 MHz \ Optional qualified PLL])
  box(12.2, 3.6, 4.8, 1.35, [*Audio domain* \ I2S · RTC · watchdog \ Independent CDC])
  wire(((2.4,6),(2.4,4.95)))
  wire(((8.5,6),(8.5,4.95)))
  wire(((14.6,6),(14.6,4.95)))
  wire(((6.1,4.3),(4.8,4.3)), dashed:true)
  box(0, 1.25, 4.8, 1.25, [*PCLK* \ LP divider: /1, /2, /4, /8, /16 \ APB4 register banks])
  box(6.1, 1.25, 4.8, 1.25, [*Memory root* \ External 72 MHz / 2 \ Stable 36 MHz root])
  box(12.2, 1.25, 4.8, 1.25, [*External domains* \ DVP pixel · ULPI · JTAG \ Domain reset synchronizers])
  wire(((2.4,3.6),(2.4,2.5)))
  wire(((8.5,5.55),(11.5,5.55),(11.5,1.875),(10.9,1.875)))
  cetz.draw.content((8.5,0.4), text(9pt, [Dashed: controlled/derived relationship. PLL is absent in the reference profile.]))
})

#let boot-diagram() = cetz.canvas({
  let stages = (
    [*Reset & LP startup* \ HP held in reset; LP owns root control],
    [*Validate boot bundle* \ Header, bounds, payload CRC and destination checks],
    [*Prepare HP memory* \ Configure SDRAM; DMA-copy and verify payloads],
    [*Publish boot mailbox* \ Entry, device tree and memory handoff; fences],
    [*Release HP* \ OpenSBI enters Linux; LP retains recovery authority],
  )
  for (n,s) in stages.enumerate() {
    let y = 8 - n * 1.8
    box(1.5, y, 14, 1.25, s, fill:if n==0 or n==4 { pale-gold } else { gray })
    if n < 4 { wire(((8.5,y),(8.5,y - 0.55))) }
  }
})

#let mpw-diagram() = cetz.canvas({
  box(0, 4, 5, 1.4, [*Management* \ Hazard3 \ Root boot / selection], fill:pale-gold)
  box(6, 4, 11, 1.4, [*C0-C3 selectable cores* \ kianV · SERV · FemtoRV32 · DarkRISCV \ One selected core at a time])
  box(0, 1.7, 17, 1.2, [*MPW compatibility integration* \ Selected RIBP core interface → AXI4 adapter → shared platform])
  wire(((2.5,4),(2.5,2.9)))
  wire(((11.5,4),(11.5,2.9)))
  box(0, -0.4, 8, 1.2, [*Shared platform* \ Memory, APB4 peripherals, SYSCTRL])
  box(9, -0.4, 8, 1.2, [*Selectable user IP* \ Slot 1 timer · slot 2 GPIO \ APB4 and user GPIO boundary])
  wire(((4,1.7),(4,0.8)))
  wire(((13,1.7),(13,0.8)))
})
