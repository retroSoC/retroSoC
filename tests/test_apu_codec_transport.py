"""APU-P5 class-6 assembler, BAM, and product-filelist tests."""

from __future__ import annotations

import os
import hashlib
import json
import struct
import sys
from pathlib import Path

import shutil
import subprocess

import pytest


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from apu_codecs import crc8, crc16  # noqa: E402
from apu_interpreter import Machine, TransportModel  # noqa: E402
from apu_isa import (  # noqa: E402
    APUMC_ABI_V2,
    ControlOpcode,
    Entry,
    Instruction,
    InstructionClass,
    build_apumc,
    crc32_iso_hdlc,
    parse_apumc,
)
from apu_mcasm import assemble  # noqa: E402
from apu_p5_coefficients import coefficient_bytes  # noqa: E402
from apu_primitives import PrimitiveBam  # noqa: E402
import run_apu_p5_corpus_rtl as corpus_runner  # noqa: E402
from run_apu_p5_corpus_rtl import (  # noqa: E402
    MIGRATABLE_VERIFICATION_SHA256,
    _can_migrate_pass_result,
    _can_reuse_result,
    _truth_sha256,
)


TRANSPORT_PROGRAM = """
.entry 0 wav wav done 16 128 0 256 0x001b0030 0 0
.entry 1 mp3 mp3 mp3 1 1 0 0 0 0 0
.entry 2 wav wav done 16 128 0 256 0x001b0030 0 0
mp3:
  trap 0x01000001
wav:
  movi r0, 0
  movi r1, 8
  input_refill r2, r0, r1
  movi r3, 0x55
  dma_wait r4
  ld32 r5, r0, 0
  movi r6, 8
  output_commit r8, r0, r6
  dma_wait r4
  movi r6, 4
  frame_commit r6, r6
  frame_commit r6, r6
  movi r7, 0
  job_result r7, r7, 0
done:
  end
"""


def test_p5_transport_assembler_and_parser_keep_legacy_targets_closed() -> None:
    assembly = assemble(TRANSPORT_PROGRAM, "p5")
    instructions, entries, _ = parse_apumc(assembly.bundle, "p5")
    assert entries[0].scratch_bytes == 256
    assert any(instruction.instruction_class == 6 for instruction in instructions)


def test_p5_transport_runs_asynchronously_and_preserves_independent_scalar_progress() -> None:
    assembly = assemble(TRANSPORT_PROGRAM, "p5")
    primitives = PrimitiveBam()
    transport = TransportModel(input_data=b"ABCDEFGH", latency=3)
    result = Machine(
        assembly.instructions,
        assembly.entries[0],
        target="p5",
        primitives=primitives,
        transport=transport,
        fetch_no_retirement_cycles=0,
    ).run()
    assert result["registers"][2] == 8
    assert result["registers"][3] == 0x55
    assert result["registers"][5] == int.from_bytes(b"ABCD", "little")
    assert result["transport"]["input_used"] == 8
    assert result["transport"]["frames"] == 2
    assert result["transport"]["output"] == b"ABCDEFGH".hex()


def test_p5_production_and_verification_filelist_boundaries() -> None:
    product = (ROOT / "rtl/mini/filelist/ip.fl").read_text(encoding="utf-8")
    assert "/ip/multimedia/apu_codec_transport.sv" in product
    assert "/ip/multimedia/apu_codec_controller.sv" in product
    assert "tests/rtl" not in product
    assert "apu_p2_backend" not in product
    assert "apu_p5_corpus_tb" not in product


