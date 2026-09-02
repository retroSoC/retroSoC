# HP Linux Port

This directory owns the Buildroot external tree, device tree, kernel config,
and integration metadata for the fixed RV32 VexiiRiscv HP core. Linux,
OpenSBI, Buildroot, toolchains, and all generated images remain below `.cache/`
or `build/` and are not tracked.

The MVP uses OpenSBI `FW_JUMP` without U-Boot. Its fixed SDRAM layout is:

| Artifact | Address | Maximum size |
| --- | --- | --- |
| OpenSBI | `0x38000000` | 512 KiB |
| DTB | `0x38080000` | 64 KiB |
| Linux Image | `0x38400000` | 12 MiB |
| initramfs | `0x39000000` | 8 MiB |

Run `make setup-hp-linux` to install the locked sources, then use the
`hp-linux` target from an `HAVE_HP=YES` committed profile. The initial Linux
console uses SBI; the UART1 and mailbox nodes reserve their stable platform
ABI for the native drivers.

