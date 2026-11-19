// RCC-style functional IP views. All geometry is explicit final millimetres.
#import "@preview/cetz:0.5.2" as cetz
#let ip-block-view(circuit)={
  let s=circuit.scene
  assert(s.style=="ip-block-v2",message:"Unreviewed IP drawing style")
  set text(font:"Inter",size:9pt,weight:"regular",fill:black)
  set par(leading:1.5pt,spacing:0pt)
  let ip-text(lines,alignment:center)=grid(columns:1,rows:lines.map(_=>3.7mm),align:alignment+horizon,..lines)
  cetz.canvas(length:1mm,{
    import cetz.draw: *
    let p(v)=(v.at(0),-v.at(1))
    rect((0.12,-0.12),(s.width - 0.12,-s.height + 0.12),fill:white,stroke:0.6pt+black,radius:0pt)
    let b=s.boundary
    rect(p(b.slice(0,2)),(b.at(0)+b.at(2),-b.at(1)-b.at(3)),fill:rgb("#F2F2F2"),stroke:0.9pt+black,radius:0pt)
    content((s.heading.x, -s.heading.y),anchor:"north-west",text(weight:"bold")[#s.heading.text])
    for group in s.groups {
      rect((group.x, -group.y), (group.x + group.w, -group.y - group.h),fill:none,stroke:(paint:black,thickness:0.6pt,dash:"dashed"))
      content((group.x + 2, -group.y - 2),anchor:"north-west",group.title)
    }
    // Emit shared trunks once; only horizontal unrelated nets carry bridges.
    for segment in s.segments {
      let a=segment.points.first();let z=segment.points.last()
      if a.at(1)==z.at(1) {
        let cuts=s.crossings.filter(c=>{
          let w=s.wires.at(c.horizontal)
          w.source_key == segment.net and c.point.at(1) == a.at(1) and a.at(0) < c.point.at(0) and c.point.at(0) < z.at(0)
        }).sorted(key:c=>c.point.at(0))
        let start=a
        for c in cuts {
          let x=c.point.at(0);let y=c.point.at(1);let r=c.radius
          line(p(start),p((x - r, y)),stroke:0.65pt+black)
          bezier(p((x - r, y)),p((x + r, y)),p((x - r, y - r*4/3)),p((x + r, y - r*4/3)),stroke:0.65pt+black,fill:none)
          start=(x + r, y)
        }
        line(p(start),p(z),stroke:0.65pt+black)
      } else {line(p(a),p(z),stroke:0.65pt+black)}
    }
    for wire in s.wires {
      for arrow in wire.arrows {line(..arrow.map(p),close:true,fill:black,stroke:none)}
    }
    for point in s.junctions {circle(p(point),radius:0.55,fill:black,stroke:none)}
    for n in s.nodes {
      if n.role=="pin-list" {
        for pin in n.pin_labels {content((n.x + 2, -pin.y),anchor:"west",ip-text(pin.lines,alignment:left))}
      } else if n.role=="bus" {
        let x=if n.at("side",default:"left")=="left" {n.x + n.w} else {n.x}
        line((x, -n.y),(x, -n.y - n.h),stroke:(paint:black,thickness:3pt,cap:"round"))
      } else if n.role!="terminal" {
        if n.at("condition",default:none)!=none {
          rect((n.x - 1, -n.y + 1),(n.x + n.w + 1, -n.y - n.h - 1),stroke:(paint:black,thickness:0.6pt,dash:"dashed"),fill:none)
        }
        // A function may group several MUXes; its rectangular contour is also
        // the authored port contour. Sloping glyphs must not leave floating pins.
        rect((n.x, -n.y),(n.x + n.w, -n.y - n.h),fill:white,
          stroke:if n.at("ownership",default:"")=="soc-integration" {(paint:black,thickness:0.6pt,dash:"dashed")} else {0.6pt+black},radius:0pt)
        if n.shape=="fifo" {line((n.x + 1, -n.y - n.h + 1),(n.x + n.w - 1, -n.y - n.h + 1),stroke:0.6pt+black)}
      }
      if n.at("signal_label",default:none)!=none {
        let l=n.signal_label
        content((l.x,-l.y),anchor:"north-west",ip-text(l.lines,alignment:left))
      } else if n.role!="pin-list" {content((n.x + n.w/2, -n.y - n.h/2),ip-text(n.lines))}
    }
    for l in s.labels {content((l.x,-l.y),anchor:"north-west",ip-text(l.lines,alignment:left))}
  })
}
