#import "engineering-figures.typ": circuit-figure
#import "@preview/cetz:0.5.2" as cetz
#import "style.typ": *

#let diagram(id, body, caption, package:"cetz") = block(width:100%,breakable:false)[
  #context metadata((kind:"tiny-diagram",id:id,package:package,page:here().page()))
  #figure(body,caption:caption)
]
#let schematic(nodes, routes, height:90) = {
  set text(font:"Inter",size:9pt,weight:"regular",fill:ink)
  cetz.canvas(length:1mm,{
    import cetz.draw: rect, line, content
    rect((0,0),(172,-height),stroke:none)
    for path in routes {
      line(..path.map(p=>(p.at(0),-p.at(1))),stroke:0.65pt+ink,mark:(end:"stealth"))
    }
    for node in nodes {
      let (x,y,w,h,label)=node
      rect((x,-y),(x+w,-y - h),fill:gray,stroke:0.6pt+ink)
      content((x+w/2,-y - h/2),block(width:(w - 4)*1mm)[
        #set text(font:"Inter",size:9pt,weight:"regular")
        #set par(leading:2pt,spacing:0pt)
        #align(center,label)
      ])
    }
  })
}
#let architecture()=circuit-figure("system-fabric")
#let clock-tree()=circuit-figure("system-clocks")

