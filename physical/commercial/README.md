# Commercial Physical Design

This directory owns the self-developed integration for the licensed ICS55
implementation flow. It contains only flow logic and configuration policy: the
PDK, foundry rule decks, standard-cell or macro libraries, commercial tool
installations, site configuration, and generated results all remain outside
Git.

## Configuration layers

Configuration is resolved in three layers; later layers override earlier ones.

1. `config/technology/<technology>.mk` (tracked) — technology policy shared by
   every product: corner/scenario names, OCV derate values, DRV limits, CTS
   targets, and library-family naming conventions.
2. `config/products/<soc>.mk` (tracked) — product policy: `TOP`, the canonical
   clock-domain list, qualified-I/O interface groups, PLL mode policy
   (`qualified` or `parked`), and non-sensitive floorplan/timing defaults.
   `tcl/common/products/<soc>.tcl` mirrors it with the product clock overlays
   and I/O port mapping. Adding a product (for example Std/Pro) means adding
   these two files plus one ignored local configuration; the Makefile and the
   shared Tcl do not change.
3. `local/<technology>-<soc>.mk` (ignored) — site values: tool commands and
   LSF queues, Liberty/DB/LEF/GDS/CDL/RC/deck paths, PDK cell lists, routing
   layers, and reviewed I/O timing budgets. Copy the matching
   `config/<technology>-<soc>.example.mk` template and replace every
   `REQUIRED` value.

Run outputs land below `build/commercial/<technology>/<soc>/<run-id>/`. The
`<soc>` path component was added with product parameterization; runs created
at `build/commercial/ics55/<run-id>/` predate it and are not migrated. A
pre-parameterization `local/ics55-production.mk` remains valid for Mini when
passed explicitly through `LOCAL_CONFIG`; rename it to `local/ics55-mini.mk`
to use the default lookup.

## Execution boundary

The development and EDA zones share the repository and build directories
through a site-mounted shared filesystem, but have different responsibilities:

1. In the development zone, generate a production RTL package. For Mini:

   ```sh
   make CONFIG=configs/cluster/ics55.mk \
     HAVE_PLL=YES HAVE_SRAM_IF=YES HAVE_SRAM_MACRO=YES \
     commercial-package
   ```

   For Tiny (the committed `configs/ci/ics55-tiny.mk` profile already carries
   the required PLL/SRAM settings):

   ```sh
   make CONFIG=configs/ci/ics55-tiny.mk commercial-package
   ```

   Both packages carry `rtl/filelist.fl` and the generated
   `rtl/contracts/commercial_timing_contract.tcl`; Tiny additionally carries
   `contracts/tiny_core.sdc` for the smoke STA flow. Packages created before
   the nine-domain Mini clock inventory (2026-08-30) are incompatible with
   the current constraint stack and must be regenerated.

2. In the EDA zone, create the ignored local configuration from the matching
   example template and point `RTL_ARCHIVE` at the generated
   `retrosoc_<product>_sources.tar.gz`. For synthesis with internal timing
   only:

   ```sh
   make -C physical/commercial SOC=MINI doctor-syn
   make -C physical/commercial SOC=MINI RUN_ID=<run-id> syn
   make -C physical/commercial SOC=MINI RUN_ID=<run-id> fm-rtl2syn
   ```

   For production implementation, first populate every interface timing
   budget of the selected product, set `IO_TIMING_QUALIFIED=YES`, and run:

   ```sh
   make -C physical/commercial SOC=MINI RUN_ID=<run-id> doctor
   make -C physical/commercial SOC=MINI RUN_ID=<run-id> signoff
   ```

   `SOC` defaults to `MINI`; `LOCAL_CONFIG` defaults to
   `local/<technology>-<soc>.mk`.

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
- PDK cell lists, routing layers, sites, and power nets;
- reviewed min/max board and external-device I/O timing budgets;
- an audited pad-mode timing hook when the product requires one (Mini does;
  Tiny does not).

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
  -> pv-merge -> pv-drc -> pv-antenna -> pv-lvs -> pv-macro-lvs
