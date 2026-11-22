#import "@preview/cetz:0.5.2" as cetz
#import "soc-palette.typ": domain-fill, rail-fill
#import "style.typ": ink

#let smartwatch(model) = {
  set text(font: "Inter", size: 9pt, weight: "regular", fill: ink)
  let links = model.links
  let title(body) = text(weight: "semibold", body)
  let wire = 0.65pt + ink
  let icon = 0.85pt + ink
  cetz.canvas(length: 1mm, {
    import cetz.draw: rect, line, content, circle, bezier, merge-path
    let p(x, y) = (x, -y)
    let print(x, y, body, anchor: "center") = content(p(x, y), body, anchor: anchor)
    let box(left, top, right, bottom, fill, optional: false, weight: 0.6pt) = {
      rect(p(left, top), p(right, bottom), fill: fill,
        stroke: (paint: ink, thickness: weight, dash: if optional { "dashed" } else { none }))
    }
    let card(left, top, right, bottom, fill, rows, optional: false) = {
      box(left, top, right, bottom, fill, optional: optional)
      for (i, row) in rows.enumerate() {
        print((left + right) / 2, (top + bottom) / 2 + (i - (rows.len() - 1) / 2) * 4.35, row)
      }
    }
    let route(..points, both: false) = {
      line(..points.pos().map(point => p(..point)), stroke: wire,
        mark: if both { (start: "stealth", end: "stealth") } else { (end: "stealth") })
    }
    let signal(x, y, body) = print(x, y - 2.65, body)

    let battery(x, y) = {
      rect(p(x - 3.7, y - 2), p(x + 3.1, y + 2), stroke: icon)
      rect(p(x + 3.1, y - 0.95), p(x + 4.2, y + 0.95), stroke: none, fill: ink)
      rect(p(x - 2.8, y - 1.15), p(x + 0.8, y + 1.15), stroke: none, fill: ink)
    }
    let usb(x, y) = {
      bezier(p(x - 2.4, y - 1.7), p(x - 2.4, y + 1.7), p(x - 4.5, y - 1.7), p(x - 4.5, y + 1.7), stroke: icon)
      bezier(p(x + 2.4, y - 1.7), p(x + 2.4, y + 1.7), p(x + 4.5, y - 1.7), p(x + 4.5, y + 1.7), stroke: icon)
      line(p(x - 2.4, y - 1.7), p(x + 2.4, y - 1.7), stroke: icon)
      line(p(x - 2.4, y + 1.7), p(x + 2.4, y + 1.7), stroke: icon)
      line(p(x - 2, y), p(x + 2, y), stroke: icon)
    }
    let bluetooth(x, y) = {
      let half-width = 1.8
      let half-height = 2.375
      merge-path(close: true, fill: rgb("#0082FC"), stroke: none, {
        bezier(p(x, y - half-height), p(x + half-width, y),
          p(x + 1.4, y - half-height), p(x + half-width, y - 1.55))
        bezier(p(x + half-width, y), p(x, y + half-height),
          p(x + half-width, y + 1.55), p(x + 1.4, y + half-height))
        bezier(p(x, y + half-height), p(x - half-width, y),
          p(x - 1.4, y + half-height), p(x - half-width, y + 1.55))
        bezier(p(x - half-width, y), p(x, y - half-height),
          p(x - half-width, y - 1.55), p(x - 1.4, y - half-height))
      })
      let glyph = 0.65pt + white
      line(p(x, y + 1.65), p(x, y - 1.65), p(x + 0.94, y - 0.78), p(x - 0.94, y + 0.98), stroke: glyph)
      line(p(x - 0.94, y - 0.98), p(x + 0.94, y + 0.78), p(x, y + 1.65), stroke: glyph)
    }
    let wifi(x, y) = {
      bezier(p(x - 3.2, y - 0.7), p(x + 3.2, y - 0.7), p(x - 1.35, y - 2.9), p(x + 1.35, y - 2.9), stroke: icon)
      bezier(p(x - 2.1, y + 0.55), p(x + 2.1, y + 0.55), p(x - 0.8, y - 0.9), p(x + 0.8, y - 0.9), stroke: icon)
      circle(p(x, y + 1.7), radius: 0.57, stroke: none, fill: ink)
    }
    let microphone(x, y) = {
      for offset in (-1.65, 0.35) {
        circle(p(x, y + offset), radius: 1.22, stroke: none, fill: ink)
      }
      rect(p(x - 1.22, y - 1.65), p(x + 1.22, y + 0.35), fill: ink, stroke: none)
      bezier(p(x - 2.23, y - 0.35), p(x + 2.23, y - 0.35), p(x - 2.23, y + 3), p(x + 2.23, y + 3), stroke: icon)
      line(p(x, y + 2.1), p(x, y + 3.6), stroke: icon)
      line(p(x - 1.3, y + 3.6), p(x + 1.3, y + 3.6), stroke: icon)
    }
    let speaker(x, y) = {
      line(p(x - 3.4, y - 1.25), p(x - 2.15, y - 1.25), p(x + 0.15, y - 2.95),
        p(x + 0.15, y + 2.95), p(x - 2.15, y + 1.25), p(x - 3.4, y + 1.25),
        close: true, fill: ink, stroke: none)
      bezier(p(x + 1, y - 1.35), p(x + 1, y + 1.35), p(x + 1.85, y - 0.55), p(x + 1.85, y + 0.55), stroke: icon)
      bezier(p(x + 2.25, y - 2.2), p(x + 2.25, y + 2.2), p(x + 3.55, y - 1), p(x + 3.55, y + 1), stroke: icon)
    }

    rect(p(0, 0), p(172, 194), fill: white, stroke: none)
    print(1, 4.3, title([REFERENCE ONLY]), anchor: "west")
    line(p(113, 4.3), p(120, 4.3), stroke: (paint: ink, thickness: 0.6pt, dash: "dashed"))
    print(122, 4.3, [Optional / alternate], anchor: "west")

    // USB power and service data leave the same connector on separate paths.
    box(3, 11, 46, 22, rail-fill)
    usb(13, 16.5)
    print(30, 16.5, title([USB-C]))
    route((24, 22), (24, 30))
    print(26, 26, [VBUS], anchor: "west")
    card(3, 30, 46, 40, rail-fill, (title([ESD / OVP]), [USB power protection]))
    route((24, 40), (24, 45))
    card(3, 45, 30.5, 58, rail-fill, (title([Charger]), [Power path]))
    box(35, 45, 46, 58, rail-fill)
    battery(40.4, 49.4)
    print(40.5, 54.9, [BAT])
    route((30.5, 51.5), (35, 51.5), both: true)
    route((16.5, 58), (16.5, 63))
    card(3, 63, 46, 75, rail-fill, (title([Load switch]), links.power.rails + " LDOs"))
    route((46, 69), (61, 69))
    signal(53.5, 69, [Rails])

    // XPI flash and optional PSRAM share the bus with independent selects.
    card(61, 24, 85, 36, domain-fill.memory, (title([Boot NOR]), links.memory.boot_cs))
    card(89, 24, 113, 36, domain-fill.memory, (title([PSRAM]), links.memory.ram_cs), optional: true)
    line(p(73, 36), p(73, 40.5), p(101, 40.5), p(101, 36), stroke: wire)
    line(p(87, 40.5), p(87, 46), stroke: wire)
    circle(p(87, 40.5), radius: 0.66, fill: ink, stroke: none)
    print(91, 43.25, links.memory.bus, anchor: "west")

    box(61, 46, 113, 165, domain-fill.system, weight: 0.9pt)
    print(87, 52, text(size: 11pt, weight: "bold")[retroSoC Tiny Gen1])
    print(87, 57.5, [Host microcontroller])
    card(64, 63, 110, 87, white, (
      title("Hazard3 " + model.hardware_isa),
      "AXI" + str(model.axi_width) + " / APB4",
      str(model.dma_channels) + "-channel DMA",
    ))
    card(64, 90, 110, 104, domain-fill.memory, (title(str(model.sram_kib) + " KiB SRAM"), [XPI controller]))
    card(64, 107, 110, 125, domain-fill.aon, (
      title([Clock and system control]), [RCU · RTC · WDG], [Timer 0/1 · CLINT], [SYSCTRL · ARCHINFO],
    ))
    card(64, 128, 110, 140, white, (title([CRC · CRYPTO · RNG]),))
    card(64, 143, 110, 162, domain-fill.peripheral, (
      title([Peripheral interfaces]),
      links.display.bus + " · " + links.sensing.bus + " · " + links.serial.bus,
      links.sd.bus + " · PWM · GPIO",
      links.audio.bus + " · " + links.actuation.rgb,
    ))

    card(3, 79, 46, 90, domain-fill.aon, (title(links.power.clock), [External oscillator]))
    route((46, 84.5), (61, 84.5))
    signal(53.5, 84.5, [XIN])
    card(3, 94, 46, 105, domain-fill.aon, (title([Reset key / supervisor]), [RESET_N]))
    route((46, 99.5), (61, 99.5))
    card(3, 109, 46, 120, domain-fill.jtag, (title([JTAG header]), [Debug / NOR loader]))
    route((46, 114.5), (61, 114.5), both: true)

    box(3, 123.5, 46, 152.5, domain-fill.peripheral)
    print(24.5, 127.1, title([Touch via FPC]))
    for (i, sensor) in links.sensing.sensors.enumerate() {
      print(24.5, 131.3 + 3.55 * i, sensor)
    }
    card(4.7, 145.4, 24.2, 151.1, white, (links.sensing.nfc,))
    card(25, 145.4, 44.4, 151.1, white, (links.sensing.gnss,))
    route((46, 136.7), (61, 136.7), both: true)
    signal(53.5, 136.7, links.sensing.bus)
    card(3, 155.5, 46, 165, domain-fill.peripheral, (title([Function key · Header]), links.io.expansion))
    route((46, 160.25), (61, 160.25), both: true)
    signal(53.5, 160.25, [I/O])

    // The three alternatives terminate at the assembly selector.
    box(126, 21.5, 171, 65, domain-fill.peripheral, optional: true)
    card(128, 23, 167, 32, domain-fill.jtag, (title(links.serial.options.service + " bridge"),))
    route((46, 16.5), (149, 16.5), (149, 23), both: true)
    signal(100, 16.5, [D+/D−])
    box(128, 37, 145, 49, white)
    bluetooth(131.8, 43)
    print(139.7, 43, title(links.serial.options.ble))
    box(150, 37, 168, 49, white)
    wifi(154.3, 43)
    print(162.4, 43, title(links.serial.options.wifi))
    card(128, 55, 168, 62.5, white, (title(links.serial.selection),))
    for (x, y) in ((136, 49), (147.5, 32), (159, 49)) {
      route((x, y), (x, 55), both: true)
    }
    route((113, 58.75), (128, 58.75), both: true)
    signal(119.5, 58.75, links.serial.bus)

    card(126, 69, 171, 87, domain-fill.memory, (
      title([TF / microSD]), text(links.sd.width + " · " + links.sd.bus), [Detect · load switch],
    ))
    route((113, 74.2), (126, 74.2), both: true)
    signal(119.5, 74.2, links.sd.bus)
    route((113, 83), (126, 83), both: true)
    signal(119.5, 83, [GPIO])

    box(126, 90, 171, 111, domain-fill.peripheral)
    card(128, 91.5, 169, 100, white, (title([Write-only LCD via FPC]),))
    card(128, 103, 169, 109.5, white, ([Backlight driver],))
    route((113, 95.75), (128, 95.75))
    signal(119.8, 95.75, links.display.bus)
    route((113, 106.25), (128, 106.25))
    signal(119.8, 106.25, links.display.backlight)
    route((148.5, 103), (148.5, 100))

    let codec-left = 128
    let codec-content-left = codec-left + 2.5
    let converter-right = 147
    let converter-center = (codec-content-left + converter-right) / 2
    box(codec-left, 114.5, 171, 145, domain-fill.audio)
    print(codec-content-left, 117.6, title(links.audio.bus + " codec"), anchor: "west")
    route((113, 116.8), (codec-left, 116.8))
    signal(120.5, 116.8, [Clocks])
    box(codec-content-left, 120, converter-right, 135, white)
    line(p(codec-content-left, 127.5), p(converter-right, 127.5), stroke: wire)
    print(converter-center, 123.75, [ADC])
    print(converter-center, 131.25, [DAC])
    microphone(165, 123.3)
    route((161.6, 123.75), (converter-right, 123.75))
    route((codec-content-left, 123.75), (113, 123.75))
    signal(120.5, 123.75, links.audio.adc)
    route((113, 131.25), (codec-content-left, 131.25))
    signal(120.5, 131.25, links.audio.dac)
    card(149.8, 128.25, 159.5, 134.25, white, ([Amp],))
    route((converter-right, 131.25), (149.8, 131.25))
    route((159.5, 131.25), (163.3, 131.25))
    speaker(167.2, 131.25)
    card(codec-content-left, 137.5, 169, 143.5, domain-fill.aon, ([Independent ref. clock],))
    route((codec-content-left, 140.5), (113, 140.5))
    signal(120.5, 140.5, links.audio.ref_clock)

    card(126, 148, 171, 155, domain-fill.peripheral, ([Motor driver + motor],))
    route((113, 151.5), (126, 151.5))
    signal(119.5, 151.5, links.actuation.motor)
    card(129, 158, 171, 165, domain-fill.peripheral, ([Addressable RGB LED],))
    route((113, 161.5), (129, 161.5))
    signal(121, 161.5, links.actuation.rgb)

    // This population option reuses the watch audio/PWM/expansion pads.
    box(1, 169.5, 171, 193.5, domain-fill.dvp_pixel, optional: true)
    print(4, 173.6, title([Camera assembly option]), anchor: "west")
    print(93, 173.6, [Replaces audio, PWM and expansion])
    print(167, 173.6, links.camera.pads, anchor: "east")
    card(4, 178.5, 30, 191.8, white, (title([Camera]), [I²C0 setup]))
    card(54, 178.5, 95, 188, white, (title("RAW " + links.camera.bus), [or PPALite PROCESS]))
    card(106, 178.5, 124, 188, white, (title([DMA2]),))
    card(135, 178.5, 168, 188, white, (title([SRAM]), [or initialized PSRAM]))
    card(54, 188.8, 95, 192.7, domain-fill.aon, ([RCU CLKOUT],))
    route((30, 183), (54, 183))
    signal(42, 183, "Data + sync")
    route((54, 190.75), (30, 190.75))
    signal(42, 190.75, links.camera.clock_out)
    route((95, 183.25), (106, 183.25))
    route((124, 183.25), (135, 183.25))
  })
}
