# ESP-PSRAM64H Controller

The Mini SoC PSRAM controller provides a 32 MiB memory-mapped AXI4 window over
four ESP-PSRAM64H devices and a separate RIBP management window. It is a
device-specific 4-bit SDR controller, not a generic serial-memory controller.

## Scope and Integration

| Property | Value |
| --- | --- |
| AXI4 data window | `0x40000000` - `0x41FFFFFF` |
| RIBP management window | Generated `RS_SOC_RIBP_PSRAM_BASE` window |
| Capacity | 4 chips x 8 MiB = 32 MiB |
| Chip selection | `chip = offset[24:23]` |
| Device address | `local_addr = offset[22:0]` |
| AXI data/ID/USER width | 32/1/1 bits |
| Physical protocol | ESP-PSRAM64H SPI/QPI, 4-bit SDR, SCLK idle low |
| Physical update/sample | Output on one phase, input on the opposite phase |
| Maximum device clock | 133 MHz device limit; see physical sign-off boundary |

The implementation excludes 8-data-pin or octal PSRAM, DDR/DTR, DQS, generic
CPOL/CPHA selection, ECC, arbitrary software opcodes, and raw protocol-phase
programming. The management port is for configuration, recovery, status, and
restricted commands. Bulk data must use the AXI window.

`ribp_psram` composes four blocks:

- `psram_reg`: RIBP register ABI, interrupts, and performance counters.
- `psram_axi4`: AXI protocol validation, error drain, byte strobes, and beat
  address generation.
- `psram_core`: initialization, chip isolation, command arbitration, and the
  read buffer.
- `psram_phy`: fixed-phase SPI/QPI command execution and timing enforcement.

## AXI4 Contract

The controller accepts one read or write burst at a time. Read addresses have
priority when read and write address valid are asserted together. Supported
transactions have all of these properties:

- aligned 1-, 2-, or 4-byte beats;
- `FIXED`, `INCR`, or legal 2/4/8/16-beat `WRAP` bursts;
- at most 16 beats;
- no exclusive access;
- no 4 KiB boundary crossing;
- both the first and last byte are inside the PSRAM window.

An invalid write address is followed by complete W-channel draining and one
`SLVERR` B response. An invalid read address returns the requested number of
R beats with `SLVERR` and the correct final `RLAST`. A disabled, absent, or
failed chip also returns `SLVERR`; it does not block healthy chip windows.

Each accepted write beat is reduced to one or more contiguous `WSTRB` runs, so
strobe holes never overwrite memory. Reads fetch an aligned 32-byte physical
line. Four fully associative entries retain fetched lines with round-robin
replacement. A write invalidates a matching line; initialization, recovery,
abort, and indirect commands invalidate all lines. This is an internal
read-only acceleration structure and is not a software-visible coherent cache.

## Initialization and Recovery

Reset defaults leave the controller and memory window enabled, but automatic
initialization disabled. This prevents commands from reaching the device
before firmware has configured the PSRAM pin mux. Firmware must configure the
pads and timing, issue `COMMAND.INIT`, and wait for the `INIT_DONE` interrupt
and `STATUS.READY`.

The controller latches an initialization request received before `tPU` has
expired. It then processes each enabled chip independently:

1. issue QPI `66h`, `99h` to recover a device left in QPI by a warm controller
   reset;
2. issue SPI `66h`, `99h` to establish the cold-reset SPI state;
3. issue SPI `9Fh` and read the 48-bit identifier;
4. require KGD `5Dh` and density `26h`;
5. issue SPI `35h` to enter QPI;
6. issue QPI `C0h` when wrap32 is selected.

A failed ID, PHY timeout, or missing device sets that chip's sticky error and
continues initialization of the remaining chips. `CHIP_PRESENT` means the ID
was accepted; `CHIP_READY` means mapped accesses are permitted. `READY` is set
when the controller and memory window are enabled and at least one chip is
ready.

`COMMAND.RECOVER` reruns the sequence for one enabled chip. `COMMAND.ABORT`
forces SCLK low, all CE# outputs high, and the data outputs to a safe state.
Software should inspect `LAST_ERROR`, clear the corresponding sticky state,
and recover only the affected chip. Recovery and indirect commands quiesce new
AXI addresses until the accepted transaction is complete.

## Timing Programming

All timing registers are expressed in source-clock cycles. The HAL helper
`rs_psram_timing_from_hz(source_hz, requested_sclk_hz, &timing)` uses 64-bit
intermediates and ceiling division:

```text
half_period = ceil(source_hz / (2 * requested_sclk_hz))
actual_sclk = floor(source_hz / (2 * half_period))
powerup     = ceil(source_hz * 150 us)
cs_setup    = ceil(source_hz * 3 ns)
cs_high     = ceil(source_hz * 50 ns)
cs_hold     = max(ceil(source_hz * 20 ns),
                  ceil(source_hz * (actual_sclk_period + 6 ns)))
cs_max_low  = floor(source_hz * 8 us)
```

