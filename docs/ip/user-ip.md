# User IP Software Contract

## Scope

The Mini SoC exposes one 4 KiB APB4 user-IP window at
`RS_SOC_APB4_USER_IP_BASE`. SystemCtrl selects which implementation responds to
that window. Slot 0 is the fixed ARCHINFO demonstration target; generated user
extensions occupy contiguous slots beginning at 1.

The extension map in `rtl/mini/integration/user_extensions.json` is the source
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
The `ci_smoke` firmware probes slot 0 and every generated extension slot in
simulation, then restores slot 0.
