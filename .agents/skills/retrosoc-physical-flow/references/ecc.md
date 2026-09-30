# ECC padless-core hardening

Read the [ECC guide](../../../../physical/ecc/README.md) and
[Makefile](../../../../physical/ecc/Makefile). The current adapter consumes the
committed `configs/ci/ics55.mk` Mini profile, locked ECC release and ICS55 PDK,
and a padless `retrosoc_core`. It is not a Tiny, pad-ring, package, or board flow.

Preflight inspects inputs without executing `ecc-doctor`, `ecc-status`, or
`ecc-log`: these targets currently depend on setup/generated-input work.
Check clock-domain constraints and the locked slow Liberty view. A missing
multi-domain SDC capability is a blocker, not permission to use a single-clock
fallback.

Authorized execution uses the root entrypoints:

```sh
make CONFIG=configs/ci/ics55.mk SOC=MINI ecc-setup
make CONFIG=configs/ci/ics55.mk SOC=MINI ecc-doctor
make CONFIG=configs/ci/ics55.mk SOC=MINI ecc-core
```

Keep one build identity across related commands. Inspect `ecc-package` before
using it; it depends on `ecc-core` and is not a read-only archive inspection.
Inputs, logs, workspace, reports, and views belong under the selected variant's
`physical/ecc/core` directory. The tool archive belongs in the existing cache.

For resume, inspect the retained workspace and the locked CLI's actual recovery
support. Do not assume the commercial stamp mechanism or LibreLane run flags
apply. Where no safe supported recovery is available, preserve the old run and
ask for the specific fresh-run/overwrite choice rather than silently restarting.

Keep resource failures separate from design failures and preserve logs and
metrics provenance. Report measured core results only. The preview PDK and
padless flow do not establish foundry DRC/LVS, IR/EM, ESD, IO-ring, package,
board, or production-signoff closure.
