"""Export the same CeTZ engineering views as standalone editable vector artifacts."""
from __future__ import annotations

from pathlib import Path
import subprocess

from publications.specification_reference import digest


def render(root: Path, out: Path, spec: dict, executable: str, options: list[str]) -> dict:
    destination = out / "engineering"
    destination.mkdir(exist_ok=True)
    expressions = {
        "board-minimum": 'connection(s,"minimum")',
        "board-supply": 'board-circuit(s,"decoupling")',
        "board-reset": 'board-circuit(s,"clock-reset-boot")',
        "board-layout": 'connection(s,"layout")',
    }
    if spec["product"] == "tiny":
        expressions.update({
            "qfn-top": 'qfn-view(s,"Top")',
            "qfn-bottom": 'qfn-view(s,"Bottom",dimensions:true)',
            "qfn-side": 'qfn-side(s)',
            "qfn-copper": 'pcb-view(s,"copper")',
            "qfn-mask": 'pcb-view(s,"mask")',
            "qfn-paste": 'pcb-view(s,"paste")',
            "qfn-vias": 'pcb-view(s,"thermal vias")',
        })
    text = ('#import "/publications/specifications/figures.typ": *\n'
            '#set page(width:auto,height:auto,margin:4mm)\n'
            '#set text(font:"Inter",size:9pt,weight:"regular")\n'
            '#let s=json(sys.inputs.at("data")).specifications\n'
            '#let view=sys.inputs.at("figure")\n')
    text += "\n".join(f'#if view=="{key}" {{{expression}}}' for key, expression in expressions.items()) + "\n"
    source = destination / "reference-views.typ"
    source.write_text(text, encoding="utf-8", newline="\n")
    files = {source.relative_to(out).as_posix(): digest(source)}
    for key in expressions:
        for suffix in ("svg", "pdf"):
            target = destination / (key + "." + suffix)
            result = subprocess.run([executable, "compile", str(source), str(target),
                                     *options, "--input", "figure=" + key],
                                    cwd=root, capture_output=True, text=True, encoding="utf-8")
            if result.returncode or "warning:" in result.stderr:
                raise ValueError("standalone engineering vector failed: " + result.stderr)
            files[target.relative_to(out).as_posix()] = digest(target)
    return files
