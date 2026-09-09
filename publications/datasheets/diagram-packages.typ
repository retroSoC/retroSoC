#import "style.typ": data, ink, gold, pale-gold, gray, muted, rhythm, code, ds-table, source-note, change-start, change-end
#import "@preview/bytefield:0.0.8" as bf
#import "@preview/rivet:0.3.1" as rv
#import "@preview/blockcell:0.1.0" as bc
#import "@preview/circuiteria:0.2.1" as ce
#import "@preview/cetz:0.3.4" as c3

#let diagrams = data.system_reference.illustrations
#let diagram-position(kind, package, id) = context {
  let position=here().position()
  metadata((kind:kind,package:package,id:id,page:position.page,x:position.x.pt(),y:position.y.pt()))
}
#let diagram-use(package, id) = diagram-position("publication-diagram",package,id)
#let diagram-end(package, id) = diagram-position("publication-diagram-end",package,id)
#let blue-gray = rgb("#E7EFF6")
#let diagram-text(body) = text(font:"Inter",size:9pt,fill:ink,body)
#let diagram-note(body) = block(above:4pt,below:0pt)[
  #set par(leading:rhythm.small-leading,spacing:rhythm.small-spacing)
  #text(size:9pt,fill:muted,body)
]

#let dma-tcd-diagram() = block(width:100%,breakable:false)[
  #diagram-use("bytefield","dma-tcd")
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
  #diagram-end("bytefield","dma-tcd")
]

#let sdio-command-diagram() = block(width:100%,breakable:false)[
  #diagram-use("bytefield","sd-command")
  #set text(font:"Inter",size:9pt,fill:ink)
  #show: bf.bf-config.with(row-height:26pt,field-font-size:9pt,note-font-size:9pt,
    header-font-size:9pt,stroke:0.6pt+ink)
  #bf.bytefield(bpr:48,msb:left,pre:(),post:(),
    bf.bitheader(47,40,8,0,angle:0deg,text-size:9pt),
    ..diagrams.sdio_command.map(f=>bf.bits(f.bits,fill:if f.bits==1 {gray} else {pale-gold})[#f.label]))
  #diagram-note[Native SD command: S = start 0; T = host transmission 1; CMD = 6-bit command index;
    ARG = 32-bit argument; CRC7 covers S through ARG; E = end 1. Bit 47 is transmitted first.]
  #diagram-end("bytefield","sd-command")
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
  #diagram-use("rivet","apu-common")
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
  #diagram-end("rivet","apu-common")
]

#let memory-window-diagram() = block(width:100%,breakable:false)[
  #diagram-use("blockcell","product-memory-windows")
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
  #diagram-end("blockcell","product-memory-windows")
]

#let cache-boundary-diagram() = block(width:100%,breakable:false)[
  #diagram-use("blockcell","cache-boundaries")
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
  #diagram-end("blockcell","cache-boundaries")
]

#let uart-fifo-diagram() = block(width:100%,breakable:false)[
  #diagram-use("blockcell","uart-fifos")
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
  #diagram-end("blockcell","uart-fifos")
]

