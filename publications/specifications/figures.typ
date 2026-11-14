// Original vector redraws from a single geometry; source dimensions remain reference data.
#import "@preview/cetz:0.5.2" as cetz
#let ink=rgb("#292C31")
#let gold=rgb("#A38442")
#let gray=rgb("#F1F2F3")
#let drawing-revision="reference-20261114"

#let board-circuit(spec, kind)={
  set text(font:"Inter",size:9pt,weight:"regular",fill:ink)
  let b=spec.models.board
  let tiny=spec.product=="tiny"
  cetz.canvas(length:1mm,{
    import cetz.draw: rect,line,content,circle
    let wire(..points)=line(..points.map(p=>(p.at(0),-p.at(1))),stroke:0.6pt+ink)
    let label-at(x,y,body)=content((x,-y),body)
    let cap(x,y,value)={
      wire((x,y),(x,y+8))
      wire((x - 3,y+8),(x+3,y+8))
      wire((x - 3,y+10),(x+3,y+10))
      wire((x,y+10),(x,y+21))
      label-at(x+10,y+10,value)
    }
    let ground(x,y)={
      wire((x,y),(x,y+3))
      wire((x - 4,y+3),(x+4,y+3))
      wire((x - 2.5,y+5),(x+2.5,y+5))
      wire((x - 1,y+7),(x+1,y+7))
    }
    rect((0,0),(172,-160),stroke:none)
    label-at(86,5,[REFERENCE ONLY - #kind circuit example])
    if kind=="decoupling" {
      rect((7,-27),(45,-48),fill:gray,stroke:0.6pt+ink)
      label-at(26,37,[Regulator #linebreak()voltage / order TBD])
      wire((45,37),(154,37),(154,58))
      label-at(96,29,[Approved rail group; repeat at each supply])
      for (x,value) in ((63,[#b.bulk_cap_uf uF]),(95,[#b.domain_cap_uf uF]),(127,[#b.local_cap_nf nF])) {
        cap(x,37,value)
        ground(x,58)
      }
      rect((133,-58),(168,-89),fill:gray,stroke:0.6pt+ink)
      label-at(150,73,[VDD / VDDIO #linebreak()SoC supply pins])
      wire((150,89),(150,105))
      ground(150,105)
      label-at(76,96,[Keep each bypass loop short. #linebreak()Review AVDD / PLL rails separately.])
      label-at(86,133,[Connect every approved ground. EP is separate; binding pending.])
      label-at(86,146,[Capacitance, voltage grade, regulator stability and layout require approval.])
    } else {
      // External clock and open-drain reset / RC example.
      rect((3,-20),(45,-36),fill:gray,stroke:0.6pt+ink)
      label-at(24,28,if tiny {[Oscillator 24 MHz]} else {[REF24 / EXT72]})
      wire((45,28),(116,28))
      label-at(81,21,if tiny {[XIN; XOUT = NC]} else {[Separate clock inputs]})
      rect((116,-20),(169,-94),fill:gray,stroke:0.6pt+ink)
      label-at(142,42,[SoC logical pins])
      label-at(142,76,[RESET_N])
      wire((10,76),(116,76))
      rect((42,-58),(48,-68),fill:white,stroke:0.6pt+ink)
      wire((45,52),(45,58))
      wire((45,68),(45,76))
      label-at(64,63,[#b.reset_pull_kohm kohm])
      label-at(45,48,[VIO])
      cap(83,76,[#b.reset_cap_nf nF])
      ground(83,97)
      label-at(36,91,[Supervisor / button #linebreak()open-drain example])
      wire((10,76),(10,84))
      wire((10,88),(10,94))
      wire((10,88),(14,83))
      ground(10,94)
      // Dedicated boot NOR and management debug connectivity.
      rect((4,-113),(50,-149),fill:gray,stroke:0.6pt+ink)
      label-at(27,131,[Boot NOR #linebreak()match I/O levels])
      rect((118,-113),(169,-149),fill:gray,stroke:0.6pt+ink)
      label-at(143,131,[SoC boot XPI #linebreak()and JTAG])
      for (y,name) in ((117,[CS0_N]),(129,[SCK]),(141,[DQ0…3])) {
        wire((50,y),(118,y))
        label-at(83,y - 3,name)
      }
      label-at(86,152,[JTAG: TCK/TMS/TDI/TDO + GND + VIO reference; pin order TBD.])
    }
  })
}

#let visual(spec,id,body,caption,reference:true)=block(width:100%,breakable:false)[
  #context metadata((kind:"specification-figure",id:id,category:"engineering",status:if reference {"reference"} else {"confirmed"},page:here().page()))
  #figure(body,caption:[#caption #if reference {text(" - REFERENCE ONLY.")}])
]
#let qfn-view(spec, view, dimensions:false)={
  set text(font:"Inter",size:9pt,weight:"regular",fill:ink)
  let q=spec.qfn
  let d=q.dimensions
  let scale=11
  let center=(86,-95)
  cetz.canvas(length:1mm,{
    import cetz.draw: rect,line,content,circle
    rect((0,0),(172,-185),stroke:none)
    content((86,-5),[REFERENCE ONLY - QFN64 reference geometry])
    content((86,-13),[#view view; mm; drawing not to scale])
    let c(p)=(center.at(0)+p.at(0)*scale,center.at(1)+p.at(1)*scale)
    let half=d.body/2
    rect(c((-half,half)),c((half,-half)),fill:white,stroke:0.8pt+ink)
    if view!="Top" {
      let ep=d.ep/2
      line(c((-ep,ep)),c((ep - d.chamfer,ep)),c((ep,ep - d.chamfer)),
        c((ep,-ep)),c((-ep,-ep)),close:true,fill:gray,stroke:0.6pt+ink)
      content(center,[EP #linebreak()unnumbered #linebreak()binding TBD])
    } else {content(center,[retroSoC Tiny Gen1 #linebreak()QFN64 target #linebreak()bonding pending])}
    for p in q.pins {
      let xy=if view=="Bottom" {p.bottom} else {p.top}
      let (x,y)=xy
      let horizontal=p.side in (0,2)
      let w=if horizontal {d.lead_length} else {d.lead_width}
      let h=if horizontal {d.lead_width} else {d.lead_length}
      rect(c((x - w/2,y+h/2)),c((x+w/2,y - h/2)),fill:gray,stroke:0.45pt+ink)
      let labelpoint=if horizontal {(x + (if x < 0 {-0.75} else {0.75}),y)} else {(x,y + (if y < 0 {-0.75} else {0.75}))}
      content(c(labelpoint),str(p.pin))
    }
    let p1=q.pins.first()
    let p=if view=="Bottom" {p1.bottom} else {p1.top}
    circle(c((p.at(0) + (if p.at(0) < 0 {0.6} else {-0.6}),p.at(1))),radius:1mm,fill:gold,stroke:0.4pt+ink)
    content((86,-179),[64 perimeter terminals + separate EP; Pin 1 marked])
    if dimensions {
      line(c((-half,half+1.7)),c((half,half+1.7)),stroke:0.5pt+ink,mark:(start:"stealth",end:"stealth"))
      content(c((0,half+2.35)),[D = E = #d.body ± 0.10])
      content((86,-169),[e = #d.pitch BSC; EP = #d.ep ± 0.10])
    }
  })
}
#let qfn-side(spec)={
  set text(font:"Inter",size:9pt,weight:"regular",fill:ink)
  let d=spec.qfn.dimensions
  cetz.canvas(length:1mm,{
    import cetz.draw: rect,line,content
    rect((0,0),(172,-52),stroke:none)
    content((86,-5),[REFERENCE ONLY - side view / seating plane])
    rect((24,-18),(141,-29),fill:gray,stroke:0.7pt+ink)
    line((18,-31),(150,-31),stroke:(paint:ink,thickness:0.5pt,dash:"dashed"))
    content((83,-41),[A = #d.height ± 0.05 mm; A1 = 0.00…#d.standoff mm])
    content((83,-49),[Terminal L = #d.lead_length ± 0.10; b = #d.lead_width ± 0.05 mm])
  })
}
#let pcb-view(spec,layer)={
  set text(font:"Inter",size:9pt,weight:"regular",fill:ink)
  let d=spec.qfn.dimensions
  let m=spec.models
  let scale=11
  let c(p)=(86+p.at(0)*scale,-78+p.at(1)*scale)
  cetz.canvas(length:1mm,{
    import cetz.draw: rect,line,content,circle
    rect((0,0),(172,-151),stroke:none)
    content((86,-5),[REFERENCE ONLY - PCB #layer; component side])
    content((86,-13),[Same pin coordinate model as top view; mm; not to scale])
    let pin-one-y=c(spec.qfn.pins.first().pcb).at(1)
    content((16,pin-one-y),[Pin 1])
    line((24,pin-one-y),(31,pin-one-y),stroke:0.5pt+ink,mark:(end:"stealth"))
    rect(c((-d.body/2,d.body/2)),c((d.body/2,-d.body/2)),stroke:(paint:ink,thickness:0.5pt,dash:"dashed"))
    let exp=if layer=="mask" {m.pcb.mask_expansion_mm} else {0}
    if layer!="paste" {
      rect(c((-d.pad_ep/2-exp,d.pad_ep/2+exp)),c((d.pad_ep/2+exp,-d.pad_ep/2-exp)),fill:gray,stroke:0.7pt+ink)
    }
    for p in spec.qfn.pins {
      let (x,y)=p.pcb
      let edge=(d.pad_outer+d.pad_inner)/4
      let xy=if p.side==0 {(-edge,y)} else if p.side==1 {(x,-edge)} else if p.side==2 {(edge,y)} else {(x,edge)}
      let w=if p.side in (0,2) {d.pad_length} else {d.pad_width}
      let h=if p.side in (0,2) {d.pad_width} else {d.pad_length}
      rect(c((xy.at(0)-w/2 - exp,xy.at(1)+h/2+exp)),c((xy.at(0)+w/2+exp,xy.at(1)-h/2 - exp)),fill:gray,stroke:0.4pt+ink)
    }
    if layer=="paste" {
      let a=m.paste.aperture_mm
      let p=a+m.paste.gap_mm
      for i in range(m.paste.count_x) {
        for j in range(m.paste.count_y) {
          let x=(i - (m.paste.count_x - 1)/2)*p
          let y=(j - (m.paste.count_y - 1)/2)*p
          rect(c((x - a/2,y+a/2)),c((x+a/2,y - a/2)),fill:gray,stroke:0.5pt+ink)
        }
      }
      content((86,-137),[#m.paste.count_x × #m.paste.count_y windows; #a mm; gap #m.paste.gap_mm mm])
      content((86,-146),[Stencil #m.paste.stencil_mm mm; rectangular EP coverage #calc.round(spec.paste_coverage_percent,digits:2)%])
    } else if layer=="thermal vias" {
      for i in range(m.pcb.via_grid) {for j in range(m.pcb.via_grid) {
        let p=((i - (m.pcb.via_grid - 1)/2)*m.pcb.via_pitch_mm,(j - (m.pcb.via_grid - 1)/2)*m.pcb.via_pitch_mm)
        circle(c(p),radius:m.pcb.via_land_mm*scale/2*1mm,fill:white,stroke:0.5pt+ink)
        circle(c(p),radius:m.pcb.via_drill_mm*scale/2*1mm,fill:ink,stroke:none)
      }}
      content((86,-137),[#m.pcb.via_grid × #m.pcb.via_grid vias; pitch #m.pcb.via_pitch_mm mm; drill #m.pcb.via_drill_mm mm])
      content((86,-146),[Land #m.pcb.via_land_mm mm; fill/cap and process approval pending])
    } else {
      content((86,-137),[Copper pad #d.pad_width × #d.pad_length; pitch #d.pitch mm])
      content((86,-146),if layer=="mask" {[Mask expansion #exp mm / edge; fabricator rule example]} else {[Inner span #d.pad_inner; outer span #d.pad_outer; center #d.pad_ep mm]})
    }
  })
}
#let connection(spec,kind)={
  set text(font:"Inter",size:9pt,weight:"regular",fill:ink)
  let tiny=spec.product=="tiny"
  let b=spec.models.board
  let nodes=if kind=="minimum" {(
    (5,25,42,24,[Regulated rails #linebreak()core / digital IO]),
    (64,18,50,69,[#if tiny {[Tiny / QFN64 target]} else {[Mini / logical pads]} #linebreak()VDD / VDDIO / GND #linebreak()external clock inputs #linebreak()RESET_N #linebreak()boot XPI / JTAG]),
    (130,22,37,24,[External clock #linebreak()#if tiny {[24 MHz XIN]} else {[24 MHz + 72 MHz]}]),
    (5,69,42,26,[Reset supervisor #linebreak()valid rails + clock]),
    (130,64,37,26,[Boot NOR #linebreak()SCK / CS0 / DQ]),
    (64,108,50,20,[JTAG header #linebreak()TCK / TMS / TDI / TDO]),
  )} else if kind=="supply" {(
    (5,22,43,28,[Regulator #linebreak()limits / sequence TBD]),
    (67,22,43,28,[Local bypass #linebreak()#b.local_cap_nf nF / supply]),
    (129,22,38,28,[SoC rail pins #linebreak()all perimeter GND]),
    (18,83,49,26,[Domain reservoir #linebreak()#b.domain_cap_uf uF + #b.bulk_cap_uf uF]),
    (103,83,55,26,[Ground plane / EP #linebreak()EP binding pending]),
  )} else if kind=="reset" {(
    (5,24,42,27,[External oscillator #linebreak()#if tiny {[XIN; XOUT unbound]} else {[REF24 / EXT72]}]),
    (64,24,49,27,[Clock / reset pins #linebreak()pad timing TBD]),
    (130,24,37,27,[Reset supervisor #linebreak()open-drain example]),
    (5,86,42,27,[BOOT / TEST #linebreak()target straps only]),
    (64,86,49,27,[NOR CS0 / SCK / DQ #linebreak()I/O voltage match]),
    (130,86,37,27,[JTAG reference IO #linebreak()return GND adjacent]),
  )} else {(
    (5,23,46,26,[GPIO alternate group #linebreak()one active owner]),
    (65,23,45,26,[Series / pull network #linebreak()device dependent]),
    (124,23,43,26,[SD card / sensor #linebreak()display / codec]),
    (5,87,46,26,[Short return paths #linebreak()decoupling by pins]),
    (65,87,45,26,[No route overlap #linebreak()review AF matrix]),
    (124,87,43,26,[Verify load / skew #linebreak()PVT + board timing]),
  )}
  cetz.canvas(length:1mm,{
    import cetz.draw: rect,line,content
    rect((0,0),(172,-139),stroke:none)
    content((86,-5),[REFERENCE ONLY - #kind connection example])
    let routes=if kind=="minimum" {(((47,37),(64,37)),((130,34),(114,34)),((47,82),(64,82)),((114,76),(130,76)),((89,108),(89,87)))}
      else if kind=="supply" {(((48,36),(67,36)),((110,36),(129,36)),((42,83),(42,61),(88,61),(88,50)),((148,50),(148,83)))}
      else {(((47,37),(64,37)),((113,37),(130,37)),((47,99),(64,99)),((113,99),(130,99)))}
    for route in routes {line(..route.map(p=>(p.at(0),-p.at(1))),stroke:0.65pt+ink)}
    for (x,y,w,h,label) in nodes {
      rect((x,-y),(x+w,-y - h),fill:gray,stroke:0.6pt+ink)
      content((x+w/2,-y - h/2),block(width:(w - 4)*1mm)[#set par(leading:3pt,spacing:0pt)
#align(center,label)])
    }
    content((86,-135),[Reference topology; final rail, strap, bond and passive values require approval])
  })
}
