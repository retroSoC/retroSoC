#import "@preview/cetz:0.5.2" as cetz
#import "style.typ": data, ink, gold, muted, rhythm, change-start, change-end

#let point(x,y) = (x,-y)
#let regular(body) = text(font:"Inter",size:9pt,weight:"regular",fill:ink,body)
#let endpoint(n,side,p) = {
  if side=="north" {(n.x+n.w*p,n.y)}
  else if side=="south" {(n.x+n.w*p,n.y+n.h)}
  else if side=="west" {(n.x,n.y+n.h*p)}
  else {(n.x+n.w,n.y+n.h*p)}
}
#let diagram-position(kind) = context {
  let p=here().position()
  metadata((kind:kind,package:"cetz",id:"soc-functional",page:p.page,x:p.x.pt(),y:p.y.pt()))
}

#let soc-functional-diagram() = block(width:100%,breakable:false)[
  #change-start("soc-functional","Compact PRODUCT functional architecture",category:"added")
  #diagram-position("publication-diagram")
  #let spec=data.system_reference.illustrations.soc_architecture.at("soc-functional")
  #set text(font:"Inter",size:9pt,weight:"regular",fill:ink)
  #cetz.canvas(length:1mm,{
    import cetz.draw: rect, line, content, circle
    let fill-for(domain) = {
      let d=spec.domains.find(d=>d.id==domain)
      if d==none {white} else {rgb(d.fill)}
    }
    // Text is explicitly regular inside every content block, including cells.
    let label(x,y,w,h,body,rotate:false,align-left:false) = {
      content(point(x+w/2,y+h/2),block(width:(if rotate {h} else {w})*1mm - 2pt,above:0pt,below:0pt)[
        #set text(font:"Inter",size:9pt,weight:"regular",fill:ink)
        #set par(leading:2pt,spacing:0pt)
        #align(if align-left {left} else {center},regular(body))
      ],angle:if rotate {90deg} else {0deg})
    }
    for r in spec.regions {
      rect(point(r.x,r.y),point(r.x+r.w,r.y+r.h),fill:fill-for(r.domain),stroke:none)
      if r.label {
        let title=spec.domains.find(d=>d.id==r.domain).label
        let p=r.at("label_position",default:(r.x+1,r.y+0.5))
        content(point(..p),regular(title),anchor:"north-west")
      }
    }
    // Draw paths first; their endpoints stop at the declared symbol boundaries.
    for e in spec.edges {
      let a=spec.nodes.find(n=>n.id==e.from)
      let b=spec.nodes.find(n=>n.id==e.to)
      let start=endpoint(a,e.source_side,e.source_position)
      let end=endpoint(b,e.target_side,e.target_position)
      let route=(start,)
      for p in e.via {
        route.push(p.enumerate().map(((axis,v))=>if v=="source" {start.at(axis)} else if v=="target" {end.at(axis)} else {v}))
      }
      route.push(end)
      let points=()
      for p in route {if points.len()==0 or points.last()!=point(..p) {points.push(point(..p))}}
      let stroke=(paint:if e.kind=="stream" {muted} else {ink},thickness:0.65pt,
        dash:if e.kind=="control" {"dashed"} else {"solid"})
      line(..points,stroke:stroke,mark:if e.kind=="stream" and e.at("duplex",default:false) {(start:">",end:">")} else if e.arrow {(end:">")} else {none})
    }
    for n in spec.nodes {
      if n.role=="rail" {
        line(point(n.x,n.y),point(n.x,n.y+n.h),stroke:0.65pt+ink)
      } else if n.role=="io" {
        label(n.x,n.y,n.w,n.h,n.label,align-left:n.x>150)
      } else {
        let base=if n.role=="bus" {rgb("#D5D6D8")} else if n.domain in ("audio","dvp") {fill-for(n.domain)} else {white}
        if n.role=="gateway" {
          line(point(n.x,n.y),point(n.x+n.w,n.y+4),point(n.x+n.w,n.y+n.h - 4),point(n.x,n.y+n.h),close:true,
            fill:white,stroke:0.6pt+gold)
        } else {
          rect(point(n.x,n.y),point(n.x+n.w,n.y+n.h),fill:base,
            stroke:0.6pt+if n.role=="bridge" {gold} else {ink})
        }
        let l=0;let r=0
        for part in n.at("parts",default:()) {
          let left-side=part.at("side",default:"right")=="left"
          let x=if left-side {n.x+l} else {n.x+n.w - r - part.width}
          rect(point(x,n.y),point(x+part.width,n.y+n.h),fill:if part.domain!=n.domain {fill-for(part.domain)} else {white},stroke:0.6pt+ink)
          label(x,n.y,part.width,n.h,part.label)
          if left-side {l+=part.width} else {r+=part.width}
        }
        label(n.x+l,n.y,n.w - l - r,n.h,n.label,rotate:n.rotate)
      }
    }
  })
  #block(above:4pt,below:0pt,width:100%)[
    #set align(left)
    #set par(leading:rhythm.small-leading,spacing:2pt)
    #set text(font:"Inter",size:9pt,weight:"regular")
    #grid(columns:(1fr,1fr,1fr,1fr,1fr),row-gutter:1pt,
      ..spec.domains.map(d=>[#box(width:2.5mm,height:2.5mm,fill:rgb(d.fill),stroke:0.35pt+muted) #d.label]))
    #v(2pt)
    GW = HP I/O gateway. Grey arrows: streams; other arrows: requests.
    #linebreak()
    PCLK derives from LP. \* = GPIO AF; QPI/OPI pads use one mode. Crossings do not join.
  ]
  #diagram-position("publication-diagram-end")
  #change-end("soc-functional")
]
