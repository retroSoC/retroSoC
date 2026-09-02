# Legacy User IP Software Contract

## Scope

Mini product mode exposes the historical 4 KiB `RS_SOC_APB4_USER_IP_BASE`
window only as a read-only compatibility/capability target. `IPSEL` reads zero,
selector writes return APB `PSLVERR`, and selector HAL operations return
`RS_ENOTSUP`. Product software uses the fixed
[EXT-L/EXT-H contract](extensions.md).

The `MINI_MODE=MPW` profile retains the original behavior: SystemCtrl selects
one implementation, slot 0 is ARCHINFO, and generated user IPs occupy
contiguous slots beginning at 1.

The legacy map in `rtl/mini/integration/user_extensions_legacy.json` is the source
of truth for implemented slots. Its generator emits `RS_SOC_USER_IP_COUNT`,
which is also the highest valid slot because extension slots are required to
be contiguous from 1.

## SDK Boundary

`<retrosoc/hal/user_ip.h>` provides the generic software interface:

- `rs_user_ip_get_selected()` reads the active slot.
- `rs_user_ip_select()` validates and selects an implemented slot.
- `rs_user_ip_probe()` selects a slot and reads its identification word at
  offset `0x000`.
- `rs_user_ip_read()` and `rs_user_ip_write()` perform aligned 32-bit accesses
  within the 4 KiB window.

The HAL rejects null outputs, unaligned offsets, out-of-window offsets, and
unimplemented slot numbers before accessing the user-IP window. Callers must
serialize selection changes with accesses; the bare-metal HAL does not provide
locking.

The word at offset `0x000` is interpreted by the selected implementation. Slot
0 returns the ARCHINFO component ID. User extension templates reserve the same
offset for the slot ID and require it to remain readable.

## Extension-Owned ABI

The generic SDK does not define registers beyond the identification word.
Register meanings belong to each integrated user IP and must not be added to
`<retrosoc/core/soc.h>`.

The current shell integration keeps its private definitions below
`app/network/userip`:

| Slot | Target | Register ABI |
| --- | --- | --- |
| 0 | fixed ARCHINFO | Managed ClusterIP ARCHINFO V2 ABI |
| 1 | managed timer target | `ID 0x000`, `DIV 0x004`, `COUNT 0x008` |
| 2 | managed GPIO target | `ID 0x000`, `OE 0x004`, `DATA_OUT 0x008`, `DATA_IN 0x00C` |

Replacing an extension target requires updating its application driver and the
register-parity test in the same change. Generic SDK consumers remain
unchanged.

## Verification

Host tests cover argument, alignment, range, and slot validation without
performing MMIO. `tests/test_user_ip_register_parity.py` compares the private C
register definitions with the integrated managed RTL and extension manifest.
Product `ci_smoke` verifies that selector mutation is unsupported, then probes
the fixed extension slots. MPW register parity remains a host test.
