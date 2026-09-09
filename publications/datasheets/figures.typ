#import "@preview/cetz:0.5.2"
#import "diagram-packages.typ": circuit-diagram
#import "style.typ": ink, gold, pale-gold, gray, muted, data, rhythm

// Coordinates are centimetres at final size. Text is never scaled down.
#let box(x, y, w, h, body, fill: gray) = {
  import cetz.draw: rect, content
  rect((x, y), (x + w, y + h), fill: fill, stroke: 0.6pt + ink, radius: 0.06)
  content((x + w / 2, y + h / 2), block(width: w * 1cm - 8pt)[
    #set text(size: 9pt)
    #set par(leading: rhythm.diagram-leading)
    #align(center, body)
  ])
}
#let wire(points, dashed: false) = {
  import cetz.draw: *
  line(..points, stroke: (paint: ink, thickness: 0.65pt,
    dash: if dashed { "dashed" } else { "solid" }), mark: (end: ">"))
}

#let product-diagram() = cetz.canvas({
  import cetz.draw: rect, content, line, circle
  // Overview-only drawing helpers; other engineering figures retain their style.
  let category-icon(kind, x, y) = {
    let pen = 0.6pt + gold
    if kind == 0 {
      rect((x - 0.11,y - 0.11),(x + 0.11,y + 0.11),stroke:pen)
      for d in (-0.065,0.065) {
        line((x + d,y - 0.18),(x + d,y - 0.11),stroke:pen)
        line((x + d,y + 0.11),(x + d,y + 0.18),stroke:pen)
        line((x - 0.18,y + d),(x - 0.11,y + d),stroke:pen)
        line((x + 0.11,y + d),(x + 0.18,y + d),stroke:pen)
      }
    } else if kind == 1 {
      for d in (-0.11,0,0.11) {
        rect((x - 0.16,y + d - 0.035),(x + 0.16,y + d + 0.035),stroke:pen)
      }
    } else if kind == 2 {
      for (n,d) in (-0.12,0,0.12).enumerate() {
        line((x - 0.17,y + d),(x + 0.17,y + d),stroke:pen)
        circle((x + if n == 1 {0.07} else {-0.06},y + d),radius:0.04,fill:pale-gold,stroke:pen)
      }
    } else if kind == 3 {
      rect((x - 0.17,y + 0.01),(x - 0.01,y + 0.15),stroke:pen)
      rect((x + 0.01,y - 0.15),(x + 0.17,y - 0.01),stroke:pen)
      line((x - 0.09,y + 0.01),(x - 0.09,y - 0.08),(x + 0.01,y - 0.08),stroke:pen)
      line((x + 0.09,y - 0.01),(x + 0.09,y + 0.08),(x - 0.01,y + 0.08),stroke:pen)
    } else if kind == 4 {
      line((x - 0.17,y + 0.08),(x + 0.17,y + 0.08),(x + 0.10,y + 0.15),stroke:pen)
      line((x + 0.17,y - 0.08),(x - 0.17,y - 0.08),(x - 0.10,y - 0.15),stroke:pen)
    } else if kind == 5 {
      circle((x,y),radius:0.17,stroke:pen)
      line((x,y + 0.11),(x,y),(x + 0.09,y - 0.04),stroke:pen)
    } else if kind == 6 {
      rect((x - 0.10,y - 0.12),(x + 0.10,y + 0.10),stroke:pen)
      line((x - 0.06,y + 0.10),(x - 0.06,y + 0.18),stroke:pen)
      line((x + 0.06,y + 0.10),(x + 0.06,y + 0.18),stroke:pen)
      line((x,y - 0.12),(x,y - 0.19),(x + 0.16,y - 0.19),stroke:pen)
    } else if kind == 7 {
      rect((x - 0.18,y - 0.13),(x + 0.18,y + 0.13),stroke:pen,radius:0.03)
      line((x - 0.05,y - 0.075),(x + 0.075,y),(x - 0.05,y + 0.075),(x - 0.05,y - 0.075),stroke:pen)
    } else {
      line((x - 0.15,y + 0.12),(x,y + 0.17),(x + 0.15,y + 0.12),
        (x + 0.12,y - 0.07),(x,y - 0.18),(x - 0.12,y - 0.07),(x - 0.15,y + 0.12),stroke:pen)
    }
  }
  let panel(index, x, top, w, h, row-counts, weights:none) = {
    let group = data.overview_groups.at(index)
    assert(row-counts.sum() == group.items.len(),message:"Overview layout must include every IP once")
    let weights = if weights == none { row-counts.map(n => 1) } else { weights }
    rect((x,top - h),(x + w,top),fill:white,stroke:0.55pt + muted,radius:0.10)
    rect((x + 0.035,top - 0.65),(x + w - 0.035,top - 0.035),fill:pale-gold,stroke:none,radius:0.07)
    category-icon(index,x + 0.38,top - 0.335)
    content((x + 0.72 + (w - 0.92)/2,top - 0.335),block(width:(w - 0.92)*1cm)[
      #align(left,text(9.5pt,weight:"semibold",group.title))
    ])
    let available = h - 1.05 - (row-counts.len() - 1)*0.10
    let cell-top = top - 0.85
    let first = 0
    for (r,count) in row-counts.enumerate() {
      let height = available*weights.at(r)/weights.sum()
      let width = (w - 0.40 - (count - 1)*0.10)/count
      for column in range(count) {
        let bx = x + 0.20 + column*(width + 0.10)
        let item = group.items.at(first + column)
        let fill = if index == 0 and first + column < 2 {pale-gold} else {gray}
        rect((bx,cell-top - height),(bx + width,cell-top),fill:fill,stroke:0.5pt + muted,radius:0.10)
        content((bx + width/2,cell-top - height/2),block(width:width*1cm - 6pt)[
          #set text(size:9pt)
          #set par(leading:rhythm.inventory-leading)
          #align(center,item)
        ])
      }
      first += count
      cell-top -= height + 0.10
    }
  }
  rect((0,0),(17.2,-16.4),fill:white,stroke:0.85pt + ink,radius:0.20)
  line((0.4,-0.29),(2.7,-0.29),stroke:1.4pt + gold)
  content((7.1,-0.86),block(width:13cm)[
    #align(left,text(12pt,weight:"semibold",data.document.title))
  ])
  category-icon(0,16.4,-0.83)
  line((0.4,-1.45),(16.8,-1.45),stroke:0.45pt + muted)
  let w = (16.4 - 0.6)/3
  panel(0,0.4,-1.7,w,4.0,(2,1),weights:(2,1))
  panel(1,0.4 + w + 0.3,-1.7,w,4.0,(2,2,1))
  panel(2,0.4 + 2*(w + 0.3),-1.7,w,4.0,(2,2,1))
  panel(3,0.4,-6.0,w,4.0,(2,2))
  panel(4,0.4 + w + 0.3,-6.0,w,4.0,(1,1,1))
  panel(5,0.4 + 2*(w + 0.3),-6.0,w,4.0,(2,2,1))
  panel(6,0.4,-10.3,2*w + 0.3,5.5,(3,3,3,2))
  panel(7,0.4 + 2*(w + 0.3),-10.3,w,2.9,(2,2))
  panel(8,0.4 + 2*(w + 0.3),-13.5,w,2.3,(3,))
})

