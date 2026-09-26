# AES/SHA-2/RSA Crypto Controller

## Scope and Sources of Truth

The Mini SoC crypto controller is a management-only APB4 peripheral at
`0x1000c000..0x1000cfff`. It provides AES-128/192/256, SHA-224/256, raw
RSA-2048 modular exponentiation, a combined interrupt, PIO access, and central
DMA streaming. The implementation consistently uses `RSA`, not the common
`RAS` transposition.

This document records the commercial reference survey and the 2026-09-25
macro-first storage refreeze. The refreeze is an approved implementation
requirement, not a claim that the current RTL already contains Crypto SRAM
macros. Revision `92830d963da2f1e39bb219c0d377bc4889c07755` is the pre-refreeze
baseline. The V2 storage, initialization, cycle and zeroization requirements
below supersede the corresponding V1 implementation behavior. Algorithms,
numerical results and existing system allocations remain fixed.

The executable sources of truth for the baseline are:

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

The production Mini instance currently has eight DMA channels. Channels 4
and 5 remain reserved for crypto input and output so a bidirectional AES
transaction cannot deadlock by competing for the legacy bulk channel. The
storage refreeze does not change the channel count or ownership; see
[DMA V2](dma.md).

The controller is management-only. The address map denies the user core any
access, the aggregate peripheral interrupt is group bit 18/core IRQ23, and the
DMA aggregate remains IRQ20.

## V1 Implemented Baseline

This section describes the pre-refreeze RTL. V2 keeps the listed algorithms
and transfer capacities, but replaces table/operand storage, initialization,
round timing and erasure completion as specified below.

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

## Existing APB4 Register ABI

All registers are 32-bit and require word-aligned accesses. Multiword arrays
advance by four bytes. `RO/W1C` means read current sticky state and write one to
clear.

| Offset | Register | Access | Purpose |
| ---: | --- | --- | --- |
| `0x000` | `IP_ID` | RO | `0x43525950` (`CRYP`) |
| `0x004` | `IP_VERSION` | RO | V1 baseline `0x00010000`; V2 refreeze `0x00020000` |
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

## V2 Macro-first Storage Contract

### Requirements and non-goals

The feature slug remains `crypto`. These requirements replace storage and
latency, not AES/SHA/RSA algorithms. The first physical acceptance profile is
`configs/ci/ihp130.mk`, with `HAVE_SRAM_MACRO=YES` and `PDK_BEHAV=NO` for
synthesis. Existing non-macro profiles retain functional compatibility through
synchronous behavioral RAMs with the same initialization and transactions.

| Requirement | Normative contract |
| --- | --- |
| `CRYPTO-SRAM-001` | Macro builds MUST replace all indexed algorithm ROMs, AES expanded-key RAM, SHA schedule RAM and Montgomery temporary RAM with physical SRAM wrappers. No runtime S-box, inverse S-box, Rcon or SHA K lookup may remain as an inferred ROM, giant case/mux table or register copy. |
| `CRYPTO-SRAM-002` | RSA staged operands, retained Montgomery values, exponent/window tables, preparation workspace and results MUST use limb-addressed SRAM. Moving unpacked arrays to packed vectors is not an acceptable memory reduction. |
| `CRYPTO-SRAM-003` | Preserve AES-128/192/256 encrypt/decrypt ECB/CBC/CTR, partial CTR tails, SHA-224/256 padding, RSA-2048 preparation/public/private operations, result verification, capacities, byte order and exact outputs. |
| `CRYPTO-SRAM-004` | Preserve AES/SHA PIO concurrency and RSA independence, the existing 32-bit stream subset, central-DMA channels 4/5 and requests 12/13, management-only access, APB base and LP IRQ23. No private AXI master, descriptor ABI, resource-controller slot, new pad, clock or CDC is allocated. |
| `CRYPTO-SRAM-005` | Use synchronous, one-port-per-bank reads/writes and bounded microsteps. The old AES/SHA one-round-per-cycle guarantee is superseded by the cycle limits below. No memory multi-pumping, falling-edge access or software crypto fallback. |
| `CRYPTO-SRAM-006` | Constants MUST be initialized through the public LP interface, validated by SRAM readback and locked before any engine starts. No synthesizable initial/readmemh preload or hardware ROM fallback. |
| `CRYPTO-SRAM-007` | Reset, zeroize, abort and faults MUST revoke valid state and prevent stale results. Physical clearing MUST finish before successful erasure acknowledgement. Private-RSA scheduling MUST remain independent of exponent value. |
| `CRYPTO-SRAM-008` | Only the three existing bounded stream FIFOs may remain inferred memories: AES input/output 8x37 each and SHA input 16x37, 1184 bits total. These FIFOs are an explicit exception, not newly macro-backed storage. |
| `CRYPTO-SRAM-009` | Qualify macro counts, inferred storage, remaining register bits, cycle bounds, synthesis time, peak RSS and STA using like-for-like artifacts; do not infer a speedup from the bit count. |

Fixed-width arithmetic constants, the active AES 128-bit round state, SHA's
eight 32-bit working words, scalar carries, counters, FSM state, short operand
and response registers may remain in flops. They MUST be individually reported
with widths and purpose. This allowance cannot retain an AES key-schedule copy,
SHA schedule array, 2048-bit RSA operand/result snapshot or predecoded table.
Preserve the FIFO depths; widening or adding inferred FIFOs needs another
reviewed contract. Software tables in the boot image and verification oracles
are permitted and are not hardware ROM implementations.

AEAD/HMAC, new key sizes, CRT, masking/blinding, HUK/key ladders, Linux crypto
drivers, private DMA, ECC/MBIST/secure scan and side-channel certification remain
deferred. Vexii and APU storage are outside this refreeze.

### Physical layout and implementation boundary