The default access timeout is 1% of one source-clock second and is increased
when necessary to exceed `cs_max_low`. The helper rejects zero frequencies,
divider/counter overflow, and requests above 133 MHz. `CLK_CONFIG[16]` records
that the actual clock exceeds 84 MHz, where linear accesses must not cross a
1 KiB device page in one physical command.

The RTL provides the digital timing controls needed by ESP-PSRAM64H. A claim
above 84 MHz additionally requires pad slew, package/board delay, input sample
window, PDK timing, and STA evidence. The 133 MHz device rating alone is not a
retroSoC system sign-off.

## Register ABI

Registers are 32-bit and naturally aligned. Unaligned, unmapped, directionally
invalid, and forbidden busy-time accesses return RIBP `resp_err`. Configuration
registers accept `wstrb` partial writes. Action and RW1C registers require the
low byte strobe.

| Offset | Name | Access | Reset | Description |
| --- | --- | --- | --- | --- |
| `0x000` | `CTRL` | RW | `0x00000003` | `[0]` enable, `[1]` memory enable, `[2]` auto-init, `[3]` wrap32. |
| `0x004` | `COMMAND` | WO | `0` | One-hot `[0]` init, `[1]` recover, `[2]` abort; recover chip in `[9:8]`. |
| `0x008` | `STATUS` | RO | `0` | init/AXI/indirect/PHY busy `[3:0]`, quiesced `[4]`, ready `[5]`. |
| `0x00C` | `CHIP_ENABLE` | RW | `0xF` | Expected and enabled chip mask. |
| `0x010` | `CHIP_PRESENT` | RO | `0` | Valid KGD/density mask. |
| `0x014` | `CHIP_READY` | RO | `0` | Memory-accessible chip mask. |
| `0x018` | `CHIP_MODE` | RO | `0` | QPI mask `[3:0]`, wrap32 mask `[7:4]`. |
| `0x01C` | `CHIP_ERROR` | RW1C | `0` | Per-chip sticky error mask. |
| `0x020` | `CLK_CONFIG` | RW | `0x00000001` | Half-period `[15:0]`, above-84-MHz policy `[16]`. |
| `0x024` | `POWERUP_CYCLES` | RW | `10800` | Minimum `tPU` wait. |
| `0x028` | `CS_SETUP_CYCLES` | RW | `1` | CE# low to first rising SCLK. |
| `0x02C` | `CS_HIGH_CYCLES` | RW | `4` | Minimum command-to-command CE# high time. |
| `0x030` | `CS_HOLD_CYCLES` | RW | `3` | Last rising SCLK to CE# high. |
| `0x034` | `CS_MAX_LOW_CYCLES` | RW | `576` | Maximum CE# low watchdog. |
| `0x038` | `ACCESS_TIMEOUT_CYCLES` | RW | `100000` | Command completion watchdog. |
| `0x03C` | `TIMING_STATUS` | RO | derived | Half-period `[15:0]`, valid `[16]`, above 84 MHz `[17]`. |
| `0x040` | `INDIRECT_CTRL` | RW/action | `0` | Command `[3:0]`, chip `[9:8]`, length-minus-one `[18:16]`, start `[31]`. |
| `0x044` | `INDIRECT_ADDR` | RW | `0` | 23-bit local device address. |
| `0x048` | `INDIRECT_WDATA_LO` | RW | `0` | Write payload `[31:0]`. |
| `0x04C` | `INDIRECT_WDATA_HI` | RW | `0` | Write payload `[63:32]`. |
| `0x050` | `INDIRECT_RDATA_LO` | RO | `0` | Read payload `[31:0]`. |
| `0x054` | `INDIRECT_RDATA_HI` | RO | `0` | Read payload `[63:32]`. |
| `0x058` | `LAST_ERROR` | RO | `0` | Error class `[3:0]`, chip `[7:6]`. |
| `0x05C` | `LAST_ERROR_ADDR` | RO | `0` | First failing mapped or local address. |
| `0x060`-`0x07C` | `CHIPn_ID_LO/HI` | RO | `0` | Four 48-bit identifiers, low word then high 16 bits. |
| `0x080` | `INTR_STATE` | RW1C | `0` | Sticky interrupt state. |
| `0x084` | `INTR_ENABLE` | RW | `0` | Interrupt enable mask. |
| `0x088` | `INTR_STATUS` | RO | `0` | `INTR_STATE & INTR_ENABLE`. |
| `0x08C` | `INTR_TEST` | WO | `0` | Set selected interrupt state bits. |
| `0x090` | `PERF_CTRL` | RW/action | `0` | enable `[0]`, freeze `[1]`, clear action `[2]`. |
| `0x094` | `PERF_READ_BYTES` | RO | `0` | Saturating mapped-read byte count. |
| `0x098` | `PERF_WRITE_BYTES` | RO | `0` | Saturating mapped-write byte count. |
| `0x09C` | `PERF_COMMANDS` | RO | `0` | Saturating physical-command count. |
| `0x0A0` | `PERF_SPLITS` | RO | `0` | Saturating split count. |
| `0x0A4` | `PERF_STALL_CYCLES` | RO | `0` | Saturating AXI stall-cycle count. |
| `0x0A8` | `PERF_ERROR_COUNT` | RO | `0` | Saturating error count. |
| `0x0F8` | `IP_VERSION` | RO | `0x00010000` | ABI version 1.0. |
| `0x0FC` | `CAPABILITY` | RO | `0x20102043` | Frozen capability encoding below. |

