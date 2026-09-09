#import "style.typ": data, ink, gold, pale-gold, gray, muted, rhythm
#import "@preview/bytefield:0.0.8" as bf
#import "@preview/rivet:0.3.1" as rv
#import "@preview/blockcell:0.1.0" as bc
#import "@preview/circuiteria:0.2.1" as ce
#import "@preview/cetz:0.3.4" as c3

#let diagrams = data.system_reference.illustrations
#let blue-gray = rgb("#E7EFF6")
#let diagram-text(body) = text(font:"Inter",size:9pt,fill:ink,body)
#let diagram-note(body) = block(above:4pt,below:0pt)[
  #set par(leading:rhythm.small-leading,spacing:rhythm.small-spacing)
  #text(size:9pt,fill:muted,body)
]

#let dma-tcd-diagram() = block(width:100%,breakable:false)[
  #set text(font:"Inter",size:9pt,fill:ink)
  #show: bf.bf-config.with(row-height:24pt,field-font-size:9pt,note-font-size:9pt,
    header-font-size:9pt,stroke:0.6pt+ink)
  #let fields = ()
  #for field in diagrams.dma_tcd {
    if calc.rem(field.offset,16)==0 {
      fields.push(bf.note(left)[#("0x"+upper(str(field.offset,base:16)))])
    }
    fields.push(bf.bytes(int(field.bits/8),fill:if field.role=="reserved" {gray}
      else if field.role=="writeback" {blue-gray} else {pale-gold})[#field.name])
  }
  #bf.bytefield(bpr:128,msb:right,pre:(36pt,),post:(),
    bf.bitheader(0,[0],32,[4],64,[8],96,[12],numbers:none,angle:0deg,text-size:9pt),..fields)
  #diagram-note[Byte offsets increase left to right; four 16-byte rows form the 64-byte TCD.
    Gold: software configuration. Blue-gray: current HAL result writeback. Gray: reserved.
    Word serialization and 64-byte descriptor alignment are separate from the transfer width.]
]

#let sdio-command-diagram() = block(width:100%,breakable:false)[
  #set text(font:"Inter",size:9pt,fill:ink)
  #show: bf.bf-config.with(row-height:26pt,field-font-size:9pt,note-font-size:9pt,
    header-font-size:9pt,stroke:0.6pt+ink)
  #bf.bytefield(bpr:48,msb:left,pre:(),post:(),
    bf.bitheader(47,40,8,0,angle:0deg,text-size:9pt),
    ..diagrams.sdio_command.map(f=>bf.bits(f.bits,fill:if f.bits==1 {gray} else {pale-gold})[#f.label]))
  #diagram-note[Native SD command: S = start 0; T = host transmission 1; CMD = 6-bit command index;
    ARG = 32-bit argument; CRC7 covers S through ARG; E = end 1. Bit 47 is transmitted first.]
]

#let instruction-row(example:none, start:0) = {
  let ranges=(:)
  let colors=(:)
  let short=("CLASS":"CLS","OPCODE":"OP","PREDICATE":"PRED","SRC0":"S0","SRC1":"S1","IMMEDIATE":"IMM")
  for field in diagrams.apu.fields.filter(f=>f.lsb >= start and f.lsb < start + 32) {
    let span=str(field.lsb+field.bits - 1)+"-"+str(field.lsb)
    let name=short.at(field.label,default:field.label)
    if example!=none {
      let value=example.values.at(field.name)
      name=if field.name=="immediate" {"0x"+upper(str(value,base:16))} else {str(value)}
    }
    ranges.insert(span,(name:name))
    colors.insert(span,if field.name in ("instruction_class","opcode","predicate") {pale-gold} else {gray})
  }
  let schema=rv.schema.load((structures:(main:(bits:32,start:start,ranges:ranges)),colors:(main:colors)))
  rv.schema.render(schema,width:100%,config:rv.config.config(
    default-font-family:"Inter",default-font-size:20pt,italic-font-family:"Inter",italic-font-size:20pt,
    text-color:ink,link-color:ink,bit-i-color:ink,border-color:ink,background:white,
    bit-width:32,bit-height:42,margins:(4,4,4,4),all-bit-i:false,full-page:false))
}

#let apu-instruction-diagram() = block(width:100%,breakable:false)[
  #set text(font:"Inter",size:9pt,fill:ink)
  #diagram-text[*APUMC 64-bit instruction format*]
  #instruction-row(start:32)
  #instruction-row(start:0)
  #for example in diagrams.apu.examples {
    block(above:6pt,below:2pt)[#diagram-text[#example.title · #example.word]]
    instruction-row(example:example,start:32)
    instruction-row(example:example,start:0)
  }
  #diagram-note[CLS = instruction class; OP = opcode; PRED = predicate; DST/S0/S1 = register indexes;
    AUX = operation-specific selector; IMM = immediate. These are internal APU instructions,
    not LP/HP RISC-V extensions. Examples demonstrate encoding, not completed codec execution.]
]

