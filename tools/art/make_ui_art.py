"""Pixel-art UI textures for the main menu, written to assets/ui/.

    python tools/art/make_ui_art.py

title.png       "PIXEL EMPIRE" logo, same recipe as the web page (tools/readme)
button_*.png    9-patch button skins: normal, hover, pressed, disabled
panel.png       9-patch frame: walnut fill, brass border, corner brackets
divider.png     gold rule with a diamond, drawn under the tagline
toggle_on/off   pixel switch for check buttons (full screen)
*_small         2x versions for the HUD: button_small_*, frame_small
check_on/off    check box, slider_grabber knob, inset (text fields, bars)
icon_chat       speech bubble for the touch-screen chat button
                (`--chat-only` writes just this one)

Every texture is painted at 1 px per "pixel" and upscaled with nearest
neighbour (SCALE), so the menu shares the chunky look of the sprites.
Needs Pillow (run without -I: it lives in the user site).
"""
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "readme"))
from make_readme_media import pixel_text, shadowed  # noqa: E402

OUT = ROOT / "assets" / "ui"
SCALE = 3

INK = (20, 14, 9, 255)
GOLD = (240, 201, 106, 255)
GOLD_MID = (201, 150, 64, 255)
GOLD_DARK = (122, 84, 34, 255)


def hexc(h, a=255):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) + (a,)


def up(img, scale=SCALE):
    return img.resize((img.width * scale, img.height * scale), Image.NEAREST)


def bayer(x, y):
    m = ((0, 8, 2, 10), (12, 4, 14, 6), (3, 11, 1, 9), (15, 7, 13, 5))
    return m[y % 4][x % 4] / 16.0


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(4))


def button(fill_top, fill_bottom, light, dark, rim, studs, pressed=False):
    """24x16 bevelled plank. `rim` is the 1 px line inside the outline."""
    w, h = 24, 16
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()
    for y in range(h):
        for x in range(w):
            if (x in (0, w - 1)) and (y in (0, h - 1)):
                continue  # rounded pixel corners
            if x in (0, w - 1) or y in (0, h - 1):
                px[x, y] = INK
                continue
            t = (y - 1) / (h - 3)
            c = lerp(fill_top, fill_bottom, t)
            # Faint wood grain, dithered.
            if (y * 7 + x // 6) % 5 == 0 and bayer(x, y) > 0.5:
                c = lerp(c, (0, 0, 0, 255), 0.12)
            px[x, y] = c
    top, bottom = (dark, light) if pressed else (light, dark)
    for x in range(1, w - 1):
        px[x, 1] = top
        px[x, h - 2] = bottom
        if not pressed:
            px[x, h - 3] = lerp(bottom, px[x, h - 3], 0.5)
    for y in range(2, h - 2):
        px[1, y] = top
        px[w - 2, y] = bottom
    if rim:
        for x in range(2, w - 2):
            px[x, 2 if not pressed else 3] = rim
        for y in range(3, h - 3):
            px[2, y] = rim
            px[w - 3, y] = rim
        for x in range(2, w - 2):
            px[x, h - 3] = rim
    if studs:
        for sx, sy in ((3, 3), (w - 4, 3), (3, h - 4), (w - 4, h - 4)):
            px[sx, sy + (1 if pressed else 0)] = studs
    return img


def panel():
    """32x32 frame: outline, brass border with highlight, walnut fill, corner brackets."""
    s = 32
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    px = img.load()
    fill_a = hexc("#1c1712", 238)
    fill_b = hexc("#14100c", 238)
    for y in range(s):
        for x in range(s):
            edge = min(x, y, s - 1 - x, s - 1 - y)
            if edge == 0:
                if not ((x in (0, s - 1)) and (y in (0, s - 1))):
                    px[x, y] = INK
            elif edge == 1:
                px[x, y] = GOLD_MID if (x < s // 2 and y < s // 2) or y == 1 or x == 1 else GOLD_DARK
            elif edge == 2:
                px[x, y] = hexc("#8a6d3b")
            elif edge == 3:
                px[x, y] = INK
            else:
                px[x, y] = fill_a if bayer(x, y) > (y / s) else fill_b
    # Corner brackets: an L of gold with a diamond rivet.
    for cx, cy, dx, dy in ((0, 0, 1, 1), (s - 1, 0, -1, 1), (0, s - 1, 1, -1), (s - 1, s - 1, -1, -1)):
        for i in range(4, 9):
            px[cx + dx * i, cy + dy * 4] = GOLD
            px[cx + dx * 4, cy + dy * i] = GOLD
        for i in range(5, 9):
            px[cx + dx * i, cy + dy * 5] = GOLD_DARK
            px[cx + dx * 5, cy + dy * i] = GOLD_DARK
        rx, ry = cx + dx * 7, cy + dy * 7
        for ox, oy in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)):
            px[rx + ox, ry + oy] = GOLD if (ox, oy) == (0, 0) else GOLD_MID
    return up(img)


