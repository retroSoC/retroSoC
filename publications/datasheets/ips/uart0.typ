#import "../style.typ": *

#import "../ip-reference.typ": ip-reference
#import "../diagram-packages.typ": uart-fifo-diagram

#pagebreak(weak:true)

=== IO Interface

==== Universal Asynchronous Receiver/Transmitter (UART)

#context metadata((kind:"ip-start",id:"uart0",page:here().page()))

===== Management Console (UART0) <uart0>

#ip("uart0")

#ip-reference("uart0","uart",5,functional-note:[
  #block(breakable:false)[
    #figure(uart-fifo-diagram(),kind:image,supplement:[Figure],caption:[UART0 FIFO depth and receive-entry storage.])<uart-fifo-layout>
    #source-note("rtl/ip/serial/uart_reg.sv",title:"Actual TX/RX FIFO geometry and register access")
  ]
],software-note:[

  #block(above:rhythm.metadata-before,below:rhythm.metadata-after,breakable:false)[
    #text(9pt)[FIFO wait budgets and partial transfers: @software-timeouts; @api-completion.]
  ]

],legacy:[
UART0 supports configurable framing, fractional baud generation, watermark and receive-timeout
interrupts, receive diagnostics, break, loopback and automatic active-low RTS/CTS. TX/RX have
dedicated pads; GPIO0/1 ALT0 carry CTS/RTS. DMA pacing is connected only for UART0.
])

#context metadata((kind:"ip-end",id:"uart0",page:here().page()))
