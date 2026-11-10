#import "@preview/cetz:0.5.2" as cetz
#import "diagrams.typ": diagram
#import "style.typ": data, ink, gold, muted, rhythm

#let point(x, y) = (x, -y)
#let domain-fill = (
  system: rgb("#E5ECF3"),
  aon: rgb("#F4EFE4"),
  memory: rgb("#ECE8F3"),
  peripheral: rgb("#E8EFE5"),
  jtag: rgb("#E7F1EF"),
  audio: rgb("#F5E8E8"),
  dvp_pixel: rgb("#F5ECDE"),
)

#let functional-canvas(spec) = cetz.canvas(length: 1mm, {
  import cetz.draw: rect, line, content
  rect(point(0, 0), point(spec.width_mm, spec.height_mm), fill: none, stroke: none)
  for panel in spec.panels {
    rect(point(panel.x, panel.y), point(panel.x + panel.w, panel.y + panel.h),
      fill: domain-fill.at(panel.domain), stroke: none)
    if "label" in panel {
      content(point(panel.x + 1.5, panel.at("label_y", default: panel.y + 0.75)),
        text(font: "Inter", size: 9pt, weight: 700, fill: ink, panel.label), anchor: "north-west")
    }
  }
  // The collector checks and supplies every endpoint and arrowhead in millimetres.
  for route in spec.routes {
    let paint = if route.kind == "stream" { muted } else { ink }
    let thickness = spec.routing.stroke_pt * 1pt
    line(..route.points.map(p => point(..p)),
      stroke: (paint: paint, thickness: thickness, dash: if route.kind == "control" { "dashed" } else { "solid" }))
    for head in route.heads {
      line(..head.map(p => point(..p)), stroke: thickness + paint)
    }
  }
  for node in spec.nodes {
    let rail = node.role == "rail"
    rect(point(node.x, node.y), point(node.x + node.w, node.y + node.h),
      fill: if rail { rgb("#D5D6D8") } else { white },
      stroke: 0.6pt + if node.role == "bridge" { gold } else { ink })
    if node.label != "" {
      let rotate = node.at("rotate", default: false)
      let width = (if rotate { node.h } else { node.w }) * 1mm - 2pt
      let height = (if rotate { node.w } else { node.h }) * 1mm
      let body = block(width: width, above: 0pt, below: 0pt)[
        #set text(font: "Inter", size: 9pt, weight: if rail { 700 } else { 400 }, fill: ink)
        #set par(leading: 1.5pt, spacing: 0pt)
        #align(center, node.label.split("\n").map(text).join(linebreak()))
      ]
      content(point(node.x + node.w / 2, node.y + node.h / 2), context {
        assert(measure(body).height <= height, message: "Tiny functional figure label overflows: " + node.id)
        body
      }, angle: if rotate { 90deg } else { 0deg })
    }
  }
  for route in spec.routes {
    if "label" in route {
      let label = route.label
      content(point(label.x, label.y),
        box(fill: white, inset: (x: 1pt, y: 0pt), text(font: "Inter", size: 9pt, fill: ink, label.text)))
    }
  }
  for pins in spec.pin_labels {
    if "leader" in pins {
      line(..pins.leader.map(p => point(..p)), stroke: 0.6pt + muted)
    }
    content(point(pins.x, pins.y), block(width: pins.width * 1mm, above: 0pt, below: 0pt)[
      #set text(font: "Inter", size: 9pt, fill: ink)
      #set par(leading: 1.5pt, spacing: 0pt)
      #align(center, pins.text.split("\n").map(text).join(linebreak()))
    ])
  }
})

#let functional-architecture() = diagram("tiny-soc-functional", [
  #functional-canvas(data.illustrations.functional)
  #v(3pt)
  #set text(font: "Inter", size: 9pt, fill: muted)
  #set par(leading: rhythm.small-leading, spacing: 0pt)
  #align(center)[Solid arrows show bus or payload routes. Gray arrows show media streams. Dashed arrows show control and debug routes.
    Numbers identify AXI owners. Each APB4 target has an independent branch. Signal groups label external interfaces.
    AF and asterisks mark GPIO alternate functions.]
], [Tiny functional architecture, clock domains and initiator paths.])
