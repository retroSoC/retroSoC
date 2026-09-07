#let ink = rgb("#292C31")
#let gold = rgb("#A38442")
#let pale-gold = rgb("#F4EFE4")
#let gray = rgb("#F1F2F3")
#let rule = rgb("#D5D6D8")
#let muted = rgb("#62666C")
#let link-color = rgb("#245A81")
#let inline-code-color = rgb("#B12146")
#let table-stroke = 0.6pt + black
#let mono = "FiraCode Nerd Font"
#let data = json(sys.inputs.at("data"))
#let doc = data.document
#let ip-chapters = json("chapter-index.json")
// RM0486-inspired spacing, adapted to the retained Inter sizes. Inter's
// cap-height-to-baseline box is 7.639 pt at 10.5 pt and 6.548 pt at 9 pt.
// Thus these leading values yield 12.6 / 10.8 pt baseline pitches, rather
// than treating Typst's `leading` as the whole distance between baselines.
#let rhythm = (
  body-leading: 4.96pt, body-spacing: 11.26pt,
  small-leading: 4.25pt, small-spacing: 8.25pt,
  heading-before: (28pt,24pt,18pt,12pt,10pt),
  heading-after: (18pt,10pt,8pt,6pt,5pt),
  heading-gap: 8pt, minor-before: 12pt, minor-after: 6pt,
  register-before: 12pt, register-after: 4pt,
  list-spacing: 7.96pt, list-indent: 0pt, list-body-indent: 8pt,
  figure-space: 12pt, figure-caption: 6pt, table-caption: 4pt,
  table-inset: (x:6pt,y:5pt), table-notes: 6pt,
  continuation-size: 8.5pt, continuation-gap: 2pt,
  code-space: 8pt, code-inset: 8pt,
  note-space: 12pt, note-inset: 10pt,
  metadata-before: 4pt, metadata-after: 6pt,
  bits-space: 6pt, bits-inset: (x:3pt,y:5pt),
  toc-leading: 9.09pt, toc-indent: 14pt, toc-group-before: 12pt, toc-group-after: 4pt,
  header-gap: 4pt,
  cover-leading: 4.96pt, cover-spacing: 3.675pt, cover-list-spacing: 7.96pt,
  cover-heading-before: (20pt,12pt), cover-heading-after: 6pt,
  cover-gap: 9pt, cover-meta-gap: 10pt, cover-rule-gap: 8pt,
  cover-gutter: 7mm, cover-list-indent: 0.5em,
  diagram-leading: 0.4em, inventory-leading: 0.35em,
)

#let heading-layout(it, before: none, after: none) = {
  if it.outlined and it.numbering != none and it.level <= 2 {
    context {
      let preceding = query(selector(heading).before(it.location(),inclusive:false)).filter(h=>h.outlined and h.numbering!=none)
      let chapters = preceding.filter(h=>h.level==1)
      let product-brief = if it.level==1 {it.body==[Product Brief]}
        else {chapters.len()>0 and chapters.last().body==[Product Brief]}
      // Chapter openers and their first section form one heading group.
      // Subsequent sections break independently, even when their text is short.
      let chapter-opener = it.level==2 and preceding.len()>0 and preceding.last().level==1
      if not product-brief and not chapter-opener {pagebreak(weak:true)}
    }
  }
  let index = calc.min(it.level - 1,4)
  let sizes = (21pt,16pt,13pt,11pt,10.5pt)
  block(above: if before == none {rhythm.heading-before.at(index)} else {before},
    below: if after == none {rhythm.heading-after.at(index)} else {after}, sticky:true)[
    #set text(size:sizes.at(index),weight:"semibold")
    #set par(leading:rhythm.body-leading,spacing:0pt)
    #if it.numbering == none { it.body } else {
      grid(columns:(auto,1fr),column-gutter:rhythm.heading-gap,
        text(fill:gold,counter(heading).display(it.numbering)),it.body)
    }
  ]
}

#let minor-title(body) = block(above:rhythm.minor-before,below:rhythm.minor-after,sticky:true,strong(body))
#let code-block(body, breakable:false) = block(above:rhythm.code-space,below:rhythm.code-space,
  width:100%,inset:rhythm.code-inset,fill:gray,breakable:breakable)[
  #set par(leading:rhythm.small-leading,spacing:rhythm.small-spacing)
  #body
]
#let cover(body) = {
  show heading: it => heading-layout(it,
    before:rhythm.cover-heading-before.at(calc.min(it.level - 1,1)),
    after:rhythm.cover-heading-after)
  body
}

