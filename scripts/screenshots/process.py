#!/usr/bin/env python3
"""Turns raw `screencapture` output from the harness into the site's WebP assets.

Usage: process.py <rawDir> <site/assets dir>

Everything here is derived from the real captures (and assets/AppIcon.png) — the only
additions are a brand-gradient backdrop and a menu-bar strip behind the composed hero.
"""
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

raw = Path(sys.argv[1])
assets = Path(sys.argv[2])
shots = assets / "screenshots"
shots.mkdir(parents=True, exist_ok=True)
root = Path(__file__).resolve().parents[2]

BLUE = (51, 81, 252)
VIOLET = (121, 69, 255)
MAGENTA = (173, 39, 243)


def save_webp(img: Image.Image, name: str, quality: int = 90) -> None:
    path = shots / f"{name}.webp"
    img.save(path, "WEBP", quality=quality, method=6)
    size = path.stat().st_size
    assert size < 300_000, f"{path} is {size} bytes"
    print(f"   {path.relative_to(assets.parent)}  {img.width}x{img.height}  {size // 1024} KB")


def gradient(w: int, h: int) -> Image.Image:
    """Diagonal blue → violet → magenta, matching the app icon."""
    base = Image.new("RGB", (w, h))
    px = base.load()
    for y in range(h):
        for x in range(w):
            t = (x / w) * 0.7 + (y / h) * 0.3
            a, b, k = (BLUE, VIOLET, t / 0.5) if t < 0.5 else (VIOLET, MAGENTA, (t - 0.5) / 0.5)
            px[x, y] = tuple(int(a[i] + (b[i] - a[i]) * k) for i in range(3))
    return base


def edge_color(bar: Image.Image) -> tuple:
    """Average colour of the capture's outer columns — the real menu-bar background."""
    rgb = bar.convert("RGB")
    cols = [rgb.getpixel((x, y)) for x in (0, 1, rgb.width - 2, rgb.width - 1) for y in range(rgb.height)]
    return tuple(sum(c[i] for c in cols) // len(cols) for i in range(3))


def hero(theme: str, scene: str = "menu") -> Image.Image:
    meta = json.loads((raw / f"{scene}-meta-{theme}.json").read_text())
    bar = Image.open(raw / f"{scene}-bar-open.png").convert("RGBA")
    menu = Image.open(raw / f"{scene}-menu-{theme}.png").convert("RGBA")
    item, m = meta["item"], meta["menu"]
    # Captures are in device pixels; bring Retina (2x) captures back to points so the
    # geometry from the harness lines up regardless of which display was active.
    scale = round(bar.height / item["h"]) or 1
    if scale > 1:
        bar = bar.resize((bar.width // scale, bar.height // scale), Image.LANCZOS)
        menu = menu.resize((menu.width // scale, menu.height // scale), Image.LANCZOS)

    # Window captures include the drop shadow; recover its margin from the known bounds.
    shadow_x = (menu.width - m["w"]) / 2
    margin = 90
    bar_h = bar.height
    width = int(bar.width + 2 * margin + 160)
    bar_left = margin + 140
    menu_left = int(bar_left + (m["x"] - (item["x"] - item["pad"])) - shadow_x)
    menu_top = int(bar_h + (m["y"] - (item["y"] + item["h"])) - shadow_x * 0.6)
    height = menu_top + menu.height + 40

    canvas = gradient(width, height).convert("RGBA")
    strip = Image.new("RGBA", (width, bar_h), edge_color(bar) + (255,))
    canvas.alpha_composite(strip, (0, 0))
    canvas.alpha_composite(bar, (bar_left, 0))
    canvas.alpha_composite(menu, (menu_left, max(menu_top, bar_h - 4)))
    return canvas.convert("RGB")


def icon_rounded(size: int) -> Image.Image:
    """AppIcon.png has an opaque black matte; cut the rounded tile out of it."""
    src = Image.open(root / "assets" / "AppIcon.png").convert("RGBA")
    tile = src.crop((100, 100, 924, 924))
    mask = Image.new("L", tile.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, tile.width - 1, tile.height - 1), radius=190, fill=255)
    tile.putalpha(mask)
    return tile.resize((size, size), Image.LANCZOS)


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    for candidate in ("/System/Library/Fonts/SFNS.ttf", "/System/Library/Fonts/Helvetica.ttc"):
        try:
            f = ImageFont.truetype(candidate, size)
            if bold:
                try:
                    f.set_variation_by_name("Bold")
                except Exception:
                    pass
            return f
        except OSError:
            continue
    return ImageFont.load_default()


def og_image(hero_img: Image.Image, subtitle: str, name: str) -> None:
    w, h = 1200, 630
    canvas = gradient(w, h).convert("RGBA")
    shot = hero_img.copy()
    shot.thumbnail((560, 560), Image.LANCZOS)
    # soft shadow behind the screenshot card
    shadow = Image.new("RGBA", (shot.width + 60, shot.height + 60), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((30, 30, shot.width + 30, shot.height + 30), 18, fill=(0, 0, 0, 110))
    shadow = shadow.filter(ImageFilter.GaussianBlur(18))
    x, y = w - shot.width - 60, (h - shot.height) // 2
    canvas.alpha_composite(shadow, (x - 30, y - 20))
    mask = Image.new("L", shot.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, shot.width - 1, shot.height - 1), 14, fill=255)
    card = shot.convert("RGBA")
    card.putalpha(mask)
    canvas.alpha_composite(card, (x, y))

    canvas.alpha_composite(icon_rounded(128), (64, 110))
    d = ImageDraw.Draw(canvas)
    d.text((64, 272), "MR Jira Menu Bar", font=font(56, bold=True), fill="white")
    y_text = 350
    for line in subtitle.split("\n"):
        d.text((64, y_text), line, font=font(30), fill=(235, 232, 255))
        y_text += 42
    d.text((64, 540), "macOS 13+  ·  GitLab  ·  GitHub  ·  Jira", font=font(24), fill=(220, 215, 255))
    out = assets / name
    canvas.convert("RGB").save(out, "PNG", optimize=True)
    print(f"   {out.relative_to(assets.parent)}  {out.stat().st_size // 1024} KB")


print("==> Screenshots")
for scene in ("menu", "menu-update", "menu-error", "needs-config"):
    save_webp(Image.open(raw / f"{scene}-menu-dark.png").convert("RGBA"), scene)
save_webp(hero("dark"), "hero")
for theme in ("dark", "light"):
    save_webp(Image.open(raw / f"settings-{theme}.png").convert("RGBA"), f"settings-{theme}")

# The menu bar strip follows the system appearance, so it is captured once.
for scene, name in (("menu", "menubar"), ("menu-compact", "menubar-compact"), ("menu-error", "menubar-error")):
    save_webp(Image.open(raw / f"{scene}-bar.png").convert("RGB"), name, quality=95)

print("==> Icons and Open Graph images")
icon_rounded(180).save(assets / "apple-touch-icon.png", optimize=True)
icon_rounded(64).save(assets / "favicon.png", optimize=True)
hero_dark = hero("dark")
og_image(hero_dark, "Twoje MR-y, PR-y i zadania z Jiry\nna pasku menu macOS.", "og-pl.png")
og_image(hero_dark, "Your MRs, PRs and Jira issues,\nright in the macOS menu bar.", "og-en.png")
