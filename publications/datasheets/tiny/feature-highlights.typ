#import "@preview/cetz:0.5.2" as cetz

// Figure 2 uses the 1200 × 674 design coordinates at 172 mm wide.
#let unit = 172mm / 1200
#let card-fill = rgb("#EDEDED")
#let card-radius = 24
#let detail-ink = rgb("#171717")
#let violet = gradient.linear(rgb("#C392F7"), rgb("#8345DC"), angle: 0deg, relative: "parent")
#let chip-violet = (light: rgb("#EAD7FB"), dark: rgb("#8345DC"))
#let chip-warm-yellow = (light: rgb("#FBF2D7"), dark: rgb("#DCB645"))
#let schematic-stroke = 0.55pt + rgb("#9D64DF")
#let chip-logos = json("chip-logo-outlines.json")
#let chip-side = 289
#let chip-edge = 0.55pt
#let chip-native-size = chip-side * unit + chip-edge
// Match the visible top of the status line with the signature fixing the bottom.
#let cover-chip-size = 33.552375mm

#let panel(x, y, w, h, fill: card-fill, radius: card-radius, stroke: none) = {
  cetz.draw.content((x, -y), box(rect(
    width: w * unit, height: h * unit, radius: radius * unit,
    fill: fill, stroke: stroke, inset: 0pt,
  )), anchor: "north-west")
}

#let draw-chip(
  x, y, product-name: "TINY", description: "RISC-V AI MCU", badge: "Edge AI",
  accent: chip-violet, show-icsprout: true, marking-ink: none,
) = {
  import cetz.draw: content

  let mark(original) = if marking-ink == none { original } else { marking-ink }
  // Both logos share one visible height and horizontal centerline.
  let chip-logo(anchor-x, logo, anchor: "center") = {
    let scale = 32 / logo.height * unit
    let commands = logo.rings.map(ring => {
      let points = ring.map(p => (p.at(0) * scale, p.at(1) * scale))
      (curve.move(points.first()),) + points.slice(1).map(p => curve.line(p)) + (curve.close(),)
    }).flatten()
    content((x + anchor-x, -y - 34), curve(..commands, fill: mark(white), stroke: none, fill-rule: "even-odd"), anchor: anchor)
  }

  // The chip labels and marks are illustrative artwork.
  // A single-ink marking uses the mold color for the lettering inside the badge.
  let (chip-fill, badge-ink) = if marking-ink == none {
    (gradient.linear(rgb("#44434B"), rgb("#171719"), angle: 45deg), detail-ink)
  } else {
    let mold = rgb("#2D2C30")
    (mold, mold)
  }
  panel(x, y, chip-side, chip-side, fill: chip-fill, radius: 0, stroke: chip-edge + rgb("#525158"))
  // Figure 2's disc aligns with the visible R1 edge, 1.65 mm from ICsprout.
  chip-logo(38.32432, chip-logos.ecos)
  if show-icsprout {
    chip-logo(65.82048, chip-logos.icsprout, anchor: "west")
  }
  // The longer badge retains its text padding.
  let (badge-left, badge-width) = if badge == "Physical AI" { (149, 133) } else { (175, 96) }
  panel(x + badge-left, y + 18, badge-width, 32, fill: mark(accent.light), radius: 8)
  content((x + badge-left + badge-width / 2, -y - 34), box(text(
    font: "Inter", size: 9pt, weight: 700, fill: badge-ink,
    top-edge: "bounds", bottom-edge: "bounds", badge,
  )), anchor: "center")

  let chip-mark = {
    set text(font: "Inter", fill: mark(rgb("#FAFAFB")), top-edge: "cap-height", bottom-edge: "baseline")
    let model = text(size: 30pt, weight: 650, tracking: -0.022em, "R1")
    // Limit the gradient to the product word within the shared baseline.
    let product = box(text(size: 16pt, weight: 650,
      fill: mark(gradient.linear(accent.light, accent.dark, angle: 0deg, relative: "parent")), product-name))
    box(model + h(1.8mm) + product)
  }
  content((x + 18, -y - 159.6234), chip-mark, anchor: "north-west")

  let chip-description = {
    set text(font: "Inter", fill: mark(rgb("#FAFAFB")), top-edge: "cap-height", bottom-edge: "descender")
    stack(dir: ttb, spacing: 0.8mm,
      box(text(size: 10pt, weight: 500, description)),
      box(text(size: 6pt, weight: 400, "Open Silicon Design")),
    )
  }
  content((x + 18, -y - 225.2), chip-description, anchor: "north-west")
}

