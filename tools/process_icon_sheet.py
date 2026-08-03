"""Convert a 4x2 generated contact sheet into eight game-ready 32px icons."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image


DEFAULT_NAMES = (
    "nav_base",
    "nav_crew",
    "nav_raids",
    "nav_map",
    "nav_bank",
    "nav_market",
    "nav_orders",
    "nav_hire",
)
PALETTE = tuple(
    tuple(bytes.fromhex(value))
    for value in (
        "080B0C",
        "1B2322",
        "43504C",
        "A4B0A8",
        "E4EBE5",
        "36C7C9",
        "D9A441",
        "4FC47A",
        "D7564E",
    )
)


def nearest_palette(rgb: tuple[int, int, int]) -> tuple[int, int, int]:
    return min(PALETTE, key=lambda color: sum((a - b) ** 2 for a, b in zip(rgb, color)))


def extract_icon(cell: Image.Image) -> Image.Image:
    binary_alpha = cell.getchannel("A").point(lambda value: 255 if value >= 96 else 0)
    bounds = binary_alpha.getbbox()
    if bounds is None:
        raise ValueError("Contact-sheet cell contains no opaque icon pixels")

    glyph = cell.crop(bounds)
    target_extent = 24
    ratio = min(target_extent / glyph.width, target_extent / glyph.height)
    target_size = (max(1, round(glyph.width * ratio)), max(1, round(glyph.height * ratio)))
    glyph = glyph.resize(target_size, Image.Resampling.NEAREST)

    pixels = []
    for red, green, blue, alpha_value in glyph.get_flattened_data():
        if alpha_value < 96:
            pixels.append((0, 0, 0, 0))
        else:
            pixels.append((*nearest_palette((red, green, blue)), 255))
    glyph.putdata(pixels)

    icon = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    icon.alpha_composite(glyph, ((32 - glyph.width) // 2, (32 - glyph.height) // 2))
    return icon


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--names", nargs=8, default=DEFAULT_NAMES, metavar="NAME")
    args = parser.parse_args()

    source = Image.open(args.input).convert("RGBA")
    args.output.mkdir(parents=True, exist_ok=True)
    for index, name in enumerate(args.names):
        column = index % 4
        row = index // 4
        bounds = (
            round(column * source.width / 4),
            round(row * source.height / 2),
            round((column + 1) * source.width / 4),
            round((row + 1) * source.height / 2),
        )
        extract_icon(source.crop(bounds)).save(args.output / f"{name}.png", optimize=True)


if __name__ == "__main__":
    main()
