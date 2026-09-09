#import "../style.typ": *

#import "../ip-reference.typ": ip-reference

#pagebreak(weak:true)

#context metadata((kind:"ip-start",id:"uart1",page:here().page()))

===== Application Console (UART1) <uart1>

#ip("uart1")

#ip-reference("uart1","uart",5,shared:"uart0",legacy:[
UART1 uses the same 64-byte FIFO UART v3 ABI, not a separate non-FIFO implementation. Its
dedicated TX/RX pads serve the HP console. HP PLIC source 1 is distinct from the LP vector
number above. The initial Linux console uses OpenSBI/hvc0; a native Linux UART driver remains
a separate delivery item.
])

#context metadata((kind:"ip-end",id:"uart1",page:here().page()))
