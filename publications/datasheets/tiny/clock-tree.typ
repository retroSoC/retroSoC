#import "@preview/cetz:0.5.2": canvas, draw
#import "style.typ": gold, pale-gold, gray, muted, ink, rhythm

#let xy(p) = (p.at(0), -p.at(1))
#let signal-ink(kind) = if kind == "clock" { ink } else { muted }

#let clock-tree-plate(record) = {
  let plate = record.clock_tree
  let outline = 0.6pt + ink
  set text(font: "Inter", size: 9pt, fill: ink, weight: "regular")
  canvas(length: 1mm, {
    draw.rect((0, 0), (plate.width_mm, -plate.height_mm), fill: white, stroke: none)
    draw.rect((0.4, -0.4), (plate.width_mm - 0.4, 0.4 - plate.height_mm), stroke: outline)
    for group in plate.groups {
      let (x, y, w, h) = (group.x, group.y, group.w, group.h)
      if group.role == "conditional" {
        draw.rect((x, -y), (x + w, -y - h),
          stroke: (paint: gold, thickness: 0.8pt, dash: "dashed"))
        draw.content((x + w / 2, -y - 3),
          box(fill: pale-gold, inset: (x: 3pt), text(weight: "semibold", group.title)))
      } else {
        draw.rect((x, -y), (x + w, -y - h), fill: gray, stroke: none)
      }
    }
    for wire in plate.segments {
      let stroke = if wire.kind == "clock" { plate.routing.stroke_pt * 1pt + ink } else {
        (paint: muted, thickness: plate.routing.stroke_pt * 1pt, dash: "dashed")
      }
      draw.line(..wire.points.map(xy), stroke: stroke)
    }
    for node in record.nodes {
      let (x, y, w, h) = (node.x, node.y, node.w, node.h)
      if node.shape == "mux" {
        draw.line((x, -y), (x + w, -y - 3), (x + w, -y - h + 3), (x, -y - h),
          close: true, fill: gray, stroke: outline)
      } else if node.shape == "gate" {
        draw.line((x, -y), (x + 0.54 * w, -y), (x + 0.86 * w, -y - 0.19 * h),
          (x + w, -y - h / 2), (x + 0.86 * w, -y - 0.81 * h), (x + 0.54 * w, -y - h),
          (x, -y - h), close: true, fill: gray, stroke: outline)
      } else if node.shape == "block" {
        draw.rect((x, -y), (x + w, -y - h), fill: gray, stroke: outline)
      } else if node.shape == "pin" {
        draw.rect((x + w - 2.4, -y - h / 2 + 1.2), (x + w, -y - h / 2 - 1.2),
          fill: white, stroke: outline)
      } else if node.shape == "tap" {
        draw.line((x, -y), (x + w - 2, -y), (x + w, -y - h / 2), (x + w - 2, -y - h),
          (x, -y - h), close: true, stroke: outline, fill: white)
      }
      let lines = node.title.split("\n")
      let body = lines.enumerate().map(((i, line)) =>
        if i == 0 and "domain" in node { text(weight: "semibold", line) } else { text(line) }
      ).join(linebreak())
      let at-left = node.shape in ("pin", "sink")
      let available = w - if node.shape == "pin" { 3.5 } else { 1.4 }
      let text-x = x + if at-left { 0.8 } else { w / 2 - if node.shape == "tap" { 0.5 } else { 0 } }
      draw.content((text-x, -y - h / 2), block(width: available * 1mm)[
        #set par(leading: rhythm.small-leading, spacing: 0pt)
        #align(if at-left { left } else { center }, body)
      ], anchor: if at-left { "west" } else { "center" })
    }
    for arrow in plate.arrows {
      draw.line(..arrow.points.map(xy), close: true, fill: signal-ink(arrow.kind), stroke: none)
    }
    for join in plate.junctions {
      draw.circle(xy(join.point), radius: 0.68mm, fill: signal-ink(join.kind), stroke: none)
    }
    for label in plate.labels {
      draw.content(xy(label.at), text(label.title), anchor: label.anchor)
    }
  })
}
