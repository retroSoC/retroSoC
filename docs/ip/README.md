# IP Documentation

This directory owns architecture, register ABI, software contract, and
verification documentation for self-owned retroSoC peripheral IP.

- [timer.md](timer.md) defines the dual RIBP general timer.
- [ws2812.md](ws2812.md) defines the WS2812 transmitter.
- [clint.md](clint.md) defines the management-hart software and timer interrupt block.
- [gpio.md](gpio.md) defines the dual-window GPIO controller.
- [uart.md](uart.md) defines the RIBP UART V3 controller.
- [i2c.md](i2c.md) defines the dual RIBP I2C V2 controllers.
- [dvp.md](dvp.md) defines the RIBP DVP V2 capture controller.

The corresponding RTL and HAL implementations remain the executable sources
of truth. Update the affected document whenever an IP interface or register ABI
changes.
