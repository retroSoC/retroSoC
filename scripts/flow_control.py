"""Shared digests, leases, and process identity for resumable flows."""

from __future__ import annotations

import hashlib
import json
import os
import subprocess
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from scripts.agent_control import dump_json, read_json
from scripts.setup_helpers import atomic_write

FINGERPRINT_KEYS = (
    "source_revision",
    "source_state_sha256",
    "script_sha256",
    "input_sha256",
    "environment_sha256",
    "tool_lock_sha256",
    "configuration",
    "command_sha256",
)


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def write_json(path: Path, document: dict[str, Any]) -> None:
    atomic_write(path, dump_json(document))


def digest_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def digest_json(value: Any) -> str:
    return digest_bytes(json.dumps(value, sort_keys=True, separators=(",", ":")).encode("utf-8"))


def file_digest(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def git_bytes(root: Path, *arguments: str) -> bytes:
    return subprocess.check_output(["git", "-C", str(root), *arguments], stderr=subprocess.DEVNULL)


def source_state(root: Path) -> dict[str, Any]:
    root = root.resolve()
    try:
        revision = git_bytes(root, "rev-parse", "HEAD").decode("ascii").strip()
        diff = git_bytes(root, "diff", "--binary", "HEAD")
        untracked = git_bytes(root, "ls-files", "--others", "--exclude-standard", "-z").split(b"\0")
    except (OSError, subprocess.CalledProcessError):
        return {
            "source_revision": None,
            "source_state_sha256": None,
            "source_dirty": False,
            "tool_lock_sha256": None,
        }
    untracked_digests = {}
    for raw in untracked:
        if not raw:
            continue
        relative = raw.decode("utf-8")
        path = root / relative
        if path.is_file():
            untracked_digests[relative] = file_digest(path)
    state = {
        "diff_sha256": digest_bytes(diff),
        "untracked_sha256": untracked_digests,
    }
    lock = root / "dependencies/dependencies.lock.json"
    return {
        "source_revision": revision,
        "source_state_sha256": digest_json(state),
        "source_dirty": bool(diff or untracked_digests),
        "tool_lock_sha256": file_digest(lock) if lock.is_file() else None,
    }


def execution_fingerprint(
    root: Path,
    command: list[str],
    environment: dict[str, str],
    *,
    script: Path | None,
    inputs: list[Path],
    configuration: dict[str, Any],
) -> dict[str, Any]:
    return {
        **source_state(root),
        "script_sha256": file_digest(script.resolve()) if script is not None else None,
        "input_sha256": {str(path.resolve()): file_digest(path.resolve()) for path in sorted(inputs)},
        "environment_sha256": digest_json(environment),
        "configuration": configuration,
        "command_sha256": digest_json(command),
    }


def fingerprint_mismatches(previous: dict[str, Any], current: dict[str, Any]) -> list[str]:
    return [key for key in FINGERPRINT_KEYS if previous.get(key) != current.get(key)]


def process_start_ticks(pid: int) -> int | None:
    try:
        text = Path(f"/proc/{pid}/stat").read_text(encoding="utf-8")
        fields = text.rsplit(")", 1)[1].split()
        return int(fields[19])
    except (OSError, IndexError, ValueError):
        return None


def pid_matches(pid: int | None, ticks: int | None) -> bool:
    return pid is not None and ticks is not None and process_start_ticks(pid) == ticks


def process_group_exists(pgid: int) -> bool:
    if pgid <= 0:
        raise ValueError("process group ID must be positive")
    try:
        for entry in Path("/proc").iterdir():
            if not entry.name.isdigit():
                continue
            try:
                fields = (entry / "stat").read_text(encoding="utf-8").rsplit(")", 1)[1].split()
                if int(fields[2]) == pgid and fields[0] not in {"Z", "X", "x"}:
                    return True
            except (OSError, IndexError, ValueError):
                continue
        return False
    except OSError:
        try:
            os.killpg(pgid, 0)
            return True
        except ProcessLookupError:
            return False
        except PermissionError:
            return True


def terminate_process_group(pgid: int, grace_seconds: float = 5.0) -> bool:
    if not process_group_exists(pgid):
        return False
    try:
        os.killpg(pgid, 15)
    except ProcessLookupError:
        return False
    deadline = time.monotonic() + grace_seconds
    while process_group_exists(pgid) and time.monotonic() < deadline:
        time.sleep(0.05)
    if process_group_exists(pgid):
        try:
            os.killpg(pgid, 9)
        except ProcessLookupError:
            pass
    return process_group_exists(pgid)


class Lease:
    def __init__(self, path: Path, metadata: dict[str, Any]):
        self.path = path.resolve()
        self.metadata = metadata
        self.lease_id = uuid.uuid4().hex

    def acquire(self) -> "Lease":
        self.path.parent.mkdir(parents=True, exist_ok=True)
        for attempt in range(2):
            try:
                descriptor = os.open(self.path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
            except FileExistsError:
                document = read_json(self.path)
                if pid_matches(document.get("parent_pid"), document.get("parent_start_ticks")):
                    raise RuntimeError(f"another flow owns the active lease: {self.path}")
                if attempt:
                    raise RuntimeError(f"cannot replace stale flow lease: {self.path}")
                stale = self.path.with_name(self.path.name + f".{document.get('lease_id', 'unknown')}.stale")
                os.replace(self.path, stale)
                continue
            with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
                json.dump(
                    {
                        **self.metadata,
                        "lease_id": self.lease_id,
                        "parent_pid": os.getpid(),
                        "parent_start_ticks": process_start_ticks(os.getpid()),
                        "created_at": utc_now(),
                        "heartbeat_at": utc_now(),
                    },
                    stream,
                    sort_keys=True,
                )
            return self
        raise AssertionError("unreachable")

    def heartbeat(self) -> None:
        current = read_json(self.path)
        if current.get("lease_id") != self.lease_id:
            raise RuntimeError(f"flow lease ownership changed: {self.path}")
        write_json(self.path, {**current, "heartbeat_at": utc_now()})

    def release(self) -> None:
        try:
            current = read_json(self.path)
        except ValueError:
            return
        if current.get("lease_id") == self.lease_id:
            self.path.unlink(missing_ok=True)

    def __enter__(self) -> "Lease":
        return self.acquire()

    def __exit__(self, _kind: object, _value: object, _traceback: object) -> None:
        self.release()


def preserve_attempt(result_path: Path, log_path: Path) -> dict[str, Any] | None:
    if not result_path.is_file():
        return None
    previous = read_json(result_path)
    attempts = result_path.parent / f"{result_path.name}.attempts"
    attempts.mkdir(parents=True, exist_ok=True)
    identity = previous.get("run_id") or f"legacy-{uuid.uuid4().hex}"
    os.replace(result_path, attempts / f"{identity}-{result_path.name}")
    if log_path.is_file():
        os.replace(log_path, attempts / f"{identity}-{log_path.name}")
    return previous


def cancel_requested(result_path: Path, document: dict[str, Any]) -> Path:
    cancel_path = result_path.with_name(result_path.name + ".cancel.json")
    write_json(
        cancel_path,
        {"schema_version": 1, "run_id": document.get("run_id"), "requested_at": utc_now()},
    )
    return cancel_path


def reconcile_result(result_path: Path) -> dict[str, Any]:
    document = read_json(result_path)
    if document.get("status") != "running":
        return document
    if pid_matches(document.get("parent_pid"), document.get("parent_start_ticks")):
        return document
    child_pid = document.get("child_pid")
    pending = True
    if pid_matches(child_pid, document.get("child_start_ticks")):
        pending = terminate_process_group(int(child_pid))
    finished = utc_now()
    document.update(
        status="interrupted",
        exit_code=130,
        finished_at=finished,
        heartbeat_at=finished,
        child_cleanup_pending=pending,
        error="flow parent is no longer running; stale execution was reconciled",
    )
    write_json(result_path, document)
    return document


def cancel_result(result_path: Path) -> dict[str, Any]:
    document = read_json(result_path)
    if document.get("status") != "running":
        return document
    if not document.get("run_id"):
        raise RuntimeError("cannot cancel a flow without a run identity")
    cancel_requested(result_path, document)
    if pid_matches(document.get("parent_pid"), document.get("parent_start_ticks")):
        os.kill(int(document["parent_pid"]), 15)
        return document
    if pid_matches(document.get("child_pid"), document.get("child_start_ticks")):
        terminate_process_group(int(document["child_pid"]))
        return reconcile_result(result_path)
    raise RuntimeError("flow process identity no longer matches; refusing to signal another process")