Instantiate exactly six dedicated `tc_sram_1024x32` wrappers (24 KiB physical
capacity). Each resolves to one `RM_IHPSG13_1P_1024x32_c2_bm_bist` in the locked
IHP130 PDK. Reuse `rtl/tech/tc_sram.sv`, its masks and model semantics; do not
edit the PDK or managed Common. GF180/SKY130 use the existing wrapper mappings;
their physical-cell counts differ and require separate qualification. With
`HAVE_SRAM_MACRO=NO`, infer the same six synchronous banks explicitly, without
claiming ASIC memory reduction. An enabled but unavailable macro mapping MUST
fail elaboration rather than silently becoming flops or an undriven cell.

All addresses in the following tables are 32-bit word rows, inclusive. Unused
rows are reserved, initialized/cleared as specified and never aliased to another
engine. This capacity is private storage, not a new software-addressable SRAM
window or a reduction of existing algorithm limits.

| Bank | Owner | Fixed allocation |
| ---: | --- | --- |
| 0 | AES constants | Rows 0..255 forward S-box; 256..511 inverse S-box; 512..527 Rcon[0..15]; values in bits 7:0, upper bits zero; 528..1023 zero padding. |
| 1 | SHA constants | Rows 0..63 K[0..63]; 64..71 SHA-224 initial state; 72..79 SHA-256 initial state; 80..1023 zero padding. |
| 2 | AES mutable | 0..7 staged key; 16..75 expanded key; 80..83 IV; 84..87 chain/counter; 88..91 input block; 92..95 output block; all other rows reserved zero. |
| 3 | SHA mutable | 0..15 schedule ring; 16..31 block/padding buffer; 32..39 chaining state; 40..47 compression initial state; 48..55 digest; all other rows reserved zero. |
| 4 | RSA retained | Sixteen 64-word slots, detailed below. |
| 5 | RSA arithmetic | 0..63 Montgomery left; 64..127 right; 128..191 modulus; 192..256 accumulator (65 limbs); 257..320 subtracted candidate; 321..384 product; 385..449 preparation double (65 limbs); 450..513 preparation subtraction; remaining rows reserved zero. |

RSA bank 4 slot `s` occupies rows `64*s..64*s+63`, least-significant limb
first. Slots 0..13 are, respectively: modulus, exponent, base, released result,
R-squared, Montgomery one, Montgomery base, running Montgomery result, window
table 2, window table 3, private candidate, verification Montgomery base,
preparation modulus, and copy workspace. Slots 14..15 are reserved zero.
Upper unused bits of a 65th limb MUST be cleared. Explicit SRAM-to-SRAM copies
are allowed; full-vector shadow registers are not.

AES staged-key/IV words retain APB little-endian byte lanes. Internal expanded
key and round/block words use the baseline FIPS byte ordering; conversion occurs
at the engine boundary, not by changing the register ABI. SHA schedule/block
words represent big-endian message words, and SHA state/digest slots keep the
existing most-significant-word-first convention. Test these conversions
independently of the image generator.

The owned implementation boundary is a private bank store plus initialization/
scrub controller under `apb4_crypto`, with independent AES, SHA and RSA clients.
The RSA core and Montgomery interface become limb transactions; their existing
wide internal ports are not a software ABI. Use Common register/handshake
primitives where their reset/enable semantics fit. Each bank accepts at most
one access per PCLK edge; responses are registered and tagged with the owning
operation epoch. A client advances only after retirement, holds an unaccepted
request stable and never consumes the macro output during a write.

AES and SHA have separate constant and mutable banks and need no mutual
arbitration. RSA serializes accesses within its own two banks. Scalar response
holding registers handle backpressure without rereading a mutable address.
No read-during-write behavior is assumed, and no extra unbounded queue is
introduced. Legal APB access owns the corresponding idle engine bank until
retirement; operating engines retain the existing busy-time write restrictions.
Reset/scrub has priority over all ordinary traffic in the banks it owns.

### Constant image and boot initialization

The `CRYC1` layout identifier is `0x43525901`. Its payload is exactly 8192
bytes: all 1024 little-endian words of bank 0, followed by all 1024 words of
bank 1, with no header. S-boxes and SHA constants equal the baseline algorithms.
Rcon rows contain zero at indices 0 and 15, and successive AES xtime powers
starting with 1 for indices 1..14, matching the baseline helper. SHA initial
states use the standard most-significant digest-word-first ordering within
their eight-word ranges.

Freeze-time parsing of the baseline tables, inverse-S-box consistency checking
and independent packing produced these identities (artifact identity only,
not synthesized-hardware evidence):

| Identity | Value |
| --- | --- |
| Payload bytes / words | 8192 / 2048 |
| CRC32/ISO-HDLC | `0x99ca52fe` |
| SHA-256 | `b662a0729bf85789aa9c9bd4a9f8a13ebe44e296deebda486bef2792b1e9d47f` |

The CRC uses reflected polynomial `0xedb88320`, initial/final XOR
`0xffffffff`, and low byte first per word. Hardware checks the fixed CRC,
not a caller-supplied expected checksum. CRC detects corruption; it does not
authenticate compromised firmware or provide runtime SRAM fault protection.
The trusted LP boot image owns initialization. A deterministic host generator
and a separately implemented algorithmic oracle MUST agree on every S-box,
inverse, Rcon and SHA word and on all zero padding. Keep the old RTL lookup
functions only in verification inputs once their product consumers migrate.
The freeze-time identities were also reproduced from GF(2^8) inversion/affine
AES construction and prime-root SHA constants without reading the RTL tables.

After reset, revoke all valid/lock state and scrub mutable storage before
accepting initialization. LP issues `MEM_CONTROL.BEGIN`, then exactly 2048
full-word `TABLE_DATA` writes in increasing row order. Hardware owns the write
index; software cannot address mutable banks through the loader. Each accepted
write increments `TABLE_WORDS` exactly once. Reserved/padding words and the
upper bits of byte-valued rows MUST be zero. `COMMIT` requires exactly 2048
words, checks the input CRC, then reads all 2048 physical SRAM words back and
checks their CRC and padding before atomically asserting `TABLE_VALID`,
`TABLE_LOCKED` and `READY`. Failed or short loads leave engines disabled;
overlong writes fail without changing any bank.

