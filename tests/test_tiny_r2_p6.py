"""P6 product integration and fail-closed SDK/macro contracts."""
from __future__ import annotations

import json
import hashlib
import io
from pathlib import Path
import re
import shutil
import subprocess
import tarfile

import pytest

from scripts.generate_tiny import generate_bindings, read_topology
from scripts.rtl.generate_memory_map import generate as generate_memory_map
from scripts.check_clock_reset_domains import validate as validate_clocks
from test_tiny_r2_p4 import run
from test_sdio import SDIO_FULL_SOURCES, SDIO_FULL_INCDIRS
from scripts.check_simulation import DEFAULT_FAILURE
from scripts import tiny_r2_p6 as evidence

ROOT = Path(__file__).resolve().parents[1]
TINY = ROOT / "rtl/tiny"


def test_native_card_model_elaborates_without_sv2v(tmp_path):
    run(["iverilog", "-g2012", "-s", "sdio_native_card_model", "-o", str(tmp_path / "sim"),
         str(ROOT / evidence.MODEL)], tmp_path, "compile")


@pytest.mark.parametrize("mutation", ["none", "expression", "body", "still_forward"])
def test_only_continuous_declaration_relocation_is_equivalent(mutation):
    after = (ROOT / evidence.MODEL).read_text()
    declaration = re.search(r"^  wire \[3:0\] s_token_lanes = [^;]+;\n", after, re.M).group()
    before = after.replace(declaration, "").replace("  integer s_data_bytes;\n",
                                                    declaration + "  integer s_data_bytes;\n")
    if mutation == "expression":
        after = after.replace("s_data_bytes >= 4", "s_data_bytes >= 3")
    elif mutation == "body":
        after = after.replace("s_data_bytes        = (bytes_i < 1) ? 1 : bytes_i;",
                              "s_data_bytes        = 1;")
        assert after != (ROOT / evidence.MODEL).read_text()
    elif mutation == "still_forward":
        after = before
    if mutation == "none":
        evidence.check_model_declaration_move(before, after)
    else:
        with pytest.raises(ValueError):
            evidence.check_model_declaration_move(before, after)


@pytest.mark.parametrize("mutation", ["none", "dut", "model", "tool"])
def test_verification_update_cannot_relabel_dut_changes(tmp_path, mutation):
    after = (ROOT / evidence.MODEL).read_text()
    declaration = re.search(r"^  wire \[3:0\] s_token_lanes = [^;]+;\n", after, re.M).group()
    before = after.replace(declaration, "").replace("  integer s_data_bytes;\n",
                                                    declaration + "  integer s_data_bytes;\n")
    if mutation == "model":
        after = after.replace("s_data_bytes >= 4", "s_data_bytes >= 3")
    dut = "rtl/tiny/top/retrosoc_tiny.sv"
    documents = [{evidence.MODEL: before, dut: "unchanged DUT"},
                 {evidence.MODEL: after, dut: "changed DUT" if mutation == "dut" else "unchanged DUT"}]
    snapshots = []
    maps = []
    for index, documents_by_name in enumerate(documents):
        folder = tmp_path / str(index)
        folder.mkdir()
        hashes = {name: hashlib.sha256(text.encode()).hexdigest() for name, text in documents_by_name.items()}
        maps.append(hashes)
        evidence.b.dump(folder / "inputs.json", hashes)
        (folder / "patch").write_text("unit-test snapshot")
        with tarfile.open(folder / "source.tar", "w") as archive:
            for name, text in documents_by_name.items():
                info = tarfile.TarInfo(name)
                info.size = len(text.encode())
                archive.addfile(info, io.BytesIO(text.encode()))
        snapshots.append({key: evidence.b.artifact(folder / name) for key, name in
                          (("inputs", "inputs.json"), ("patch", "patch"), ("snapshot", "source.tar"))})
    saved = {"source": snapshots[0], "tools": {"unit-test": 1}, "captured_at": "2026-10-12T00:00:00+00:00"}
    evidence.b.dump(tmp_path / "source.json", saved)
    changed = sorted(name for name in maps[0] if maps[0][name] != maps[1][name])
    update = {"phase": evidence.PHASE, "kind": "native_model_declaration_order",
              "original_source": evidence.b.artifact(tmp_path / "source.json"), "source": snapshots[1],
              "tools": {"unit-test": 2 if mutation == "tool" else 1}, "changed_inputs": changed,
              "captured_at": "2026-10-12T00:01:00+00:00"}
    if mutation == "none":
        assert evidence.check_update(tmp_path, saved, update, maps[1]) == maps[0]
    else:
        with pytest.raises(ValueError):
            evidence.check_update(tmp_path, saved, update, maps[1])


