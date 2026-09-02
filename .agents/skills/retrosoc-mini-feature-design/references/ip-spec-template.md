# retroSoC Mini IP Specification Template

Use this structure for `docs/ip/<feature>.md`. Merge sections only when doing
so improves clarity; do not omit a contract area merely because the MVP defers
its implementation.

# [Feature Name]

## Purpose and Research Boundary

State the problem, intended Mini product role, evidence date, authoritative
repository inputs, and claims that the document does not make.

## Commercial References

Compare the smallest set of high-value current references. For each, cover the
problem, architecture, dependencies/activity, reuse candidates, and patterns to
avoid. Link primary sources.

## Requirements and Non-goals

Use stable requirement identifiers when traceability is needed. Separate MVP
requirements, target requirements, and explicit non-goals.

## Selected Architecture

Describe the selection rationale, module hierarchy, data/control flow, resource
ownership, concurrency, backpressure, and recovery boundaries.

## Interfaces

Define the AXI4 data interface, APB4 configuration interface, external pads or
streams, protocol subsets, widths, ordering, alignment, bursts, errors, and
backpressure.

## DMA and Interrupt Contract

Define central/private DMA use, channels or request IDs, descriptors or direct
mode, completion/error events, sticky state, enables, W1C precedence, and IRQ
routing.

## Register and Software ABI

Define the register map, field semantics, reset values, illegal access behavior,
capability/version discovery, handwritten SVH/C mirror, parity test, HAL API,
and compatibility policy. Do not introduce a register generator.

## Clock, Reset, CDC/RDC, and Lifecycle

Name every clock/reset domain, synchronizer or handshake boundary, unilateral
reset behavior, quiesce/flush rules, timeout/isolation behavior, and any
qualified technology dependency.

## Errors, Recovery, Security, and Observability

Define first-error/sticky behavior, abort/reset recovery, counters, snapshots,
debug visibility, access-control assumptions, and claims explicitly excluded
without further evidence.

## MVP and Commercial-grade Roadmap

State the exact MVP, its measurable acceptance criteria, the target
high-performance architecture, and ordered increments between them. Keep
product variants separate when they require materially different verification.

## Verification and Software Validation

Map requirements to directed, randomized, formal, integration, firmware,
protocol, error-injection, and long-duration evidence. Link a separate
`<feature>-verification.md` only when the evidence matrix would dominate this
document.

## Synthesis, Timing, and Physical Evidence

Define the committed profile, clock target, counters or workloads, synthesis
and STA reports, cell/area metrics, CDC/RDC, DFT/MBIST, power/activity, PVT/MMMC,
and post-layout evidence required. Distinguish measured data from targets.

## Development Order

Split the work into small approved phases. Give every phase a stable unique
heading in the form `Phase N - Title`. Do not rename, renumber, or reuse a phase
ID after design freeze; add a new phase when later work must be inserted.

For each phase define scope, dependencies, expected RTL/software/test/doc
changes, integration requirements, validation commands, and objective
completion criteria. State explicitly when a phase changes a public interface,
register ABI, address map, DMA/interrupt allocation, clock/reset boundary, or
CDC/RDC behavior.

## Commercial Delivery Gaps

List missing specification traceability, reusable VIP, coverage closure,
CDC/RDC/DFT evidence, physical signoff, reference software, release artifacts,
qualification, and silicon validation.
