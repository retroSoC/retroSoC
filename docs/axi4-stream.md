# AXI4-Stream Peripheral Data Paths

The Mini SoC uses 32-bit AXI4-Stream links for high-rate peripheral data that
does not need an address on every word. APB4 remains the register configuration
plane. The active stream endpoints are DMA to I2S TX, I2S RX to DMA, and DVP RX
to DMA. UART, I2C, and WS2812 retain their existing APB4 FIFO data registers.

## Interface Contract

All three links use `DATA_WIDTH=32`, one-bit ID, destination, and user fields,
and the system clock/reset. `TKEEP` and `TSTRB` are `4'hF`; the current I2S and
DVP data paths always transfer complete words. DMA holds `TDATA`, `TKEEP`,
`TSTRB`, and `TLAST` stable while `TVALID` is high and `TREADY` is low. A word
is consumed only on a `TVALID && TREADY` clock edge.

DMA asserts `TLAST` on the final programmed I2S TX word. I2S RX and DVP do not
currently provide a packet boundary to DMA, so DMA terminates their transfers
using its programmed `XFERLEN`; incoming `TLAST` is informational and ignored.
IDs, destinations, and user sidebands are currently zero.

## Configuration and PIO Fallback

I2S register offset `0x00C` is `STREAM_CTRL`: bit 0 selects AXI4-Stream as the
TX FIFO producer and bit 1 selects AXI4-Stream as the RX FIFO consumer. A clear
bit preserves the existing `TXDATA` or `RXDATA` PIO behavior. Software must not
change a stream-select bit while that direction is active. `TXDATA` is `0x01C`
and `RXDATA` is `0x020`.

DVP register offset `0x0C` is `STREAM_CTRL`: bit 0 selects AXI4-Stream as the
RX FIFO consumer. When clear, reads of `RXDATA` retain the existing pop
behavior. When set, `RXDATA` reads do not pop the FIFO.

DMA modes 1 and 2 use the I2S TX and RX stream links. Mode 11 uses DVP RX. The
source address is unused for stream RX modes, and the destination address is
unused for I2S TX, but the current software API still requires valid nonzero
addresses for a uniform descriptor contract. DMA writes received stream words
to AXI4 memory and reads I2S TX words from AXI4 memory.

## Verification Boundary

The DMA directed test covers stream TX backpressure, two-word stream RX to
memory, exact transfer length, bus errors, and retained RIB burst behavior. The
I2S and DVP FIFO tests continue to cover PIO mode. Physical audio and camera
clock-domain behavior remains controller-specific and must be verified with
board-level timing and device models.