@pytest.mark.parametrize("scope", ["consumer", "collection"])
@pytest.mark.parametrize("mutation", ["none", "dut", "firmware", "smoke", "model", "clock_contract", "other_consumer", "tool"])
def test_consumer_snapshot_cannot_change_running_flow_inputs(tmp_path, mutation, scope):
    consumer = "publications/programming_reference.py" if scope == "consumer" else "scripts/tiny_r2_p6.py"
    forbidden = {
        "dut": "rtl/tiny/top/retrosoc_tiny.sv", "firmware": "app/apps/ci_smoke/tiny.c",
        "smoke": "physical/smoke/sta/opensta/generate_sdc.py", "model": evidence.MODEL,
        "clock_contract": "rtl/tiny/integration/clock_reset_domains.json",
        "other_consumer": "scripts/regress.py" if scope == "consumer" else "publications/programming_reference.py",
    }
    old = {consumer: "old", **{name: "same" for name in forbidden.values()}}
    new = dict(old, **{consumer: "new"})
    if mutation in forbidden:
        new[forbidden[mutation]] = "changed"
    snapshots = []
    for index, values in enumerate((old, new)):
        folder = tmp_path / str(index)
        folder.mkdir()
        evidence.b.dump(folder / "inputs", values)
        for name in ("snapshot", "patch"):
            (folder / name).write_text("unit-test consumer artifact")
        snapshots.append({name: evidence.b.artifact(folder / name) for name in ("inputs", "snapshot", "patch")})
    previous = {"source": snapshots[0], "tools": {"unit-test": 1}, "captured_at": "2026-10-12T00:00:00+00:00"}
    prior = "verification-update.json" if scope == "consumer" else "consumer-update.json"
    kind = "publication_and_commercial_consumers" if scope == "consumer" else "terminal_log_collection"
    check = evidence.check_consumer_update if scope == "consumer" else evidence.check_collection_update
    evidence.b.dump(tmp_path / prior, previous)
    update = {"phase": evidence.PHASE, "kind": kind,
              "previous_update": evidence.b.artifact(tmp_path / prior),
              "source": snapshots[1], "tools": {"unit-test": 2 if mutation == "tool" else 1},
              "changed_inputs": sorted(name for name in old if old[name] != new[name]),
              "captured_at": "2026-10-12T00:01:00+00:00"}
    if mutation == "none":
        check(tmp_path, previous, update, new)
    else:
        with pytest.raises(ValueError):
            check(tmp_path, previous, update, new)


@pytest.mark.parametrize("simulator,top", [("verilator", "sdio_standalone_tb"),
                                          ("verilator", "tiny_p6_sdio_pads_tb"),
                                          ("iverilog", "tiny_p6_sdio_pads_tb")])
def test_shared_sdio_native_data(tmp_path, simulator, top):
    sources = [ROOT / name for name in (*SDIO_FULL_SOURCES, "tests/rtl/sdio_standalone_tb.sv")]
    output = tmp_path / "sim"
    includes = ["-I" + str(ROOT / p) for p in SDIO_FULL_INCDIRS]
    if simulator == "iverilog":
        converted = subprocess.run(["sv2v", *includes, *map(str, sources)], capture_output=True,
                                   text=True, timeout=180)
        assert converted.returncode == 0, converted.stderr
        (tmp_path / "converted.v").write_text(converted.stdout)
        run([simulator, "-g2012", "-s", top, "-o", str(output), str(tmp_path / "converted.v")],
            tmp_path, "compile")
        launch = ["vvp", str(output)]
    else:
        run([simulator, "--binary", "--timing", "--assert", "-Wno-fatal", "-j", "3",
             "--top-module", top, *includes, *map(str, sources),
             "--Mdir", str(tmp_path / "obj"), "-o", str(output)], tmp_path, "compile", timeout=180)
        launch = [str(output)]
    assert "SDIO standalone native SD model test passed" in run(launch, tmp_path, "sim")


