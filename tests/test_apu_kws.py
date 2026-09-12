"""Locked APU-P7 APUM converter and container tests."""

from __future__ import annotations

import hashlib
import sys
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from apu_kws import (  # noqa: E402
    APUM_PAYLOAD_CRC,
    APUM_SHA256,
    crc32_iso_hdlc,
    infer_apum,
    parse_apum,
    select_class,
)
from apu_kws_convert import TfliteError, import_tflite  # noqa: E402


MODEL = (
    ROOT
    / ".cache/retrosoc/sources/apu-mlperf-tiny/benchmark/training/keyword_spotting"
    / "trained_models/kws_ref_model.tflite"
)


def test_apu_p7_locked_tflite_import_matches_freeze() -> None:
    if not MODEL.is_file():
        pytest.skip("locked P7 model was not installed")
    image = import_tflite(MODEL)
    header = parse_apum(image)

    assert len(image) == 32768
    assert header.crc == APUM_PAYLOAD_CRC
    assert crc32_iso_hdlc(image[64:]) == APUM_PAYLOAD_CRC
    assert hashlib.sha256(image).hexdigest() == APUM_SHA256


def test_apu_p7_import_rejects_mutated_model(tmp_path: Path) -> None:
    if not MODEL.is_file():
        pytest.skip("locked P7 model was not installed")
    mutated = tmp_path / "mutated.tflite"
    data = bytearray(MODEL.read_bytes())
    data[-1] ^= 1
    mutated.write_bytes(data)

    with pytest.raises(TfliteError, match="SHA-256"):
        import_tflite(mutated)


def test_apu_p7_container_rejects_padding_and_crc_mutations() -> None:
    if not MODEL.is_file():
        pytest.skip("locked P7 model was not installed")
    image = bytearray(import_tflite(MODEL))
    image[0x4E0] = 1
    with pytest.raises(ValueError, match="payload CRC"):
        parse_apum(bytes(image))


def test_apu_p7_scalar_inference_matches_official_feature() -> None:
    feature = (
        ROOT
        / ".cache/retrosoc/sources/apu-kws-mfcc/datasets/kws01"
        / "tst_000000_Stop_7.bin"
    )
    if not MODEL.is_file() or not feature.is_file():
        pytest.skip("locked P7 model or official MFCC feature was not installed")
    layers = infer_apum(import_tflite(MODEL), feature.read_bytes())

    assert [len(layer) for layer in layers] == [8000] * 9 + [64, 12, 12]
    assert [
        hashlib.sha256(bytes(value & 0xFF for value in layer)).hexdigest()
        for layer in layers
    ] == [
        "4ea162c5d6215d5f4531c63d044eedef1cad9526e2c4fdcae6709f7ac5ab5abb",
        "9b3d9d6ba64079304f99477cd6689a44018e7ab6987d7611d8bfc0ec3be5d81d",
        "877299da8c940c038a02e2b5adee0f47dbce2f419697648394dcb2f0317ddb8f",
        "77bf309dcf7cdd0a8bf080748bb40929957a53a6ba3c3d8f83c87b26d540e183",
        "7be9b616635d7f96458b3c5bb997f95e08fc5266288552df7367c83e33592b62",
        "67c3b2a8ef7c342a7cc953594b544927881ea34290307d6716a65bb9e67cb81b",
        "ffe495e62d171963549f5cfd937b126691d5173592b7b0e8d7ca00101a033354",
        "7afa076d3e45a9f04ca36cdc0ff604acebc32c7a3a2ebeeda05f05e3b405a074",
        "de0c2f7b0a1aa7e774e2a48cdcbe770ec3f1f26378fa6820210d55a62e3b30a2",
        "d556d43668ea73c5a935ad4199967b53ac1c51245d4edaffe13fbe4d0e826fff",
        "dcaf556579a9340e9065a137135dd52ee4e9f81568f71608a25a9a2db10cf44f",
        "ebfee7fb52365b69ac386245459e7364533978a9a4996a988b4ba0fb83372959",
    ]
    assert select_class(layers[-1]) == 7

    image = bytearray(import_tflite(MODEL))
    image[0x24] ^= 1
    with pytest.raises(ValueError, match="payload CRC"):
        parse_apum(bytes(image))