`BEGIN` is allowed only after reset scrub, with every engine idle, no active
loader/verify, no erasure fault and no table lock. It restarts a failed load at
word zero. `CANCEL` cancels an unlocked load/verify, drains its pending access
and leaves constants invalid. No per-word readback register is exposed. After
locking, only hard/PCLK reset unlocks the tables. Zeroize clears mutable state
but preserves a previously validated constant image. No Crypto work may start
without `READY`; legacy firmware that omits initialization fails closed.

A sequence/count, padding or CRC error during an unlocked initialization ends
that attempt, drains its pending request, clears LOAD_ACTIVE/VERIFY_BUSY and
leaves TABLE_VALID/TABLE_LOCKED/READY clear. A rejected write after lock does
not unlock or modify the validated image. BEGIN clears earlier recoverable
MEM_ERROR and ERROR_STATUS.MEMORY, but does not acknowledge sticky IRQs or
unrelated ACCESS errors. CANCEL during idle/unlocked state is an idempotent
no-op; during locked state it fails. A fatal maintenance fault ends active
maintenance, keeps FAULT latched and never asserts READY or ZEROIZED.

Host generation emits an 8192-byte image and manifest under the selected build
variant and a firmware include consumed through the normal software build.
There is no external download, new dependency or filesystem requirement on the
freestanding target. LP startup and every standalone test initialize through
the public interface; hierarchical SRAM preload is not acceptance evidence.

### APB V2 discovery and lifecycle ABI

V2 deliberately advertises `IP_VERSION=0x00020000`: mandatory initialization
and asynchronous erase completion are not binary-compatible V1 behavior.
Existing offsets, algorithm capability bits 0..23 and `CAPABILITY1` remain.
`CAPABILITY0[24]` advertises this storage/initialization contract; bit 25
advertises configured macro backing and is clear for the inferred fallback.
Bits 26..31 remain zero. Do not advertise V2 on a partially migrated product.

| Offset | Register | Access / reset | V2 semantics |
| ---: | --- | --- | --- |
| `0x028` | `MEM_STATUS` | RO / `0x00000004` | READY bit 0; TABLE_VALID 1; SCRUB_BUSY 2; LOAD_ACTIVE 3; VERIFY_BUSY 4; TABLE_LOCKED 5; FAULT 6. READY requires valid locked constants, completed erasure and no fault. |
| `0x02c` | `MEM_CONTROL` | WO / 0 | BEGIN bit 0, COMMIT bit 1, CANCEL bit 2; one-hot commands only; zero is a no-op. |
| `0x030` | `TABLE_ID` | RO / `0x43525901` | Frozen CRYC1 identity. |
| `0x034` | `TABLE_WORDS` | RO / 0 | Accepted payload count, 0..2048; BEGIN/CANCEL/reset clear it. |
| `0x038` | `TABLE_DATA` | WO / 0 | Auto-incrementing loader input; full `PSTRB=0xf` required; reads fail. |
| `0x03c` | `TABLE_CRC` | RO / 0 | Last completed full SRAM-readback CRC; zero until a complete readback, including after BEGIN/CANCEL/reset. |
| `0x040` | `MEM_ERROR` | RO / 0 | First lifecycle error code bits 7:0; physical bank bits 10:8; row bits 20:11; bit 31 valid; other bits zero. Non-addressed errors use bank/row zero. |
| `0x044` | `MEM_CYCLES` | RO / 0 | Elapsed internal verify/scrub cycles; reset at each maintenance operation and retained on completion/fault. Counts active PCLK edges, not LP polling or loader inter-write gaps. |

`STATUS[3]` is maintenance busy (scrub/load/verify), and bit 4 is READY; reset
STATUS therefore has bit 3 set. Existing busy bits describe their respective
engine including abort cleanup. During global maintenance, engine
result/key/prepared valids and PIO input-ready are clear. Existing global
status, identity, IRQ and error registers remain accessible.

`IRQ_STATE/ENABLE/TEST[5]` is the new memory-ready event on successful COMMIT;
bits 0..4 retain their assignments. `ZEROIZED` bit 4 reports explicit global
zeroize completion only, never command acceptance or reset scrub. Clear stale
ZEROIZED on accepted zeroize; an IRQ_TEST bit cannot serve as physical erasure
evidence. Concurrent events win over W1C. `ERROR_STATUS[4]` is MEMORY; W1C
clears its diagnostic and MEM_ERROR together only when maintenance is idle.
W1C never restores readiness or clears a fatal erasure fault. Errors also set
the existing error IRQ. MEM_ERROR codes are: 1 sequence/count, 2 padding,
3 input CRC, 4 SRAM readback CRC, 5 scrub verification, 6 internal progress
timeout. Codes 5/6 latch FAULT until hard reset; codes 1..4 allow BEGIN retry.
Invalid APB encodings additionally retain `ERROR_STATUS.ACCESS` behavior.

New command/data registers require full-word writes; reserved command bits,
multiple command bits and invalid accesses fail with `PSLVERR` without side
effects. Existing legal byte strobes retain their meaning. Bank-backed APB
reads/writes may insert at most four access-phase wait cycles; data and response
remain stable through the completing handshake. Side effects occur exactly
once. Invalid/secret/busy-time accesses fail promptly rather than wait for a
long crypto operation. Never acknowledge a write before its SRAM retirement,
return an unregistered SRAM read or expose a raw secret-bank address.

During scrub or load/verify, engine data/key/operand/configuration accesses fail
with `PSLVERR`; only global identity/status/error/IRQ and the legal loader or
zeroize controls operate. Invalid result/digest reads return zero; secret reads
always fail. Mutable-window reads during the owning engine's computation fail
with `PSLVERR`, allowing its private schedule to remain independent of APB
polling. Existing legal idle operand access is preserved.

### Reset, zeroize, abort and stream ownership

