"""Reject incomplete P8 transport/optional-device evidence."""
import pytest
from pathlib import Path

from scripts.tiny_r2_p8 import measurements

CONFIG = {"PDK": "IHP130", "EXT_CLK_HZ": "24000000"}


@pytest.fixture
def valid_log():
    return "\n".join([
        "P8_TRANSPORT sys_hz=24000000 mem_hz=24000000 bytes=1024 burst=4 "
        "isolated_cycles=24000 contended_cycles=48000 progress=10",
        *[f"P8_XPI_WINDOW index={i} mem_cycles=24000 "
          f"write_bytes={1024 if i % 2 == 0 else 0} read_bytes={0 if i % 2 == 0 else 1024} "
          "aw_max=10 w_max=20 ar_max=30 b_max=40 r_max=50" for i in range(4)],
        "P8_RESULT code=0 profiles=1", "SIM_TEST_PASS Tiny cycles=100000",
    ])


def test_p8_measurement_units(valid_log):
    result = measurements(valid_log, CONFIG)
    assert result["profiles"][0]["isolated_bytes_per_second"] == 1024000
    assert result["profiles"][0]["contended_bytes_per_second"] == 512000
    assert result["windows"][0]["b_max_ns"] == pytest.approx(40e9 / 24e6)


@pytest.mark.parametrize("old,new", [
    ("SIM_TEST_PASS Tiny cycles=100000", "Hello retroSoC!"),
    ("profiles=1", "profiles=0"), ("code=0", "code=3"),
    ("write_bytes=1024", "write_bytes=1020"), ("progress=10", "progress=0"),
    ("aw_max=10", "aw_max=25000"), ("isolated_cycles=24000", "isolated_cycles=0"),
])
def test_p8_rejects_incomplete_measurements(valid_log, old, new):
    with pytest.raises(ValueError):
        measurements(valid_log.replace(old, new), CONFIG)


def test_p8_does_not_promote_missing_profiles_or_errors(valid_log):
    with pytest.raises(ValueError):
        measurements(valid_log, {"PDK": "ICS55", "EXT_CLK_HZ": "24000000"})
    with pytest.raises(ValueError):
        measurements(valid_log + "\nSIM_TEST_FAIL", CONFIG)
    with pytest.raises(ValueError):
        measurements(valid_log, CONFIG, absent=True)


def test_p8_optional_absence_has_separate_verdict():
    log = ("P8_ABSENT bounded optional-device rejection\nP8_RESULT code=0 profiles=0\n"
           "SIM_TEST_PASS Tiny cycles=100000\n")
    assert measurements(log, CONFIG, absent=True)["mode"] == "absent"
    with pytest.raises(ValueError):
        measurements(log, CONFIG)


def test_p8_observer_labels_match_axi_channels():
    source = (Path(__file__).resolve().parents[1] /
              "rtl/tiny/dv/tiny_p8_observers.svh").read_text()
    order = source.split("wire [4:0] s_p8_stalls = {", 1)[1].split("};", 1)[0]
    channels = [line.split("`_P8_AXI.", 1)[1].split("valid", 1)[0]
                for line in order.splitlines() if "`_P8_AXI." in line]
    assert channels == ["aw", "w", "ar", "b", "r"]
