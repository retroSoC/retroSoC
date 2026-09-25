# Shared RTL IP

This directory owns project RTL IP.

Self-owned IP is grouped by function: interconnect, util, memory, storage,
serial, USB, multimedia, and peripheral. Mini and Tiny select active sources
explicitly in their product filelists.
Source order is part of the build contract. Shared Hazard3/debug wrappers are
in `core`, AXI adapters in `interconnect`, and native AXI SRAM in `memory`.
Both products reference these shared files directly in their own filelists.
Tiny does not select any RIB/RIBP module.

experimental contains retained inactive RTL. It is not included by any active
filelist and must not become a build dependency without an explicit integration
change and matching validation.