#let scaled-chip(size, ..variant) = {
  // Include the outline in the master bounds before scaling the complete chip.
  let artwork = cetz.canvas(length: unit, draw-chip(0, 0, ..variant))
  let master = block(width: chip-native-size, height: chip-native-size, above: 0pt, below: 0pt)[
    #place(top + left, dx: chip-edge / 2, dy: chip-edge / 2, artwork)
  ]
  let factor = size / chip-native-size * 100%
  scale(x: factor, y: factor, origin: top + left, reflow: true, master)
}

#let r1-chip-size = 26.5mm
#let r1-chip(product) = {
  let embedded = product.group == "embedded"
  scaled-chip(r1-chip-size, product-name: product.name, show-icsprout: false,
    description: if embedded { "RISC-V AI MCU" } else { "RISC-V AI SoC" },
    badge: if embedded { "Edge AI" } else { "Physical AI" },
    accent: if embedded { chip-violet } else { chip-warm-yellow })
}

#let cover-chip() = {
  [#block(width: cover-chip-size, height: cover-chip-size, above: 0pt, below: 0pt)[
    #metadata(cover-chip-size / chip-native-size)<tiny-cover-chip-scale>
    #place(top + left, scaled-chip(cover-chip-size, show-icsprout: false))
  ]<tiny-cover-chip-region>]
}