All banks, engines, APB and internal streams remain in the existing PCLK domain
and use its active-low reset. No additional CDC/RDC path is allocated. SRAM
contents themselves do not have a reset pin. On reset, clear scalar sensitive
registers, revoke keys/results/prepared state/table lock, suppress engine work
and start a write-zero/readback-zero sweep of every row of banks 2..5. These
four banks can scrub in parallel. Boot scrub MUST complete within 2056 active
PCLK cycles after reset release; a new reset restarts from row zero. Constants
remain inaccessible until completely overwritten and validated.

An accepted global zeroize cancels unlocked initialization, invalidates results
and secrets immediately, clears sensitive scalar/round state and starts the
same full mutable-bank sweep. It physically clears the payload of all three
FIFO exceptions as well as their pointers; flushing only valid bits is not
erasure. Reuse the Common FIFO through an owned clear controller that fills
and drains every slot with zero while application ports are isolated; do not
patch managed FIFO storage or erase it by hierarchical access. Check the
cleared payloads before restoring the empty state. Reads of each scrubbed
SRAM row must return zero before completion.
All banks include reserved rows in the sweep. ZEROIZED is emitted only after
the last write/read response drains and scalar/FIFO erasure also completes;
the bound is 2056 active cycles from accepted command. Repeated zeroize while
scrubbing is idempotent, does not restart the sweep or create an early event.
Hard reset and accepted zeroize take precedence over engine DONE/START.

To preserve the AXI4-Stream stability contract, a V2 zeroize request while an
AES/SHA DMA operation is active or an output beat is held valid MUST fail
promptly with `PSLVERR` and ACCESS; it is not accepted as an erase request.
Software first completes or quiesces the owning DMA transfer and confirms
that no beat remains held. Do not drop TVALID or erase its payload underneath
backpressure. PIO operations and private RSA may be interrupted by accepted
zeroize without waiting for their calculation to finish. Reset remains the
coordinated emergency recovery boundary, not evidence of immediate physical
erasure while PCLK is stopped.

Per-engine abort revokes that engine's result, stops new input/work and drains
any already-presented output beat before scrubbing its mutable banks/FIFO and
clearing BUSY. Do not assert DONE for abort. An outstanding stream beat can
extend this drain indefinitely under external backpressure; count/report this
separately from the bounded local scrub. Merely aborting the DMA consumer is
not evidence that a held producer beat retired. The HAL must preserve/drain
that transfer or require coordinated reset on timeout. AES abort preserves
staged/expanded keys in rows 0..75; erases rows 76..1023 and all transient round
state/FIFOs. A key expansion interrupted by AES abort leaves KEY_VALID clear;
only a previously completed key schedule may retain KEY_VALID. SHA abort clears
bank 3 and its scalar state/FIFO. RSA abort clears
banks 4/5 and revokes PREPARED; modulus preparation must be repeated. Global
zeroize always erases the AES key region as well.

SCRUB_BUSY and MEM_CYCLES describe global reset/zeroize maintenance, not a
per-engine abort. Local abort cleanup retains that engine's BUSY and cycle
counter, completes its scrub within 2056 cycles after the last pending stream
beat retires, and does not clear another engine's valid state or block its
banks. A global zeroize supersedes any local cleanup. Local scrub failure
latches the same fatal MEMORY fault, revokes global READY and invalidates all
engine results. New starts while the owning engine is still cleaning fail.

No clear loop, return-early branch, table selection or SRAM arbitration during
private RSA may depend on a secret exponent bit. Retain all 1024 two-bit windows,
two squarings plus one multiply per window and the mandatory 65537 recheck.
Select window operands by scanning all four candidates in a fixed address
order and selecting in scalar logic, rather than exposing secret-indexed bank
timing. Do not publish the candidate until verification succeeds. This is a
logical scheduling requirement, not a new DPA/FIA resistance claim.

### Execution cycles and HAL

Replace combinational lookup fanout with a single AES table read lane and a
single SHA constant read lane. AES processes SubBytes in fixed byte order and
fetches round keys by words; SHA fetches schedule operands and K through
bounded microsteps. RSA retains a 32-bit-limb Montgomery datapath and sequences
SRAM reads, arithmetic and writes. Small pipeline cuts are permitted without
changing arithmetic widths or numerical results.

The following are acceptance ceilings in active PCLK cycles, not measured
performance. They include private-bank waits and arithmetic control; they
exclude external input starvation/output backpressure and LP initialization
write gaps. There is no inter-engine bank contention to exclude.

| Operation | Maximum cycles |
| --- | ---: |
| Full reset/global-zeroize scrub, including readback | 2056 |
| COMMIT validation after last accepted payload word | 8192 |
| AES key expansion, any supported key size | 2048 |
| AES block, including mode bookkeeping, with key already valid | 1024 |
| SHA compression block, including schedule and local state transfer | 2048 |
| Montgomery multiply, including operand/result SRAM copies | 131072 |
| RSA modulus preparation | 4194304 |
| RSA private operation, including table preparation and public recheck | 536870912 |
| RSA public operation, all supported exponent lengths/values | 1073741824 |

AES/SHA streaming overhead beyond the per-block bounds is at most 128 local
cycles per operation; SHA includes every compression block added by padding.
Existing operation counters include local SRAM waits and external stalls, and
retain their 32-bit wrap behavior; verification records unwrapped 64-bit cycle
totals. MEM_CYCLES has no externally stalled phase and uses a watchdog equal
to the applicable maintenance ceiling. A missed ceiling sets code 6, revokes
READY and requires reset; it must not produce a success event. Physical timing
is separately checked at the committed PCLK constraint, with 72 MHz Crypto
block characterization retained as a separate target, not the reset frequency.

Keep existing public algorithm function signatures. Add:

```c
rs_status_t rs_crypto_init(rs_timeout_t timeout);
rs_status_t rs_crypto_zeroize_wait(rs_timeout_t timeout);
```

`rs_crypto_init` identifies V2/CRYC1, waits for boot scrub, loads the frozen
public image, commits and waits for valid+locked+ready. It is idempotent when
already ready, returns RS_EIO for live engine/foreign loader ownership or
maintenance fault, and RS_ENOTSUP for unsupported hardware/layout. It never
zeroizes an active context to obtain ownership. The LP application calls it
before the first crypto operation; selftest does so explicitly. It must not
require completion of a crypto operation to initialize Crypto.

