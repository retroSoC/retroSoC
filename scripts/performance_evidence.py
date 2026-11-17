#!/usr/bin/env python3
"""Bind offline regression samples to complete identities without starting experiments."""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import math
import re
import stat
import sys
import zipfile
from pathlib import Path, PurePosixPath
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from scripts.agent_control import read_json  # noqa: E402
from scripts.ci_observations import MAX_ARTIFACT_BYTES  # noqa: E402
from scripts.flow_control import utc_now, write_json  # noqa: E402
from scripts.regress import selection_digest, semantic_digest  # noqa: E402

REVISION = re.compile(r"^[0-9a-f]{40}$")
DIGEST = re.compile(r"^[0-9a-f]{64}$")
ARTIFACT = re.compile(r"^(?:pr|nightly)-regression-(\d+)-(\d+)(?:-.+)?$")
SUPPORTED_TASKS = {"iverilog-sim": ("sim-asm", "sim", "netsim", "netsim-boot", "postsim")}
ROLES = {"observation", "baseline", "candidate"}


def member_document(archive: zipfile.ZipFile, info: zipfile.ZipInfo) -> Any:
    path = PurePosixPath(info.filename)
    if path.is_absolute() or ".." in path.parts or info.is_dir():
        raise ValueError("performance artifact path is unsafe")
    if stat.S_ISLNK(info.external_attr >> 16):
        raise ValueError("performance artifact JSON must not be a symlink")
    if info.file_size > MAX_ARTIFACT_BYTES:
        raise ValueError("performance artifact JSON exceeds the observation limit")
    return json.loads(archive.read(info))


def valid_revision(value: Any, label: str) -> str:
    if not isinstance(value, str) or REVISION.fullmatch(value) is None:
        raise ValueError(f"{label} must be a full Git revision")
    return value


def valid_digest(value: Any, label: str) -> str:
    if not isinstance(value, str) or DIGEST.fullmatch(value) is None:
        raise ValueError(f"{label} must be a SHA-256 digest")
    return value


def positive_number(value: Any, label: str) -> int | float:
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or value <= 0:
        raise ValueError(f"{label} must be a positive finite number")
    return value


def isolation_identity(job: dict[str, Any], supplied: Any) -> tuple[dict[str, Any], dict[str, Any]] | None:
    if supplied is None:
        return None
    if not isinstance(supplied, dict) or supplied.get("exclusive") is not True:
        raise ValueError("runner isolation must explicitly be exclusive")
    lease = supplied.get("lease_id")
    machine = supplied.get("machine")
    contention = supplied.get("contention")
    if not isinstance(lease, str) or not lease or not isinstance(machine, str) or not machine:
        raise ValueError("runner isolation requires lease and machine identities")
    if contention != "NONE":
        raise ValueError("runner isolation requires an explicit NONE contention observation")
    cpu = supplied.get("cpu_count")
    memory = supplied.get("memory_bytes")
    if any(isinstance(value, bool) or not isinstance(value, int) or value <= 0 for value in (cpu, memory)):
        raise ValueError("runner isolation CPU and memory resources must be positive integers")
    runner_id = supplied.get("runner_id", job.get("runner_id"))
    if runner_id != job.get("runner_id"):
        raise ValueError("runner isolation does not match the job runner")
    resource = {"machine": machine, "cpu_count": cpu, "memory_bytes": memory, "contention": contention}
    return {"lease_id": lease, "runner_id": runner_id, **resource}, resource


