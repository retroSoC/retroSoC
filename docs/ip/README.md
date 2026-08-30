# IP Documentation

This directory owns architecture, register ABI, software contract, and
verification documentation for self-owned retroSoC peripheral IP and platform
extension interfaces.

- [timer.md](timer.md) defines the dual APB4 general timer.
- [sysctrl.md](sysctrl.md) defines the APB4 SystemCtrl register ABI, control-plane contracts, HAL, and verification.
- [resource-controller.md](resource-controller.md) defines root-managed resource ownership, IRQ routing, and cache-maintenance handoff.
- [user-ip.md](user-ip.md) defines the selectable user-IP window and software ownership boundary.
- [ws2812.md](ws2812.md) defines the WS2812 transmitter.
- [clint.md](clint.md) defines the management-hart software and timer interrupt block.
- [gpio.md](gpio.md) defines the dual-window GPIO controller.
- [uart.md](uart.md) defines the APB4 UART controller.
- [i2c.md](i2c.md) defines the dual APB4 I2C controllers.
- [dvp.md](dvp.md) defines the APB4 DVP capture controller.
- [i2s.md](i2s.md) defines the APB4 I2S master transceiver.
- [usb2.md](usb2.md) defines the dual-role ULPI USB 2.0 controller, AXI4
  descriptor DMA, dedicated-pad integration, HAL, and commercial release gates.
- [mini-npu.md](mini-npu.md) records the commercial NPU reference survey and optional
  Mini-AI architecture direction; it does not define implemented RTL or ABI.
- [sdram.md](sdram.md) defines the AXI4 SDRAM data controller and APB4 configuration window.
- [xpi.md](xpi.md) defines the native-AXI4/APB4 XPI V2 controller, commercial reference survey, LUT and PHY contracts, HAL, JTAG NOR programming, and delivery boundary.

The corresponding RTL and HAL implementations remain the executable sources
of truth. Update the affected document whenever an IP interface or register ABI
changes.
