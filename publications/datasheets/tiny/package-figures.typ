// QFN64 package and assembly drawings share the Tiny reference geometry.
#import "@preview/cetz:0.5.2" as cetz
#import "../../specifications/figures.typ": ink, gold, gray
#import "../../specifications/components.typ": use-record
#import "../../specifications/scientific.typ" as scientific
#import "soc-palette.typ": domain-fill, rail-fill

#let metal = rgb("#A0A09C")
#let outline = 0.6pt + ink
#let projection = (paint: ink, thickness: 0.45pt, dash: "dashed")
#let centerline = (paint: gold, thickness: 0.55pt, dash: "dashed")
#let dimension = 0.7pt + gold
#let extension = 0.45pt + gold

#let point(x, y) = (x, -y)
#let write-at(x, y, body, anchor: "center") = cetz.draw.content(point(x, y), body, anchor: anchor)
#let face(width, height) = cetz.draw.rect(point(0, 0), point(width, height), fill: gray, stroke: none)
#let view-title(x, y, title) = write-at(x, y, text(size: 11pt, weight: "semibold", fill: gold, title))
#let reference-label(x, y, anchor: "center") = write-at(x, y, strong[REFERENCE ONLY], anchor: anchor)
#let mm-note(x, y, anchor: "center") = write-at(x, y, [Dimensions in mm. Drawing not to scale.], anchor: anchor)

// Physical x/y coordinates have their origin at the centre of the package.
#let transform(center, scale, xy) = (center.at(0) + xy.at(0) * scale, center.at(1) - xy.at(1) * scale)
#let square(center, scale, span, fill: none, stroke: outline) = {
  let half = span * scale / 2
  let (x, y) = center
  cetz.draw.rect(point(x - half, y + half), point(x + half, y - half), fill: fill, stroke: stroke)
}
#let contact(center, scale, bounds, expand: 0, fill: metal, stroke: outline) = {
  let (x, y, w, h) = bounds
  let half-w = w / 2 + expand
  let half-h = h / 2 + expand
  let (left, low) = transform(center, scale, (x - half-w, y - half-h))
  let (right, high) = transform(center, scale, (x + half-w, y + half-h))
  cetz.draw.rect(point(left, low), point(right, high), fill: fill, stroke: stroke)
}
#let exposed-pad(center, scale, d, top: false, fill: metal, stroke: outline) = {
  let half = d.ep / 2
  let corners = ((-half, half), (half - d.chamfer, half), (half, half - d.chamfer),
    (half, -half), (-half, -half))
  let xy = corners.map(((x, y)) => transform(center, scale, (if top { -x } else { x }, y)))
  cetz.draw.line(..xy.map(p => point(..p)), close: true, fill: fill, stroke: stroke)
}
#let pin-position(spec, center, scale, view) = {
  let (x, y) = spec.qfn.pins.first().at(view)
  let inset = if view == "top" { 0.62 } else { -0.62 }
  transform(center, scale, (x + inset, y))
}
#let pin-mark(position) = cetz.draw.circle(point(..position), radius: 0.85mm, fill: gold, stroke: outline)
#let measures(spec, keys) = {
  for key in keys {
    let m = spec.qfn.measurements.at(key)
    use-record(spec.records.find(r => r.id == m.id), [])
  }
}
#let symbol(spec, name) = scientific.render(name, spec.scientific, mechanical: true)

