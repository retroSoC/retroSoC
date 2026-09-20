#import "@preview/cetz:0.5.2" as cetz
#import "style.typ": data, ink, gold, muted, rhythm, change-start, change-end

#let point(x,y) = (x,-y)
#let emphasis(body) = context {
  let body=text(font:"Inter",size:9pt,weight:700,fill:ink,top-edge:"ascender",bottom-edge:"descender",body)
  let size=measure(body)
  box[#context {
    let p=here().position()
    metadata((kind:"soc-emphasis-region",page:p.page,x:p.x.pt(),y:p.y.pt(),width:size.width.pt(),height:size.height.pt()))
  }#body]
}
#let diagram-position(kind) = context {
  let p=here().position()
  metadata((kind:kind,package:"cetz",id:"soc-functional",page:p.page,x:p.x.pt(),y:p.y.pt()))
}

#let soc-functional-diagram() = block(width:100%,breakable:false)[
  #change-start("soc-functional","Compact CDC/gateways, orthogonal routes and scoped typography")
  #diagram-position("publication-diagram")
  #let spec=data.system_reference.illustrations.soc_architecture.at("soc-functional")
  #context {
    let p=here().position()
    metadata((kind:"soc-canvas-origin",id:spec.id,page:p.page,x:p.x.pt(),y:p.y.pt()))
  }
  #set text(font:"Inter",size:9pt,weight:"regular",fill:ink)
  #cetz.canvas(length:1mm,{
    import cetz.draw: rect, line, content, circle
    let fill-for(domain) = {
      let d=spec.domains.find(d=>d.id==domain)
      if d==none {white} else {rgb(d.fill)}
    }
    // Fix the canvas origin and physical extent for PDF-bound text regions.
    rect(point(0,0),point(spec.width_mm,spec.height_mm),fill:none,stroke:none)
    let label(x,y,w,h,body,rotate:false,align-left:false,compact:false,bold:false) = {
      let size=if compact {spec.typography.compact_size_pt*1pt} else {9pt}
      let pad-x=if compact {spec.typography.compact_padding_x_mm*1mm} else {1pt}
      let pad-y=if compact {spec.typography.compact_padding_y_mm*1mm} else {0pt}
      let text-width=(if rotate {h} else {w})*1mm - 2*pad-x
      let text-height=(if rotate {w} else {h})*1mm - 2*pad-y
      let body=block(width:text-width,above:0pt,below:0pt)[
        #set text(font:"Inter",size:size,weight:if bold {700} else {400},fill:ink)
        #set par(leading:if compact {1pt} else {2pt},spacing:0pt)
        #align(if align-left {left} else {center},body)
      ]
      content(point(x+w/2,y+h/2),context {
        let measured=measure(body)
        assert(not compact or measured.height<=text-height+0.01pt,message:"SoC label overflow: "+repr((x,y,w,h,measured.height,text-height)))
        body
      },angle:if rotate {90deg} else {0deg})
    }
    for r in spec.regions {
      rect(point(r.x,r.y),point(r.x+r.w,r.y+r.h),fill:fill-for(r.domain),stroke:none)
      if r.label {
        let title=spec.domains.find(d=>d.id==r.domain).label
        let p=r.at("label_position",default:(r.x+1,r.y+0.5))
        content(point(..p),emphasis(title),anchor:"north-west")
      }
    }
    // Draw paths first; their endpoints stop at the declared symbol boundaries.
    for e in spec.routes {
      let stroke=(paint:if e.kind=="stream" {muted} else {ink},thickness:spec.routing.stroke_pt*1pt,
        dash:if e.kind=="control" {"dashed"} else {"solid"})
      line(..e.points.map(p=>point(..p)),stroke:stroke)
      for head in e.heads {
        line(..head.map(p=>point(..p)),stroke:(paint:stroke.paint,thickness:stroke.thickness))
      }
    }
    for n in spec.nodes {
      if n.role=="rail" {
        line(point(n.x,n.y),point(n.x,n.y+n.h),stroke:0.65pt+ink)
      } else if n.role=="io" {
        label(n.x,n.y,n.w,n.h,n.label,align-left:n.x>150)
      } else {
        let base=if n.role=="bus" {rgb("#D5D6D8")} else if n.domain in ("audio","dvp") {fill-for(n.domain)} else {white}
        if n.role=="gateway" {
          line(point(n.x,n.y),point(n.x+n.w,n.y+3),point(n.x+n.w,n.y+n.h - 3),point(n.x,n.y+n.h),close:true,
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
        label(n.x+l,n.y,n.w - l - r,n.h,n.label,rotate:n.rotate,compact:n.at("compact",default:false),bold:n.role=="bus")
      }
    }
  })
  #block(above:4pt,below:0pt,width:100%)[
    #set align(left)
    #set par(leading:rhythm.small-leading,spacing:2pt)
    #set text(font:"Inter",size:9pt,weight:"regular")
    #grid(columns:(64mm,102mm),column-gutter:6mm,align:top,
      grid(columns:(1fr,1fr,1fr),row-gutter:1pt,
        ..spec.domains.map(d=>[#box(width:2.5mm,height:2.5mm,fill:rgb(d.fill),stroke:0.35pt+muted) #emphasis(d.label)])),
      [GW = HP I/O gateway. Grey arrows: streams; other arrows: requests.
       #linebreak()
       PCLK derives from LP. \* = GPIO AF; QPI/OPI pads use one mode. Crossings do not join.])
  ]
  #diagram-position("publication-diagram-end")
  #change-end("soc-functional")
]
