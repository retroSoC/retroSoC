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
   `retrosoc_mini_sources.tar.gz`, and run:

   ```sh
   make -C physical/commercial \
     LOCAL_CONFIG=local/ics55-production.mk doctor
   make -C physical/commercial \
     LOCAL_CONFIG=local/ics55-production.mk signoff
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
The flow has no local switch that converts a required check into success.

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
