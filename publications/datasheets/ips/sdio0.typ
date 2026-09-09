#import "../style.typ": *

#import "../ip-reference.typ": ip-reference
#import "../diagram-packages.typ": sdio-command-diagram

#pagebreak(weak:true)

#context metadata((kind:"ip-start",id:"sdio0",page:here().page()))

===== SD Card Controller (SDIO0) <sdio0>

#ip("sdio0")

#ip-reference("sdio0","sdio",5,protocol-note:[
  #block(breakable:false)[
    #figure(sdio-command-diagram(),kind:image,supplement:[Figure],caption:[Native SD command field order, shared by SDIO0 and SDIO1.])<sdio-command-layout>
    #source-note("rtl/ip/storage/sdio_command.sv",title:"Command assembly and most-significant-bit-first transmission")
  ]
],legacy:[
SDIO0 provides native SD command/data transfers and descriptor-driven DMA through I/O gateway A.
Its signals share the GPIO alternate-function matrix. The card, pull-ups, bus voltage and board
timing are external integration requirements. Do not equate protocol support with a qualified
card-speed grade. SDIO1 uses the same controller family with a separate instance and pad group.
])

#context metadata((kind:"ip-end",id:"sdio0",page:here().page()))