```

Each stage writes `log/`, `reports/`, `output/`, a result JSON, and a success
stamp below the run root. A stamp is created only when LSF reports success and
every required output, including the stage verdict marker, exists. Re-running
`signoff` resumes from the first missing stamp. Use `force-<stage>` to rerun
one stage and downstream dependencies; use `clean-stage STAGE=<stage>` for
targeted cleanup.

`pv-macro-lvs` verifies the macros listed in `MACRO_LVS_CELLS` (for example
`PLL_TOP`) individually against `MACRO_GDS`/`MACRO_CDL` with LVS+ERC; with an
empty list the stage records a harmless skip.

## Timing constraint model

Constraints are generated from the canonical per-product inventory
(`rtl/<product>/integration/clock_reset_domains.json` + `pin_map.json`) into
the packaged `commercial_timing_contract.tcl` by
`scripts/generate_timing_contract.py --soc <SOC>`, which rejects any drift
from the product domain list in `config/products/<soc>.mk`. The shared Tcl
(`tcl/common/clocks.tcl`) creates one master clock per source-port domain at
its contract observation and period, a `-divide_by 1` generated clock for
domains derived from another domain, groups clocks by the contract
`async_group`, applies uncertainty/transition from configuration, and
false-paths the canonical reset ports. Product overlays
(`tcl/common/products/<soc>.tcl`) own the rest:

- Mini (`mini.tcl`): the LP root mux is modeled with physically exclusive
  generated clocks — `clk_lp_ext`/`clk_pclk_ext` from the 24 MHz reference
  (bypass) and `clk_lp_pll`/`clk_pclk_pll` from `clk_pll` (PLL performance
  mode, master on `u_rcu/u_clock_reset_subsystem/u_tc_pll/u_PLL_TOP/CKOUT1`).
  Qualified I/O covers JTAG, DVP (GPIO10-20), ULPI, SDRAM, SDIO, XPI, and
  asynchronous pads (UART0/1, remaining GPIO); a reviewed
  `TIMING_IO_MODE_HOOK` is mandatory in qualified mode.
- Tiny (`tiny.tcl`): SAFE24 boot — `clk_system` (external 24 MHz) and
  `clk_jtag` only. The PLL_TOP macro is parked (EN=0), is not a clock source,
  and has no characterized timing arcs yet (see `docs/ip/tiny-soc.md`
  TINY-055); its DB/LEF/GDS/CDL views are still required for link, placement,
  and LVS. Qualified I/O covers JTAG, XPI, and asynchronous pads.

## Legacy-flow parity

This implementation re-expresses the legacy CX55 flow
(DC + Formality + Innovus + StarRC + PrimeTime/PT-ECO + Calibre) and carries
over every capability the legacy project actually exercised on CX55:

- OCV derate policy in PrimeTime per scenario PVT and in Innovus per stage,
  with the legacy per-stage setup uncertainty tightening
  (`flow::apply_signoff_derate`, `flow::apply_apr_derate`,
  `flow::apply_apr_stage_uncertainty` in `tcl/common/corners.tcl`);
- DC compile policy: critical range, high-effort TNS optimization, path
  groups, latch-based clock-gating style with synchronizer exclusion,
  `set_max_area 0`, `set_wire_load_mode top`, macro `set_dont_touch`, and the
  legacy hdlin/suppress-message subset;
- PrimeTime CRPR, signal-integrity analysis settings, the full legacy
  `check_timing` include list, PBA-exhaustive reports, optional SAIF power
  analysis (`STA_SAIF_FILE`), and a configurable SDF scenario
  (`STA_SDF_SCENARIO`);
- Innovus engine settings (OCV analysis, CPPR, postRoute extraction,
  SI/timing-driven routing), per-stage DRV limits, macro preplacement
  (`APR_MACRO_LOC_FILE`) with halos, CTS NDR with trunk shielding and ccopt
  targets, full `streamOut` options, a reviewed pad-order file slot
  (`APR_IO_ORDER_FILE`), and optional multi-power-net mapping
  (`APR_POWER_PIN_MAP`/`APR_GROUND_PIN_MAP`, for example a separate PLL AVDD);
- PrimeTime ECO over all 13 restored DMSA scenarios with merged changes, plus
  optional VT-swap, size-down, and buffer-removal sub-flows
  (`ECO_ENABLE_*`, off by default) and `freeze_silicon` physical mode;
- Calibre merge with an `OTHER_GDS` slot (seal ring), macro-level LVS/ERC,
  and `CALIBRE_LVS_ARGS` performance options.

Capabilities the legacy framework carried but never exercised on CX55 are
deliberately not migrated: DCG/DCNXT physical synthesis (only ever configured
for tsmc28), the Cadence Genus setup (SMIC110 remnant), DFT/scan hooks
(inactive in both flows), UPF low-power, ETM hardening and the hierarchical
harden tree, IP/library preparation helpers (`fake_db.py`, `itf_to_ict.pl`,
`lib2db`, `std_wrapper_gen.py`, `gen_memory.sh`, `timed_run.py`), the legacy
`func/gdsout.tcl` (replaced by the calibredrv merge), `formate_pt2edi.pl`
(replaced by `scripts/translate_eco.py`), the `bes_data_zcn` snapshot, and the
legacy automatic I/O delay decorator (replaced by the `doctor-syn` internal-QoR
mode plus qualified budget review). The legacy multi-design entry points
(`run_syn -d ...`) are superseded by the `SOC` product layer; external
non-retroSoC designs are out of scope.

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
It also requires the product's qualified I/O budgets and, for Mini, an audited
local hook that selects GPIO10-20 DVP input mode and cuts invalid
bidirectional-pad feedback arcs. `doctor-syn` is the only relaxed entry point:
Design Compiler then false-paths all top-level I/O and reports internal
sequential QoR. Its summary carries `io_qualified=no`, and Innovus and
PrimeTime reject it.

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

The common corner contract is:

| PVT | RC views |
| --- | --- |
| `MAX`, `WCL` | `Cworst`, `RCworst` |
| `TYP` | `TYP` |
| `MIN`, `ML` | `Cworst`, `RCworst`, `Cbest`, `RCbest` |

APR, extraction, STA, and ECO scenarios all derive from this single
configuration, and the flow rejects missing views.

## Known gaps and risks

- The APR-and-later stages have not yet executed on any product; only
  `input`, `syn`, and `fm-rtl2syn` have run to completion. Expect first-run
  issues in later stages and retain logs when they surface.
- PLL_TOP ships without characterized timing arcs, so PLL output timing is
  modeled by the product overlays, not by library arcs. Tiny additionally
  parks the PLL (EN=0). Timing closure is mandatory only in the final
  complete-product campaign (`docs/ip/tiny-soc.md` policy).
- Without `APR_IO_ORDER_FILE`, the floorplan stage distributes pads
  round-robin at a fixed pitch; production runs must supply a reviewed pad
  order. The stage records `io_order=file|round_robin` in
  `apr/floorplan/output/floorplan.io.json`.
- The default power hook maps every `APR_POWER_PINS` entry (including the PLL
  analog supplies) onto the single digital power net; use
  `APR_POWER_PIN_MAP`/`APR_GROUND_PIN_MAP` when a separate PLL supply domain
  is required.