@pytest.mark.parametrize("simulator", ["iverilog", "verilator"])
def test_shared_sdio_running_clock_commands(tmp_path, simulator):
    sources = [ROOT / "rtl/ip/storage" / name for name in
               ("sdio_pkg.sv", "sdio_clock.sv", "sdio_command.sv")]
    sources += [ROOT / "tests/rtl/sdio_command_tb.sv"]
    output = tmp_path / "sim"
    if simulator == "iverilog":
        converted = subprocess.run(["sv2v", *map(str, sources)], capture_output=True,
                                   text=True, timeout=60)
        assert converted.returncode == 0, converted.stderr
        (tmp_path / "converted.v").write_text(converted.stdout)
        run([simulator, "-g2012", "-s", "sdio_command_tb", "-o", str(output),
             str(tmp_path / "converted.v")], tmp_path, "compile")
        launch = ["vvp", str(output)]
    else:
        run([simulator, "--binary", "--timing", "-Wno-fatal", "--top-module", "sdio_command_tb",
             *map(str, sources), "--Mdir", str(tmp_path / "obj"), "-o", str(output)],
            tmp_path, "compile", timeout=120)
        launch = [str(output)]
    assert "SDIO command engine test passed" in run(launch, tmp_path, "sim")


@pytest.mark.parametrize("simulator", ["iverilog", "verilator"])
def test_apb_read_strobes_after_writes(tmp_path, simulator):
    common = ROOT / "rtl/managed/clusterip/common/rtl"
    generate_memory_map(TINY / "address_map/memory_map.json", tmp_path / "map", "YES", 128)
    sources = [common / "utils/register.sv", common / "interface/axi4_if.sv",
               common / "interface/apb4_if.sv", TINY / "top/tiny_axi42apb4.sv",
               ROOT / "tests/rtl/tiny_r2_p6_bridge_tb.sv"]
    flags = ["-DSV_ASSRT_DISABLE", "-I" + str(common), "-I" + str(common / "interface"),
             "-I" + str(tmp_path / "map/rtl")]
    top = "tiny_r2_p6_bridge_tb"
    output = tmp_path / "sim"
    if simulator == "iverilog":
        converted = subprocess.run(["sv2v", *flags, *map(str, sources)], capture_output=True,
                                   text=True, timeout=60)
        assert converted.returncode == 0, converted.stderr
        (tmp_path / "converted.v").write_text(converted.stdout)
        run([simulator, "-g2012", "-s", top, "-o", str(output), str(tmp_path / "converted.v")],
            tmp_path, "compile")
        launch = ["vvp", str(output)]
    else:
        run([simulator, "--binary", "--timing", "--assert", "-Wno-fatal", "--top-module", top,
             *flags, *map(str, sources), "--Mdir", str(tmp_path / "obj"), "-o", str(output)],
            tmp_path, "compile", timeout=120)
        launch = [str(output)]
    assert "SIM_TEST_PASS Tiny P6 APB read strobes" in run(launch, tmp_path, "sim")


def p6_log():
    rows = ["R2_P6_" + name + " " + " ".join(f"{k}={v}" for k, v in fields.items())
            for name, fields in evidence.RECORDS.items()]
    rows += [f"R2_P6_AUDIO bits={bits} frames=256 ws_frames=2 background_jobs=8 "
             f"tcd={int(bits == 24)} elapsed_us=7000 cycles=168000 instructions=40000"
             for bits in (16, 24)]
    rows += [f"R2_P6_I2S_WIRE bits={bits} samples=512" for bits in (16, 24)]
    rows += [f"R2_P6_AXI owner={owner} read_bytes=1024 write_bytes=1024 "
             f"descriptor_bytes={256 if owner == 1 else 0} ar_stall_max=3 aw_stall_max=3 "
             "w_stall_max=3 r_stall_max=3 b_stall_max=3" for owner in range(3)]
    rows += ["R2_P6_CONTENTION sdio_dma_cycles=100 cpu_fetches=10"]
    return "\n".join([*rows, "R2_P6_DEVICES ws_frames=4 ws_wait_max=100 fifo_max=16 "
                      "underflows=1 aborts=1 clock_stops=2", "SIM_TEST_PASS Tiny cycles=200000"])


