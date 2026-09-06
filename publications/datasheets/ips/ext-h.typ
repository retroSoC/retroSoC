#import "../style.typ": *

#import "../ip-reference.typ": ip-reference

#pagebreak(weak:true)

#context metadata((kind:"ip-start",id:"ext-h",page:here().page()))

==== High-Bandwidth Extension (EXT-H) <ext-h>

#ip("ext-h")

#ip-reference("ext-h","extensions",4,legacy:[
EXT-H adds a native AXI64 data master with read/write address bounds, ownership and timeout
handling. Its current capability declaration has no stream interface or local SRAM. It is a
fixed product slot, not the legacy runtime IPSEL multiplexer.
])

#context metadata((kind:"ip-end",id:"ext-h",page:here().page()))
