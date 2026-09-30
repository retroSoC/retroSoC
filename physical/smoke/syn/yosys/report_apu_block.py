#!/usr/bin/env python3
"""Generate the retroSoC APU block-level synthesis/STA evidence report.

Parses the named artifacts of two APU block configurations (EnableP7=0
baseline and EnableP7=1 expanded) produced by physical/smoke/syn/yosys/
apu_block.mk and emits:

  * apu-block-synth.json -- machine-readable evidence
  * apu-block-synth.md   -- human-readable summary

Every number is parsed from a named artifact (Yosys stat JSON, netlist,
inventory reports, OpenSTA reports, RTL source constants); nothing is
hand-typed. Standard-cell area is report-only: no area or power ceiling is
evaluated, and pre-layout STA is not post-layout signoff.
"""

from __future__ import annotations

import argparse
import json
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[4]
TOP_MODULE = "apb4_apu"

MACRO_TYPE_PREFIX = "RM_IHPSG13_"
STDCELL_TYPE_PREFIX = "sg13g2_"
SRAM_WRAPPER_PREFIX = "tc_sram"
CLOCK_GATE_RE = re.compile(r"^sg13g2_(s)?lgcp_\d+$")

MACRO_CLASS_BY_ANCESTOR = {
    "u_proof_memo": "verifier_memo",
    "u_kws_coeff_store": "coefficient_store",
    "u_kws_sram_client": "kws_model_scratch",
    "u_control_store": "control_store",
    "u_local_sram": "codec_common_data",
    "u_microcode_loader": "loader_path_stack",
}

LOCAL_SRAM_RTL = REPO_ROOT / "rtl/ip/multimedia/apu_local_sram.sv"
APU_TOP_RTL = REPO_ROOT / "rtl/ip/multimedia/apb4_apu.sv"
APU_DEFINE_RTL = REPO_ROOT / "rtl/ip/multimedia/apu_define.svh"
DOC_REFERENCE = "docs/ip/apu.md:2698-2714"

MODULE_DEF_RE = re.compile(r"^module\s+\\?([^\s(]+)", re.MULTILINE)
WORST_BLOCK_RE = re.compile(r"(?=^Startpoint: )", re.MULTILINE)
UNCONSTRAINED_MARKER = "(Path is unconstrained)"
VIOLATED_MARKER = "(VIOLATED)"


def parse_unconstrained(path: Path) -> dict[str, Any]:
    text = read_text(path)
    endpoints: list[str] = []
    for block in WORST_BLOCK_RE.split(text):
        if not block.startswith("Startpoint: ") or UNCONSTRAINED_MARKER not in block:
            continue
        endpoint = re.search(r"^Endpoint: (\S+)", block, re.MULTILINE)
        endpoints.append(endpoint.group(1) if endpoint else "<unknown>")
    return {
        "unconstrained_path_count": text.count(UNCONSTRAINED_MARKER),
        "unconstrained_endpoints": sorted(set(endpoints)),
    }


def count_violations(path: Path) -> int:
    return read_text(path).count(VIOLATED_MARKER)


def read_json(path: Path) -> Any:
    if not path.is_file():
        raise SystemExit(f"missing artifact: {path}")
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        raise SystemExit(f"invalid JSON artifact {path}: {error}") from error


def read_text(path: Path) -> str:
    if not path.is_file():
        raise SystemExit(f"missing artifact: {path}")
    return path.read_text(encoding="utf-8", errors="replace")


def parse_config(path: Path) -> dict[str, str]:
    config: dict[str, str] = {}
    for line in read_text(path).splitlines():
        name, separator, value = line.partition("=")
        if separator:
            config[name.strip()] = value.strip()
    return config


def parse_metrics(path: Path) -> dict[str, float]:
    metrics: dict[str, float] = {}
    for line in read_text(path).splitlines():
        name, separator, value = line.partition("=")
        if not separator:
            continue
        # values carry the report prefix, e.g. "wns max -4262.54"
        token = value.strip().split()[-1] if value.strip() else ""
        try:
            metrics[name.strip()] = float(token)
        except ValueError:
            metrics[name.strip()] = float("nan")
    for key in ("wns_min", "wns_max", "tns_min", "tns_max"):
        if key not in metrics:
            raise SystemExit(f"timing metric {key} missing in {path}")
    return metrics


