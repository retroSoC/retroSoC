# HP RT-Thread BSP

This directory owns the single-hart RV64 M-mode BSP and deterministic kernel
acceptance application. Upstream RT-Thread is installed at the revision in the
dependency lock under `.cache/`; it is not edited or copied into project source.
SCons runs on a staged BSP below `build/<variant>/hp-rtthread/`.

Run `make setup-hp-rtthread`, then `make CONFIG=configs/ci/ihp130-rtthread.mk
SIMU=VERILATOR hp-rtthread-sim`. The test uses UART1, hart-1 CLINT and PLIC
machine context 0/source 2. Peripheral accesses remain 32 bits. Static threads
exercise RV64 integer state, timer preemption, semaphore/message queue behavior,
timeouts, and an LP-to-HP mailbox interrupt. LP validates the final mailbox
response and owns SYSCTRL TEST_STATUS. A banner alone is not a pass.

The authoritative contract is [HP platform](../../../docs/ip/hp-platform.md).
RT-Smart, networking, filesystems, floating-point task qualification, and PPA
are outside this test. Self-owned C follows the repository C policy; the locked
upstream OS is third-party material. No operating-system dependency enters crt.
