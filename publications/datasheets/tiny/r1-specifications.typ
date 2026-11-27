// Four comparative plates share one set of column, chip and row coordinates.
#import "style.typ": ink, muted
#import "feature-highlights.typ": r1-chip, r1-chip-size, chip-native-size

#let r1-specification-plate(specs, key, book: false) = context {
  set align(left + top)
  set text(font: "Inter", size: 9pt, weight: "regular", fill: ink,
    top-edge: "cap-height", bottom-edge: "descender")
  set par(leading: 2.1pt, spacing: 0pt, justify: false)
  set block(above: 0pt, below: 0pt, breakable: false)
  let topic = specs.topics.find(s => s.key == key)
  let plate-height = 247mm
  let panel-width = 85mm
  let panel-top = 20mm
  let panel-height = 205mm
  let row-top = 57.5mm
  let cell-width = r1-chip-size
  let pitch = 28mm
  let accent = (rgb("#883ACF"), rgb("#A77A20"))
  let small-ink = (rgb("#7631B4"), rgb("#806019"))
  let panel-fill = gradient.linear(rgb("#F2F2F3"), rgb("#E9E9EB"), angle: 90deg)
  let at(x, y, item) = place(top + left, dx: x, dy: y, item)
  let column(i) = 1.25mm + calc.rem(i, 3) * pitch
  let title = text(size: 24pt, weight: "bold", "R1 Family · " + topic.title)
  let title-block = if book {[
    #show heading: h => title
    #heading(level: 3, topic.title)#label("tiny-family-" + key)
  ]} else {title}
  let tidy(s) = s.replace(regex(" (KiB|MiB|GiB|GB/s|TB/s|GB)\\b"), match => " " + match.captures.first())
  let entry(cell, prominent, color) = {
    let big = prominent and type(cell.value) in (int, float)
    let value = text(size: if big {21pt} else {9.4pt},
      weight: if big {"bold"} else {"medium"}, fill: if big {color} else {ink}, tidy(cell.display))
    let suffix = if cell.state == "target" { text(size: 9pt, weight: "regular", " target") }
    block(width: cell-width, inset: (x: 0.3mm), align(center, [
      #value#suffix#if "note" in cell { linebreak(); text(size: 9pt, fill: muted, cell.note) }
    ]))
  }
  let products = specs.products
  let rows = topic.metrics.map(id => {
    let metric = specs.metrics.at(id)
    let entries = products.enumerate().map(((i, p)) =>
      entry(metric.cells.at(p.name), metric.emphasis, accent.at(calc.div-euclid(i, 3))))
    let height = calc.max(..entries.map(v => measure(v).height))
    (id: id, label: upper(metric.label), entries: entries, height: 5mm + height)
  })
  let spare = panel-height - 2.2mm - row-top - rows.map(r => r.height).sum()
  assert(spare >= 0mm, message: "Specification rows exceed " + key + " by " + repr(-spare))
  let space = spare / rows.len()
  let footer = block(width: 172mm, inset: (x: 1mm), stack(dir: ttb, spacing: 1mm,
    ..topic.notes.map(s => text(size: 9pt, fill: muted, s)),
    text(size: 9pt, weight: "semibold", fill: ink, "target = planned   ·   TBD = to be defined   ·   None = unit absent")))
  assert(measure(footer).height <= plate-height - panel-top - panel-height - 2.5mm,
    message: "R1 specification footnotes exceed " + key)
  [#block(width: 172mm, height: plate-height)[
    #metadata(r1-chip-size / chip-native-size)<tiny-spec-chip-scale>
    #at(0mm, 0mm, title-block)
    #at(0mm, 11.3mm, text(size: 10pt, fill: muted, "Product planning draft · Maximum configurations shown where defined"))
    #if book {at(153mm, 11.3mm, block(width: 19mm, align(right, text(size: 9pt, fill: muted,
      [Table #counter(figure.where(kind: table)).display()]))))}
    #for group in range(2) {
      let x = group * 87mm
      at(x, panel-top, block(width: panel-width, height: panel-height, fill: panel-fill, radius: 3.5mm))
      at(x + 2.3mm, panel-top + 4.1mm, text(size: 18pt, weight: "bold", fill: accent.at(group),
        ("Embedded & Edge", "Professional Compute").at(group)))
      for j in range(3) {
        let i = group * 3 + j
        let p = products.at(i)
        let chip = [#block(width: r1-chip-size, height: r1-chip-size)[#place(top + left, r1-chip(p))]<tiny-spec-chip>]
        at(x + column(j), panel-top + 15.5mm, chip)
        let role = block(width: cell-width, inset: (x: 0.4mm), align(center, text(size: 9.6pt, weight: "semibold", p.positioning)))
        assert(measure(role).height <= 13mm, message: "R1 positioning exceeds " + p.name)
        at(x + column(j), panel-top + 44.3mm, role)
      }
      let y = panel-top + row-top
      for row in rows {
        if book {
          at(x + 2mm, y, context metadata((kind: "r1-spec-row", topic: key, metric: row.id,
            group: group, page: here().page(), top: here().position().y.pt())))
        }
        at(x + 2mm, y, text(size: 10pt, weight: "bold", fill: small-ink.at(group), row.label))
        at(x + 2mm, y + 3.7mm, line(length: panel-width - 4mm, stroke: 0.4pt + rgb("#A8AAAD")))
        for j in range(3) { at(x + column(j), y + 5mm, row.entries.at(group * 3 + j)) }
        y += row.height + space
      }
    }
    #at(0mm, panel-top + panel-height + 2.5mm, footer)
  ]<tiny-spec-plate>]
}
