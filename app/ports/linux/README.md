# HP Linux Port

This directory owns the Buildroot external tree, device tree, kernel config,
and integration metadata for the fixed RV64 VexiiRiscv HP core. Linux,
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

The RV64/Sv39 acceptance image uses musl and static BusyBox with a dedicated
`/init`. It mounts procfs, sysfs, devtmpfs and tmpfs, verifies file I/O and child
execution, then publishes the Linux-ready mailbox message. The kernel effective
configuration and all executable ELF classes are checked during the build.
`rootfs.cpio` is a small uncompressed archive; the DTB uses its actual length.
The DT reserves the resident 512 KiB OpenSBI window with `no-map`; Linux must
not allocate it. The custom platform does not apply the generic OpenSBI FDT fixups.
It does not start the full Buildroot service sequence.

```sh
make CONFIG=configs/ci/ihp130-hp.mk hp-linux
make CONFIG=configs/ci/ihp130-hp.mk SIMU=VERILATOR hp-linux-sim
```

The V2 bundle uses workload 1 and four typed payloads. V1 images must be rebuilt.
Linux success goes directly to LP TEST_STATUS; GA2D/cache lifecycle is tested
by `hp-smoke-sim`. Logs and verdicts live in `sim/verilator/hp-linux/` below
the selected variant. `HP_LINUX_SIM_TIME=0` means no emulator wall-clock timeout;
successful TEST_STATUS ends the run. Interrupted/running results are not passes.

See [HP platform](../../../docs/ip/hp-platform.md) for the ABI and
[RT-Thread BSP](../rtthread/README.md) for the separate M-mode workload.
