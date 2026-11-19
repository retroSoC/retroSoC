"""Compare published IP diagram evidence against the RM0486 review baseline."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import re

from publications.specification_reference import digest, read, write

RM0486 = (
    "https://www.st.com/resource/en/reference_manual/"
    "rm0486-stm32n647657xx-armbased-32bit-mcus-stmicroelectronics.pdf"
)
RM_SHA256 = "83cb7e9c7f784a4c5dbbedec428adf58d2cbac8cd802d11e2cdc4d504cceaa86"

# Rev 4 figure identifiers, printed/PDF pages, relationship, and applicable reading pattern.
FAMILIES = (
    ("dma", ((93, 941),), "功能相近", "区分通道、仲裁、事务与事件反馈"),
    ("sdio sdio0 sdio1", ((231, 1375),), "功能相近", "区分命令、数据引擎、时钟和卡端接口"),
    ("xpi opipsram", ((197, 1292),), "结构类比", "从地址与协议阶段追踪到存储器引脚"),
    ("psram", ((198, 1293),), "结构类比", "区分主机访问、命令阶段和四线数据"),
    ("sdram", ((160, 1178),), "结构类比", "分开请求队列、刷新、命令与外部接口"),
    ("sram", ((1, 160),), "仅借鉴表达", "明确发起方与存储边界，并单列分组及响应路径"),
    ("gpio", ((66, 784),), "功能相近", "分开输入采样、输出使能、复用与引脚"),
    ("piolite", ((66, 784), (93, 941)), "结构类比", "分开可编程执行、USER 引脚归属与 DMA 流；不推断 RM0486 具有等价状态机"),
    ("timer", ((590, 2627),), "功能相近", "从时基、计数到比较和事件"),
    ("pwm", ((501, 2485),), "功能相近", "区分时基、通道和输出控制"),
    ("rtc", ((781, 3004),), "功能相近", "分开秒周期、日历／闹钟及状态"),
    ("wdg", ((772, 2980),), "功能相近", "突出计数、服务与复位"),
    ("uart0 uart1", ((840, 3282),), "功能相近", "分开 TX/RX、FIFO、采样时钟和引脚"),
    ("i2c", ((787, 3106),), "功能相近", "区分开漏接口、采样滤波与命令状态"),
    ("spi i2s", ((881, 3428),), "功能相近", "区分配置、收发、FIFO、时钟域与引脚"),
    ("ws2812 spisd", ((881, 3428),), "仅借鉴表达", "用明确的串行路径及方向呈现本产品协议"),
    ("ps2", ((787, 3106),), "仅借鉴表达", "借鉴开漏边界和采样分区，保留 PS/2 独立协议"),
    ("archinfo", ((4, 202),), "仅借鉴表达", "明确寄存器读回和信息来源边界"),
    ("clint hp-aclint mpw-timer", ((672, 2739),), "结构类比", "强调时基、比较及输出目的地"),
    ("hp-plic", ((155, 1126),), "仅借鉴表达", "显示输入来源、事件选择和中断方向"),
    ("hp-mailbox", ((9, 281),), "仅借鉴表达", "区分各侧寄存器出口和通知事件"),
    ("dvp", ((389, 1794),), "功能相近", "按并行输入、同步、数据打包和搬运组织"),
    ("ppalite", ((398, 1820),), "结构类比", "突出实际像素处理阶段及流边界"),
    ("crypto", ((455, 2305), (493, 2409), (500, 2452)), "功能相近", "分开各引擎、配置、数据和完成路径"),
    ("crc", ((159, 1170),), "功能相近", "从数据输入追踪到计算状态和结果读回"),
    ("rng", ((452, 2287),), "功能相近", "区分采样、就绪和状态控制"),
    ("sysctrl", ((34, 412),), "结构类比", "分开寄存器门控、控制请求与复位状态"),
    ("rcu", ((34, 412),), "功能相近", "按真实选择、分频、门控和复位组织"),
    ("apu", ((914, 3503),), "仅借鉴表达", "保留音频边界，并区分实际微码与执行反馈"),
    ("resource ext-l ext-h", ((6, 260),), "仅借鉴表达", "用边界与状态回传表达已实现的归属及控制"),
    ("monitor", ((9, 281),), "仅借鉴表达", "突出观测事件入口及统计读回"),
    ("jpeg", ((451, 2265),), "功能相近", "区分编码／解码阶段、表与数据缓冲"),
    ("usb2", ((982, 3763),), "功能相近", "区分控制器、事务与物理接口边界"),
    ("mpw-gpio", ((66, 784),), "仅借鉴表达", "保留 MPW 配置实际实现的接口"),
    ("ga2d", ((132, 1033),), "功能相近", "按前景／背景读取、变换、混合及输出组织"),
    ("npu", ((116, 1013), (131, 1029)), "结构类比", "分开本地存储、计算阵列和系统数据接口"),
)
LOOKUP = {key: (refs, relation, principle)
          for keys, refs, relation, principle in FAMILIES for key in keys.split()}


def figure_numbers(directory: Path, manifest: dict, sources: dict, pages: dict) -> dict:
    from pypdf import PdfReader

    pdf = directory / manifest["document"]["filename"]
    if digest(pdf) != manifest["pdf_sha256"]:
        raise ValueError(f"IP review PDF differs from manifest: {pdf}")

    result = {}
    text_by_page = {}
    with pdf.open("rb") as stream:
        reader = PdfReader(stream)
        for key, page in pages.items():
            if page not in text_by_page:
                text_by_page[page] = " ".join(reader.pages[page - 1].extract_text().split())
            title = " ".join(sources[key]["title"].rstrip(".").split())
            pattern = rf"\bFigure (\d+)[.:] ?{re.escape(title)}[.\s]"
            numbers = re.findall(pattern, text_by_page[page], re.IGNORECASE)
            if len(numbers) != 1:
                raise ValueError(f"IP review could not locate a unique caption for {key} on page {page}")
            result[key] = int(numbers[0])
    return result


def compare(baseline: Path, current: Path) -> dict:
    old_manifest = read(baseline / "manifest.json")
    manifest = read(current / "manifest.json")
    old = read(baseline / "ip-block-geometry.json")
    now = read(current / "ip-block-geometry.json")
    old_pages = read(baseline / "ip-block-coverage.json")["pages"]
    coverage = read(current / "ip-block-coverage.json")
    source = read(current / "ip-block-sources.json")
    if not old.keys() <= now.keys() or set(coverage["pages"]) != set(now) or set(source) != set(now):
        raise ValueError("IP review inputs do not have complete publication coverage")
    old_numbers = figure_numbers(baseline, old_manifest, read(baseline / "ip-block-sources.json"), old_pages)
    numbers = figure_numbers(current, manifest, source, coverage["pages"])
    rows = []
    for key, scene in now.items():
        previous = old.get(key)
        proof = source[key]
        refs, relation, principle = LOOKUP[proof["parent"]]
        old_wires = {w["id"]: w for w in previous["wires"]} if previous else {}
        new_wires = {w["id"]: w for w in scene["wires"]}
        changed_labels = {
            k: [old_wires[k]["label"], w["label"]]
            for k, w in new_wires.items() if k in old_wires and old_wires[k]["label"] != w["label"]
        }
        routes = [
            k for k, w in new_wires.items() if k in old_wires and old_wires[k]["points"] != w["points"]
        ]
        scope = proof.get("route_details", [])
        if scene["metrics"]["crossings"] > 12:
            raise ValueError(f"IP review crossing limit exceeded: {key}")
        role = "retain" if previous == scene and not scope else "update" if previous else "add"
        rows.append({
            "product": proof["product"], "id": key, "parent": proof["parent"],
            "title": proof["title"], "anchor": "circuit-" + key,
            "baseline_figure": old_numbers.get(key), "figure": numbers[key],
            "baseline_page": old_pages.get(key), "page": coverage["pages"][key],
            "reference": [{"figure": n, "page": p, "url": f"{RM0486}#page={p}"} for n, p in refs],
            "relation": relation, "principal_comparison": principle, "decision": role,
            "before": previous["metrics"] if previous else None, "after": scene["metrics"],
            "changed_labels": changed_labels, "rerouted_edges": routes,
            "routed_in_companion_view": sorted(old_wires.keys() - new_wires.keys()),
            "companion_views": scope, "source_hashes": proof["sources"],
            "unannotated_data_widths": [
                e["id"] for e in proof["functional"]["edges"]
                if e["kind"] == "data" and e.get("width") is None
            ],
        })
    return {
        "baseline_manifest": digest(baseline / "manifest.json"),
        "manifest": digest(current / "manifest.json"),
        "baseline_pdf": old_manifest["pdf_sha256"], "pdf": manifest["pdf_sha256"],
        "product": coverage["product"], "primary": coverage["primary"],
        "details": coverage["details"], "rows": rows,
    }


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--tiny-baseline", type=Path, required=True)
    p.add_argument("--tiny", type=Path, required=True)
    p.add_argument("--mini-baseline", type=Path, required=True)
    p.add_argument("--mini", type=Path, required=True)
    p.add_argument("--output", type=Path, required=True)
    args = p.parse_args()
    books = [compare(args.tiny_baseline, args.tiny), compare(args.mini_baseline, args.mini)]
    write(args.output, {"manual": "RM0486 Rev 4", "manual_sha256": RM_SHA256, "books": books})
    print(json.dumps([
        {k: book[k] for k in ("product", "primary", "details")} for book in books
    ]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
