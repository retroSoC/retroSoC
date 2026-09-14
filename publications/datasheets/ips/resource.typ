#import "../style.typ": *

#import "../ip-reference.typ": ip-reference, register-section

#pagebreak(weak:true)

#context metadata((kind:"ip-start",id:"resource",page:here().page()))

==== Resource Controller <resource>

#ip("resource")

#ip-reference("resource","resource",4,legacy:[
Nine resources are managed: central DMA, USB2, SDIO0, SDIO1, SPI-SD, EXT-H, JPEG,
APU, and the P4 GA2D direct single-job FILL/COPY DMA engine. Resource 8 routes
its IRQ according to its current owner and controls its private AXI64 lifecycle.
GA2D supports RGB565, RGB888, XRGB8888, and ARGB8888 with snapshots, pitch, and
byte edges. It does not provide CONVERT, BLEND, A8, in-place background composition,
descriptor/ring/queue submission, hardware cache coherency, or a Linux graphics driver.
Ownership changes require quiesce, completion of accepted traffic and cache-maintenance
handoff. HP can inspect allowed status but cannot take over root writes. An ownership grant
does not bypass the target access policy or EXT-H address bounds.
])

#heading(level:5,numbering:none,outlined:false,bookmarked:false)[GA2D Phase 4 Direct FILL/COPY DMA] <ga2d>
#register-section("ga2d",4)

#context metadata((kind:"ip-end",id:"resource",page:here().page()))
