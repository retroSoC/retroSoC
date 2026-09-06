#import "../style.typ": *

#import "../ip-reference.typ": ip-reference

#pagebreak(weak:true)

#context metadata((kind:"ip-start",id:"dvp",page:here().page()))

==== Digital Video Port (DVP) <dvp>

#ip("dvp")

#ip-reference("dvp","dvp",4,legacy:[
The 8-bit parallel input supports RGB565 and YUV422, programmable sync polarity and sampling
edge, snapshot/continuous capture and rectangular cropping. AXI4-Stream marks start-of-frame
and end-of-line; central DMA moves capture data to memory. A maximum sensor resolution or frame
rate requires a validated sensor, clock, buffer and memory-bandwidth configuration.
])

#context metadata((kind:"ip-end",id:"dvp",page:here().page()))