#let fabric-diagram() = circuit-diagram("system-fabric")

#let matrix-diagram() = cetz.canvas({
  import cetz.draw: *
  let names = ("HP I-cache", "HP D-cache", "Central DMA", "I/O gateway A", "I/O gateway B", "LP gateway", "JPEG", "EXT-H")
  let targets = ("SRAM", "SDRAM", "QPI", "OPI", "XPI")
  let initiator-width = 4.5
  let target-width = 2.54
  box(0, 6.9, initiator-width, 0.85, [*Initiator / target*], fill: pale-gold)
  for (n,t) in targets.enumerate() { box(initiator-width + n * target-width, 6.9, target-width, 0.85, text(weight:"semibold",t), fill:pale-gold) }
  for (n,p) in data.policies.enumerate() {
    let y = 6.9 - (n + 1) * 0.82
    box(0, y, initiator-width, 0.82, names.at(n))
    for (j,t) in data.targets.enumerate() {
      let r = t in p.read_targets
      let w = t in p.write_targets
      box(initiator-width + j * target-width, y, target-width, 0.82,
        if r and w { [R / W] } else if r { [R] } else if w { [W] } else { [-] },
        fill: if w { pale-gold } else { white })
    }
  }
})

#let clock-diagram() = circuit-diagram("system-clocks")

#let boot-diagram() = cetz.canvas({
  let stages = (
    [*Reset & LP startup* \ HP held in reset; LP owns root control],
    [*Check prerequisites* \ Confirm HP reset and SDRAM readiness; validate bundle header and bounds],
    [*Load HP memory* \ DMA-copy with CRC; software-copy/CRC fallback on failure],
    [*Order and release* \ Fence; clear LP mailbox interrupt; request HP release],
    [*Observe readiness* \ OpenSBI enters Linux; LP waits for the expected mailbox event],
  )
  for (n,s) in stages.enumerate() {
    let y = 8 - n * 1.8
    box(1.5, y, 14, 1.25, s, fill:if n==0 or n==4 { pale-gold } else { gray })
    if n < 4 { wire(((8.5,y),(8.5,y - 0.55))) }
  }
})

#let mpw-diagram() = circuit-diagram("system-mpw")
