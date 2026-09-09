#import "../style.typ": *

#import "../ip-reference.typ": ip-reference

#pagebreak(weak:true)

#context metadata((kind:"ip-start",id:"usb2",page:here().page()))

==== USB 2.0 Dual-Role Controller <usb2>

#ip("usb2")

#ip-reference("usb2","usb2",4,legacy:[
The digital controller uses an external 8-bit ULPI PHY, descriptor-driven AXI DMA and APB4
control. Its dedicated thirteen-pad interface includes ULPI clock, DATA[7:0], DIR, NXT, STP
and PHY reset. These pads do not enter the GPIO mux. The primary external PHY target is USB3320.
#note[The custom controller is not an EHCI register-compatible block. Host/device software,
protocol coverage, USB compliance and board/PHY timing have their own release gates.
An integrated digital controller does not establish USB-IF certification.]
])

#context metadata((kind:"ip-end",id:"usb2",page:here().page()))
