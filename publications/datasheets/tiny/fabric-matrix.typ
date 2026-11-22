#import "@preview/cetz:0.5.2": canvas, draw
#import "style.typ": gold, gray, ink, rhythm, rule

#let xy(point) = (point.at(0), -point.at(1))

#let fabric-matrix-plate(record) = {
  let plate = record.fabric_matrix
  let outline = 0.6pt + ink
  let matrix = record.nodes.find(node => node.id == "fabric")
  let sram = record.nodes.find(node => node.id == "sram")
  set text(font: "Inter", size: 9pt, fill: ink, weight: "regular")
  canvas(length: 1mm, {
    draw.rect((0, 0), (plate.width_mm, -plate.height_mm), fill: white, stroke: none)
    draw.rect((0.4, -0.4), (plate.width_mm - 0.4, 0.4 - plate.height_mm), stroke: outline)
    for node in record.nodes {
      let (x, y, w, h) = (node.x, node.y, node.w, node.h)
      draw.rect((x, -y), (x + w, -y - h),
        fill: if node.id in ("fabric", "sram") { white } else { gray }, stroke: outline)
      if node.id not in ("fabric", "sram") {
        draw.content((x + w / 2, -y - h / 2), block(width: (w - 1.4) * 1mm)[
          #set par(leading: rhythm.small-leading, spacing: 0pt)
          #align(center, node.title.split("\n").map(text).join(linebreak()))
        ])
      }
    }

    let bottom = matrix.y + matrix.h - 2.5
    let east = matrix.x + matrix.w
    draw.rect((matrix.x + 0.4, -matrix.y - 0.4), (plate.matrix_left_rail - 1, -bottom), fill: gray, stroke: none)
    for column in plate.columns {
      draw.line((column.x, -matrix.y), (column.x, -bottom), stroke: 0.65pt + ink)
      draw.content((column.x + 2.2, 3.8 - matrix.y), text("Owner " + str(column.owner)), anchor: "west")
    }
    for row in plate.rows {
      draw.content((matrix.x + 3, -row.y), text(row.title), anchor: "west")
      draw.line((plate.matrix_left_rail, -row.y), (east, -row.y), stroke: 0.65pt + ink)
    }
    for point in plate.crosspoints {
      draw.circle(xy(point), radius: 0.86mm, fill: white, stroke: 0.55pt + ink)
    }
    draw.content((matrix.x + 3, -matrix.y - 3.7), text(weight: "semibold", matrix.title), anchor: "west")
    draw.content((matrix.x + 3, -matrix.y - 8.0),
      text(str(plate.data_width) + "-bit data / " + str(plate.id_width) + "-bit ID"), anchor: "west")

    let sram-east = sram.x + sram.w
    for port in sram.ports.filter(p => p.side == "north") {
      draw.content((sram.x + sram.w * port.position, -sram.y - 2.7), text(upper(port.id)))
    }
    draw.content((sram.x + sram.w / 2, -sram.y - 7.0),
      text(weight: "semibold", "Main SRAM · " + str(plate.sram_kib) + " KiB · SYS"))
    for row in plate.rows.filter(r => r.port.starts-with("b")) {
      draw.line((sram.x, 3 - row.y), (sram-east, 3 - row.y), stroke: 0.55pt + rule)
      draw.content((sram.x + 3, -row.y), text(upper(row.port)), anchor: "west")
      draw.content((sram-east - 3, -row.y), text(str(plate.group_kib) + " KiB"), anchor: "east")
    }

    for wire in plate.wires {
      let stroke = if wire.local { 1.4pt + gold } else { plate.routing.stroke_pt * 1pt + ink }
      draw.line(..wire.points.map(xy), stroke: stroke)
    }
    for (x, y) in plate.terminals {
      draw.rect((x - 0.78, 0.78 - y), (x + 0.78, -0.78 - y), fill: white, stroke: 0.5pt + ink)
    }
    for wire in plate.wires {
      for head in wire.heads {
        draw.line(..head.map(xy), close: true, fill: if wire.local { gold } else { ink }, stroke: none)
      }
    }
    for label in plate.labels {
      draw.content(xy(label.at), text(label.title), anchor: label.anchor)
    }
  })
}
