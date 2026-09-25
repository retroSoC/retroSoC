#import "style.typ": *
#import "diagrams.typ": ip-diagram
#import "waveforms.typ": timing
#let inline(value) = {
  // A deliberately limited inline grammar: explicit strong spans and raw code.
  // Code is opaque, including any literal asterisks it contains.
  let bold = false
  for (i,part) in value.split("`").enumerate() {
    if calc.rem(i,2)==1 { code(part) } else {
      for (j,piece) in part.split("**").enumerate() {
        if j>0 { bold = not bold }
        if bold { strong(piece) } else { piece }
      }
    }
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
      show underline: omit-link-underline
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
    context metadata((kind:"tiny-register",family:family,key:register.key,page:here().page()))
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


#let reference(entry) = {
  pagebreak(weak:true)
  context metadata((kind:"ip-start",id:entry.id,page:here().page()))
  [#heading(level:3,entry.title)#label(entry.id)]
  ip(entry.id)
  minor-title("Features and functional organization")
  list(..entry.features.map(inline))
  ip-diagram(entry)
  minor-title("Functional description and integration boundary")
  for paragraph in entry.paragraphs {par(inline(paragraph))}
  minor-title("Protocol and representative timing")
  [The common AXI/APB rules in @tiny-bus and this instance's access rules both apply.
    *Example waveforms show ordering and stable handshakes, not guaranteed cycle latency or electrical timing.*]
  timing(if entry.family in data.waveforms {entry.family} else {"apb4"},[#entry.title representative transaction.],instance:entry.id)
  if entry.id=="uart1" {
    minor-title("Shared register reference")
    [Use the @uart0 register definition with the UART1 base and IRQ from this chapter.
      *Do not use the UART0 convenience HAL or DMA route as a UART1 binding.*]
  } else {register-section(entry.family,3)}
  minor-title("Software sequence and recovery")
  enum(..entry.steps.map(inline))
  if entry.id!="uart1" {
    let api=data.apis.at(entry.family)
    if api.len()>0 {ds-table("api-"+entry.id,[#entry.title selected SDK interfaces],([Function],[Declaration]),
      api.map(a=>(code(a.name),code(a.signature))),widths:(1fr,3fr))}
    if entry.family in data.examples {
      code-block(raw(data.examples.at(entry.family),block:true,lang:"c"),breakable:true)
      text(9pt,fill:muted)[Syntax-checked API fragment; clocks, pins, memory and arguments must already be valid.
        Submission is not necessarily transfer completion.]
    }
  }
  source-note(data.registers.at(entry.family).document,title:"Register and detailed interface contract")
  context metadata((kind:"ip-end",id:entry.id,page:here().page()))
}