def test_p5_corpus_runner_uses_identical_production_simulator_fixture(tmp_path: Path) -> None:
    if any(shutil.which(tool) is None for tool in ("iverilog", "vvp", "verilator")):
        raise RuntimeError("P5 corpus verification requires Icarus, vvp, and Verilator")
    source = b"bad!"
    corpus = tmp_path / "corpus"
    corpus.mkdir()
    (corpus / "bad.flac").write_bytes(source)
    bundle = tmp_path / "apu-p5.apumc"
    bundle.write_bytes(
        assemble(
            (ROOT / "rtl/ip/multimedia/apu_p5_codecs.apus").read_text(encoding="utf-8"),
            "p5",
            coefficient_bytes(),
        ).bundle
    )
    empty_hash = hashlib.sha256(b"").hexdigest()
    manifest = {
        "schema_version": 1,
        "file_count": 1,
        "counts": {"supported": 0, "unsupported": 0, "malformed": 1},
        "files": [
            {
                "path": "bad.flac",
                "sha256": hashlib.sha256(source).hexdigest(),
                "expected": "malformed",
                "geometry": None,
                "production_truth": {
                    "status": "error",
                    "code": 4,
                    "stage": 4,
                    "warnings": 1,
                    "reason": 0x10,
                    "error_offset": 0,
                    "input_used": 4,
                    "input_used_policy": "exact",
                    "output_bytes": 0,
                    "frames": 0,
                    "source_info": 0,
                    "pcm_sha256": empty_hash,
                },
            }
        ],
    }
    manifest_path = tmp_path / "corpus.json"
    manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
    output = tmp_path / "result.json"
    subprocess.run(
        [
            sys.executable,
            str(ROOT / "scripts/run_apu_p5_corpus_rtl.py"),
            "--manifest",
            str(manifest_path),
            "--bundle",
            str(bundle),
            "--corpus",
            str(corpus),
            "--build-dir",
            str(tmp_path / "rtl"),
            "--output",
            str(output),
            "--jobs",
            "2",
            "--timeout-seconds",
            "300",
        ],
        check=True,
    )
    result = json.loads(output.read_text(encoding="utf-8"))
    assert result["production_rtl"]["complete"] is True
    assert result["production_rtl"]["simulator_runs"] == 2
    production = result["files"][0]["production_rtl"]
    assert production["agreement"] is True
    assert production["icarus"]["result"] == production["verilator"]["result"]
    assert production["icarus"]["pcm_sha256"] == empty_hash
    for simulator in ("icarus", "verilator"):
        assert production[simulator]["timeout_seconds"] == 300
        assert production[simulator]["command"]
        assert production[simulator]["verification_sha256"]


def test_p5_corpus_timeout_result_is_never_reused() -> None:
    identity = {
        "source_sha256": "source",
        "bundle_sha256": "bundle",
        "verification_sha256": "verification",
        "truth_sha256": "truth",
    }
    assert not _can_reuse_result(
        {"status": "failed", **identity}, "source", "bundle", "verification", "truth"
    )
    assert _can_reuse_result(
        {"status": "passed", **identity}, "source", "bundle", "verification", "truth"
    )


def test_p5_corpus_cache_requires_canonical_bam_truth_identity() -> None:
    record = {
        "path": "case.flac",
        "sha256": "source",
        "expected": "supported",
        "production_truth": {"status": "success", "code": 0, "reason": 0},
    }
    truth = _truth_sha256(record)
    identity = {
        "source_sha256": "source",
        "bundle_sha256": "bundle",
        "verification_sha256": "verification",
        "truth_sha256": truth,
    }
    assert _can_reuse_result(
        {"status": "passed", **identity}, "source", "bundle", "verification", truth
    )
    changed = {**record, "production_truth": {"status": "error", "code": 4, "reason": 0x10}}
    assert not _can_reuse_result(
        {"status": "passed", **identity},
        "source",
        "bundle",
        "verification",
        _truth_sha256(changed),
    )
    assert not _can_migrate_pass_result(
        {
            "status": "passed",
            **identity,
            "verification_sha256": next(iter(MIGRATABLE_VERIFICATION_SHA256)),
        },
        "source",
        "bundle",
        _truth_sha256(changed),
    )