def test_terminal_verdict_survives_partial_uart_line():
    flow = {"status": "passed", "exit_code": 0}
    content = p6_log().replace("SIM_TEST_PASS Tiny cycles=", "Tiny acceptance passed coSIM_TEST_PASS Tiny cycles=")
    assert evidence.parse_log(content, flow)["uart"]["echo_bytes"] == 4
    for replacement in ("SIM_TEST_PASS Tiny JTAG transport halt/resume", "Hello retroSoC!",
                        "SIM_TEST_PASS Mini cycles=200000", "SIM_TEST_PASS Tiny cycles=unknown"):
        with pytest.raises(ValueError):
            evidence.parse_log(content.replace("SIM_TEST_PASS Tiny cycles=200000", replacement), flow)


@pytest.mark.parametrize("mutation", ["none", "failed_command", "missing", "duplicate", "budget",
                                      "overflow", "false_qualification", "error", "no_terminal"])
def test_p6_evidence_is_fail_closed(mutation):
    log = p6_log()
    flow = {"status": "passed", "exit_code": 0}
    if mutation == "failed_command":
        flow["exit_code"] = 1
    elif mutation == "missing":
        log = "\n".join(line for line in log.splitlines() if not line.startswith("R2_P6_RNG"))
    elif mutation == "duplicate":
        log += "\n" + log.splitlines()[0]
    elif mutation == "budget":
        log = log.replace("ws_wait_max=100", "ws_wait_max=4801")
    elif mutation == "overflow":
        log = log.replace("fifo_max=16", "fifo_max=17")
    elif mutation == "false_qualification":
        log = log.replace("unqualified=1", "unqualified=0")
    elif mutation == "error":
        log += "\nSIM_TEST_FAIL"
    elif mutation == "no_terminal":
        log = log.replace("SIM_TEST_PASS", "Hello retroSoC!")
    if mutation == "none":
        assert len(evidence.parse_log(log, flow)["audio"]) == 2
    else:
        with pytest.raises(ValueError):
            evidence.parse_log(log, flow)


@pytest.mark.parametrize("mutation", ["none", "failed", "old", "unfinished", "reversed"])
def test_p6_gate_chronology(tmp_path, mutation):
    flow = {"status": "passed", "exit_code": 0,
            "started_at": "2026-10-12T01:00:00+00:00", "finished_at": "2026-10-12T01:01:00+00:00"}
    if mutation == "failed":
        flow["exit_code"] = 1
    elif mutation == "old":
        flow["started_at"] = "2026-10-11T01:00:00+00:00"
    elif mutation == "unfinished":
        del flow["finished_at"]
    elif mutation == "reversed":
        flow["finished_at"] = "2026-10-12T00:30:00+00:00"
    path = tmp_path / "gate.json"
    path.write_text(json.dumps(flow))
    if mutation == "none":
        assert evidence.checked_flow(path, "2026-10-12T00:59:00+00:00") == flow
    else:
        with pytest.raises(ValueError):
            evidence.checked_flow(path, "2026-10-12T00:59:00+00:00")