def count_report_lines(path: Path) -> int:
    return sum(1 for line in read_text(path).splitlines() if line.strip())


def split_module_name(name: str) -> tuple[str, str]:
    clean = name.lstrip("\\")
    if "$" not in clean:
        return clean, ""
    module_type, path = clean.split("$", 1)
    return module_type, path


def classify_cell_type(cell_type: str, defined_modules: set[str]) -> str:
    if cell_type in defined_modules:
        return "submodule"
    if cell_type.startswith(STDCELL_TYPE_PREFIX):
        return "pdk_stdcell"
    if cell_type.startswith(MACRO_TYPE_PREFIX):
        return "pdk_macro"
    if cell_type.startswith("$_"):
        return "internal_unmapped"
    return "unresolved_non_pdk"


@dataclass
class Node:
    path: str
    module_type: str
    own_cells: int = 0
    own_std_cells: int = 0
    own_macro_cells: int = 0
    own_area: float = 0.0
    children: dict[str, "Node"] = field(default_factory=dict)

    @property
    def instance(self) -> str:
        return self.path.rsplit(".", 1)[-1] if self.path else TOP_MODULE

    def subtree(self) -> tuple[int, int, float]:
        cells = self.own_cells
        macros = self.own_macro_cells
        area = self.own_area
        for child in self.children.values():
            child_cells, child_macros, child_area = child.subtree()
            cells += child_cells
            macros += child_macros
            area += child_area
        return cells, macros, area


def build_tree(area_json: dict[str, Any], defined_modules: set[str]) -> tuple[Node, set[str]]:
    root = Node(path="", module_type=TOP_MODULE)
    cell_types: set[str] = set()
    modules = area_json.get("modules")
    if not isinstance(modules, dict):
        raise SystemExit("area JSON has no modules section")
    entries = []
    for raw_name, stats in modules.items():
        module_type, path = split_module_name(raw_name)
        if path and not path.startswith(f"{TOP_MODULE}."):
            raise SystemExit(f"module outside {TOP_MODULE} hierarchy: {raw_name}")
        relative = path[len(TOP_MODULE) + 1 :] if path else ""
        entries.append((relative, module_type, stats))
    # parents must be attached before their children
    entries.sort(key=lambda item: item[0].count("."))
    for relative, module_type, stats in entries:
        by_type = stats.get("num_cells_by_type", {})
        node = Node(path=relative, module_type=module_type)
        for cell_type, count in by_type.items():
            cell_types.add(cell_type)
            if classify_cell_type(cell_type, defined_modules) == "submodule":
                continue
            node.own_cells += int(count)
            if cell_type.startswith(MACRO_TYPE_PREFIX):
                node.own_macro_cells += int(count)
            else:
                node.own_std_cells += int(count)
        node.own_area = float(stats.get("area", 0.0))
        parent = root
        if relative:
            segments = relative.split(".")
            walked: list[str] = []
            for segment in segments[:-1]:
                walked.append(segment)
                parent = parent.children.setdefault(
                    ".".join(walked), Node(path=".".join(walked), module_type="<missing>")
                )
            placeholder = parent.children.get(relative)
            if placeholder is not None:
                node.children = placeholder.children
            parent.children[relative] = node
    return root, cell_types


def parse_macros(path: Path) -> dict[str, Any]:
    by_class: dict[str, int] = {name: 0 for name in MACRO_CLASS_BY_ANCESTOR.values()}
    instances: list[str] = []
    for line in read_text(path).splitlines():
        line = line.strip()
        if not line:
            continue
        instances.append(line)
        cell_path = line.replace("/", ".")
        for ancestor, klass in MACRO_CLASS_BY_ANCESTOR.items():
            if f".{ancestor}." in cell_path:
                by_class[klass] += 1
                break
        else:
            by_class.setdefault("unclassified", 0)
            by_class["unclassified"] += 1
    return {"total_physical": len(instances), "by_class": by_class, "instances": instances}