Algorithm APIs on V2 check READY before accepting work and return RS_EIO if
uninitialized; there is no implicit software crypto or hidden table fallback.
`rs_crypto_zeroize_wait` validates the stream-quiescence precondition, clears
stale ZEROIZED, submits the command and waits for SCRUB_BUSY=0, no FAULT and a
fresh completion. It returns RS_ETIMEOUT without claiming erasure when polling
expires. `rs_crypto_zeroize(void)` remains a compatibility wrapper using
RS_TIMEOUT_DEFAULT and MUST also wait for physical completion. Use the
correct AES_KEY_STATUS bit definition in that path; the baseline mixes it
with the distinct AES_STATUS key-valid mask. The updated HAL may retain V1
algorithm/zeroize support by explicit IP_VERSION dispatch; V1 must not be
reported as satisfying this SRAM contract. Timeout budgets are bounded polls,
not claimed PCLK cycles. Timeout never frees live DMA buffers implicitly.
Initialization and erasure each consume one monotonically decreasing caller
budget across their waits/transfers; do not restart it per word or retry.
On initialization timeout, cancel an unlocked attempt and report timeout;
never unlock a completed image or claim a still-running scrub completed.
LP software serializes lifecycle calls and IRQ_TEST use with operation setup;
there is no hidden multi-client initialization or erasure owner.

The HAL uses CANCEL during its load phase. During verification it uses the
existing ZEROIZE command for timeout cleanup: verification can finish between
a status read and the cleanup write, and CANCEL on a locked image is illegal.
ZEROIZE either cancels the owned initialization or preserves the just-locked
image. No engine can start while this serialized initialization owns the block.
The returned timeout does not certify completion of the resulting scrub.

Maintain all new offsets, fields, masks and public constants manually in
`crypto_define.svh` and `crypto_regs.h`, extend their parity test, and add host
tests for pure validation/error handling. No new MISRA deviation is authorized.

### Verification and synthesis acceptance

| Evidence | Required coverage |
| --- | --- |
| Constant identity | Every forward/inverse byte, Rcon and SHA word against independent oracles; exact image hash, CRC, packing and zero padding; generate twice reproducibly. |
| Storage primitives | All six banks, first/last rows, byte masks, same-bank collisions, response backpressure, operation epochs and no write-cycle read consumption; behavioral fallback and real IHP FUNCTIONAL models. |
| Initialization | Boot scrub, no-init START rejection, short/long/partial-strobe loads, bad padding/CRC, injected SRAM readback corruption, cancel/retry, lock rejection, reset at every load/verify boundary. |
| Algorithms | Existing AES key sizes/modes/directions and CTR tails; SHA empty, 55/56/63/64/65-byte and multiblock padding; full RSA-2048 prepare/public/private/recheck and Montgomery carries/edge limbs. Reduced-width RSA tests supplement but cannot replace 2048-bit evidence. |
| Concurrency/protocol | Simultaneous AES/SHA PIO and RSA, DMA duplex/backpressure/error, APB wait-state side effects, busy/secret access faults, IRQ/W1C races, unchanged central-DMA reservations and access denial. |
| Erasure/security | Abort/reset/zeroize at every state, FIFO payload inspection after scrub, partial/restarted scrub, late responses, stalled output rejection/drain, failure injection, no early ZEROIZED/READY, no stale key/result and equal private-operation cycles for different exponents. |
| Formal | Single bank owner/access, stable pending requests/responses, no secret readback, no operation before lock/ready, result release only after private verify, and bounded scrub/commit progress under running clocks and functioning macro assumptions. |
| Firmware | Public initialization, selftest, PIO and AES DMA, zeroize completion and timeout recovery through LP; no direct SRAM preload or bypass of macro/model interfaces. |

Use revision-qualified baseline A at `92830d963da2f1e39bb219c0d377bc4889c07755`
and candidate B with identical committed profile, macros, feature enables,
locked tools/PDK, hierarchy policy, ABC recipe, timing target and host limits.
The 2026-09-25 interrupted full-chip run measured Crypto **91712 bits** at
the post-`proc` initial checkpoint: 83968 ROM and 7744 RAM, including the 1184
FIFO bits. It also measured 504050 whole-chip inferred bits. Its artifact is
`build/ihp130-2026-09-25-09-01-9903b3d112b7/syn/yosys/rpt/retrosoc_asic_initial.rpt`;
the manifest records the baseline revision. The run was intentionally stopped
after 443.075 seconds, before pre-memory, with peak RSS 1511724 KiB. It is
neither a timeout nor a completed A/B performance baseline.

For completed macro acceptance, the Crypto hierarchy MUST contain all six
physical banks, zero algorithm ROMs, no inferred key/schedule/Montgomery RAM,
and at most the 1184 allowed FIFO memory bits at the unchanged pre-memory
checkpoint. Inventory packed vectors/FF bits separately to catch hidden
copies; do not lower memories early to make a report appear empty. Fully
report every remaining register group and the logical/physical capacity
overhead. Do not shrink algorithms, FIFO depths or RSA widths to pass a gate.

Archive per-hierarchy initial/pre-memory/post-memory/pre-tech counts, inferred
memory ports and geometry, macro types/instances, mapped FF/mux counts,
standard-cell and macro area, pass timings (memory, opt_dff, techmap, ABC and
whole flow), peak RSS, tool versions, input hashes and raw logs. Run both a
Crypto block comparison and a whole-SoC comparison. Require measured block
synthesis time/RSS improvement; do not claim whole-chip timeout resolution
unless the unchanged full-chip flow actually completes. Timeouts retain their
failed status and partial evidence. Keep `opt_dff -sat -nodffe -nosdff`, the
180-minute Yosys limit and global warning/metric policies unchanged.

