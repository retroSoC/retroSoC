# Public Crypto constants

`crypto_constants.json` is the canonical software source for CRYC1: 528 AES
bytes and 80 SHA words. `scripts/crypto_constants.py` pads these to the exact
8192-byte image and emits a compact 848-byte firmware header. Its frozen hash
and CRC are checked against the independent mathematical oracle in
`tests/crypto_reference.py`; production RTL contains no lookup tables.

The layout and identity are frozen in [the Crypto specification](../../docs/ip/crypto.md).
