#import "@preview/cetz:0.5.2" as cetz
#import "soc-palette.typ": domain-fill, rail-fill
#import "style.typ": ink

#let smartwatch(model) = {
  set text(font: "Inter", size: 9pt, weight: "regular", fill: ink)
  let links = model.links
  let title(body) = text(weight: "semibold", body)
  let signal-stroke = 0.65pt + ink
  cetz.canvas(length: 1mm, {
    import cetz.draw: rect, line, content, circle
    let p(x, y) = (x, -y)
    let print(x, y, body, anchor: "center") = content(p(x, y), body, anchor: anchor)
    let box(left, top, right, bottom, fill, optional: false, weight: 0.6pt) = {
      rect(p(left, top), p(right, bottom), fill: fill,
        stroke: (paint: ink, thickness: weight, dash: if optional { "dashed" } else { none }))
    }
    let card(left, top, right, bottom, fill, rows, optional: false) = {
      box(left, top, right, bottom, fill, optional: optional)
      for (i, row) in rows.enumerate() {
        print((left + right) / 2, (top + bottom) / 2 + (i - (rows.len() - 1) / 2) * 4.5, row)
      }
    }
    let route(x1, y1, x2, y2, both: false) = {
      line(p(x1, y1), p(x2, y2), stroke: signal-stroke,
        mark: if both { (start: "stealth", end: "stealth") } else { (end: "stealth") })
    }
    let link-label(x, y, body) = print(x, y - 2.8, body)
    rect(p(0, 0), p(172, 124), fill: white, stroke: none)
    print(0.5, 7, title([REFERENCE ONLY]), anchor: "west")
    line(p(0.5, 14), p(7, 14), stroke: (paint: ink, thickness: 0.6pt, dash: "dashed"))
    print(9, 14, [Optional], anchor: "west")

    // External memory branches have a shared bus and independent selects.
    card(48, 4, 80, 17, domain-fill.memory, (title([Boot NOR]), links.memory.boot_cs))
    card(84, 4, 116, 17, domain-fill.memory, (title([PSRAM]), links.memory.ram_cs), optional: true)
    line(p(64, 17), p(64, 23), p(100, 23), p(100, 17), stroke: signal-stroke)
    line(p(82, 23), p(82, 34), stroke: signal-stroke)
    circle(p(82, 23), radius: 0.65, fill: ink, stroke: none)
    print(85, 28, links.memory.bus + " shared bus", anchor: "west")

    // The host boundary contains only on-chip functions used by the example.
    box(50, 34, 116, 122, domain-fill.system, weight: 0.9pt)
    print(83, 39.5, text(size: 11pt, weight: "bold")[retroSoC Tiny Gen1])
    print(83, 45, [Host microcontroller])
    card(54, 51, 112, 68, white, (
      title("Hazard3 " + model.hardware_isa),
      "AXI" + str(model.axi_width) + " / APB4 · " + str(model.dma_channels) + "-channel DMA",
    ))
    card(54, 71, 82, 89, domain-fill.memory, (title(str(model.sram_kib) + " KiB SRAM"), links.memory.bus))
    card(85, 71, 112, 89, domain-fill.aon, (title([RCU / RTC]), [Clock and time]))
    card(54, 92, 112, 105, domain-fill.peripheral, (
      title(links.display.bus + " · " + links.sensing.bus + " · " + links.ble.bus),
      [GPIO / PWM0],
    ))
    card(54, 108, 112, 118, domain-fill.audio, (title(links.audio.bus + " master"),))

    card(0.5, 21, 36, 32, rail-fill, (title([Battery]),))
    route(18.25, 32, 18.25, 37)
    card(0.5, 37, 36, 50, rail-fill, (title([External charger]), "PMIC · " + links.power.rails))
    route(36, 43.5, 50, 43.5)
    link-label(43, 43.5, [Rails])

    card(0.5, 56, 36, 70, domain-fill.aon, (title(links.power.clock), [External clock]))
    route(36, 63, 50, 63)
    link-label(43, 63, [XIN])

    card(0.5, 79, 36, 114, domain-fill.peripheral, (
      title([Touch and sensors]), [Touch controller], [IMU], [Optical front end],
    ))
    route(36, 96.5, 50, 96.5, both: true)
    link-label(43, 96.5, links.sensing.bus)

    card(138, 35, 171.5, 49, domain-fill.peripheral, (title([SPI LCD]), [Write-only]))
    route(116, 42, 138, 42)
    link-label(127, 42, links.display.bus + " + GPIO")
    card(138, 54, 171.5, 67, domain-fill.peripheral, (title([Backlight driver]), [External]))
    route(116, 60.5, 138, 60.5)
    link-label(127, 60.5, links.display.pwm)
    route(154.75, 54, 154.75, 49)

    card(138, 71, 171.5, 82, domain-fill.peripheral, (title([BLE module]),), optional: true)
    route(116, 76.5, 138, 76.5, both: true)
    link-label(127, 76.5, links.ble.bus)

    box(138, 86, 171.5, 122, domain-fill.audio, optional: true)
    card(140, 88, 169.5, 98, white, (title([Codec / amplifier]),))
    route(154.75, 98, 154.75, 102)
    print(154.75, 104.5, [Speaker])
    card(140, 110, 169.5, 119, domain-fill.aon, ([Audio ref. clock],))
    route(116, 93, 140, 93, both: true)
    link-label(127, 93, links.audio.bus)
    route(140, 114.5, 116, 114.5)
    link-label(127, 114.5, links.audio.ref_clock)
  })
}
