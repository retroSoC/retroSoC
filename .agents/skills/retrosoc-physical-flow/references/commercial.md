# Commercial ICS55 flow

Read the [commercial guide](../../../../physical/commercial/README.md), its
[Makefile](../../../../physical/commercial/Makefile), and the selected local
configuration without copying site-sensitive values into tracked material.
The current flow is Mini/ICS55, not a generic adapter for every product/PDK.

## Inputs and execution boundary

The development zone creates the production RTL package from the committed
`configs/cluster/ics55.mk` profile with the guide's PLL/SRAM settings. The EDA
zone consumes that archive through a real, ignored `LOCAL_CONFIG` and `RUN_ID`.
Validate the source/configuration/clock inventory and archive identity before
using it. An inspection request must not generate the package or submit jobs.

For authorized execution, use the repository Make targets and site-selected
LSF mechanism. Never invoke licensed tools directly on the development host
or replace missing site libraries/decks with guessed or public substitutes.
Missing licenses, queues, collateral, or approved constraints are explicit
prerequisites. Do not claim that setup succeeded just because an example local
configuration exists.

There are two different acceptance boundaries:

- Internal synthesis QoR uses `doctor-syn`, `syn`, and `fm-rtl2syn`. The relaxed
  entrypoint may omit qualified board I/O budgets and records `io_qualified=no`.
  Its top-level I/O exclusions must be visible in the summary; it is not input
  qualification for Innovus/PrimeTime implementation.
- Full implementation uses the strict `doctor` and the selected stages up to
  `signoff`. Qualified I/O budgets, local pad timing hook, library/corner and
  extraction coverage, and zero-threshold verification rules remain mandatory.
  Never set `IO_TIMING_QUALIFIED=YES` without the supporting reviewed budgets.

Follow the current stage graph through synthesis/equivalence, APR,
post-route equivalence, extraction/STA/ECO, and physical verification only as
far as requested. The guide and executable targets, not a skill-maintained
copy of the graph, define dependencies and required evidence.

## Resume and handoff

Runs live under `build/commercial/ics55/<run-id>`. Before resuming, compare
original input/configuration hashes and the source identity, then check each
completed stage's result, required outputs, and verdict marker against its
stamp. Stamps alone are insufficient, especially after input or tool changes.

For unchanged valid inputs, repeating the requested endpoint with the same
local configuration and run ID uses the existing first-missing-stage behavior.
For stale evidence, stop and identify the invalid stage and affected downstream
stages. `force-<stage>` and `clean-stage` require explicit corresponding
authorization; never touch stamps or delete run trees to manufacture recovery.

Retain stage logs, result JSON, views, and reports. Report internal QoR versus
qualified I/O separately, and group timing by actual PVT/RC corner and stage.
Confirm the flow's equivalence, connectivity, annotation, setup/hold/design-rule,
DRC, antenna, and LVS verdicts rather than relying on an ending log line. A
target called `signoff` does not prove unmeasured package, board, electrical,
IR/EM/ESD, or silicon requirements; identify the remaining qualification gaps.