Resolve all six macros to the existing IHP130 Liberty views for synthesis/STA
and Verilog models for simulation. Register actual instance paths and
LEF/GDS/CDL, power hooks and non-overlapping placement in both applicable
LibreLane deliveries; mapping-only evidence is not PnR/signoff. Report
WNS/TNS, reset/enable fanout and SRAM setup/hold separately. Existing whole-SoC
timing debt does not excuse a new uncharacterized macro or missing timing path.

Expected artifact classes are `constants.json`, `storage-inventory.json`,
`functional.json`, `lifecycle.json`, `cycles.json`, `memory-synthesis-ab.json`
and `physical.json`, under the selected variant. Each carries source/config/
tool identity, exact command, verdict and raw evidence paths. Missing tools,
missing full-width tests or interrupted flows are NOT_RUN/failed, never PASS.

## Storage Refreeze Development Phases

The historical V1 development list below is not a set of stable phase IDs.
The following new phase IDs are frozen; later work must not renumber them.

### Phase 0 - Baseline and Storage Verification

ID: `CRYPTO-P0`. Establish the baseline, independent CRYC1 image/oracle,
storage/FF inventory and verification harnesses before modifying production
datapaths. Preserve V1 public behavior. Map the six-bank contract to existing
Common/technology modules, lock APB/HAL parity expectations and prepare
full-width numerical/lifecycle/cycle comparisons. Dependencies are the existing
Crypto contract, dependency lock and committed IHP130 profile. Completion
requires reproducible constant identities and traceable baseline reports;
interrupted historical synthesis is not a successful baseline.

Validation: existing Crypto primitive/stream/APB tests and register parity,
independent image verification and baseline synthesis inventory. This phase
adds verification/build artifacts only; it does not advertise V2, change an
address/IRQ/DMA allocation or enable incomplete engines.

The P0 tooling entry points are now available; availability is not a PASS
verdict. Set one `BUILD_TIMESTAMP` for the entire sequence:

```sh
make CONFIG=configs/ci/ihp130.mk SYNTH=YOSYS crypto-p0-constants
make CONFIG=configs/ci/ihp130.mk SYNTH=YOSYS crypto-p0-rtl
make CONFIG=configs/ci/ihp130.mk SYNTH=YOSYS crypto-p0-baseline
make CONFIG=configs/ci/ihp130.mk SYNTH=YOSYS crypto-p0-report
```

Artifacts are under `build/<variant>/crypto/p0/`. `functional.json` identifies
the standalone tests, exact commands/logs and source identity; `cycles.json`
records V1 measurement conditions. `baseline-synthesis.json` and
`storage-inventory.json` distinguish generic memories, explicit register bits
and physical macros at initial, pre-memory, pre-SAT and mapped checkpoints.
The block driver wraps the existing SoC script without dropping SAT or ABC
passes. V1/P0 has zero Crypto macros; the six-bank count is a P1 expectation.
`p0-report.json` stays incomplete if any required stage is absent, stale or
unsuccessful. Full-SoC A/B and V2 physical acceptance remain P2 work.

P0 baseline evidence collected on 2026-09-25 is below
`build/ihp130-2026-09-25-10-23-9903b3d112b7/crypto/p0/`. The aggregate
`p0-report.json` passes its constant, functional, cycle, inventory and block
synthesis gates. Its source hashes establish that production Crypto RTL still
matches baseline `92830d9`; this is not V2 implementation evidence.

| P0 observation | Measured result |
| --- | --- |
| CRYC1 generation | Independent mathematical oracle and six data/padding corruption cases pass. |
| Functional suite | Seven fixtures pass: four existing V1 tests, CBC/CTR plus 22 SHA padding cases, actual Crypto-DMA, and full RSA-2048. |
| RSA-2048 | Prepare 283077 cycles; public 65537 operation 187352; private and bad-private-exponent rejection both 26382568 cycles. |
| AES DMA | Four ECB blocks / 64 bytes, AXI stalls, exact output/address/count checks: 75 engine cycles. |
| Initial / pre-memory inferred storage | Both 91712 bits: 83968 ROM and 7744 RAM. |
| Explicit generic register bits | Initial 44724; pre-memory 44719; pre-SAT 52591; post-SAT 52587. SRAM macro count is zero. |
| Block synthesis | Unchanged balanced recipe, PCLK target 20833 ps, exit 0; 2056.928 seconds and peak RSS 2011792 KiB. |
| Major phase wall times | Memory 1.518 s; explicit SAT opt_dff 1499.169 s; techmap 8.852 s; ABC 391.591 s. |
| Mapped block | 324973 cells, 5153548.201206 um2 total standard-cell area; 2576174.025598 um2 sequential area. |

The explicit SAT pass removed four AES register bits; RSA core register bits
remained 32938. Auxiliary checkpoint replays completed APB-wrapper, AES-core,
other AES/SHA/FIFO and Montgomery selections in approximately 15.9, 12.7, 6.9
and 12.2 seconds. RSA selections remained active longer and were intentionally
stopped after the main baseline completed. These are localization observations,
not substitute synthesis passes or timeout verdicts. The main run used the
original complete selection and completed successfully. Auxiliary jobs and
brief debugger sampling overlapped part of its runtime; repeat isolated A/B
runs for any strict performance-improvement claim.

ABC warned that its shared SCL cache rename failed and fell back to Liberty;
record and match that frontend mode in later comparisons. The combinational
network warning is also retained in raw logs. No warning baseline was changed.
Ruff, changed-testbench Verible checks and diff checks pass. The full Make
format check reports existing differences in Makefile, APU software/block
rules, GA2D/Yosys rules and formal.mk; the new Make entries introduce no
formatter delta. Pytest was not run under the maintainer's instruction.
Firmware/full-SoC simulation, full-chip synthesis, netlist simulation, STA,
formal proofs and physical qualification were not run by this P0 delivery.
They remain explicit later gates; the P0 aggregate is not an all-gates release
verdict or a claim that SRAM has resolved the whole-SoC synthesis problem.

### Phase 1 - Macro-backed Crypto and Secure Initialization

