#import "../style.typ": *

#import "../ip-reference.typ": ip-reference

#pagebreak(weak:true)

#context metadata((kind:"ip-start",id:"dvp",page:here().page()))

==== Digital Video Port (DVP) <dvp>

#ip("dvp")

#ip-reference("dvp","dvp",4,software-note:[
  #change-start("v05-commercial-20261114-dvp-recovery","Current shared-DVP bounded start and stop helpers")
  #code("rs_dvp_start_with_timeout(timeout)") uses the bounded startup/rearm path.
  #code("rs_dvp_stop(timeout)") disables capture, then waits for enable clear, inactive
  state and FIFO empty. It returns an I/O error for remaining hardware errors or a timeout
  when the poll budget expires; neither timeout nor command submission confirms drain.
  The optional PPALite raw-route guard is conditional on the generated product feature;
  Mini does not acquire Tiny's processed route through this shared HAL update.
  #source-note("crt/src/hal/dvp.c",title:"Current bounded DVP lifecycle helpers")
  #change-end("v05-commercial-20261114-dvp-recovery")
],legacy:[
The *8-bit parallel input* supports RGB565 and YUV422, programmable sync polarity and sampling
edge, snapshot/continuous capture and rectangular cropping. AXI4-Stream marks start-of-frame
and end-of-line; central DMA moves capture data to memory. A maximum sensor resolution or frame
rate requires a *validated sensor, clock, buffer and memory-bandwidth configuration*.
])

#context metadata((kind:"ip-end",id:"dvp",page:here().page()))
