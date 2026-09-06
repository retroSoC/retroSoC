#import "../style.typ": *

#import "../ip-reference.typ": ip-reference

#pagebreak(weak:true)

==== HP Interrupt and Mailbox Platform <hp-platform>

#context metadata((kind:"ip-start",id:"hp-aclint",page:here().page()))

===== HP Local Interrupt Controller (ACLINT) <hp-aclint>

#let r=data.regions.find(r=>r.symbol=="HP_ACLINT")
Base address: #code(r.base_hex). Window size: #r.size_label. HP software and timer interrupts; hart slot 1 is connected.


#ip-reference("hp-aclint","aclint",5,legacy:[

The HP ACLINT supplies local software and timer interrupts to VexiiRiscv. The PLIC
handles external interrupt sources, including the separate mailbox doorbell. These
controllers have distinct address windows and interrupt semantics.
])

#context metadata((kind:"ip-end",id:"hp-aclint",page:here().page()))
