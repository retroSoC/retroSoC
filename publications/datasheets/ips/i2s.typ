#import "../style.typ": *

#import "../ip-reference.typ": ip-reference

#pagebreak(weak:true)

=== Multimedia <multimedia-overview>

#include "../sections/media-formats.typ"

#pagebreak(weak:true)

#context metadata((kind:"ip-start",id:"i2s",page:here().page()))

==== Inter-Integrated Circuit Sound (I2S) <i2s>

#ip("i2s")

#ip-reference("i2s","i2s",4,legacy:[
The stereo master supports 16/24-bit and 48/96 kHz presets plus programmable clock dividers.
TX/RX streams use 32-bit words and 128-word FIFOs. Configuration and sample CDC handle the
independent audio clock. Slave, TDM and PDM modes are not advertised. A codec/DAC/ADC and
board-level audio-clock qualification are external requirements.
The wrapper exports the synchronized RX warm-flush state as #code("rx_flush_busy_o") to
the APU integration. The internal KWS receive route and its flush/lifecycle coordination are
implemented, but default PRODUCT leaves #code("EnableP7=0") and the public KWS capability
clear. Flush completion is distinct from FIFO empty and from codec/KWS job completion.
This integration change introduces no new pad, sample format or external audio mode.
#source-note("rtl/ip/serial/apb4_i2s.sv",title:"I2S RX flush status export")
#source-note("rtl/mini/top/apb4_periph.sv",title:"APU receive-route and flush integration")
])

==== Extended Peripheral Interface (XPI)
The multimedia serial-peripheral use refers to the same controller documented in @xpi; it is not a second XPI instance.


#context metadata((kind:"ip-end",id:"i2s",page:here().page()))
