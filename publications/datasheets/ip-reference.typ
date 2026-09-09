#import "style.typ": *
#import "figures.typ": box, wire
#import "@preview/cetz:0.5.2"
#import "waveforms.typ": timing

#let inline(value) = {
  let parts=value.split("`")
  for (i,part) in parts.enumerate() {
    if calc.rem(i,2)==1 { code(part) } else { part.replace("**","") }
  }
}

#let subhead(ip, name, depth) = [
  #{
    show heading: it => heading-layout(it,before:rhythm.minor-before,after:rhythm.minor-after)
    heading(level:depth+1,numbering:none,outlined:false,bookmarked:true,name)
  }#label("detail-"+ip+"-"+lower(name).replace(" ","-"))
]

#let prose-blocks(ip, section-title, blocks) = {
  for (n,item) in blocks.enumerate() {
    if item.kind=="heading" {
      minor-title(inline(item.text))
    } else if item.kind=="code" {
      if item.language not in ("mermaid","dot") {
        code-block(raw(item.text,block:true),breakable:true)
      }
    } else if item.kind=="table" {
      ds-table(ip+"-"+str(n),section-title,
        item.headers.map(inline),item.rows.map(r=>r.map(inline)))
    } else if item.kind=="list" {
      let bodies=item.items.enumerate().map(((index,entry))=>{
        let content=prose-blocks(ip+"-"+str(n)+"-"+str(index),section-title,entry.blocks)
        if item.ordered {enum.item(entry.number,content)} else {list.item(content)}
      })
      if item.ordered {enum(..bodies)} else {list(..bodies)}
    } else { par(inline(item.text)) }
  }
}

#let prose-sections(ip, sections, depth) = {
  for (index,section) in sections.enumerate() {
    if sections.len()>1 { minor-title(section.title) }
    prose-blocks(ip+"-"+str(index),section.title,section.blocks)
  }
}

#let component-diagram(family, id) = {
  let items=data.chapters.at(family).blocks
  if id=="uart1" { items=items.map(v=>v.replace("Flow/DMA/IRQ","FIFO status / IRQ")) }
  cetz.canvas({
    import cetz.draw: line, content
    box(4.3,1.0,8.4,1.0,text(9pt,items.first()),fill:pale-gold)
    line((8.5,1.0),(8.5,0.55),stroke:0.6pt+ink)
    let rows=calc.ceil((items.len()-1)/3)
    line((-0.25,0.55),(-0.25,0.55-(rows - 1)*1.7),stroke:0.6pt+ink)
    for row in range(rows) {
      let columns=calc.min(3,items.len()-1-row*3)
      line((-0.25,0.55-row*1.7),((columns - 1)*5.75+2.5,0.55-row*1.7),stroke:0.6pt+ink)
    }
    for (i,entry) in items.slice(1).enumerate() {
      let col=calc.rem(i,3)
      let row=calc.floor(i/3)
      let x=col*5.75
      let y= -row*1.7 - 1.0
      box(x,y,5.0,0.95,text(9pt,entry),fill:gray)
      line((x+2.5,0.55-row*1.7),(x+2.5,y+0.95),stroke:0.6pt+ink)
    }
    let flow=data.chapters.at(family).flow
    if id=="uart1" { flow=("APB TXDATA","FIFO + serializer","Dedicated TX pad") }
    let y= -rows*1.7 - 1.1
    content((8.25,y+1.4),text(9pt,fill:muted,"Representative data / event path"))
    for (n,entry) in flow.enumerate() {
      box(n*5.75,y,5.0,1.0,text(9pt,entry),fill:white)
      if n < 2 { wire(((n*5.75+5.0,y+0.5),(n*5.75+5.75,y+0.5))) }
    }
  })
}

#let bit-layout(register) = {
  let fields=register.fields.sorted(key:f=>-f.msb)
  set text(size:9pt)
  set par(leading:rhythm.small-leading,spacing:0pt)
  let cells = ()
  for high in (31,15) {
    cells += range(high,high - 16,step:-1).map(b=>align(center,str(b)))
    cells += fields.enumerate().filter(((n,f))=>f.lsb<=high and f.msb>=high - 15).map(((n,f))=>{
        let span=calc.min(f.msb,high)-calc.max(f.lsb,high - 15)+1
        let text=if f.name.len()<=span*4 {f.name} else {"F"+str(n+1)}
        table.cell(colspan:span,fill:if f.name=="Reserved" {gray} else {pale-gold},align(center,text))
      })
  }
  table(columns:range(16).map(n=>1fr),
    stroke:table-stroke,inset:rhythm.bits-inset,..cells)
}

