# Commercial Physical Design

This directory owns the self-developed integration for the licensed ICS55
implementation flow. It does not contain the PDK, foundry rule decks, standard
cell or macro libraries, commercial tool installations, or generated results.

## Execution boundary

The development and EDA zones share the repository and build directories
through a site-mounted shared filesystem, but have different responsibilities:

1. In the development zone, generate a production RTL package:

   ```sh
   make CONFIG=configs/cluster/ics55.mk \
     HAVE_PLL=YES HAVE_SRAM_IF=YES HAVE_SRAM_MACRO=YES \
     commercial-package
   ```

2. In the EDA zone, create the ignored local configuration from
   `config/ics55.example.mk`, point `RTL_ARCHIVE` at the generated
   `retrosoc_mini_sources.tar.gz`, and choose one of two entry points.
   For synthesis with internal timing only:

   ```sh
   make -C physical/commercial \
     LOCAL_CONFIG=local/ics55-production.mk doctor-syn
   make -C physical/commercial \
     LOCAL_CONFIG=local/ics55-production.mk RUN_ID=<run-id> syn
   make -C physical/commercial \
     LOCAL_CONFIG=local/ics55-production.mk RUN_ID=<run-id> fm-rtl2syn
   ```

   For production implementation, first populate every interface timing
   budget, set `IO_TIMING_QUALIFIED=YES`, and run:

   ```sh
   make -C physical/commercial \
     LOCAL_CONFIG=local/ics55-production.mk RUN_ID=<run-id> doctor
   make -C physical/commercial \
     LOCAL_CONFIG=local/ics55-production.mk RUN_ID=<run-id> signoff
   ```

Commercial tools are never executed directly by this Makefile. Every tool
stage is submitted as an independent blocking LSF job. `LSF_MODE=batch` uses
`bsub -K`; sites that expose only an interactive queue use
`LSF_MODE=interactive`, which runs the tool through `bsub -I` while preserving
the same exit-code and log contract. The submit host therefore retains a
deterministic dependency graph while each commercial command runs in the
isolated EDA compute environment.

The EDA-side implementation is compatible with GNU Make 3.82, Tcl 8.5, and
Python 2.7.5. Python helpers use only the standard library.

## Tracked and local inputs

Tracked sources define flow behavior, validation policy, stage dependencies,
and non-sensitive design intent. The ignored `local/` directory supplies all
site-specific values, including:

- tool commands and LSF queues/resources;
- Liberty/DB, LEF, GDS, CDL, and RC technology files;
- stream maps and Calibre DRC, antenna, and LVS decks;
- PDK cell lists, routing layers, sites, and power nets.
- reviewed min/max board and external-device I/O timing budgets;
- an audited ICS55 pad-mode timing hook when bidirectional arcs require it.

Do not add absolute PDK/library paths to tracked Make, Tcl, Python, shell, or
documentation files. Run `python3 scripts/audit_boundary.py --root ../..`
before handing off a change.

## Stage graph

The complete `signoff` target runs:

```text
input
  -> syn
  -> fm-rtl2syn
  -> apr-initialize -> apr-floorplan -> apr-preplace -> apr-place
  -> apr-cts -> apr-route
  -> fm-syn2pr
  -> extract -> sta
  -> eco -> apr-eco -> reextract -> resta
  -> pv-merge -> pv-drc -> pv-antenna -> pv-lvs
```

Each stage writes `log/`, `reports/`, `output/`, a result JSON, and a success
stamp below:

```text
build/commercial/ics55/<run-id>/
```

A stamp is created only when LSF reports success and every required output,
including the stage verdict marker, exists. Re-running `signoff` resumes from
the first missing stamp. Use `force-<stage>` to rerun one stage and downstream
dependencies; use `clean-stage STAGE=<stage>` for targeted cleanup.

## Strict verdict

The default policy is blocking:

- Design Compiler must elaborate and link without unresolved references.
- Formality RTL-to-synthesis and synthesis-to-route checks must succeed.
- PrimeTime route analysis must report complete timing/parasitic annotation
  and no unconstrained endpoints. Its violations are explicit ECO inputs; the
  post-ECO `resta` gate requires zero setup, hold, and design-rule violations.
- Route STA runs each common corner in the stage's LSF allocation and saves a
  PrimeTime session. PrimeTime ECO restores all 13 sessions into one DMSA
  analysis before emitting the reviewed Innovus ECO subset.
- Innovus connectivity and geometry checks must pass.
- Calibre DRC and antenna counts must be zero and LVS must be clean.

The production `doctor` requires every violation threshold to remain zero.
It also requires qualified JTAG, DVP, ULPI, SDRAM, SDIO, XPI, and asynchronous
I/O budgets and an audited local hook that selects GPIO10-20 DVP input mode
and cuts invalid bidirectional-pad feedback arcs. `doctor-syn` is the only
relaxed entry point: Design Compiler then false-paths all top-level I/O and
reports internal sequential QoR. Its summary carries `io_qualified=no`, and
Innovus and PrimeTime reject it.

The canonical six-domain clock inventory is generated from
`rtl/mini/integration/clock_reset_domains.json` into the commercial RTL
package. Commercial constraints add the crystal and PLL overlays and model
the system clock mux as physically exclusive external-source and PLL-source
generated clocks. The asynchronous relationships cover system, audio,
crystal, JTAG, DVP, and ULPI domains.

The standard-cell family is LLSC H7C across DB, Liberty, LEF, GDS, and CDL.
Design Compiler links one TYP set and targets only H7CR (SVT) plus H7CL
(LVT); H7CH remains available to physical implementation but is not a
synthesis target. No LVT percentage cap is implied. The synthesis result
records actual HVT/LVT/SVT counts, areas, and percentages in:

```text
syn/output/synthesis.summary.tsv
syn/output/synthesis.path_groups.tsv
```

Detailed clock, exception, setup/hold, QoR, design-rule, library-binding, and
reference reports are written below `syn/reports/`.

## Legacy-flow audit

The legacy source contains valid DC, Formality, Innovus, StarRC, PrimeTime,
PrimeTime ECO, Calibre, and `calibredrv` behavior, but also contains unrelated
process branches, old top-level names, copied RTL, absolute site paths, and
many generated sessions and reports. This implementation re-expresses only
the ICS55/`retrosoc_asic` behavior and does not source or execute legacy
scripts.

The common corner contract is:

| PVT | RC views |
| --- | --- |
| `MAX`, `WCL` | `Cworst`, `RCworst` |
| `TYP` | `TYP` |
| `MIN`, `ML` | `Cworst`, `RCworst`, `Cbest`, `RCbest` |

The old flow used a single typical Innovus analysis view and delegated broad
corner coverage to separate StarRC/PrimeTime runs. The new flow derives APR,
extraction, STA, and ECO scenarios from one configuration and rejects missing
views.