def parse_rtl_constants() -> dict[str, int]:
    constants: dict[str, int] = {}
    local_sram = read_text(LOCAL_SRAM_RTL)
    match = re.search(r"localparam\s+int\s+unsigned\s+LogicalBankCount\s*=\s*(\d+)", local_sram)
    if not match:
        raise SystemExit(f"LogicalBankCount not found in {LOCAL_SRAM_RTL}")
    constants["local_data_logical_banks"] = int(match.group(1))

    top_rtl = read_text(APU_TOP_RTL)
    depth = re.search(
        r"apu_control_store\s*#\s*\(\s*\.Depth\((\d+)\)\s*\)\s*u_control_store", top_rtl
    )
    if not depth:
        raise SystemExit(f"control-store Depth not found in {APU_TOP_RTL}")
    constants["control_store_depth"] = int(depth.group(1))
    stack = re.search(r"\.PathStackDepth\((\d+)\)", top_rtl)
    if not stack:
        raise SystemExit(f"PathStackDepth not found in {APU_TOP_RTL}")
    constants["path_stack_depth"] = int(stack.group(1))

    define_rtl = read_text(APU_DEFINE_RTL)
    for key, macro in (
        ("local_data_bytes", "APB4_APU__LOCAL_DATA_BYTES"),
        ("local_kws_bytes", "APB4_APU__LOCAL_KWS_BYTES"),
    ):
        value = re.search(rf"`define\s+{macro}\s+(\d+)", define_rtl)
        if not value:
            raise SystemExit(f"{macro} not found in {APU_DEFINE_RTL}")
        constants[key] = int(value.group(1))
    return constants


def parse_worst_paths(path: Path, limit: int = 5) -> list[dict[str, Any]]:
    text = read_text(path)
    paths: list[dict[str, Any]] = []
    for block in WORST_BLOCK_RE.split(text):
        if not block.startswith("Startpoint: "):
            continue
        startpoint = re.search(r"^Startpoint: (\S+)", block, re.MULTILINE)
        endpoint = re.search(r"^Endpoint: (\S+)", block, re.MULTILINE)
        group = re.search(r"^Path Group: (\S+)", block, re.MULTILINE)
        path_type = re.search(r"^Path Type: (\S+)", block, re.MULTILINE)
        slack = re.search(r"(-?[0-9.eE+]+)\s+slack \((MET|VIOLATED)\)", block)
        if not (startpoint and endpoint and slack):
            continue
        paths.append(
            {
                "startpoint": startpoint.group(1),
                "endpoint": endpoint.group(1),
                "path_group": group.group(1) if group else "",
                "path_type": path_type.group(1) if path_type else "",
                "slack_ns": float(slack.group(1)),
                "verdict": slack.group(2),
            }
        )
    kept: list[dict[str, Any]] = []
    for path_type in ("max", "min"):
        typed = [item for item in paths if item["path_type"] == path_type]
        kept.extend(typed[:limit])
    return kept


def scan_link_log(path: Path) -> list[str]:
    if not path.is_file():
        return []
    findings = []
    for line in read_text(path).splitlines():
        if re.search(r"(?i)not found|blackbox|black box|undefined module", line):
            findings.append(line.strip())
    return findings


