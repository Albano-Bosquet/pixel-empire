"""Builds the README images in docs/media/ from a showcase capture.

Capture first (opens a game window, ~1 minute):
    set SHOWCASE_OUT=<folder>
    tools/godot/Godot_v4.7.2-stable_win64_console.exe --path . -- --smoke=showcase --mode=skirmish --seed=4242 --nofog
Then:
    python tools/readme/make_readme_media.py <folder>

Writes banner.jpg, hero.jpg + title.png (site/), download.png, day_night.jpg, the GIFs and the new stills.
Needs Pillow. Fonts come from C:/Windows/Fonts (Consolas Bold, Segoe UI).
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs" / "media"
FONTS = Path("C:/Windows/Fonts")
GOLD = (240, 200, 96)
GOLD_DARK = (150, 100, 30)
INK = (20, 16, 12)


def pixel_text(text, cell, colour_top, colour_bottom, outline=1):
    """Text drawn aliased at a tiny size, gradient filled, outlined, then
    upscaled by `cell` with nearest neighbour so it reads as pixel art."""
    font = ImageFont.truetype(str(FONTS / "consolab.ttf"), 22)
    probe = ImageDraw.Draw(Image.new("L", (1, 1)))
    l, t, r, b = probe.textbbox((0, 0), text, font=font)
    w, h = r - l + 4 * outline + 2, b - t + 4 * outline + 2
    mask = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(mask)
    d.fontmode = "1"
    d.text((2 * outline - l, 2 * outline - t), text, font=font, fill=255)
    grad = Image.new("RGBA", (w, h))
    for y in range(h):
        f = y / max(1, h - 1)
        c = tuple(int(colour_top[i] + (colour_bottom[i] - colour_top[i]) * f) for i in range(3))
        ImageDraw.Draw(grad).line([(0, y), (w, y)], fill=c + (255,))
    fill = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    fill.paste(grad, (0, 0), mask)
    border = mask.filter(ImageFilter.MaxFilter(2 * outline + 1))
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    out.paste(Image.new("RGBA", (w, h), INK + (255,)), (0, 0), border)
    out.alpha_composite(fill)
    return out.resize((w * cell, h * cell), Image.NEAREST)


def shadowed(layer, offset, blur=0):
    shadow = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    shadow.paste(Image.new("RGBA", layer.size, (0, 0, 0, 170)), (0, 0), layer.split()[3])
    if blur:
        shadow = shadow.filter(ImageFilter.GaussianBlur(blur))
    canvas = Image.new("RGBA", (layer.width + offset, layer.height + offset), (0, 0, 0, 0))
    canvas.alpha_composite(shadow, (offset, offset))
    canvas.alpha_composite(layer, (0, 0))
    return canvas


def banner(src):
    """1600x560 hero: the city at sunset, a dark vignette and the pixel title."""
    city = Image.open(src / "city_sunset.png").convert("RGBA")
    w, h = 1600, 560
    scale = w / city.width
    city = city.resize((w, int(city.height * scale)), Image.LANCZOS)
    top = (city.height - h) // 2 - 20
    img = city.crop((0, top, w, top + h))
    shade = Image.new("L", (w, h), 0)
    sd = ImageDraw.Draw(shade)
    for y in range(h):
        f = abs(y - h * 0.42) / (h * 0.6)
        sd.line([(0, y), (w, y)], fill=int(150 - 110 * min(1.0, f)))
    for y in range(h):
        f = y / h
        if f > 0.7:
            sd.line([(0, y), (w, y)], fill=int(40 + 180 * (f - 0.7) / 0.3))
    img.alpha_composite(_with_alpha((14, 10, 24), shade))
    title = shadowed(pixel_text("PIXEL EMPIRE", 7, (255, 232, 140), (214, 140, 40), 1), 10, 4)
    img.alpha_composite(title, ((w - title.width) // 2, 120))
    font = ImageFont.truetype(str(FONTS / "seguisb.ttf"), 34)
    tag = "Recolecta  ·  Construye  ·  Avanza  ·  Conquista"
    d = ImageDraw.Draw(img)
    tw = d.textlength(tag, font=font)
    x, y = (w - tw) / 2, 120 + title.height + 18
    d.text((x + 2, y + 3), tag, font=font, fill=(0, 0, 0, 200))
    d.text((x, y), tag, font=font, fill=(250, 240, 220, 255))
    small = ImageFont.truetype(str(FONTS / "segoeui.ttf"), 24)
    sub = "Estrategia en tiempo real en pixel art HD  ·  7 edades  ·  50 unidades  ·  hasta 8 jugadores"
    sw = d.textlength(sub, font=small)
    d.text(((w - sw) / 2 + 2, y + 62), sub, font=small, fill=(0, 0, 0, 200))
    d.text(((w - sw) / 2, y + 60), sub, font=small, fill=(236, 214, 170, 255))
    img.convert("RGB").save(OUT / "banner.jpg", quality=92, optimize=True)


def site_hero(src):
    """Text-free hero background and the transparent pixel title for site/."""
    city = Image.open(src / "city_sunset.png").convert("RGB").resize((1920, 1080), Image.LANCZOS)
    city.save(OUT / "hero.jpg", quality=88, optimize=True)
    shadowed(pixel_text("PIXEL EMPIRE", 6, (255, 232, 140), (214, 140, 40), 1), 8, 3).save(OUT / "title.png", optimize=True)


def _with_alpha(rgb, mask):
    layer = Image.new("RGBA", mask.size, rgb + (255,))
    layer.putalpha(mask)
    return layer


def download_button():
    """A chunky pixel-art gold button."""
    label = pixel_text("DESCARGAR PARA WINDOWS", 3, (60, 36, 10), (30, 18, 4), 0)
    pad_x, pad_y, cell = 30, 18, 3
    w, h = label.width + 2 * pad_x + 70, label.height + 2 * pad_y
    w -= w % cell
    h -= h % cell
    img = Image.new("RGBA", (w, h + 2 * cell), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rectangle([cell, 2 * cell, w - 1, h + 2 * cell - 1], fill=(90, 56, 14, 255))
    d.rectangle([0, 0, w - cell - 1, h - 1], fill=INK + (255,))
    d.rectangle([cell, cell, w - 2 * cell - 1, h - 2 * cell - 1], fill=GOLD + (255,))
    d.rectangle([cell, h // 2, w - 2 * cell - 1, h - 2 * cell - 1], fill=(222, 170, 64, 255))
    d.rectangle([2 * cell, cell, w - 3 * cell - 1, 2 * cell - 1], fill=(255, 238, 170, 255))
    # Download arrow, drawn on a 3px grid.
    arrow = ["...##...", "...##...", "...##...", "########", ".######.", "..####..", "...##...", "........",
             "########"]
    ac = 5
    ax, ay = pad_x - 4, (h - len(arrow) * ac) // 2 - cell // 2
    for r, row in enumerate(arrow):
        for c, ch in enumerate(row):
            if ch == "#":
                d.rectangle([ax + c * ac, ay + r * ac, ax + c * ac + ac - 1, ay + r * ac + ac - 1], fill=(60, 36, 10, 255))
    img.alpha_composite(label, (pad_x + 54, (h - label.height) // 2 - cell // 2))
    img.save(OUT / "download.png", optimize=True)


def day_night(src):
    """Day, sunset and night side by side with soft diagonal seams."""
    names = ["city_day", "city_sunset", "city_night"]
    ims = [Image.open(src / f"{n}.png").convert("RGB").resize((1600, 900), Image.LANCZOS) for n in names]
    out = ims[0].copy()
    w, h = out.size
    for k, im in enumerate(ims[1:], start=1):
        mask = Image.new("L", (w, h), 0)
        md = ImageDraw.Draw(mask)
        x0 = w * k / 3
        md.polygon([(x0 + 90, 0), (w, 0), (w, h), (x0 - 90, h)], fill=255)
        out.paste(im, (0, 0), mask.filter(ImageFilter.GaussianBlur(2)))
    d = ImageDraw.Draw(out)
    font = ImageFont.truetype(str(FONTS / "seguisb.ttf"), 30)
    for k, text in enumerate(["Día", "Atardecer", "Noche"]):
        tw = d.textlength(text, font=font)
        x = w * (k + 0.5) / 3 - tw / 2
        d.rounded_rectangle([x - 16, h - 70, x + tw + 16, h - 22], 10, fill=(14, 10, 8))
        d.text((x, h - 66), text, font=font, fill=GOLD)
    out = out.resize((1200, 675), Image.LANCZOS)
    out.save(OUT / "day_night.jpg", quality=90, optimize=True)


def gif(src, name, width=720, ms=50):
    frames = sorted((src / name).glob("*.png"))
    ims = []
    for f in frames:
        im = Image.open(f).convert("RGB")
        im = im.resize((width, int(im.height * width / im.width)), Image.LANCZOS)
        ims.append(im)
    # One shared palette from a few frames keeps the GIF small and flicker free.
    sample = Image.new("RGB", (width, ims[0].height * 3))
    for i, k in enumerate([0, len(ims) // 2, len(ims) - 1]):
        sample.paste(ims[k], (0, i * ims[0].height))
    pal = sample.quantize(colors=255, method=Image.Quantize.MEDIANCUT)
    q = [im.quantize(palette=pal, dither=Image.Dither.NONE) for im in ims]
    q[0].save(OUT / f"{name}.gif", save_all=True, append_images=q[1:], duration=ms, loop=0, optimize=True)


def still(src, name, out_name, width=1600):
    im = Image.open(src / f"{name}.png").convert("RGB")
    im = im.resize((width, int(im.height * width / im.width)), Image.LANCZOS)
    im.save(OUT / f"{out_name}.jpg", quality=90, optimize=True)


def main():
    src = Path(sys.argv[1])
    OUT.mkdir(parents=True, exist_ok=True)
    banner(src)
    site_hero(src)
    download_button()
    day_night(src)
    for name, ms in [("battle", 50), ("city_life", 70), ("modern", 50)]:
        gif(src, name, ms=ms)
    still(src, "battle_charge", "batalla")
    still(src, "city_day", "ciudad")
    still(src, "modern", "guerra_moderna")
    # Web gallery (site/index.html).
    for name, out_name in [("city_day_hud", "ciudad_hud"), ("city_night", "noche"), ("city_sunset", "atardecer"),
                           ("battle_late", "batalla_final"), ("modern_early", "avance_moderno"),
                           ("gallery_wonder", "maravilla"), ("gallery_naval", "naval"),
                           ("gallery_industrial", "industrial"), ("gallery_techs", "tecnologias"),
                           ("gallery_victory", "victoria")]:
        still(src, name, out_name)
    for f in sorted(OUT.iterdir()):
        print(f"{f.name}: {f.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
