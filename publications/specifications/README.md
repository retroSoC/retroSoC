# Publication specifications and reference data

This directory owns shared publication-only source identities, constructed
models and Typst components. Product catalogs live in
[Tiny parameters](../datasheets/tiny/specifications/parameters.json) and
[Mini parameters](../datasheets/specifications/parameters.json).
Canonical RTL, profiles, topology, pad maps and SDK remain authoritative.
The data layer neither generates registers nor changes product decisions.

## Reading order and navigation

Retain one volume and all existing level-one chapter/IP/register anchors.
The Product Brief contains configuration, applications and a specification/status
quick reference. Put package/pins, connections and electrical/reference
characteristics before the complete peripheral registers. Preserve software,
implementation evidence, historical limitations and global indexes.
The approved 2026-11-14 structure adds the quick reference and reorders package/
electrical sections; future structural changes require reviewed contract updates.

The table directory groups engineering/system/board material and IP register
overviews. Detailed field tables retain numbering, captions and links but are
entered from the IP overview/global address index. Qualify captions with the IP
family, for example SPI / CTRL. Repeated instances retain shared definitions and
their instance-qualified address index.

## Four states and evidence scope

Each record requires a stable product-prefixed ID, product, applicable profile(s),
meaning, group, unit, explicit value, state, conditions, evidence scope, source IDs,
assumptions, input dependencies and replacement conditions.

| State | Permitted meaning | Release rule |
| --- | --- | --- |
| confirmed | Product target, profile or executable design fact | Identify product-target, profile, rtl, simulation or physical evidence. A target is not a silicon rating. |
| calculated | Formula derived only from confirmed/calculated inputs | Record formula, dependency IDs/units and boundary. No benchmark or timing qualification implied. |
| reference | External or constructed illustration | Display REFERENCE ONLY. Record source/model, assumptions and replacement evidence. Dependent outputs inherit this state. |
| tbd | Evidence unavailable | Explicit JSON null. Never substitute zero, an interpolated point or an unrestricted range. |

A scalar is a nominal/value. Min/Typ/Max is an object with all three keys and
nullable missing bounds. Conditions name rail/pad domain, PVT/load, clock/profile,
workload and measurement boundary. Bandwidth uses decimal MB/s; storage uses
B/KiB/MiB. Separate stress limits, recommended operation and typical characteristics.

A model scan is not an operating envelope. WFI/leaf gates do not imply deep sleep,
power isolation, retention or voltage scaling. A signature, behavioral test,
synthesis constraint or functional profile is not a physical rating. Promotion to
simulation/physical evidence requires a report source/hash, revision, profile,
method and conditions. Never relabel historical reports with the current SHA.

## Sources, models and replacement

The shared source catalog records official document title, version, locator,
URL and SHA-256 of the retrieved source. Store downloads only in the ignored
research cache; commit reviewed extracted facts and original drawings. Builds
must not fetch changing web content. Reference vendors supply organization and
engineering expression, not transferred device ratings or qualifications.

The shared model catalog holds current, transfer, GPIO, paste, via, mask and
passive assumptions. Its fingerprint is a source dependency. Product catalogs
identify independent scenarios. Source-bound collectors add facts without
overwriting canonical memory/register/IRQ/pad data.

When real evidence arrives:

1. Review product/profile, physical revision, method, conditions and raw report.
2. Retain the parameter ID; update value/state/evidence and source fingerprint.
3. Review every dependent use in the replacement index. Recompute results and
   replace the applicable model rather than retaining unrelated coefficients.
4. Update prose, tables, curves, captions and markers through that data entry.
5. Rebuild affected books, run negative/numerical/geometry tests, inspect changes
   and retain the old PDF/manifest. Git history retains earlier catalog values.

There is no automatic state promotion. A reference input cannot become a
confirmed/calculated output because its result looks plausible.

## Tables, curves and drawings

Reference examples live in independent blocks within the relevant topic.
Captions, repeated headers and notes identify their state. Curves and standalone
vectors carry the state inside the exported image. Grayscale uses text,
line patterns, markers and hatching rather than color alone.

Use A4, existing Inter/Fira Code hierarchy and gold/gray palette. New labels are
at least 9 pt. Mini's existing 8 pt CDC/Gateway exception remains limited to its
marked cells. Move, wrap or reroute crowded labels rather than shrinking them.
Use consistent units, reference edges, axes, legends, conditions and captions.
Architecture wire labels remain transparent and clear of wires.

CeTZ owns package/connection vectors. Matplotlib 3.10.7 owns numerical curves,
exporting SVG/PDF and CSV. Fix managed Inter font instances, SVG identifiers,
timestamps, physical size and plotting parameters. Each chart needs a technical
purpose. Distinguish payload, wire-rate ceilings and end-to-end throughput.

Connection figures distinguish logical signals, intended package targets and
physical binding. Passive/regulator/reset/strap examples remain reference data
until an approved schematic and pad limits exist. Use each product's real clocks
and shared-pad rules. Tiny QFN64 and SPI routes must not appear as Mini facts.

Implementation errata retain applicable source/version/profile, trigger, impact,
workaround and evidence. Preserve negative STA and failed/unrun gates. These are
implementation/qualification limitations, not manufactured-silicon errata.

## Locked environment and workflows

Use Python 3.10 on Ubuntu 22.04 x86_64 or Python 3.12 on Windows x86_64.
Create an isolated environment, activate it, then install the complete pinned set:

    python -m venv .cache/publication-venv
    python -m pip install --require-hashes -r requirements/publication.txt
    python publications/build_tiny_datasheet.py check --source-only
    python publications/build_datasheet.py check --source-only

The existing setup/build/check entrypoints keep their semantics; --config still
selects publication JSON. Use --typst for the locked compiler when needed.
Normal builds/checks are offline after setup. The publication lock does not
change global Python, firmware, CI or EDA environments.

## Audits and acceptance

Each builder records independent product/configuration/input/data hashes, tool
versions, PDF digest and build records. Exclude the other product's private
sources. Publication-owned text uses LF; binary/managed inputs retain their policy.

Default collection/check validates fingerprints, states, product scope,
dependencies, units, reference inheritance, explicit nulls and replacement rules.
Build resolves actual usage and figure metadata. Retain beside each PDF:

- specification-data, status, usage and replacement JSON indexes.
- characteristics CSV/SVG/PDF plus plot manifest, and engineering SVG/PDF plus
  editable export wrapper, all protected by manifest hashes.
- existing coverage/layout/font/bookmark/link checks and the common
  report_changes.py comparison with the previous delivered PDF.
- full original-scale color/grayscale renders, changed/reflowed page review,
  baseline comparison and offline repeat-build byte comparison.

Run Ruff, complete Pytest, product SDK example syntax checks, dependency and
documentation checks, then git diff --check. Run YAML/Actions/regression-definition
checks if those files change. Preserve failures and unavailable gates.
Publication checks do not close RTL, synthesis, netlist, CDC/RDC, timing,
physical, package, board or silicon acceptance.
