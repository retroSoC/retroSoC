#import "@preview/cetz:0.5.2"
#import "style.typ": pale-gold, gray
#import "figures.typ": box, wire

// Logical sequences use fixed-size text boxes, never a scaled raster.
#let sequence-diagram(stages) = cetz.canvas({
  let columns = calc.min(3,stages.len())
  for (i,body) in stages.enumerate() {
    let row = calc.floor(i / columns)
    let col = if calc.rem(row,2)==0 {calc.rem(i,columns)} else {columns - 1 - calc.rem(i,columns)}
    let x = col*5.8
    let y = -row*2.2
    box(x,y,5.0,1.35,body,fill:if i==0 or i==stages.len()-1 {pale-gold} else {gray})
    if i < stages.len()-1 {
      if calc.rem(i+1,columns)==0 {
        wire(((x+2.5,y),(x+2.5,y - 0.85)))
      } else if calc.rem(row,2)==0 {
        wire(((x+5,y+0.675),(x+5.8,y+0.675)))
      } else {
        wire(((x,y+0.675),(x - 0.8,y+0.675)))
      }
    }
  }
})

#let media-system-diagram() = cetz.canvas({
  box(0,4,5,1.3,[*External camera* \ Pixel clock, VSYNC/HREF \ Board configuration required])
  box(5.8,4,5,1.3,[*DVP + central DMA* \ Capture stream and buffers])
  box(11.6,4,5,1.3,[*Shared memory* \ Explicit buffer ownership])
  wire(((5,4.65),(5.8,4.65)))
  wire(((10.8,4.65),(11.6,4.65)))
  box(11.6,1.6,5,1.3,[*JPEG / software consumer* \ Separate memory job \ No direct DVP-to-JPEG claim])
  wire(((14.1,4),(14.1,2.9)))
  box(0,1.6,5,1.3,[*External audio codec* \ Audio clock and I2S wiring])
  box(5.8,1.6,5,1.3,[*I2S + DMA / software* \ Separate audio buffers])
  wire(((5,2.25),(5.8,2.25)))
  wire(((8.3,2.9),(8.3,3.3),(14.1,3.3),(14.1,4)))
  box(0,-0.7,16.6,1.2,[*LP orchestrates clocks, pad mode and resource ownership* \ APU production codec jobs remain disabled in this snapshot.],fill:pale-gold)
})
