// Carrier, reel, carton and reflow reference plates for the Tiny package section.
#import "@preview/cetz:0.5.2" as cetz
#import "../../specifications/figures.typ": ink, gray
#import "../../specifications/components.typ": use-record
#import "package-figures.typ": point, write-at, face, view-title, reference-label, mm-note, horizontal, vertical, outline, projection, centerline, dimension, extension, metal, pin-mark, symbol

#let record(spec, key) = spec.records.find(r => r.id == "tiny." + key)
#let symbol-for(spec, r) = r.at("symbols", default: ()).map(s => symbol(spec, s)).join(text(" / "))
#let value(r) = {
  if r.value == none { return [TBD] }
  let amount = if type(r.value) == dictionary {
    let v = r.value
    if v.typ != none { str(v.typ) }
    else if v.min == none { [≤ #v.max] }
    else if v.max == none { [≥ #v.min] }
    else { [#v.min–#v.max] }
  } else if "decimals" in r {
    let parts = str(r.value).split(".")
    let fraction = parts.at(1, default: "")
    parts.first() + "." + fraction + "0" * calc.max(0, r.decimals - fraction.len())
  } else { str(r.value) }
  [#amount#if r.unit != "1" { [ #r.unit] }]
}
#let marked-value(r) = use-record(r, value(r))
#let dimension-label(spec, r) = [#symbol-for(spec, r) #marked-value(r)]

#let assembly-reference-table(spec, group, table-renderer) = {
  let rows = spec.records.filter(r => r.group == group)
  if group == "reflow" { rows.push(record(spec, "assembly.msl")) }
  if group == "reel-box" { rows = (record(spec, "reel.quantity"),) + rows }
  let title = spec.groups.find(g => g.id == group).title
  table-renderer("spec-" + group, [#title],
    ([Symbol], [Parameter], [Reference value #linebreak() REFERENCE ONLY], [Tiny product]),
    rows.map(r => (
      if "symbols" in r { symbol-for(spec, r) } else { [—] },
      r.meaning,
      if r.status == "reference" { marked-value(r) } else { [—] },
      if r.status == "reference" { [—] } else { marked-value(r) },
    )),
    widths: (0.78fr, 2.53fr, 1.12fr, 0.72fr))
}

#let plate-header(title, source) = {
  reference-label(5, 6, anchor: "west")
  view-title(86, 6, title)
  write-at(167, 6, source, anchor: "east")
}
#let center-mark(x, y, radius) = {
  cetz.draw.line(point(x - radius, y), point(x + radius, y), stroke: centerline)
  cetz.draw.line(point(x, y - radius), point(x, y + radius), stroke: centerline)
}

#let carrier-tape(spec) = {
  set text(font: "Inter", size: 9pt, fill: ink)
  let width = record(spec, "carrier-tape.width")
  let pocket-width = record(spec, "carrier-tape.pocket-width")
  let pocket-length = record(spec, "carrier-tape.pocket-length")
  let pitch = record(spec, "carrier-tape.pocket-pitch")
  let depth = record(spec, "carrier-tape.pocket-depth")
  let orientation = record(spec, "carrier-tape.orientation")
  let scale = 2.4
  let tape-top = 26
  let tape-bottom = tape-top + width.value * scale
  let pocket-y = 48.4
  let tape-end = 135
  let pocket-centers = range(4).map(n => 29 + n * pitch.value * scale)
  let half-x = pocket-width.value * scale / 2
  let half-y = pocket-length.value * scale / 2
  let quadrants = (Q1: (-1, -1), Q2: (1, -1), Q3: (-1, 1), Q4: (1, 1))
  let (qx, qy) = quadrants.at(orientation.value)
  cetz.canvas(length: 1mm, {
    face(172, 137)
    plate-header([Carrier tape], [TI TUSB8041IRGCR])
    write-at(14, 15, strong[Tape top view], anchor: "west")
    write-at(28, 21, [Sprocket holes], anchor: "west")
    write-at(115, 15, [User direction of feed])
    cetz.draw.line(point(101, 20.5), point(129, 20.5), stroke: dimension, mark: (end: "stealth"))
    cetz.draw.rect(point(14, tape-top), point(tape-end, tape-bottom), stroke: outline, fill: white)
    for x in range(12).map(i => 20 + i * 10) {
      cetz.draw.circle(point(x, 30.8), radius: 1.55mm, fill: none, stroke: outline)
    }
    cetz.draw.line(point(27, 21.5), point(20.9, 29.6), stroke: outline)
    for x in pocket-centers {
      cetz.draw.rect(point(x - half-x, pocket-y - half-y), point(x + half-x, pocket-y + half-y),
        stroke: outline, fill: rgb("#E3E3E1"))
      center-mark(x, pocket-y, 2.8)
      pin-mark((x + qx * (half-x - 3), pocket-y + qy * (half-y - 3)))
    }
    let first = pocket-centers.at(0)
    let second = pocket-centers.at(1)
    for x in (first, second) {
      cetz.draw.line(point(x, pocket-y + 3.1), point(x, tape-bottom), stroke: projection)
    }
    horizontal(first, second, tape-bottom, tape-bottom, 68, dimension-label(spec, pitch), below: true)
    vertical(tape-top, tape-bottom, tape-end, tape-end, 142, dimension-label(spec, width))

    write-at(14, 79, strong[Pocket detail], anchor: "west")
    let (cx, cy) = (48, 104)
    let ax = pocket-width.value * 3.4 / 2
    let by = pocket-length.value * 3.4 / 2
    cetz.draw.rect(point(cx - ax, cy - by), point(cx + ax, cy + by), stroke: outline, fill: white)
    cetz.draw.line(point(cx, cy - by), point(cx, cy + by), stroke: centerline)
    cetz.draw.line(point(cx - ax - 2, cy), point(cx + ax + 2, cy), stroke: projection)
    write-at(cx - ax - 3, cy, [A], anchor: "east")
    write-at(cx + ax + 3, cy, [A], anchor: "west")
    for (q, (dx, dy)) in quadrants.pairs() {
      write-at(cx + dx * 8, cy + dy * 6, q, anchor: "center")
    }
    pin-mark((cx + qx * (ax - 3), cy + qy * (by - 3)))
    write-at(70, 94, [Pin 1 in #marked-value(orientation)], anchor: "west")
    horizontal(cx - ax, cx + ax, cy + by, cy + by, 126, dimension-label(spec, pocket-width), below: true)
    vertical(cy - by, cy + by, cx - ax, cx - ax, 26, dimension-label(spec, pocket-length), left: true, label-y: 96)

    write-at(99, 79, strong[Section A–A], anchor: "west")
    let web = 96
    let floor = web + depth.value * 8
    let lip-left = 108
    let lip-right = 138
    cetz.draw.line(point(100, web), point(lip-left, web), point(lip-left + 2, floor),
      point(lip-right - 2, floor), point(lip-right, web), point(147, web), stroke: outline)
    vertical(web, floor, 147, lip-right - 2, 147.5, dimension-label(spec, depth))
    cetz.draw.line(point(121, floor), point(121, 112), stroke: projection)
    write-at(121, 116, [Pocket floor])
    mm-note(168, 131, anchor: "east")
  })
}

#let reel(spec) = {
  set text(font: "Inter", size: 9pt, fill: ink)
  let diameter = record(spec, "reel.diameter")
  let width = record(spec, "reel.width")
  let quantity = record(spec, "reel.quantity")
  let (cx, cy) = (49, 55)
  let radius = diameter.value * 0.108
  let top = cy - radius
  let bottom = cy + radius
  let side = 137
  let half-span = width.value * 0.95
  let left = side - half-span
  let right = side + half-span
  let polar(r, a) = point(cx + r * calc.cos(a), cy + r * calc.sin(a))
  cetz.canvas(length: 1mm, {
    face(172, 117)
    plate-header([Reel], [TI TUSB8041IRGCR])
    write-at(cx, 13, strong[Front view])
    write-at(side, 13, strong[Axial side view])
    cetz.draw.circle(point(cx, cy), radius: radius * 1mm, fill: rgb("#E3E3E1"), stroke: outline)
    cetz.draw.circle(point(cx, cy), radius: (radius - 2.1) * 1mm, fill: white, stroke: outline)
    for n in range(6) {
      let a = n * 60deg + 30deg
      cetz.draw.line(polar(9, a), polar(radius - 2.3, a), stroke: 2mm + metal)
    }
    cetz.draw.circle(point(cx, cy), radius: 10.5mm, fill: rgb("#E3E3E1"), stroke: outline)
    cetz.draw.circle(point(cx, cy), radius: 3.8mm, fill: white, stroke: outline)
    center-mark(cx, cy, radius + 2.3)
    vertical(top, bottom, cx, cx, 92, dimension-label(spec, diameter))
    for x in (left, right - 2.3) {
      cetz.draw.rect(point(x, top), point(x + 2.3, bottom), fill: metal, stroke: outline)
    }
    for dy in (-10.5, 10.5) {
      cetz.draw.line(point(left + 2.3, cy + dy), point(right - 2.3, cy + dy), stroke: outline)
    }
    cetz.draw.line(point(left - 2.5, cy), point(right + 2.5, cy), stroke: centerline)
    horizontal(left, right, bottom, bottom, 98, dimension-label(spec, width), below: true)
    write-at(13, 102, [Hub and arbor bore shown schematically.], anchor: "west")
    write-at(13, 109, [Standard pack (#marked-value(quantity))], anchor: "west")
    mm-note(168, 109, anchor: "east")
  })
}

#let carton-base-dimension(a, b, offset, label) = {
  let (dx, dy) = offset
  let shift(p, factor) = (p.at(0) + factor * dx, p.at(1) + factor * dy)
  for vertex in (a, b) {
    cetz.draw.line(point(..vertex), point(..shift(vertex, 1.13)), stroke: extension)
  }
  let (x1, y1) = shift(a, 1)
  let (x2, y2) = shift(b, 1)
  cetz.draw.line(point(x1, y1), point(x2, y2), stroke: dimension,
    mark: (start: "stealth", end: "stealth"))
  write-at((x1 + x2) / 2, (y1 + y2) / 2 + 9, label)
}

#let reel-box(spec) = {
  set text(font: "Inter", size: 9pt, fill: ink)
  import cetz.draw: line, bezier, merge-path
  let length = record(spec, "reel-box.length")
  let width = record(spec, "reel-box.width")
  let height = record(spec, "reel-box.height")
  let (l, w, h) = (length.value, width.value, height.value)
  let scale = 53 / calc.max(l, w)
  let ux = scale * calc.cos(30deg)
  let uy = scale * calc.sin(30deg)
  let project(x, y, z) = (27 + (x + y) * ux, 84 + (y - x) * uy - z * scale)
  let (a, c, d) = (project(0, 0, 0), project(l, w, 0), project(0, w, 0))
  let (atop, btop, ctop, dtop) = (project(0, 0, h), project(l, 0, h), project(l, w, h), project(0, w, h))
  let silhouette = 0.85pt + ink
  let detail = 0.43pt + ink
  let paper = rgb("#E3E3E1")
  let corner = 0.552285
  let panel(vertices, fill, stroke: outline) = line(..vertices.map(v => point(..v)), close: true, fill: fill, stroke: stroke)

  // Schematic folds use their own planes and share the projection of the carton.
  let lid(x, s) = project(x, s * calc.cos(68deg), h + s * calc.sin(68deg))
  let lip(x, t) = project(x, w * (calc.cos(68deg) + 0.07 * t), h + w * (calc.sin(68deg) - 0.04 * t))
  let wing(x, rise) = project(x, w - 0.17 * rise, h + rise)
  let rim(x, y) = point(..project(x, y, h))
  let rim-x = 0.17 * l
  let rim-y = 0.03 * w
  let inner-plan = ((rim-x, rim-y), (l - rim-x, rim-y), (l - rim-x, w - rim-y), (rim-x, w - rim-y))
  let (top-a, top-b, top-c, top-d) = inner-plan.map(p => project(..p, h))
  let (floor-a, floor-b, floor-c, floor-d) = inner-plan.map(p => project(..p, 0.24 * h))

  let tab(plane, span, reach, radius, fill) = merge-path(close: true, fill: fill, stroke: outline, {
    let tangent = corner * radius
    line(plane(0, 0), plane(reach - radius, 0))
    bezier(plane(reach - radius, 0), plane(reach, radius),
      plane(reach - radius + tangent, 0), plane(reach, radius - tangent))
    line(plane(reach, radius), plane(reach, span - radius))
    bezier(plane(reach, span - radius), plane(reach - radius, span),
      plane(reach, span - radius + tangent), plane(reach - radius + tangent, span))
    line(plane(reach - radius, span), plane(0, span))
  })
  let slot(x, y0, y1, radius) = merge-path(close: true, fill: paper, stroke: detail, {
    let cap = 4 * radius / 3
    line(rim(x - radius, y0), rim(x - radius, y1))
    bezier(rim(x - radius, y1), rim(x + radius, y1), rim(x - radius, y1 + cap), rim(x + radius, y1 + cap))
    line(rim(x + radius, y1), rim(x + radius, y0))
    bezier(rim(x + radius, y0), rim(x - radius, y0), rim(x + radius, y0 - cap), rim(x - radius, y0 - cap))
  })

  cetz.canvas(length: 1mm, {
    face(172, 135)
    plate-header([Tape and reel box], [TI TUSB8041IRGCR])

    // Put the far tab behind the lid edge and the near tab on the lid face.
    tab((x, s) => point(..lid(l + x, 0.44 * w + s)), 0.20 * w, 0.13 * l, 0.043 * l, gray)
    panel((atop, btop, lid(l, w), lid(0, w)), white, stroke: silhouette)
    for x in (0.012 * l, 0.988 * l) {
      line(point(..lid(x, 0.02 * w)), point(..lid(x, w)), stroke: detail)
    }
    panel((lid(0, w), lid(l, w), lip(l, 1), lip(0, 1)), gray, stroke: silhouette)
    line(point(..lip(0.012 * l, 0.84)), point(..lip(0.988 * l, 0.84)), stroke: detail)
    tab((x, s) => point(..lid(x, 0.35 * w + s)), 0.20 * w, 0.13 * l, 0.043 * l, gray)

    let hole(x, y) = point(..lid(l * (0.51 + 0.038 * x), w * (0.55 + 0.064 * y)))
    merge-path(close: true, fill: gray, stroke: detail, {
      bezier(hole(1, 0), hole(0, 1), hole(1, corner), hole(corner, 1))
      bezier(hole(0, 1), hole(-1, 0), hole(-corner, 1), hole(-1, corner))
      bezier(hole(-1, 0), hole(0, -1), hole(-1, -corner), hole(-corner, -1))
      bezier(hole(0, -1), hole(1, 0), hole(corner, -1), hole(1, -corner))
    })
    let lid-mark(x, y) = point(..lid(x * l, y * w))
    merge-path(close: true, stroke: projection, {
      line(lid-mark(0.23, 0.12), lid-mark(0.425, 0.12))
      bezier(lid-mark(0.425, 0.12), lid-mark(0.515, 0.12), lid-mark(0.425, 0.19), lid-mark(0.515, 0.19))
      line(lid-mark(0.515, 0.12), lid-mark(0.72, 0.12), lid-mark(0.72, 0.41), lid-mark(0.23, 0.41))
    })

    // Draw the recess and four rim slots before the near wing occludes them.
    panel((floor-a, floor-b, floor-c, floor-d), white, stroke: detail)
    panel((top-a, top-b, floor-b, floor-a), gray, stroke: detail)
    panel((top-b, top-c, floor-c, floor-b), paper, stroke: detail)
    panel((atop, btop, top-b, top-a), gray)
    panel((btop, ctop, top-c, top-b), white)
    panel((dtop, atop, top-a, top-d), white)
    panel((ctop, dtop, top-d, top-c), gray)
    for x in (0.45 * rim-x, l - 0.45 * rim-x) {
      for (start, end) in ((0.23, 0.39), (0.58, 0.84)) {
        slot(x, start * w, end * w, 0.0075 * l)
      }
    }
    line(rim(l - rim-x + 0.01 * l, rim-y), rim(l - rim-x + 0.01 * l, w - rim-y), stroke: detail)
    panel((a, d, dtop, atop), gray, stroke: silhouette)
    panel((d, c, ctop, dtop), paper, stroke: silhouette)
    for x in (0.18 * l, 0.83 * l) {
      line(point(..project(x, w, 0)), point(..project(x, w, h)), stroke: detail)
    }
    let rise = 1.65 * h
    panel((dtop, ctop, wing(l, rise), wing(0, rise)), white, stroke: silhouette)
    line(point(..wing(0.012 * l, rise - 0.09 * h)), point(..wing(0.988 * l, rise - 0.09 * h)), stroke: detail)
    tab((x, s) => point(..wing(-x, 0.43 * h + s)), 1.19 * h, 0.095 * l, 0.34 * h, gray)

    carton-base-dimension(d, c, (5.5, 9), dimension-label(spec, length))
    carton-base-dimension(a, d, (-5.5, 9), dimension-label(spec, width))
    vertical(ctop.at(1), c.at(1), ctop.at(0), c.at(0), c.at(0) + 12,
      dimension-label(spec, height), small: true)
    write-at(5, 131, [Carton details shown schematically.], anchor: "west")
    mm-note(167, 131, anchor: "east")
  })
}

#let reflow(spec) = {
  set text(font: "Inter", size: 9pt, fill: ink)
  let start = record(spec, "reflow.start-temperature")
  let soak = record(spec, "reflow.soak-temperature")
  let liquidus = record(spec, "reflow.liquidus-temperature")
  let peak = record(spec, "reflow.peak-temperature")
  let band = record(spec, "reflow.peak-band")
  let soak-time = record(spec, "reflow.soak-time")
  let liquidus-time = record(spec, "reflow.liquidus-time")
  let peak-time = record(spec, "reflow.peak-time")
  let time-to-peak = record(spec, "reflow.time-to-peak")
  let x-axis = 29
  let axis-y = 81
  let y-temp(t) = axis-y - (t - start.value) * 0.251
  let y-min = y-temp(soak.value.min)
  let y-max = y-temp(soak.value.max)
  let y-l = y-temp(liquidus.value)
  let y-p = y-temp(peak.value)
  let y-band = y-temp(peak.value - band.value)
  let (x-min, x-max, x-peak, x-flat, x-down) = (55, 80, 113, 122, 144)
  let rise = (liquidus.value - soak.value.max) / (peak.value - soak.value.max)
  let x-up = x-max + rise * (x-peak - x-max)
  let ratio = band.value / (peak.value - liquidus.value)
  let p-in = x-peak - ratio * (x-peak - x-up)
  let p-out = x-flat + ratio * (x-down - x-flat)
  cetz.canvas(length: 1mm, {
    face(172, 99)
    plate-header([Pb-free package classification], [ADI SMP Rev J])
    write-at(5, 14, [Package body temperature (°C)], anchor: "west")
    cetz.draw.line(point(x-min, y-min), point(x-max, y-min), point(x-max, y-max),
      point(64, y-min - 4), close: true, fill: rgb("#E2E2E1"), stroke: none)
    cetz.draw.line(point(x-up, y-l), point(x-peak, y-p), point(x-flat, y-p), point(x-down, y-l),
      close: true, fill: rgb("#E7DDC5"), stroke: none)
    for (y, x, label) in (
      (y-p, x-peak, dimension-label(spec, peak)),
      (y-l, x-up, dimension-label(spec, liquidus)),
      (y-max, x-max, use-record(soak, [#symbol(spec, "T_Smax") #soak.value.max °C])),
      (y-min, x-min, use-record(soak, [#symbol(spec, "T_Smin") #soak.value.min °C])),
    ) {
      cetz.draw.line(point(x-axis, y), point(x, y), stroke: projection)
      write-at(x-axis - 2.2, y, label, anchor: "east")
    }
    cetz.draw.line(point(p-in, y-band), point(p-out, y-band), stroke: projection)
    write-at(133, 12.5, [Within #marked-value(band) of #symbol-for(spec, peak)], anchor: "west")
    horizontal(p-in, p-out, y-band, y-band, 16, use-record(peak-time, symbol-for(spec, peak-time)))
    cetz.draw.line(point(x-axis, axis-y), point(166, axis-y), stroke: outline, mark: (end: "stealth"))
    cetz.draw.line(point(x-axis, axis-y), point(x-axis, 18), stroke: outline, mark: (end: "stealth"))
    cetz.draw.line(point(x-axis, axis-y), point(x-min, y-min), point(64, y-min - 4), point(x-max, y-max),
      point(x-up, y-l), point(x-peak, y-p), point(x-flat, y-p), point(x-down, y-l), point(162, y-max + 14),
      stroke: 1.15pt + ink)
    write-at(x-axis - 2.2, axis-y, marked-value(start), anchor: "east")
    // Leave the liquidus interval arrow and its label clear.
    cetz.draw.line(point(x-peak, y-p + 2), point(x-peak, 65.5), stroke: projection)
    cetz.draw.line(point(x-peak, 74), point(x-peak, axis-y), stroke: projection)
    horizontal(x-min, x-max, y-min, y-max, 59,
      use-record(soak-time, [Preheat and soak (#symbol-for(spec, soak-time))]), below: true)
    horizontal(x-up, x-down, y-l, y-l, 68,
      use-record(liquidus-time, [Above liquidus (#symbol-for(spec, liquidus-time))]), below: true)
    write-at(69, 27, use-record(record(spec, "reflow.ramp-up"), [Ramp-up]))
    cetz.draw.line(point(78, 28), point(x-up + 7, y-l - 7 * (y-l - y-p) / (x-peak - x-up)),
      stroke: dimension, mark: (end: "stealth"))
    write-at(156, 21.5, use-record(record(spec, "reflow.ramp-down"), [Ramp-down]))
    cetz.draw.line(point(149, 23.5), point(135, 29.4), stroke: dimension, mark: (end: "stealth"))
    horizontal(x-axis, x-peak, axis-y, axis-y, 88, use-record(time-to-peak, [#value(start) to peak]), below: true)
    write-at(167, 88, [Time (schematic)], anchor: "east")
  })
}
