#let ink = rgb("#292C31")
#let gold = rgb("#A38442")
#let pale-gold = rgb("#F4EFE4")
#let gray = rgb("#F1F2F3")
#let rule = rgb("#D5D6D8")
#let muted = rgb("#62666C")
#let mono = "FiraCode Nerd Font"
#let data = json(sys.inputs.at("data"))
#let doc = data.document
#let code(value) = text(font: mono, size: 9pt, value.replace("_", "_\u{200b}").replace(".", ".\u{200b}"))
#let source(path, title: "Interface and implementation reference", line:none) = {
  let managed = data.managed_sources.find(s=>path.starts-with(s.destination + "/"))
  let url = if managed == none {
    "https://github.com/retroSoC/retroSoC/blob/" + doc.source_revision + "/" + path
  } else {
    managed.url.trim(".git", at:end) + "/blob/" + managed.revision + "/" + path.slice(managed.destination.len()+1)
  }
  if line!=none { url += "#L"+str(line) }
  link(url, text(size: 9pt, fill: muted, title))
}
#let note(body, title: "Integration note") = block(
  width: 100%, inset: 10pt, fill: pale-gold, stroke: (left: 2pt + gold),
  above: 9pt, below: 9pt, breakable: false,
)[#text(weight: "semibold", title) #linebreak() #body]
#let tbd(body) = note(body, title: "TBD - specification not available")
#let placeholder(title, height: 35mm) = block(
  width: 100%, height: height, stroke: 0.7pt + rule, fill: gray,
  inset: 12pt, above: 8pt, below: 8pt, breakable: false,
)[#align(center + horizon)[#text(weight: "semibold", title) \
  #text(9pt, fill: muted)[TBD - awaiting reviewed engineering data]]]

#let ds-table(key, caption, headers, rows, widths: auto, notes: none) = {
  let anchor = label("start-" + key)
  figure(
    kind: table, supplement: [Table], caption: caption,
    block(breakable: rows.len() > 8, width: 100%)[
      #metadata(none)#anchor
      #set text(size: 9pt)
      #set par(leading: 0.5em)
      #table(
        columns: if widths == auto { headers.len() } else { widths },
        inset: (x: 6pt, y: 5pt),
        stroke: (top:none, bottom:0.35pt + rule, left:none, right:none),
        fill: (x, y) => if y == 1 { gray } else { none },
        align: left + horizon,
        table.header(repeat: true,
          table.cell(colspan: headers.len(), inset: 0pt, stroke: none, fill: white)[
            #context if here().page() > query(anchor).first().location().page() {
              block(above: 5pt, below: 5pt, text(9pt, fill: muted)[#caption (continued)])
            }
          ],
          ..headers.map(h => table.cell(fill: gray, text(weight: "semibold", h))),
        ),
        ..rows.map(row => row.map(v => table.cell(breakable: false, v))).flatten(),
      )
      #if notes != none { block(above: 6pt, breakable: false, text(9pt, fill: muted, notes)) }
    ],
  )
}

#let ip(id) = {
  let entry = data.catalog.find(e => e.id == id)
  let windows = data.regions.filter(r => r.symbol in entry.regions)
  let irqs = data.interrupts.filter(i => i.name in entry.irqs)
  block(above: 5pt, below: 8pt, breakable: false, sticky: true)[
    #entry.summary
    #set text(size: 9pt)
    #set par(leading: 0.5em)
    #table(columns: (1.3fr, 1fr, 0.7fr), inset: (x: 5pt, y: 4pt),
      stroke: (top:none, bottom:0.3pt + rule, left:none, right:none),
      table.header([*Address window*], [*Base address*], [*Size*]),
      ..windows.map(r => (code(r.symbol), code(r.base_hex), r.size_label)).flatten(),
    )
    #block(above: 4pt)[
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
  set par(justify: false, leading: 0.65em, spacing: 0.7em)
  set page(paper: "a4", margin: (x: 19mm, top: 21mm, bottom: 20mm),
    header: context {
      let hs = query(heading.where(level: 1)).filter(h => h.location().page() <= here().page())
      let starts=query(metadata).filter(m=>type(m.value)==dictionary and m.value.at("kind",default:"")=="ip-start" and m.value.page<=here().page())
      let active=none
      if starts.len()>0 {
        let latest=starts.last().value
        let ends=query(metadata).filter(m=>type(m.value)==dictionary and m.value.at("kind",default:"")=="ip-end" and m.value.id==latest.id)
        if ends.len()>0 and here().page()<=ends.first().value.page { active=upper(latest.id) }
      }
      set text(size: 9pt, fill: muted)
      grid(columns: (1fr, 1fr), [retroSoC Mini], align(right)[
        #if active!=none { active } else if hs.len() > 0 { hs.last().body } else { [Product datasheet] }
      ])
      v(4pt)
      line(length: 100%, stroke: 0.6pt + gold)
    },
    footer: context {
      set text(size: 9pt, fill: muted)
      line(length: 100%, stroke: 0.35pt + rule)
      v(4pt)
      grid(columns: (1fr, auto, 1fr),
        [#doc.document_id · v#doc.version · #doc.status],
        [#counter(page).display() / #counter(page).final().first()],
        align(right)[#doc.date],
      )
    },
  )
  set heading(numbering: "1.1.1.1.1", outlined: true)
  show heading: it => {
    let sizes = (21pt, 16pt, 13pt, 11pt, 10.5pt)
    let size = sizes.at(calc.min(it.level - 1, 4))
    block(above: if it.level == 1 { 20pt } else { 12pt }, below: 6pt, sticky: true)[
      #set text(size: size, weight: "semibold")
      #if it.numbering != none {
        text(fill: gold, counter(heading).display(it.numbering))
        h(0.6em)
      }
      #it.body
    ]
  }
  show raw: set text(font: mono, size: 9pt)
  show link: set text(fill: rgb("#65512B"))
  set figure(gap: 7pt)
  show figure.where(kind: table): set figure.caption(position: top)
  show figure.where(kind: table): set block(breakable: true)
  show figure.caption: set text(size: 9pt, fill: muted)
  show figure.caption: set block(sticky: true)
  set outline(indent: 9pt)
  body
}