def plan_for_manifest(plan: dict[str, Any], manifest: dict[str, Any], task: str) -> dict[str, Any]:
    if plan.get("schema_version") != 1 or plan.get("kind") != "regression-command-identity":
        raise ValueError("regression command plan has an invalid identity")
    if plan.get("source_revision") != manifest["repository"]["commit"]:
        raise ValueError("regression command plan source differs from the variant manifest")
    if plan.get("dependency_lock_sha256") != manifest["dependency_lock"]["sha256"]:
        raise ValueError("regression command plan tool lock differs from the variant manifest")
    if plan.get("command_set_sha256") != selection_digest(plan):
        raise ValueError("regression command plan digest does not match its selected commands")
    commands = plan.get("commands")
    if not isinstance(commands, list) or any(not isinstance(command, dict) for command in commands):
        raise ValueError("regression command plan commands are missing")
    candidates = [
        command
        for command in commands
        if command.get("profile", "").endswith(f"/{manifest['profile']}.mk")
        and "SIMU=IVERILOG" in command.get("arguments", [])
        and any(target in SUPPORTED_TASKS[task] for target in command.get("arguments", []))
    ]
    if len(candidates) != 1:
        raise ValueError(f"cannot uniquely bind {task} to a selected Make command")
    selected = candidates[0]
    if any(not isinstance(selected.get(field), list) for field in ("arguments", "command")) or any(
        not isinstance(item, str) for field in ("arguments", "command") for item in selected[field]
    ):
        raise ValueError("selected Make command and arguments must be string arrays")
    if selected.get("command_sha256") != semantic_digest(selected.get("command")):
        raise ValueError("selected Make command digest does not match its argv")
    return selected