@pytest.mark.parametrize("mutation", ["none", "source", "tool", "old_model", "missing_image"])
def test_p6_complete_collection_requires_current_inputs(tmp_path, monkeypatch, mutation):
    """Exercise real artifact retention with synthetic, explicitly unit-test flows."""
    directory = tmp_path / "evidence"
    directory.mkdir()
    source = tmp_path / "source.sv"
    source.write_text("unit-test source\n")
    source_inputs = {"source.sv": evidence.b.sha256(source)}
    evidence.b.dump(directory / "inputs.json", source_inputs)
    for name in ("patch", "snapshot"):
        (directory / name).write_text("unit-test artifact\n")
    saved_source = {name: evidence.b.artifact(directory / filename) for name, filename in
                    (("inputs", "inputs.json"), ("patch", "patch"), ("snapshot", "snapshot"))}
    variants = [tmp_path / pdk for pdk in ("ICS55", "IHP130")]
    captured = "2026-10-12T00:00:00+00:00"
    evidence.b.dump(directory / "source.json", {"phase": evidence.PHASE, "source": saved_source,
        "tools": {"unit-test": 1}, "captured_at": captured, "variants": list(map(str, variants))})
    monkeypatch.setattr(evidence, "ROOT", tmp_path)
    monkeypatch.setattr(evidence, "inputs", lambda _: {"source.sv": evidence.b.sha256(source)})
    monkeypatch.setattr(evidence, "current_tools", lambda: {"unit-test": 2 if mutation == "tool" else 1})
    monkeypatch.setattr(evidence.b, "configuration", lambda p: {
        "configuration": {"PDK": p.name, "APP": "ci_smoke"}})
    monkeypatch.setattr(evidence.b, "runtime_inputs", lambda *_: {"unit-test": "explicit fixture"})
    for variant in variants:
        for relative in ("sw/firmware", "sw/retrosoc_fw.hex", "sw/retrosoc_fw.map", "sw/retrosoc_fw.bin",
                         "sw/ld2_all_sram.lds", "sw/memory_regions.ld", "meta/manifest.json"):
            path = variant / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("unit-test artifact\n")
        for simulator in ("iverilog", "verilator"):
            folder = variant / "sim" / simulator
            folder.mkdir(parents=True)
            for name in ("compile.log", "simv" if simulator == "iverilog" else "emu"):
                (folder / name).write_text("unit-test artifact\n")
            (folder / "sim.log").write_text(p6_log())
            evidence.b.dump(folder / "result-sim-check.json", {"status": "passed"})
            for label, start, end in (("compile", "01", "02"), ("sim", "03", "04")):
                evidence.b.dump(folder / f"result-{label}.json", {"status": "passed", "exit_code": 0,
                    "started_at": f"2026-10-12T00:{start}:00+00:00",
                    "finished_at": f"2026-10-12T00:{end}:00+00:00"})
    if mutation == "source":
        source.write_text("changed unit-test source\n")
    elif mutation == "old_model":
        path = variants[0] / "sim/iverilog/result-compile.json"
        flow = evidence.b.read_json(path)
        flow["started_at"] = "2026-10-11T00:00:00+00:00"
        evidence.b.dump(path, flow)
    elif mutation == "missing_image":
        (variants[0] / "sw/retrosoc_fw.hex").unlink()
    if mutation == "none":
        evidence.report(directory, [], variants)
        report = evidence.b.read_json(directory / "report.json")
        assert report["status"] == "functional_evidence_collected"
        assert len(report["simulations"]) == 4
        for simulation in report["simulations"].values():
            for artifact in simulation["artifacts"]:
                evidence.b.check_artifact(artifact)
    else:
        with pytest.raises((ValueError, FileNotFoundError)):
            evidence.report(directory, [], variants)
        assert not (directory / "report.json").exists()


@pytest.mark.parametrize("name", ["rng", "crc"])
def test_locked_controller_contracts(tmp_path, name):
    for tool in ("iverilog", "vvp", "verilator", "cc"):
        assert shutil.which(tool), f"required tool unavailable: {tool}"
    source = ROOT / "rtl/managed/clusterip" / name
    result = subprocess.run(["make", "-C", str(source), f"BUILD_DIR={tmp_path}",
                             "register-check", "test"], text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=180)
    (tmp_path / "build.log").write_text(result.stdout)
    assert result.returncode == 0, result.stdout[-12000:]
    for simulator, marker in (("iverilog", f"{name.upper()}_TEST_PASS"),
                               ("verilator", f"APB4_{name.upper()}_TEST_PASS")):
        log = (tmp_path / simulator / "test.log").read_text()
        assert marker in log and not DEFAULT_FAILURE.search(log), log


