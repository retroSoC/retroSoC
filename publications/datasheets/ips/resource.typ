#import "../style.typ": *

#import "../ip-reference.typ": ip-reference, register-section

#pagebreak(weak:true)

#context metadata((kind:"ip-start",id:"resource",page:here().page()))

==== Resource Controller <resource>

#ip("resource")

#ip-reference("resource","resource",4,legacy:[
Nine resources are managed: central DMA, USB2, SDIO0, SDIO1, SPI-SD, EXT-H, JPEG,
APU, and the P3 GA2D shell with its idle AXI bridge placeholder. Resource 8 routes
the shell IRQ according to its current owner; the shell does not submit GA2D work.
Ownership changes require quiesce, completion of accepted traffic and cache-maintenance
handoff. HP can inspect allowed status but cannot take over root writes. An ownership grant
does not bypass the target access policy or EXT-H address bounds.
])

#heading(level:5,numbering:none,outlined:false,bookmarked:false)[GA2D Phase 3 Register Shell] <ga2d>
#register-section("ga2d",4)

#context metadata((kind:"ip-end",id:"resource",page:here().page()))
