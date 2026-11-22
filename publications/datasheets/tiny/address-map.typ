#import "@preview/cetz:0.5.2" as cetz
#import "style.typ": ink, gold, pale-gold, gray, rule, mono, window-size

#let point(x, y) = (x, -y)
#let hex32(value) = {
  let digits = upper(str(value, base: 16))
  "0x" + "00000000".slice(0, 8 - digits.len()) + digits
}
#let addresses(band) = text(font: mono, size: 9pt, hex32(band.base) + " – " + hex32(band.end))
#let capacity(bytes) = window-size((size: bytes, size_label: str(int(bytes / 1024)) + " KiB"))

#let address-map(model) = {
  set text(font: "Inter", size: 9pt, fill: ink)
  let left = 0.4
  let left-end = 58.3
  let right = 69.4
  let right-end = 171.6
  let overview-top = 9
  let overview-height = 10
  let header-height = 8
  let apb-height = 4.8
  let panel-gap = 6
  let heights = model.apb_groups.map(group => header-height + group.bands.len() * apb-height)
  let panel-tops = (0.4, 0.4 + heights.first() + panel-gap)
  let overview-end = overview-top + model.overview.len() * overview-height
  let panels-end = panel-tops.last() + heights.last()
  let notes-top = panels-end + 6.2
  let notes = (
    [Address ranges include both endpoints. Band heights are schematic.],
    [GPIO Data and GPIO Admin share one target. RCU registers are within SYSCTRL.],
    [Valid AXI requests to unmapped addresses return #text(font: mono)[DECERR].],
    [Flash and XPI ranges are decode apertures. Usable capacity depends on the device and slot configuration.],
  )
  cetz.canvas(length: 1mm, {
    import cetz.draw: rect, line, content, circle
    let print(x, y, label, anchor: "west") = content(point(x, y), label, anchor: anchor)
    let box(x1, x2, y, height, fill, stroke: 0.55pt + ink) = {
      rect(point(x1, y), point(x2, y + height), fill: fill, stroke: stroke)
    }
    box(0, 172, 0, notes-top + 16.4, white, stroke: none)

    // Only the two source ranges expand across the gutter.
    for (i, group) in model.apb_groups.enumerate() {
      let index = model.overview.position(band => band.at("symbol", default: none) == group.symbol)
      let y = overview-top + index * overview-height
      let top = panel-tops.at(i) + header-height
      let bottom = panel-tops.at(i) + heights.at(i)
      line(point(left-end, y), point(right, top), point(right, bottom), point(left-end, y + overview-height),
        close: true, fill: pale-gold, stroke: 0.6pt + gold)
    }

    print(left, 4, text(size: 10pt, weight: "bold")[32-bit address space])
    for (i, band) in model.overview.enumerate() {
      let y = overview-top + i * overview-height
      let selected = band.kind == "apb-group" or band.at("symbol", default: none) == "SRAM"
      let fill = if selected { pale-gold } else if band.kind == "unmapped" { gray } else { white }
      box(left, left-end, y, overview-height, fill, stroke: if selected { 0.6pt + gold } else { 0.55pt + ink })
      let label = band.name + if band.kind == "memory" { " · " + capacity(band.size) } else { "" }
      print(left + 2, y + 2.8, text(weight: if band.kind == "unmapped" { "regular" } else { "semibold" }, label))
      print(left + 2, y + 7.1, addresses(band))
    }
    let reset-x = left + 2.1
    line(point(reset-x, overview-end), point(reset-x, overview-end + 5.6), stroke: 0.65pt + gold)
    circle(point(reset-x, overview-end), radius: 0.65mm, fill: gold, stroke: none)
    print(reset-x + 2, overview-end + 5.6, [Reset entry · #text(font: mono, hex32(model.reset))])

    let sram-top = overview-end + 13.3
    box(left, left-end, sram-top, header-height, pale-gold, stroke: 0.6pt + gold)
    print(left + 2, sram-top + header-height / 2,
      text(size: 10pt, weight: "bold")[SRAM banks · #capacity(model.sram_banks.first().size) each])
    for (i, bank) in model.sram_banks.enumerate() {
      let y = sram-top + header-height + i * 7.6
      box(left, left-end, y, 7.6, white)
      print(left + 2, y + 3.8, strong(bank.name))
      print(left-end - 2, y + 3.8, addresses(bank), anchor: "east")
    }

    for (i, group) in model.apb_groups.enumerate() {
      let top = panel-tops.at(i)
      box(right, right-end, top, header-height, pale-gold, stroke: 0.6pt + gold)
      print(right + 2, top + header-height / 2, text(size: 10pt, weight: "bold", group.name))
      print(right-end - 2, top + header-height / 2, addresses(group), anchor: "east")
      for (row, band) in group.bands.enumerate() {
        let y = top + header-height + row * apb-height
        box(right, right-end, y, apb-height, if band.kind == "unmapped" { gray } else { white })
        let label = band.name + if band.at("symbol", default: none) == "APB4_CLINT" { " (" + capacity(band.size) + ")" } else { "" }
        print(right + 2, y + apb-height / 2, label)
        print(right-end - 2, y + apb-height / 2, addresses(band), anchor: "east")
      }
    }

    line(point(left, panels-end + 2.7), point(right-end, panels-end + 2.7), stroke: 0.65pt + rule)
    for (i, note) in notes.enumerate() { print(left, notes-top + 4.2 * i, note) }
  })
}
