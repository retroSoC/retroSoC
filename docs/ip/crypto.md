# AES/SHA-2/RSA Crypto Controller

## Scope and Sources of Truth

The Mini SoC crypto controller is a management-only APB4 peripheral at
`0x1000c000..0x1000cfff`. It provides AES-128/192/256, SHA-224/256, raw
RSA-2048 modular exponentiation, a combined interrupt, PIO access, and central
DMA streaming. The implementation consistently uses `RSA`, not the common
`RAS` transposition.

This document records the commercial reference survey, freezes the current
hardware/software contract, and separates implemented behavior from the
commercialization roadmap. The executable sources of truth are:

- `rtl/ip/security/crypto_*.sv`, `apb4_crypto.sv`, and `crypto_define.svh`;
- `crt/include/retrosoc/hal/crypto_regs.h`, `crypto.h`, and
  `crt/src/hal/crypto.c`;
- `rtl/mini/address_map/memory_map.json` and
  `rtl/mini/integration/soc_topology.json`;
- `tests/test_crypto*.py` and `tests/rtl/crypto_*_tb.sv`.

There is intentionally no register generator. The aligned SystemVerilog macro
table and C header are maintained manually, and
`tests/test_crypto_register_parity.py` checks their shared offsets and fields.

## Commercial Reference Survey

The survey was refreshed on 2026-08-20 from vendor and standards-organization
material. "Active" means that a current product, SDK, or IP page was available
at review time. It does not imply access to vendor RTL, certification evidence,
or implementation details not stated by the vendor.

