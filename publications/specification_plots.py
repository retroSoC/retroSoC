"""Deterministic scientific curves for the two source-bound datasheets."""
from __future__ import annotations

from datetime import datetime, timezone
import importlib.metadata
from pathlib import Path
import re

from publications.specification_reference import digest, export_csv, write

REQUIRED = {"matplotlib": "3.10.7", "numpy": "2.2.6", "fonttools": "4.60.1"}


def verify_environment(root: Path) -> dict:
    pins = dict(re.findall(r"^([\w.-]+)==([^\s]+)", (root / "requirements/publication.txt").read_text(encoding="utf-8"), re.M))
    versions = {name: importlib.metadata.version(name) for name in pins}
    if versions != pins or any(versions.get(k) != v for k, v in REQUIRED.items()):
        raise ValueError("publication plotting environment differs from requirements/publication.txt")
    return versions


def render(root: Path, out: Path, spec: dict, date: str) -> dict:
    versions = verify_environment(root)
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.font_manager import FontProperties, fontManager
    from fontTools.ttLib import TTFont
    from fontTools.varLib.instancer import instantiateVariableFont

    plot_dir = out / "characteristics"
    plot_dir.mkdir(exist_ok=True)
    source = root / "publications/media/fonts/inter/Inter-VariableFont_opsz,wght.ttf"
    font = plot_dir / "Inter-Regular.ttf"
    variable = TTFont(source)
    static = instantiateVariableFont(variable, {"wght": 400, "opsz": 14}, inplace=False)
    # FontTools' creation/modification values follow the managed input; do not use wall time.
    static.recalcTimestamp = False
    static.save(font)
    fontManager.addfont(str(font))
    family = FontProperties(fname=str(font)).get_name()
    plt.rcParams.update({
        "font.family": family, "font.size": 9, "axes.titlesize": 10.5, "axes.labelsize": 9,
        "xtick.labelsize": 9, "ytick.labelsize": 9, "legend.fontsize": 9,
        "svg.fonttype": "none", "svg.hashsalt": "retrosoc-specification-v1",
        "pdf.fonttype": 42, "axes.edgecolor": "#292c31", "axes.labelcolor": "#292c31",
        "text.color": "#292c31", "axes.linewidth": .6, "lines.linewidth": 1.15,
        "savefig.transparent": False, "figure.facecolor": "white",
    })
    colors = ["#292c31", "#a38442", "#62666c", "#245a81"]
    styles = ["-", "--", "-.", ":"]
    epoch = datetime.fromisoformat(date).replace(tzinfo=timezone.utc)
    files = {}
    for dataset in spec["datasets"]:
        fig, ax = plt.subplots(figsize=(172 / 25.4, 104 / 25.4))
        fig.subplots_adjust(left=.14, right=.97, bottom=.23, top=.77)
        marker = "REFERENCE ONLY" if dataset["status"] == "reference" else "CALCULATED / IDEAL"
        fig.text(.5, .965, marker, ha="center", fontsize=10, weight="regular")
        fig.text(.5, .89, dataset["title"], ha="center", fontsize=10.5)
        series = list(dict.fromkeys(p["series"] for p in dataset["points"]))
        for i, name in enumerate(series):
            points = sorted((p for p in dataset["points"] if p["series"] == name), key=lambda p: p["x"])
            xs, ys = [p["x"] for p in points], [p["y"] for p in points]
            if dataset["id"] == "current-modes":
                width = .75 / len(series)
                ax.bar([x - .375 + width * (i + .5) for x in xs], ys, width=width,
                       edgecolor="#292c31", linewidth=.6, color=colors[i % 4],
                       hatch=["", "//", "..", "\\\\"][i % 4], label=name)
            else:
                ax.plot(xs, ys, linestyle=styles[i % 4], color=colors[i % 4],
                        marker=["o", "s", "^", "D"][i % 4], markersize=3, label=name)
        ax.set_xlabel(dataset["x_label"])
        ax.set_ylabel(dataset["y_label"])
        ax.grid(axis="y", linewidth=.4, color="#d5d6d8")
        ax.set_axisbelow(True)
        if len(series) > 1:
            ax.legend(loc="best", framealpha=1, facecolor="white", edgecolor="#d5d6d8")
        if dataset["id"] == "current-modes":
            ax.set_xticks([0, 1, 2], ["Run", "WFI", "WFI + idle gates"])
        if dataset["id"] == "transfer":
            ax.set_xscale("log", base=2)
            ax.set_xticks([256, 1024, 4096, 16384, 65536], ["256", "1024", "4096", "16384", "65536"])
        condition = dataset["conditions"]
        # Fixed lines prevent font fitting or tiny footnotes; all plot text is >=9 pt.
        import textwrap
        for i, line in enumerate(textwrap.wrap(condition, 104)):
            fig.text(.04, .09 - i * .045, line, fontsize=9)
        paths = {}
        for suffix in ("svg", "pdf"):
            target = plot_dir / (dataset["id"] + "." + suffix)
            metadata = ({"Date": date, "Creator": "retroSoC publication"} if suffix == "svg" else
                        {"CreationDate": epoch, "ModDate": epoch, "Creator": "retroSoC publication"})
            fig.savefig(target, metadata=metadata)
            paths[suffix] = "/" + target.relative_to(root).as_posix()
            files[target.relative_to(out).as_posix()] = digest(target)
        target = plot_dir / (dataset["id"] + ".csv")
        export_csv(target, dataset)
        files[target.relative_to(out).as_posix()] = digest(target)
        dataset["paths"] = paths
        plt.close(fig)
    write(plot_dir / "plot-manifest.json", dict(versions=versions, font_source_sha256=digest(source),
                                               font_instance_sha256=digest(font), files=files))
    files["characteristics/plot-manifest.json"] = digest(plot_dir / "plot-manifest.json")
    return dict(versions=versions, outputs=files, font_source_sha256=digest(source))
