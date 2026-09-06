#import "../style.typ": *

#import "../ip-reference.typ": ip-reference

#pagebreak(weak:true)

#context metadata((kind:"ip-start",id:"sdio0",page:here().page()))

===== SD Card Controller (SDIO0) <sdio0>

#ip("sdio0")

#ip-reference("sdio0","sdio",5,legacy:[
SDIO0 provides native SD command/data transfers and descriptor-driven DMA through I/O gateway A.
Its signals share the GPIO alternate-function matrix. The card, pull-ups, bus voltage and board
timing are external integration requirements. Do not equate protocol support with a qualified
card-speed grade. SDIO1 uses the same controller family with a separate instance and pad group.
])

#context metadata((kind:"ip-end",id:"sdio0",page:here().page()))