@pytest.mark.parametrize("simulator", ["iverilog", "verilator"])
def test_shared_i2s_payload(tmp_path, simulator):
    common = ROOT / "rtl/managed/clusterip/common/rtl"
    serial = ROOT / "rtl/ip/serial"
    for tool in (simulator, "sv2v", "vvp"):
        assert shutil.which(tool), f"required tool unavailable: {tool}"
    sources = [common / name for name in (
        "interface/apb4_if.sv", "interface/axi4_stream_if.sv", "utils/register.sv",
        "utils/bin2gray.sv", "utils/gray2bin.sv", "utils/spill_register.sv",
        "cdc/cdc_sync.sv", "cdc/cdc_rst_ctrlr.sv", "cdc/async_reqack.sv", "cdc/cdc_fifo.sv",
        "cdc/cdc_2phase.sv", "cdc/cdc_warm_flush.sv", "utils/edge_det.sv", "clkrst/rst_sync.sv")]
    sources += [ROOT / "rtl/tech/tc_clk.sv"]
    sources += [serial / name for name in ("i2s_pkg.sv", "i2s_reg.sv", "i2s_clkgen.sv",
                                         "i2s_recv.sv", "i2s_send.sv", "i2s_core.sv", "apb4_i2s.sv")]
    sources += [ROOT / "tests/rtl/tiny_r2_p6_shared_tb.sv"]
    flags = ["-DPDK_BEHAV", "-DSV_ASSRT_DISABLE", *[f"-I{p}" for p in (
        common, common / "interface", common / "utils", common / "cdc", common / "clkrst", serial)]]
    top = "tiny_r2_p6_shared_tb"
    output = tmp_path / "sim"
    if simulator == "iverilog":
        converted = subprocess.run(["sv2v", *flags, *map(str, sources)], capture_output=True,
                                   text=True, timeout=180)
        assert converted.returncode == 0, converted.stderr
        (tmp_path / "converted.v").write_text(converted.stdout)
        run([simulator, "-g2012", "-s", top, "-o", str(output), str(tmp_path / "converted.v")],
            tmp_path, "compile", timeout=180)
        launch = ["vvp", str(output)]
    else:
        run([simulator, "--binary", "--timing", "--assert", "-Wno-fatal", "-j", "3",
             "--top-module", top, *flags, *map(str, sources), "--Mdir", str(tmp_path / "obj"),
             "-o", str(output)], tmp_path, "compile", timeout=180)
        launch = [str(output)]
    content = run(launch, tmp_path, "sim", timeout=180)
    assert "SIM_TEST_PASS Tiny P6 I2S payload" in content
    for bits in (16, 24):
        assert f"P6_I2S bits={bits} samples=512" in content


def test_p6_map_irq_request_and_pin_contract():
    topology = read_topology(TINY / "integration/soc_topology.json", TINY / "address_map/memory_map.json")
    regions = {r["symbol"]: int(r["base"], 0) for r in json.loads(
        (TINY / "address_map/memory_map.json").read_text())["regions"]}
    for name, base in {"RNG": 0x20001000, "CRC": 0x20006000, "WS2812": 0x10008000,
                       "CRYPTO": 0x1000C000, "I2S": 0x10007000, "SDIO0": 0x1000F000}.items():
        assert regions["APB4_" + name] == base
    assert not {"APB4_UART1", "APB4_I2C1", "APB4_DVP", "APB4_SPI0", "APB4_PIOLITE"} & regions.keys()
    irqs = {i["name"]: i["core_bit"] for i in topology["interrupts"]}
    assert {k: irqs[k] for k in ("rng", "ws2812", "crypto", "i2s", "sdio")} == {
        "rng": 16, "ws2812": 17, "crypto": 23, "i2s": 8, "sdio": 10}
    assert {15, 19, 24, 25, 26, 27}.isdisjoint(irqs.values())
    assert irqs["rcu"] == 31
    pins = topology["gpio_alt_functions"]
    assert pins[9]["alt0"]["inputs"] == ["u_uart0_if.rx_i"]
    assert pins[10]["alt0"]["inputs"] == ["u_i2c0_if.scl_i"]
    assert pins[11]["alt0"]["inputs"] == ["u_i2c0_if.sda_i"]
    assert pins[26]["alt0"]["do"] == "u_ws2812_if.dat_o"
    for pin in (24, 25):
        assert pins[pin]["alt0"]["inputs"] == [f"u_pwm_if.capture_i[{pin - 24}]"]
        assert pins[pin]["alt1"]["inputs"] == []
    for pin in range(12, 23):
        assert pins[pin]["alt1"]["oe"] == "1'b0"
    assert pins[23]["alt1"]["do"] == pins[28]["alt0"]["do"] == "s_clkout"
    assert pins[23]["alt1"]["oe"] == pins[28]["alt0"]["oe"] == "s_clkout_enable"
    validate_clocks(TINY / "integration/clock_reset_domains.json", ROOT)


