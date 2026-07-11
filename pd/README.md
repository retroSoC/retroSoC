# Physical Design Entry Points

This directory contains physical-design integration entry points. The local
Makefile is reserved for implementation flows that require the selected PDK,
technology collateral, and often site-specific tools.

Generated layout, report, and database outputs must remain outside tracked
source paths. Treat PDK-dependent physical-design results as toolchain-specific
evidence and record the selected profile, PDK, and validation command when
handing off a change. See [Engineering Workflow](../docs/engineering.md).
