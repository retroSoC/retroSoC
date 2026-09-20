"""NPU-P3 job-execution RTL unit tests (Icarus and Verilator).

``test_npu_dma`` drives the AXI4 DMA engine testbench. ``test_npu_job_decoder``
drives the descriptor fetch/validation testbench with descriptor images and
expected verdicts generated here, using ``scripts/npu_descriptors.py`` as the
golden validator (fault code and ABI word parity). ``test_npu_core`` drives the
job-level testbench (production launch interface into npu_core + npu_dma over a
byte-memory BFM) with directed transport jobs whose stored bytes are checked
against a Python golden model of the documented P3 transport-content echo rule
(output byte (oy, ox, c) echoes the gather byte at reduction index c mod G).
``test_npu_job`` drives the shell-level job-admission testbench (apb4_npu
driven through the software APB4 ABI over the same byte-memory BFM): START
admission and PSLVERR rules, terminal DONE/ABORTED/ERROR mirrors with their
IRQ events, RESULT_VALID lifetime, the no-progress watchdog, descriptor
validation error propagation, and byte-exact golden stores.
"""

from __future__ import annotations

import os
import shutil
import struct
import subprocess
import sys
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
COMMON = ROOT / "rtl/managed/clusterip/common/rtl"
MULTIMEDIA = ROOT / "rtl/ip/multimedia"
TECH = ROOT / "rtl/tech"

sys.path.insert(0, str(ROOT / "scripts"))
from npu_descriptors import (  # noqa: E402
    DESCRIPTOR_BYTES,
    Descriptor,
    DescriptorError,
    validate_descriptor,
)
import npu_reference  # noqa: E402

INCDIRS = [COMMON, COMMON / "interface", MULTIMEDIA]
COMMON_SOURCES = [
    COMMON / "interface/axi4_if.sv",
]
DMA_SOURCES = [
    MULTIMEDIA / "npu_dma.sv",
]
DECODER_SOURCES = [
    MULTIMEDIA / "npu_pkg.sv",
    MULTIMEDIA / "npu_dma.sv",
    MULTIMEDIA / "npu_job_decoder.sv",
]
CORE_SOURCES = [
    COMMON / "utils/register.sv",
    MULTIMEDIA / "npu_pkg.sv",
    TECH / "tc_sram.sv",
    MULTIMEDIA / "npu_local_sram.sv",
    MULTIMEDIA / "npu_patch_packer.sv",
    MULTIMEDIA / "npu_dma.sv",
    MULTIMEDIA / "npu_job_decoder.sv",
    MULTIMEDIA / "npu_mac_array.sv",
    MULTIMEDIA / "npu_accumulator.sv",
    MULTIMEDIA / "npu_vector.sv",
    MULTIMEDIA / "npu_requantizer.sv",
    MULTIMEDIA / "npu_scheduler.sv",
    MULTIMEDIA / "npu_core.sv",
]

MEM_BASE = 0x3000_0000
DEC_MEM_BYTES = 0x40000  # decoder TB memory: 256 KiB
CORE_MEM_BYTES = 0x80000  # core TB memory: 512 KiB
GAP_FILL = 0xA5

# fault codes
F_DESCRIPTOR = 1
F_UNSUPPORTED = 2
F_RANGE = 3
F_AXI_READ = 4
F_AXI_WRITE = 5
F_AXI_PROTOCOL = 6
F_ARITHMETIC = 7
F_NO_PROGRESS = 8
F_LOCAL_STATE = 9
F_RESET_CANCELLED = 10

# result codes
R_DONE = 1
R_ERROR = 2
R_ABORTED = 3
R_RESET_CANCELLED = 4

UNIT_KERNEL_STRIDE = 0x01010101


def _tools() -> dict[str, str]:
    tools: dict[str, str] = {}
    missing = []
    for name in ("iverilog", "vvp", "sv2v", "verilator"):
        path = shutil.which(name)
        if path is None:
            missing.append(name)
        else:
            tools[name] = path
    if missing:
        pytest.fail(f"required simulation tools missing: {', '.join(missing)}")
    return tools