// Extension lines start at the measured edges. Short spans use outward arrows.
#let horizontal(x1, x2, y1, y2, level, value, small: false, below: false) = {
  cetz.draw.line(point(x1, y1), point(x1, level), stroke: extension)
  cetz.draw.line(point(x2, y2), point(x2, level), stroke: extension)
  if small {
    cetz.draw.line(point(x1 - 3.2, level), point(x1, level), stroke: dimension, mark: (end: "stealth"))
    cetz.draw.line(point(x2 + 3.2, level), point(x2, level), stroke: dimension, mark: (end: "stealth"))
  } else {
    cetz.draw.line(point(x1, level), point(x2, level), stroke: dimension, mark: (start: "stealth", end: "stealth"))
  }
  write-at((x1 + x2) / 2, level + if below { 2.8 } else { -2.8 }, value)
}
#let vertical(y1, y2, x1, x2, level, value, small: false, left: false, label-y: none) = {
  cetz.draw.line(point(x1, y1), point(level, y1), stroke: extension)
  cetz.draw.line(point(x2, y2), point(level, y2), stroke: extension)
  if small {
    cetz.draw.line(point(level, y1 - 3), point(level, y1), stroke: dimension, mark: (end: "stealth"))
    cetz.draw.line(point(level, y2 + 3), point(level, y2), stroke: dimension, mark: (end: "stealth"))
  } else {
    cetz.draw.line(point(level, y1), point(level, y2), stroke: dimension, mark: (start: "stealth", end: "stealth"))
  }
  let text-y = if label-y == none { (y1 + y2) / 2 } else { label-y }
  if left { write-at(level - 2, text-y, value, anchor: "east") }
  else { write-at(level + 2, text-y, value, anchor: "west") }
}

#let qfn-pin-view(spec, view) = {
  set text(font: "Inter", size: 9pt, fill: ink)
  let centre = (86, 53)
  let scale = 8
  let d = spec.qfn.dimensions
  let top = view == "top"
  cetz.canvas(length: 1mm, {
    face(172, 104)
    reference-label(5, 6, anchor: "west")
    view-title(86, 4.4, if top { [Top view] } else { [Bottom view] })
    square(centre, scale, d.body, fill: white)
    if top {
      write-at(86, 48, [Projected terminal positions])
      write-at(86, 55, [Pin 1 at upper left])
    } else {
      exposed-pad(centre, scale, d)
      write-at(86, 49, strong[EP])
      write-at(86, 55, [Unnumbered])
    }
    for p in spec.qfn.pins {
      let (x, y) = p.at(view)
      contact(centre, scale, p.at(view + "_terminal"),
        fill: if top { none } else { metal }, stroke: if top { projection } else { outline })
      let (screen-x, screen-y) = transform(centre, scale, (x, y))
      if p.side in (0, 2) {
        write-at(screen-x + if x < 0 { -4.5 } else { 4.5 }, screen-y, str(p.pin))
      } else {
        let direction = if y > 0 { -1 } else { 1 }
        let offset = if calc.rem(p.pin, 2) == 0 { 8.0 } else { 3.8 }
        let label-y = screen-y + direction * offset
        cetz.draw.line(point(screen-x, screen-y), point(screen-x, label-y - 1.6 * direction), stroke: extension)
        write-at(screen-x, label-y, str(p.pin))
      }
    }
    pin-mark(pin-position(spec, centre, scale, view))
  })
}

#let pinout-fill = (
  supply: domain-fill.system,
  ground: rail-fill,
  gpio: domain-fill.peripheral,
  xpi: domain-fill.memory,
  jtag: domain-fill.jtag,
  control: domain-fill.aon,
  audio: domain-fill.audio,
  pixel: domain-fill.dvp_pixel,
)

#let pinout-primary-fill(name) = {
  if name.starts-with("GPIO") { pinout-fill.gpio }
  else if name.starts-with("XPI_") { pinout-fill.xpi }
  else if name.starts-with("JTAG_") { pinout-fill.jtag }
  else if name.starts-with("VDD") or name.starts-with("AVDD") { pinout-fill.supply }
  else if name.starts-with("VSS") or name.starts-with("AVSS") { pinout-fill.ground }
  else { pinout-fill.control }
}

#let pinout-tag(body, fill) = box(body, fill: fill, radius: 0.55mm, inset: (x: 0.85mm, y: 0.33mm))

