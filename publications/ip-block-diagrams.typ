// Monochrome source-bound functional IP views. Geometry is in final millimetres.
#import "@preview/cetz:0.5.2" as cetz
#let ip-block-view(circuit)={
  let s=circuit.scene
  set text(font:"Inter",size:9pt,weight:"regular",fill:black)
  set par(leading:1.5pt,spacing:0pt)
  let ip-text(lines,alignment:center)=grid(columns:1,rows:lines.map(_=>3.7mm),align:alignment+horizon,..lines)
  cetz.canvas(length:1mm,{
    import cetz.draw: *
    let p(v)=(v.at(0),-v.at(1))
    let signal(points,both:false)={
      line(..points,stroke:0.65pt+black)
      let ends=if both {(points,points.rev())} else {(points,)}
      for route in ends {
        let tip=route.last()
        let before=route.at(route.len() - 2)
        let dx=tip.at(0)-before.at(0)
        let dy=tip.at(1)-before.at(1)
        let d=calc.sqrt(dx*dx+dy*dy)
        let u=dx/d;let v=dy/d
        line((tip.at(0)-u*1.8-v*0.75,tip.at(1)-v*1.8+u*0.75),tip,
          (tip.at(0)-u*1.8+v*0.75,tip.at(1)-v*1.8-u*0.75),close:true,fill:black,stroke:none)
      }
    }
    let box(n)={
      if n.at("condition",default:none)!=none {
        rect((n.x - 1,-n.y+1),(n.x+n.w+1,-n.y - n.h - 1),stroke:(paint:black,thickness:0.6pt,dash:"dashed"),fill:none)
      }
      if n.role=="bus" {
        line((n.x,-n.y),(n.x,-n.y - n.h),stroke:(paint:black,thickness:3pt,cap:"round"))
        if n.at("side",default:"left")=="left" {content((n.x - 3,-n.y - n.h/2),anchor:"east",ip-text(n.lines,alignment:right))}
        else {content((n.x+3,-n.y - n.h/2),anchor:"west",ip-text(n.lines,alignment:left))}
      } else {
        if n.shape=="mux" {
          line((n.x,-n.y),(n.x+n.w,-n.y - 3),(n.x+n.w,-n.y - n.h+3),(n.x,-n.y - n.h),close:true,fill:white,stroke:0.6pt+black)
        } else {
          rect((n.x,-n.y),(n.x+n.w,-n.y - n.h),fill:white,stroke:0.6pt+black,radius:0pt)
          if n.shape=="fifo" {
            line((n.x+1,-n.y - n.h+1),(n.x+n.w - 1,-n.y - n.h+1),stroke:0.6pt+black)
          }
        }
        content((n.x+n.w/2,-n.y - n.h/2),ip-text(n.lines))
      }
    }
    rect((0,0),(s.width,-s.height),fill:white,stroke:0.6pt+black,radius:0pt)
    let b=s.boundary
    rect(p(b.slice(0,2)),(b.at(0)+b.at(2),-b.at(1)-b.at(3)),fill:rgb("#F2F2F2"),stroke:0.9pt+black,radius:0pt)
    content((b.at(0)+b.at(2)/2,-b.at(1)+3),text(weight:"bold")[#circuit.block_diagram.at("boundary_title",default:circuit.block_diagram.title)])
    let side-count=(left:0,right:0)
    for port in s.ports {
      let side=if port.direction=="input" {"left"} else {"right"}
      let y=port.y
      side-count.insert(side,side-count.at(side)+1)
      if side=="left" {
        content((25,-y),anchor:"east",ip-text(port.lines,alignment:right))
        signal(((26,-y),(29,-y)))
      } else {
        content((147,-y),anchor:"west",ip-text(port.lines,alignment:left))
        signal(((141,-y),(145,-y)))
      }
    }
    for interface in s.interfaces {
      let x=interface.x
      let y=interface.y
      line((x,-y+interface.span/2),(x,-y - interface.span/2),stroke:(paint:black,thickness:3pt,cap:"round"))
      let n=s.nodes.find(n=>n.id==interface.node)
      if interface.side=="left" {
        content((x - 3,-y),anchor:"east",ip-text(interface.lines,alignment:right))
        if interface.at("direction",default:"")=="output" {signal(((n.x,-y),(x,-y)))}
        else {signal(((x,-y),(n.x,-y)),both:interface.at("direction",default:"")!="input")}
      } else {
        content((x+3,-y),anchor:"west",ip-text(interface.lines,alignment:left))
        if interface.at("direction",default:"")=="input" {signal(((x,-y),(n.x+n.w,-y)))}
        else {signal(((n.x+n.w,-y),(x,-y)),both:interface.at("direction",default:"")!="output")}
      }
    }
    for w in s.wires {
      if w.kind=="data" {
        line(..w.polygon.map(p),close:true,fill:white,stroke:0.6pt+black)
      } else {
        signal(w.points.map(p))
      }
    }
    for point in s.at("junctions",default:()) {circle(p(point),radius:0.55,fill:black,stroke:none)}
    for n in s.nodes {box(n)}
    for l in s.labels {content((l.x+l.w/2,-l.y - l.h/2),l.text)}
    for l in s.legend {content((l.x,-l.y),anchor:"north-west",ip-text(l.lines,alignment:left))}
  })
}