#let register-section(family, depth) = {
  let reference=data.registers.at(family)
  subhead(family,"Register Summary",depth)
  [Offsets are byte offsets within the named register group. Repeated groups use the base,
  stride and instance range below. Access descriptions include register-specific restrictions.
  A numeric reset identifies stored or fixed state. Dynamic marks live producer/integration
  state; apply the domain, validity and snapshot rules before consuming it. Not retained marks
  a command or data port, rather than a persistent configuration word.]
  for group in reference.groups {
    let registers=reference.registers.filter(r=>r.group==group.id)
    if registers.len()==0 { continue }
    minor-title(group.title)
    if group.count>1 {
      par([Instance offset: #code("0x"+str(group.base,base:16)) + n × #code("0x"+str(group.stride,base:16)),
        n = 0…#(group.count - 1). Local offsets below are added to this instance offset.])
    }
    {
      // Register-name links keep their blue color and destination, without decoration.
      show underline: it => it.body
      ds-table(family+"-summary-"+group.id,group.title,
        ([Offset],[Register],[Access],[Reset],[Description]),
        registers.map(r=>(code("0x"+str(r.offset,base:16)),link(label("reg-"+family+"-"+r.key),code(r.name)),r.access,inline(r.reset),inline(r.description))),
        widths:(0.55fr,1.6fr,0.6fr,1.1fr,2.6fr))
    }
  }
  subhead(family,"Register Description",depth)
  [Bit-layout cells refer to the numbered field rows below each diagram. Reserved bits must
  be handled as specified by the register; register access checks still apply to the full word.]
  for register in reference.registers {
    block(above:rhythm.register-before,below:rhythm.metadata-after,breakable:false,sticky:true)[
      #show heading: it => heading-layout(it,before:0pt,after:rhythm.register-after)
      #set text(size:9pt)
      #set par(leading:rhythm.small-leading,spacing:rhythm.small-spacing)
      #heading(level:depth+2,numbering:none,outlined:false,bookmarked:true,register.name)
      #label("reg-"+family+"-"+register.key)
      #text(9pt,fill:muted)[#register.group · offset #code("0x"+str(register.offset,base:16)) · #register.access · reset #inline(register.reset)]
      #linebreak()
      #source(register.source,title:"RTL definition",line:register.line)
      #if register.c_source!=none { [ · ]; source(register.c_source,title:"C ABI / HAL") }
    ]
    par(inline(register.description))
    block(breakable:false,above:rhythm.bits-space,below:rhythm.bits-space,bit-layout(register))
    let fields=register.fields.sorted(key:f=>-f.msb)
    ds-table("fields-"+family+"-"+register.key,[#register.name field descriptions],
      ([\#],[Bits],[Field],[Reset],[Description]),
      fields.enumerate().map(((n,f))=>("F"+str(n+1),str(f.msb)+if f.msb!=f.lsb {":"+str(f.lsb)} else {""},code(f.name),inline(f.reset),inline(f.description))),
      widths:(0.25fr,0.5fr,1.1fr,0.75fr,2.3fr))
    if register.at("notes",default:"")!="" { par(inline(register.notes)) }
  }
}

#let ip-reference(id, family, depth, shared:none, legacy:none, register-family:none, software-note:none) = {
  let chapter=data.chapters.at(family)
  subhead(id,"Features and Block Diagram",depth)
  list(..chapter.at("features",default:()).map(inline))
  figure(component-diagram(family,id),caption:[#chapter.title functional organization.])
  subhead(id,"Functional Description",depth)
  if legacy!=none {
    set heading(outlined:false,bookmarked:true)
    legacy
  }
  for paragraph in chapter.notes { par(inline(paragraph)) }
  prose-sections(id+"-functional",chapter.functional,depth)
  subhead(id,"Protocol and Timing",depth)
  [For common APB4/AXI4/stream handshake rules, see @common-protocols.]
  if shared==none {
    timing(family,[#chapter.title example transaction or event sequence.])
    if family+"-exception" in data.waveforms {
      timing(family+"-exception",[#chapter.title waiting, fault or recovery example.])
    }
  } else {
    [Common protocol and timing follow #link(label("detail-"+shared+"-protocol-and-timing"))[the shared implementation description].
    The instance's address, pins, IRQ routing and software ownership remain those listed above.]
  }
  if shared==none { register-section(family,depth) }
  else {
    subhead(id,"Register Interface",depth)
    let target=if register-family==none { family } else {register-family}
    [Use the #link(label("detail-"+target+"-register-summary"))[shared register summary] and
    #link(label("detail-"+target+"-register-description"))[field descriptions] with this instance's base address.]
  }
  subhead(id,"Software",depth)
  if id=="uart1" {
    [The generic UART HAL example configures UART0. UART1 shares the register ABI but has its own base address, dedicated TX/RX, HP PLIC route and no DMA/RTS/CTS binding. Use the HP console integration or a driver explicitly bound to UART1; do not apply UART0 pad configuration to it.]
  } else {
    prose-sections(id+"-software",chapter.software,depth)
  }
  enum(..chapter.software_steps.map(inline))
  if software-note!=none {software-note}
  if chapter.at("api",default:()).len()>0 and id!="uart1" {
    ds-table(id+"-api",[Selected SDK interfaces],([Function],[Declaration]),
      chapter.api.map(a=>(code(a.name),code(a.signature))),widths:(1fr,2.8fr))
  }
  if chapter.example!="" and id!="uart1" {
    block(breakable:false)[
      #minor-title("Minimal SDK call example")
      #code-block(raw(chapter.example,block:true,lang:"c"))
      #set par(leading:rhythm.small-leading,spacing:rhythm.small-spacing)
      #text(9pt,fill:muted)[The example is syntax-checked against the SDK. It assumes clocks, ownership and board initialization are already valid.]
      #source-note(chapter.reference,title:"Detailed interface contract and source provenance")
    ]
  } else {
    source-note(chapter.reference,title:"Detailed interface contract and source provenance")
  }
}