`CAPABILITY[31:24]` is aperture MiB (`0x20`), `[23:16]` is the maximum AXI
burst beats (`0x10`), `[15:8]` is the physical read-line bytes (`0x20`),
`[7:4]` is the chip count (`4`), `[1]` advertises the restricted indirect
engine, and `[0]` advertises per-chip fault isolation. Other low feature bits
are reserved as zero.

Interrupt bits are init done `[0]`, indirect done `[1]`, error `[2]`, and
timeout `[3]`. Events win over a same-cycle RW1C clear. Error classes are none
`0`, illegal `1`, unavailable `2`, timeout `3`, ID `4`, aborted `5`, PHY `6`,
and protocol `7`.

The restricted command field accepts only `03h`, `0Bh`, `EBh`, `02h`, `38h`,
`35h`, `F5h`, `66h`, `99h`, `C0h`, and `9Fh` through command enum values
0 through 10. Payload length is 1 through 8 bytes. Mode, line width, address
phase, and dummy cycles are selected by hardware.

## HAL Sequence

Applications include `<retrosoc/hal/psram.h>` and use bounded APIs:

```c
rs_psram_config_t config;

if ((rs_psram_timing_from_hz(source_hz, target_hz, &config.timing) == RS_OK)) {
    config.chip_enable = UINT8_C(0x0F);
    config.wrap32 = false;
    config.auto_initialize = false;
    config.memory_enable = true;
    if ((rs_psram_configure(&config) == RS_OK) &&
        (rs_psram_initialize(timeout) == RS_OK)) {
        /* The healthy CHIP_READY windows may now be accessed through AXI. */
    }
}
```

The HAL also provides status and ID reads, per-chip recovery, abort, typed
indirect commands, wrap selection, interrupt control, and a bounded destructive
self-test. No dynamic memory or hosted-library dependency is introduced.

## Requirement Traceability

| ID | Requirement | Primary evidence |
| --- | --- | --- |
| PSRAM-001 | Four 8 MiB chips form one 32 MiB window. | Memory-map tests, boundary accesses in `psram_tb.sv`, full-SoC boot. |
| PSRAM-002 | Warm and cold initialization recover SPI/QPI state and validate ID. | Device model plus initialization and missing-chip scenarios in `psram_tb.sv`. |
| PSRAM-003 | One failed chip is isolated without blocking healthy chips. | Chip 2 missing-fault test; ready/error masks and healthy-chip AXI accesses. |
| PSRAM-004 | AXI legal bursts complete; illegal bursts terminate without deadlock. | Directed AXI/WSTRB/backpressure/error-drain tests and `formal-psram`. |
| PSRAM-005 | RIBP rejects invalid ABI accesses and protects active timing. | Register error tests in `psram_tb.sv`. |
| PSRAM-006 | All commands obey bounded CE#/SCLK and abort-safe behavior. | PHY assertions in `formal-psram`, model timing checks, access watchdog tests. |
| PSRAM-007 | RTL and HAL register offsets remain synchronized. | `tests/test_psram.py` ABI comparison. |
| PSRAM-008 | Timing math rounds conservatively and rejects invalid ranges. | Host cases in `tests/c/test_runtime.c`. |
| PSRAM-009 | The integrated SoC boots and executes from PSRAM. | IHP130 Verilator `SIM_TEST_PASS`; synthesis/netlist/STA regression gates. |

`python3 -m pytest -q tests/test_psram.py` runs the deterministic controller
test. `make CONFIG=configs/ci/ihp130.mk formal-psram` runs the PSRAM AXI/PHY
prove and cover jobs. Full delivery also requires the selected IHP130 firmware,
RTL lint, Yosys synthesis, Icarus netlist simulation, OpenSTA, warning, and
metric stages.

Event-driven simulation retains model timing checks based on simulation time.
The full-SoC Verilator harness uses `--no-timing`, so it disables those model
`$time` checks and relies on the controller's cycle counters. Passing either
simulation does not replace board-level SI, 133 MHz sample-window training,
package/PCB timing, or silicon characterization.
