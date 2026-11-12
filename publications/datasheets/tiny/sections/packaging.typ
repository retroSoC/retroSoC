#import "../style.typ": *
#import "../diagrams.typ": architecture, clock-tree, overview, flow
#import "../waveforms.typ": timing

== Packaging <tiny-pins>
The approved target is QFN64: 48 signal terminals and 16 perimeter power/ground terminals. The table below records the
frozen target allocation; it is not an implemented bond map, approved package drawing or electrical specification.
=== Pin Mapping
#ds-table("qfn64",[Approved QFN64 target perimeter; physical binding pending],([Pin],[Target name],[Pin],[Target name]),
  data.package.map(r=>(str(r.at(0)),code(r.at(1)),str(r.at(2)),code(r.at(3)))),widths:(0.35fr,1.65fr,0.35fr,1.65fr))
The current ASIC compatibility wrapper still retains legacy dedicated UART/XPI-CS ports and its older power-pad inventory.
Its executable map below is kept separate from the 64-terminal target. Do not route a PCB from the wrapper inventory or
infer voltage ratings from a target terminal name. GPIO8/9 carry the active UART0; legacy dedicated UART outputs are inactive.
#source-note("docs/ip/tiny-soc.md",title:"Approved package target and allocation")
#ds-table("pads",[Tiny logical signal pads],([Signal],[RTL direction],[Pad kind]),
  data.pads.map(p=>(code(p.name),p.direction,p.kind.replace("_"," "))),widths:(2fr,0.8fr,1.2fr))
The executable wrapper inventory contains #data.pads.len() logical signal pads and
#data.power_pads.values().sum() power/ground pad cells. These counts describe the current wrapper,
not QFN64 perimeter pins or an approved die-to-package bond map.
=== GPIO Alternate-Function Matrix
#let gpio-mode(mode) = {
  let terms=mode.inputs + if mode.do.contains("'") {()} else {(mode.do,)}
  if terms.len()==0 {[Not routed]} else {code(terms.join(" / "))}
}
#ds-table("gpio-alternates",[Tiny GPIO alternate-function routes],([GPIO],[ALT0],[ALT1]),
  data.gpio.map(g=>(str(g.pin),gpio-mode(g.alt0),gpio-mode(g.alt1))),widths:(0.4fr,1.85fr,1.85fr))
Disable producers and release output enables before changing a live pad route. I2C and open-drain signals require external
pull-ups and compatible levels. The dedicated boot-XPI interface remains separate; additional chip selects and active UART use their declared GPIO routes. Verify complete
pin groups, reset drive state and external clock availability before enabling a device.



=== Package Dimensions, Reflow and Reliability
QFN64 is an approved target allocation. No completed die-to-package bond map, mechanical outline,
reflow profile, thermal characterization or orderable part number is established by this source snapshot.
The executable wrapper remains distinct from that target. Board wiring needs the approved physical binding
and electrical constraints; neither can be derived from a logical terminal name.

== Electrical and Timing Specifications
This source-level publication supplies *no numerical production electrical ratings*. TBD means unavailable evidence,
not zero, unlimited range or permission to select a convenient value. Functional clock names are not independent power rails.
#ds-table("physical-gaps",[Evidence required before physical product claims],([Area],[Required evidence],[Current state]),(
  ([Supply / absolute maximum],[Pad/core rails, sequencing, injection/ESD limits, approved conditions],[TBD]),
  ([AC/DC timing],[PVT, loading, clock reference edge, setup/hold and input/output limits],[TBD]),
  ([Package / pinout],[QFN64 target allocation recorded; actual die/pad bonding and outline pending],[Not qualified]),
  ([Thermal / power],[Package/board/test conditions, workloads, voltage and measured results],[TBD]),
  ([Reliability / ordering],[Qualification records, traceable device revisions and order codes],[TBD])),widths:(1fr,2.5fr,0.5fr))
No package photograph, fabricated part number, regulatory mark or silicon speed grade is inferred from the digital profile.
The documented STA deficit remains visible in @tiny-evidence; it is not an operating specification.