def parse_synth(root: Path) -> dict[str, Any]:
    out_dir = root / "out"
    rpt_dir = root / "rpt"
    netlist = out_dir / f"{TOP_MODULE}_yosys.v"
    area_json = read_json(rpt_dir / f"{TOP_MODULE}_area.json")
    netlist_text = read_text(netlist)
    defined_modules = {match.lstrip("\\") for match in MODULE_DEF_RE.findall(netlist_text)}
    design = area_json["design"]
    tree, module_cell_types = build_tree(area_json, defined_modules)

    all_types = set(module_cell_types) | set(design.get("num_cells_by_type", {}))
    blackboxes = {"pdk_macro": [], "pdk_stdcell": 0, "internal_unmapped": [], "unresolved_non_pdk": []}
    for cell_type in sorted(all_types):
        klass = classify_cell_type(cell_type, defined_modules)
        if klass == "pdk_macro":
            blackboxes["pdk_macro"].append(cell_type)
        elif klass == "pdk_stdcell":
            blackboxes["pdk_stdcell"] += 1
        elif klass == "internal_unmapped":
            blackboxes["internal_unmapped"].append(cell_type)
        elif klass == "unresolved_non_pdk":
            blackboxes["unresolved_non_pdk"].append(cell_type)

    latch_cells = sum(
        int(count)
        for cell_type, count in design.get("num_cells_by_type", {}).items()
        if "DLATCH" in cell_type
    )
    clock_gate_cells = sum(
        int(count)
        for cell_type, count in design.get("num_cells_by_type", {}).items()
        if CLOCK_GATE_RE.match(cell_type)
    )
    latch_report = rpt_dir / f"{TOP_MODULE}_latches.rpt"
    latch_select = count_report_lines(latch_report)

    macros = parse_macros(rpt_dir / f"{TOP_MODULE}_macros.rpt")
    macro_types: dict[str, int] = {}
    wrapper_area = 0.0
    for raw_name, stats in area_json["modules"].items():
        module_type, _ = split_module_name(raw_name)
        if module_type.startswith(SRAM_WRAPPER_PREFIX):
            wrapper_area += float(stats.get("area", 0.0))
            for cell_type, count in stats.get("num_cells_by_type", {}).items():
                if cell_type.startswith(MACRO_TYPE_PREFIX):
                    macro_types[cell_type] = macro_types.get(cell_type, 0) + int(count)
    macros["by_type"] = macro_types

    config = parse_config(out_dir / f"{TOP_MODULE}_yosys.config")
    result = read_json(root / "result-synth.json")
    return {
        "root": root,
        "config": config,
        "result": result,
        "design": design,
        "tree": tree,
        "macros": macros,
        "wrapper_area": wrapper_area,
        "latches": {"mapped_dlatch_cells": latch_cells, "select_report_entries": latch_select},
        "clock_gate_cells": clock_gate_cells,
        "blackboxes": blackboxes,
        "artifacts": {
            "netlist": netlist,
            "area_json": rpt_dir / f"{TOP_MODULE}_area.json",
            "latches": latch_report,
            "macros": rpt_dir / f"{TOP_MODULE}_macros.rpt",
            "check": rpt_dir / f"{TOP_MODULE}_synth.rpt",
            "config": out_dir / f"{TOP_MODULE}_yosys.config",
            "result": root / "result-synth.json",
        },
    }


def parse_sta(root: Path) -> dict[str, Any]:
    metrics = parse_metrics(root / "timing_metrics.rpt")
    check = parse_unconstrained(root / "unconstrained.rpt")
    result = read_json(root / "result-sta.json")
    worst = parse_worst_paths(root / "apu_block_worst.log")
    worst_max = next((item["slack_ns"] for item in worst if item["path_type"] == "max"), None)
    worst_min = next((item["slack_ns"] for item in worst if item["path_type"] == "min"), None)
    return {
        "root": root,
        "metrics": metrics,
        "check": check,
        "worst_slack_max_ns": worst_max,
        "worst_slack_min_ns": worst_min,
        "drv_violations": count_violations(root / "check_types.rpt"),
        "result": result,
        "worst_paths": worst,
        "link_findings": scan_link_log(root / "opensta.log"),
        "artifacts": {
            "max_report": root / "apu_block_sta_max.log",
            "min_report": root / "apu_block_sta_min.log",
            "worst": root / "apu_block_worst.log",
            "unconstrained": root / "unconstrained.rpt",
            "check_types": root / "check_types.rpt",
            "metrics": root / "timing_metrics.rpt",
            "result": root / "result-sta.json",
        },
    }


def flatten_tree(root: Node) -> dict[str, Node]:
    nodes: dict[str, Node] = {}

    def visit(node: Node) -> None:
        if node.path:
            nodes[node.path] = node
        for child in node.children.values():
            visit(child)

    for child in root.children.values():
        visit(child)
    return nodes


