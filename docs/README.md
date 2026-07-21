# Engineering Documentation

This directory contains repository-level engineering policy that supplements
the root README and subsystem guides.

- [engineering.md](engineering.md) describes reproducible inputs, build
  artifacts, result policy, warning baselines, metrics, CI, and releases.
- [misra-c-2012.md](misra-c-2012.md) defines the MISRA C:2012 Amendment 2
  baseline, scope, partial automation, and deviation process.
- [pll-clock-control.md](pll-clock-control.md) describes the SYSCTRL PLL
  register protocol and software quiesce contract.
- [soc-integration-wiring.md](soc-integration-wiring.md) defines the generated
  pin-map workflow and SoC integration boundary.

Keep policy descriptions here concise and link to executable configuration as
the source of truth. Changes that alter process requirements must also update
[`AGENTS.md`](../AGENTS.md) when agents need to follow them.
