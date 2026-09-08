#import "@preview/jogs:0.2.4": compile-js, call-js-function
#import "style.typ": ink, gold, muted, data, rhythm
#let wave-bytecode=compile-js(read(data.wave_renderer))

// Thread the palette index through nested WaveDrom groups without mutating
// the source dictionary. Codes 2-9 and '=' differ only in bus fill color.
#let color-signals(signals, start: 0) = {
  let next = start
  let colored = ()
  for signal in signals {
    if type(signal) == array {
      let (group, index) = color-signals(signal, start: next)
      colored.push(group)
      next = index
    } else if type(signal) == dictionary and signal.at("wave", default: "").contains(regex("[=2-9]")) {
      let row = signal
      row.wave = row.wave.replace(regex("[=2-9]"), str(3 + calc.rem(next, 4)))
      colored.push(row)
      next += 1
    } else {
      colored.push(signal)
    }
  }
  (colored, next)
}

#let color-wave-source(source) = {
  let colored = source
  if "signal" in source { colored.signal = color-signals(source.signal).first() }
  colored
}

// Keep the pinned SVG renderer and its geometry; override only valid bus fills.
// Signal names and edges remain readable independently of color.
#let wave-svg(key) = {
  let entry = data.waveforms.at(key)
  let svg = call-js-function(wave-bytecode,"wavy",json.encode(color-wave-source(entry.source)))
  svg = svg.replace(regex("font-family:[^;]+;"), "font-family:Inter;")
  svg = svg.replace(regex("font-family=\"[^\"]+\""), "font-family=\"Inter\"")
  svg = svg.replace(regex("(?i)#(?:0041c4|0000ff|00f)\\b"), "#292C31")
  svg = svg.replace("fill:blue", "fill:#292C31")
  svg.replace("</style>", "text{font-weight:400}.info{font-weight:400;font-style:normal}.s8{fill:#F4EFE4}.s9{fill:#E7EFF6}.s10{fill:#E8F1EA}.s11{fill:#EEEAF5}</style>")
}

#let timing(key, caption) = {
  let entry = data.waveforms.at(key)
  block(width:100%,above:rhythm.figure-space,below:rhythm.figure-space,breakable:false)[
    #show figure: set block(above:0pt,below:0pt)
    #figure(image(bytes(wave-svg(key))), caption: caption)
    #block(width:100%,above:rhythm.metadata-before,below:0pt)[
      #set par(leading:rhythm.small-leading,spacing:rhythm.small-spacing)
      #align(center,text(9pt,fill:muted,entry.note))
    ]
  ]
}