def divider():
    """96x7 gold rule tapering to the ends with a diamond in the middle."""
    w, h = 96, 7
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()
    mid = w // 2
    for x in range(w):
        d = abs(x - mid) / mid
        if d > 0.97:
            continue
        a = int(255 * (1.0 - d ** 2))
        px[x, 3] = GOLD[:3] + (a,)
        if bayer(x, 0) > d:
            px[x, 4] = GOLD_DARK[:3] + (a,)
    for y in range(h):
        r = 3 - abs(y - 3)
        for x in range(mid - r - 1, mid + r + 2):
            inner = abs(x - mid) <= r - 1
            px[x, y] = GOLD if inner else INK
    for x, y in ((mid - 9, 3), (mid + 9, 3)):
        px[x, y] = GOLD
        px[x, y - 1] = GOLD_MID
        px[x, y + 1] = GOLD_MID
    return up(img)


def toggle(on):
    """16x9 switch: a rounded track with a knob, gold when on."""
    w, h = 16, 9
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()
    track = hexc("#6a8f3a") if on else hexc("#2a231b")
    for y in range(h):
        for x in range(w):
            if (x in (0, w - 1)) and (y in (0, h - 1)):
                continue
            edge = x in (0, w - 1) or y in (0, h - 1)
            px[x, y] = INK if edge else (lerp(track, (0, 0, 0, 255), 0.25) if y >= h - 3 else track)
    kx = w - 7 if on else 1
    for y in range(1, h - 1):
        for x in range(kx, kx + 6):
            edge = x in (kx, kx + 5) or y in (1, h - 2)
            px[x, y] = INK if edge else (GOLD if on else hexc("#b5a88e"))
    px[kx + 1, 2] = (255, 246, 200, 255) if on else hexc("#e8dcc4")
    return up(img)


def frame_small():
    """12x12 thin frame (HUD bars, tooltips, popups): outline, brass, dark line, walnut."""
    s = 12
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    px = img.load()
    for y in range(s):
        for x in range(s):
            edge = min(x, y, s - 1 - x, s - 1 - y)
            if edge == 0:
                if not ((x in (0, s - 1)) and (y in (0, s - 1))):
                    px[x, y] = INK
            elif edge == 1:
                px[x, y] = GOLD_MID if (y == 1 or x == 1) else GOLD_DARK
            elif edge == 2:
                px[x, y] = INK
            else:
                px[x, y] = hexc("#1c1712", 240) if bayer(x, y) > 0.5 else hexc("#18130f", 240)
    for cx, cy in ((1, 1), (s - 2, 1), (1, s - 2), (s - 2, s - 2)):
        px[cx, cy] = GOLD
    return img


def inset():
    """8x8 sunken well: dark fill, shadowed top/left, brass bottom/right lip."""
    s = 8
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    px = img.load()
    for y in range(s):
        for x in range(s):
            if x in (0, s - 1) or y in (0, s - 1):
                px[x, y] = GOLD_MID if (x == s - 1 or y == s - 1) else hexc("#8a6d3b")
            elif x == 1 or y == 1:
                px[x, y] = hexc("#0a0705")
            else:
                px[x, y] = hexc("#15110d")
    return img


