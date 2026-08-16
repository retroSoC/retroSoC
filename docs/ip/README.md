# IP Documentation

This directory owns architecture, register ABI, software contract, and
verification documentation for self-owned retroSoC peripheral IP.

- [timer.md](timer.md) defines the dual APB4 general timer.
- [sysctrl.md](sysctrl.md) defines the APB4 SystemCtrl register ABI, control-plane contracts, HAL, and verification.
- [ws2812.md](ws2812.md) defines the WS2812 transmitter.
- [clint.md](clint.md) defines the management-hart software and timer interrupt block.
- [gpio.md](gpio.md) defines the dual-window GPIO controller.
- [uart.md](uart.md) defines the APB4 UART controller.
- [i2c.md](i2c.md) defines the dual APB4 I2C controllers.
- [dvp.md](dvp.md) defines the APB4 DVP capture controller.
- [sdram.md](sdram.md) defines the AXI4 SDRAM data controller and APB4 configuration window.

The corresponding RTL and HAL implementations remain the executable sources
of truth. Update the affected document whenever an IP interface or register ABI
changes.