#let qfn-pinout(spec) = context {
  set text(font: "Inter", size: 9pt, fill: ink)
  let qfn = spec.qfn
  let d = qfn.dimensions
  let centre = (86, 77)
  let scale = 9
  let half = d.body * scale / 2
  let number-inset = (d.lead_length * scale + (d.body - d.ep) * scale / 2) / 2
  let normals = ((-1, 0), (0, 1), (1, 0), (0, -1))
  let anchors = ("east", "north", "west", "south")
  let alias-fills = (CLKOUT: pinout-fill.control, UART0: pinout-fill.gpio,
    AUDIO: pinout-fill.audio, DVP: pinout-fill.pixel)
  let size(key) = qfn.measurements.at(key).nom.split(" ").first()
  measures(spec, ("body", "pitch", "ep"))
  cetz.canvas(length: 1mm, {
    import cetz.draw: circle, line, rect
    face(172, 180)
    write-at(4, 5.5, [*FROZEN TARGET* · Physical binding pending], anchor: "west")
    square(centre, scale, d.body, fill: white, stroke: 0.9pt + ink)
    exposed-pad(centre, scale, d, top: true, fill: none, stroke: projection)
    circle(point(centre.at(0) - half + 3, centre.at(1) - half + 3), radius: 0.9mm, fill: ink, stroke: none)
    write-at(86, 66, text(size: 16pt, weight: "bold", [Tiny Gen1]))
    write-at(86, 73.5, text(size: 12pt, weight: "semibold", [QFN64 · Top view]))
    write-at(86, 91, pinout-tag([*EP* · Intended GND · Bonding TBD], pinout-fill.ground))
    for p in qfn.pins {
      let (x, y) = transform(centre, scale, p.top)
      let (dx, dy) = normals.at(p.side)
      let anchor = anchors.at(p.side)
      let name = p.name + if p.unbound_target { "*" } else { "" }
      let primary = pinout-tag(text(weight: "semibold", name), pinout-primary-fill(p.name))
      let (lx, ly) = (x + 1.55 * dx, y + 5.15 * dy)
      contact(centre, scale, p.top_terminal, fill: none, stroke: projection)
      // Split the number lanes at each corner so the adjacent edge numbers stay distinct.
      if dy == 0 {
        write-at(x - dx * number-inset, y, str(p.pin))
        line(point(x, y), point(lx, ly), stroke: 0.45pt + ink)
      } else {
        write-at(x, y + 2.35 * dy, str(p.pin))
        line(point(x, y + 4.05 * dy), point(lx, ly), stroke: 0.45pt + ink)
      }
      let angled = if dy == 0 { primary } else { rotate(dy * 90deg, reflow: true, primary) }
      write-at(lx, ly, angled, anchor: anchor)

      let alt = qfn.pinout_aliases.find(a => a.pin == p.pin)
      if alt != none {
        let fill = alias-fills.at(alt.function.split(".").first())
        let width = measure(primary).width / 1mm
        if dy == 0 {
          let badge = pinout-tag(stack(spacing: 0.6mm, strong(alt.function), alt.mode), fill)
          let start = lx + dx * width
          let end = start + dx * 2.6
          line(point(start, ly), point(end, ly), stroke: 0.45pt + ink)
          write-at(end, ly, badge, anchor: anchor)
        } else {
          // Give the adjacent UART callouts separate outward lanes.
          let direction = if alt.function == "UART0.TX" { -1 } else { 1 }
          let row = 146
          let end = lx + direction * 2.6
          line(point(lx, ly + width), point(lx, row), point(end, row), stroke: 0.45pt + ink)
          let badge = pinout-tag([#alt.mode · #strong(alt.function)], fill)
          write-at(end, row, badge, anchor: if direction < 0 { "east" } else { "west" })
        }
      }
    }

    let legend = (([Supply], pinout-fill.supply), ([Ground / EP], pinout-fill.ground),
      ([GPIO / UART0], pinout-fill.gpio), ([Boot XPI], pinout-fill.xpi),
      ([Clock / reset / straps], pinout-fill.control), ([JTAG], pinout-fill.jtag),
      ([AUDIO (ALT)], pinout-fill.audio), ([PIXCLK (ALT)], pinout-fill.pixel))
    for (i, (title, fill)) in legend.enumerate() {
      let x = 4 + 41 * calc.rem(i, 4)
      let y = if i < 4 { 153 } else { 159 }
      rect(point(x, y - 1.55), point(x + 3.1, y + 1.55), fill: fill, stroke: 0.4pt + ink)
      write-at(x + 4.8, y, title, anchor: "west")
    }
    write-at(4, 165, [\* Unbound target assignment.], anchor: "west")
    write-at(4, 173, [*REFERENCE ONLY* · Body #size("body") × #size("body") mm ·
      Pitch #size("pitch") mm · EP #size("ep") × #size("ep") mm], anchor: "west")
  })
}

#let qfn-outline-view(spec, view) = {
  let d = spec.qfn.dimensions
  let centre = (43, 44)
  let scale = 5.75
  let (cx, cy) = centre
  let b = d.body * scale / 2
  let ep = d.ep * scale / 2
  let sym(name) = symbol(spec, name)
  cetz.canvas(length: 1mm, {
    face(84, 86)
    view-title(cx, 5, if view == "top" { [Top view] } else { [Bottom view] })
    square(centre, scale, d.body, fill: white)
    if view == "top" {
      horizontal(cx - b, cx + b, cy - b, cy - b, 13, [D])
      vertical(cy - b, cy + b, cx + b, cx + b, 74, [E])
      let pin-one = pin-position(spec, centre, scale, "top")
      cetz.draw.line(point(37, 33), point(..pin-one), stroke: extension)
      write-at(39, 33, [Pin 1], anchor: "west")
      pin-mark(pin-one)
    } else {
      exposed-pad(centre, scale, d)
      for p in spec.qfn.pins { contact(centre, scale, p.bottom_terminal) }
      horizontal(cx - ep, cx + ep, cy - ep, cy - ep, 13, sym("D2"))
      vertical(cy - ep, cy + ep, cx + ep, cx + ep, 73, sym("E2"))
      let half-pitch = d.pitch * scale / 2
      let half-width = d.lead_width * scale / 2
      let outer = cy + b
      horizontal(cx - 5 * half-pitch - half-width, cx - 5 * half-pitch + half-width,
        outer, outer, 78, [b], small: true, below: true)
      horizontal(cx + 5 * half-pitch, cx + 7 * half-pitch,
        outer, outer, 78, [e], small: true, below: true)
      horizontal(cx - b, cx - b + d.lead_length * scale,
        cy + 7.5 * d.pitch * scale, cy + 7.5 * d.pitch * scale, 74, [L], small: true, below: true)
      let chamfer = (cx + ep - d.chamfer * scale / 2, cy - ep + d.chamfer * scale / 2)
      cetz.draw.line(point(47, 32), point(..chamfer), stroke: dimension, mark: (end: "stealth"))
      write-at(45.5, 33, [C], anchor: "east")
      write-at(43, 48, strong[EP])
      pin-mark(pin-position(spec, centre, scale, "bottom"))
    }
  })
}

#let qfn-side(spec, standalone: true) = {
  set text(font: "Inter", size: 9pt, fill: ink)
  let d = spec.qfn.dimensions
  let sym(name) = symbol(spec, name)
  let seat = 42
  let height-scale = 26
  let top = seat - d.height * height-scale
  let bottom = seat - d.standoff * height-scale
  let lead-top = seat - d.lead_height * height-scale
  let half-body = d.body * 4.6 / 2
  let left = 42 - half-body
  let right = 42 + half-body
  cetz.canvas(length: 1mm, {
    face(84, 62)
    if standalone { reference-label(42, 4) }
    view-title(42, if standalone { 11 } else { 7 }, [Side view])
    cetz.draw.rect(point(left, top), point(right, bottom), fill: white, stroke: outline)
    for p in spec.qfn.pins.filter(p => p.side == 1) {
      let x = 42 + p.top.at(0) * 4.6
      let half-lead = d.lead_width * 4.6 / 2
      cetz.draw.rect(point(x - half-lead, lead-top), point(x + half-lead, seat), fill: metal, stroke: 0.35pt + ink)
    }
    cetz.draw.line(point(18, seat), point(69, seat), stroke: projection)
    vertical(top, seat, left, 18, 9.5, [A], left: true)
    vertical(bottom, seat, left, left, 17, sym("A1"), small: true, label-y: 49)
    let lead-edge = 42 + (7.5 * d.pitch + d.lead_width / 2) * 4.6
    vertical(lead-top, seat, lead-edge, lead-edge, 73, sym("A3"), small: true)
    cetz.draw.line(point(64, seat), point(62, 49), point(51, 49), stroke: extension)
    write-at(49, 49, [Seating plane], anchor: "east")
    mm-note(42, 57)
  })
}

#let qfn-dimension-table(spec) = {
  let fields = (
    ("A", "height"), ("A1", "standoff"), ("A3", "lead_height"), ("D", "body"), ("E", "body"),
    ("D2", "ep"), ("E2", "ep"), ("b", "lead_width"), ("e", "pitch"), ("L", "lead_length"), ("C", "chamfer"),
  )
  let rows = fields.map(((name, key)) => {
    let m = spec.qfn.measurements.at(key)
    let values = (m.min, m.nom, m.max).map(value => if value == none { [] } else { value })
    (use-record(spec.records.find(r => r.id == m.id), symbol(spec, name)), ..values)
  })
  table(
    columns: (1fr, 1fr, 1.47fr, 1fr),
    align: center + horizon,
    inset: (x: 2pt, y: 2.8pt),
    stroke: 0.4pt + rgb("#A7A9AB"),
    fill: (x, y) => if y == 0 { rgb("#F4EFE4") } else { white },
    table.header(strong[Symbol], strong[Min.], strong[Nom.], strong[Max.]),
    ..rows.flatten(),
  )
}

