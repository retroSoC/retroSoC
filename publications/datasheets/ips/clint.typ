#import "../style.typ": *
#change-start("v05-c906-20261022-ips-clint","LP timebase and core-internal HP timer boundary")

#import "../ip-reference.typ": ip-reference

#pagebreak(weak:true)

#context metadata((kind:"ip-start",id:"clint",page:here().page()))

==== Management Local Interrupts (CLINT) <clint>

#ip("clint")

#ip-reference("clint","clint",4,legacy:[
CLINT supplies machine software and timer interrupts for the management hart. The committed
*timebase is 1 MHz*. It is *separate from the HP local-interrupt window* and from the PLIC external
interrupt controller.
])

#context metadata((kind:"ip-end",id:"clint",page:here().page()))

#change-end("v05-c906-20261022-ips-clint")
