#import "@preview/cetz:0.5.2" as cetz
#import "@preview/bytefield:0.0.8" as bf
#import "style.typ": *

#let diagram(id, body, caption) = block(width:100%,breakable:false)[
  #context metadata((kind:"tiny-diagram",id:id,page:here().page()))
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
#let architecture() = diagram("tiny-architecture",schematic((
  (5,4,65,19,[Hazard3 · hart 0 \ RV32IMC · A disabled]),
  (104,4,63,19,[JTAG / debug transport \ External TCK domain]),
  (5,37,65,15,[AHB-Lite → AXI32 adapter]),
  (104,37,63,15,[Four-channel DMA \ AXI32 master]),
  (30,69,112,19,[Tiny AXI32 fabric \ One active transaction globally]),
  (0,110,40,22,[128 KiB SRAM \ 32 × 4 KiB]),
  (44,110,40,22,[XPI read path \ Flash alias / NOR]),
  (88,110,40,22,[APB4 bridge \ 16 targets]),
  (132,110,40,22,[Error responders \ DECERR / SLVERR]),
),(
  ((104,13),(70,13)),((37,23),(37,37)),
  ((37,52),(37,61),(60,61),(60,69)),((135,52),(135,61),(112,61),(112,69)),
  ((45,88),(45,99),(20,99),(20,110)),((70,88),(70,103),(64,103),(64,110)),
  ((103,88),(103,103),(108,103),(108,110)),((127,88),(127,99),(152,99),(152,110)),
),height:134),[Tiny Gen1 integration. System logic runs from the configured 24 MHz clock; JTAG is asynchronous.])

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

#let tcd-diagram() = {
  let names=("next_ptr":"Next","source":"Source","destination":"Destination","byte_count":"Byte count",
    "source_stride":"Src stride","destination_stride":"Dst stride","y_count":"Rows","reserved":"Rsvd",
    "control":"Control","crc_expected":"CRC expect","crc_seed":"CRC seed","crc_result":"CRC result",
    "status":"Status","bytes_done":"Bytes done","error_status":"Error","reserved_tail":"Reserved","reserved_tail2":"Reserved")
  let fields=()
  for field in data.tcd {
    if calc.rem(field.offset,16)==0 {fields.push(bf.note(left)[#("0x"+upper(str(field.offset,base:16)))])}
    fields.push(bf.bytes(field.bytes,fill:if field.role=="reserved" {gray} else if field.role=="HAL result" {rgb("#E7EFF6")} else {pale-gold})[#{names.at(field.name)}])
  }
  diagram("dma-tcd",{
    set text(font:"Inter",size:9pt)
    show: bf.bf-config.with(row-height:27pt,field-font-size:9pt,note-font-size:9pt,header-font-size:9pt,stroke:0.6pt+ink)
    bf.bytefield(bpr:128,msb:right,pre:(36pt,),post:(),
      bf.bitheader(0,[0],32,[4],64,[8],96,[12],numbers:none,angle:0deg,text-size:9pt),..fields)
  },[DMA TCD: four 16-byte rows. Gold: configuration; blue: HAL result fields; gray: reserved.])
}

