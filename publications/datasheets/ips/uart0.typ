#import "../style.typ": *

#import "../ip-reference.typ": ip-reference

#pagebreak(weak:true)

=== IO Interface

==== Universal Asynchronous Receiver/Transmitter (UART)

#context metadata((kind:"ip-start",id:"uart0",page:here().page()))

===== Management Console (UART0) <uart0>

#ip("uart0")

#ip-reference("uart0","uart",5,legacy:[
UART0 supports configurable framing, fractional baud generation, watermark and receive-timeout
interrupts, receive diagnostics, break, loopback and automatic active-low RTS/CTS. TX/RX have
dedicated pads; GPIO0/1 ALT0 carry CTS/RTS. DMA pacing is connected only for UART0.
])

#context metadata((kind:"ip-end",id:"uart0",page:here().page()))
