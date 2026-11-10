#import "style.typ": *
#import "@preview/bytefield:0.0.8" as bf
#import "@preview/blockcell:0.1.0" as bc
#import "@preview/circuiteria:0.2.1" as ce
#import "@preview/cetz:0.3.4" as c3
#let diagrams=data.illustrations
#let blue-gray=rgb("#E7EFF6")
#let diagram-id(package,id)=if package=="circuiteria" {"circuit-"+id} else if package=="bytefield" {"format-"+id} else {"storage-"+id}
#let diagram-use(package,id)=context {
 let pos=here().position()
 metadata((kind:"tiny-diagram",id:diagram-id(package,id),source_id:id,package:package,page:pos.page,x:pos.x.pt(),y:pos.y.pt()))
}
#let diagram-end(package,id)=context {
 let pos=here().position()
 metadata((kind:"tiny-diagram-end",id:diagram-id(package,id),page:pos.page,x:pos.x.pt(),y:pos.y.pt()))
}
#let diagram-text(body)=text(font:"Inter",size:9pt,fill:ink,body)
#let diagram-note(body)=block(above:4pt,below:0pt)[
 #set par(leading:rhythm.small-leading,spacing:rhythm.small-spacing)
 #text(size:9pt,fill:muted,body)
]
#let circuit-diagram(id) = block(width:100%,breakable:false)[
  #diagram-use("circuiteria",id)
  #set text(font:"Inter",size:9pt,fill:ink)
  #let circuit=diagrams.circuits.at(id)
  #if "clock_note" in circuit {diagram-note[*Clock domains:* #circuit.clock_note]}
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
        guided-center:edge.at("guided-center",default:(50,50)).map(v=>v*1%),
        guided-margins:edge.at("guided-margins",default:(15,15)).map(v=>v*1%),
        dodge-y:edge.at("dodge-y",default:0),
        dodge-sides:edge.at("dodge-sides",default:("east","west")),
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


#let storage-diagram(record) = block(width:100%,breakable:false)[
  #diagram-use("blockcell",record.id)
  #set text(font:"Inter",size:9pt,fill:ink)
  #for store in record.at("stores",default:()) {
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


#let circuit-figure(id)=block(width:100%,breakable:false)[
 #figure(circuit-diagram(id),kind:image,supplement:[Figure],caption:[#diagrams.circuits.at(id).title.])
 #label("circuit-"+id)
]
#let binary-figures(chapter,section)={
 for (id,r) in diagrams.layouts.pairs().filter(((id,r))=>chapter in r.chapters and r.section==section) {
  if "existing_label" in r {
   par([Shared format: #link(label(r.existing_label))[#r.title].])
  } else if r.chapters.first()==chapter {
   block(breakable:false)[
    #figure(binary-diagram(r),kind:image,supplement:[Figure],caption:[#r.title.])
    #label("format-"+id)
    #for source in r.sources {source-note(source,title:"Format source: "+source.split("/").last())}
   ]
  } else {par([Shared format: #link(label("format-"+id))[#r.title].])}
 }
}
#let storage-figures(chapter,section:"functional")={
 for (id,r) in diagrams.storage.pairs().filter(((id,r))=>chapter in r.chapters and r.section==section) {
  if r.chapters.first()==chapter {
   block(breakable:false)[
    #figure(storage-diagram(r),kind:image,supplement:[Figure],caption:[#r.title.])
    #label("storage-"+id)
    #for source in r.sources {source-note(source,title:"Storage source: "+source.split("/").last())}
   ]
  } else {par([Shared storage: #link(label("storage-"+id))[#r.title].])}
 }
}
