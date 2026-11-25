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
  accent: chip-violet, show-icsprout: true,
) = {
  import cetz.draw: content

  // The logo paths retain the circuit cutouts and the wordmark counters.
  let chip-logo(cx, slot-width, logo) = {
    let scale = calc.min(slot-width / logo.width, 32 / logo.height) * unit
    let commands = logo.rings.map(ring => {
      let points = ring.map(p => (p.at(0) * scale, p.at(1) * scale))
      (curve.move(points.first()),) + points.slice(1).map(p => curve.line(p)) + (curve.close(),)
    }).flatten()
    content((x + cx, -y - 34), curve(..commands, fill: white, stroke: none, fill-rule: "even-odd"), anchor: "center")
  }

  // The chip labels and marks are illustrative artwork.
  let chip-fill = gradient.linear(rgb("#44434B"), rgb("#171719"), angle: 45deg)
  panel(x, y, chip-side, chip-side, fill: chip-fill, radius: 0, stroke: chip-edge + rgb("#525158"))
  // Figure 2's disc aligns with the visible R1 edge, 1.65 mm from ICsprout.
  chip-logo(38.32432, 62, chip-logos.ecos)
  if show-icsprout {
    chip-logo(103.82048, 76, chip-logos.icsprout)
  }
  // The longer badge retains its text padding.
  let (badge-left, badge-width) = if badge == "Physical AI" { (149, 133) } else { (175, 96) }
  panel(x + badge-left, y + 18, badge-width, 32, fill: accent.light, radius: 8)
  content((x + badge-left + badge-width / 2, -y - 34), box(text(
    font: "Inter", size: 9pt, weight: 700, fill: detail-ink,
    top-edge: "bounds", bottom-edge: "bounds", badge,
  )), anchor: "center")

  let chip-mark = {
    set text(font: "Inter", fill: rgb("#FAFAFB"), top-edge: "cap-height", bottom-edge: "baseline")
    let model = text(size: 30pt, weight: 650, tracking: -0.022em, "R1")
    // Limit the gradient to the product word within the shared baseline.
    let product = box(text(size: 16pt, weight: 650,
      fill: gradient.linear(accent.light, accent.dark, angle: 0deg, relative: "parent"), product-name))
    box(model + h(1.8mm) + product)
  }
  content((x + 18, -y - 159.6234), chip-mark, anchor: "north-west")

  let chip-description = {
    set text(font: "Inter", fill: rgb("#FAFAFB"), top-edge: "cap-height", bottom-edge: "descender")
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

#let cover-chip() = {
  [#block(width: cover-chip-size, height: cover-chip-size, above: 0pt, below: 0pt)[
    #metadata(cover-chip-size / chip-native-size)<tiny-cover-chip-scale>
    #place(top + left, scaled-chip(cover-chip-size, show-icsprout: false))
  ]<tiny-cover-chip-region>]
}

