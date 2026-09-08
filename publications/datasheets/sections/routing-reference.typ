#import "../style.typ": *
#let programming = data.system_reference.programming

== DMA Request, Interrupt and Event Routing <dma-routing>
Request selectors describe pacing or stream endpoints. Channel numbers describe software
contexts, and interrupt numbers describe completion delivery. None can be inferred from another.
Central DMA channel conventions are not independent hardware ownership or privilege domains.

=== Central DMA request map
#ds-table("dma-request-map",[DMA request numbers checked against RTL, SDK and top-level connections],
  ([Request],[Endpoint],[Data transport],[Software channel convention],[Endpoint LP IRQ]),
  programming.dma_routes.map(r=>(str(r.number),r.label,r.transport,r.channel,r.lp_irq)),
  widths:(0.5fr,0.9fr,1.25fr,1.15fr,0.65fr))
The two SDK XPI selectors map to the RTL's historical QSPI names with identical values.
UART selectors connect to UART0, not UART1. I2S, DVP and crypto have dedicated stream ports;
the other paced clients use peripheral data windows through the MM-to-MM path. Software
selector zero has no dedicated peripheral request wire. WS2812 uses that software-paced path.

The endpoint IRQ column identifies the peripheral's own event line where one exists; it is
not the DMA transfer-completion interrupt. Central DMA channel events aggregate at the DMA
resource's LP IRQ or HP PLIC source according to the central resource owner. Crypto has no
separate LP vector entry in this integration; inspect its register status and DMA completion path.

=== Software channel allocation
#ds-table("dma-channel-conventions",[Current SDK and application channel conventions],
  ([Channel],[Client / convention],[Basis]),
  programming.channels.map(r=>(str(r.number),r.label,source(r.sources.last(),title:"Driver / allocation source"))),
  widths:(0.5fr,2.7fr,0.9fr))
The bulk convention is shared and must be serialized by the application. XPI accepts an
explicit channel argument, but selecting another number does not bypass an active stream
endpoint, resource ownership or buffer-lifetime restriction. Crypto uses separate input/output
contexts. The HP boot loader uses its declared boot context; channel 7 remains reserved.

The central DMA start validator currently accepts only its 32-bit width code, even though
the SDK type also names 8- and 16-bit widths. Streams require a full-word length and the
supported source/destination increment mode. Do not infer DRE, narrow stream writes, cyclic
descriptors or 2D operation merely from fields in the descriptor structure.

=== Private DMA masters and owner-directed completion
#ds-table("private-dma-routes",[Central and private-master routes with owner-directed interrupts],
  ([Engine],[Native master / gateway],[LP vector bit],[HP PLIC source]),
  programming.engines.map(r=>(link(label(r.id),r.name),r.master,str(r.lp_irq),str(r.hp_irq))),
  widths:(1.2fr,1.5fr,0.65fr,0.7fr))
These HP source numbers are read from the actual PLIC assignments. The Resource Controller
selects one owner's route and masks routes according to its lifecycle contract; it does not
deliver a completion to both owners. Private DMA engines do not consume a central DMA channel
simply because both move memory. They can still share a gateway or destination bandwidth.
JPEG's slot-6 admission limitation is described in @bus-programming.

=== Completion and event handling
+ Prepare the receiving handler and buffers before enabling the channel, peripheral event and owner route.
+ On interrupt, identify the aggregate source and inspect the channel/IP event fields; a DMA
  completion does not by itself prove that a serial device finished its on-wire operation.
+ Check actual length, error and endpoint status, then acknowledge only the documented sticky causes.
+ Observe each stream's boundary definition. I2S RX has no TLAST, while DVP TLAST marks a line;
  a generic “TLAST means complete frame” rule is incorrect.
+ On timeout, stop submissions and complete abort/drain before releasing the context or changing ownership.

The central DMA receiver requires full byte qualification. Odd-pixel DVP lines create a
partial final stream word and are not supported by its current DMA path. Use the documented
PIO handling or a separately implemented extension; do not discard the partial-word error.
#source-note("rtl/ip/peripheral/dma_pkg.sv",title:"RTL request numbers and transfer kinds")
#source-note("crt/include/retrosoc/hal/dma.h",title:"SDK selectors, contexts and descriptor type")
#source-note("rtl/mini/top/apb4_periph.sv",title:"Request, stream and PLIC wiring")
#source-note("rtl/ip/peripheral/dma_core.sv",title:"Start validation, endpoint exclusion and stream acceptance")