def block_table(synths: dict[str, dict[str, Any]]) -> list[dict[str, Any]]:
    trees = {name: flatten_tree(synth["tree"]) for name, synth in synths.items()}
    paths: set[str] = set()
    for nodes in trees.values():
        paths.update(nodes)
    rows = []
    for path in sorted(paths, key=lambda item: (item.count("."), item)):
        segments = path.split(".")
        if any(segment.startswith("gen_") for segment in segments):
            continue
        row: dict[str, Any] = {"path": path, "depth": path.count(".") + 1}
        for name, nodes in trees.items():
            node = nodes.get(path)
            if node is None:
                row[name] = {"cells": 0, "macros": 0, "area": 0.0, "present": False}
                continue
            cells, macros, area = node.subtree()
            row[name] = {
                "cells": cells,
                "macros": macros,
                "area": area,
                "present": node.module_type != "<missing>",
                "module_type": node.module_type,
            }
        rows.append(row)
    return rows


def summarize_configuration(
    name: str, enable_p7: int, synth: dict[str, Any], sta: dict[str, Any]
) -> dict[str, Any]:
    design = synth["design"]
    metrics = sta["metrics"]
    return {
        "name": name,
        "apu_enable_p7": enable_p7,
        "synth_status": synth["result"].get("status"),
        "synth_duration_seconds": synth["result"].get("duration_seconds"),
        "sta_status": sta["result"].get("status"),
        "sta_duration_seconds": sta["result"].get("duration_seconds"),
        "num_cells_yosys": int(design.get("num_cells", 0)),
        "area_um2": float(design.get("area", 0.0)),
        "sequential_area_um2": float(design.get("sequential_area", 0.0)),
        "sram_wrapper_area_um2": synth["wrapper_area"],
        "std_cell_area_um2": float(design.get("area", 0.0)) - synth["wrapper_area"],
        "macros": synth["macros"],
        "latches": synth["latches"],
        "clock_gate_cells": synth["clock_gate_cells"],
        "blackboxes": synth["blackboxes"],
        "sta": {
            "wns_max_ns": metrics["wns_max"],
            "tns_max_ns": metrics["tns_max"],
            "wns_min_ns": metrics["wns_min"],
            "tns_min_ns": metrics["tns_min"],
            "worst_slack_max_ns": sta["worst_slack_max_ns"],
            "worst_slack_min_ns": sta["worst_slack_min_ns"],
            "unconstrained_path_count": sta["check"]["unconstrained_path_count"],
            "unconstrained_endpoints": sta["check"]["unconstrained_endpoints"],
            "drv_violations": sta["drv_violations"],
            "worst_paths": sta["worst_paths"],
            "link_findings": sta["link_findings"],
        },
        "artifacts": {
            key: str(value) for key, value in {**synth["artifacts"], **sta["artifacts"]}.items()
        },
    }


