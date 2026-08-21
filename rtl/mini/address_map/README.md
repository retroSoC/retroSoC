# Canonical Address Map

memory_map.json is the sole source for Mini SoC address ranges. Its generator
emits RTL include definitions, SDK headers, linker memory regions, and the
filelist include path into the selected build variant.

Validate edits with make check-memory-map and the address-map tests before
running an affected simulation.

The `APB4_CRYPTO` region is fixed at `0x1000c000..0x1000cfff`, routes through
`apb4_periph`, and is management-only. Its hardware/software register ABI is
defined in [the crypto controller contract](../../../docs/ip/crypto.md).
