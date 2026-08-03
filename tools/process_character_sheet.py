"""Normalize a generated 12x3 character contact sheet into 48px animation frames."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image


PALETTE = tuple(
    tuple(bytes.fromhex(value))
    for value in (
        "080B0C", "111616", "1B2322", "283331", "43504C", "707D76",
        "A4B0A8", "E4EBE5", "214E50", "36C7C9", "6B4D24", "D9A441",
        "7A4B34", "C7956E", "7D302D", "D7564E",
    )
)


def nearest_palette(rgb: tuple[int, int, int]) -> tuple[int, int, int]:
    return min(PALETTE, key=lambda color: sum((a - b) ** 2 for a, b in zip(rgb, color)))


def normalize_frame(cell: Image.Image, column: int) -> Image.Image:
    binary_alpha = cell.getchannel("A").point(lambda value: 255 if value >= 96 else 0)
    bounds = binary_alpha.getbbox()
    if bounds is None:
        raise ValueError("Character sheet cell contains no opaque pixels")
    glyph = cell.crop(bounds)

    maximum = (44, 36) if column == 11 else (38, 40)
    ratio = min(maximum[0] / glyph.width, maximum[1] / glyph.height)
    size = (max(1, round(glyph.width * ratio)), max(1, round(glyph.height * ratio)))
    glyph = glyph.resize(size, Image.Resampling.NEAREST)

    pixels = []
    for red, green, blue, alpha_value in glyph.get_flattened_data():
        if alpha_value < 96:
            pixels.append((0, 0, 0, 0))
        else:
            pixels.append((*nearest_palette((red, green, blue)), 255))
    glyph.putdata(pixels)

    frame = Image.new("RGBA", (48, 48), (0, 0, 0, 0))
    x = (48 - glyph.width) // 2
    y = (48 - glyph.height) // 2 if column == 11 else 40 - glyph.height
    frame.alpha_composite(glyph, (x, y))
    return frame


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    source = Image.open(args.input).convert("RGBA")
    sheet = Image.new("RGBA", (576, 144), (0, 0, 0, 0))
    for row in range(3):
        for column in range(12):
            bounds = (
                round(column * source.width / 12),
                round(row * source.height / 3),
                round((column + 1) * source.width / 12),
                round((row + 1) * source.height / 3),
            )
            frame = normalize_frame(source.crop(bounds), column)
            sheet.alpha_composite(frame, (column * 48, row * 48))

    args.output.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(args.output, optimize=True)


if __name__ == "__main__":
    main()
