#import "../style.typ": *
#import "../ip-reference.typ": reference

== Peripherals <tiny-peripherals>
Every current IP appears once. The hierarchy follows the Mini publication; address, clock, routing and capability facts are Tiny-specific.

=== Memory Interface
==== Non-Volatile Memory (NVM)
#context metadata((kind:"ip-start",id:"xpi",page:here().page()))
===== XPI Universal Controller <xpi>
#reference(data.catalog.find(e=>e.id=="xpi"))
#context metadata((kind:"ip-end",id:"xpi",page:here().page()))

#pagebreak(weak:true)
#context metadata((kind:"ip-start",id:"sdio",page:here().page()))
===== Native SD/SDIO Host (SDIO0) <sdio>
#reference(data.catalog.find(e=>e.id=="sdio"))
#context metadata((kind:"ip-end",id:"sdio",page:here().page()))

#pagebreak(weak:true)
==== Volatile Memory (VM)
External RAM uses the existing @xpi controller and explicit NSS1 PSRAM initialization; it is not a second memory-controller IP. Main SRAM follows below.
#context metadata((kind:"ip-start",id:"sram",page:here().page()))
===== On-Chip SRAM <sram>
#reference(data.catalog.find(e=>e.id=="sram"))
#context metadata((kind:"ip-end",id:"sram",page:here().page()))

#pagebreak(weak:true)
#context metadata((kind:"ip-start",id:"gpio",page:here().page()))
=== General-Purpose Input/Output (GPIO) <gpio>
#reference(data.catalog.find(e=>e.id=="gpio"))
#context metadata((kind:"ip-end",id:"gpio",page:here().page()))

#pagebreak(weak:true)
#context metadata((kind:"ip-start",id:"dma",page:here().page()))
=== Direct Memory Access (DMA) <dma>
#reference(data.catalog.find(e=>e.id=="dma"))
#context metadata((kind:"ip-end",id:"dma",page:here().page()))

#pagebreak(weak:true)
=== Timers
#context metadata((kind:"ip-start",id:"timer",page:here().page()))
==== General-Purpose Timers (TIM0, TIM1) <timer>
#reference(data.catalog.find(e=>e.id=="timer"))
#context metadata((kind:"ip-end",id:"timer",page:here().page()))

#pagebreak(weak:true)
#context metadata((kind:"ip-start",id:"rtc",page:here().page()))
==== Real-Time Clock (RTC) <rtc>
#reference(data.catalog.find(e=>e.id=="rtc"))
#context metadata((kind:"ip-end",id:"rtc",page:here().page()))

#pagebreak(weak:true)
#context metadata((kind:"ip-start",id:"wdg",page:here().page()))
==== Watchdog (WDG) <wdg>
#reference(data.catalog.find(e=>e.id=="wdg"))
#context metadata((kind:"ip-end",id:"wdg",page:here().page()))

#pagebreak(weak:true)
#context metadata((kind:"ip-start",id:"pwm",page:here().page()))
==== Pulse Width Modulation (PWM) <pwm>
#reference(data.catalog.find(e=>e.id=="pwm"))
#context metadata((kind:"ip-end",id:"pwm",page:here().page()))

#pagebreak(weak:true)
=== IO Interface
==== Universal Asynchronous Receiver/Transmitter (UART)
#context metadata((kind:"ip-start",id:"uart0",page:here().page()))
===== Management UART (UART0) <uart0>
#reference(data.catalog.find(e=>e.id=="uart0"))
#context metadata((kind:"ip-end",id:"uart0",page:here().page()))

#pagebreak(weak:true)
#context metadata((kind:"ip-start",id:"i2c",page:here().page()))
==== Inter-Integrated Circuit (I2C0) <i2c>
#reference(data.catalog.find(e=>e.id=="i2c"))
#context metadata((kind:"ip-end",id:"i2c",page:here().page()))

#pagebreak(weak:true)
#context metadata((kind:"ip-start",id:"spi",page:here().page()))
==== Serial Peripheral Interface (SPI0) <spi>
#reference(data.catalog.find(e=>e.id=="spi"))
#context metadata((kind:"ip-end",id:"spi",page:here().page()))

#pagebreak(weak:true)
#context metadata((kind:"ip-start",id:"ws2812",page:here().page()))
==== WS2812 LED Output <ws2812>
#reference(data.catalog.find(e=>e.id=="ws2812"))
#context metadata((kind:"ip-end",id:"ws2812",page:here().page()))

