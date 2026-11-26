#import "../style.typ": *
#import "../diagrams.typ": diagram
#import "../r1-roadmap.typ": r1-roadmap

= Appendix: Product Direction
== Product Series
#ds-table("series",[Product positioning and publication scope],([Series],[Role],[Status here]),(
 ([TINY],[Independent single-core wired MCU],[Only this reviewed TINY snapshot is specified.]),
 ([Mini],[Management and application processing],[Separate implementation and publication.]),
 ([Std / Pro],[Future family directions],[Roadmap context; no implemented-product claim.])),widths:(0.6fr,1.5fr,2fr))
#source-note("docs/soc-family-positioning.md",title:"Family positioning and scope")

== Roadmap <tiny-r1-roadmap>
PIO-lite has standalone P2 RTL and host ISA/model/assembler tools; TINY routing, DMA and HAL integration remain pending.
PPALite integrates the camera source, DMA, RCU and SDK. The dated P4 acceptance covers the scoped capture, SD readback, preview and recovery cases on both TINY reference profiles. The joint P5 physical and timing campaign remains open.
Reserved addresses/selectors, host tools and shared SDK names do not instantiate hardware.
Release dates, derivative features, package/process choices and commercial availability are not commitments in this draft.
#source-note("docs/ip/piolite-verification.md",title:"PIO-lite host evidence and open phases")
#source-note("docs/ip/ppalite-verification.md",title:"Dated PPALite application evidence and qualification boundary")
#source-note("docs/ip/tiny-soc.md",title:"Phased TINY extensions and final campaign")

#change-start(doc.change_prefix + "family-roadmap", "Six-tier R1 development and planning roadmap", category: "added")
#{
  show figure: set block(above: 6pt, below: 0pt, breakable: false)
  diagram("r1-roadmap", r1-roadmap(data.r1_roadmap), [R1 Roadmap.], figure-label: "tiny-r1-roadmap-figure")
}
#change-end(doc.change_prefix + "family-roadmap")
