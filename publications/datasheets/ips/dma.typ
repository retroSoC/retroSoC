#import "../style.typ": *

#import "../ip-reference.typ": ip-reference
#import "../diagram-packages.typ": dma-tcd-diagram

#pagebreak(weak:true)

#context metadata((kind:"ip-start",id:"dma",page:here().page()))

=== Direct Memory Access (DMA) <dma>

#ip("dma")

#ip-reference("dma","dma",3,functional-note:[
  #block(breakable:false)[
    #figure(dma-tcd-diagram(),kind:image,supplement:[Figure],caption:[Central DMA TCD memory layout and field ownership.])<dma-tcd-layout>
    #source-note("crt/include/retrosoc/hal/dma.h",title:"Handwritten 64-byte TCD layout")
    #source-note("crt/src/hal/dma.c",title:"Current HAL descriptor result writeback")
  ]
],software-note:[
  #change-start("v05-commercial-20261114-dma-recovery","Current shared-DMA abort and reset helpers")
  #code("rs_dma_session_abort_wait(session, timeout)") first requests abort, then polls channel busy.
  A zero budget still submits abort and returns timeout without a confirming poll. The budget counts
  register polls, not elapsed microseconds; timeout does not establish drain. A bus error propagates.
  #code("rs_dma_session_reset(session)") submits the session-owned reset command; its return does not
  add a completion wait. Release the channel only after the documented idle/ownership checks.
  #source-note("crt/src/hal/dma.c",title:"Current session abort-wait/reset implementation")
  #change-end("v05-commercial-20261114-dma-recovery")


  #block(above:rhythm.metadata-before,below:rhythm.metadata-after,breakable:false)[
    #text(9pt)[Command submission, wait exhaustion and confirmed abort/drain: @api-completion.]
  ]

],legacy:[
==== Architecture
Eight channel contexts share one AXI32 master. The production integration uses 32-bit words,
up to sixteen beats per burst and thirty-two words of buffering. Direct mode supports memory
copies, fixed MMIO and selected AXI4-Stream endpoints. Linked-list mode fetches 64-byte,
64-byte-aligned transfer-control descriptors. Arbitrary nonzero memory-copy byte counts are
supported with aligned addresses and a partial final write beat.

Narrow transfer widths, unaligned realignment, cyclic descriptors, 2D stride and hardware
cache coherency are not implemented. Firmware must perform ownership and cache maintenance
before handing shared buffers to DMA.

==== Hardware Trigger Channels
UART0 uses channel 0; I2C0 and I2C1 use channels 1 and 2. I2S and DVP use bulk channel 3.
Channels 0-5 retain defined endpoint ownership, channel 6 is reserved for HP boot and channel
7 is reserved. Crypto streaming and other endpoint details remain defined by the DMA contract;
drivers must not silently share a context.

The optional software session API acquires an idle channel, clears inherited TCD state and
retains a caller-owned session object. Unleased commands are rejected while that lease exists.
After successful terminal completion or confirmed abort/drain, release the same session object.
This single-hart guard supplements the hardware owner and cache rules; it is not inter-hart
mutual exclusion. With CSR support disabled, it does not provide interrupt masking either.
])

#context metadata((kind:"ip-end",id:"dma",page:here().page()))