def _build_iverilog(tools: dict[str, str], tmp_path: Path, name: str, top: str,
                    sources: list[Path]) -> Path:
    filelist = tmp_path / f"{name}.fl"
    filelist.write_text(
        "\n".join(
            [
                "+define+SV_ASSRT_DISABLE",
                "+define+PDK_BEHAV",
                *(f"+incdir+{incdir}" for incdir in INCDIRS),
                *(str(source) for source in sources),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / f"{name}.v"
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
    simulation = tmp_path / f"{name}.iverilog"
    subprocess.run(
        [tools["iverilog"], "-g2012", "-s", top, "-o", str(simulation), str(converted)],
        check=True,
    )
    return simulation


def _build_verilator(tools: dict[str, str], tmp_path: Path, name: str, top: str,
                     sources: list[Path]) -> Path:
    object_dir = tmp_path / f"obj-{name}"
    ccache_dir = tmp_path / f"ccache-{name}"
    ccache_dir.mkdir()
    subprocess.run(
        [
            tools["verilator"],
            "--binary",
            "--timing",
            "-Wno-fatal",
            "+define+PDK_BEHAV",
            "--top-module",
            top,
            *(f"+incdir+{incdir}" for incdir in INCDIRS),
            *(str(source) for source in sources),
            "-Mdir",
            str(object_dir),
            "-o",
            "simv",
        ],
        check=True,
        text=True,
        capture_output=True,
        env={
            **os.environ,
            "CCACHE_DIR": str(ccache_dir),
            "CCACHE_TEMPDIR": str(ccache_dir),
        },
    )
    return object_dir / "simv"


def _run_p3_test(tools: dict[str, str], simulator: str, tmp_path: Path, name: str, top: str,
                 testbench: Path, sources: list[Path], marker: str) -> None:
    full_sources = [*COMMON_SOURCES, *sources, testbench]
    if simulator == "iverilog":
        simulation = _build_iverilog(tools, tmp_path, name, top, full_sources)
        command = [tools["vvp"], str(simulation)]
    elif simulator == "verilator":
        command = [str(_build_verilator(tools, tmp_path, name, top, full_sources))]
    else:
        raise AssertionError(f"unknown simulator {simulator}")
    result = subprocess.run(command, check=True, text=True, capture_output=True)
    assert marker in result.stdout


def _build_sim(tools: dict[str, str], simulator: str, tmp_path: Path, name: str, top: str,
               testbench: Path, sources: list[Path]) -> list[str]:
    full_sources = [*COMMON_SOURCES, *sources, testbench]
    if simulator == "iverilog":
        return [tools["vvp"], str(_build_iverilog(tools, tmp_path, name, top, full_sources))]
    if simulator == "verilator":
        return [str(_build_verilator(tools, tmp_path, name, top, full_sources))]
    raise AssertionError(f"unknown simulator {simulator}")


def _run(command: list[str], plusargs: list[str], marker: str) -> str:
    result = subprocess.run([*command, *plusargs], check=True, text=True, capture_output=True)
    assert marker in result.stdout
    return result.stdout


# ---------------------------------------------------------------------------
# Descriptor construction (mirrors scripts/npu_descriptors.py ABI 1.0)
# ---------------------------------------------------------------------------


def _slot_bases(slot: int, shift: int = 0) -> dict[str, int]:
    # fully disjoint operand regions per descriptor slot (decoder validation
    # is arithmetic-only; the core TB executes the contents)
    return {
        "in0": 0x3000_4000 + (slot + shift) * 0x4000,
        "in1": 0x3001_4000 + (slot + shift) * 0x4000,
        "out": 0x3002_0000 + (slot + shift) * 0x8000,
        "w": 0x3004_0000 + (slot + shift) * 0x8000,
        "p": 0x3006_0000 + (slot + shift) * 0x8000,
    }


def _valid_descriptor(opcode: int, slot: int, shift: int = 0) -> Descriptor:
    """One ABI-1.0-valid record for opcode in operand slot `slot`."""
    b = _slot_bases(slot, shift)
    d = Descriptor()
    d.version_opcode = 0x0100_0000 | opcode
    d.act_min = -128
    d.act_max = 127
    d.input0_base = b["in0"]
    d.input1_base = 0
    d.output_base = b["out"]
    d.param_base = 0
    d.weight_base = 0
    d.weight_bytes = 0
    d.param_bytes = 0
    d.input1_zero = 0

    if opcode == 1:  # CONV2D
        h, w, cin, cout = 5, 6, 3, 5
        kh, kw, sh, sw = 3, 2, 1, 2
        pt, pb, pl, pr = 1, 1, 0, 1
        oh = (h + pt + pb - kh) // sh + 1
        ow = (w + pl + pr - kw) // sw + 1
        d.input_hw = (w << 16) | h
        d.channels = (cout << 16) | cin
        d.output_hw = (ow << 16) | oh
        d.input0_row_bytes = w * cin + 2
        d.output_row_bytes = ow * cout + 1
        d.kernel_stride = (sw << 24) | (sh << 16) | (kw << 8) | kh
        d.padding = (pr << 24) | (pl << 16) | (pb << 8) | pt
        d.tile_hw = (2 << 8) | 2
        full_k = kh * kw * cin
        d.k_slice = 7
        assert d.k_slice <= full_k
        d.input0_bytes = (h - 1) * d.input0_row_bytes + w * cin
        d.output_bytes = (oh - 1) * d.output_row_bytes + ow * cout
        d.weight_base = b["w"]
        d.weight_bytes = ((cout + 7) // 8) * full_k * 8
        d.param_base = b["p"]
        d.param_bytes = cout * 16
    elif opcode == 2:  # DEPTHWISE3X3
        h, w, cin = 6, 7, 5
        sh = sw = 2
        pt, pl = 1, 1
        oh = (h + pt - 3) // sh + 1
        ow = (w + pl - 3) // sw + 1
        d.input_hw = (w << 16) | h
        d.channels = (cin << 16) | cin
        d.output_hw = (ow << 16) | oh
        d.input0_row_bytes = w * cin + 1
        d.output_row_bytes = ow * cin + 1
        d.kernel_stride = (sw << 24) | (sh << 16) | (3 << 8) | 3
        d.padding = pl << 16 | pt
        d.tile_hw = (2 << 8) | 2
        d.k_slice = 9
        d.input0_bytes = (h - 1) * d.input0_row_bytes + w * cin
        d.output_bytes = (oh - 1) * d.output_row_bytes + ow * cin
        d.weight_base = b["w"]
        d.weight_bytes = ((cin + 7) // 8) * 72
        d.param_base = b["p"]
        d.param_bytes = cin * 16
    elif opcode == 3:  # FULLY_CONNECTED
        cin, cout = 13, 4
        d.input_hw = (1 << 16) | 1
        d.channels = (cout << 16) | cin
        d.output_hw = (1 << 16) | 1
        d.input0_row_bytes = cin + 3
        d.output_row_bytes = cout + 4
        d.kernel_stride = UNIT_KERNEL_STRIDE
        d.padding = 0
        d.tile_hw = (1 << 8) | 1
        d.k_slice = 13
        d.input0_bytes = cin
        d.output_bytes = cout
        d.weight_base = b["w"]
        d.weight_bytes = ((cout + 7) // 8) * cin * 8
        d.param_base = b["p"]
        d.param_bytes = cout * 16
    elif opcode == 4:  # ADD
        h, w, cin = 2, 3, 3
        d.input_hw = (w << 16) | h
        d.channels = (cin << 16) | cin
        d.output_hw = (w << 16) | h
        d.input0_row_bytes = w * cin + 3
        d.output_row_bytes = w * cin + 3
        d.input1_row_bytes = w * cin + 3
        d.input1_base = b["in1"]
        d.input1_bytes = (h - 1) * d.input1_row_bytes + w * cin
        d.input1_zero = -5
        d.kernel_stride = UNIT_KERNEL_STRIDE
        d.padding = 0
        d.tile_hw = (2 << 8) | 2
        d.k_slice = 1
        d.input0_bytes = (h - 1) * d.input0_row_bytes + w * cin
        d.output_bytes = (h - 1) * d.output_row_bytes + w * cin
        d.param_base = b["p"]
        d.param_bytes = 32
    elif opcode in (5, 6):  # MAX_POOL / AVERAGE_POOL
        h, w, cin = 6, 6, 4
        kh = kw = 3 if opcode == 5 else 2
        sh = sw = 1 if opcode == 5 else 2
        pt = pb = pl = pr = 1
        oh = (h + pt + pb - kh) // sh + 1
        ow = (w + pl + pr - kw) // sw + 1
        d.input_hw = (w << 16) | h
        d.channels = (cin << 16) | cin
        d.output_hw = (ow << 16) | oh
        d.input0_row_bytes = w * cin
        d.output_row_bytes = ow * cin
        d.kernel_stride = (sw << 24) | (sh << 16) | (kw << 8) | kh
        d.padding = (pr << 24) | (pl << 16) | (pb << 8) | pt
        d.tile_hw = (2 << 8) | 2
        d.k_slice = min(5, kh * kw)
        d.input0_bytes = (h - 1) * d.input0_row_bytes + w * cin
        d.output_bytes = (oh - 1) * d.output_row_bytes + ow * cin
        d.input0_zero = 11
        d.output_zero = 11
    elif opcode == 7:  # GLOBAL_AVERAGE_POOL
        h, w, cin = 4, 5, 6
        d.input_hw = (w << 16) | h
        d.channels = (cin << 16) | cin
        d.output_hw = (1 << 16) | 1
        d.input0_row_bytes = w * cin + 2
        d.output_row_bytes = cin
        d.kernel_stride = 0
        d.padding = 0
        d.tile_hw = (1 << 8) | 1
        d.k_slice = 9
        d.input0_bytes = (h - 1) * d.input0_row_bytes + w * cin
        d.output_bytes = cin
        d.input0_zero = -3
        d.output_zero = -3
    elif opcode == 8:  # CLAMP
        h, w, cin = 3, 5, 4
        d.input_hw = (w << 16) | h
        d.channels = (cin << 16) | cin
        d.output_hw = (w << 16) | h
        d.input0_row_bytes = w * cin + 4
        d.output_row_bytes = w * cin + 12
        d.kernel_stride = UNIT_KERNEL_STRIDE
        d.padding = 0
        d.tile_hw = (2 << 8) | 2
        d.k_slice = 1
        d.input0_bytes = (h - 1) * d.input0_row_bytes + w * cin
        d.output_bytes = (h - 1) * d.output_row_bytes + w * cin
        d.input0_zero = 7
        d.output_zero = 7
    else:
        raise AssertionError(f"no factory for opcode {opcode}")
    validate_descriptor(d, descriptor_region=(MEM_BASE, 4 * DESCRIPTOR_BYTES))
    return d


def _words_of(desc: Descriptor) -> list[int]:
    return list(struct.unpack(f"<{DESCRIPTOR_BYTES // 4}I", desc.to_bytes()))


def _image_hex(path: Path, words: list[int]) -> None:
    path.write_text("\n".join(f"{word & 0xFFFFFFFF:08x}" for word in words) + "\n",
                    encoding="utf-8")


def _descriptor_case_image(records: list[Descriptor], count: int) -> list[int]:
    words: list[int] = []
    for record in records:
        words.extend(_words_of(record))
    while len(words) < count * 32:
        words.append(0xDEAD0000 | (len(words) & 0xFFFF))
    return words


def _expected_fault(records: list[Descriptor], count: int):
    """(code, word, index) of the first validator failure, or None."""
    region = (MEM_BASE, count * DESCRIPTOR_BYTES)
    for index, record in enumerate(records[:count]):
        wire = Descriptor.from_bytes(record.to_bytes())
        try:
            validate_descriptor(wire, descriptor_region=region)
        except DescriptorError as error:
            return error.code, error.word, index
    return None


# ---------------------------------------------------------------------------
# Decoder testbench cases
# ---------------------------------------------------------------------------


def _decoder_cases(tmp_path: Path) -> list[list[str]]:
    cases: list[list[str]] = []

    def emit(name: str, records: list[Descriptor], count: int, mode: int, fcode: int,
             findex: int, fword: int, rderr_addr: int = 0xFFFFFFFF,
             rderr_code: int = 0, rderr_badid: int = 0) -> None:
        image = tmp_path / f"dec_{name}.hex"
        _image_hex(image, _descriptor_case_image(records, count))
        cases.append(
            [
                f"+IMG={image}",
                f"+BASE={MEM_BASE:x}",
                f"+COUNT={count}",
                f"+MODE={mode}",
                f"+FCODE={fcode}",
                f"+FINDEX={findex}",
                f"+FWORD={fword & 0xFFFFFFFF}",
                f"+RDERR_ADDR={rderr_addr:x}",
                f"+RDERR_CODE={rderr_code}",
                f"+RDERR_BADID={rderr_badid}",
                f"+NAME={name}",
            ]
        )

    # valid accept per opcode, plus one multi-record in-order traversal, plus
    # the ADD input0/input1 alias legality case, plus pause-during-fetch
    for opcode in range(1, 9):
        emit(f"valid_op{opcode}", [_valid_descriptor(opcode, 0)], 1, 0, 0, 0, 0xFFFFFFFF)
    multi = [
        _valid_descriptor(8, 0),
        _valid_descriptor(1, 1),
        _valid_descriptor(7, 2),
        _valid_descriptor(4, 3),
    ]
    assert _expected_fault(multi, 4) is None
    emit("valid_multi4", multi, 4, 0, 0, 0, 0xFFFFFFFF)
    alias = _valid_descriptor(4, 0)
    alias.input1_base = alias.input0_base
    validate_descriptor(alias, descriptor_region=(MEM_BASE, 2 * DESCRIPTOR_BYTES))
    emit("valid_add_alias", [alias], 1, 0, 0, 0, 0xFFFFFFFF)
    emit("pause_fetch", [_valid_descriptor(8, 0), _valid_descriptor(1, 1)], 2, 3, 0, 0,
         0xFFFFFFFF)

    # validation rejection classes
    def mutate(name: str, opcode: int, fn) -> None:
        base_record = _valid_descriptor(opcode, 0)
        words = _words_of(base_record)
        fn(words)
        record = Descriptor.from_bytes(struct.pack(f"<{len(words)}I", *words))
        expected = _expected_fault([record], 3)
        assert expected is not None, f"mutation {name} unexpectedly valid"
        code, word, index = expected
        assert index == 0
        emit(name, [record], 3, 1, code, index, 0xFFFFFFFF if word is None else word)

    mutate("bad_version", 8, lambda w: w.__setitem__(0, 0x0200_0000 | 8))
    mutate("bad_version_mid", 8, lambda w: w.__setitem__(0, 0x0100_0100 | 8))
    mutate("bad_reserved1", 8, lambda w: w.__setitem__(1, 1))
    mutate("bad_reserved26", 8, lambda w: w.__setitem__(26, 1))
    mutate("bad_reserved31", 8, lambda w: w.__setitem__(31, 0x8000_0000))
    mutate("bad_tile_upper", 8, lambda w: w.__setitem__(14, w[14] | 0x0001_0000))
    mutate("bad_in0zero_upper", 8, lambda w: w.__setitem__(20, w[20] | 0x100))
    mutate("bad_outzero_upper", 8, lambda w: w.__setitem__(22, w[22] | 0x0100_0000))
    mutate("bad_bounds_upper", 8, lambda w: w.__setitem__(23, w[23] | 0x0001_0000))
    mutate("bad_bounds_order", 8, lambda w: w.__setitem__(23, 0x0000_0305))
    mutate("bad_tile_h0", 8, lambda w: w.__setitem__(14, w[14] & 0xFFFF_FF00))
    mutate("bad_tile_product", 8, lambda w: w.__setitem__(14, 0x0000_0303))
    mutate("bad_kslice0", 8, lambda w: w.__setitem__(15, 0))
    mutate("bad_kslice1025", 8, lambda w: w.__setitem__(15, 1025))
    mutate("bad_opcode0", 8, lambda w: w.__setitem__(0, w[0] & 0xFFFF_FF00))
    mutate("bad_opcode9", 8, lambda w: w.__setitem__(0, (w[0] & 0xFFFF_FF00) | 9))
    mutate("unused_input1_base", 8, lambda w: w.__setitem__(3, 0x3001_4000))
    mutate("unused_input1_row", 8, lambda w: w.__setitem__(11, 4))
    mutate("unused_input1_bytes", 8, lambda w: w.__setitem__(17, 4))
    mutate("unused_input1_zero", 8, lambda w: w.__setitem__(21, 1))
    mutate("unused_weight_base", 8, lambda w: w.__setitem__(24, 0x3002_8000))
    mutate("unused_weight_bytes", 8, lambda w: w.__setitem__(25, 8))
    mutate("unused_param_base", 8, lambda w: w.__setitem__(5, 0x3003_0000))
    mutate("unused_param_bytes", 8, lambda w: w.__setitem__(19, 8))
    mutate("gap_kernel_word", 7, lambda w: w.__setitem__(12, 1))
    mutate("gap_padding", 7, lambda w: w.__setitem__(13, 1))
    mutate("dim_h0", 8, lambda w: w.__setitem__(6, w[6] & 0xFFFF_0000))
    mutate("dim_w0", 8, lambda w: w.__setitem__(6, w[6] & 0x0000_FFFF))
    mutate("dim_cin0", 8, lambda w: w.__setitem__(7, w[7] & 0xFFFF_0000))
    mutate("dim_cout0", 8, lambda w: w.__setitem__(7, w[7] & 0x0000_FFFF))
    mutate("dim_oh0", 8, lambda w: w.__setitem__(8, w[8] & 0xFFFF_0000))
    mutate("dim_ow0", 8, lambda w: w.__setitem__(8, w[8] & 0x0000_FFFF))
    mutate("dim_h4097", 8, lambda w: w.__setitem__(6, (w[6] & 0xFFFF_0000) | 4097))
    mutate("conv_kh0", 1, lambda w: w.__setitem__(12, w[12] & 0xFFFF_FF00))
    mutate("conv_pad_ge_kernel", 1, lambda w: w.__setitem__(13, (w[13] & 0xFFFF_FF00) | 3))
    mutate("conv_extent_negative", 1,
           lambda w: (w.__setitem__(6, (w[6] & 0xFFFF_0000) | 2), w.__setitem__(13, 0)))
    mutate("conv_extent_mismatch", 1, lambda w: w.__setitem__(8, w[8] + 1))
    mutate("conv_kh17", 1, lambda w: w.__setitem__(12, w[12] | 17))
    mutate("conv_stride3", 1, lambda w: w.__setitem__(12, (w[12] & 0xFF00_FFFF) | (3 << 16)))
    mutate("dw_kh5", 2, lambda w: w.__setitem__(12, w[12] | 5))
    mutate("dw_cout_ne", 2, lambda w: w.__setitem__(7, w[7] + (1 << 16)))
    mutate("fc_h2", 3, lambda w: w.__setitem__(6, w[6] | 2))
    mutate("fc_oh2", 3, lambda w: w.__setitem__(8, w[8] | 2))
    mutate("fc_kernel0", 3, lambda w: w.__setitem__(12, 0))
    mutate("fc_padding", 3, lambda w: w.__setitem__(13, 1))
    mutate("add_input1_zero_upper", 4, lambda w: w.__setitem__(21, w[21] | 0x100))
    mutate("add_input1_base0", 4, lambda w: w.__setitem__(3, 0))
    mutate("add_broadcast", 4, lambda w: w.__setitem__(8, w[8] + 1))
    mutate("add_cout_ne", 4, lambda w: w.__setitem__(7, w[7] + (1 << 16)))
    mutate("add_kernel", 4, lambda w: w.__setitem__(12, 0))
    mutate("add_padding", 4, lambda w: w.__setitem__(13, 1))
    mutate("pool_kh17", 5, lambda w: w.__setitem__(12, w[12] | 17))
    mutate("pool_cout_ne", 5, lambda w: w.__setitem__(7, w[7] + (1 << 16)))
    mutate("pool_zero_mismatch", 5, lambda w: w.__setitem__(22, w[22] ^ 1))
    mutate("gap_oh2", 7, lambda w: w.__setitem__(8, w[8] | 2))
    mutate("gap_cout_ne", 7, lambda w: w.__setitem__(7, w[7] + (1 << 16)))
    mutate("gap_zero_mismatch", 7, lambda w: w.__setitem__(22, w[22] ^ 1))
    mutate("clamp_oh_ne", 8, lambda w: w.__setitem__(8, w[8] + 1))
    mutate("clamp_zero_mismatch", 8, lambda w: w.__setitem__(22, w[22] ^ 1))
    mutate("clamp_kernel", 8, lambda w: w.__setitem__(12, 0))
    mutate("clamp_padding", 8, lambda w: w.__setitem__(13, 1))
    mutate("kslice_gt_full", 1, lambda w: w.__setitem__(15, 19))
    mutate("tile_gt_oh", 8, lambda w: w.__setitem__(14, (w[14] & 0xFFFF_FF00) | 4))
    mutate("weight_base0", 1, lambda w: w.__setitem__(24, 0))
    mutate("weight_bytes_bad", 1, lambda w: w.__setitem__(25, w[25] + 8))
    mutate("param_base0", 1, lambda w: w.__setitem__(5, 0))
    mutate("param_bytes_bad", 1, lambda w: w.__setitem__(19, w[19] + 16))
    mutate("add_param_bytes_bad", 4, lambda w: w.__setitem__(19, 16))
    clamp_min_in = 5 * 4  # W*Cin of the CLAMP factory
    clamp_min_out = 5 * 4  # OW*Cout of the CLAMP factory
    add_min_in = 3 * 3  # W*Cin of the ADD factory
    mutate("stride_in0_low", 8, lambda w: w.__setitem__(9, clamp_min_in - 1))
    mutate("stride_out_low", 8, lambda w: w.__setitem__(10, clamp_min_out - 1))
    mutate("add_stride1_low", 4, lambda w: w.__setitem__(11, add_min_in - 1))
    mutate("span_in0", 8, lambda w: w.__setitem__(16, w[16] - 1))
    mutate("span_out", 8, lambda w: w.__setitem__(18, w[18] - 1))
    mutate("wrap_in0_alloc", 8,
           lambda w: (w.__setitem__(2, 0xFFFF_F000), w.__setitem__(16, 0x2000)))
    mutate("wrap_out", 8,
           lambda w: (w.__setitem__(4, 0xFFFF_FFC0), w.__setitem__(18, 96)))
    mutate("wrap_weight", 1, lambda w: w.__setitem__(24, 0xFFFF_FF80))
    mutate("wrap_param", 1, lambda w: w.__setitem__(5, 0xFFFF_FFC0))
    mutate("align_param", 1, lambda w: w.__setitem__(5, w[5] | 4))
    mutate("align_weight", 1, lambda w: w.__setitem__(24, w[24] | 4))
    mutate("overlap_in0_out", 8, lambda w: w.__setitem__(4, w[2]))
    mutate("overlap_out_desc", 8, lambda w: w.__setitem__(4, MEM_BASE))
    mutate("overlap_weight_param", 1, lambda w: w.__setitem__(5, w[24]))
    # first-fault order: earlier validator stage wins
    mutate("priority_struct", 8,
           lambda w: (w.__setitem__(0, 0x0300_0000 | 8), w.__setitem__(1, 7)))
    mutate("priority_unused_over_geometry", 8,
           lambda w: (w.__setitem__(3, 0x3001_4000), w.__setitem__(6, 0)))

    # validation fault after a valid prefix record
    prefix = _valid_descriptor(8, 0)
    faulty = _valid_descriptor(1, 1)
    words = _words_of(faulty)
    words[15] = 19  # K_SLICE above full K
    faulty = Descriptor.from_bytes(struct.pack(f"<{len(words)}I", *words))
    expected = _expected_fault([prefix, faulty], 4)
    assert expected == (F_UNSUPPORTED, 15, 1)
    emit("fault_at_index1", [prefix, faulty], 4, 1, expected[0], 1, expected[1])

    # fetch bus faults
    emit("fetch_slverr", [_valid_descriptor(8, 0)], 1, 2, F_AXI_READ, 0, 0xFFFFFFFF,
         rderr_addr=MEM_BASE + 24, rderr_code=2)
    emit("fetch_decerr_index1", [_valid_descriptor(8, 0), _valid_descriptor(1, 1)], 2, 2,
         F_AXI_READ, 1, 0xFFFFFFFF, rderr_addr=MEM_BASE + 128, rderr_code=3)
    emit("fetch_bad_rid", [_valid_descriptor(8, 0)], 1, 2, F_AXI_PROTOCOL, 0, 0xFFFFFFFF,
         rderr_addr=MEM_BASE, rderr_badid=1)
    # truncation: the third record does not exist in memory
    emit("fetch_truncated", [_valid_descriptor(8, 0), _valid_descriptor(1, 1)], 3, 2,
         F_AXI_READ, 2, 0xFFFFFFFF, rderr_addr=MEM_BASE + 256, rderr_code=3)
    return cases


@pytest.mark.parametrize("simulator", ("iverilog", "verilator"))
def test_npu_dma(tmp_path: Path, simulator: str) -> None:
    tools = _tools()
    _run_p3_test(
        tools,
        simulator,
        tmp_path,
        f"npu_dma_{simulator}",
        "npu_dma_tb",
        ROOT / "tests/rtl/npu_dma_tb.sv",
        DMA_SOURCES,
        "NPU DMA test passed",
    )


@pytest.mark.parametrize("simulator", ("iverilog", "verilator"))
def test_npu_job_decoder(tmp_path: Path, simulator: str) -> None:
    tools = _tools()
    command = _build_sim(
        tools,
        simulator,
        tmp_path,
        f"npu_job_decoder_{simulator}",
        "npu_job_decoder_tb",
        ROOT / "tests/rtl/npu_job_decoder_tb.sv",
        DECODER_SOURCES,
    )
    cases = _decoder_cases(tmp_path)
    assert len(cases) >= 70
    for plusargs in cases:
        _run(command, plusargs, "NPU job decoder test passed")


# ---------------------------------------------------------------------------
# Core testbench scenarios
# ---------------------------------------------------------------------------


def _pat(address: int) -> int:
    """Deterministic input/weight/param content byte."""
    return (address ^ (address >> 7) ^ 0x36) & 0xFF


def _s8(value: int) -> int:
    return value - 256 if value >= 128 else value


def _fill_descriptor_content(mem: bytearray, desc: Descriptor) -> None:
    """Deterministic compute-valid content: any INT8 input, weights never
    -128, and parameter encodings inside numerical profile 1 with magnitudes
    that cannot trip the checked INT32 paths (the jobs must reach DONE)."""
    for offset in range(desc.input0_bytes):
        mem[desc.input0_base - MEM_BASE + offset] = _pat(desc.input0_base + offset)
    if desc.input1_base:
        for offset in range(desc.input1_bytes):
            mem[desc.input1_base - MEM_BASE + offset] = _pat(desc.input1_base + 3 + offset)
    if desc.weight_bytes:
        for offset in range(desc.weight_bytes):
            byte = _pat(desc.weight_base + 1 + offset)
            mem[desc.weight_base - MEM_BASE + offset] = 0x7F if byte == 0x80 else byte
    if desc.param_bytes:
        if desc.opcode == 4:  # ADD: one 32-byte record
            raw = [_pat(desc.param_base + 2 + offset) for offset in range(32)]
            words = [int.from_bytes(bytes(raw[index * 4:(index + 1) * 4]), "little")
                     for index in range(8)]
            m0 = words[1] & 0x3FFFFFFF
            s0 = max(-31, min(2, _s8(words[2] & 0xFF)))
            m1 = words[3] & 0x3FFFFFFF
            s1 = max(-31, min(2, _s8(words[4] & 0xFF)))
            mout = words[5] & 0x7FFFFFFF
            sout = max(-31, min(2, _s8(words[6] & 0xFF)))
            struct.pack_into("<IiiiiiiI", mem, desc.param_base - MEM_BASE,
                             20, m0, s0, m1, s1, mout, sout, 0)
        else:  # per-channel 16-byte records
            for record in range(desc.param_bytes // 16):
                base = desc.param_base - MEM_BASE + record * 16
                raw = [_pat(base + lane) for lane in range(12)]
                bias = int.from_bytes(bytes(raw[0:4]), "little", signed=True)
                bias = max(-(1 << 28), min((1 << 28) - 1, bias))
                mult = int.from_bytes(bytes(raw[4:8]), "little") & 0x7FFFFFFF
                shift = max(-31, min(2, _s8(raw[8])))
                struct.pack_into("<iiiI", mem, base, bias, mult, shift, 0)


def _input_tensor(desc: Descriptor, mem: bytearray, input1: bool = False):
    """(H,W,Cin) input tensor parsed from memory in raster order."""
    base = desc.input1_base if input1 else desc.input0_base
    row_bytes = desc.input1_row_bytes if input1 else desc.input0_row_bytes
    zero = desc.input1_zero if input1 else desc.input0_zero
    data = []
    for iy in range(desc.h):
        for ix in range(desc.w):
            for channel in range(desc.cin):
                data.append(_s8(mem[base - MEM_BASE + iy * row_bytes + ix * desc.cin + channel]))
    return npu_reference.Tensor((desc.h, desc.w, desc.cin), tuple(data), 1.0, zero)


def _channel_params(desc: Descriptor, mem: bytearray) -> tuple[list, list, list]:
    bias, mults, shifts = [], [], []
    for record in range(desc.param_bytes // 16):
        b_value, m_value, s_value, _ = struct.unpack(
            "<iiiI", mem[desc.param_base - MEM_BASE + record * 16:
                         desc.param_base - MEM_BASE + (record + 1) * 16])
        bias.append(b_value)
        mults.append(m_value)
        shifts.append(s_value)
    return bias, mults, shifts


def _ref_output(desc: Descriptor, mem: bytearray) -> list[int]:
    """Pinned numerical-reference output bytes of one descriptor."""
    inputs = _input_tensor(desc, mem)
    pads = (desc.pad_top, desc.pad_bottom, desc.pad_left, desc.pad_right)
    if desc.opcode == 1:  # CONV2D
        full_k = desc.kh * desc.kw * desc.cin
        weights = [[[[_s8(mem[desc.weight_base - MEM_BASE +
                              (c // 8) * full_k * 8 +
                              (dkh * desc.kw * desc.cin + dkw * desc.cin + ci) * 8 + (c % 8)])
                      for ci in range(desc.cin)] for dkw in range(desc.kw)]
                    for dkh in range(desc.kh)] for c in range(desc.cout)]
        bias, mults, shifts = _channel_params(desc, mem)
        ref = npu_reference.conv2d(
            inputs, weights, bias, mults, shifts, stride_h=desc.sh, stride_w=desc.sw,
            pad_top=pads[0], pad_bottom=pads[1], pad_left=pads[2], pad_right=pads[3],
            output_scale=1.0, output_zero_point=desc.output_zero,
            act_min=desc.act_min, act_max=desc.act_max)
    elif desc.opcode == 2:  # DEPTHWISE3X3
        weights = [[[_s8(mem[desc.weight_base - MEM_BASE +
                             (c // 8) * 72 + (dkh * 3 + dkw) * 8 + (c % 8)])
                     for c in range(desc.cin)] for dkw in range(3)]
                   for dkh in range(3)]
        bias, mults, shifts = _channel_params(desc, mem)
        ref = npu_reference.depthwise_conv2d(
            inputs, weights, bias, mults, shifts, stride_h=desc.sh, stride_w=desc.sw,
            pad_top=pads[0], pad_bottom=pads[1], pad_left=pads[2], pad_right=pads[3],
            output_scale=1.0, output_zero_point=desc.output_zero,
            act_min=desc.act_min, act_max=desc.act_max)
    elif desc.opcode == 3:  # FULLY_CONNECTED
        cin = desc.cin
        weights = [[_s8(mem[desc.weight_base - MEM_BASE +
                            (c // 8) * cin * 8 + ci * 8 + (c % 8)])
                    for ci in range(cin)] for c in range(desc.cout)]
        bias, mults, shifts = _channel_params(desc, mem)
        ref = npu_reference.fully_connected(
            inputs, weights, bias, mults, shifts, output_scale=1.0,
            output_zero_point=desc.output_zero, act_min=desc.act_min, act_max=desc.act_max)
    elif desc.opcode == 4:  # ADD
        record = struct.unpack(
            "<IiiiiiiI", mem[desc.param_base - MEM_BASE: desc.param_base - MEM_BASE + 32])
        _, m0, s0, m1, s1, mout, sout, _ = record
        ref = npu_reference.add(
            inputs, _input_tensor(desc, mem, input1=True),
            input0_multiplier=m0, input0_shift=s0, input1_multiplier=m1, input1_shift=s1,
            output_multiplier=mout, output_shift=sout, output_scale=1.0,
            output_zero_point=desc.output_zero, act_min=desc.act_min, act_max=desc.act_max)
    elif desc.opcode == 5:
        ref = npu_reference.max_pool(
            inputs, kernel_h=desc.kh, kernel_w=desc.kw, stride_h=desc.sh,
            stride_w=desc.sw, pad_top=pads[0], pad_bottom=pads[1], pad_left=pads[2],
            pad_right=pads[3], act_min=desc.act_min, act_max=desc.act_max)
    elif desc.opcode == 6:
        ref = npu_reference.average_pool(
            inputs, kernel_h=desc.kh, kernel_w=desc.kw, stride_h=desc.sh,
            stride_w=desc.sw, pad_top=pads[0], pad_bottom=pads[1], pad_left=pads[2],
            pad_right=pads[3], act_min=desc.act_min, act_max=desc.act_max)
    elif desc.opcode == 7:
        ref = npu_reference.global_average_pool(inputs, act_min=desc.act_min,
                                                act_max=desc.act_max)
    elif desc.opcode == 8:
        ref = npu_reference.clamp(inputs, desc.act_min, desc.act_max)
    else:
        raise AssertionError(f"no reference for opcode {desc.opcode}")
    return [value & 0xFF for value in ref.data]


def _golden_window(descs: list[Descriptor], mem: bytearray) -> tuple[int, bytes]:
    """Byte-exact output window content after a full run of the job: the
    pinned reference output bytes at (oy, ox, c), inter-row padding zeroed by
    the store engine, everything else the initial memory image."""
    lo = min(d.output_base for d in descs)
    hi = max(d.output_base + (d.oh - 1) * d.output_row_bytes + d.ow * d.cout for d in descs)
    window = bytearray(mem[lo - MEM_BASE : hi - MEM_BASE])
    for desc in descs:
        out_span = (desc.oh - 1) * desc.output_row_bytes + desc.ow * desc.cout
        span = bytearray(out_span)
        ref = _ref_output(desc, mem)
        for oy in range(desc.oh):
            for ox in range(desc.ow):
                for channel in range(desc.cout):
                    span[oy * desc.output_row_bytes + ox * desc.cout + channel] = ref[
                        (oy * desc.ow + ox) * desc.cout + channel]
        start = desc.output_base - lo
        window[start : start + out_span] = span
    return lo, bytes(window)


def _core_case(tmp_path: Path, name: str, descs: list[Descriptor], scen: int,
               timeout: int = 20_000_000, rderr_addr: int = 0xFFFFFFFF, rderr_code: int = 0,
               werr_addr: int = 0xFFFFFFFF, werr_code: int = 0, exp_faddr: int = 0,
               wchk: bool = False) -> list[str]:
    for desc in descs:
        validate_descriptor(desc, descriptor_region=(MEM_BASE, len(descs) * DESCRIPTOR_BYTES))
    mem = bytearray([GAP_FILL] * CORE_MEM_BYTES)
    for index, desc in enumerate(descs):
        words = _words_of(desc)
        struct.pack_into(f"<{len(words)}I", mem, MEM_BASE - MEM_BASE + index * 128, *words)
        _fill_descriptor_content(mem, desc)
    image = tmp_path / f"core_{name}.hex"
    _image_hex(image, list(struct.unpack(f"<{CORE_MEM_BYTES // 4}I", bytes(mem))))
    gold_base, gold = _golden_window(descs, mem)
    golden = tmp_path / f"core_{name}_gold.hex"
    pad = (-len(gold)) % 4
    _image_hex(golden, list(struct.unpack(f"<{(len(gold) + pad) // 4}I", bytes(gold) +
                                          bytes(pad))))
    first = descs[0]
    macs = 0
    for desc in descs:
        if desc.opcode == 1:
            macs += desc.oh * desc.ow * desc.cout * desc.kh * desc.kw * desc.cin
        elif desc.opcode == 2:
            macs += desc.oh * desc.ow * desc.cin * 9
        elif desc.opcode == 3:
            macs += desc.cout * desc.cin
    exp_pack = 1 if any(desc.opcode in (1, 2, 3) for desc in descs) else 0
    return [
        f"+IMG={image}",
        f"+GOLD={golden}",
        f"+BASE={MEM_BASE:x}",
        f"+COUNT={len(descs)}",
        "+JOBID=1a2b3c4d",
        f"+TIMEOUT={timeout}",
        f"+SCEN={scen}",
        f"+GOLD_BASE={gold_base:x}",
        f"+GOLD_BYTES={len(gold)}",
        f"+RDERR_ADDR={rderr_addr:x}",
        f"+RDERR_CODE={rderr_code}",
        f"+WERR_ADDR={werr_addr:x}",
        f"+WERR_CODE={werr_code}",
        f"+EXP_FADDR={exp_faddr:x}",
        f"+WCHK={1 if wchk else 0}",
        f"+WCHK_BASE={first.weight_base:x}",
        f"+WCHK_BYTES={first.weight_bytes}",
        f"+MACS={macs}",
        f"+EXP_PACK={exp_pack}",
        f"+NAME={name}",
    ]


def _conv_kws_shape(slot: int) -> Descriptor:
    """KWS conv1 shape: 10x4 kernel, stride 2, Cin=1, reduced geometry."""
    b = _slot_bases(slot)
    d = Descriptor()
    d.version_opcode = 0x0100_0000 | 1
    d.act_min = -128
    d.act_max = 127
    h, w, cin, cout = 13, 8, 1, 8
    kh, kw, sh, sw = 10, 4, 2, 2
    oh = (h - kh) // sh + 1
    ow = (w - kw) // sw + 1
    d.input_hw = (w << 16) | h
    d.channels = (cout << 16) | cin
    d.output_hw = (ow << 16) | oh
    d.input0_base = b["in0"]
    d.output_base = b["out"]
    d.input0_row_bytes = w * cin
    d.output_row_bytes = ow * cout
    d.kernel_stride = (sw << 24) | (sh << 16) | (kw << 8) | kh
    d.padding = 0
    d.tile_hw = (2 << 8) | 2
    d.k_slice = 40
    d.input0_bytes = (h - 1) * d.input0_row_bytes + w * cin
    d.output_bytes = (oh - 1) * d.output_row_bytes + ow * cout
    d.weight_base = b["w"]
    d.weight_bytes = ((cout + 7) // 8) * kh * kw * cin * 8
    d.param_base = b["p"]
    d.param_bytes = cout * 16
    validate_descriptor(d, descriptor_region=(MEM_BASE, 4 * DESCRIPTOR_BYTES))
    return d


def _clamp_strided(slot: int) -> Descriptor:
    d = _valid_descriptor(8, slot)
    d.input0_row_bytes = d.w * d.cin + 7
    d.output_row_bytes = d.ow * d.cout + 11
    d.input0_bytes = (d.h - 1) * d.input0_row_bytes + d.w * d.cin
    d.output_bytes = (d.oh - 1) * d.output_row_bytes + d.ow * d.cout
    validate_descriptor(d, descriptor_region=(MEM_BASE, 4 * DESCRIPTOR_BYTES))
    return d


def _core_cases(tmp_path: Path) -> list[list[str]]:
    cases: list[list[str]] = []
    # directed transport jobs, one invocation per shape
    cases.append(_core_case(tmp_path, "clamp_small", [_valid_descriptor(8, 0)], 0))
    cases.append(_core_case(tmp_path, "clamp_strided", [_clamp_strided(0)], 0))
    cases.append(_core_case(tmp_path, "conv_kws_shape", [_conv_kws_shape(0)], 0, wchk=True))
    cases.append(_core_case(tmp_path, "dw33", [_valid_descriptor(2, 0)], 0))
    cases.append(_core_case(tmp_path, "maxpool", [_valid_descriptor(5, 0)], 0))
    cases.append(_core_case(tmp_path, "avgpool", [_valid_descriptor(6, 0)], 0))
    cases.append(_core_case(tmp_path, "gap", [_valid_descriptor(7, 0)], 0))
    cases.append(_core_case(tmp_path, "fc", [_valid_descriptor(3, 0)], 0))
    cases.append(_core_case(tmp_path, "add", [_valid_descriptor(4, 0)], 0))
    cases.append(_core_case(
        tmp_path, "multi3",
        [_valid_descriptor(8, 0), _conv_kws_shape(1), _clamp_strided(2)], 0))
    # lifecycle scenarios use a two-descriptor job
    pair = [_valid_descriptor(8, 0), _clamp_strided(1)]
    cases.append(_core_case(tmp_path, "b_order", pair, 1))
    cases.append(_core_case(tmp_path, "watchdog", [_valid_descriptor(8, 0)], 2,
                            timeout=2000))
    cases.append(_core_case(tmp_path, "abort", pair, 3))
    cases.append(_core_case(tmp_path, "quiesce", pair, 4))
    cases.append(_core_case(tmp_path, "reset", pair, 5))
    cases.append(_core_case(tmp_path, "flush", pair, 6))
    cases.append(_core_case(
        tmp_path, "snapshot_race",
        [_valid_descriptor(8, 0), _conv_kws_shape(1), _clamp_strided(2)], 7))
    # write fault: error on the first store burst of descriptor 0
    fault_job = _valid_descriptor(8, 0)
    burst_base = fault_job.output_base & ~7
    span_beats = ((fault_job.output_base & 7) + fault_job.cout + 7) >> 3
    beats_4k = (4096 - (burst_base & 0xFFF)) >> 3
    beats = min(16, span_beats, beats_4k)
    cases.append(_core_case(tmp_path, "write_fault", [fault_job], 8,
                            werr_addr=burst_base, werr_code=2,
                            exp_faddr=burst_base + (beats - 1) * 8))
    # fetch fault: SLVERR on descriptor 0's first beat
    cases.append(_core_case(tmp_path, "read_fault", [_valid_descriptor(8, 0)], 9,
                            rderr_addr=MEM_BASE, rderr_code=2, exp_faddr=MEM_BASE))
    # administrative pause mid-job with a short job watchdog timeout: the
    # pause must be excluded from the watchdog and the job must resume whole
    cases.append(_core_case(tmp_path, "pause", [_conv_kws_shape(0)], 10, timeout=2000))
    return cases


@pytest.mark.parametrize("simulator", ("iverilog", "verilator"))
def test_npu_core(tmp_path: Path, simulator: str) -> None:
    tools = _tools()
    command = _build_sim(
        tools,
        simulator,
        tmp_path,
        f"npu_core_{simulator}",
        "npu_core_tb",
        ROOT / "tests/rtl/npu_core_tb.sv",
        CORE_SOURCES,
    )
    for plusargs in _core_cases(tmp_path):
        _run(command, plusargs, "NPU core test passed")


# ---------------------------------------------------------------------------
# Shell-level job admission testbench scenario
# ---------------------------------------------------------------------------

JOB_SOURCES = [
    COMMON / "interface/apb4_if.sv",
    COMMON / "utils/register.sv",
    COMMON / "utils/xchecker.sv",
    COMMON / "clkrst/rst_sync.sv",
    COMMON / "cdc/cdc_sync.sv",
    COMMON / "cdc/cdc_rst_ctrlr.sv",
    COMMON / "cdc/async_reqack.sv",
    MULTIMEDIA / "npu_pkg.sv",
    TECH / "tc_sram.sv",
    MULTIMEDIA / "npu_local_sram.sv",
    MULTIMEDIA / "npu_patch_packer.sv",
    MULTIMEDIA / "npu_dma.sv",
    MULTIMEDIA / "npu_job_decoder.sv",
    MULTIMEDIA / "npu_mac_array.sv",
    MULTIMEDIA / "npu_accumulator.sv",
    MULTIMEDIA / "npu_vector.sv",
    MULTIMEDIA / "npu_requantizer.sv",
    MULTIMEDIA / "npu_scheduler.sv",
    MULTIMEDIA / "npu_reg.sv",
    MULTIMEDIA / "npu_control_cdc.sv",
    MULTIMEDIA / "npu_core.sv",
    MULTIMEDIA / "apb4_npu.sv",
]


def _job_case(tmp_path: Path) -> list[str]:
    """Single-run admission case: one valid CLAMP job at index 0 plus a
    version-mismatched record at index 1, with the golden output window of
    the valid job; the testbench drives every admission scenario from it."""
    good = _valid_descriptor(8, 0)
    bad_words = _words_of(_valid_descriptor(8, 1))
    bad_words[0] = 0x0200_0000 | 8  # VERSION 2.0: rejected at ABI word 0
    bad = Descriptor.from_bytes(struct.pack(f"<{len(bad_words)}I", *bad_words))
    expected = _expected_fault([bad], 1)
    assert expected == (F_DESCRIPTOR, 0, 0)
    mem = bytearray([GAP_FILL] * CORE_MEM_BYTES)
    struct.pack_into(f"<{DESCRIPTOR_BYTES // 4}I", mem, 0, *_words_of(good))
    struct.pack_into(f"<{DESCRIPTOR_BYTES // 4}I", mem, DESCRIPTOR_BYTES, *bad_words)
    _fill_descriptor_content(mem, good)
    image = tmp_path / "job_img.hex"
    _image_hex(image, list(struct.unpack(f"<{CORE_MEM_BYTES // 4}I", bytes(mem))))
    gold_base, gold = _golden_window([good], mem)
    golden = tmp_path / "job_gold.hex"
    pad = (-len(gold)) % 4
    _image_hex(golden, list(struct.unpack(f"<{(len(gold) + pad) // 4}I", bytes(gold) +
                                          bytes(pad))))
    bad_base = MEM_BASE + DESCRIPTOR_BYTES
    return [
        f"+IMG={image}",
        f"+GOLD={golden}",
        f"+GOLD_BASE={gold_base:x}",
        f"+GOLD_BYTES={len(gold)}",
        f"+BASE={MEM_BASE:x}",
        f"+BAD_BASE={bad_base:x}",
        f"+BAD_FADDR={bad_base:x}",
        "+TIMEOUT=20000000",
        "+WDOG=2000",
        "+JOBID=51a50001",
    ]


@pytest.mark.parametrize("simulator", ("iverilog", "verilator"))
def test_npu_job(tmp_path: Path, simulator: str) -> None:
    tools = _tools()
    command = _build_sim(
        tools,
        simulator,
        tmp_path,
        f"npu_job_{simulator}",
        "npu_job_tb",
        ROOT / "tests/rtl/npu_job_tb.sv",
        JOB_SOURCES,
    )
    _run(command, _job_case(tmp_path), "NPU job test passed")
