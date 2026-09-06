#import "../style.typ": *

#import "../ip-reference.typ": ip-reference

#pagebreak(weak:true)

=== Multimedia

#context metadata((kind:"ip-start",id:"i2s",page:here().page()))

==== Inter-Integrated Circuit Sound (I2S) <i2s>

#ip("i2s")

#ip-reference("i2s","i2s",4,legacy:[
The stereo master supports 16/24-bit and 48/96 kHz presets plus programmable clock dividers.
TX/RX streams use 32-bit words and 128-word FIFOs. Configuration and sample CDC handle the
independent audio clock. Slave, TDM and PDM modes are not advertised. A codec/DAC/ADC and
board-level audio-clock qualification are external requirements.
])

==== Extended Peripheral Interface (XPI)
The multimedia serial-peripheral use refers to the same controller documented in @xpi; it is not a second XPI instance.


#context metadata((kind:"ip-end",id:"i2s",page:here().page()))
