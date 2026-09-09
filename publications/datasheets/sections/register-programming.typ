#import "../style.typ": *

== Register Access and Programming Conventions <register-programming>
The following conventions explain how to read the IP register chapters. They do not override
an individual register's access width, strobe, reset or side-effect contract. Use the current
IP version and capability before interpreting a familiar offset from another device or revision.

For an address-first lookup, use @global-register-index. Its instance-qualified formulas
lead back to the same register definitions used in this chapter's access conventions.

=== Access attributes and side effects
#ds-table("register-access-conventions",[Register access attributes and safe software interpretation],
  ([Attribute / behavior],[Meaning],[Programming consequence]),
  (([RO],[Hardware supplies a value; software writes are not part of the interface.],[Do not assume a write is harmless; an IP can reject it.]),
   ([RW],[Software can update documented writable fields.],[Read-modify-write is valid only when reads and writes have no conflicting side effects.]),
   ([WO / command],[A write submits an action or value; reads need not return the last write.],[Use the command encoding and required state; do not read it to construct another command.]),
   ([W1C / RW1C],[Writing one clears the selected documented status bit.],[Write an explicit acknowledgement mask; a read-modify-write can clear unrelated pending events.]),
   ([Set / clear / toggle alias],[A specific IP provides a dedicated operation.],[Use only that IP's documented address/mask; there is no global SoC alias scheme.]),
   ([Read/pop or clear-on-read],[Reading consumes data or changes state.],[Avoid speculative reads, repeated debugger watches and reads used only for display.]),
   ([Live / snapshot],[A live value can change between accesses; a snapshot is captured by a defined operation.],[Use the register's snapshot/latch sequence before combining multiple words.]),
   ([Reserved / unsupported],[The offset or field is not a supported software feature.],[Follow stated reserved-bit rules; reject unsupported modes and preserve defined state.])),
  widths:(0.85fr,1.55fr,1.75fr))

For an event that arrives concurrently with a software acknowledgement, the IP's stated
hardware-set versus software-clear priority applies. No single priority rule is imposed on
all peripherals. Clear only events already captured by the handler and re-check pending state
using the documented sequence before reenabling interrupts.

=== Access width, byte lanes and alignment
Use naturally aligned 32-bit register operations unless the IP explicitly supports another
width. APB4 PSTRB support is per register and per instance. A data window can require all four
byte strobes while adjacent configuration registers accept partial updates. The bus fabric's
supported beat sizes do not imply that a byte store is meaningful for every peripheral.

Offsets in the register tables are byte offsets from the listed base. Bit 0 is the least
significant bit of the displayed register value. Separate numeric bit numbering, bus byte lanes
and protocol payload packing. The boot-bundle serialization has its own little-endian format;
camera byte swaps and audio sample order must follow their IP definitions rather than a
generic byte-copy assumption.

#ds-table("register-access-exceptions",[Examples requiring an IP-specific access sequence],
  ([IP / case],[Exception],[Required handling]),
  (([I2S data windows],[TXDATA/RXDATA are word interfaces; RXDATA can pop data.],[Use full-word accesses and the selected PIO/stream ownership mode.]),
   ([DVP RXDATA],[PIO pop is permitted only when stream output is disabled.],[Do not consume a frame simultaneously through PIO and DMA.]),
   ([DMA active configuration],[Unsupported widths/strobes and writes forbidden while busy can fail.],[Configure idle context first; inspect command/error status rather than assuming a write took effect.]),
   ([GPIO atomic outputs],[Dedicated output operations avoid an ordinary output-register read-modify-write race.],[Use documented GPIO operations; they are not general atomic memory operations.]),
   ([MPW demo IPs],[Legacy examples ignore PSTRB and have a small aliased decode.],[Use aligned full-word operations and the MPW contract; do not generalize to PRODUCT.]),
   ([Dynamic reset values],[Some status/identification fields reflect configuration or live inputs.],[Do not assume every reset value is a fixed zero constant.])),
  widths:(0.9fr,1.5fr,1.75fr))

=== Busy-state writes and read-modify-write
+ Check identity/capability and the current busy/owner state before touching configuration.
+ Build a value from documented fields. Do not preserve arbitrary readback bits from a command,
  FIFO, W1C or mixed-access register.
+ Stop or quiesce the engine when required, then write the supported field/word width.
+ Read a documented status or ordinary configuration register to confirm acceptance. A posted
  write at one layer is not proof that an external device completed the operation.
+ On a bus error or rejected command, retain the cause and recover the previous operation
  before retrying. Blind command replay can duplicate a side effect.

The volatile qualifier controls compiler treatment of an MMIO access; it does not provide
cache coherency, buffer ownership, device completion or an arbitrary inter-core ordering
guarantee. Use the platform's required barriers and the sequences in @memory-coherency.
Neither the LP fabric nor the native crossbar admits locked transactions in the reviewed
predicate; do not infer a global exclusive-access service from CPU ISA names alone.

#block(above:rhythm.metadata-before,below:rhythm.metadata-after,breakable:false)[
  #text(9pt)[Software timeout budgets and API return boundaries: @software-timeouts; @api-completion.]
]


=== RV32 access to multiword registers
For CLINT, the SDK reads high, low and high again, accepting the result only if both high
words match; its retry count is bounded. It writes the compare register by temporarily
setting the low word to all ones, then writing high and the final low word. These are the
actual CLINT helper sequences, not a blanket rule for every 64-bit peripheral value.

Use an IP's latch or snapshot trigger when one exists. A latched counter, FIFO pair, write-only
command pair and live monotonic counter can require different orders. Avoid inventing a high/low
retry loop for a read that pops data. If the interface lacks a safe coherent observation,
describe the result as separate samples rather than claiming an atomic 64-bit read.
#source-note("crt/src/hal/clint.c",title:"Bounded CLINT reads and compare-write order")
#source-note("docs/ip/i2s.md",title:"I2S strobes, data windows and event priority")
#source-note("docs/ip/dvp.md",title:"DVP PIO/stream exclusion and frame semantics")
#source-note("docs/ip/gpio.md",title:"GPIO-specific atomic operations and pad control")
#source-note("rtl/ip/peripheral/dma_reg.sv",title:"DMA register legality and busy-state handling")