#let memory-window-diagram() = block(width:100%,breakable:false)[
  #set text(font:"Inter",size:9pt,fill:ink)
  #set par(leading:rhythm.small-leading,spacing:5pt)
  #for window in diagrams.windows {
    block(above:0pt,below:4pt,grid(columns:(32mm,87mm,47mm),gutter:2mm,
      bc.cell(width:100%,height:12mm,fill:pale-gold,stroke:0.6pt+ink)[#align(center+horizon)[#window.symbol]],
      bc.cell(width:100%,height:12mm,fill:gray,stroke:0.6pt+ink)[#align(center+horizon)[#window.base_hex … #window.end_hex]],
      bc.cell(width:100%,height:12mm,fill:white,stroke:0.6pt+ink)[#align(center+horizon)[#window.size_label]]))
  }
  #diagram-note[Selected PRODUCT memory address windows, not to scale. The reference SRAM is 32 KiB.
    FLASH is a boot alias; serial-memory apertures do not establish fitted device capacity.
    Register windows and reserved gaps remain in the complete address tables.]
]

#let cache-boundary-diagram() = block(width:100%,breakable:false)[
  #set text(font:"Inter",size:9pt,fill:ink)
  #let c=diagrams.cache
  #diagram-text[Relative byte boundaries: 0 · #c.granule · #c.covered_bytes]
  #v(4pt)
  #bc.region(width:100%,fill:white,stroke:0.6pt+ink,radius:0pt)[
    #bc.cell(width:77mm,height:12mm,fill:gray,stroke:0.6pt+ink)[#align(center+horizon)[CBO block 0: bytes 0–63]]
    #h(2mm)
    #bc.cell(width:77mm,height:12mm,fill:gray,stroke:0.6pt+ink)[#align(center+horizon)[CBO block 1: bytes 64–127]]
    #linebreak()
    #v(4pt)
    #bc.cell(width:19mm,height:15mm,fill:gray,stroke:0.6pt+ink)[16 B \ before]
    #bc.cell(width:57mm,height:15mm,fill:pale-gold,stroke:0.6pt+ink)[48 B payload \ bytes 16–63]
    #h(2mm)
    #bc.cell(width:19mm,height:15mm,fill:pale-gold,stroke:0.6pt+ink)[16 B \ payload]
    #bc.cell(width:57mm,height:15mm,fill:gray,stroke:0.6pt+ink)[48 B after \ bytes 80–127]
  ]
  #diagram-note[The software-declared 64-byte maintenance granule covers a 64-byte payload at offset 16
    using two blocks. Keep boundary bytes under compatible ownership. Relative offsets are illustrative;
    this is not a verified HP cache tag/set/way layout or an allocated buffer address.]
]

#let uart-fifo-diagram() = block(width:100%,breakable:false)[
  #set text(font:"Inter",size:9pt,fill:ink)
  #for (name,geometry) in diagrams.uart_fifo.pairs() {
    block(above:4pt,below:6pt)[
      *#upper(name) FIFO: #geometry.depth entries × #geometry.bits bits*
      #linebreak()
      #v(3pt)
      #bc.region(width:100%,fill:white,stroke:0.6pt+ink,radius:0pt)[
        #for index in ("0","1","2","…","63") {
          bc.cell(width:29mm,height:13mm,fill:gray,stroke:0.6pt+ink)[#align(center+horizon)[Entry #index]]
          h(2pt)
        }
      ]
    ]
  }
  #bc.cell(width:103mm,height:14mm,fill:pale-gold,stroke:0.6pt+ink)[#align(center+horizon)[RX entry: data bits 7:0]]
  #h(2mm)
  #bc.cell(width:61mm,height:14mm,fill:blue-gray,stroke:0.6pt+ink)[#align(center+horizon)[Error metadata bits 11:8]]
  #diagram-note[Storage slots are shown schematically; the drawing is not a live occupancy snapshot.
    TX stores eight data bits. RX stores eight data bits plus four error bits; the 32-bit APB RXDATA
    access width is a separate register interface. Pointer, flush and watermark rules remain in the UART contract.]
]

#let circuit-diagram(id) = block(width:100%,breakable:false)[
  #set text(font:"Inter",size:9pt,fill:ink)
  #let circuit=diagrams.circuits.at(id)
  #ce.circuit(length:1cm,{
    for node in circuit.nodes {
      let ports=(:)
      let margins=(:)
      for side in ("west","east","north","south") {
        ports.insert(side,node.ports.filter(p=>p.side==side).map(p=>(id:p.id,name:"")))
      }
      for (side,values) in node.at("port_margins",default:(:)) {
        margins.insert(side,values.map(v=>v*1%))
      }
      ce.element.block(id:node.id,x:node.x,y:node.y,w:node.w,h:node.h,
        name:node.title.split("\n").map(diagram-text).join(linebreak()),
        ports:ports,ports-margins:margins,
        fill:if node.id in ("reg","loader") {pale-gold} else {gray},
        radius:0.06,stroke:0.6pt+ink)
    }
    for (index,edge) in circuit.edges.enumerate() {
      let src=edge.from.split(".")
      let dst=edge.to.split(".")
      ce.wire.wire("edge"+str(index),(src.first()+"-port-"+src.last(),dst.first()+"-port-"+dst.last()),
        bus:edge.kind=="data",name:none,color:ink,dashed:edge.kind=="control",directed:true,
        style:edge.style,rotate-name:false,zigzag-dir:edge.at("zigzag-dir",default:"vertical"),
        guided-sides:edge.at("guided-sides",default:("east","west")))
      c3.draw.content(("edge"+str(index)+".start",50%,"edge"+str(index)+".end"),
        box(fill:white,inset:(x:2pt,y:1pt),diagram-text(edge.label)))
    }
  })
  #diagram-note[Solid arrows: data paths. Dashed arrows: control signals. #circuit.note]
]