def bind_sample(
    artifact: Path,
    job: dict[str, Any],
    task: str = "iverilog-sim",
    role: str = "observation",
    isolation: Any = None,
    artifact_name: str | None = None,
) -> dict[str, Any]:
    if task not in SUPPORTED_TASKS:
        raise ValueError(f"unsupported performance task: {task}")
    if role not in ROLES:
        raise ValueError("performance sample role must be observation, baseline, or candidate")
    revision = valid_revision(job.get("head_sha"), "job head_sha")
    run_id = job.get("run_id")
    attempt = job.get("run_attempt", 1)
    job_id = job.get("id")
    if any(isinstance(value, bool) or not isinstance(value, int) or value <= 0 for value in (run_id, attempt, job_id)):
        raise ValueError("performance job identifiers must be positive integers")
    if job.get("status") != "completed" or job.get("conclusion") != "success":
        raise ValueError("performance samples require a successful completed job")
    identity = ARTIFACT.fullmatch(artifact_name or artifact.stem)
    if identity is None or (int(identity.group(1)), int(identity.group(2))) != (run_id, attempt):
        raise ValueError("performance artifact name does not match its job run and attempt")
    if artifact.stat().st_size > MAX_ARTIFACT_BYTES:
        raise ValueError("performance artifact exceeds the 16 MiB observation limit")
    payload = artifact.read_bytes()
    isolation_evidence = isolation_identity(job, isolation)
    gaps = [] if isolation_evidence is not None else ["runner isolation and contention controls absent"]
    samples = []
    with zipfile.ZipFile(io.BytesIO(payload)) as archive:
        manifests = {}
        results = []
        plans = []
        for info in archive.infolist():
            path = PurePosixPath(info.filename)
            if path.is_absolute() or ".." in path.parts:
                raise ValueError("performance artifact path is unsafe")
            if path.name == "manifest.json" and path.parent.name == "meta" and len(path.parts) == 3:
                manifests[path.parts[0]] = member_document(archive, info)
            elif path.name.startswith("result-") and path.suffix == ".json" and ".attempts" not in path.parts:
                document = member_document(archive, info)
                if isinstance(document, dict) and document.get("task_id") == task:
                    results.append((path, document))
            elif path.parent.name == "ci-summary" and path.name.startswith("regression-plan-"):
                plans.append(member_document(archive, info))
        if len(plans) > 1:
            raise ValueError("performance artifact contains ambiguous regression command plans")
        if not plans:
            gaps.append("evaluated command plan is unavailable")
        if not results:
            raise ValueError(f"performance artifact has no {task} result")
        for result_path, result in results:
            variant = result_path.parts[0]
            manifest = manifests.get(variant)
            if not isinstance(manifest, dict):
                raise ValueError(f"performance result has no variant manifest: {result_path}")
            repository = manifest.get("repository")
            dependency_lock = manifest.get("dependency_lock")
            profile = manifest.get("profile")
            if (
                manifest.get("schema_version") != 1
                or not isinstance(repository, dict)
                or repository.get("dirty") is not False
                or not isinstance(dependency_lock, dict)
                or not isinstance(profile, str)
                or not profile
            ):
                raise ValueError("performance variant manifest identity is invalid")
            if valid_revision(repository.get("commit"), "manifest revision") != revision:
                raise ValueError("performance job and manifest revisions differ")
            if valid_revision(result.get("source_revision"), "result revision") != revision:
                raise ValueError("performance result and job revisions differ")
            if result.get("schema_version") != 2 or result.get("status") != "passed" or result.get("source_dirty") is not False:
                raise ValueError("performance result is not a clean passing schema-v2 result")
            configuration = manifest.get("configuration")
            tools = manifest.get("tools")
            if not isinstance(configuration, dict) or not isinstance(tools, dict) or not isinstance(tools.get("iverilog"), str):
                raise ValueError("performance manifest configuration or tool identity is missing")
            if not configuration.get("PDK") or not configuration.get("SOC"):
                raise ValueError("performance manifest PDK or SoC identity is missing")
            lock = valid_digest(dependency_lock.get("sha256"), "manifest dependency lock")
            if result.get("tool_lock_sha256") is not None and result["tool_lock_sha256"] != lock:
                raise ValueError("performance result and manifest tool locks differ")
            command = result.get("command")
            if not isinstance(command, list) or not command or any(not isinstance(item, str) for item in command):
                raise ValueError("performance result command is missing")
            command_sha256 = valid_digest(result.get("command_sha256"), "result command digest")
            if command_sha256 != semantic_digest(command):
                raise ValueError("performance result command digest does not match argv")
            duration = positive_number(result.get("duration_seconds"), "result duration_seconds")
            peak_rss = result.get("peak_rss_kib")
            if peak_rss is not None:
                positive_number(peak_rss, "result peak_rss_kib")
            for field, label in (("environment_sha256", "execution environment digest"), ("source_state_sha256", "source state digest")):
                if result.get(field) is None:
                    gaps.append(f"{label} is unavailable")
                else:
                    valid_digest(result[field], label)
            selected = None
            if plans:
                selected = plan_for_manifest(plans[0], manifest, task)
            evaluated_profile = selected["profile"] if selected else None
            evaluated_arguments = selected["arguments"] if selected else None
            evaluated_command = selected["command"] if selected else None
            evaluated_sha256 = selected["command_sha256"] if selected else None
            command_set_sha256 = plans[0]["command_set_sha256"] if plans else None
            configuration_sha256 = semantic_digest(configuration)
            tools_sha256 = semantic_digest(tools)
            resource = isolation_evidence[1] if isolation_evidence is not None else None
            pairing_key = None
            if not gaps:
                pairing_key = semantic_digest(
                    {
                        "task": task,
                        "profile": manifest["profile"],
                        "pdk": configuration["PDK"],
                        "soc": configuration["SOC"],
                        "configuration_sha256": configuration_sha256,
                        "tool_lock_sha256": lock,
                        "tool_versions_sha256": tools_sha256,
                        "command_set_sha256": command_set_sha256,
                        "evaluated_command_sha256": evaluated_sha256,
                        "command_sha256": command_sha256,
                        "environment_sha256": result["environment_sha256"],
                        "isolation_resource": resource,
                    }
                )
            samples.append(
                {
                    "artifact_name": artifact_name or artifact.stem,
                    "artifact_sha256": hashlib.sha256(payload).hexdigest(),
                    "run_id": run_id,
                    "run_attempt": attempt,
                    "job_id": job_id,
                    "role": role,
                    "source_revision": revision,
                    "variant": variant,
                    "result_path": result_path.as_posix(),
                    "task_id": task,
                    "profile": manifest["profile"],
                    "pdk": configuration["PDK"],
                    "soc": configuration["SOC"],
                    "configuration_sha256": configuration_sha256,
                    "tool_lock_sha256": lock,
                    "tool_lock_source": "manifest",
                    "tool_versions_sha256": tools_sha256,
                    "tool_versions": tools,
                    "evaluated_profile": evaluated_profile,
                    "evaluated_arguments": evaluated_arguments,
                    "evaluated_command": evaluated_command,
                    "evaluated_command_sha256": evaluated_sha256,
                    "command_set_sha256": command_set_sha256,
                    "command": command,
                    "command_sha256": command_sha256,
                    "environment_sha256": result.get("environment_sha256"),
                    "source_state_sha256": result.get("source_state_sha256"),
                    "duration_seconds": duration,
                    "peak_rss_kib": peak_rss,
                    "runner": {
                        "id": job.get("runner_id"),
                        "name": job.get("runner_name"),
                        "group_id": job.get("runner_group_id"),
                        "labels": job.get("labels"),
                    },
                    "isolation": isolation_evidence[0] if isolation_evidence is not None else None,
                    "identity_gaps": sorted(set(gaps)),
                    "identity_complete": not gaps,
                    "pairing_eligible": not gaps and role in {"baseline", "candidate"},
                    "pairing_key": pairing_key,
                }
            )
    if len(samples) != 1:
        raise ValueError(f"performance artifact has ambiguous {task} results")
    return samples[0]


