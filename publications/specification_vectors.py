"""Export the same CeTZ engineering views as standalone editable vector artifacts."""
from __future__ import annotations

from pathlib import Path
import subprocess

from publications.specification_reference import digest


def render(root: Path, out: Path, spec: dict, executable: str, options: list[str],
           *, r1_product_line_height: float | None = None) -> dict:
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
            "address-map": 'address-map(json(sys.inputs.at("data")).address_map)',
            "tiny-gen1-highlights": 'feature-highlights(json(sys.inputs.at("data")))',
            "smartwatch": 'smartwatch(json(sys.inputs.at("data")).smartwatch)',
            "qfn-pinout": 'qfn-pinout(s)',
            "qfn-top": 'qfn-pin-view(s,"top")',
            "qfn-bottom": 'qfn-pin-view(s,"bottom")',
            "qfn-side": 'qfn-side(s)',
            "qfn-mechanical": 'qfn-mechanical(s)',
            "qfn-copper": 'qfn-copper(s)',
            "qfn-mask": 'qfn-layer(s,"mask")',
            "qfn-paste": 'qfn-layer(s,"paste")',
            "qfn-vias": 'qfn-layer(s,"vias")',
            "qfn-carrier-tape": 'carrier-tape(s)',
            "qfn-reel": 'reel(s)',
            "qfn-reel-box": 'reel-box(s)',
            "qfn-reflow": 'reflow(s)',
        })
        if r1_product_line_height is not None:
            expressions["tiny-r1-product-line"] = f"r1-product-line({r1_product_line_height:.9f}pt)"
    text = '#import "/publications/specifications/figures.typ": *\n'
    if spec["product"] == "tiny":
        text += '#import "/publications/datasheets/tiny/address-map.typ": address-map\n'
        text += '#import "/publications/datasheets/tiny/feature-highlights.typ": feature-highlights, r1-product-line\n'
        text += '#import "/publications/datasheets/tiny/smartwatch.typ": smartwatch\n'
        text += '#import "/publications/datasheets/tiny/package-figures.typ": *\n'
        text += '#import "/publications/datasheets/tiny/assembly-references.typ": carrier-tape, reel, reel-box, reflow\n'
    text += ('#set page(width:auto,height:auto,margin:4mm)\n'
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