#let qfn-mechanical(spec, numbered: false) = block(width: 172mm, fill: gray, inset: (y: 2mm), breakable: false)[
  #set text(font: "Inter", size: 9pt, fill: ink)
  #align(center, strong[REFERENCE ONLY])
  #grid(
    columns: (84mm, 84mm), column-gutter: 4mm, row-gutter: 1mm,
    qfn-outline-view(spec, "top"), qfn-outline-view(spec, "bottom"),
    block(inset: (left: 4mm, right: 2mm))[
      #let table-body = qfn-dimension-table(spec)
      #if numbered {
        figure(kind: table, supplement: [Table], caption: [QFN64 dimensions (mm) - REFERENCE ONLY], table-body)
      } else {
        [#align(center, strong[Mechanical dimensions (mm)]) #table-body]
      }
      #v(1mm)
      BSC = basic dimension. REF = reference dimension.
      #linebreak()C = Pin 1 chamfer.
    ],
    qfn-side(spec, standalone: false),
  )
]

#let land-pattern(spec, centre, scale, fill: metal, stroke: outline, expand: 0) = {
  square(centre, scale, spec.qfn.dimensions.pad_ep + 2 * expand, fill: fill, stroke: stroke)
  for p in spec.qfn.pins {
    contact(centre, scale, p.land, fill: fill, stroke: stroke, expand: expand)
  }
}

