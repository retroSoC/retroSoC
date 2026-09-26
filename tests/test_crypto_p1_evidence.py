"""A passing old simulation must not qualify a different firmware build."""

import json

import pytest

from scripts import crypto_p1


@pytest.fixture
def firmware_record(tmp_path, monkeypatch):
    inputs = {"crt/src/hal/crypto.c": "original"}
    monkeypatch.setattr(crypto_p1, "firmware_inputs", lambda: inputs)
    artifact = tmp_path / "sim.log"
    artifact.write_text("SIM_TEST_PASS\n")
    flow = tmp_path / "flow.json"
    flow.write_text(json.dumps({"status": "passed", "exit_code": 0}))
    path = tmp_path / "crypto/p1/firmware-run.json"
    path.parent.mkdir(parents=True)
    path.write_text(json.dumps({
        "status": "passed", "kind": "ci", "source_sha256": dict(inputs),
        "manifest": {"configuration": {"APP": "ci_smoke", "HAVE_CSR": "YES"}},
        "artifacts_sha256": {str(artifact): crypto_p1.digest(artifact)},
        "flow": {"result": str(flow)},
    }))
    return tmp_path, inputs, artifact, flow


def test_firmware_identity_is_run_identity(firmware_record):
    root, _, _, _ = firmware_record
    result = crypto_p1.checked_firmware(root, "ci")
    assert result["manifest"]["configuration"] == {"APP": "ci_smoke", "HAVE_CSR": "YES"}


def test_changed_source_rejects_old_pass(firmware_record):
    root, inputs, _, _ = firmware_record
    inputs["crt/src/hal/crypto.c"] = "changed"
    with pytest.raises(ValueError, match="stale firmware inputs"):
        crypto_p1.checked_firmware(root, "ci")


def test_changed_log_rejects_old_pass(firmware_record):
    root, _, artifact, _ = firmware_record
    artifact.write_text("SIM_TEST_FAIL\n")
    with pytest.raises(ValueError, match="stale firmware artifact"):
        crypto_p1.checked_firmware(root, "ci")


def test_failed_command_cannot_reuse_success_marker(firmware_record):
    root, _, _, flow = firmware_record
    flow.write_text(json.dumps({"status": "failed", "exit_code": 1}))
    with pytest.raises(ValueError, match="command did not succeed"):
        crypto_p1.checked_firmware(root, "ci")
