#import "../style.typ": *

#import "../ip-reference.typ": ip-reference, register-section

#pagebreak(weak:true)

#context metadata((kind:"ip-start",id:"resource",page:here().page()))

==== Resource Controller <resource>

#ip("resource")

#ip-reference("resource","resource",4,legacy:[
Nine resources are managed: central DMA, USB2, SDIO0, SDIO1, SPI-SD, EXT-H, JPEG,
APU, and the P5 GA2D direct single-job private-AXI64 2D engine. Resource 8 routes
its IRQ according to its current owner and controls its private AXI64 lifecycle.
GA2D supports FILL, COPY, bit-exact CONVERT, opaque alpha BLEND, A8 fixed-color
foreground masks, and exact equal background/destination in-place composition.
RGB565, RGB888, XRGB8888, and ARGB8888 are color surfaces; A8 is BLEND
foreground-only. Snapshots, pitch, and byte edges remain available. It does not
provide transparent-background/premultiplied-alpha modes, scaling, rendering,
descriptor/ring/queue submission, hardware cache coherency, or a Linux graphics driver.
Ownership changes require quiesce, completion of accepted traffic and cache-maintenance
handoff. HP can inspect allowed status but cannot take over root writes. An ownership grant
does not bypass the target access policy or EXT-H address bounds.
])

#heading(level:5,numbering:none,outlined:false,bookmarked:false)[GA2D Phase 5 Direct 2D Composition] <ga2d>
#register-section("ga2d",4)

#context metadata((kind:"ip-end",id:"resource",page:here().page()))