#let qfn-copper(spec) = {
  set text(font: "Inter", size: 9pt, fill: ink)
  let d = spec.qfn.dimensions
  let m = spec.qfn.measurements
  let scale = 10
  let centre = (84, 82)
  let (cx, cy) = centre
  let outer = d.pad_outer * scale / 2
  let inner = d.pad_inner * scale / 2
  let ep = d.pad_ep * scale / 2
  let first = spec.qfn.pins.first()
  let last = spec.qfn.pins.at(15)
  let y-first = transform(centre, scale, first.land).at(1)
  let y-last = transform(centre, scale, last.land).at(1)
  let row = spec.qfn.pins.slice(16, 32)
  let x-for(n) = transform(centre, scale, row.at(n).land).at(0)
  let half-width = d.pad_width * scale / 2
  measures(spec, ("pitch", "pad_outer", "pad_inner", "pad_ep", "pad_width", "pad_length"))
  cetz.canvas(length: 1mm, {
    face(172, 173)
    reference-label(6, 7, anchor: "west")
    view-title(86, 7, [Component-side view])
    land-pattern(spec, centre, scale)
    cetz.draw.line(point(cx - outer - 5, cy), point(cx + outer + 5, cy), stroke: centerline)
    cetz.draw.line(point(cx, cy - outer - 2), point(cx, cy + outer + 2), stroke: centerline)
    horizontal(cx - outer, cx + outer, y-first, y-first, 18, strong(m.pad_outer.label))
    horizontal(cx - inner, cx + inner, y-first, y-first, 25, strong(m.pad_inner.label))
    horizontal(cx - ep, cx + ep, cy - ep, cy - ep, 32, strong(m.pad_ep.label))
    vertical(cy - ep, cy + ep, cx + ep, cx + ep, 144, strong(m.pad_ep.label))
    write-at(7, y-first, [Pin 1], anchor: "west")
    cetz.draw.line(point(18, y-first), point(cx - outer - 1.6, y-first), stroke: dimension, mark: (end: "stealth"))
    cetz.draw.circle(point(cx - outer - 0.8, y-first), radius: 0.65mm, fill: gold, stroke: none)
    write-at(cx, cy - 5, strong[EP copper])
    horizontal(x-for(2) - half-width, x-for(2) + half-width, cy + outer, cy + outer, 139,
      strong(m.pad_width.label), small: true, below: true)
    horizontal(x-for(9), x-for(10), cy + outer, cy + outer, 139,
      strong(m.pitch.label), small: true, below: true)
    horizontal(cx + inner, cx + outer, y-last, y-last, 136,
      strong(m.pad_length.label), small: true, below: true)
    horizontal(x-for(0), x-for(15), cy + outer, cy + outer, 153,
      [#spec.qfn.land_row_span REF], below: true)
    mm-note(6, 166, anchor: "west")
    write-at(166, 166, [Spans apply to both axes], anchor: "east")
  })
}

#let qfn-layer(spec, layer) = {
  set text(font: "Inter", size: 9pt, fill: ink)
  let d = spec.qfn.dimensions
  let (pcb, paste) = (spec.models.pcb, spec.models.paste)
  let centre = (42, 41)
  let scale = 5.5
  let title = ("mask": [Solder mask], "paste": [Solder paste], "vias": [Thermal vias]).at(layer)
  cetz.canvas(length: 1mm, {
    face(84, 87)
    reference-label(5, 5, anchor: "west")
    view-title(42, 11, title)
    if layer == "mask" {
      land-pattern(spec, centre, scale, expand: pcb.mask_expansion_mm)
    }
    land-pattern(spec, centre, scale, fill: none, stroke: projection)
    let (pin-x, pin-y) = transform(centre, scale, spec.qfn.pins.first().land)
    let marker = pin-x - d.pad_length * scale / 2 - 2
    cetz.draw.circle(point(marker, pin-y), radius: 0.7mm, fill: gold, stroke: outline)
    write-at(marker - 1.5, pin-y, [1], anchor: "east")
    if layer == "mask" {
      write-at(42, 36, [Exposed-pad opening])
      write-at(42, 44, [Dashed: copper])
      write-at(42, 73, [Expansion #pcb.mask_expansion_mm mm per edge])
      write-at(42, 78, [Nominal perimeter web #spec.qfn.assembly.mask_web_mm mm])
    } else if layer == "paste" {
      let a = paste.aperture_mm
      let p = a + paste.gap_mm
      for i in range(paste.count_x) {
        for j in range(paste.count_y) {
          let x = (i - (paste.count_x - 1) / 2) * p
          let y = (j - (paste.count_y - 1) / 2) * p
          contact(centre, scale, (x, y, a, a))
        }
      }
      write-at(42, 73, [#paste.count_x × #paste.count_y EP windows, #a mm square])
      write-at(42, 78, [#paste.gap_mm mm gap · #paste.stencil_mm mm stencil])
      write-at(42, 83, [#calc.round(spec.paste_coverage_percent, digits: 2)% of nominal EP area])
    } else {
      for i in range(pcb.via_grid) {
        for j in range(pcb.via_grid) {
          let x = (i - (pcb.via_grid - 1) / 2) * pcb.via_pitch_mm
          let y = (j - (pcb.via_grid - 1) / 2) * pcb.via_pitch_mm
          let pos = point(..transform(centre, scale, (x, y)))
          let land-radius = pcb.via_land_mm * scale / 2
          let drill-radius = pcb.via_drill_mm * scale / 2
          cetz.draw.circle(pos, radius: land-radius * 1mm, fill: metal, stroke: outline)
          cetz.draw.circle(pos, radius: drill-radius * 1mm, fill: ink, stroke: none)
        }
      }
      write-at(42, 73, [#pcb.via_grid × #pcb.via_grid vias · #pcb.via_pitch_mm mm pitch])
      write-at(42, 78, [Drill Ø#pcb.via_drill_mm mm · land Ø#pcb.via_land_mm mm])
    }
    if layer != "paste" { write-at(42, 83, [Component side · not to scale]) }
  })
}