#let overview()=diagram("tiny-overview",cetz.canvas({
 import cetz.draw: rect, content, line, circle
  let category-icon(kind, x, y) = {
    let pen = 0.6pt + gold
    if kind == 0 {
      rect((x - 0.11,y - 0.11),(x + 0.11,y + 0.11),stroke:pen)
      for d in (-0.065,0.065) {
        line((x + d,y - 0.18),(x + d,y - 0.11),stroke:pen)
        line((x + d,y + 0.11),(x + d,y + 0.18),stroke:pen)
        line((x - 0.18,y + d),(x - 0.11,y + d),stroke:pen)
        line((x + 0.11,y + d),(x + 0.18,y + d),stroke:pen)
      }
    } else if kind == 1 {
      for d in (-0.11,0,0.11) {
        rect((x - 0.16,y + d - 0.035),(x + 0.16,y + d + 0.035),stroke:pen)
      }
    } else if kind == 2 {
      for (n,d) in (-0.12,0,0.12).enumerate() {
        line((x - 0.17,y + d),(x + 0.17,y + d),stroke:pen)
        circle((x + if n == 1 {0.07} else {-0.06},y + d),radius:0.04,fill:pale-gold,stroke:pen)
      }
    } else if kind == 3 {
      rect((x - 0.17,y + 0.01),(x - 0.01,y + 0.15),stroke:pen)
      rect((x + 0.01,y - 0.15),(x + 0.17,y - 0.01),stroke:pen)
      line((x - 0.09,y + 0.01),(x - 0.09,y - 0.08),(x + 0.01,y - 0.08),stroke:pen)
      line((x + 0.09,y - 0.01),(x + 0.09,y + 0.08),(x - 0.01,y + 0.08),stroke:pen)
    } else if kind == 4 {
      line((x - 0.17,y + 0.08),(x + 0.17,y + 0.08),(x + 0.10,y + 0.15),stroke:pen)
      line((x + 0.17,y - 0.08),(x - 0.17,y - 0.08),(x - 0.10,y - 0.15),stroke:pen)
    } else if kind == 5 {
      circle((x,y),radius:0.17,stroke:pen)
      line((x,y + 0.11),(x,y),(x + 0.09,y - 0.04),stroke:pen)
    } else if kind == 6 {
      rect((x - 0.10,y - 0.12),(x + 0.10,y + 0.10),stroke:pen)
      line((x - 0.06,y + 0.10),(x - 0.06,y + 0.18),stroke:pen)
      line((x + 0.06,y + 0.10),(x + 0.06,y + 0.18),stroke:pen)
      line((x,y - 0.12),(x,y - 0.19),(x + 0.16,y - 0.19),stroke:pen)
    } else if kind == 7 {
      rect((x - 0.18,y - 0.13),(x + 0.18,y + 0.13),stroke:pen,radius:0.03)
      line((x - 0.05,y - 0.075),(x + 0.075,y),(x - 0.05,y + 0.075),(x - 0.05,y - 0.075),stroke:pen)
    } else {
      line((x - 0.15,y + 0.12),(x,y + 0.17),(x + 0.15,y + 0.12),
        (x + 0.12,y - 0.07),(x,y - 0.18),(x - 0.12,y - 0.07),(x - 0.15,y + 0.12),stroke:pen)
    }
  }

 let labels=("sysctrl":"SYSCTRL","rcu":"RCU","clint":"CLINT","archinfo":"ARCHINFO",
  "xpi":"XPI","sram":"128 KiB SRAM","dma":"8-channel DMA","gpio":"GPIO","timer":"TIM0 / TIM1",
  "pwm":"PWM","rtc":"RTC","wdg":"WDG","uart0":"UART0","i2c":"I2C0","spi":"SPI0","sdio":"SDIO0",
  "i2s":"I2S","dvp":"DVP","ppalite":"PPALite","ws2812":"WS2812","crypto":"Crypto","crc":"CRC","rng":"RNG")
 let icons=(0,2,5,6,7,8)
 rect((0,0),(17.2,-10.8),fill:white,stroke:0.85pt+ink,radius:0.20)
 line((0.4,-0.29),(2.7,-0.29),stroke:1.4pt+gold)
 content((8.6,-0.85),block(width:16.4cm)[#text(12pt,weight:"semibold",doc.title)])
 line((0.4,-1.45),(16.8,-1.45),stroke:0.45pt+muted)
 let w=(16.4-0.6)/3
 for (i,group) in data.overview.enumerate() {
  let x=0.4+calc.rem(i,3)*(w+0.3)
  let top=-1.7-calc.floor(i/3)*4.3
  rect((x,top - 4),(x+w,top),fill:white,stroke:0.55pt+muted,radius:0.10)
  rect((x+0.035,top - 0.65),(x+w - 0.035,top - 0.035),fill:pale-gold,stroke:none,radius:0.07)
  category-icon(icons.at(i),x+0.38,top - 0.335)
  content((x+0.72+(w - 0.92)/2,top - 0.335),block(width:(w - 0.92)*1cm)[#text(9.5pt,weight:"semibold",group.title)])
  let h=(2.95-(group.ids.len()-1)*0.10)/group.ids.len()
  for (j,id) in group.ids.enumerate() {
   let y=top - 0.85-j*(h+0.10)
   rect((x+0.2,y - h),(x+w - 0.2,y),fill:gray,stroke:0.5pt+muted,radius:0.10)
   content((x+w/2,y - h/2),block(width:(w - 0.4)*1cm - 6pt)[
    #set par(leading:rhythm.inventory-leading)
    #align(center,text(9pt,weight:"regular",labels.at(id)))
   ])
  }
 }
}),[Integrated Tiny IP inventory, organized by function.])

#let ip-diagram(entry) = {
  let children=entry.nodes.slice(1)
  let positions=if children.len()<=3 {((1,40,54,20),(59,40,54,20),(117,40,54,20))}
    else {((5,39,68,20),(99,39,68,20),(5,76,68,20),(99,76,68,20))}
  let nodes=((50,0,72,20,entry.nodes.first()),)
  let routes=()
  for (i,name) in children.enumerate() {
    let (x,y,w,h)=positions.at(i)
    nodes.push((x,y,w,h,name))
    // Control reaches each functional group independently; no invented FIFO-to-FIFO chain.
    let branch=if children.len()<=3 or i < 2 {29} else {68}
    routes.push(((86,20),(86,branch),(x+w/2,branch),(x+w/2,y)))
  }
  diagram("ip-"+entry.id,schematic(nodes,routes,height:if children.len()>3 {98} else {62}),
    [#entry.title functional groups. Arrows show control reach, not every internal data wire or a cycle schedule.])
}

#let flow(id, items, caption) = {
  let nodes=items.enumerate().map(((i,item))=>(16,i*23,140,16,item))
  let paths=range(items.len()-1).map(i=>((86,i*23+16),(86,(i+1)*23)))
  diagram(id,schematic(nodes,paths,height:items.len()*23-5),caption)
}

#let access-matrix()=diagram("tiny-access-matrix",cetz.canvas(length:1mm,{
 import cetz.draw: rect, content
 let widths=(48,31,31,31,31)
 let rows=(
  ("Request origin","Main SRAM","XPI aperture","APB controls","Fabric owner"),
  ("CPU local I / D","Direct group","-","-","Local ports"),
  ("CPU slow path","Via fabric","Via fabric","Via bridges","0"),
  ("Central DMA","Via fabric","Via fabric","Via bridges","1"),
  ("SDIO private DMA","Via fabric","Via fabric","Via bridges","2"))
 for (r,row) in rows.enumerate() {
  let x=0
  for (c,value) in row.enumerate() {
   rect((x,-r*14),(x+widths.at(c),-(r+1)*14),fill:if r==0 or c==0 {pale-gold} else {gray},stroke:0.6pt+ink)
   content((x+widths.at(c)/2,-r*14-7),block(width:(widths.at(c)-4)*1mm)[
    #set par(leading:rhythm.diagram-leading)
    #align(center,text(9pt,weight:"regular",value))])
   x+=widths.at(c)
  }
 }
}),[Tiny connection matrix. Entries show fabric connectivity, not permission for every transaction. Admission, endpoint and private-DMA address rules still apply.])
