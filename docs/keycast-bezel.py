#!/usr/bin/env python3
"""Render deterministic KeyCastr-style svelte bezel PNGs for the dock demo.

The demo navigates the dock with the arrow keys and jumps with Return, so the
bezels are the bare keys (no modifier is held — the ⇧⌃⌥⌘ strip stays dim). The
bezel component is shared verbatim with the rest of the operonlab tmux family
(tmux-workdesk, tmux-floatpane) so every family GIF shows keys the same way.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Final

from PIL import Image, ImageDraw, ImageFont


SCALE: Final = 4
BEZEL_HEIGHT: Final = 150
MAIN_HEIGHT: Final = 108
STRIP_HEIGHT: Final = BEZEL_HEIGHT - MAIN_HEIGHT
CORNER_RADIUS: Final = 27
MAIN_FONT_SIZE: Final = 76
STRIP_FONT_SIZE: Final = 27

SFNS_FONT: Final = Path("/System/Library/Fonts/SFNS.ttf")
APPLE_SYMBOLS_FONT: Final = Path("/System/Library/Fonts/Apple Symbols.ttf")
ASSET_DIR: Final = Path(__file__).resolve().parent / "assets"
PREVIEW_PATH: Final = Path("/tmp/bezel-preview.png")

MODIFIERS: Final = ("⇧", "⌃", "⌥", "⌘")
SYMBOLS: Final = frozenset(MODIFIERS)

BODY_COLOR: Final = (0x16, 0x16, 0x16, 235)
STRIP_COLOR: Final = (0x20, 0x20, 0x20, 235)
ACTIVE_COLOR: Final = (0x3D, 0x3D, 0x3D, 235)
DIVIDER_COLOR: Final = (0x3A, 0x3A, 0x3A, 235)
INACTIVE_GLYPH_COLOR: Final = (0x9A, 0x9A, 0x9A, 255)
ACTIVE_GLYPH_COLOR: Final = (255, 255, 255, 255)
MAIN_GLYPH_COLOR: Final = (255, 255, 255, 255)
PREVIEW_COLOR: Final = (0x1E, 0x1E, 0x1E, 255)


@dataclass(frozen=True)
class FontFace:
    font: ImageFont.FreeTypeFont
    stroke_width: int


@dataclass(frozen=True)
class Variant:
    filename: str
    text: str
    active_modifier: int | None


VARIANTS: Final = (
    Variant("bezel-down.png", "↓", None),
    Variant("bezel-up.png", "↑", None),
    Variant("bezel-return.png", "⏎", None),
)


def _clamp(value: int, minimum: int, maximum: int) -> int:
    return max(minimum, min(value, maximum))


def _load_font(path: Path, size: int, weight: int, *, bold_fallback: bool) -> FontFace:
    """Load a font at supersampled size and select its variable weight, if any."""
    font = ImageFont.truetype(str(path), size * SCALE)
    weight_applied = False

    try:
        axes = font.get_variation_axes()
        values: list[int] = []
        for axis in axes:
            name = axis["name"].decode("ascii", errors="ignore").lower()
            minimum = int(axis["minimum"])
            maximum = int(axis["maximum"])
            value = int(axis["default"])
            if name == "weight":
                value = _clamp(weight, minimum, maximum)
                weight_applied = True
            elif name == "optical size":
                value = _clamp(size, minimum, maximum)
            values.append(value)
        if values:
            font.set_variation_by_axes(values)
    except (AttributeError, OSError, TypeError, ValueError):
        weight_applied = False

    stroke_width = 2 * SCALE if bold_fallback and not weight_applied else 0
    return FontFace(font=font, stroke_width=stroke_width)


def _supports_modifier_glyphs(path: Path) -> bool:
    try:
        font = ImageFont.truetype(str(path), STRIP_FONT_SIZE * SCALE)
        return all(font.getmask(symbol).getbbox() is not None for symbol in MODIFIERS)
    except (OSError, TypeError, ValueError):
        return False


def _select_symbol_font() -> Path:
    if _supports_modifier_glyphs(SFNS_FONT):
        return SFNS_FONT
    if _supports_modifier_glyphs(APPLE_SYMBOLS_FONT):
        return APPLE_SYMBOLS_FONT
    raise RuntimeError(
        "Neither SFNS.ttf nor Apple Symbols.ttf can render modifier glyphs"
    )


def _font_for_character(
    character: str,
    text_face: FontFace,
    symbol_face: FontFace,
) -> FontFace:
    return symbol_face if character in SYMBOLS else text_face


def _mixed_text_metrics(
    text: str,
    text_face: FontFace,
    symbol_face: FontFace,
) -> tuple[float, int, int]:
    """Return advance width and vertical bounds relative to a shared baseline."""
    advance = 0.0
    top = 0
    bottom = 0
    found_ink = False
    for character in text:
        face = _font_for_character(character, text_face, symbol_face)
        bbox = face.font.getbbox(character, anchor="ls", stroke_width=face.stroke_width)
        advance += face.font.getlength(character)
        if character.isspace():
            continue
        top = min(top, bbox[1]) if found_ink else bbox[1]
        bottom = max(bottom, bbox[3]) if found_ink else bbox[3]
        found_ink = True
    if not found_ink:
        raise ValueError("Main text must contain a visible glyph")
    return advance, top, bottom


def _draw_mixed_text(
    draw: ImageDraw.ImageDraw,
    position: tuple[float, float],
    text: str,
    text_face: FontFace,
    symbol_face: FontFace,
    fill: int,
) -> None:
    x, baseline = position
    for character in text:
        face = _font_for_character(character, text_face, symbol_face)
        draw.text(
            (round(x), round(baseline)),
            character,
            font=face.font,
            fill=fill,
            anchor="ls",
            stroke_width=face.stroke_width,
            stroke_fill=fill,
        )
        x += face.font.getlength(character)


def _bezel_width(
    text: str,
    text_face: FontFace,
    symbol_face: FontFace,
    strip_face: FontFace,
) -> int:
    advance, top, bottom = _mixed_text_metrics(text, text_face, symbol_face)
    glyph_height = (bottom - top) / SCALE
    side_padding = glyph_height * 0.5
    content_width = advance / SCALE + side_padding * 2

    widest_modifier = (
        max(strip_face.font.getlength(symbol) for symbol in MODIFIERS) / SCALE
    )
    strip_minimum = 4 * (widest_modifier + 14)
    required_width = max(content_width, strip_minimum)
    return max(4, int((required_width + 3) // 4) * 4)


def render_bezel(
    variant: Variant,
    text_face: FontFace,
    symbol_face: FontFace,
    strip_face: FontFace,
) -> Image.Image:
    width = _bezel_width(variant.text, text_face, symbol_face, strip_face)
    scaled_width = width * SCALE
    scaled_height = BEZEL_HEIGHT * SCALE
    scaled_main_height = MAIN_HEIGHT * SCALE
    scaled_cell_width = scaled_width // 4

    body = Image.new("RGB", (scaled_width, scaled_height), BODY_COLOR[:3])
    draw = ImageDraw.Draw(body)

    draw.rectangle(
        (0, scaled_main_height, scaled_width - 1, scaled_height - 1),
        fill=STRIP_COLOR[:3],
    )

    if variant.active_modifier is not None:
        x0 = variant.active_modifier * scaled_cell_width
        x1 = x0 + scaled_cell_width - 1
        draw.rectangle(
            (x0, scaled_main_height, x1, scaled_height - 1),
            fill=ACTIVE_COLOR[:3],
        )

    alpha_mask = Image.new("L", body.size, 0)
    ImageDraw.Draw(alpha_mask).rounded_rectangle(
        (0, 0, scaled_width - 1, scaled_height - 1),
        radius=CORNER_RADIUS * SCALE,
        fill=BODY_COLOR[3],
    )

    final_size = (width, BEZEL_HEIGHT)
    image = body.resize(final_size, resample=Image.Resampling.LANCZOS).convert("RGBA")
    image.putalpha(alpha_mask.resize(final_size, resample=Image.Resampling.LANCZOS))

    # Draw the requested one-pixel dividers at final resolution so their width
    # and named color remain exact after the supersampled body is downscaled.
    draw = ImageDraw.Draw(image)
    cell_width = width // 4
    for index in range(1, 4):
        x = index * cell_width
        draw.line((x, MAIN_HEIGHT, x, BEZEL_HEIGHT - 1), fill=DIVIDER_COLOR, width=1)

    main_mask = Image.new("L", (scaled_width, scaled_height), 0)
    main_draw = ImageDraw.Draw(main_mask)
    advance, top, bottom = _mixed_text_metrics(variant.text, text_face, symbol_face)
    main_x = (scaled_width - advance) / 2
    baseline = (scaled_main_height - (bottom - top)) / 2 - top
    _draw_mixed_text(
        main_draw,
        (main_x, baseline),
        variant.text,
        text_face,
        symbol_face,
        255,
    )
    main_layer = Image.new("RGBA", final_size, MAIN_GLYPH_COLOR)
    main_layer.putalpha(main_mask.resize(final_size, resample=Image.Resampling.LANCZOS))
    image = Image.alpha_composite(image, main_layer)

    strip_center_y = scaled_main_height + (STRIP_HEIGHT * SCALE) / 2
    for index, symbol in enumerate(MODIFIERS):
        center_x = index * scaled_cell_width + scaled_cell_width / 2
        color = (
            ACTIVE_GLYPH_COLOR
            if variant.active_modifier == index
            else INACTIVE_GLYPH_COLOR
        )
        bbox = strip_face.font.getbbox(
            symbol,
            anchor="ls",
            stroke_width=strip_face.stroke_width,
        )
        symbol_width = strip_face.font.getlength(symbol)
        symbol_x = center_x - symbol_width / 2
        symbol_baseline = strip_center_y - (bbox[3] - bbox[1]) / 2 - bbox[1]
        symbol_mask = Image.new("L", (scaled_width, scaled_height), 0)
        ImageDraw.Draw(symbol_mask).text(
            (round(symbol_x), round(symbol_baseline)),
            symbol,
            font=strip_face.font,
            fill=255,
            anchor="ls",
            stroke_width=strip_face.stroke_width,
            stroke_fill=255,
        )
        symbol_layer = Image.new("RGBA", final_size, color)
        symbol_layer.putalpha(
            symbol_mask.resize(final_size, resample=Image.Resampling.LANCZOS)
        )
        image = Image.alpha_composite(image, symbol_layer)

    return image


def _save_png(image: Image.Image, path: Path) -> None:
    image.save(path, format="PNG", optimize=False, compress_level=3)


def render_all() -> tuple[Path, list[Path]]:
    symbol_font_path = _select_symbol_font()
    text_face = _load_font(SFNS_FONT, MAIN_FONT_SIZE, 700, bold_fallback=True)
    symbol_face = _load_font(symbol_font_path, MAIN_FONT_SIZE, 700, bold_fallback=True)
    strip_face = _load_font(symbol_font_path, STRIP_FONT_SIZE, 500, bold_fallback=False)

    ASSET_DIR.mkdir(parents=True, exist_ok=True)
    rendered: list[tuple[Path, Image.Image]] = []
    for variant in VARIANTS:
        image = render_bezel(variant, text_face, symbol_face, strip_face)
        output_path = ASSET_DIR / variant.filename
        _save_png(image, output_path)
        rendered.append((output_path, image))

    row_width = 800
    row_height = 220
    preview = Image.new("RGBA", (row_width, row_height * len(rendered)), PREVIEW_COLOR)
    for index, (_, bezel) in enumerate(rendered):
        x = (row_width - bezel.width) // 2
        y = index * row_height + (row_height - bezel.height) // 2
        preview.alpha_composite(bezel, dest=(x, y))
    _save_png(preview.convert("RGB"), PREVIEW_PATH)

    paths = [path for path, _ in rendered] + [PREVIEW_PATH]
    print(f"Symbol font: {symbol_font_path}")
    for path in paths:
        print(f"{path}: {path.stat().st_size} bytes")
    return symbol_font_path, paths


if __name__ == "__main__":
    render_all()
