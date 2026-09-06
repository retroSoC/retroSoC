#import "../style.typ": *

#import "../ip-reference.typ": ip-reference

#pagebreak(weak:true)

#context metadata((kind:"ip-start",id:"archinfo",page:here().page()))

==== Architecture Information (ARCHINFO) <archinfo>

#ip("archinfo")

#ip-reference("archinfo","archinfo",4,legacy:[
Discovery registers report the generated build/configuration identity, topology, SRAM bytes
and technology capabilities. Device-ID inputs are tied invalid and read-disabled in the
current SoC integration; the document does not claim a provisioned unique silicon identity.
])

#context metadata((kind:"ip-end",id:"archinfo",page:here().page()))
