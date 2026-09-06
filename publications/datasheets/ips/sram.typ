#import "../style.typ": *

#import "../ip-reference.typ": ip-reference

#pagebreak(weak:true)

==== Volatile Memory (VM)

#context metadata((kind:"ip-start",id:"sram",page:here().page()))

===== On-Chip Memory (OCM / SRAM) <sram>

#ip("sram")

#ip-reference("sram","sram",5,legacy:[
The reference profile selects eight 4 KiB banks for 32 KiB total. The configuration accepts
4, 16, 32, 64 or 128 KiB; only 32 KiB is selected by the committed product profiles.
SRAM has a native AXI64/ID6 data interface in the HP domain and an APB4 configuration window.
Technology macros and behavioral models are selected by the configuration. A larger configurable
capacity is not a statement of qualified area, timing or yield.
])

#context metadata((kind:"ip-end",id:"sram",page:here().page()))