#let circuit-diagram(id) = block(width:100%,breakable:false)[
  #diagram-use("circuiteria",id)
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
        name:block(width:node.w*1cm - 8pt)[
          #set par(leading:2pt,spacing:0pt)
          #align(center)[#node.title.split("\n").map(diagram-text).join(linebreak())]
        ],
        ports:ports,ports-margins:margins,
        fill:if node.id in ("reg","loader") {pale-gold} else {gray},
        radius:0.06,stroke:0.6pt+ink)
    }
    for (index,edge) in circuit.edges.enumerate() {
      let src=edge.from.split(".")
      let dst=edge.to.split(".")
      ce.wire.wire("edge"+str(index),(src.first()+"-port-"+src.last(),dst.first()+"-port-"+dst.last()),
        bus:edge.kind=="data",name:none,color:if edge.at("availability",default:"")=="admission-blocked" {muted} else {ink},dashed:edge.kind=="control",directed:true,
        style:edge.style,rotate-name:false,zigzag-dir:edge.at("zigzag-dir",default:"vertical"),
        guided-sides:edge.at("guided-sides",default:("east","west")),
        dodge-y:edge.at("dodge-y",default:0),
        dodge-margins:edge.at("dodge-margins",default:(5,5)).map(v=>v*1%))
    }
    // Keep label backplates above every route, including later crossing wires.
    for (index,edge) in circuit.edges.enumerate() {
      let anchors=if edge.style=="dodge" {("dodge-start","dodge-end")} else {("start","end")}
      c3.draw.content(("edge"+str(index)+"."+anchors.first(),50%,"edge"+str(index)+"."+anchors.last()),
        box(fill:white,inset:(x:2pt,y:1pt),diagram-text(edge.label)))
    }
  })
  #diagram-note[Solid arrows: data paths. Dashed arrows: control signals. #circuit.note]
  #diagram-end("circuiteria",id)
]

