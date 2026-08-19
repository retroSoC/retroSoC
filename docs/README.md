# Engineering Documentation

This directory contains repository-level engineering policy that supplements
the root README and subsystem guides.

- [engineering.md](engineering.md) describes reproducible inputs, build
  artifacts, result policy, warning baselines, metrics, CI, and releases.
- [development-environment.md](development-environment.md) describes the
  Docker, Nix, and manual open-source regression environments.
- [misra-c-2012.md](misra-c-2012.md) defines the MISRA C:2012 Amendment 2
  baseline, scope, partial automation, and deviation process.
- [rtl-coding-style.md](rtl-coding-style.md) is the normative self-owned RTL
  policy; [rtl-coding-style-compliance.md](rtl-coding-style-compliance.md)
  defines its executable audit and behavior-preserving migration process.
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
- [axi4-interconnect.md](axi4-interconnect.md) defines the active Mini SoC AXI4
  subset, arbitration, target, access-control, error, and performance contract.
- [axi4-sdram-performance.md](axi4-sdram-performance.md) records the commercial
  SDRAM-controller survey, the implemented retroSoC MVP, and the performance
  roadmap that stays inside the phase-separated 16-bit / 64 MiB contract.
- [axi4-stream.md](axi4-stream.md) defines the DMA, I2S, and DVP AXI4-Stream
  data paths, PIO fallback, register controls, and backpressure contract.
- [ip/dma.md](ip/dma.md) defines the native-AXI4 four-channel DMA direct-mode
  register ABI, SDK API, scheduling, error, IRQ, and stream contracts.
- [ip/ws2812.md](ip/ws2812.md) defines the WS2812 transmitter register ABI,
  timing, FIFO, interrupt, DMA, and integration contracts.
- [ip/timer.md](ip/timer.md) defines the dual general timer register ABI,
  counting modes, interrupt, debug-freeze, HAL, and verification contracts.
- [ip/sysctrl.md](ip/sysctrl.md) defines the SystemCtrl register ABI, user-core
  lifecycle, PLL/fault/performance/RTC/test contracts, HAL, and verification.
- [ip/clint.md](ip/clint.md) defines the standard CLINT register map, fixed
  timebase, RV32 access rules, interrupt behavior, and verification contract.
- [ip/gpio.md](ip/gpio.md) defines the GPIO dual-window ABI, pad ownership,
  filtering, interrupts, PDK capabilities, HAL, and verification contract.
- [ip/uart.md](ip/uart.md) defines the UART framing, FIFO, RTS/CTS flow
  control, error, interrupt, DMA, HAL, and verification contracts.
- [ip/i2c.md](ip/i2c.md) defines the dual I2C command, timing, error,
  recovery, DMA, HAL, and verification contracts.
- [ip/i2s.md](ip/i2s.md) defines the I2S master register ABI, phase-separated
  PHY, AXI4-Stream packing, CDC, HAL, and verification contracts.
- [ip/psram.md](ip/psram.md) defines the four-chip ESP-PSRAM64H AXI/APB4
  controller, register ABI, timing, isolation, recovery, HAL, and verification
  contracts.
- [ip/opipsram.md](ip/opipsram.md) defines the boot-selected OPI/xSPI and
  single-clock HyperBus profiles, shared digital PHY, delay-cell boundary,
  register ABI, central-DMA use, and commercial signoff limits.
- [ip/ps2.md](ip/ps2.md) defines the Mini SoC PS/2 APB, GPIO pad,
  interrupt, SDK, and managed-IP integration contract.
- The managed [RTC V2 datasheet](../rtl/managed/clusterip/rtc/doc/datasheet.md)
  defines Epoch time, alarms, periodic wake, calibration, CDC, and software.
- The managed [CRC V2 datasheet](../rtl/managed/clusterip/crc/doc/datasheet.md)
  defines the programmable streaming CRC engine, APB ABI, errors, and software.
- The managed [PWM V2 datasheet](../rtl/managed/clusterip/pwm/doc/datasheet.md)
  defines the dual-timer/four-channel LED and motor PWM controller, fault,
  synchronization, dead-time, carrier, fade, and capture contracts.
- [soc-integration-wiring.md](soc-integration-wiring.md) defines the generated
  pin-map workflow and SoC integration boundary.
- [mini-soc-block-diagram.svg](mini-soc-block-diagram.svg) is the Mini SoC
  architecture overview. Its Graphviz source is
  [mini-soc-block-diagram.dot](mini-soc-block-diagram.dot).

Keep policy descriptions here concise and link to executable configuration as
the source of truth. Changes that alter process requirements must also update
[`AGENTS.md`](../AGENTS.md) when agents need to follow them.
