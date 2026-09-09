#import "../style.typ": *

#import "../ip-reference.typ": ip-reference

#pagebreak(weak:true)

#context metadata((kind:"ip-start",id:"hp-mailbox",page:here().page()))

===== LP/HP Mailbox <hp-mailbox>

#let r=data.regions.find(r=>r.symbol=="APB4_HP_MAILBOX")
Base address: #code(r.base_hex). Window size: #r.size_label. LP IRQ25 and HP PLIC source 2.


#ip-reference("hp-mailbox","mailbox",5,legacy:[

])

#context metadata((kind:"ip-end",id:"hp-mailbox",page:here().page()))
