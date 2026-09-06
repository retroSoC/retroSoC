#import "@preview/jogs:0.2.4": compile-js, call-js-function
#import "style.typ": ink, gold, muted, data
#let wave-bytecode=compile-js(read(data.wave_renderer))

// WaveDrom's SVG is kept vector. Use a restrained monochrome skin and short
// wave segments so final signal labels remain at least 9 pt.
#let timing(key, caption) = {
  let entry = data.waveforms.at(key)
  let svg = call-js-function(wave-bytecode,"wavy",json.encode(entry.source))
  svg = svg.replace(regex("font-family:[^;]+;"), "font-family:Inter;")
  svg = svg.replace(regex("font-family=\"[^\"]+\""), "font-family=\"Inter\"")
  svg = svg.replace(regex("(?i)#(?:0041c4|0000ff|00f)\\b"), "#292C31")
  svg = svg.replace("fill:blue", "fill:#292C31")
  figure(image(bytes(svg)), caption: caption)
  block(above:4pt,below:8pt,text(9pt,fill:muted,entry.note))
}