def test_duplicate_input_routes_are_rejected(tmp_path):
    topology = json.loads((TINY / "integration/soc_topology.json").read_text())
    topology["gpio_alt_functions"][25]["alt1"]["inputs"] = ["u_uart0_if.rx_i"]
    path = tmp_path / "topology.json"
    path.write_text(json.dumps(topology))
    with pytest.raises(ValueError, match="exclusive route"):
        read_topology(path, TINY / "address_map/memory_map.json")


@pytest.mark.parametrize("enabled", ["YES", "NO"])
def test_tiny_sva_build_selection_reaches_owned_assertions(enabled):
    result = subprocess.run(["make", "-n", "CONFIG=configs/ci/ics55-tiny.mk", "SOC=TINY",
                             "PDK=ICS55", "SIMU=VERILATOR", f"HAVE_SVA={enabled}",
                             "BUILD_TIMESTAMP=2099-01-01-00-00", "comp"], cwd=ROOT,
                            capture_output=True, text=True, check=True)
    assert ("+define+HAVE_SVA" in result.stdout) == (enabled == "YES")
    assert ("+define+SV_ASSRT_DISABLE" in result.stdout) == (enabled == "NO")


@pytest.mark.parametrize("simulator", ["iverilog", "verilator"])
def test_board_pullups_survive_partial_external_drivers(tmp_path, simulator):
    assert shutil.which(simulator), f"required simulator unavailable: {simulator}"
    generate_bindings(read_topology(TINY / "integration/soc_topology.json",
                                   TINY / "address_map/memory_map.json"), tmp_path)
    source = tmp_path / "board.sv"
    drivers = "\n".join(f"assign s_gpio_{n}=oe[{n}] ? data[{n}] : 1'bz;" for n in range(32))
    source.write_text('module board;\n`include "tiny_tb_gpio.svh"\n' +
        "logic clk=0; logic [31:0] oe=0, data=0; always #5 clk=!clk;\n" + drivers +
        "\nassign s_gpio_17=clk; assign s_gpio_15=s_gpio_14;\n" + r'''
initial begin
  #21;
  if (s_gpio[11:10] !== 2'b11) $fatal(1, "lost board pullups");
  oe[10]=1;
  #10;
  if (s_gpio[11:10] !== 2'b10) $fatal(1, "open-drain drive/readback");
  oe[10]=0;
  #10;
  if (s_gpio[11:10] !== 2'b11) $fatal(1, "open-drain release/readback");
  $display("SIM_TEST_PASS Tiny P6 board pulls");
  $finish;
end
endmodule
''')
    output = tmp_path / "sim"
    flags = ["-I" + str(tmp_path / "rtl")]
    if simulator == "iverilog":
        run([simulator, "-g2012", "-s", "board", *flags, "-o", str(output), str(source)],
            tmp_path, "compile")
        launch = ["vvp", str(output)]
    else:
        run([simulator, "--binary", "--timing", "-Wno-fatal", "--top-module", "board",
             *flags, str(source), "--Mdir", str(tmp_path / "obj"), "-o", str(output)],
            tmp_path, "compile", timeout=180)
        launch = [str(output)]
    assert "SIM_TEST_PASS Tiny P6 board pulls" in run(launch, tmp_path, "sim")


