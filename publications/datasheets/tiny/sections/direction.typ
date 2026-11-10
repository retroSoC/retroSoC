#import "../style.typ": *
#import "../diagrams.typ": architecture, clock-tree, overview, flow

= Appendix: Product Direction
== Product Series
#ds-table("series",[Product positioning and publication scope],([Series],[Role],[Status here]),(
 ([Tiny],[Independent single-core wired MCU],[Only this reviewed Tiny snapshot is specified.]),
 ([Mini],[Management and application processing],[Separate implementation and publication.]),
 ([Std / Pro],[Future family directions],[Roadmap context; no implemented-product claim.])),widths:(0.6fr,1.5fr,2fr))
#source-note("docs/soc-family-positioning.md",title:"Family positioning and scope")

== Roadmap
PIO-lite has standalone P2 RTL and host ISA/model/assembler tools; Tiny routing, DMA and HAL integration remain pending.
PPALite P3 source/DMA/RCU/SDK integration is present. Its P4 camera/memory/display application campaign and joint P5 physical/timing campaign remain open.
Reserved addresses/selectors, host tools and shared SDK names do not instantiate hardware.
Release dates, derivative features, package/process choices and commercial availability are not commitments in this draft.
#source-note("docs/ip/piolite-verification.md",title:"PIO-lite host evidence and open phases")
#source-note("docs/ip/tiny-soc.md",title:"Phased Tiny extensions and final campaign")