ID: `CRYPTO-P1`. Depends on P0. Implement all six banks, constant loading,
scrub/readback/lock, AES/SHA microsteps, SRAM-based RSA/Montgomery and the full
V2 APB/HAL/LP-startup contract together. Preserve the allowed FIFO capacities,
numerical behavior and concurrency. Update filelists/models, manual register
mirrors and tests. The public change is V2 initialization/maintenance discovery,
bounded APB waits, new HAL APIs and delayed erase completion; system address,
DMA/IRQ and clock/reset allocations stay fixed.

Completion requires the full verification matrix, cycle ceilings, all six
macro instances in block synthesis and no prohibited inferred stores/copies.
Validate focused simulations/formal first, then RTL style/lint, embedded-C
format/policy/host tests, affected firmware and full-SoC behavioral selftest.
Do not call the refreeze implemented merely because wrappers elaborate.

The P1 implementation uses `crypto_sram_store` and `crypto_mem_pkg` for six
independent tagged synchronous bank channels, `crypto_mem_ctrl` for CRYC1
initialization/global maintenance, `crypto_scrubber` for write/readback, and
`crypto_clearable_fifo` around the unchanged Common payload queues. The
`crypto_*_sram_*` engines retain only bounded working/scalar state in flops.
The V1 modules and tables are retained solely in `tests/rtl/crypto_v1/`.
`scripts/data/crypto_constants.json` is the software constant source; the
independent mathematical oracle and frozen identity remain unchanged.

Run P1 evidence without invoking Pytest, with one explicit timestamp:

```sh
make CONFIG=configs/ci/ihp130.mk SYNTH=YOSYS BUILD_TIMESTAMP=<timestamp> \
  crypto-p1-constants crypto-p1-rtl crypto-p1-formal crypto-p1-synth
make CONFIG=configs/ci/ihp130.mk SYNTH=YOSYS BUILD_TIMESTAMP=<timestamp> \
  CRYPTO_P0_BASELINE_ROOT=build/<p0-variant> \
  CRYPTO_P1_LP_ROOT=build/<lp-test-variant> \
  CRYPTO_P1_CI_ROOT=build/<ci-smoke-variant> crypto-p1-report
```

The standalone test initializes only through public APB, including the IHP
FUNCTIONAL macro model. Hierarchical accesses are restricted to fault
injection and post-erasure inspection, never initialization. The SRAM ports
retire at a fixed one-cycle latency; clients reserve a response slot before
issuing a read. APB reads consume the tagged result with a bounded wait,
while write side effects occur only at the completed transfer. Reset clears
response validity; canceled operations drain or ignore their retired requests.

The focused LP acceptance firmware uses the real full-SoC APB and DMA path:

```sh
make CONFIG=configs/ci/ihp130.mk BUILD_TIMESTAMP=<lp-test-timestamp> \
  APP=bringup APP_SRCS=$PWD/tests/c/crypto_firmware.c LINK_TYPE=ld2_all_sram \
  SIMU=VERILATOR HAVE_SVA=YES VERILATOR_SIM_ARGS=--fast-flash \
  SOC_SIM_TIME=1800 firmware sim
```

This explicitly overrides the bringup application source with a test image;
it is not a replacement PASS for the unmodified `ci_smoke` regression.
The first 2026-09-25 `ci_smoke` attempt omitted `HAVE_CSR=YES` and failed
the preceding fabric-monitor check (`SIM_TEST_FAIL code=13`): the CSR-disabled
build replaces GA2D tests with no-ops, while the monitor requires their traffic.
Use the CSR override below, matching `scripts/regress.py`. The ordinary verbose
bringup attempt reached its 1800-second simulation limit while printing boot
discovery. Both failures remain recorded. The focused image passed public
initialization, AES/SHA selftest, AES DMA, timeout handling and physical
zeroize with `SIM_TEST_PASS` and the unchanged 32 KiB SRAM capacity.

Candidate artifacts are under
`build/ihp130-2026-09-25-11-30-9903b3d112b7/crypto/p1/`; the focused LP
simulation is under `build/ihp130-2026-09-25-12-50-2ff2ea5518f5/`.
P0 inputs were archived before migration, and its evidence directory was not
modified. P1 block reports include raw source hashes, inferred memories,
separate register inventory, all six macro paths and unchanged-recipe timing
and RSS. Strict isolated clean-revision A/B, full-chip synthesis/netlist/STA,
remaining PDK mappings and physical registration stay in P2. Exhaustive
state-by-state fault campaigns and independent review must not be inferred
from the directed test list or a block-synthesis PASS.

The CRYPTO-P1 review fixes have a separate evidence set under
`build/ihp130-2026-09-25-15-19-9903b3d112b7/crypto/p1/`. The
[verification mapping](crypto-verification.md) identifies the exact control
properties, physical-data checks and fault cases. The fixes restore new-command
DONE clearing, validate SRAM-readback padding, guard lifecycle configuration
accesses, and retain a stalled AES output beat through a fatal local erasure
fault. Fault handling revokes keys and computation immediately; only the
already-presented FIFO head may drain, after which its payload is cleared.
No register offset, public HAL signature, DMA reservation or bank allocation
changes as part of these fixes.

Capture full-SoC evidence at build/run time, using the matching manifest and
source snapshot; report assembly cannot certify an earlier binary by hashing
the current source tree. After creating each variant with the firmware command
above (replace `firmware sim` with `manifest`), run:

```sh
python3 scripts/crypto_p1.py firmware --variant-root build/<lp-test-variant> --firmware-kind lp
python3 scripts/crypto_p1.py firmware --variant-root build/<ci-smoke-variant> --firmware-kind ci
python3 scripts/crypto_p1.py quality --variant-root build/<block-variant>
```

For the CI manifest use `APP=ci_smoke HAVE_CSR=YES`, the existing
`ld2_all_sram`, `SIMU=VERILATOR` and `HAVE_SVA=YES` overrides. The firmware
runner records its complete build/simulation command, per-run manifest, input
hashes including generated VexiiRiscv and selected PDK model inputs, ELF/log/
result hashes and command exit status. The report rejects
missing, changed or unsuccessful runs. These helpers do not invoke Pytest.