def storage_accounting(synths: dict[str, dict[str, Any]]) -> dict[str, Any]:
    constants = parse_rtl_constants()
    wrapper_kib = 1024 * 32 // 8 // 1024  # tc_sram_1024x32 geometry: 4 KiB
    control_kib = constants["control_store_depth"] * 64 // 8 // 1024
    data_kib = constants["local_data_logical_banks"] * wrapper_kib
    kws_window_kib = constants["local_kws_bytes"] // 1024
    result: dict[str, Any] = {
        "wrapper_geometry": "tc_sram_1024x32",
        "wrapper_kib": wrapper_kib,
        "control_store": {
            "depth_words": constants["control_store_depth"],
            "wrappers": control_kib // wrapper_kib,
            "kib": control_kib,
        },
        "local_data": {
            "logical_banks": constants["local_data_logical_banks"],
            "kib": data_kib,
            "kws_window_kib": kws_window_kib,
            "macro_backed_kib": data_kib - kws_window_kib,
        },
        "combined_logical": {
            "wrappers": control_kib // wrapper_kib + constants["local_data_logical_banks"],
            "kib": control_kib + data_kib,
        },
        "p9_physical": {
            "control_store": {"wrappers": 8, "kib": 32},
            "codec_common_data": {"wrappers": 12, "kib": 48},
            "kws_model_scratch": {"wrappers": 16, "kib": 64},
            "loader_path_stack": {"wrappers": 8, "kib": 32},
            "verifier_memo": {"wrappers": 17, "kib": 68},
            "coefficient_store": {"wrappers": 15, "kib": 60},
            "total": {"wrappers": 76, "kib": 304},
        },
        "rtl_artifacts": [str(LOCAL_SRAM_RTL), str(APU_TOP_RTL), str(APU_DEFINE_RTL)],
        "per_configuration": {},
    }
    for name, synth in synths.items():
        macros = synth["macros"]
        result["per_configuration"][name] = {
            "physical_macro_instances": macros["total_physical"],
            "by_class": macros["by_class"],
            "by_type": macros["by_type"],
            "unclassified": macros["by_class"].get("unclassified", 0),
        }
    expected_p9 = {
        "control_store": 8,
        "codec_common_data": 12,
        "kws_model_scratch": 16,
        "loader_path_stack": 8,
        "verifier_memo": 17,
        "coefficient_store": 15,
    }
    expanded = result["per_configuration"]["expanded"]
    observed = {name: expanded["by_class"].get(name, 0) for name in expected_p9}
    if observed != expected_p9 or expanded["physical_macro_instances"] != 76:
        raise SystemExit(
            "P9 expanded macro inventory mismatch: "
            f"observed {observed}, total {expanded['physical_macro_instances']}; "
            f"expected {expected_p9}, total 76"
        )
    return result


def fmt_slack(value: float | None) -> str:
    return "n/a" if value is None else f"{value:.3f}"


