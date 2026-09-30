# Frozen Crypto V1 reference

These modules preserve the pre-SRAM algorithm implementation for verification.
They are not in any production filelist. The original tests in
`tests/test_crypto.py` continue to exercise this independent numerical
reference; the V2 fixture additionally uses the independent CRYC1, SHA and
RSA oracles. Do not add a production fallback to these ROMs or operand arrays.

The original P0 sources, commands and measurements are retained in the P0
evidence directory documented in [the specification](../../../docs/ip/crypto.md).