#let contents(depth:5) = {
  set text(size:9.5pt,fill:ink)
  show link: set text(fill:ink)
  show underline: it => it.body
  set par(leading:rhythm.toc-leading,spacing:rhythm.toc-leading)
  set outline(indent:rhythm.toc-indent)
  show outline.entry: it => context {
    let peers = query(heading).filter(h=>h.outlined and h.level==it.level and h.numbering!=none)
    let widths = peers.map(h=>measure(numbering(h.numbering,..counter(heading).at(h.location()))).width)
    let prefix-width = calc.max(0pt,..widths)
    let prefix = it.prefix()
    // Scope emphasis by the section ancestor, not by a hard-coded chapter number.
    let ancestors = query(selector(heading).before(it.element.location(),inclusive:true)).filter(h=>h.level<=2)
    let peripheral = ancestors.len()>0 and ancestors.last().body==[Peripherals]
    let inner = if peripheral {
      // Keep parentheses, separators and qualifiers such as "partial" regular.
      show regex("\\([^()]*\\)"): group => {
        show regex("\\b[A-Z][A-Z0-9]*(?:-[A-Z0-9]+)*\\b"): strong
        group
      }
      it.inner()
    } else {it.inner()}
    block(above:rhythm.toc-leading + if it.level==1 {rhythm.toc-group-before} else {0pt},
      below:rhythm.toc-leading + if it.level==1 {rhythm.toc-group-after} else {0pt},breakable:false)[
      #link(it.element.location(),it.indented(
        if prefix==none {none} else {box(width:prefix-width,prefix)},inner,gap:rhythm.heading-gap))
    ]
  }
  outline(title:[Contents],depth:depth)
}
#let inline-code(body) = context {
  // Link scopes already select link-color; keep that semantic cue and underline.
  set text(fill:if text.fill==link-color {link-color} else {inline-code-color})
  body
}
#let code(value) = inline-code(text(font: mono, size: 9pt,
  value.replace("_", "_\u{200b}").replace(".", ".\u{200b}")))
#let source(path, title: "Interface and implementation reference", line:none) = {
  let managed = data.managed_sources.find(s=>path.starts-with(s.destination + "/"))
  let url = if managed == none {
    "https://github.com/retroSoC/retroSoC/blob/" + doc.source_revision + "/" + path
  } else {
    managed.url.trim(".git", at:end) + "/blob/" + managed.revision + "/" + path.slice(managed.destination.len()+1)
  }
  if line!=none { url += "#L"+str(line) }
  link(url, text(size: 9pt, title))
}
#let source-note(path, title:"Interface and implementation reference", line:none) = block(
  above:rhythm.metadata-before,below:rhythm.metadata-after,breakable:false)[
  #set par(leading:rhythm.small-leading,spacing:rhythm.small-spacing)
  #source(path,title:title,line:line)
]
#let note(body, title: "Integration note", below: rhythm.note-space) = block(
  width: 100%, inset: rhythm.note-inset, fill: pale-gold, stroke: (left: 2pt + gold),
  above: rhythm.note-space, below: below, breakable: false,
)[#text(weight: "semibold", title) #linebreak() #body]
#let tbd(body) = note(body, title: "TBD - specification not available")
#let placeholder(title, height: 35mm) = block(
  width: 100%, height: height, stroke: 0.7pt + rule, fill: gray,
  inset: rhythm.note-inset, above: rhythm.note-space, below: rhythm.note-space, breakable: false,
)[#align(center + horizon)[#text(weight: "semibold", title) \
  #text(9pt, fill: muted)[TBD - awaiting reviewed engineering data]]]

// Frame each row at its outer edges without adding internal vertical rules.
// Repeated header rows supply the top edge on every continued table segment.
#let table-rules(columns, header-row:0) = (x,y) => (
  top: if y==header-row {table-stroke} else {none},
  bottom: table-stroke,
  left: if x==0 {table-stroke} else {none},
  right: if x==columns - 1 {table-stroke} else {none},
)

#let continuation-notice() = layout(size => {
  let body = block(width:100%,above:0pt,below:0pt)[
    #set text(size:rhythm.continuation-size,weight:"regular",fill:black,
      top-edge:"ascender",bottom-edge:"descender")
    #set par(leading:4pt,spacing:0pt)
    (continued)
  ]
  let extent = measure(body,width:size.width)
  block(width:100%,above:rhythm.table-caption,below:0pt,
    inset:(bottom:rhythm.continuation-gap))[
    #block(width:extent.width,height:extent.height,above:0pt,below:0pt,body)<table-continuation-region>
  ]
})

#let ds-table(key, caption, headers, rows, widths: auto, notes: none) = {
  let anchor = label("start-" + key)
  figure(
    kind: table, supplement: [Table], caption: caption,
    block(breakable: rows.len() > 8, width: 100%)[
      #metadata(none)#anchor
      #set text(size: 9pt)
      #set par(leading: rhythm.small-leading, spacing: rhythm.small-spacing)
      #table(
        columns: if widths == auto { headers.len() } else { widths },
        inset: rhythm.table-inset,
        stroke: table-rules(headers.len(),header-row:1),
        fill: (x, y) => if y == 1 { gray } else { none },
        align: left + horizon,
        table.header(repeat: true,
          table.cell(colspan: headers.len(), inset: 0pt,
            stroke:(top:none,bottom:table-stroke,left:none,right:none),fill: white)[
            #context if here().page() > query(anchor).first().location().page() {
              continuation-notice()
            }
          ],
          ..headers.map(h => table.cell(fill: gray, text(weight: "semibold", h))),
        ),
        ..rows.map(row => row.map(v => table.cell(breakable: false, v))).flatten(),
      )
      #if notes != none { block(above: rhythm.table-notes, breakable: false, text(9pt, fill: muted, notes)) }
    ],
  )
}