@pytest.mark.parametrize("tiny", [True, False])
def test_dma_sdk_request_matrix(tmp_path, tiny):
    assert shutil.which("cc"), "host compiler required"
    if tiny:
        generate_bindings(read_topology(TINY / "integration/soc_topology.json",
                                       TINY / "address_map/memory_map.json"), tmp_path)
    else:
        extension = tmp_path / "include/retrosoc/generated/user_extensions.h"
        extension.parent.mkdir(parents=True)
        extension.write_text("")
    generate_memory_map(ROOT / ("rtl/tiny" if tiny else "rtl/mini") / "address_map/memory_map.json",
                        tmp_path / "map", "YES", 128 if tiny else 32)
    probe = tmp_path / "probe.c"
    probe.write_text(r'''
#include <assert.h>
#include <retrosoc/hal/dma.h>
int main(void) {
    _Alignas(64) rs_dma_tcd_t tcd = {0};
    rs_dma_config_t c = {.kind=RS_DMA_KIND_MM_TO_MM, .source=0x30000000U,
        .destination=0x30010000U, .byte_count=64U, .width=RS_DMA_WIDTH_32,
        .source_increment=true, .destination_increment=true, .burst_beats=16U};
    for (unsigned channel=0; channel<8; ++channel) {
        for (unsigned request=0; request<16; ++request) {
            c.request=(rs_dma_request_t)request;
            c.kind=(request==1 || request==12) ? RS_DMA_KIND_MM_TO_STREAM :
                ((request==2 || request==11 || request==13) ? RS_DMA_KIND_STREAM_TO_MM :
                 RS_DMA_KIND_MM_TO_MM);
#ifdef RS_SOC_TINY
            bool supported=(0x31ffU & (1U << request)) != 0U;
#else
            bool supported=request < 14U;
#endif
            assert((rs_dma_config_validate(channel, &c)==RS_OK)==supported);
            tcd.source=c.source; tcd.destination=c.destination; tcd.byte_count=64U;
            tcd.control=RS_DMA_TCD_VALID | RS_DMA_TCD_SRC_INC | RS_DMA_TCD_DST_INC |
                ((unsigned)c.kind << RS_DMA_TCD_KIND_SHIFT) |
                (request << RS_DMA_TCD_REQUEST_SHIFT) | (16U << RS_DMA_TCD_BURST_SHIFT);
            assert((rs_dma_tcd_validate(channel, &tcd)==RS_OK)==supported);
        }
    }
    assert(rs_dma_config_validate(8, &c)!=RS_OK);
    c.request=(rs_dma_request_t)16;
    assert(rs_dma_config_validate(0, &c)!=RS_OK);
    c.request=(rs_dma_request_t)17;
    assert(rs_dma_config_validate(0, &c)!=RS_OK);
    c.request=(rs_dma_request_t)255;
    assert(rs_dma_config_validate(0, &c)!=RS_OK);
    return 0;
}
''')
    binary = tmp_path / "probe"
    command = ["cc", "-std=c11", "-Wall", "-Wextra", "-Werror",
               "-I" + str(ROOT / "crt/include"), "-I" + str(tmp_path / "include"),
               "-I" + str(tmp_path / "map/include"), str(probe),
               str(ROOT / "crt/src/hal/dma_math.c"), "-o", str(binary)]
    subprocess.run(command, check=True, capture_output=True, text=True)
    subprocess.run([str(binary)], check=True, capture_output=True, text=True)


def test_p6_reset_and_macro_policy_remains_explicit():
    text = (TINY / "top/retrosoc_tiny.sv").read_text()
    assert ".clk_aud_i" in text and "s_audio_rst_n" in text
    assert ".EnableStreams" in text and "16'h31ff" in text
    assert "apb4_crypto u_crypto" in text
    tree = (TINY / "top/tiny_reset_tree.sv").read_text()
    assert "s_audio" not in tree and "crypto" not in tree
    assert ".STAGE(5)" in tree
