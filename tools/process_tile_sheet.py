"""Extract, palette-normalize, and make seamless 32px tiles from a 4x2 sheet."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image


NAMES = ("asphalt", "concrete", "dirt", "grass", "wood", "carpet", "ceramic", "brick")
PALETTE = tuple(
    tuple(bytes.fromhex(value))
    for value in (
        "080B0C", "111616", "1B2322", "283331", "43504C", "707D76",
        "A4B0A8", "E4EBE5", "214E50", "36C7C9", "6B4D24", "D9A441",
        "285B3A", "4FC47A", "7D302D", "D7564E",
    )
)


def nearest_palette(rgb: tuple[int, int, int]) -> tuple[int, int, int]:
    return min(PALETTE, key=lambda color: sum((a - b) ** 2 for a, b in zip(rgb, color)))


def seamless_tile(cell: Image.Image) -> Image.Image:
    inset_x = max(1, round(cell.width * 0.08))
    inset_y = max(1, round(cell.height * 0.08))
    sample = cell.crop((inset_x, inset_y, cell.width - inset_x, cell.height - inset_y))
    sample = sample.resize((16, 16), Image.Resampling.NEAREST).convert("RGB")
    sample.putdata([nearest_palette(pixel) for pixel in sample.get_flattened_data()])

    tile = Image.new("RGB", (32, 32))
    tile.paste(sample, (0, 0))
    tile.paste(sample.transpose(Image.Transpose.FLIP_LEFT_RIGHT), (16, 0))
    tile.paste(sample.transpose(Image.Transpose.FLIP_TOP_BOTTOM), (0, 16))
    tile.paste(sample.transpose(Image.Transpose.FLIP_LEFT_RIGHT).transpose(Image.Transpose.FLIP_TOP_BOTTOM), (16, 16))
    return tile


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("seam_tests", type=Path)
    args = parser.parse_args()

    source = Image.open(args.input).convert("RGB")
    args.output.mkdir(parents=True, exist_ok=True)
    args.seam_tests.mkdir(parents=True, exist_ok=True)

    for index, name in enumerate(NAMES):
        column = index % 4
        row = index // 4
        bounds = (
            round(column * source.width / 4),
            round(row * source.height / 2),
            round((column + 1) * source.width / 4),
            round((row + 1) * source.height / 2),
        )
        tile = seamless_tile(source.crop(bounds))
        tile.save(args.output / f"tile_{name}.png", optimize=True)

        seam_test = Image.new("RGB", (96, 96))
        for y in range(3):
            for x in range(3):
                seam_test.paste(tile, (x * 32, y * 32))
        seam_test.save(args.seam_tests / f"tile_{name}_3x3.png", optimize=True)


if __name__ == "__main__":
    main()
