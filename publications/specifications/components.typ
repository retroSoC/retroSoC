// Shared publication-only components. Hardware/style context is passed by each book.
#let palette=(ink:rgb("#292C31"),gold:rgb("#A38442"),gray:rgb("#F1F2F3"))
#let state-label(s)=("confirmed":"Confirmed design","calculated":"Calculated","reference":"REFERENCE ONLY","tbd":"TBD").at(s)
#let number(v)=if v==none {[TBD]} else if type(v)==float {str(calc.round(v,digits:4))} else {str(v)}
#let use-record(r, body)=context {
  metadata((kind:"specification-use",id:r.id,status:r.status,page:here().page()))
  body
}
#let datum(r)=use-record(r,if type(r.value)==dictionary {
  [Min #number(r.value.min) / Typ #number(r.value.typ) / Max #number(r.value.max)]
} else {number(r.value)})
#let quantity(r)={
  let v=r.value
  let u=r.unit
  if u=="Hz" and v>=1000000 {v/=1000000;u="MHz"}
  if u=="B" and v>=1024 and calc.rem(v,1024)==0 {v/=1024;u="KiB"}
  use-record(r,[#number(v)#if u!="1" {[ #u]}])
}
#let reference-notice(body)=block(width:100%,inset:10pt,above:12pt,below:12pt,
  stroke:(left:2pt+palette.gold),fill:rgb("#F4EFE4"),breakable:false)[
  #text(10.5pt,weight:"semibold")[REFERENCE ONLY - unverified example]
  #linebreak()#body
]
#let parameters(spec, group, render)={
  let records=spec.records.filter(r=>r.group==group)
  for status in ("confirmed","calculated","reference","tbd") {
    let selected=records.filter(r=>r.status==status)
    if selected.len()==0 {continue}
    let title=spec.groups.find(g=>g.id==group)
    let title=if title==none {group} else {title.title}
    if group=="mechanical" {
      render("spec-mechanical-reference",[QFN64 reference dimensions - REFERENCE ONLY],
        ([Dimension - REFERENCE ONLY],[Nominal / bound],[Tolerance / qualifier]),
        selected.map(r=>(use-record(r,r.meaning),[#number(r.value) mm],r.at("tolerance",default:"See source drawing"))),
        widths:(1.7fr,0.8fr,1.5fr),
        notes:[REFERENCE ONLY. ADI UP64 05-08-1705 Rev C p1; all dimensions in millimeters. BSC is a basic dimension. Tiny outline, bonding, pad metallurgy and supplier approval remain pending.])
      continue
    }
    let rows=selected.map(r=>{
      let scaled=r.unit=="Hz" and type(r.value) in (int,float)
      let unit=if scaled {"MHz"} else {r.unit}
      let range=if type(r.value)==dictionary {r.value} else {(min:none,typ:if scaled {r.value/1000000} else {r.value},max:none)}
      let value=if type(r.value)==str and r.value.len()>70 {
        [See model / assumption record below]
      } else {number(range.typ)}
      (use-record(r,[#r.meaning #linebreak()#text(9pt,fill:rgb("#62666C"))[#r.conditions]]),
       number(range.min),value,number(range.max),unit)
    })
    render("spec-"+group+"-"+status,[#title - #state-label(status)],
      ([Parameter / conditions - #state-label(status)],[Min],[Typ / value],[Max],[Unit]),rows,
      widths:(2.9fr,0.45fr,0.9fr,0.45fr,0.5fr),
      notes:[#state-label(status). A blank bound is shown as TBD. Evidence and replacement requirements are retained under the same parameter IDs in the accompanying audit.])
  }
}
#let quick-reference(spec, render)={
  render("specification-legend",[Specification status and evidence guide],
    ([Status],[Meaning and use]),(
      ([Confirmed design],[Current source/configuration or approved product target. The evidence scope distinguishes a target from RTL, simulation or a physical result.]),
      ([Calculated],[An explicit formula using confirmed inputs. No measurement or operating qualification is implied.]),
      ([REFERENCE ONLY],[External or constructed illustration. Not a released electrical, PCB, manufacturing or selection specification.]),
      ([TBD],[Unavailable product evidence. Explicit null; never zero or a permissive limit.])),widths:(1fr,3fr))
  render("specification-quick",[Selected product facts and applicability],
    ([Parameter],[Value],[Scope]),spec.records.filter(r=>r.group=="quick").map(r=>(
      r.meaning,quantity(r),r.conditions)),widths:(1.1fr,0.8fr,2.1fr))
  [Clock values identify digital configurations or encoded design points. Check the implementation limitations and physical evidence before selecting an operating point.
  The complete register reference follows the package, connection and electrical information.]
}
#let pin-table(spec, render)={
  render("functional-pins",[External functions, GPIO ownership and reset logic],
    ([External function / GPIO],[Mode / direction],[Reset logic / bias],[Restrictions / status]),
    spec.pins.map(p=>([#p.function #linebreak()GPIO#p.gpio], [#p.mode / #p.direction],
      [#p.reset #linebreak()#p.pull],[#p.restriction #linebreak()#p.state])),
    widths:(1.25fr,0.55fr,1fr,1.2fr),
    notes:[ALT function directions are derived from producer/consumer routes. GPIO reset input/OE-disabled state is digital behavior; pad thresholds, pull strength and physical bonding remain separate. Raw RTL identifiers remain in the canonical alternate-function matrix and specification-data.json.])
}
#let curve(spec, id)={
  let d=spec.datasets.find(d=>d.id==id)
  block(width:100%,breakable:false)[
    #context metadata((kind:"specification-figure",id:id,category:"curve",status:d.status,page:here().page()))
    #for pid in d.points.map(p=>p.record_ids).flatten().dedup() {
      let r=spec.records.find(r=>r.id==pid)
      use-record(r,[])
    }
    #figure(image(d.paths.svg,width:172mm),caption:[#d.title - #state-label(d.status).])
  ]
}
#let characteristics(spec, render)={
  reference-notice[The following model curves illustrate documentation and planning methods. They are not measured silicon data, guaranteed limits or evidence that the scanned voltage, temperature or frequency is safe for this product.]
  heading(level:3,[Digital clock points and ideal throughput])
  if spec.product=="tiny" {
    [SAFE24 is the current boot mode. PLL192/PLL240 are conditional R2-P7 profiles. SAFE24 boots with the PLL off; the RTL can request a qualified source through drain, safe parking and commit. Backend capability and digital lock do not establish physical timing or an approved speed grade.]
  } else {
    [The main profile uses the independent 24 MHz reference and 72 MHz external performance input. REF24 and LP performance-divider alternatives are separate configurations; they are not simultaneous operating points or a shared LP/HP synchronous-clock claim. HP has its own root and CDC boundary.]
  }
  parameters(spec,"clocks",render)
  [The ideal bandwidth boundary is the active SYS AXI32 fabric in Tiny and the independent HP AXI64 fabric in Mini.
  MEM/backend clocks are separate; width times a backend clock does not specify SRAM or external-memory throughput.]
  curve(spec,"cpu-relative")
  heading(level:3,[Peripheral wire rates and application payloads])
  render("wire-rates",[Ideal SDR wire payload - Calculated; no pad-rate qualification],
    ([Interface / configuration],[Wire clock],[Useful payload]),
    spec.peripheral.map(p=>([#p.interface #linebreak()#p.config],
      [#number(p.clock_hz/1000000) MHz],
      use-record(spec.records.find(r=>r.id==p.record_id),[#number(p.payload_bps/1000000) MB/s]))),
    widths:(2fr,1fr,1fr),
    notes:[Decimal MB/s. SDIO uses four data lanes; I2S is one stereo direction. #if spec.product=="tiny" {[SPI0 uses one data lane.]} Command, CRC, gaps, buffering, memory access and software are excluded. I2S uses the actual audio reference, so a preset name alone does not promise an exact 48/96 ksample/s.])
  if spec.product=="tiny" {[SPI0 SCK = PCLK/(2d), d=1..65535. ]}
  [SDIO SCK = PCLK/(2 max(1,h)), h=0..65535 in the clock generator; use h>=1 for consistent discovery. I2S BCLK = AUDIO/(2(SCLK_DIV+1)); sample rate = BCLK/(2(LRCK_DIV+1)); both programmable fields are 8 bits. Framing and configured slot/sample width must agree.]
  if spec.product=="mini" {
    [Mini SDIO CLOCK_ACTUAL uses the instance's fixed 72 MHz discovery input while the wire clock is generated from live PCLK. Recompute from the actual PCLK when it differs; the discovery value is not a clock measurement. Tiny SPI0 is absent from Mini.]
  }
  parameters(spec,"resources",render)
  parameters(spec,"software",render)
  [Compare the payload rows with this product's SRAM before choosing buffering. A resource example is not evidence that an entire application fits or that external memory is initialized. ELF/MAP footprint remains TBD until an exact-source/profile artifact is supplied.]
  heading(level:3,[Current, voltage and temperature examples])
  curve(spec,"current-frequency")
  curve(spec,"current-modes")
  curve(spec,"current-voltage")
  curve(spec,"current-temperature")
  [WFI and idle peripheral gates are digital activity scenarios. These curves do not imply deep sleep, voltage scaling, independent power islands, analog bias behavior or retained state. Currents cover the constructed core domain only.]
  heading(level:3,[Memory and GPIO model examples])
  curve(spec,"transfer")
  render("transfer-model-values",[Effective transfer model - REFERENCE ONLY],
    ([Payload],[Model time],[Effective payload rate]),
    spec.datasets.find(d=>d.id=="transfer").points.map(p=>(
      [#number(p.x) B],[#number(p.seconds*1000000) us],[#number(p.y) MB/s])),
    widths:(1fr,1fr,2fr),notes:[Tref=16/fbus+L/(0.6 Bideal). Setup and efficiency are constructed model coefficients.])
  curve(spec,"gpio-load")
  parameters(spec,"performance",render)
  heading(level:3,[Model assumptions and replacement conditions])
  for r in spec.records.filter(r=>r.group in ("models","board","assembly")) {
    block(width:100%,above:12pt,below:12pt,breakable:false)[
      #text(9pt,weight:"semibold")[#r.meaning - #state-label(r.status)] #linebreak()
      #use-record(r,text(9pt,if r.value==none {"TBD"} else {r.at("display_value",default:str(r.value))}))
      #linebreak()#text(9pt)[#r.conditions #r.replacement]
    ]
  }
  heading(level:3,[Source and data traceability])
  render("commercial-sources",[Commercial organization references and model provenance],
    ([Source],[Version / locator],[Adopted practice]),
    spec.sources.filter(s=>s.kind=="external").map(s=>(
      link(s.url,s.title),[#s.version #linebreak()#s.locator],
      [Section/table organization and engineering presentation; no donor measurement is a product specification.])),
    widths:(1.3fr,1.3fr,1.4fr))
  [The manifest binds parameter catalogs, source fingerprints, model coefficients, plot CSV/SVG/PDF files, fonts and tool versions. The usage and replacement indexes retain stable IDs, rendered pages, dependencies, assumptions and the evidence needed for promotion. Only reviewed, product-specific evidence can replace an example.]
}
