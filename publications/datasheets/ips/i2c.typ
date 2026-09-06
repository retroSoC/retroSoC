#import "../style.typ": *

#import "../ip-reference.typ": ip-reference

#pagebreak(weak:true)

#context metadata((kind:"ip-start",id:"i2c",page:here().page()))

==== Inter-Integrated Circuit (I2C) <i2c>

#ip("i2c")

#ip-reference("i2c","i2c",4,legacy:[
Each instance has sixteen-entry command and receive FIFOs, 7/10-bit addresses, repeated START,
clock stretching, arbitration-loss detection, filtering, bounded waits and bus recovery.
GPIO7/8 ALT0 route I2C0; GPIO3/4 ALT1 route I2C1. External pull-ups and a validated board timing
budget are required. The current IP is controller-mode, not an I2C target/slave peripheral.
])

#context metadata((kind:"ip-end",id:"i2c",page:here().page()))
