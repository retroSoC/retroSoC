#import "../style.typ": *

#import "../ip-reference.typ": ip-reference

#pagebreak(weak:true)

#context metadata((kind:"ip-start",id:"spisd",page:here().page()))

===== SPI SD Card Controller (SPISD) <spisd>

#ip("spisd")

#ip-reference("spisd","spisd",5,legacy:[
The host controls SD cards in SPI mode and moves payloads through a private AXI4 master, routed
through I/O gateway B. Resource ownership determines which hart receives its interrupt.
The former 1 GiB memory-mapped card aperture is reserved; software must use command/data
operations. Card initialization, capacity discovery and supported transfer details belong to
the SPI-SD contract, rather than fixed card-size claims in the feature list.
])

#context metadata((kind:"ip-end",id:"spisd",page:here().page()))
