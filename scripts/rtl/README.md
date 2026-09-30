# Shared RTL Flow Helpers

These product-independent helpers parse filelists, convert SystemVerilog,
generate address/pad artifacts, and prepare simulation inputs. Both products
invoke them here directly, with Python imports through `scripts.rtl`. Product
inputs stay under their owning `rtl/<product>` directory; outputs stay below
`build/`.

Changes require focused generator tests, Ruff and Pytest, plus compilation of
each affected product. `generate_tiny.py` owns Tiny-only integration bindings.
