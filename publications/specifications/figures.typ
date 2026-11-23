// Original vector redraws from a single geometry; source dimensions remain reference data.
#import "@preview/cetz:0.5.2" as cetz
#import "scientific.typ" as scientific
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
      label-at(96,29,if tiny {[Repeat for each approved power rail]} else {[Approved rail group; repeat at each supply]})
      for (x,value) in ((63,[#b.bulk_cap_uf #scientific.render("uF",spec.scientific,unit:true)]),(95,[#b.domain_cap_uf #scientific.render("uF",spec.scientific,unit:true)]),(127,[#b.local_cap_nf nF])) {
        cap(x,37,value)
        ground(x,58)
      }
      rect((133,-58),(168,-89),fill:gray,stroke:0.6pt+ink)
      label-at(150,73,[VDD / VDDIO #linebreak()#if tiny {[SoC power pins]} else {[SoC supply pins]}])
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
      label-at(64,63,[#b.reset_pull_kohm #scientific.render("kohm",spec.scientific,unit:true)])
      label-at(45,48,scientific.render("VIO",spec.scientific))
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
      label-at(86,152,[JTAG: TCK/TMS/TDI/TDO + GND + #scientific.render("VIO",spec.scientific) reference; pin order TBD.])
    }
  })
}

#let visual(spec,id,body,caption,reference:true,kind:auto,anchor:none)=block(width:100%,breakable:false)[
  #context metadata((kind:"specification-figure",id:id,category:"engineering",status:if reference {"reference"} else {"confirmed"},page:here().page()))
  #let item=figure(body,kind:kind,caption:[#caption #if reference {text(" - REFERENCE ONLY.")}])
  #if anchor == none { item } else { [#item#label(anchor)] }
]
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
    (67,22,43,28,[Local bypass #linebreak()#b.local_cap_nf nF / #if tiny {[power rail]} else {[supply]}]),
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
