#import "../style.typ": *

#import "../ip-reference.typ": ip-reference

#pagebreak(weak:true)

#context metadata((kind:"ip-start",id:"sdio1",page:here().page()))

==== SDIO Controller (SDIO1) <sdio1>

#ip("sdio1")

#ip-reference("sdio1","sdio",4,shared:"sdio0",legacy:[
The second native SD instance uses dedicated clock, command and four data pads and is routed
through I/O gateway B. Resource ownership controls DMA submission and LP/HP interrupt delivery.
The dedicated pad group is intentionally unbound in the generic FPGA profile until board pin,
I/O-bank voltage and timing constraints are approved.
])

#context metadata((kind:"ip-end",id:"sdio1",page:here().page()))
