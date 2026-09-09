#import "../style.typ": *

#import "../ip-reference.typ": ip-reference

#pagebreak(weak:true)

#context metadata((kind:"ip-start",id:"ws2812",page:here().page()))

==== WS2812 LED Interface <ws2812>

#ip("ws2812")

#ip-reference("ws2812","ws2812",4,legacy:[
GPIO2 ALT1 carries the single transmit output. Words are sent GRB, most-significant bit first.
Symbol high/low durations and reset-low time are programmable. This is not a Dallas/Maxim
1-Wire controller and must not be used as a substitute for that protocol.
])

#context metadata((kind:"ip-end",id:"ws2812",page:here().page()))
