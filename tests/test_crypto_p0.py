"""Independent image and hierarchy-accounting regressions for CRYPTO-P0."""

import json
from pathlib import Path

import pytest

from crypto_reference import constant_image, integer_root
from scripts.crypto_constants import pack, validate
from scripts.crypto_p0 import inventory


ROOT = Path(__file__).resolve().parents[1]


def test_cryc1_independent_mathematical_image():
    assert pack(ROOT) == constant_image()
    assert validate(constant_image())["bytes"] == 8192


@pytest.mark.parametrize("offset", (0, 1023, 2048, 4095, 4096, 8191))
def test_cryc1_rejects_data_and_padding_corruption(offset):
    image = bytearray(constant_image())
    image[offset] ^= 1
    with pytest.raises(ValueError, match="frozen identity"):
        validate(bytes(image))


def test_integer_root_exact_boundaries():
    for degree in (2, 3):
        for value in (1, 2, 255, 1 << 32):
            assert integer_root(value ** degree, degree) == value
            assert integer_root(value ** degree - 1, degree) == value - 1


def test_inventory_counts_reused_modules_and_separate_registers(tmp_path):
    module = {"memories": {"ram": {"width": 32, "size": 64},
                           "rom": {"width": 8, "size": 256}},
              "cells": {"write": {"type": "$memwr_v2", "parameters": {"MEMID": "\\ram"}},
                        "ff": {"type": "$adffe", "parameters": {"WIDTH": "100000000000"}}}}
    design = {"modules": {"apb4_crypto": {"cells": {
        "one": {"type": "shared"}, "two": {"type": "shared"}}}, "shared": module}}
    path = tmp_path / "design.json"
    path.write_text(json.dumps(design))
    report = inventory(path)
    assert report["ram_bits"] == 4096
    assert report["rom_bits"] == 4096
    assert report["register_bits"] == 4096
    assert len(report["rows"]) == 3


def test_inventory_rejects_recursive_hierarchy(tmp_path):
    path = tmp_path / "design.json"
    path.write_text(json.dumps({"modules": {"apb4_crypto": {
        "cells": {"loop": {"type": "apb4_crypto"}}}}}))
    with pytest.raises(ValueError, match="recursive"):
        inventory(path)
