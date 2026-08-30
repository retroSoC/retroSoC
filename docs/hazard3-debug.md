# Hazard3 Management-Core Debug

## Scope

The fixed Hazard3 management core always exposes a standard RISC-V JTAG Debug
Transport Module (DTM) on five ASIC pads: TCK, TMS, TDI, TRST_n, and TDO. The
default JTAG ID code is `0xDEADBEEF`. Set
`JTAG_IDCODE=<eight hexadecimal digits>` to use a board-specific value.

The Debug Module (DM) controls only the management Hazard3 hart. It supports
abstract register and memory commands and has `HAVE_SBA=0`, so it never becomes
a second SoC bus master. Debugger memory operations execute through the halted
hart and remain subject to the AXI4 interconnect access policy. MPW user cores,
peripherals, clocks, and pad control stay outside the debug-reset scope.

The product Vexii HP hart can own shared JTAG only while held in reset. C0-C3
are software-selected only in the mini-ver-mpw compatibility profile; they are
not management-core options and do not have a management Debug Module.

## Reset And Clocking

The DTM runs in the JTAG TCK domain. Hazard3's APB async bridge transfers DMI
transactions into the LP DM domain. The canonical clock/reset map constrains
TCK at 10 MHz and declares JTAG asynchronous to LP.

The DM `ndmreset` and hart-reset requests pass through `mgmt_debug_reset`.
It waits until the management AHB-Lite-to-AXI4 bridge is idle, then resets only
that bridge and the management hart. The DTM, DM, RCU, MPW user cores, and all
peripherals remain live. Reset release is synchronized with the common
`rst_sync` cell and acknowledged only after the local reset is released.

## Verilator Acceptance

The `ihp130-debug` profile builds a minimal SRAM-resident firmware image and
starts a loopback remote-bitbang endpoint inside the Verilator harness. The
locked OpenOCD and RISC-V GDB binaries then verify JTAG identification, hart
register access, SRAM read/write, ELF download, a software breakpoint, resume,
and single-step.

```sh
make CONFIG=configs/ci/ihp130-debug.mk SIMU=VERILATOR debug-sim
```

The flow writes `result-debug-sim.json` and the emulator, OpenOCD, and GDB logs
under `build/<variant>/sim/verilator/debug/`. It passes only when GDB prints
`DEBUG_GDB_PASS`. This is a functional simulation check, not board-level JTAG
signal-integrity, DFT, or production debug-lock signoff.

The OpenOCD configuration is
`rtl/mini/dv/verilator/openocd/retrosoc_hazard3.cfg`; its remote-bitbang port
is supplied by the test driver, so concurrent local runs do not share a fixed
TCP port.
