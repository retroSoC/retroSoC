// Calendar offsets come from the publication collector and are measured in quarters.
#import "@preview/cetz:0.5.2" as cetz
#import "style.typ": gold, pale-gold, ink, muted, rule
#import "feature-highlights.typ": chip-native-size, detail-ink, r1-chip, r1-chip-size

#let r1-roadmap(data) = context {
  let date-ink = color.mix((gold, 60%), (ink, 40%), space: rgb)
  let planned = (paint: gold, thickness: 1pt, dash: "dashed")
  let solid = 1.25pt + gold
  let header = 10.5
  let lane = 29
  let axis-left = 2
  let xq(offset) = axis-left + offset * 12
  let right = xq(data.quarters.len())
  let row-top(i) = header + i * lane
  let rail-y(i) = row-top(i) + 27.9
  let xy(x, y) = (x, -y)
  let lettering(value, weight: 500, fill: ink) = box(text(
    font: "Inter", size: 9pt, weight: weight, fill: fill,
    top-edge: "cap-height", bottom-edge: "descender", value))
  let at(x, y, body) = place(top + left, dx: x * 1mm, dy: y * 1mm, body)
  let chip-mm = r1-chip-size / 1mm
  assert(right == 170 and data.products.len() == 6, message: "Review the R1 roadmap plate for the new axis or tiers")

  let grid-and-rails = cetz.canvas(length: 1mm, {
    import cetz.draw: rect, line, circle, content
    let centered(x, y, value, weight) = content(xy(x, y), lettering(value, weight: weight, fill: detail-ink))
    let diamond(x, y) = line(xy(x, y - 0.75), xy(x + 0.75, y), xy(x, y + 0.75), xy(x - 0.75, y),
      close: true, stroke: none, fill: gold)
    rect(xy(0, 0), xy(172, 190), fill: white, stroke: none)
    rect(xy(axis-left, 0), xy(right, 5.3), fill: gold, stroke: none)
    rect(xy(axis-left, 5.3), xy(right, header), fill: pale-gold, stroke: none)
    for (i, quarter) in data.quarters.enumerate() {
      let x = xq(i)
      let year-start = i == 0 or data.quarters.at(i - 1).year != quarter.year
      if year-start {
        let year-span = data.quarters.filter(q => q.year == quarter.year).len()
        centered(x + 6 * year-span, 2.65, str(quarter.year), 700)
      }
      centered(x + 6, 7.9, quarter.label, 600)
      if i > 0 {
        if year-start { line(xy(x, 0), xy(x, 5.3), stroke: 0.35pt + pale-gold) }
        line(xy(x, 5.3), xy(x, header), stroke: 0.35pt + gold)
        line(xy(x, header), xy(x, row-top(data.products.len())), stroke: (paint: rule, thickness: 0.4pt, dash: "dashed"))
      }
    }
    for (i, p) in data.products.enumerate() {
      let y = rail-y(i)
      let a = xq(p.start_offset)
      let b = xq(p.end_offset)
      line(xy(axis-left, row-top(i + 1)), xy(right, row-top(i + 1)), stroke: 0.35pt + rule)
      line(xy(a, y), xy(b, y), stroke: if p.observed { solid } else { planned })
      line(xy(a, y - 0.65), xy(a, y + 0.65), stroke: 0.75pt + gold)
      if p.observed {
        circle(xy(b, y), radius: 0.65mm, fill: white, stroke: 0.9pt + gold)
      } else {
        line(xy(b, y - 0.65), xy(b, y + 0.65), stroke: 0.75pt + gold)
      }
      if p.milestone != none {
        diamond(xq(p.milestone.offset), y)
        diamond(b + 3.25, row-top(i) + 13.65)
      }
    }
    line(xy(2, 187.5), xy(9, 187.5), stroke: solid)
    circle(xy(9, 187.5), radius: 0.65mm, fill: white, stroke: 0.9pt + gold)
    content(xy(11, 187.5), lettering("Recorded development"), anchor: "west")
    line(xy(58, 187.5), xy(65, 187.5), stroke: planned)
    content(xy(67, 187.5), lettering("Planned window"), anchor: "west")
    diamond(106, 187.5)
    content(xy(109, 187.5), lettering("Milestone"), anchor: "west")
    content(xy(right, 187.5), lettering("As of " + data.as_of), anchor: "east")
  })

  let information(p, width) = {
    let title = lettering(p.at("short_title", default: p.positioning), weight: 650, fill: detail-ink)
    let focus = lettering(p.focus, weight: 400)
    let period = lettering(p.period, weight: 600, fill: date-ink)
    let state = lettering(p.status, fill: muted)
    for item in (title, focus, period, state) {
      assert(measure(item).width <= width - 3mm, message: "R1 roadmap card exceeds its column: " + p.name)
    }
    block(width: width, height: 21.5mm, radius: 1.35mm, above: 0pt, below: 0pt,
      fill: pale-gold, stroke: if p.observed { none } else {
        (paint: gold, thickness: 0.5pt, dash: "dashed")
      })[
      #at(1.5, 1.9, title)
      #at(1.5, 6.6, focus)
      #at(1.5, 12, if p.source_url == none { period } else { link(p.source_url, period) })
      #at(1.5, 16.6, state)
    ]
  }
  [#block(width: 172mm, height: 190mm, above: 0pt, below: 0pt, breakable: false)[
    #show underline: it => it.body
    #metadata(r1-chip-size / chip-native-size)<tiny-roadmap-chip-scale>
    #at(0, 0, grid-and-rails)
    #for (i, p) in data.products.enumerate() {
      let chip-right = xq(p.end_offset)
      let chip-left = chip-right - chip-mm
      let chip-top = row-top(i) + 0.4
      let width = calc.min(55, chip-left - axis-left - 0.5)
      at(chip-left - 0.5 - width, chip-top + (chip-mm - 21.5) / 2, information(p, width * 1mm))
      at(chip-left, chip-top, [#block(width: r1-chip-size, height: r1-chip-size, above: 0pt, below: 0pt)[
        #place(top + left, r1-chip(p))
      ]<tiny-roadmap-chip-region>])
      if p.milestone != none {
        let event = p.milestone
        at(chip-right + 5, row-top(i) + 7.35, block(width: 42mm, height: 12.6mm,
          inset: 0pt, radius: 1.3mm, fill: white, stroke: 0.45pt + gold, above: 0pt, below: 0pt)[
          #at(1.6, 1.9, lettering(event.label, weight: 600))
          #at(1.6, 7, link(event.url, lettering(event.date + " · " + event.quarter.split(" ").last(), fill: date-ink)))
        ])
      }
    }
  ]<tiny-r1-roadmap-region>]
}
