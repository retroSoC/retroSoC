#import "../style.typ": *
#import "../diagrams.typ": diagram
#import "../r1-roadmap.typ": r1-roadmap
#import "../r1-specifications.typ": r1-specification-plate

#pagebreak(weak: true)
#{
  show heading: h => text(size: 12pt, weight: "semibold")[#text(fill: gold, counter(heading).display(h.numbering)) #h.body]
  grid(columns: (1fr, auto), [
    = Appendix: Product Direction
  ], [
    == Product Series <tiny-product-series>
  ])
}
#change-start("tiny-v02-r1-specifications-20261127-specification-plates", "Four R1 family specification comparisons")
#for (i, topic) in data.r1_specs.topics.enumerate() {
  if i > 0 { pagebreak() }
  v(1fr)
  show figure: set block(above: 0pt, below: 0pt, breakable: false)
  show figure.caption: it => none
  figure(kind: table, supplement: [Table], caption: [R1 Family · #topic.title], [
    #metadata(none)#label(if i == 0 {"start-series"} else {"start-series-" + topic.key})
    #change-start("tiny-v02-piolite-r1-badges-20261128-spec-" + topic.key, topic.title + " chip badges")
    #r1-specification-plate(data.r1_specs, topic.key, book: true)
    #change-end("tiny-v02-piolite-r1-badges-20261128-spec-" + topic.key)
  ])
}
#change-end("tiny-v02-r1-specifications-20261127-specification-plates")

== Roadmap <tiny-r1-roadmap>
PIOLITE P3 integrates GPIO ownership, DMA, RCU and the TINY HAL. Application and protocol qualification (P4) and the combined physical campaign (P5) remain open.
PPALite integrates the camera source, DMA, RCU and SDK. The dated P4 acceptance covers the scoped capture, SD readback, preview and recovery cases on both TINY reference profiles. The joint P5 physical and timing campaign remains open.
Reserved addresses/selectors, host tools and shared SDK names do not instantiate hardware.
Release dates, derivative features, package/process choices and commercial availability are not commitments in this draft.
#source-note("docs/ip/piolite-verification.md",title:"PIOLITE P3 integration evidence and open phases")
#source-note("docs/ip/ppalite-verification.md",title:"Dated PPALite application evidence and qualification boundary")
#source-note("docs/ip/tiny-soc.md",title:"Phased TINY extensions and final campaign")

#change-start("tiny-v02-r1-roadmap-20261126-family-roadmap", "Six-tier R1 development and planning roadmap", category: "added")
#{
  show figure: set block(above: 6pt, below: 0pt, breakable: false)
  change-start("tiny-v02-piolite-r1-badges-20261128-roadmap", "R1 roadmap chip badges")
  diagram("r1-roadmap", r1-roadmap(data.r1_roadmap), [R1 Roadmap.], figure-label: "tiny-r1-roadmap-figure")
  change-end("tiny-v02-piolite-r1-badges-20261128-roadmap")
}
#change-end("tiny-v02-r1-roadmap-20261126-family-roadmap")