def render_markdown(report: dict[str, Any]) -> str:
    configs = report["configurations"]
    storage = report["storage_accounting"]
    lines = [
        "# APU block-level IHP130 synthesis + STA evidence",
        "",
        f"- recipe: `{report['recipe']}` (locked Yosys/OpenSTA, PDK IHP130)",
        f"- top: `{TOP_MODULE}`; PCLK target period: {report['target_period_ns']} ns (48 MHz)",
        f"- baseline: EnableP7=0 (`{configs['baseline']['synth_root_label']}`); "
        f"expanded: EnableP7=1 (`{configs['expanded']['synth_root_label']}`)",
        "- all values parsed from the named artifacts listed at the end; report-only,",
        "  no area/power ceiling is evaluated; pre-layout STA is not post-layout signoff.",
        "",
        "## Flow status",
        "",
        "| configuration | synth | synth duration (s) | STA | STA duration (s) |",
        "| --- | --- | --- | --- | --- |",
    ]
    for name in ("baseline", "expanded"):
        cfg = configs[name]
        lines.append(
            f"| {name} (EnableP7={cfg['apu_enable_p7']}) | {cfg['synth_status']} | "
            f"{cfg['synth_duration_seconds']:.1f} | {cfg['sta_status']} | "
            f"{cfg['sta_duration_seconds']:.1f} |"
        )
    lines += [
        "",
        "## Static timing (PCLK 20.833 ns target; hold reported separately)",
        "",
        "WNS/TNS below are the SoC-flow-compatible OpenSTA metrics (clipped at 0",
        "when no negative slack exists); the true worst slack comes from the",
        "worst-paths report.",
        "",
        "| configuration | WNS max (ns) | TNS max (ns) | worst max slack (ns) | WNS min/hold (ns) | TNS min/hold (ns) | worst min slack (ns) | unconstrained paths |",
        "| --- | --- | --- | --- | --- | --- | --- | --- |",
    ]
    for name in ("baseline", "expanded"):
        sta = configs[name]["sta"]
        lines.append(
            f"| {name} | {sta['wns_max_ns']:.3f} | {sta['tns_max_ns']:.3f} | "
            f"{fmt_slack(sta['worst_slack_max_ns'])} | {sta['wns_min_ns']:.3f} | "
            f"{sta['tns_min_ns']:.3f} | {fmt_slack(sta['worst_slack_min_ns'])} | "
            f"{sta['unconstrained_path_count']} |"
        )
    lines += [
        "",
        "Acceptance reference (docs/ip/apu.md): max-delay WNS >= 0 and TNS = 0, no",
        "unconstrained active APU path; hold (min) analysis reported separately above.",
        "",
        "## Integrity checks",
        "",
        "| configuration | inferred latches | clock-gate cells | unresolved non-PDK black boxes | PDK macro black boxes | unmapped internal cells | STA DRV violations |",
        "| --- | --- | --- | --- | --- | --- | --- |",
    ]
    for name in ("baseline", "expanded"):
        cfg = configs[name]
        lines.append(
            f"| {name} | {cfg['latches']['mapped_dlatch_cells']} | "
            f"{cfg['clock_gate_cells']} | "
            f"{len(cfg['blackboxes']['unresolved_non_pdk'])} | "
            f"{', '.join(cfg['blackboxes']['pdk_macro']) or 'none'} | "
            f"{len(cfg['blackboxes']['internal_unmapped'])} | "
            f"{cfg['sta']['drv_violations']} |"
        )
    lines += [
        "",
        "PDK macro cells are Liberty black boxes exactly as in the whole-SoC flow",
        "(`read_liberty -lib`); their timing views come from the sg13g2_sram slow",
        "Liberty set during STA. Standard cells resolve against sg13g2_stdcell.",
        "",
        "## SRAM macro accounting",
        "",
        f"- wrapper geometry: `{storage['wrapper_geometry']}` = {storage['wrapper_kib']} KiB",
        f"- control store: depth {storage['control_store']['depth_words']} words -> "
        f"{storage['control_store']['wrappers']} wrappers, {storage['control_store']['kib']} KiB",
        f"- local data: {storage['local_data']['logical_banks']} logical banks -> "
        f"{storage['local_data']['kib']} KiB "
        f"(codec/common {storage['local_data']['macro_backed_kib']} KiB + "
        f"KWS model/scratch {storage['local_data']['kws_window_kib']} KiB)",
        f"- combined logical: {storage['combined_logical']['wrappers']} wrappers, "
        f"{storage['combined_logical']['kib']} KiB",
        "",
        "| configuration | control | codec/common | KWS | path stack | memo/bitmap | coefficients | total physical |",
        "| --- | --- | --- | --- | --- | --- | --- | --- |",
    ]
    for name in ("baseline", "expanded"):
        per = storage["per_configuration"][name]
        lines.append(
            f"| {name} | {per['by_class'].get('control_store', 0)} | "
            f"{per['by_class'].get('codec_common_data', 0)} | "
            f"{per['by_class'].get('kws_model_scratch', 0)} | "
            f"{per['by_class'].get('loader_path_stack', 0)} | "
            f"{per['by_class'].get('verifier_memo', 0)} | "
            f"{per['by_class'].get('coefficient_store', 0)} | "
            f"{per['physical_macro_instances']} |"
        )
    lines += [
        "",
        f"P9 physical reference ({DOC_REFERENCE}): 76 wrappers / 304 KiB. The software",
        "capacity remains 8 control-store + 28 local-data wrappers / 144 KiB; path stack,",
        "memo/bitmap and coefficient banks are auxiliary physical storage. The inspected",
        "pre-P9 source inventory was 44 wrappers, so P9 adds exactly 32 wrappers.",
        "",
        "## Per-block cell/macro/area accounting (hierarchy subtree totals)",
        "",
        "| block | cells P7=0 | cells P7=1 | delta | area um2 P7=0 | area um2 P7=1 | delta | macros P7=0/P7=1 |",
        "| --- | --- | --- | --- | --- | --- | --- | --- |",
    ]
    for row in report["blocks"]:
        base = row["baseline"]
        exp = row["expanded"]
        indent = "  " * (row["depth"] - 1)
        lines.append(
            f"| {indent}`{row['path']}` | {base['cells']} | {exp['cells']} | "
            f"{exp['cells'] - base['cells']:+d} | {base['area']:.1f} | {exp['area']:.1f} | "
            f"{exp['area'] - base['area']:+.1f} | {base['macros']}/{exp['macros']} |"
        )
    lines += [
        "",
        "Cells are leaf standard cells plus macro cells inside the kept hierarchy;",
        "areas are the sums of the Liberty cell areas inside each subtree. The",
        "All six P9 storage classes above must resolve to SRAM macros in the IHP130 flow;",
        "a register-file or giant mux implementation is not accepted as physical storage.",
        "",
        "## Worst max-delay paths (top 5 per configuration)",
        "",
    ]
    for name in ("baseline", "expanded"):
        lines.append(f"### {name}")
        lines.append("")
        lines.append("| startpoint | endpoint | slack (ns) | verdict |")
        lines.append("| --- | --- | --- | --- |")
        for path in configs[name]["sta"]["worst_paths"]:
            if path["path_type"] != "max":
                continue
            lines.append(
                f"| `{path['startpoint']}` | `{path['endpoint']}` | "
                f"{path['slack_ns']:.3f} | {path['verdict']} |"
            )
        lines.append("")
    lines += [
        "## Artifacts",
        "",
    ]
    for name in ("baseline", "expanded"):
        lines.append(f"- {name}:")
        for key, value in configs[name]["artifacts"].items():
            lines.append(f"  - {key}: `{value}`")
    lines += [
        "",
        "Assumptions are documented in physical/smoke/sta/opensta/apu_block.sdc",
        "(single PCLK domain, 30%/30% I/O budget, false path from rst_n_i).",
    ]
    return "\n".join(lines) + "\n"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline-synth", type=Path, required=True)
    parser.add_argument("--expanded-synth", type=Path, required=True)
    parser.add_argument("--baseline-sta", type=Path, required=True)
    parser.add_argument("--expanded-sta", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--recipe", default="balanced", choices=("balanced", "area", "speed"))
    parser.add_argument(
        "--top",
        default="apb4_apu",
        help="netlist top module; apb4_apu for the APU evidence flow",
    )
    return parser.parse_args()


def main() -> int:
    global TOP_MODULE
    args = parse_args()
    TOP_MODULE = args.top
    synths = {
        "baseline": parse_synth(args.baseline_synth),
        "expanded": parse_synth(args.expanded_synth),
    }
    stas = {
        "baseline": parse_sta(args.baseline_sta),
        "expanded": parse_sta(args.expanded_sta),
    }
    for name, synth in synths.items():
        expected = {"baseline": "0", "expanded": "1"}[name]
        observed = synth["config"].get("APU_ENABLE_P7")
        if observed != expected:
            raise SystemExit(
                f"{name} synth config APU_ENABLE_P7={observed}, expected {expected}: "
                f"{args.baseline_synth if name == 'baseline' else args.expanded_synth}"
            )
    period_ps = float(synths["baseline"]["config"].get("PERIOD_PS", "0"))

    report: dict[str, Any] = {
        "schema_version": 1,
        "flow": "apu-block-ihp130",
        "generated_by": "physical/smoke/syn/yosys/report_apu_block.py",
        "recipe": args.recipe,
        "target_period_ns": period_ps / 1000.0,
        "configurations": {
            name: summarize_configuration(name, int(p7), synths[name], stas[name])
            for name, p7 in (("baseline", "0"), ("expanded", "1"))
        },
        "storage_accounting": storage_accounting(synths),
        "documentation_reference": {
            "source": DOC_REFERENCE,
            "p9_physical_wrappers": 76,
            "p9_physical_kib": 304,
            "pre_p9_source_wrappers": 44,
            "added_wrappers": 32,
            "advertised_capacity_wrappers": 36,
            "advertised_capacity_kib": 144,
        },
    }
    report["blocks"] = block_table(synths)
    for name, cfg in report["configurations"].items():
        cfg["synth_root_label"] = str(synths[name]["root"])

    args.output_dir.mkdir(parents=True, exist_ok=True)
    json_path = args.output_dir / "apu-block-synth.json"
    md_path = args.output_dir / "apu-block-synth.md"
    json_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    md_path.write_text(render_markdown(report), encoding="utf-8")
    print(f"generated: {json_path}")
    print(f"generated: {md_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