def check(on):
    """9x9 check box with a gold tick."""
    s = 9
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    px = img.load()
    for y in range(s):
        for x in range(s):
            edge = x in (0, s - 1) or y in (0, s - 1)
            px[x, y] = INK if edge else (hexc("#2a231b") if y > 1 else hexc("#120d08"))
    if on:
        for x, y in ((2, 4), (3, 5), (4, 6), (5, 5), (6, 4), (6, 3), (7, 2), (3, 4), (4, 5), (5, 4)):
            px[x, y] = GOLD
        px[4, 6] = GOLD_MID
    return img


def grabber():
    """7x11 slider knob: brass with a highlight."""
    w, h = 7, 11
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()
    for y in range(h):
        for x in range(w):
            if (x in (0, w - 1)) and (y in (0, h - 1)):
                continue
            if x in (0, w - 1) or y in (0, h - 1):
                px[x, y] = INK
            else:
                px[x, y] = GOLD if x <= 2 and y <= 4 else (GOLD_MID if y < h - 3 else GOLD_DARK)
    for y in (4, 6):
        for x in range(2, w - 2):
            px[x, y] = GOLD_DARK
    return img


def chat_icon():
    """15x13 speech bubble: parchment with an ink outline, three gold dots, tail."""
    rows = [
        "..###########..",
        ".#ppppppppppp#.",
        "#ppppppppppppp#",
        "#ppppppppppppps",
        "#ppGGppGGppGGps",
        "#ppGGppGGppGGps",
        "#ppppppppppppps",
        "#pppppppppppsps",
        ".#ppsssssssss#.",
        "..#p##########.",
        "..#p#..........",
        "..##...........",
        "...............",
    ]
    colours = {"#": INK, "p": hexc("#f1e6cf"), "s": hexc("#b5a88e"), "G": GOLD_MID}
    img = Image.new("RGBA", (len(rows[0]), len(rows)), (0, 0, 0, 0))
    px = img.load()
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch in colours:
                px[x, y] = colours[ch]
    return img


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    up(chat_icon(), 2).save(OUT / "icon_chat.png")
    if "--chat-only" in sys.argv:
        return
    title = shadowed(pixel_text("PIXEL EMPIRE", 6, (255, 232, 140), (214, 140, 40), 1), 8, 3)
    title.save(OUT / "title.png", optimize=True)
    walnut_top, walnut_bottom = hexc("#4a3c2c"), hexc("#30271d")
    skins = {
        "normal": button(walnut_top, walnut_bottom, hexc("#7a6346"), hexc("#1d150e"), None, GOLD_DARK),
        "hover": button(hexc("#5c4a34"), hexc("#3a2f22"), hexc("#9a7d55"), hexc("#1d150e"), GOLD_MID, GOLD),
        "pressed": button(hexc("#2a2219"), hexc("#3a2f22"), hexc("#7a6346"), hexc("#120d08"), GOLD, GOLD, pressed=True),
        "disabled": button(hexc("#34302b"), hexc("#26231f"), hexc("#4a453e"), hexc("#16130f"), None, hexc("#4a453e")),
    }
    for name, img in skins.items():
        up(img).save(OUT / f"button_{name}.png")
        up(img, 2).save(OUT / f"button_small_{name}.png")
    up(frame_small(), 2).save(OUT / "frame_small.png")
    up(inset(), 2).save(OUT / "inset.png")
    up(check(True), 2).save(OUT / "check_on.png")
    up(check(False), 2).save(OUT / "check_off.png")
    up(grabber(), 2).save(OUT / "slider_grabber.png")
    panel().save(OUT / "panel.png")
    divider().save(OUT / "divider.png")
    toggle(True).save(OUT / "toggle_on.png")
    toggle(False).save(OUT / "toggle_off.png")
    print("wrote", sorted(p.name for p in OUT.glob("*.png")))


if __name__ == "__main__":
    main()
