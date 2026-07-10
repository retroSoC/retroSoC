# retroSoC

[![style](https://github.com/retroSoC/retroSoC/actions/workflows/style.yml/badge.svg)](https://github.com/retroSoC/retroSoC/actions/workflows/style.yml)
[![lint](https://github.com/retroSoC/retroSoC/actions/workflows/lint.yml/badge.svg)](https://github.com/retroSoC/retroSoC/actions/workflows/lint.yml)
[![test](https://github.com/retroSoC/retroSoC/actions/workflows/test.yml/badge.svg)](https://github.com/retroSoC/retroSoC/actions/workflows/test.yml)

## Build automation

Run `make help` for the supported build targets and `make config` for the active
configuration. `make doctor` checks the selected simulator, synthesis/STA tools,
RISC-V compiler, PDK, and external source trees before a long build starts.

External dependencies are pinned to known commits. Install them with `make setup`;
individual targets such as `setup-pdk`, `setup-ip`, and `setup-app` are also
available. Setup scripts are idempotent and accept `--update` when an existing
checkout must be moved to the pinned revision.

Typical open-source flows are:

```sh
make PROG_TYPE=BASE firmware
make SIMU=VERILATOR sim
make SIMU=IVERILOG sim
make SYNTH=YOSYS synth
make STA=OPENSTA sta
```

Generated outputs are isolated under ignored build directories. `make clean`
cleans the selected simulator backend and `make clean-all` removes all generated
flow output while leaving dependency checkouts intact.