| Reference | Problem solved and architecture | Dependencies | Activity | Reuse / avoid |
| --- | --- | --- | --- | --- |
| ST STM32H5 AES/SAES, HASH, and PKA | Separates general AES, side-channel-resistant AES with protected key paths, hashing, public-key arithmetic, RNG, and on-the-fly memory decryption. PKA uses Montgomery-domain arithmetic; protected PKA/SAES operations consume RNG services. | System bus, DMA, RNG, TrustZone/security attribution, protected/derived key paths, HAL and security lifecycle. | Active; ST published current [STM32H5 crypto training](https://www.st.com/content/ccc/resource/training/technical/product_training/group1/18/b1/c0/01/3b/7c/4b/59/STM32H5-Security-Crypto/files/stm32h5-security-crypto-crypto.pdf/jcr%3Acontent/translations/en.stm32h5-security-crypto-crypto.pdf) and [STM32H5F5 documentation](https://www.st.com/resource/en/datasheet/stm32h5f5vj.pdf). | Reuse the independent engines, Montgomery arithmetic, protected-key boundary, zeroization, and explicit RNG dependency for SCA claims. Avoid claiming protection merely because software cannot read a key register. |
| Espressif ESP32-S3 AES/SHA/RSA and Digital Signature | General accelerators serve software crypto, while the Digital Signature block keeps RSA private parameters encrypted in flash and derives their unwrap key in hardware from HMAC/eFuse material. Software never sees the signing private key. | eFuse root, HMAC, AES unwrap, RSA engine, secure boot/flash encryption, ESP-IDF or PSA/mbedTLS integration. | Active in the current [ESP32-S3 Digital Signature guide](https://docs.espressif.com/projects/esp-idf/en/stable/esp32s3/api-reference/peripherals/ds.html) and [security guide](https://docs.espressif.com/projects/esp-idf/en/latest/esp32s3/security/security.html). | Reuse opaque key handles and a composed key ladder in a later revision. Avoid raw private-key staging as the final product model and avoid forcing every application to orchestrate several blocks safely. |
| NXP EdgeLock CAAM | A descriptor/job-ring front end schedules multiple cipher, hash, public-key, RNG, and protocol engines. Integrated DMA, secure memory, key blobs, access domains, and multiple job rings target TLS, IPsec, storage, and virtualization rather than single blocking register calls. | AXI/system fabric, descriptor memory, DMA/IOMMU or domain IDs, secure RAM, entropy, key provisioning, Linux/RTOS drivers. | Active in NXP's current [EdgeLock accelerator portfolio](https://www.nxp.com/docs/en/training-presentation/NXP-Security-Solutions-Protecting-the-Edge-at-scale-Technology-Six-Pack.pdf). | Reuse capabilities, queued jobs, independent engines, DMA, domain isolation, and wrapped keys as the scale-up architecture. Avoid importing descriptor complexity before ownership, coherency, cancellation, and fault containment are specified. |
| Renesas RA SCE9 | Protected mode binds wrapped application keys to a hardware unique key; compatibility mode exposes PSA/FSP APIs. The engine covers AES modes, SHA-224/256, RSA-2048 private/public operations, larger public RSA, ECC, HMAC, KDF, key wrap, and conditioned random generation. | HUK and key-injection flow, secure region, TRNG/DRBG, PSA/FSP middleware, lifecycle and debug controls. | Active; the 2025 [RA6M5 Security Manual](https://www.renesas.com/en/document/apn/ra6m5-mcu-group-security-manual) documents SCE9 operation and key handling. | Reuse protected/compatibility modes, a stable high-level API, wrapped keys, and lifecycle-aware provisioning. Avoid making plaintext-key compatibility mode the default security story. |
| Nordic nRF52840 CryptoCell 310 | A security subsystem combines AES, SHA/HMAC, RSA/ECC, random generation, derived keys, and DMA behind a vendor runtime library. It solves crypto offload and root-of-trust services as one subsystem rather than unrelated accelerators. | SRAM DMA, CryptoCell runtime/SDK, device root key, random source, secure boot policy. | Active in the current [nRF52840 specification](https://docs.nordicsemi.com/r/bundle/ps_nrf52840/page/cryptocell.html) and product documentation. | Reuse a supported driver boundary, capability discovery, derived-key model, and integrated self-test. Avoid relying on undocumented registers or treating the hardware primitive as a complete protocol implementation. |
| Rambus crypto accelerator IP | Offers separately configurable AES, hash/HMAC, public-key, DMA-enabled, DPA-resistant, and FIA-resistant cores with different area/performance points and validation options. This exposes the commercial need for parameterized deliverables and independently evidenced security claims. | Licensed IP flow, target technology characterization, entropy/masking for protected variants, integration wrappers, CAVP/certification packages. | Active in the current [Rambus Crypto Accelerator IP catalog](https://www.rambus.com/security/crypto-accelerator-cores/). | Reuse the product-family approach, explicit PPA/security variants, hardening options, and validation deliverables. Avoid a single undocumented implementation being marketed for every threat model. |

The most relevant architectural combination is ST's independent primitive
engines, NXP's DMA/job separation, and Espressif/Renesas protected-key model.
The current Mini SoC uses the first two at MVP scale: independent engines, a
stable control ABI, sticky interrupt/error state, and central DMA. Opaque key
slots, a key ladder, entropy-backed masking, descriptor queues, AEAD, and
certification evidence remain explicit future work.

## Selected Architecture

```text
 management APB4 (0x1000c000)
              |
       +------+--------------------+--------------------+
       | register / policy / IRQ   |                    |
       | secret read protection    |                    |
       +---------+-----------------+--------------------+
                 |                 |                    |
          +------v------+   +------v------+      +------v------+
          | AES engine  |   | SHA-2 engine|      | RSA-2048   |
          | key schedule|   | padding     |      | Montgomery |
          | ECB/CBC/CTR |   | 64 rounds  |      | modexp     |
          +---+------+--+   +------+------+
              |      |             |
       output |      +------ input-+
              |             |
          AXI4-Stream input/output
              |             |
        central DMA channels 4/5
        request IDs 12/13
```

The APB4 plane is for configuration, status, PIO, and RSA operand windows. The
32-bit AXI4-Stream plane is internal to the SoC and connects to the existing
central DMA. AES and SHA can operate concurrently through PIO; they arbitrate
the one crypto DMA input, and only AES produces the crypto DMA output stream.
RSA has a private 32-bit-limb datapath and does not occupy the stream path.

The production Mini instance expands the DMA from four to six channels.
Channels 4 and 5 are reserved for crypto input and output so a bidirectional
AES transaction cannot deadlock by competing for the legacy bulk channel.
The reusable DMA module default remains four channels for existing standalone
users.

The controller is management-only. The address map denies the user core any
access, the aggregate peripheral interrupt is group bit 18/core IRQ23, and the
DMA aggregate remains IRQ20.

## Implemented MVP

| Area | Implemented behavior | Deliberate limit |
| --- | --- | --- |
| AES | FIPS 197 AES-128/192/256, encryption/decryption, ECB/CBC/CTR, expanded-key retention, 8-word input and output FIFOs, PIO and DMA, partial final CTR word. | ECB/CBC length must be a multiple of 16; no GCM/CCM/XTS/CMAC; no entropy-backed masking. |
| SHA-2 | SHA-224 and SHA-256 compression, streaming input, hardware FIPS 180-4 padding including empty and two-padding-block cases, PIO and DMA input. | Digest is read through APB; no SHA-384/512, HMAC, context save/restore, or multi-context scheduler. |
| RSA | Raw 2048-bit modular exponentiation, modulus preparation, 32-bit-limb CIOS Montgomery multiply, variable-length public exponent, fixed-window private operation, result registers. | Exactly 2048-bit modulus at the wrapper; no PKCS #1 encoding, CRT, blinding, key generation, or smaller/larger keys. Protocol padding belongs in reviewed software. |
| Control | APB4 errors, busy-time write protection, byte strobes for stream tails, sticky W1C IRQ/error state, IRQ test, abort, zeroize, cycle/byte/progress counters. | One APB command at a time; no command queue or virtual contexts. |
| Key handling | AES and RSA exponent write windows are unreadable and return `PSLVERR`; zeroize clears keys, operands, internal round keys, hash state, FIFOs, Montgomery temporaries, results, and valid state. | Plaintext keys still cross APB and live in ordinary flops. There is no HUK, wrapped-key import, anti-tamper input, retention domain, or key-slot ACL. |

AES uses one full round per cycle after key expansion. Key schedules require 40,
46, or 52 expansion cycles for 128-, 192-, or 256-bit keys; block operations
require 10, 12, or 14 round cycles plus engine/FIFO handshakes. SHA-2 performs
one of 64 compression rounds per cycle. These are architectural counts, not a
frequency or throughput claim; post-synthesis `CYCLES` and regression metrics
are the signoff sources.

RSA first derives `-N^-1 mod 2^32` and `R^2 mod N` in hardware. Public work
scales with exponent bit length and population count. The one-time `R^2`
preparation uses 32-bit limb-serial compare/subtract steps so it does not place
a 2048-bit carry chain in one cycle; for a 2048-bit modulus its upper bound is
528,389 cycles including the inverse seed. Prepared state can then be reused
for subsequent operations with the same modulus. Private work always processes
all 1024 two-bit windows with two squarings and one multiply per window,
regardless of the exponent value. It then verifies the candidate with public
exponent 65537 and reports an error instead of releasing a mismatched result.
The fixed schedule reduces simple timing leakage but is not a DPA/FIA claim;
table selection, datapath activity, physical implementation, and fault coverage
still require dedicated hardening and lab evaluation.

## Data and Operation Contract

- AES and SHA stream bytes are in little-endian APB/AXI word lanes: lane 0 is
  the earliest byte. `KEEP`/`PSTRB` must be `0001`, `0011`, `0111`, or `1111`.
- AES key and IV register 0 holds the first four bytes supplied by the API.
  The core converts them to the FIPS byte ordering internally.
- SHA digest word 0 is the most significant digest word. SHA-224 returns seven
  meaningful words; digest word 7 is zero.
- RSA operands are arrays of 64 little-endian 32-bit limbs. Word 0 is least
  significant. A modulus must be odd and have bit 2047 set; the base must be
  less than the prepared modulus.
- A public RSA command uses `RSA_CFG.EXPONENT_BITS` in the range 1..2048. A
  private command always processes 2048 exponent bits and assumes the paired
  public exponent is 65537 for mandatory result verification.
- Software must wait for AES `KEY_STATUS.VALID` after `KEY_CTRL.COMMIT`.
  `KEY_STATUS.BUSY` and `AES_STATUS.BUSY` cover key expansion.
- `STATUS.DONE` is sticky through the corresponding IRQ state bit and is
  cleared by a new command or W1C `IRQ_STATE`; result/digest valid remains
  asserted until a new command, abort, zeroize, or reset.
- A malformed, misaligned, read-only write, secret read, busy-time
  configuration write, FIFO underflow/overflow, or illegal command returns
  APB `PSLVERR` and latches `ERROR_STATUS.ACCESS`.

The HAL provides AES PIO, AES DMA, SHA-224/256 PIO, RSA prepare/modexp,
zeroize, and an AES/SHA known-answer self-test. DMA buffers and lengths must be
4-byte aligned and non-overlapping. AES PIO supports an arbitrary CTR tail;
the DMA API deliberately rejects partial words. Hardware accepts SHA DMA input,
but a public SHA DMA HAL call is deferred until timeout ownership and digest
completion semantics are covered end to end.

## APB4 Register ABI

All registers are 32-bit and require word-aligned accesses. Multiword arrays
advance by four bytes. `RO/W1C` means read current sticky state and write one to
clear.

| Offset | Register | Access | Purpose |
| ---: | --- | --- | --- |
| `0x000` | `IP_ID` | RO | `0x43525950` (`CRYP`) |
| `0x004` | `IP_VERSION` | RO | `0x00010000` |
| `0x008` | `CAPABILITY0` | RO | Algorithm, DMA, control, and security feature bits |
| `0x00c` | `CAPABILITY1` | RO | RSA bits `[31:16]`, DMA width `[15:8]`, APB width `[7:0]` |
| `0x010` | `COMMAND` | WO | bit 0 zeroize; bits 1..3 abort AES/SHA/RSA |
| `0x014` | `STATUS` | RO | busy bits 0..2, AES key valid bit 8, RSA prepared bit 9 |
| `0x018` | `IRQ_STATE` | RO/W1C | AES done, SHA done, RSA done, error, zeroized |
| `0x01c` | `IRQ_ENABLE` | RW | IRQ enable mask |
| `0x020` | `IRQ_TEST` | WO | set selected sticky IRQ bits |
| `0x024` | `ERROR_STATUS` | RO/W1C | AES, SHA, RSA, and APB access errors |
| `0x100` | `AES_CTRL` | WO | start |
| `0x104` | `AES_CFG` | RW | mode `[1:0]`, decrypt bit 2, key size `[5:4]`, DMA bit 8 |
| `0x108` | `AES_STATUS` | RO | busy, done, error, key valid |
| `0x10c` | `AES_LENGTH` | RW | message bytes |
| `0x110` | `AES_DATA_IN` | WO | PIO stream word; `PSTRB` is byte keep |
| `0x114` | `AES_DATA_OUT` | RO | PIO result word; read pops FIFO |
| `0x118` | `AES_DATA_STATUS` | RO | input ready, output valid, output last |
| `0x11c` | `AES_BYTES_IN` | RO | accepted input bytes |
| `0x120` | `AES_BYTES_OUT` | RO | consumed output bytes |
| `0x124` | `AES_CYCLES` | RO | operation cycles |
| `0x128` | `AES_KEY_CTRL` | WO | commit staged key |
| `0x12c` | `AES_KEY_STATUS` | RO | valid bit 0, expansion busy bit 1 |
| `0x140..0x15c` | `AES_KEY[0..7]` | WO | staged key; reads fail |
| `0x160..0x16c` | `AES_IV[0..3]` | RW | IV or initial counter |
| `0x170..0x17c` | `AES_CHAIN[0..3]` | RO | current CBC chain/counter observation |
| `0x200` | `SHA_CTRL` | WO | start |
| `0x204` | `SHA_CFG` | RW | SHA-256 bit 0, DMA bit 8; clear bit 0 selects SHA-224 |
| `0x208` | `SHA_STATUS` | RO | busy, done, error, digest valid |
| `0x20c..0x210` | `SHA_LENGTH` | RW | 64-bit message byte length, low word first |
| `0x214` | `SHA_DATA_IN` | WO | PIO stream word; `PSTRB` is byte keep |
| `0x218` | `SHA_DATA_STATUS` | RO | input ready and digest valid |
| `0x21c..0x220` | `SHA_BYTES_IN` | RO | 64-bit accepted-byte count |
| `0x224` | `SHA_CYCLES` | RO | operation cycles |
| `0x240..0x25c` | `SHA_DIGEST[0..7]` | RO | big-endian digest words |
| `0x300` | `RSA_CTRL` | WO | one-hot prepare, public, or private command |
| `0x304` | `RSA_CFG` | RW | public exponent bit length `[11:0]` |
| `0x308` | `RSA_STATUS` | RO | busy, done, error, prepared, result valid |
| `0x30c` | `RSA_CYCLES` | RO | current/last operation cycles |
| `0x310` | `RSA_PROGRESS` | RO | private flag and exponent position |
| `0x400..0x4fc` | `RSA_MODULUS[0..63]` | RW | little-endian modulus limbs |
| `0x600..0x6fc` | `RSA_EXPONENT[0..63]` | WO | little-endian exponent; reads fail |
| `0x800..0x8fc` | `RSA_BASE[0..63]` | RW | little-endian input limbs |
| `0xa00..0xafc` | `RSA_RESULT[0..63]` | RO | little-endian result limbs |

`CAPABILITY0` bits 0..7 describe AES-128/192/256, decrypt, ECB, CBC, CTR,
and DMA. Bits 8..11 describe SHA-224, SHA-256, hardware padding, and DMA.
Bits 12..15 describe RSA-2048, public, private, and private-result verify.
Bits 16..23 describe PIO, interrupt, zeroize, secret-read protection,
concurrent engines, counters, APB errors, and central DMA. Unknown capability
bits must be ignored by software.

## Security Boundary and Claims

The MVP provides useful logical controls: management-only address decoding,
no key/exponent readback, busy-time configuration rejection, sticky error
reporting, deterministic private-RSA scheduling, post-operation RSA checking,
abort, and synchronous zeroization. Reset and zeroize drive all self-owned
secret-bearing state to zero; FIFOs are flushed.

It is not a secure element and makes no resistance claim against DPA, EM
analysis, clock/voltage/laser fault injection, invasive probing, scan access,
cold-boot/retention attacks, or a compromised management core. Synthesis can
optimize zeroized flops or expose sensitive scan paths unless implementation
constraints preserve the security intent. Product documentation must not use
"side-channel resistant", "tamper resistant", "FIPS validated", or similar
language until the matching implementation and independent evidence exist.

RSA is a raw integer primitive. The HAL does not implement RSAES-OAEP,
RSASSA-PSS, or PKCS1-v1_5 encoding from RFC 8017. Application code must not
use textbook RSA directly for messages or signatures.

## Commercial IP Alignment

| Delivery area | MVP evidence | Commercial release gate |
| --- | --- | --- |
| Functional specification | Frozen algorithm, stream, APB, interrupt, error, zeroize, and data-order contract in this document. | Add versioned requirements with bidirectional traceability to tests and RTL assertions. |
| Algorithm correctness | NIST known-answer vectors for AES key sizes/modes and SHA-224/256 cases; RSA/Montgomery directed vectors. | Run NIST ACVP/CAVP vector sets, randomized differential tests against a qualified library, corner lengths, and long RSA campaigns. |
| Protocol verification | APB error/read-protection/IRQ/zeroize tests and DMA backpressure endpoint test. | Constrained-random APB/stream agents, coverage closure, simultaneous-engine stress, abort/reset at every state, and AXI/DMA fault injection. |
| Security verification | Secret reads fail; all secret state has explicit zeroize; private RSA has a fixed operation schedule and public recheck. | Information-flow/noninterference checks, gate-level zeroize audit, scan/DFT policy, formal fault properties, TVLA/leakage assessment, and FIA campaign. |
| PPA/performance | Cycle counters and IHP130 synthesis/STA regression hooks. | Freeze frequency/area/power corners, publish reproducible benchmark sizes, and close timing with physical synthesis and extracted parasitics. |
| Integration | Manual RTL/C parity check, public HAL, address/IRQ topology tests, central-DMA endpoints. | UVM or equivalent reusable VIP, integration checklist, CDC/RDC/DFT constraints, UPF if power gated, firmware reference driver, and release example. |
| Release package | Synthesizable RTL, tests, HAL, and documentation in repository. | Versioned encrypted/plain source policy, file lists, lint/CDC/RDC/formal reports, coverage database, waiver register, synthesis scripts, SDC, integration guide, release notes, and support matrix. |

No MISRA deviation is introduced by the HAL. Automated repository policy is
only a mechanical subset of MISRA C:2012 Amendment 2 and is not a certification.

### IHP130 implementation evidence

The 2026-08-21 PR regression used the committed IHP130 profile at 72 MHz and
completed RTL simulation, synthesis, netlist boot simulation, OpenSTA, warning
review, and metric collection. The synthesized SoC contains 793,473 cells with
an estimated top-level area of 14,054,459.83 square micrometres. These numbers
are comparison data for this repository configuration, not a hard-macro PPA
commitment.

Focused post-synthesis timing queries separate crypto datapath evidence from
known whole-SoC reset and high-fanout limitations:

| Query | Slow-corner slack | Interpretation |
| --- | ---: | --- |
| AES round core | +1.23 ns | Meets the 72 MHz smoke target. |
| RSA limb-serial `R^2` preparation | +6.02 ns | Meets after removal of the single-cycle 2048-bit compare/subtract path. |
| SHA-256 compression core | -1.80 ns | The current indexed message-schedule write decoder is the critical path. |
| Montgomery MAC data registers | -1.05 ns | The 32x32 multiply/add path needs a pipeline or carry-save cut for margin. |

The repository-wide OpenSTA WNS is -2687.45 ns and is dominated by existing
reset-distribution and unconstrained high-fanout effects. A broader Montgomery
query similarly reports -47.20 ns through state/control fanout, while its
isolated arithmetic path is the -1.05 ns result above. Neither number is a
crypto signoff result. Commercial release still requires placed-and-routed,
extracted-corner timing with reset, generated clocks, false paths, multicycle
paths, and maximum-fanout intent reviewed by the integration owner.

## Performance and Security Optimization Roadmap

The current design is a balanced, low-integration-risk baseline. Optimize only
from measured IHP130 synthesis/STA/power data and preserve a small reference
configuration for equivalence and regression.

1. Harden the current interface. Add formal APB assertions, stable result
   properties, zeroize/abort reachability, FIFO conservation, and independent
   AES/SHA/RSA concurrency coverage. Add ACVP vector import and a software
   differential harness before changing datapaths.
2. Improve AES throughput. Parameterize 4/8/16 S-box organizations and one-,
   two-, or fully unrolled round pipelines. Register S-box/MixColumns cut
   points when STA shows the table-to-mix path is critical. Add a dual-buffered
   key context so expansion overlaps the preceding transfer. Do not share one
   S-box across all bytes in the high-throughput SKU.
3. Add authenticated symmetric modes. Implement GHASH with a parameterized
   32/64/128-bit multiplier, then GCM/GMAC; add CMAC and CCM only with complete
   length/AAD/tag error contracts. Never release unauthenticated plaintext on
   tag failure in a protected API.
4. Scale SHA. Add SHA-384/512 with a 64-bit datapath variant, HMAC with inner/
   outer state isolation, context save/restore, and two context banks. First
   replace the indexed SHA-256 schedule ring with a shift schedule so the round
   counter does not decode onto the schedule write path. A two-round-per-cycle
   option is reasonable only after the one-round implementation closes the
   target timing with margin.
5. Improve RSA performance. Parameterize the Montgomery limb multiplier for
   one, two, or four 32x32 MAC lanes; add a registered multiply stage,
   carry-save accumulation, banked operand SRAM, and locally registered control
   enables to bound fanout. Add CRT for private RSA only after `p`, `q`, `dP`,
   `dQ`, and `qInv` receive protected storage, recombination checks,
   exponent/base blinding, and fault-response verification. Support 3072/4096-
   bit public RSA as separate configurations rather than silently widening
   every product.
6. Replace plaintext keys. Add opaque key slots, HUK-derived unwrap, wrapped
   key import, per-slot usage policy, lifecycle/debug gating, anti-rollback
   metadata, and a secure erase acknowledgement. Feed masking/blinding from a
   conditioned TRNG/DRBG with health-test status; fail closed when entropy is
   required but unavailable.
7. Add scheduling only when needed. A small command FIFO with immutable
   descriptors and per-job completion is preferable before a CAAM-scale shared
   memory ring. A memory descriptor design requires IOMMU/domain ownership,
   cache coherency, TOCTOU protection, cancellation, and error containment.
8. Close physical security. Define DFT exclusions or secure scan, clock/reset
   glitch monitors, duplicated control/FSM checks, parity/ECC on key memories,
   synthesis preservation for zeroize, placement constraints for masked logic,
   power-intent behavior, and post-layout leakage/fault validation.

The recommended product variants are `compact` (iterative AES/SHA and one RSA
MAC), `balanced` (current control plane with parallel Montgomery MACs and GCM),
and `throughput` (pipelined AES/GHASH, multi-context SHA, descriptor DMA). DPA/
FIA-protected variants are separate security products, not compile-time labels
on the same unassessed netlist.

## Development and Verification Order

The implemented sequence followed the lowest-risk dependency order:

1. Freeze standards, byte order, APB address, IRQ, error, and zeroize semantics.
2. Verify standalone AES, SHA-2, Montgomery, and RSA primitives with known
   answers, including AES decrypt and SHA padding boundaries.
3. Add streaming FIFOs, CBC/CTR chaining, SHA padding, counters, and abort.
4. Add the APB wrapper, manual RTL/C parity check, key read protection, sticky
   interrupts, and error behavior.
5. Add DMA request IDs 12/13 and dedicated production channels 4/5; verify
   backpressure independently before SoC integration.
6. Integrate slot 19 at `0x1000c000`, peripheral group bit 18/core IRQ23, the
   HAL, and firmware self-test.
7. Run format/style, software policy/host tests, firmware build, behavioral
   simulation, IHP130 synthesis/netlist/STA regression, warning review, and
   metric collection.

New feature work should keep this order: update the written contract and
capability bit, add primitive/differential tests, implement the datapath, add
protocol and negative tests, expose the HAL, then run full physical regression.

## Standards Baseline

- [NIST FIPS 197, Advanced Encryption Standard](https://csrc.nist.gov/pubs/fips/197/final)
- [NIST SP 800-38A, Block Cipher Modes](https://csrc.nist.gov/pubs/sp/800/38/a/final)
- [NIST FIPS 180-4, Secure Hash Standard](https://csrc.nist.gov/pubs/fips/180-4/upd1/final)
- [RFC 8017, PKCS #1 v2.2](https://www.rfc-editor.org/rfc/rfc8017)

The AES primitive follows FIPS 197, ECB/CBC/CTR follow SP 800-38A, and SHA-224/
256 follows FIPS 180-4. RSA hardware implements only the modular-arithmetic
primitive used underneath RFC 8017 schemes; it does not itself claim RFC 8017
conformance.
