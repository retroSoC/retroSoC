#import "../style.typ": *

#import "../ip-reference.typ": ip-reference

#pagebreak(weak:true)

#context metadata((kind:"ip-start",id:"hp-plic",page:here().page()))

===== HP Platform-Level Interrupt Controller (PLIC) <hp-plic>

#let r=data.regions.find(r=>r.symbol=="HP_PLIC")
Base address: #code(r.base_hex). Window size: #r.size_label. HP machine and supervisor external interrupts.


#ip-reference("hp-plic","plic",5,legacy:[

])

#context metadata((kind:"ip-end",id:"hp-plic",page:here().page()))
