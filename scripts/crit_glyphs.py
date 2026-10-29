"""Draw the characters a crit number uses into one texture per font, for big crits drawn as images.

    python scripts/crit_glyphs.py <SharedMedia addon folder>

Each character is white with a black outline baked in, so the game can tint it to the crit's colour
(the black stays black). For every font SharedMedia.lua registers this writes Media/Crit/<file>.png,
converts it to Media/Crit/<file>.blp through Okanvil's png2blp_dxt5.py, and writes CritGlyphs.lua
with each character's spot in its texture, keyed by the font's name in the Font list. A font
missing one of the characters is left out (and so isn't offered in the Font list).

DXT5 needs Pillow 11.2 or later: older ones silently write raw pixels under a DXT5 header, which
the game draws as garbage. Each texture is checked for that.
"""
import os
import re
import subprocess
import sys

import PIL
from fontTools.ttLib import TTFont
from PIL import Image, ImageDraw, ImageFont

# Blender Pro's crits are drawn in its bold cut, which reads better that big
DRAWN_AS = {"Blender Pro": "BlenderProBold.ttf"}


def registered(addon):
    # name in the Font list -> font file, as SharedMedia.lua registers them
    text = open(os.path.join(addon, "SharedMedia.lua"), encoding="utf-8", errors="replace").read()
    found = re.findall(r'LSM:Register\(MediaType_FONT,\s*"([^"]+)",\s*\[\[[^\]]*\\([^\\\]]+\.ttf)\]\]', text)
    return [(name, DRAWN_AS.get(name, ttf)) for name, ttf in found]


def has_chars(path):
    cmap = TTFont(path, fontNumber=0).getBestCmap() or {}
    return all(ord(c) in cmap for c in CHARS)

CHARS = "0123456789.,km+-"
W, H = 512, 512           # square (the client loads square custom textures), four rows of cells
CELL_H = 128
PAD = 4
STROKE = 7

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BLP = os.path.join(ROOT, "..", "Okanvil", "scripts", "png2blp_dxt5.py")


def rows_needed(font):
    x, rows = 0, 1
    for c in CHARS:
        left, _, right, _ = font.getbbox(c, anchor="ls", stroke_width=STROKE)
        w = right - left + 2 * PAD
        if x + w > W:
            x, rows = 0, rows + 1
        x += w
    return rows


def fit(path):
    # The biggest size at which every character, outline included, fits a cell with the digits
    # centred in it, so the number sits level with the icon beside it (the comma hangs below), and
    # all of them fit the texture.
    size = CELL_H
    while size > 10:
        font = ImageFont.truetype(path, size)
        box = lambda c: font.getbbox(c, anchor="ls", stroke_width=STROKE)
        baseline = CELL_H / 2 - (min(box(c)[1] for c in "0123456789") + max(box(c)[3] for c in "0123456789")) / 2
        top = min(box(c)[1] for c in CHARS) + baseline
        bottom = max(box(c)[3] for c in CHARS) + baseline
        if top >= PAD and bottom <= CELL_H - PAD and rows_needed(font) * CELL_H <= H:
            return font, round(baseline)
        size -= 2
    return None, None


def build(file, path):
    font, baseline = fit(path)
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    x, row, glyphs = 0, 0, []
    for c in CHARS:
        left, _, right, _ = font.getbbox(c, anchor="ls", stroke_width=STROKE)
        w = right - left + 2 * PAD
        if x + w > W:
            x, row = 0, row + 1
        if (row + 1) * CELL_H > H:
            sys.exit(f"{path}: too wide for one texture")
        y = row * CELL_H
        draw.text((x + PAD - left, y + baseline), c, font=font, anchor="ls", fill="white",
                  stroke_width=STROKE, stroke_fill="black")
        # left: where the cell starts against the pen, advance: how far the pen moves on
        glyphs.append((c, x, y, w, left - PAD, font.getlength(c)))
        x += w
    os.makedirs(os.path.join(ROOT, "Media", "Crit"), exist_ok=True)
    png = os.path.join(ROOT, "Media", "Crit", file + ".png")
    blp = png[:-4] + ".blp"
    img.save(png)
    subprocess.check_call([sys.executable, BLP, png, blp, "%dx%d" % (W, H)])
    # a DXT5 top level is one byte a pixel; four means raw pixels slipped through
    with open(blp, "rb") as f:
        f.seek(84)
        mip0 = int.from_bytes(f.read(4), "little")
    if mip0 != W * H:
        sys.exit(f"{blp}: top level is {mip0} bytes, not DXT5")
    return glyphs, font.size


def num(v):
    """a number as short as it reads the same: 0.25, 66, -11, 44"""
    s = ("%.6f" % v).rstrip("0").rstrip(".")
    return s if s not in ("", "-0") else "0"


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    if tuple(int(v) for v in PIL.__version__.split(".")[:2]) < (11, 2):
        sys.exit(f"Pillow {PIL.__version__} can't write DXT5: 11.2 or later is needed")
    addon = sys.argv[1]
    folder = os.path.join(addon, "Media", "Fonts")
    # one string per font, unpacked in game only for the font in use: a table per character for
    # every font cost over half a megabyte of memory
    out = ["local ADDON, ns = ...", "",
           "-- Made by scripts/crit_glyphs.py: per font in the Font list, one string read only for the font in",
           "-- use: its texture in Media\\Crit, the size its characters were drawn at, then each character",
           "-- (\";\" between them): the character, its cell (left, right, top, bottom as texture coordinates),",
           "-- its width and its pen offset and advance, in pixels of a %d-pixel-high cell." % CELL_H,
           "ns.CRIT_GLYPHS = {"]
    built, skipped = {}, []
    for name, ttf in registered(addon):
        path = os.path.join(folder, ttf)
        file = re.sub(r"[^A-Za-z0-9]", "", os.path.splitext(ttf)[0])
        if file not in built:
            if not os.path.exists(path) or not has_chars(path) or fit(path)[0] is None:
                built[file] = None
            else:
                built[file] = build(file, path)
        if not built[file]:
            skipped.append(name)
            continue
        glyphs, size = built[file]
        parts = []
        for c, x, y, w, left, adv in glyphs:
            vals = (x / W, (x + w) / W, y / H, (y + CELL_H) / H, w, left, adv)
            parts.append(c + " " + " ".join(num(v) for v in vals))
        out.append('\t["%s"] = "%s|%d|%s",' % (name, file, size, ";".join(parts)))
    out += ["}", "ns.CRIT_CELL = %d" % CELL_H, ""]
    with open(os.path.join(ROOT, "CritGlyphs.lua"), "w", encoding="utf-8", newline="\r\n") as f:
        f.write("\n".join(out))
    print(f"{len(built) - len([b for b in built.values() if not b])} textures; left out: {', '.join(skipped) or 'none'}")


if __name__ == "__main__":
    main()