#pagebreak(weak:true)
#context metadata((kind:"ip-start",id:"archinfo",page:here().page()))
==== Architecture Information (ARCHINFO) <archinfo>
#reference(data.catalog.find(e=>e.id=="archinfo"))
#context metadata((kind:"ip-end",id:"archinfo",page:here().page()))

#pagebreak(weak:true)
#context metadata((kind:"ip-start",id:"sysctrl",page:here().page()))
==== System Controller (SYSCTRL) <sysctrl>
#reference(data.catalog.find(e=>e.id=="sysctrl"))
#context metadata((kind:"ip-end",id:"sysctrl",page:here().page()))

#pagebreak(weak:true)
#context metadata((kind:"ip-start",id:"rcu",page:here().page()))
==== Reset and Clock Unit (RCU) <rcu>
#reference(data.catalog.find(e=>e.id=="rcu"))
#context metadata((kind:"ip-end",id:"rcu",page:here().page()))

#pagebreak(weak:true)
#context metadata((kind:"ip-start",id:"clint",page:here().page()))
==== Local Interrupt Controller (CLINT) <clint>
#reference(data.catalog.find(e=>e.id=="clint"))
#context metadata((kind:"ip-end",id:"clint",page:here().page()))

#pagebreak(weak:true)
=== Multimedia
==== Data Formats and Peripheral Interoperability <tiny-media-formats>
DVP, I2S and SPI transport words do not share a universal pixel/sample format. Interpret word packing,
valid bytes, frame dimensions and completion before handing data to another peripheral.
#ds-table("media-interoperability",[Payload and transport boundaries],([Producer],[Transport],[Consumer requirement]),(
 ([DVP RGB565],[Two 16-bit pixels per 32-bit word],[Preserve sensor byte order, dimensions and final drain.]),
 ([PPALite PROCESS],[GRAY8 or RGB565; each row padded to four bytes],[Use valid width and stride; RESULT_VALID follows final source/DMA checks.]),
 ([I2S16 / I2S24],[Two 16-bit samples per word / one 24-bit sample per word],[Keep channel order and storage width distinct from valid sample bits.]),
 ([SPI display],[8/16-bit frames packed into 32-bit transport words],[Panel command/pixel ordering and clean D/C/held-CS boundaries.])),widths:(0.9fr,1.5fr,1.8fr))

#context metadata((kind:"ip-start",id:"i2s",page:here().page()))
==== Inter-IC Sound (I2S) <i2s>
#reference(data.catalog.find(e=>e.id=="i2s"))
#context metadata((kind:"ip-end",id:"i2s",page:here().page()))

#pagebreak(weak:true)
#context metadata((kind:"ip-start",id:"dvp",page:here().page()))
==== Digital Video Port (DVP) <dvp>
#reference(data.catalog.find(e=>e.id=="dvp"))
#context metadata((kind:"ip-end",id:"dvp",page:here().page()))

#pagebreak(weak:true)
#context metadata((kind:"ip-start",id:"ppalite",page:here().page()))
==== Streaming Pixel Processor (PPALITE) <ppalite>
#reference(data.catalog.find(e=>e.id=="ppalite"))
#context metadata((kind:"ip-end",id:"ppalite",page:here().page()))

#pagebreak(weak:true)
=== Encryption and Data Integrity
#context metadata((kind:"ip-start",id:"crypto",page:here().page()))
==== Cryptographic Accelerator (CRYPTO) <crypto>
#reference(data.catalog.find(e=>e.id=="crypto"))
#context metadata((kind:"ip-end",id:"crypto",page:here().page()))

#pagebreak(weak:true)
#context metadata((kind:"ip-start",id:"crc",page:here().page()))
==== Cyclic Redundancy Check (CRC) <crc>
#reference(data.catalog.find(e=>e.id=="crc"))
#context metadata((kind:"ip-end",id:"crc",page:here().page()))

#pagebreak(weak:true)
#context metadata((kind:"ip-start",id:"rng",page:here().page()))
==== Random Number Generator (RNG) <rng>
#reference(data.catalog.find(e=>e.id=="rng"))
#context metadata((kind:"ip-end",id:"rng",page:here().page()))