#let r1-product-line(height) = {
  let size = 24mm
  let gap = 3mm
  assert(height >= size + gap, message: "R1 product line must fit below Figure 2")

  let group(products, description, badge, accent: chip-violet) = rect(
    width: 84mm, height: height, radius: card-radius * unit, stroke: none, fill: card-fill,
    inset: (top: gap, left: gap, right: gap, bottom: 0pt),
    align(top + left, grid(columns: (size, size, size), column-gutter: gap, ..products.map(product => [
      #block(width: size, height: size, above: 0pt, below: 0pt)[
        #place(top + left, scaled-chip(
          size, product-name: product, description: description, badge: badge, accent: accent,
          show-icsprout: false,
        ))
      ]<tiny-r1-chip-region>
    ]))),
  )

  [#block(width: 172mm, height: height, above: 0pt, below: 0pt, breakable: false)[
    #metadata(size / chip-native-size)<tiny-r1-chip-scale>
    #place(top + left, grid(columns: (84mm, 84mm), column-gutter: 4mm,
      group(("TINY", "MINI", "STD"), "RISC-V AI MCU", "Edge AI"),
      group(("PRO", "MAX", "ULTRA"), "RISC-V AI SoC", "Physical AI", accent: chip-warm-yellow),
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
  let accent(x, y, body, size) = label(x, y, body, size: size, weight: 650, paint: violet, tracking: -0.018em)

  frame((0, 0), (1200, -674), stroke: none, fill: white)
  for (x, y, w, h) in (
    (14, 14, 167, 154), (191, 14, 168, 154), (369, 14, 167, 154), (546, 14, 286, 154), (842, 14, 345, 154),
    (14, 179, 345, 209), (14, 398, 167, 154), (191, 398, 168, 154), (14, 562, 345, 100),
    (369, 179, 463, 373), (369, 562, 463, 100),
    (842, 179, 167, 264), (1019, 179, 168, 264), (842, 453, 345, 209),
  ) { panel(x, y, w, h) }

  // Five tiles across the top.
  frame((82, -41), (113, -104), stroke: 0.7pt + detail-ink)
  label(97.5, 117, "Open-source")
  label(97.5, 141, "MCU")
  label(275, 29, "Hazard3 hart")
  accent(275, 69, "1", 22pt)
  label(275, 139, data.facts.hardware_isa)
  label(452.5, 29, "Central DMA")
  accent(452.5, 69, str(data.facts.dma.NumChannels), 22pt)
  label(452.5, 139, "Channels")
  for (y, title) in ((48, "Camera capture"), (77, "Stereo audio"), (106, "SPI LCD preview")) {
    accent(689, y, title, 10.5pt)
  }
  label(1014.5, 29, "On-chip")
  accent(1014.5, 59, str(data.facts.sram.CapacityKiB) + " KiB", 28pt)
  label(1014.5, 139, "SRAM")

  // Camera and media application tiles below the left-hand metrics.
  label(186.5, 214, "Camera input", size: 10pt)
  accent(186.5, 258, "8-bit DVP", 23.5pt)
  label(186.5, 326, "RGB565 / YUV422", size: 10pt)
  label(97.5, 412, "Inline")
  accent(97.5, 448, "PPALite", 14pt)
  label(97.5, 490, "Pixel sampling")
  label(97.5, 522, "Extract luma")
  accent(275, 456, "4-bit", 20pt)
  label(275, 522, "SDIO host")
  label(186.5, 586, "Audio capture and playback", size: 9.25pt, weight: 600)
  label(186.5, 619, "Camera preview on SPI LCD", size: 9.25pt, weight: 600)

  draw-chip(456, 222)
  label(600.5, 578, "Two alternate modes")
  accent(600.5, 605, str(data.gpio.len()) + " GPIOs", 19pt)

  // The two tall tiles use logical memory views in place of die illustrations.
  let banks = data.address_map.sram_banks
  for i in range(banks.len()) {
    let x = 862 + calc.rem(i, 2) * 65
    let y = 232 + calc.floor(i / 2) * 48
    frame((x, -y), (x + 61, -y - 44), stroke: schematic-stroke)
    frame((x + 5, -y - 5), (x + 56, -y - 30), stroke: 0.35pt + rgb("#B382EB"))
    line((x + 5, -y - 35), (x + 56, -y - 35), stroke: schematic-stroke)
  }
  accent(925.5, 382, str(banks.len()) + " groups", 12.5pt)
  label(925.5, 418, "Main SRAM")
  frame((1051, -203), (1155, -271), stroke: schematic-stroke)
  frame((1051, -282), (1155, -350), stroke: (paint: rgb("#9D64DF"), thickness: 0.55pt, dash: "dashed"))
  label(1103, 216, "NOR")
  label(1103, 243, "Boot")
  label(1103, 295, "PSRAM")
  label(1103, 322, "Optional")
  accent(1103, 382, "XPI", 12.5pt)
  label(1103, 418, "Memory port")

  accent(1014.5, 510, "16/24-bit", 24.5pt)
  label(1014.5, 577, "Stereo I²S", size: 11pt, weight: 600)
  label(1014.5, 616, "TX and RX")
})
