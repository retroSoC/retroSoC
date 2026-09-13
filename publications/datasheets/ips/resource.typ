#import "../style.typ": *

#import "../ip-reference.typ": ip-reference

#pagebreak(weak:true)

#context metadata((kind:"ip-start",id:"resource",page:here().page()))

==== Resource Controller <resource>

#ip("resource")

#ip-reference("resource","resource",4,legacy:[
Nine resources are managed: central DMA, USB2, SDIO0, SDIO1, SPI-SD, EXT-H, JPEG,
APU, and the idle GA2D bridge placeholder. Resource 8 has no routed IRQ in Phase 2.
Ownership changes require quiesce, completion of accepted traffic and cache-maintenance
handoff. HP can inspect allowed status but cannot take over root writes. An ownership grant
does not bypass the target access policy or EXT-H address bounds.
])

#context metadata((kind:"ip-end",id:"resource",page:here().page()))