#let r1-product-line(height) = context {
  let products = json("r1-roadmap.json").products
  let embedded-palette = (
    width: 87.4mm,
    heading: rgb("#883ACF"), heading-size: 20.4pt,
    model: rgb("#963ADF"), status: rgb("#962ACB"), pill: rgb("#ECDBFA"),
    dot: gradient.radial(rgb("#C982F3"), rgb("#9C49DE"),
      center: (31%, 24%), radius: 80%, relative: "self"),
  )
  let professional-palette = (
    width: 89.3mm,
    heading: rgb("#B1842A"), heading-size: 20pt,
    model: rgb("#B48629"), status: rgb("#A47414"), pill: rgb("#F5E8CC"),
    dot: gradient.radial(rgb("#DAC079"), rgb("#AE8025"),
      center: (31%, 24%), radius: 80%, relative: "self"),
  )

  let chip-size = r1-chip-size
  let plate-height = 136.4mm
  let column-gap = 1.7mm
  let plate-width = embedded-palette.width + column-gap + professional-palette.width
  let group-inset = 2mm
  let group-height = 128.5mm
  let heading-height = 19.5mm
  let card-gap = 2.15mm
  let card-height = 33.6mm
  let chip-left = 2.1mm
  let title-top = 3.4mm
  let copy-left = chip-left + chip-size + 3mm
  let point-inset = 3.4mm
  let pill-height = 5.2mm
  let positioning-sizes = (MINI: 8.25pt, ULTRA: 7.25pt)
  let panel-fill = gradient.radial(rgb("#EEEEEF"), rgb("#EBEBEC"), rgb("#E1E2E3"),
    center: (38%, 18%), radius: 95%, relative: "self")
  let product-fill = gradient.linear(white, rgb("#FBFBFB"), angle: 90deg)
  assert(height >= plate-height - 0.01pt, message: "R1 product line must fit below Figure 2")

  let product-card(product, palette) = {
    let (name, positioning, highlights, status) = (product.name, product.positioning, product.highlights, product.status)
    let card-width = palette.width - 2 * group-inset
    let copy-width = card-width - copy-left - 1mm
    let chip = [#block(width: chip-size, height: chip-size, above: 0pt, below: 0pt)[
      #place(top + left, r1-chip(product))
    ]<tiny-r1-chip-region>]
    set text(font: "Inter", fill: detail-ink,
      top-edge: "cap-height", bottom-edge: "descender")
    let title-tracking = if name == "ULTRA" { -0.025em } else { 0em }
    let model = text(size: 12pt, weight: "bold", fill: palette.model, tracking: title-tracking, name)
    let position = text(size: positioning-sizes.at(name, default: 8.75pt),
      weight: "semibold", tracking: title-tracking, " — " + positioning)
    let title = box(model + position)
    let pill-text = box(text(size: 8.5pt, weight: "semibold", fill: palette.status,
      top-edge: "bounds", bottom-edge: "bounds", status))
    let pill = block(width: measure(pill-text).width + 5.6mm, height: pill-height,
      fill: palette.pill, radius: pill-height / 2, above: 0pt, below: 0pt)[
      #place(center + horizon, pill-text)
    ]
    assert(measure(title).width <= copy-width, message: "R1 product title exceeds its frame: " + name)

    let copy = [#block(width: copy-width, height: card-height, above: 0pt, below: 0pt)[
      #place(top + left, dy: title-top, title)
      #for (index, highlight) in highlights.enumerate() {
        let point = box(text(font: "Inter", size: 8.25pt, weight: 450, tracking: -0.015em, highlight))
        assert(measure(point).width <= copy-width - point-inset,
          message: "R1 product highlight exceeds its frame: " + name + " / " + highlight)
        let point-top = 10.1mm + index * 4.6mm
        place(top + left, dy: point-top + 0.35mm, circle(radius: 0.7mm, stroke: none, fill: palette.dot))
        place(top + left, dx: point-inset, dy: point-top, point)
      }
      #place(top + left, dy: title-top + chip-size - pill-height, pill)
    ]<tiny-r1-card-copy-region>]
    block(width: card-width, height: card-height, fill: product-fill, radius: 3mm, above: 0pt, below: 0pt)[
      #place(top + left, dx: chip-left, dy: title-top, chip)
      #place(top + left, dx: copy-left, copy)
    ]
  }

  let group(title, group-name, palette) = block(
    width: palette.width, height: group-height, radius: 3.8mm, fill: panel-fill,
    above: 0pt, below: 0pt,
  )[
    #place(top + left, dx: 5.4mm, dy: 5mm,
      text(font: "Inter", size: palette.heading-size, weight: "bold", fill: palette.heading,
        top-edge: "cap-height", bottom-edge: "descender", title))
    #place(top + left, dx: group-inset, dy: heading-height,
      stack(dir: ttb, spacing: card-gap,
        ..products.filter(p => p.group == group-name).map(p => product-card(p, palette))))
  ]

  [#block(width: plate-width, height: plate-height, above: 0pt, below: 0pt, breakable: false)[
    #metadata(chip-size / chip-native-size)<tiny-r1-chip-scale>
    #place(top + left, grid(columns: (embedded-palette.width, professional-palette.width), column-gutter: column-gap,
      group("Embedded & Edge", "embedded", embedded-palette),
      group("Professional Compute", "professional", professional-palette),
    ))
    #place(top + center, dy: group-height + 3.6mm, text(
      font: "Inter", size: 9pt, fill: rgb("#64646C"), top-edge: "cap-height", bottom-edge: "descender",
      "STD summarizes roadmap targets. PRO, MAX and ULTRA illustrate concept positioning.",
    ))
  ]<tiny-r1-product-line-region>]
}

