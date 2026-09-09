#import "@preview/cetz:0.5.2"
#import "diagram-packages.typ": circuit-diagram
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

#let media-system-diagram() = circuit-diagram("system-media")