def test_p5_corpus_migrates_only_known_pre_wallclock_passes() -> None:
    legacy_verification = next(iter(MIGRATABLE_VERIFICATION_SHA256))
    cached = {
        "status": "passed",
        "source_sha256": "source",
        "bundle_sha256": "bundle",
        "verification_sha256": legacy_verification,
        "truth_sha256": "truth",
        "command": ["vvp", "fixture", "+MAX_CYCLES=5000000"],
    }
    assert _can_migrate_pass_result(cached, "source", "bundle", "truth")
    assert not _can_migrate_pass_result({**cached, "status": "failed"}, "source", "bundle", "truth")
    assert not _can_migrate_pass_result(
        {**cached, "verification_sha256": "future"}, "source", "bundle", "truth"
    )
    assert not _can_migrate_pass_result(
        {**cached, "command": [*cached["command"], "+WALLCLOCK_NS=0"]},
        "source",
        "bundle",
        "truth",
    )


def test_p5_corpus_output_size_mismatch_is_structured_and_retryable(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    source = tmp_path / "case.flac"
    source.write_bytes(b"fLaC")
    image = tmp_path / "image.apumc"
    image.write_bytes(b"image")
    record = {
        "path": "case.flac",
        "sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
        "expected": "malformed",
        "production_truth": {
            "status": "error",
            "code": 4,
            "stage": 4,
            "warnings": 1,
            "reason": 0x10,
            "error_offset": 0,
            "input_used": 4,
            "output_bytes": 0,
            "frames": 0,
            "source_info": 0,
            "pcm_sha256": hashlib.sha256(b"").hexdigest(),
        },
    }
    stdout = (
        "APU_P5_CORPUS_RESULT status=00010304 input_used=00000004 "
        "output_bytes=00000004 frames=00000000 source_info=00000000 "
        "cycles=00000010 detail=02010010 error_status=00000207 "
        "error_address=40000000 error_detail=02010010 elapsed=10"
    )
    monkeypatch.setattr(
        corpus_runner,
        "_run_command",
        lambda command, cwd, timeout: {
            "command": command,
            "duration_seconds": 0.1,
            "exit_code": 0,
            "stdout": stdout,
            "stderr": "",
            "timed_out": False,
        },
    )
    case_dir = tmp_path / "case"
    case_dir.mkdir()
    result = corpus_runner._run_case(
        "verilator",
        tmp_path / "fake-vlt",
        tmp_path / "fake-vvp",
        image,
        source,
        record,
        case_dir,
        300,
        "bundle",
        "verification",
    )
    assert result["status"] == "failed"
    assert (
        "verilator output size 0 does not match RESULT_OUTPUT_BYTES 4" in result["execution_errors"]
    )


def test_p5_production_transport_matches_icarus_and_verilator(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    sv2v = shutil.which("sv2v")
    verilator = shutil.which("verilator")
    if None in (iverilog, vvp, sv2v, verilator):
        raise RuntimeError("P5 requires Icarus, vvp, sv2v, and Verilator")
    common = ROOT / "rtl/managed/clusterip/common/rtl"
    multimedia = ROOT / "rtl/ip/multimedia"
    filelist = tmp_path / "apu_p5_transport.fl"
    filelist.write_text(
        "\n".join(
            [
                "+define+SV_ASSRT_DISABLE",
                f"+incdir+{multimedia}",
                str(common / "interface/axi4_stream_if.sv"),
                str(common / "utils/fifo.sv"),
                str(multimedia / "apu_codec_transport.sv"),
                str(ROOT / "tests/rtl/apu_p5_transport_tb.sv"),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "apu_p5_transport_tb.v"
    subprocess.run(
        [
            sys.executable,
            str(ROOT / "rtl/mini/script/convt_sv2v.py"),
            "-f",
            str(filelist),
            "--output",
            str(converted),
        ],
        check=True,
    )
    executable = tmp_path / "apu_p5_transport_tb"
    subprocess.run(
        [iverilog, "-g2012", "-s", "apu_p5_transport_tb", "-o", str(executable), str(converted)],
        check=True,
    )
    icarus = subprocess.run([vvp, str(executable)], check=True, capture_output=True, text=True)
    assert "APU-P5 production transport passed" in icarus.stdout

    verilator_dir = tmp_path / "verilator"
    ccache_dir = tmp_path / "ccache"
    ccache_dir.mkdir()
    environment = {
        **os.environ,
        "CCACHE_DIR": str(ccache_dir),
        "CCACHE_TEMPDIR": str(ccache_dir),
    }
    subprocess.run(
        [
            verilator,
            "--binary",
            "--timing",
            "-Wno-fatal",
            "--top-module",
            "apu_p5_transport_tb",
            "--Mdir",
            str(verilator_dir),
            str(converted),
        ],
        check=True,
        env=environment,
    )
    verilator_run = subprocess.run(
        [str(verilator_dir / "Vapu_p5_transport_tb")], check=True, capture_output=True, text=True
    )
    assert "APU-P5 production transport passed" in verilator_run.stdout


def test_p5_v2_4096_word_loader_store_and_sequencer(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    verilator = shutil.which("verilator")
    if None in (iverilog, vvp, verilator):
        raise RuntimeError("P5 capacity verification requires Icarus, vvp, and Verilator")

    instructions = [Instruction(InstructionClass.CONTROL, ControlOpcode.NOP)] * 4096
    instructions[0] = Instruction(InstructionClass.CONTROL, ControlOpcode.END)
    instructions[2045] = Instruction(
        InstructionClass.CONTROL, ControlOpcode.JUMP_FWD, immediate=2048
    )
    instructions[2048] = Instruction(InstructionClass.SCALAR, 1, dst=1, immediate=0x800)
    instructions[3072] = Instruction(InstructionClass.SCALAR, 1, dst=2, immediate=0xC00)
    instructions[4093] = Instruction(InstructionClass.CONTROL, ControlOpcode.END)
    instructions[4094] = Instruction(InstructionClass.CONTROL, ControlOpcode.END)
    instructions[4095] = Instruction(InstructionClass.CONTROL, ControlOpcode.END)
    entries = [
        Entry(0, 2045, 2045, 4094, 1, 4),
        Entry(1, 0, 0, 0, 1, 1),
        Entry(2, 2048, 2048, 4093, 1, 4096),
    ]
    bundle = build_apumc(instructions, entries, 0x0005000000000002, target="p5", abi=APUMC_ABI_V2)
    image = tmp_path / "apu_p5_capacity.hex"
    image.write_text(
        "".join(
            f"{int.from_bytes(bundle[offset : offset + 4], 'little'):08x}\n"
            for offset in range(0, len(bundle), 4)
        ),
        encoding="utf-8",
    )

    def write_image(name: str, payload: bytes) -> Path:
        path = tmp_path / f"{name}.hex"
        path.write_text(
            "".join(
                f"{int.from_bytes(payload[offset : offset + 4], 'little'):08x}\n"
                for offset in range(0, len(payload), 4)
            ),
            encoding="utf-8",
        )
        return path

    def with_crc(payload: bytearray) -> bytes:
        struct.pack_into("<I", payload, 44, crc32_iso_hdlc(payload[64:]))
        return bytes(payload)

    short_instructions = [
        Instruction(InstructionClass.CONTROL, ControlOpcode.JUMP_FWD, immediate=1),
        Instruction(InstructionClass.CONTROL, ControlOpcode.END),
        Instruction(InstructionClass.CONTROL, ControlOpcode.END),
    ]
    short_entries = [Entry(index, 0, 0, 2, 1, 4) for index in range(3)]
    v1 = build_apumc(short_instructions, short_entries, target="p5", abi=0x00010000)
    v2 = build_apumc(short_instructions, short_entries, target="p5", abi=APUMC_ABI_V2)
    rejection_cases: list[tuple[Path, int, int, int, int]] = []

    mutated = bytearray(v1)
    struct.pack_into("<I", mutated, 4, 0x00030000)
    rejection_cases.append(
        (write_image("unknown_abi", bytes(mutated)), 0x04, 0x30000004, 0x00030000, 9)
    )
    for name, source, bit in (("v1_descriptor_high", v1, 15), ("v2_descriptor_reserved", v2, 16)):
        mutated = bytearray(source)
        word = struct.unpack_from("<I", mutated, 64)[0] | (1 << bit)
        struct.pack_into("<I", mutated, 64, word)
        rejection_cases.append((write_image(name, with_crc(mutated)), 0x08, 0x30000040, word, 9))
    for name, source, bit in (("v1_immediate_high", v1, 11), ("v2_immediate_reserved", v2, 12)):
        mutated = bytearray(source)
        word = struct.unpack_from("<Q", mutated, 192)[0] | (1 << bit)
        struct.pack_into("<Q", mutated, 192, word)
        rejection_cases.append(
            (write_image(name, with_crc(mutated)), 0x10, 0x300000C0, 0x01800001, 9)
        )
    for name, source, count in (
        ("v1_count_zero", v1, 0),
        ("v1_count_2049", v1, 2049),
        ("v2_count_4097", v2, 4097),
    ):
        mutated = bytearray(source)
        struct.pack_into("<I", mutated, 12, count)
        rejection_cases.append((write_image(name, bytes(mutated)), 0x08, 0x3000000C, count, 9))
    mutated = bytearray(bundle)
    mutated[-1] ^= 0x80
    actual_crc = crc32_iso_hdlc(mutated[64:])
    rejection_cases.append(
        (write_image("upper_bank_crc", bytes(mutated)), 0x40, 0x3000002C, actual_crc, 10)
    )
    multimedia = ROOT / "rtl/ip/multimedia"
    sources = [
        multimedia / "apu_microcode_pkg.sv",
        multimedia / "apu_microcode_loader.sv",
        multimedia / "apu_control_store.sv",
        multimedia / "apu_codec_sequencer.sv",
        ROOT / "tests/rtl/apu_p5_capacity_tb.sv",
    ]
    filelist = tmp_path / "apu_p5_capacity.fl"
    filelist.write_text(
        "\n".join(
            [
                "+define+SV_ASSRT_DISABLE",
                f"+incdir+{multimedia}",
                *(str(source) for source in sources),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "apu_p5_capacity.v"
    subprocess.run(
        [
            sys.executable,
            str(ROOT / "rtl/mini/script/convt_sv2v.py"),
            "-f",
            str(filelist),
            "--output",
            str(converted),
        ],
        check=True,
    )
    executable = tmp_path / "apu_p5_capacity"
    subprocess.run(
        [iverilog, "-g2012", "-s", "apu_p5_capacity_tb", "-o", str(executable), str(converted)],
        check=True,
    )
    result = subprocess.run(
        [vvp, str(executable), f"+IMAGE={image}"], check=True, capture_output=True, text=True
    )
    assert "APU-P5 4096-word loader/store/sequencer passed" in result.stdout
    for case_image, status, fault_addr, fault_detail, fault_code in rejection_cases:
        rejected = subprocess.run(
            [
                vvp,
                str(executable),
                f"+IMAGE={case_image}",
                f"+EXPECT_STATUS={status:x}",
                f"+EXPECT_FAULT_ADDR={fault_addr:x}",
                f"+EXPECT_FAULT_DETAIL={fault_detail:x}",
                f"+EXPECT_FAULT_CODE={fault_code:x}",
            ],
            check=True,
            capture_output=True,
            text=True,
        )
        assert "APU-P5 version rejection passed" in rejected.stdout

    verilator_dir = tmp_path / "capacity_verilator"
    ccache_dir = tmp_path / "capacity_ccache"
    ccache_dir.mkdir()
    environment = {
        **os.environ,
        "CCACHE_DIR": str(ccache_dir),
        "CCACHE_TEMPDIR": str(ccache_dir),
    }
    subprocess.run(
        [
            verilator,
            "--binary",
            "--timing",
            "-Wno-fatal",
            "--top-module",
            "apu_p5_capacity_tb",
            "--Mdir",
            str(verilator_dir),
            str(converted),
        ],
        check=True,
        env=environment,
    )
    verilator_run = subprocess.run(
        [str(verilator_dir / "Vapu_p5_capacity_tb"), f"+IMAGE={image}"],
        check=True,
        capture_output=True,
        text=True,
    )
    assert "APU-P5 4096-word loader/store/sequencer passed" in verilator_run.stdout
    for case_image, status, fault_addr, fault_detail, fault_code in rejection_cases:
        rejected = subprocess.run(
            [
                str(verilator_dir / "Vapu_p5_capacity_tb"),
                f"+IMAGE={case_image}",
                f"+EXPECT_STATUS={status:x}",
                f"+EXPECT_FAULT_ADDR={fault_addr:x}",
                f"+EXPECT_FAULT_DETAIL={fault_detail:x}",
                f"+EXPECT_FAULT_CODE={fault_code:x}",
            ],
            check=True,
            capture_output=True,
            text=True,
        )
        assert "APU-P5 version rejection passed" in rejected.stdout


def test_p5_direct_wav_uses_product_loader_dma_sequencer_and_tx(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    sv2v = shutil.which("sv2v")
    verilator = shutil.which("verilator")
    if None in (iverilog, vvp, sv2v, verilator):
        raise RuntimeError("P5 integration requires Icarus, vvp, sv2v, and Verilator")
    multimedia = ROOT / "rtl/ip/multimedia"
    common = ROOT / "rtl/managed/clusterip/common/rtl"
    assembly = assemble(
        (multimedia / "apu_p5_codecs.apus").read_text(encoding="utf-8"),
        "p5",
        coefficient_bytes(),
    )
    image = tmp_path / "apu_p5.hex"
    image.write_text(
        "".join(
            f"{int.from_bytes(assembly.bundle[offset : offset + 4], 'little'):08x}\n"
            for offset in range(0, len(assembly.bundle), 4)
        ),
        encoding="utf-8",
    )
    streaminfo = bytearray(34)
    streaminfo[0:2] = (16).to_bytes(2, "big")
    streaminfo[2:4] = (16).to_bytes(2, "big")
    streaminfo[10:18] = ((48000 << 44) | (15 << 36) | 16).to_bytes(8, "big")
    frame_header = ((0x3FFE << 18) | (6 << 12) | (4 << 1)).to_bytes(4, "big")
    frame_header += b"\x00\x0f"
    frame_header += bytes([crc8(frame_header)])
    frame = frame_header + b"\x00\xff\xfe"
    frame += crc16(frame).to_bytes(2, "big")
    flac = b"fLaC" + bytes([0x80, 0, 0, 34]) + streaminfo + frame
    flac_image = tmp_path / "apu_p5_constant_flac.hex"
    flac_image.write_text(
        "".join(
            f"{int.from_bytes(flac[offset : offset + 4].ljust(4, bytes(1)), 'little'):08x}\n"
            for offset in range(0, len(flac), 4)
        ),
        encoding="utf-8",
    )
    streaminfo24 = bytearray(34)
    streaminfo24[0:2] = (128).to_bytes(2, "big")
    streaminfo24[2:4] = (128).to_bytes(2, "big")
    streaminfo24[10:18] = ((96000 << 44) | (23 << 36) | 128).to_bytes(8, "big")
    frame_header24 = ((0x3FFE << 18) | (6 << 12) | (6 << 1)).to_bytes(4, "big")
    frame_header24 += b"\x00\x7f"
    frame_header24 += bytes([crc8(frame_header24)])
    frame24 = frame_header24 + b"\x00" + (-2).to_bytes(3, "big", signed=True)
    frame24 += crc16(frame24).to_bytes(2, "big")
    flac24 = b"fLaC" + bytes([0x80, 0, 0, 34]) + streaminfo24 + frame24
    flac24_image = tmp_path / "apu_p5_constant_24bit_flac.hex"
    flac24_image.write_text(
        "".join(
            f"{int.from_bytes(flac24[offset : offset + 4].ljust(4, bytes(1)), 'little'):08x}\n"
            for offset in range(0, len(flac24), 4)
        ),
        encoding="utf-8",
    )
    sources = [
        common / "interface/apb4_if.sv",
        common / "interface/axi4_if.sv",
        common / "interface/axi4_stream_if.sv",
        common / "utils/register.sv",
        common / "utils/fifo.sv",
        ROOT / "rtl/tech/tc_sram.sv",
        ROOT / "rtl/ip/peripheral/dma_axi4_master.sv",
        *(
            multimedia / name
            for name in (
                "apu_microcode_pkg.sv",
                "apu_dma.sv",
                "apu_ring_scheduler.sv",
                "apu_stream_router.sv",
                "apu_control_store.sv",
                "apu_microcode_loader.sv",
                "apu_local_sram.sv",
                "apu_kws_engine.sv",
                "apu_kws_sram_client.sv",
                "apu_kws_model_loader.sv",
                "apu_bitstream_engine.sv",
                "apu_entropy_engine.sv",
                "apu_reconstruction_engine.sv",
                "apu_transform_engine.sv",
                "apu_resampler.sv",
                "apu_kernel_engine.sv",
                "apu_primitive_dispatcher.sv",
                "apu_codec_sequencer.sv",
                "apu_codec_transport.sv",
                "apu_codec_controller.sv",
                "apu_reg.sv",
                "apb4_apu.sv",
            )
        ),
        ROOT / "tests/rtl/apu_p5_integration_tb.sv",
    ]
    filelist = tmp_path / "apu_p5_integration.fl"
    filelist.write_text(
        "\n".join(
            [
                "+define+SV_ASSRT_DISABLE",
                f"+incdir+{common}",
                f"+incdir+{common / 'interface'}",
                f"+incdir+{multimedia}",
                *(str(source) for source in sources),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "apu_p5_integration.v"
    subprocess.run(
        [
            sys.executable,
            str(ROOT / "rtl/mini/script/convt_sv2v.py"),
            "-f",
            str(filelist),
            "--output",
            str(converted),
        ],
        check=True,
    )
    executable = tmp_path / "apu_p5_integration"
    subprocess.run(
        [iverilog, "-g2012", "-s", "apu_p5_integration_tb", "-o", str(executable), str(converted)],
        check=True,
    )
    result = subprocess.run(
        [
            vvp,
            str(executable),
            f"+IMAGE={image}",
            f"+FLAC={flac_image}",
            f"+FLAC24={flac24_image}",
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    assert "APU-P5 direct WAV product integration passed" in result.stdout
    assert "APU-P5 PLAYBACK_44100_48000" in result.stdout
    assert "APU-P5 PLAYBACK_24B_96000" in result.stdout
    assert "APU-P5 PLAYBACK_FLAC_24B_96000" in result.stdout
    assert "APU-P5 PLAYBACK_8000_96000" in result.stdout

    verilator_dir = tmp_path / "integration_verilator"
    ccache_dir = tmp_path / "integration_ccache"
    ccache_dir.mkdir()
    environment = {
        **os.environ,
        "CCACHE_DIR": str(ccache_dir),
        "CCACHE_TEMPDIR": str(ccache_dir),
    }
    subprocess.run(
        [
            verilator,
            "--binary",
            "--timing",
            "-Wno-fatal",
            "--top-module",
            "apu_p5_integration_tb",
            "--Mdir",
            str(verilator_dir),
            str(converted),
        ],
        check=True,
        env=environment,
    )
    verilator_result = subprocess.run(
        [
            str(verilator_dir / "Vapu_p5_integration_tb"),
            f"+IMAGE={image}",
            f"+FLAC={flac_image}",
            f"+FLAC24={flac24_image}",
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    assert "APU-P5 direct WAV product integration passed" in verilator_result.stdout
    assert "APU-P5 PLAYBACK_44100_48000" in verilator_result.stdout
    assert "APU-P5 PLAYBACK_24B_96000" in verilator_result.stdout
    assert "APU-P5 PLAYBACK_FLAC_24B_96000" in verilator_result.stdout
    assert "APU-P5 PLAYBACK_8000_96000" in verilator_result.stdout