def evaluate(samples: list[dict[str, Any]]) -> dict[str, Any]:
    groups = {}
    seen = set()
    for sample in samples:
        if sample.get("pairing_eligible") and sample.get("pairing_key") is not None:
            identity = (sample["run_id"], sample["job_id"], sample["role"])
            if identity in seen:
                raise ValueError("performance samples contain a duplicate run, job, and role")
            seen.add(identity)
            groups.setdefault(sample["pairing_key"], []).append(sample)
    pair_groups = []
    for key, members in sorted(groups.items()):
        baseline = sorted({sample["run_id"] for sample in members if sample["role"] == "baseline"})
        candidate = sorted({sample["run_id"] for sample in members if sample["role"] == "candidate"})
        if set(baseline) & set(candidate):
            raise ValueError("paired baseline and candidate samples must use distinct runs")
        pair_groups.append(
            {
                "pairing_key": key,
                "baseline_run_ids": sorted(baseline),
                "candidate_run_ids": sorted(candidate),
                "baseline_count": len(baseline),
                "candidate_count": len(candidate),
                "eligible_for_review": len(baseline) >= 5 and len(candidate) >= 5,
            }
        )
    return {
        "schema_version": 1,
        "created_at": utc_now(),
        "decision": "READY_FOR_REVIEW" if any(group["eligible_for_review"] for group in pair_groups) else "HOLD",
        "sample_count": len(samples),
        "complete_identity_count": sum(sample["identity_complete"] for sample in samples),
        "required_samples_per_role": 5,
        "complete_pair_group_count": sum(group["eligible_for_review"] for group in pair_groups),
        "pair_groups": pair_groups,
        "samples": samples,
        "experiment_started": False,
        "network_access": False,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sample", type=Path, action="append", required=True)
    parser.add_argument("--task", choices=tuple(SUPPORTED_TASKS), default="iverilog-sim")
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        samples = []
        for packet in args.sample:
            specification = read_json(packet)
            artifact = Path(specification["artifact"])
            if not artifact.is_absolute():
                artifact = packet.parent / artifact
            samples.append(
                bind_sample(
                    artifact,
                    specification["job"],
                    task=args.task,
                    role=specification.get("role", "observation"),
                    isolation=specification.get("isolation"),
                    artifact_name=specification.get("artifact_name"),
                )
            )
        result = evaluate(samples)
        write_json(args.output, result)
        print(json.dumps({key: value for key, value in result.items() if key != "samples"}, indent=2, sort_keys=True))
        return 0
    except (OSError, ValueError, KeyError, TypeError, zipfile.BadZipFile, json.JSONDecodeError) as error:
        print(f"performance evidence: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
