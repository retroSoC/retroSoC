"""Frozen APU-P9 APUC image and physical-bank layout coverage."""

from __future__ import annotations

import hashlib
import copy
import struct
import sys
import zlib
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

import generate_apu_kws_rtl_constants as gen  # noqa: E402
from apu_kws_coeff import validate_layout_manifest  # noqa: E402
from apu_kws_convert import import_tflite  # noqa: E402


TFLITE = (
    ROOT
    / ".cache/retrosoc/sources/apu-mlperf-tiny/benchmark/training/keyword_spotting"
    / "trained_models/kws_ref_model.tflite"
)


def _require_tflite() -> Path:
    if not TFLITE.is_file():
        pytest.fail(
            "locked P7 model is required for APU-P9 coefficient validation; "
            "run `make setup-apu-kws-reference`"
        )
    return TFLITE


def test_apu_p9_frozen_apuc_and_layout() -> None:
    image = import_tflite(_require_tflite())
    apuc, manifest = gen.build_apuc(image)
    validate_layout_manifest(apuc, manifest)
    header = struct.unpack_from("<16I", apuc)

    assert len(apuc) == gen.APUC_BYTES == 61504
    assert header[:10] == (
        gen.APUC_MAGIC,
        gen.APUC_ABI,
        gen.APUC_BYTES,
        gen.APUC_HEADER_BYTES,
        gen.APUC_PAYLOAD_BYTES,
        gen.APUC_PROFILE,
        gen.APUC_LAYOUT_ID,
        gen.APUC_BANK_COUNT,
        gen.APUC_TABLE_COUNT,
        gen.APUC_PAYLOAD_CRC,
    )
    assert header[10:13] == (*gen.APUC_COEFFICIENT_ID, gen.APUC_APUM_PAYLOAD_CRC)
    assert header[14:] == (0, 0)
    assert zlib.crc32(apuc[64:]) & 0xFFFFFFFF == gen.APUC_PAYLOAD_CRC
    assert hashlib.sha256(apuc[64:]).hexdigest() == gen.APUC_PAYLOAD_SHA256
    assert hashlib.sha256(apuc).hexdigest() == gen.APUC_SHA256
    assert manifest["layout"] == {
        "geometry": "tc_sram_1024x32",
        "banks": 15,
        "words_per_bank": 1024,
        "populated_words": 14444,
        "zero_padding_words": 916,
    }


def test_apu_p9_layout_locations_are_unique_and_complete() -> None:
    apuc, manifest = gen.build_apuc(import_tflite(_require_tflite()))
    validate_layout_manifest(apuc, manifest)
    locations = [
        tuple(location)
        for table in manifest["tables"].values()
        for location in table["locations"]
    ]
    assert len(locations) == 14444
    assert len(set(locations)) == len(locations)
    assert all(0 <= bank < 15 and 0 <= row < 1024 for bank, row in locations)


def test_apu_p9_layout_oracle_rejects_generator_self_consistency() -> None:
    apuc, manifest = gen.build_apuc(import_tflite(_require_tflite()))
    stale = copy.deepcopy(manifest)
    stale["tables"]["hann"]["locations"][0] = [14, 1023]
    with pytest.raises(ValueError, match="independent map/hash oracle"):
        validate_layout_manifest(apuc, stale)

    missing_revision = copy.deepcopy(manifest)
    del missing_revision["generator"]["revision"]
    with pytest.raises(ValueError, match="generator revision"):
        validate_layout_manifest(apuc, missing_revision)


def test_apu_p9_irq_mask_preserves_legacy_rejection() -> None:
    register_source = (ROOT / "rtl/ip/multimedia/apu_reg.sv").read_text(encoding="utf-8")
    assert "IrqMask = EnableP7 ? 12'hfff : 12'h7ff" in register_source
