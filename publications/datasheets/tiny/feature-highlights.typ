#import "@preview/cetz:0.5.2" as cetz

// The design coordinates follow the 1200 × 674 reference. All geometry uses
// the same scale at the 172 mm publication width.
#let unit = 172mm / 1200
#let card-fill = rgb("#EDEDED")
#let detail-ink = rgb("#171717")
#let violet = gradient.linear(rgb("#C392F7"), rgb("#8345DC"), angle: 0deg, relative: "parent")
#let schematic-stroke = 0.55pt + rgb("#9D64DF")

#let feature-highlights(data) = cetz.canvas(length: unit, {
  import cetz.draw: content, line, rect as frame

  let panel(x, y, w, h, fill: card-fill, radius: 24, stroke: none) = {
    content((x, -y), box(rect(
      width: w * unit, height: h * unit, radius: radius * unit,
      fill: fill, stroke: stroke, inset: 0pt,
    )), anchor: "north-west")
  }
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

  // The reserved logo area and chip mark are illustrative artwork.
  let chip-fill = gradient.linear(rgb("#44434B"), rgb("#171719"), angle: 45deg)
  panel(456, 222, 289, 289, fill: chip-fill, radius: 0, stroke: 0.55pt + rgb("#525158"))
  frame((511, -317), (575, -384), stroke: 0.65pt + rgb("#D1CDD9"))
  label(637, 328, "R1", size: 30pt, weight: 650, paint: rgb("#FAFAFB"), tracking: -0.022em)
  label(600.5, 404, "TINY", size: 16pt, weight: 650,
    paint: gradient.linear(rgb("#EAD7FB"), rgb("#8345DC"), angle: 0deg, relative: "parent"))
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
