# Engineering Documentation

This directory contains repository-level engineering policy that supplements
the root README and subsystem guides.

- [engineering.md](engineering.md) describes reproducible inputs, build
  artifacts, result policy, warning baselines, metrics, CI, and releases.
- [development-environment.md](development-environment.md) describes the
  Docker, Nix, and manual open-source regression environments.
- [misra-c-2012.md](misra-c-2012.md) defines the MISRA C:2012 Amendment 2
  baseline, scope, partial automation, and deviation process.
- [pll-clock-control.md](pll-clock-control.md) describes the SYSCTRL PLL
  register protocol and software quiesce contract.
- [hazard3-debug.md](hazard3-debug.md) defines the management Hazard3 JTAG
  Debug Module integration, reset boundary, and Verilator/OpenOCD/GDB flow.
- [coremark.md](coremark.md) defines the SRAM-resident Hazard3 CoreMark quick
  measurement, optional standard hardware run, and structured result format.
- [soc-family-positioning.md](soc-family-positioning.md) defines the planned
  Tiny, Mini, Std, and Pro product ladder, the implemented Mini baseline,
  planned product targets, claim gates, and commercial reference points.
- [rib-interconnect.md](rib-interconnect.md) defines the RIB v1 linear-burst
  contract, compatibility boundaries, target status, and verification.
- [ip/ws2812.md](ip/ws2812.md) defines the WS2812 transmitter register ABI,
  timing, FIFO, interrupt, DMA, and integration contracts.
- [ip/timer.md](ip/timer.md) defines the dual general timer register ABI,
  counting modes, interrupt, debug-freeze, HAL, and verification contracts.
- [ip/clint.md](ip/clint.md) defines the standard CLINT register map, fixed
  timebase, RV32 access rules, interrupt behavior, and verification contract.
- [ip/gpio.md](ip/gpio.md) defines the GPIO V2 dual-window ABI, pad ownership,
  filtering, interrupts, PDK capabilities, HAL, and verification contract.
- [ip/uart.md](ip/uart.md) defines the UART V2 framing, FIFO, error, interrupt,
  DMA, HAL, and verification contracts.
- [ip/i2c.md](ip/i2c.md) defines the dual I2C V2 command, timing, error,
  recovery, DMA, HAL, and verification contracts.
- [ip/ps2.md](ip/ps2.md) defines the Mini SoC PS/2 V2 APB, GPIO pad,
  interrupt, SDK, and managed-IP integration contract.
- The managed [RTC V2 datasheet](../rtl/managed/clusterip/rtc/doc/datasheet.md)
  defines Epoch time, alarms, periodic wake, calibration, CDC, and software.
- The managed [CRC V2 datasheet](../rtl/managed/clusterip/crc/doc/datasheet.md)
  defines the programmable streaming CRC engine, APB ABI, errors, and software.
- [soc-integration-wiring.md](soc-integration-wiring.md) defines the generated
  pin-map workflow and SoC integration boundary.
- [mini-soc-block-diagram.svg](mini-soc-block-diagram.svg) is the Mini SoC
  architecture overview. Its Graphviz source is
  [mini-soc-block-diagram.dot](mini-soc-block-diagram.dot).

Keep policy descriptions here concise and link to executable configuration as
the source of truth. Changes that alter process requirements must also update
[`AGENTS.md`](../AGENTS.md) when agents need to follow them.