#let binary-diagram(record) = block(width:100%,breakable:false)[
  #diagram-use("bytefield",record.id)
  #set text(font:"Inter",size:9pt,fill:ink)
  #show: bf.bf-config.with(row-height:26pt,field-font-size:9pt,note-font-size:9pt,
    header-font-size:9pt,stroke:0.6pt+ink)
  #let field-fill(field) = {
    if field.at("role",default:"")=="reserved" {gray}
    else if field.at("role",default:"") in ("writeback","mixed") {blue-gray} else {pale-gold}
  }
  #if record.kind=="bytes" {
    let bytes=int(record.bits/8)
    let row-bytes=if calc.rem(bytes,16)==0 {16} else {12}
    let header=()
    for n in range(0,row-bytes,step:4) {header.push(n*8); header.push([#n])}
    let cells=()
    for field in record.fields {
      if calc.rem(field.offset,row-bytes)==0 {
        cells.push(bf.note(left)[#("0x"+upper(str(field.offset,base:16)))])
      }
      cells.push(bf.bytes(int(field.bits/8),fill:field-fill(field))[#field.label])
    }
    bf.bytefield(bpr:row-bytes*8,msb:right,pre:(36pt,),post:(),
      bf.bitheader(..header,numbers:none,angle:0deg,text-size:9pt),..cells)
  } else {
    for row in record.at("rows",default:(record,)) {
      if "label" in row {block(above:4pt,below:4pt)[#text(weight:"semibold",row.label)]}
      let compressed=row.at("compressed",default:record.at("compressed",default:false))
      let groups=row.at("display_groups",default:record.at("display_groups",default:none))
      let fields=if groups==none {row.fields} else {
        groups.map(g=>if g.first()==g.last() {row.fields.at(g.first())} else {
          (label:"Words "+str(g.first())+" … "+str(g.last()),bits:32,role:"configuration")})
      }
      let cells=fields.map(f=>bf.bits(if compressed {32} else {f.bits},fill:field-fill(f))[#f.label])
      let bits=if compressed {fields.len()*32} else {row.bits}
      let msb=record.order=="msb"
      bf.bytefield(bpr:bits,msb:if msb {left} else {right},pre:(),post:(),
        ..if compressed {()} else {(bf.bitheader(if msb {bits - 1} else {0},if msb {0} else {bits - 1},angle:0deg,text-size:9pt),)},
        ..cells)
    }
  }
  #diagram-note[#record.note]
  #diagram-end("bytefield",record.id)
]

#let binary-figures(chapter, section) = {
  for (id,record) in diagrams.layouts.pairs().filter(((id,r))=>chapter in r.chapters and r.section==section) {
    if record.chapters.first()==chapter and not "existing_label" in record {
      block(breakable:false)[
        #change-start("binary-"+id,record.title,category:"added")
        #figure(binary-diagram(record),kind:image,supplement:[Figure],caption:[#record.title.])
        #label("binary-"+id)
        #for path in record.sources {source-note(path,title:"Format source: "+path.split("/").last())}
        #change-end("binary-"+id)
      ]
    } else if record.chapters.first()!=chapter {
      block[
        #change-start("binary-link-"+chapter+"-"+id,record.title+" shared-instance reference",category:"cross-reference")
        Shared format: #link(label(record.at("existing_label",default:"binary-"+id)))[#record.title].
        #record.at("shared_notes",default:(:)).at(chapter,default:"Apply this instance's address, pads and interrupt routing.")
        #change-end("binary-link-"+chapter+"-"+id)
      ]
    }
  }
}

#let storage-diagram(record) = block(width:100%,breakable:false)[
  #diagram-use("blockcell",record.id)
  #set text(font:"Inter",size:9pt,fill:ink)
  #for store in record.stores {
    block(above:4pt,below:7pt)[
      #text(weight:"semibold")[#store.title: #store.depth × #if store.bits > 512 {
        [#int(store.bits/8) bytes]
      } else {[#store.bits bits]}]
      #v(3pt)
      #let slots=if store.depth <= 4 {range(store.depth).map(str)} else {("0","1","2","…",str(store.depth - 1))}
      #bc.region(width:100%,fill:white,stroke:0.6pt+ink,radius:0pt)[
        #grid(columns:(1fr,)*slots.len(),gutter:2mm,
          ..slots.map(slot=>bc.cell(width:100%,height:11mm,fill:gray,stroke:0.6pt+ink)[#align(center+horizon)[#slot]]))
      ]
    ]
  }
  #for row in record.at("ranges",default:()) {
    block(above:0pt,below:4pt,grid(columns:(54mm,85mm,27mm),gutter:2mm,
      bc.cell(width:100%,height:12mm,fill:pale-gold,stroke:0.6pt+ink)[#align(center+horizon)[#row.name]],
      bc.cell(width:100%,height:12mm,fill:gray,stroke:0.6pt+ink)[#align(center+horizon)[#row.base_hex … #row.end_hex]],
      bc.cell(width:100%,height:12mm,fill:white,stroke:0.6pt+ink)[#align(center+horizon)[#row.size_label]]))
  }
  #if "sections" in record {
    block(above:3pt,below:5pt)[#code(record.profile)]
    grid(columns:(1fr,)*record.sections.len(),gutter:2mm,
      ..record.sections.map(s=>bc.cell(width:100%,height:24mm,fill:pale-gold,stroke:0.6pt+ink)[
        #align(center+horizon)[*#s.name#if s.name!=".init" and s.includes_init {text(" + .init")}* \ VMA: #s.vma \ LMA: #if s.name==".bss" {[No load bytes]} else {s.lma}]
      ]))
    block(above:5pt)[Stack top: end of #record.stack_region. Startup: #code(record.startup).]
  }
  #for budget in record.at("budgets",default:()) {
    block(above:5pt,below:5pt)[
      #text(weight:"semibold",budget.name)
      #v(3pt)
      #grid(columns:(1fr,1fr,1fr,1fr),gutter:2mm,
        ..(("Payload",budget.payload_bytes),("Stored",budget.storage_bytes),("Stride",budget.stride_bytes),("Total",budget.total_bytes)).map(((name,value))=>
          bc.cell(width:100%,height:13mm,fill:if name=="Total" {pale-gold} else {gray},stroke:0.6pt+ink)[#align(center+horizon)[#name \ #value B]]))
    ]
  }
  #diagram-note[#record.note]
  #diagram-end("blockcell",record.id)
]

#let storage-figures(chapter, section:"functional") = {
  for (id,record) in diagrams.storage.pairs().filter(((id,r))=>chapter in r.chapters and r.section==section) {
    if record.chapters.first()==chapter and not "existing_label" in record {
      block(breakable:false)[
        #change-start("storage-"+id,record.title,category:"added")
        #figure(storage-diagram(record),kind:image,supplement:[Figure],caption:[#record.title.])
        #label("storage-"+id)
        #for path in record.sources {source-note(path,title:"Storage source: "+path.split("/").last())}
        #change-end("storage-"+id)
      ]
    } else if record.chapters.first()!=chapter {
      block[
        #change-start("storage-link-"+chapter+"-"+id,record.title+" shared-instance reference",category:"cross-reference")
        Shared storage geometry: #link(label(record.at("existing_label",default:"storage-"+id)))[#record.title].
        Instance routing, ownership and enabled paths remain those described here.
        #change-end("storage-link-"+chapter+"-"+id)
      ]
    }
  }
}

#let family-instruction-diagram(family) = block(width:100%,breakable:false)[
  #diagram-use("rivet","apu-family-"+lower(family.name))
  #set text(font:"Inter",size:9pt,fill:ink)
  #diagram-text[*#family.name: class #family.class*]
  #for start in (32,0) {
    let ranges=(:)
    let colors=(:)
    for field in diagrams.apu.fields.filter(f=>f.lsb >= start and f.lsb < start + 32) {
      let aliases=("instruction_class":"CLS","opcode":"OP","predicate":"PRED","dst":"DST","src0":"S0","src1":"S1","aux":"AUX","immediate":"IMM")
      let name=if field.name=="instruction_class" {str(family.class)}
        else if field.name=="opcode" or field.name in family.active {aliases.at(field.name)} else {"0"}
      let span=str(field.lsb+field.bits - 1)+"-"+str(field.lsb)
      ranges.insert(span,(name:name))
      colors.insert(span,if field.name in ("instruction_class","opcode","predicate") {pale-gold} else {gray})
    }
    let schema=rv.schema.load((structures:(main:(bits:32,start:start,ranges:ranges)),colors:(main:colors)))
    rv.schema.render(schema,width:100%,config:rv.config.config(
      default-font-family:"Inter",default-font-size:20pt,italic-font-family:"Inter",italic-font-size:20pt,
      text-color:ink,link-color:ink,bit-i-color:ink,border-color:ink,background:white,
      bit-width:32,bit-height:42,margins:(4,4,4,4),all-bit-i:false,full-page:false))
  }
  #diagram-note[#family.note The diagram shows the union of admitted operand slots in this family;
    individual opcodes reserve the slots listed below. Example #family.example.name: #family.example.word.]
  #diagram-end("rivet","apu-family-"+lower(family.name))
]

#let apu-family-figures() = {
  change-start("apu-family-guide","APU instruction-family coverage and target qualifications",category:"added")
  [The following seven classes cover all currently defined operation codes. Variable slots are operands
  admitted by the existing validator; zero slots are whole fields required to be zero.
  Tool targets describe encoding acceptance, not enabled production codecs or successful payload execution.
  Primitive masks shown are APUMC requirements for the encoded example, distinct from the APB capability word.
  WAIT is source-dependent: P4 admits kernel/input/output-FIFO waits;
  P5 also admits DMA, TX-stream and ring-writeback waits. Value ranges, mode bits, scratch bounds and entry control flow still apply.]
  change-end("apu-family-guide")
  for family in diagrams.apu.families {
    change-start("apu-family-"+lower(family.name),"APU "+family.name+" instruction family",category:"added")
    figure(family-instruction-diagram(family),kind:image,supplement:[Figure],caption:[APU #family.name instruction-family operand fields.])
    ds-table("apu-opcodes-"+lower(family.name),[APU #family.name opcode and operand constraints],
      ([OP],[Operation],[Variable slots],[Zero slots],[Example mask],[Tool target]),
      family.operations.map(op=>(code(op.opcode_hex),code(op.name),op.slots,op.zero_slots,code(op.required_mask),op.targets)),
      widths:(0.3fr,1.1fr,1fr,1fr,0.85fr,0.65fr))
    source-note("scripts/apu_isa.py",title:"Complete operand/value and target checks")
    source-note("rtl/ip/multimedia/apu_microcode_pkg.sv",title:"RTL encoding and predicate checks")
    change-end("apu-family-"+lower(family.name))
  }
}