#let feature-highlights(data) = cetz.canvas(length: unit, {
  import cetz.draw: content, line, rect as frame

  let label(x, y, body, size: 9pt, weight: 500, paint: detail-ink, tracking: 0em) = {
    // A snug parent gives each label one continuous gradient across its glyphs.
    content((x, -y), box(text(
      font: "Inter", size: size, weight: weight, fill: paint, tracking: tracking,
      top-edge: "cap-height", bottom-edge: "baseline", body,
    )), anchor: "north")
  }
  let accent(x, y, body, size, tracking: -0.018em) = label(
    x, y, body, size: size, weight: 650, paint: violet, tracking: tracking,
  )
  let count-labels(title, count, caption) = {
    label(0, 27, title)
    accent(0, 85, str(count), 22pt)
    label(0, 163, caption)
  }
  let memory-captions(title, detail) = {
    accent(0, 180, title, 12.5pt)
    label(0, 218, detail)
  }
  // Place the contents relative to the tile's top center.
  let tile(x, y, w, h, contents) = {
    panel(x, y, w, h)
    cetz.draw.group({
      cetz.draw.translate((x + w / 2, -y))
      contents
    })
  }

  let chip-column = (x: 369, width: 463)
  frame((0, 0), (1200, -674), stroke: none, fill: white)
  // Top row: on-chip storage and multimedia interfaces.
  tile(7, 14, 352, 154, {
    label(0, 13, "On-chip")
    accent(0, 48, str(data.facts.sram.CapacityKiB) + " KiB", 28pt)
    label(0, 121, "SRAM")
  })
  tile(chip-column.x, 14, chip-column.width, 154, {
    label(0, 13, "Camera input", size: 10pt)
    accent(0, 52, "8-bit DVP", 23.5pt)
    label(0, 118, "RGB565 / YUV422", size: 10pt)
  })
  tile(842, 14, 351, 154, {
    accent(0, 22, "16/24-bit", 24.5pt)
    label(0, 88, "Stereo I²S", size: 11pt, weight: 600)
    label(0, 121, "TX and RX")
  })

  // Left of the chip, PPALite spans the two columns.
  tile(7, 179, 172, 166, {
    accent(0, 37, "55nm", 22pt)
    label(0, 98, "Open-source")
    label(0, 125, "PDK")
  })
  tile(189, 179, 170, 166, {
    accent(0, 32, "Camera capture", 9pt, tracking: -0.060em)
    accent(0, 63, "Stereo audio", 9pt)
    accent(0, 95, "SPI LCD", 9pt)
    accent(0, 117, "preview", 9pt)
  })
  tile(7, 355, 352, 164, {
    label(0, 13, "Inline")
    accent(0, 48, "PPALite", 14pt)
    label(0, 95, "Pixel sampling")
    label(0, 122, "Extract luma")
  })
  tile(7, 529, 167, 133, {
    accent(0, 38, "4-bit", 20pt)
    label(0, 92, "SDIO host")
  })
  tile(184, 529, 175, 133, {
    label(0, 23, "Two alternate")
    label(0, 47, "modes")
    accent(0, 83, str(data.gpio.len()) + " GPIOs", 14.5pt)
  })

  panel(chip-column.x, 179, chip-column.width, 373)
  draw-chip(456, 222)
  tile(chip-column.x, 562, chip-column.width, 100, {
    label(0, 21, "Audio capture and playback", size: 9.25pt, weight: 600)
    label(0, 54, "Camera preview on SPI LCD", size: 9.25pt, weight: 600)
  })

  // Right of the chip, both rows share one column divider.
  tile(842, 179, 159, 216, count-labels("Central DMA", data.facts.dma.NumChannels, "Channels"))
  tile(1011, 179, 182, 216, count-labels("Hazard3 hart", 1, data.facts.hardware_isa))
  tile(842, 405, 159, 257, {
    frame((-52, -15), (52, -83), stroke: schematic-stroke)
    frame((-52, -94), (52, -162), stroke: (paint: rgb("#9D64DF"), thickness: 0.55pt, dash: "dashed"))
    label(0, 28, "NOR")
    label(0, 55, "Boot")
    label(0, 107, "PSRAM")
    label(0, 134, "Optional")
    memory-captions("XPI", "Memory port")
  })
  tile(1011, 405, 182, 257, {
    let banks = data.address_map.sram_banks
    for i in range(banks.len()) {
      let x = -63 + calc.rem(i, 2) * 65
      let y = 49.5 + calc.floor(i / 2) * 48
      frame((x, -y), (x + 61, -y - 44), stroke: schematic-stroke)
      frame((x + 5, -y - 5), (x + 56, -y - 30), stroke: 0.35pt + rgb("#B382EB"))
      line((x + 5, -y - 35), (x + 56, -y - 35), stroke: schematic-stroke)
    }
    memory-captions(str(banks.len()) + " groups", "Main SRAM")
  })
})
