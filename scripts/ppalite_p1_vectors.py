#!/usr/bin/env python3
"""Emit deterministic independent scalar streams for standalone RTL differential tests."""
from __future__ import annotations

import argparse
from pathlib import Path

from ppalite_model import Config, input_words, layout, output_words


def sensor(config: Config, seed: int) -> bytes:
    return bytes((index * 73 + seed * 29 + 11) & 0xFF
                 for index in range(config.width * config.height * 2))


def cases() -> list[tuple[Config, int, int]]:
    result = []
    for fmt in range(6):
        for gray8 in ((False, True) if fmt >= 2 else (False,)):
            for width, height, step_x, step_y, phase_x, phase_y in (
                    (1, 1, 1, 1, 0, 0), (3, 2, 1, 1, 0, 0),
                    (5, 5, 2, 4, 1, 3), (7, 4, 4, 2, 3, 1)):
                config = Config(width, height, input_format=fmt, gray8=gray8,
                                step_x=step_x, step_y=step_y, phase_x=phase_x, phase_y=phase_y)
                result.append((config, len(result) + 1, 0xA55A))
    for rgb_swap in (False, True):
        for byte_swap in (False, True):
            for fmt in (0, 1):
                result.append((Config(5, 3, input_format=fmt, rgb_swap=rgb_swap,
                                      output_byte_swap=byte_swap), len(result) + 1, 0x5AA5))
    for step_x in (1, 2, 4):
        for step_y in (1, 2, 4):
            for phase_x in range(step_x):
                for phase_y in range(step_y):
                    result.append((Config(9, 9, input_format=2, gray8=True, step_x=step_x,
                                          step_y=step_y, phase_x=phase_x, phase_y=phase_y),
                                   len(result) + 1, 0xBEEF))
    return result


def emit(directory: Path) -> None:
    directory.mkdir(parents=True, exist_ok=False)
    case_list = cases()
    values = [len(case_list)]
    metadata = []
    for index, (config, seed, tail) in enumerate(case_list):
        shape = layout(config)
        pixels = sensor(config, seed)
        inputs = input_words(config, pixels, ignored_tail=tail)
        outputs = output_words(config, pixels)
        base = len(values)
        header = [config.register_config, (config.height << 16) | config.width, config.sampling,
                  (shape["output_height"] << 16) | shape["output_width"], shape["row_bytes"],
                  shape["stride_bytes"], shape["valid_bytes"], shape["transport_bytes"],
                  shape["expected_words"], len(inputs), len(outputs), seed]
        values.extend(header)
        for word in inputs:
            values.extend((word["data"], word["keep"], word["strb"], word["sof"], word["last"]))
        for word in outputs:
            values.extend((word["data"], word["keep"], word["strb"], word["sof"], word["last"]))
        metadata.append({"index": index, "base": base, "words": len(header) + 5 * (len(inputs) + len(outputs)),
                         "config": header[:9], "input_count": len(inputs), "output_count": len(outputs)})
    (directory / "vectors.hex").write_text("".join(f"{value:08x}\n" for value in values))
    import json
    (directory / "vectors.json").write_text(json.dumps({"count": len(metadata), "cases": metadata},
                                                       indent=2) + "\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    args = parser.parse_args()
    emit(args.directory)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
