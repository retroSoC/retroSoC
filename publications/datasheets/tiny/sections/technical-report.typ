#import "../style.typ": *
#import "../diagrams.typ": architecture, clock-tree, overview, flow

= Technical Report
== Release Verification Summary <tiny-evidence>
Readiness is *prototype*. #data.evidence.boundary
#ds-table("evidence",[Dated repository verification record and publication boundary],([Area],[What the record reports],[Interpretation]),
  data.evidence.records.map(r=>(r.at(0),r.at(1),r.at(2))),widths:(0.8fr,1.7fr,1.65fr))
No newly executed current-commit hardware report is created by this publication. The historical negative timing entries
remain attributed to their original profiles and source revisions; a successful STA command does not imply positive slack.
R2-P8/P9/P10 and SPI-P4 human acceptance are retained as dated ledger decisions, independently of generated
#code("phase_accepted=false") records. Final combined product timing/physical closure remains open.
#source-note("docs/ip/spi-verification.md",title:"SPI phase evidence and human acceptance")

Publication tests establish document/source consistency and layout, not electrical compliance, full protocol coverage or
silicon operation. Future pass records must identify exact source/profile, tool/model versions, executed stage, raw report
and result. Keep skipped, failed and unfinished work visible.
#source-note("docs/ip/tiny-soc-verification.md",title:"Historical evidence, timing deficit and remaining work")

== Shuttle and Qualification Evidence
No die photograph, package image, tapeout status or silicon measurement is inferred from a source build.
A qualification package must tie the device/lot/revision and physical implementation to its profile, netlist,
PDK/corners, constraints, board and instruments. Missing reports remain missing; see the electrical section.

== Performance and Power Characterization
Separate instruction throughput, memory bandwidth, DMA transport, peripheral wire rate and complete-workload time.
Record useful payload, startup/drain costs, alignment, burst limits, clock profile and contention. A calculated
buffer size or divider rate is not a measurement. Power requires supply conditions and a defined workload.
Retain the dated R2-P10 workload records with their own source/backend identity; do not extrapolate them into
continuous camera FPS, arbitrary-panel performance or a qualified PLL operating rating.
#source-note("docs/ip/tiny-soc-verification.md",title:"Scoped performance, timing and backend observations")
