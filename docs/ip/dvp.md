# APB4 DVP

The DVP block captures an 8-bit parallel camera stream and presents the
captured pixels through an AXI4-Stream source. APB4 is used for configuration,
status, statistics, error reporting, and interrupts. The existing DMA engine
can transfer the AXI4-Stream payload into AXI4 memory using DVP receive mode.
The input path supports RGB565 and YUV422 byte formats, programmable VSYNC
and HREF polarity, selectable PCLK sampling edge, snapshot and continuous
capture, and rectangular cropping.

## Integration

| Property | Value |
| --- | --- |
| APB4 base address | `0x1000E000` |
| APB4 interrupt group bit | 13 |
| Management-core interrupt | 15 |
| Input interface | 8-bit parallel data, PCLK, HREF, VSYNC |
| AXI4-Stream data width | 32 bits |
| AXI4-Stream frame markers | `TUSER[0]` SOF, `TLAST` EOL |
| DMA request selector | `DVP_RX` on bulk DMA channel 3 |
| ABI version | `0x00020000` |

The pixel clock is buffered and can be inverted before the pixel-domain reset
synchronizer. Configuration and frame statistics cross between the system and
pixel domains through the common `cdc_2phase` primitive. Captured payloads use
the common `cdc_fifo_warm_flush` primitive and carry
`{TUSER, TLAST, TKEEP, TSTRB, TDATA}`. FIFO overflow drops the active frame,
sets an error flag, and requires software to discard the affected DMA buffer.

## Register ABI

All registers are 32 bits and naturally aligned. Unmapped, unaligned, and
direction-invalid accesses complete with `resp_err`. Configuration writes are
rejected while capture is active. Frame dimensions must be non-zero; invalid
format or crop values set the configuration error path and do not start a
valid capture. RW registers support byte strobes.

| Offset | Name | Access | Description |
| --- | --- | --- | --- |
| `0x000` | `CTRL` | RW | Enable, snapshot, and crop-enable controls. |
| `0x004` | `RXDATA` | RO/pop | PIO receive word when AXI4-Stream output is disabled. |
| `0x008` | `STATUS` | RO | Active, FIFO, stream, and error state. |
| `0x00C` | `STREAM_CTRL` | RW | Enable AXI4-Stream output. |
| `0x010` | `FORMAT` | RW | RGB565/YUV422 selection and byte/pixel swap controls. |
| `0x014` | `SYNC_CFG` | RW | VSYNC, HREF, and PCLK polarity controls. |
| `0x018` | `FRAME_SIZE` | RW | Frame width in bits 15:0 and height in bits 31:16. |
| `0x01C` | `CROP_START` | RW | Crop X coordinate in bits 15:0 and Y coordinate in bits 31:16. |
| `0x020` | `CROP_SIZE` | RW | Crop width in bits 15:0 and height in bits 31:16. |
| `0x024` | `FRAME_COUNT` | RO | Completed frame count. |
| `0x028` | `LINE_COUNT` | RO | Completed line count from the last frame. |
| `0x02C` | `PIXEL_COUNT` | RO | Captured pixel count from the last frame. |
| `0x030` | `WORD_COUNT` | RO | AXI4-Stream word count from the last frame. |
| `0x034` | `DROP_COUNT` | RO | Number of dropped words caused by overflow. |
| `0x038` | `ERROR_STATUS` | RW1C | Sticky overflow, sync, size, partial, config, and abort errors. |
| `0x03C` | `INTR_STATE` | RW1C | Sticky frame, line, overflow, configuration, and abort events. |
| `0x040` | `INTR_ENABLE` | RW | Interrupt enable mask. |
| `0x044` | `INTR_STATUS` | RO | `INTR_STATE & INTR_ENABLE`. |
| `0x048` | `INTR_TEST` | WO | Write-one software interrupt injection. |
| `0x04C` | `COMMAND` | WO | Abort and FIFO flush commands. |
| `0x0F8` | `IP_VERSION` | RO | ABI version, currently `0x00020000` (2.0). |
| `0x0FC` | `CAPABILITY` | RO | Implemented format, crop, statistics, interrupt, and stream features. |

`CTRL` bit 0 enables capture, bit 1 selects snapshot mode, and bit 2 enables
cropping. `STREAM_CTRL` bit 0 enables AXI4-Stream output; when it is clear,
software can consume captured words through `RXDATA`. `FORMAT` values `0` and
`1` select RGB565 and YUV422 respectively. Values above `1` are invalid.
`FORMAT` bits 2 and 3 control byte and pixel ordering. `SYNC_CFG` bits 0, 1,
and 2 select active-low VSYNC, active-low HREF, and falling-edge PCLK.

