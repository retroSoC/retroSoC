# Canonical Address Map

memory_map.json is the sole source for Mini SoC address ranges. Its generator
emits RTL include definitions, SDK headers, linker memory regions, and the
filelist include path into the selected build variant.

Validate edits with make check-memory-map and the address-map tests before
running an affected simulation.
