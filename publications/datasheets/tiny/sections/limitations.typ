#import "../style.typ": *
#import "../diagrams.typ": architecture, clock-tree, overview, flow

= Known Limitations and Revision Compatibility <tiny-known-limitations>
== Implementation and Qualification Limitations
#ds-table("known-limitations",[Implementation and evidence boundaries],([Area],[Current limitation]),(
 ([DMA discovery],[The four-bit maximum-burst field truncates configured 16 to zero; actual engine maximum remains 16 beats.]),
 ([SPI discovery],[CAPABILITY bit 7 reads zero despite the connected Tiny V2.2 DMA path.]),
 ([External memory],[PSRAM requires explicit initialization; clock/reset invalidates its session.]),
 ([Shared routes],[Camera/audio/PWM and selected display/bulk channels require ownership and ordered handoff.]),
 ([Recovery],[Polling timeout does not prove peripheral idle or guarantee completion of a blocked bus read.]),
 ([Entropy / identity],[RNG entropy is unqualified; device-ID reads are unavailable.]),
 ([Qualification],[Negative timing observations, package/board/electrical and final product gates remain open.])),widths:(0.9fr,3.2fr))

== Revision Identification and Compatibility
Read the Tiny SOC_ID, selected capabilities and build/configuration metadata before using product-specific controls.
A source SHA or build flag is not a silicon serial number. Preserve the versioned register contract and reject
unavailable operations rather than inferring them from a library default.

=== Migration from v0.1 <tiny-migration>
The v0.1 draft described a previous IHP130/four-channel integration. Its PDF and manifest keep their original source identity.
This edition changes the main reference to ICS55, while documenting IHP130 compatibility independently.

#heading(level:4,numbering:none,outlined:false,bookmarked:true)[Retired UART1 interface] <uart1>
UART1 at the former 0x10018000 window and its former interrupt are not integrated. Retained shared UART register anchors
describe UART0 only. Legacy dedicated UART ports in the ASIC wrapper are not an additional usable UART. Move console/serial
use to UART0 on GPIO8/9 ALT0 and check the current address and IRQ tables.

#heading(level:4,numbering:none,outlined:false,bookmarked:true)[Retired I2C1 and changed DMA conventions]
The former I2C1 window at 0x10011000 and requests 9/10 are absent. I2C0 uses GPIO10/11. DMA has eight channels and supports
the selected streams; hardcoded four-channel allocation and 4-bit request packing must be replaced with capability-aware
validation. The request high bit in TCD control[25] is required for SPI16/17.

#heading(level:4,numbering:none,outlined:false,bookmarked:true)[Clock, external memory and product scope]
The old single-clock/no-external-RAM descriptions do not apply to this snapshot. Use RCU rate/lifecycle operations and
explicit XPI PSRAM sessions; a clock/reset transition invalidates device timing/session assumptions. PIO-lite remains
unintegrated. PPALite P3 is present; its processed application and final physical qualification are separate open gates.