Before the review fixes, the unchanged balanced block flow measured 69.377
seconds and 345344 KiB peak process-tree RSS on that candidate, versus P0's
2056.928 seconds and 2011792 KiB. Initial/pre-memory inventory is six
`RM_IHPSG13_1P_1024x32_c2_bm_bist` macros, zero inferred ROM bits, 1184
FIFO RAM bits and 2179 generic register bits. Post-memory/SAT has 3363
register bits including FIFO payloads. These are observed block results;
overlapping host jobs and the uncommitted candidate prevent a strict isolated
release-performance claim. The P1 report keeps acceptance incomplete:
historical failed attempts remain visible, the standalone lint-warning
baseline check fails, and repository-wide RTL format checking stops at the
unchanged `apb4_apu.sv`. Changed Crypto files pass explicit formatting/style;
C format/policy/host tests and the four named inductive proofs pass. No
warning baseline or MISRA deviation was changed. Pytest remains unrun under
the maintainer's instruction.

The earlier corrected full-SoC CI invocation, including `HAVE_CSR=YES`, passed
all peripheral tests with `SIM_TEST_PASS` on the pre-review snapshot. Its variant
is `build/ihp130-2026-09-25-12-50-10e1102406ad/`. Its firmware occupies
27744 bytes of `.text` and 1104 bytes of `.bss` in SRAM: 28848 of the existing
32768 bytes, leaving 3920 bytes. The two constant symbols occupy exactly
528 and 320 bytes. The earlier CSR-disabled failure is superseded; it is
retained as a configuration diagnostic, not an unresolved Crypto failure.

The review-fix snapshot passes all seven RTL configurations, both real-DMA
AXI error cases and five inductive proofs, including output retention through
abort/fatal fault with FIFO pointer/count invariants. Full RSA-2048 remains
2887941 cycles for preparation, 949456 for public exponent 65537, and
134047298 for both private success and bad-private-exponent rejection.
The final unchanged-recipe block run records 68.549 seconds and 343924 KiB
peak RSS; storage remains six macros, 0 inferred ROM bits, 1184 FIFO bits
and 2179 pre-memory generic register bits. These are still block observations,
not isolated clean-revision or whole-chip qualification.

The new LP and CI runs are respectively
`build/ihp130-2026-09-25-15-19-2ff2ea5518f5/` and
`build/ihp130-2026-09-25-15-19-10e1102406ad/`; both report `SIM_TEST_PASS`.
The CI SRAM footprint is 27792 bytes of text plus 1104 bytes of BSS, totaling
28896 of 32768 bytes. P0 report/archive hashes remain unchanged. Focused
format/style/readiness, C format/policy/host tests and Ruff pass. Whole-tree
formatting still stops at the untouched APU file; the warning comparison
retains 21 new Crypto unused/empty-port signatures without changing a baseline.
Pytest, full-matrix regression and P2 qualification were not run. The aggregate
keeps release acceptance incomplete pending independent review and deferred
qualification, while reporting the focused P1 gates separately.

### Phase 2 - Synthesis and Integration Qualification

ID: `CRYPTO-P2`. Depends on P1. Complete like-for-like block/SoC synthesis,
netlist boot plus Crypto functional evidence, STA, physical-view registration,
remaining PDK/fallback compatibility and the release report. Keep block
functional netlist tests in addition to whole-chip UART boot; boot alone does
not exercise Crypto. Refresh guide/status claims only from current evidence.

Use these existing commands for the applicable gates (focused new harness
commands are added and documented by P0/P1 before use):

```sh
make rtl-format-check rtl-style-check-all rtl-readiness-check-all
make CONFIG=configs/ci/ihp130.mk SIMU=VERILATOR HAVE_SVA=YES rtl-lint
make sw-format-check sw-policy-check sw-host-test
make CONFIG=configs/ci/ihp130.mk APP=ci_smoke HAVE_CSR=YES firmware
make CONFIG=configs/ci/ihp130.mk APP=ci_smoke LINK_TYPE=ld2_all_sram \
  SIMU=VERILATOR HAVE_SVA=YES HAVE_CSR=YES VERILATOR_SIM_ARGS=--fast-flash \
  SOC_SIM_TIME=1800 firmware sim
python3 scripts/regress.py --root . --suite pr --pdk IHP130 --netsim-boot-only
make CONFIG=configs/ci/ihp130.mk librelane-doctor
git diff --check
```

Use a single explicit BUILD_TIMESTAMP for commands that must consume the same
variant; behavioral and synthesis configuration differences must be recorded.
Python tooling changes additionally require Ruff/Pytest under repository
policy, subject to the maintainer's active execution constraints. Existing CI
behavioral-only jobs are not synthesis/STA evidence. P2 completion requires
numerical/lifecycle PASS, macro and residual-register audit, measured block
time/RSS improvement, full-flow verdicts and explicit physical/security gaps.

## Security Boundary and Claims

The MVP provides useful logical controls: management-only address decoding,
no key/exponent readback, busy-time configuration rejection, sticky error
reporting, deterministic private-RSA scheduling, post-operation RSA checking,
abort, and zeroization. The V1 intent is clearing secret state and flushing
FIFOs; this is not evidence of physical SRAM erasure. V2 requires immediate
logical invalidation on reset or accepted zeroize, followed by the bounded
physical scrub/readback protocol above. Its completion is qualified by a
running PCLK; stopped-clock retention is not a successful clear.

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

The following historical V1 evidence does not qualify the SRAM refreeze.
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

The approved next delivery is the compact SRAM implementation in CRYPTO-P0
through CRYPTO-P2. The following commercial variants are later work, not
permission to restore ROMs or inferred operand arrays in that delivery.
Optimize from measured IHP130 synthesis/STA/power data and retain a
verification-only V1 reference for numerical comparisons.

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
   qualify a separately banked/pipelined schedule organization for a throughput
   variant. The compact refreeze uses the synchronous SRAM schedule above;
   restoring a shift-register schedule needs a separate variant specification.
   A two-round-per-cycle option needs its own timing and numerical evidence.
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