#let ip(id) = {
  let entry = data.catalog.find(e => e.id == id)
  let windows = data.regions.filter(r => r.symbol in entry.regions)
  let irqs = data.interrupts.filter(i => i.name in entry.irqs)
  block(above: rhythm.metadata-before, below: rhythm.metadata-after, breakable: false, sticky: true)[
    #entry.summary
    #set text(size: 9pt)
    #set par(leading: rhythm.small-leading, spacing: rhythm.small-spacing)
    #table(columns: (1.3fr, 1fr, 0.7fr), inset: rhythm.table-inset,
      stroke: table-rules(3),
      table.header(..([Address window],[Base address],[Size]).map(h=>
        table.cell(fill:gray,text(weight:"semibold",h)))),
      ..windows.map(r => (code(r.symbol), code(r.base_hex), r.size_label)).flatten(),
    )
    #block(above: rhythm.metadata-before)[
      *LP IRQ:* #if irqs.len() == 0 { [No dedicated source.] } else {
        irqs.map(i => str(i.core_bit) + " (" + i.name.replace("_", " ") + ")").join("; ")
      }
    ]
    #for (n, p) in entry.sources.enumerate() {
      source(p, title: if n == 0 { "Detailed contract / source" } else { "Additional source" })
      if n < entry.sources.len() - 1 { [ · ] }
    }
  ]
}

#let template(body) = {
  set document(title: doc.title, author: doc.author,
    keywords: ("retroSoC", "Mini", "Gen2", "Gen2+", "datasheet", "DRAFT"))
  set text(font: "Inter", size: 10.5pt, fill: ink, lang: "en", weight: "regular")
  set par(justify: false, leading: rhythm.body-leading, spacing: rhythm.body-spacing,first-line-indent:0pt)
  set list(indent:rhythm.list-indent,body-indent:rhythm.list-body-indent,spacing:rhythm.list-spacing)
  set enum(indent:rhythm.list-indent,body-indent:rhythm.list-body-indent,spacing:rhythm.list-spacing)
  set page(paper: "a4", margin: (x: 19mm, top: 21mm, bottom: 20mm),
    header: context {
      let hs = query(heading.where(level: 1)).filter(h => h.location().page() <= here().page())
      // Heading locations avoid the extra layout pass needed by page-valued metadata.
      // A later chapter/section heading closes the preceding IP's header scope.
      let navigation=query(selector(heading.where(level:1)).or(heading.where(level:2),
        ..ip-chapters.map(chapter=>label(chapter.id))))
        .filter(h=>h.location().page()<=here().page())
      let active=if navigation.len()==0 {none} else {
        ip-chapters.find(chapter=>label(chapter.id)==navigation.last().fields().at("label",default:none))
      }
      set text(size: 9pt, fill: muted)
      grid(columns: (1fr, 1fr), doc.title, align(right)[
        #if active!=none { upper(active.id) } else if hs.len() > 0 { hs.last().body } else { [Product datasheet] }
      ])
      v(rhythm.header-gap)
      line(length: 100%, stroke: 0.6pt + gold)
    },
    footer: context {
      set text(size: 9pt, fill: muted)
      line(length: 100%, stroke: 0.35pt + rule)
      v(rhythm.header-gap)
      grid(columns: (1fr, auto, 1fr),
        [#doc.document_id · v#doc.version · #doc.status],
        [#counter(page).display() / #counter(page).final().first()],
        align(right)[#doc.date],
      )
    },
  )
  set heading(numbering: "1.1.1.1.1", outlined: true)
  show heading: heading-layout
  show raw: set text(font: mono, size: 9pt)
  show raw.where(block:false): inline-code
  show link: set text(fill:link-color)
  show link: it => underline(stroke:0.4pt + link-color,offset:2pt,it)
  set figure(gap: rhythm.figure-caption)
  show figure: set block(above:rhythm.figure-space,below:rhythm.figure-space,breakable:false)
  set figure.caption(position:top)
  show figure.where(kind: table): set figure(gap:rhythm.table-caption)
  show figure.where(kind: table): set block(breakable: true)
  show figure.caption: set text(size: 9pt, fill: black)
  show figure.caption: it => block(above:0pt,below:0pt,sticky:it.position==top,it)
  body
  context {
    let regions=query(<table-continuation-region>).map(region=>{
      let pos=region.location().position()
      (kind:"table-continuation",page:pos.page,x:pos.x.pt(),y:pos.y.pt(),
        width:region.width.length.pt(),height:region.height.length.pt())
    })
    [#metadata((kind:"layout-regions",regions:regions))<layout-report>]
  }
}