The seven interrupt bits are frame start, line done, frame done, overflow,
synchronization error, configuration error, and aborted capture. Error and
interrupt state are write-one-to-clear. Hardware events have priority over a
simultaneous software clear so that an event cannot be lost. The external
interrupt is the reduction OR of `INTR_STATE & INTR_ENABLE`.

The RTL ABI constants are maintained directly in
`rtl/ip/multimedia/dvp_define.svh`. Matching HAL offsets and masks are
maintained directly in `crt/src/hal/dvp.c`. Changes to either definition must
update the other definition, this document, and the RTL/software tests in the
same change.

## AXI4-Stream and Capture Semantics

Two 8-bit input samples are packed into one 32-bit stream word. The first
pixel occupies `TDATA[15:0]` and the second pixel occupies `TDATA[31:16]`.
`TUSER[0]` is asserted on the first word of a frame, and `TLAST` is asserted
on the last word of each line. `TID` and `TDEST` are tied to zero.

For an even number of pixels, `TKEEP` and `TSTRB` are `4'b1111`. For an odd
number of pixels, the final word of each line uses `4'b0011` and the unused
upper half of `TDATA` is zero. AXI4-Stream `TVALID` remains asserted and the
payload remains stable while `TREADY` is low. The FIFO backpressures the pixel
domain; an inability to accept a word during an active frame records an
overflow and terminates that frame.

VSYNC rising after polarity normalization starts a frame. HREF qualifies
pixel sampling and its falling edge completes a line. Snapshot mode stops
after the next completed frame; continuous mode resets line and pixel counters
and captures the next frame. Crop coordinates are applied in the normalized
frame coordinate space, and a crop must fit within the configured frame size.

The PIO path and AXI4-Stream path are mutually exclusive at the output:
`RXDATA` pops a word only while stream output is disabled. The DMA HAL uses a
single-frame transfer length; descriptor rings, double buffering, and frame
metadata chaining are not part of the current ABI.

## DMA and Software Contract

The DMA MVP treats each full AXI4-Stream word as one 32-bit memory write.
It accepts only `TKEEP=4'hf`; an odd-pixel DVP line produces a partial final
word and therefore requires PIO handling or a future narrow-transfer/DRE DMA
extension. Software should configure the frame and crop dimensions, clear
stale error and interrupt state, program the channel-3 `DVP_RX` destination
and capacity, enable stream output, and then start DVP capture. A frame that
reports overflow, synchronization, partial, DMA, or abort errors must not be
consumed by software.

The public HAL exposes structured configuration, bounded status polling,
command and interrupt control, capability discovery, and a convenience API
for one-frame DMA capture. Applications should use `rs_dvp_configure()`,
`rs_dma_configure()`, `rs_dma_start()`, `rs_dvp_start()`, and
`rs_dvp_capture_dma()` rather than
accessing the registers directly.

## Verification and Current Scope

The self-checking RTL test covers the versioned ABI, invalid APB4 accesses,
configuration writes, RGB565 packing, SOF/EOL framing, even and odd line
widths, AXI4-Stream output, frame statistics, and interrupt state handling.
The SBY target proves APB4 response behavior, request/response progress,
interrupt composition, and normal/error coverage for the register shell.
Host tests compile and execute the DVP directed test, while the IHP130
regression exercises behavior simulation, synthesis, netlist simulation, and
STA integration.

The current ABI does not include a native DVP AXI4 memory master, outstanding
AXI transactions, frame descriptor rings, line stride configuration, JPEG or
other compressed formats, external sync metadata, or multiple camera clocks.
Those features require a versioned ABI extension and explicit SoC routing;
existing register fields must not be repurposed for them.

## RTL Coding-Style Migration

The current DVP maintenance pass is limited to source organization and naming;
it does not change the register ABI, APB4 timing, AXI4-Stream framing, CDC
topology, pixel packing, interrupt behavior, or error semantics. Register
address macros retain their `APB4_DVP_*` names so the software HAL remains
compatible. Internal field macros use the `APB4_DVP__*` namespace, and local
parameters use UpperCamelCase. Internal configuration and command paths use
the project abbreviations `cfg` and `cmd`, while public APB4 and AXI4-Stream
interfaces remain unchanged.

Owned DVP modules use explicit named-port connections. Module ports and macro
definitions are manually column-aligned only inside narrow
`verilog_format: off/on` regions where Verible cannot preserve the alignment;
ordinary declarations, assignments, and instances remain formatter-managed.
The `dvp_camera` simulation model follows the same naming and named-port
rules. Its delayed falling-edge assignment is intentionally retained because
it models camera HREF timing and is not synthesizable IP behavior.

The local validation entry points are:

```sh
python3 -m pytest -q tests/test_dvp.py
make CONFIG=configs/ci/ihp130.mk formal-dvp
make format-check rtl-style-check-all rtl-readiness-check-all
```
