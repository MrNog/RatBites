"""Draw the characters a crit number uses into one texture per font, for big crits drawn as images.

    python scripts/crit_glyphs.py <key> <font.ttf> [<key> <font.ttf> ...]

Each character is white with a black outline baked in, so the game can tint it to the crit's colour
(the black stays black). Writes Media/Crit/<key>.png, converts it to Media/Crit/<key>.blp through
Okanvil's png2blp_dxt5.py, and writes CritGlyphs.lua with each character's spot in its texture.
"""
import os
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFont

CHARS = "0123456789.,km+-"
W, H = 512, 512           # square (the client loads square custom textures), four rows of cells
CELL_H = 128
PAD = 4
STROKE = 7

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BLP = os.path.join(ROOT, "..", "Okanvil", "scripts", "png2blp_dxt5.py")


def fit(path):
    # the biggest size whose tallest character, outline included, fits a cell
    size = CELL_H
    while size > 10:
        font = ImageFont.truetype(path, size)
        top = min(font.getbbox(c, anchor="ls", stroke_width=STROKE)[1] for c in CHARS)
        bottom = max(font.getbbox(c, anchor="ls", stroke_width=STROKE)[3] for c in CHARS)
        if bottom - top <= CELL_H - 2 * PAD:
            return font, -top + PAD
        size -= 2
    sys.exit("font too tall")


def build(key, path):
    font, baseline = fit(path)
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    x, row, glyphs = 0, 0, []
    for c in CHARS:
        left, _, right, _ = font.getbbox(c, anchor="ls", stroke_width=STROKE)
        w = right - left + 2 * PAD
        if x + w > W:
            x, row = 0, row + 1
        y = row * CELL_H
        draw.text((x + PAD - left, y + baseline), c, font=font, anchor="ls", fill="white",
                  stroke_width=STROKE, stroke_fill="black")
        # left: where the cell starts against the pen, advance: how far the pen moves on
        glyphs.append((c, x, y, w, left - PAD, font.getlength(c)))
        x += w
    os.makedirs(os.path.join(ROOT, "Media", "Crit"), exist_ok=True)
    png = os.path.join(ROOT, "Media", "Crit", key + ".png")
    img.save(png)
    subprocess.check_call([sys.executable, BLP, png, png[:-4] + ".blp", "%dx%d" % (W, H)])
    return glyphs, font.size


def main():
    args = sys.argv[1:]
    if not args or len(args) % 2:
        sys.exit(__doc__)
    out = ["local ADDON, ns = ...", "",
           "-- Made by scripts/crit_glyphs.py: per font, each character's cell in Media\\Crit\\<font>.blp",
           "-- (left, right, top, bottom as texture coordinates), its width and its pen offset and advance,",
           "-- in pixels of a %d-pixel-high cell." % CELL_H,
           "ns.CRIT_GLYPHS = {"]
    for key, path in zip(args[::2], args[1::2]):
        out.append('\t["%s"] = {' % key)
        glyphs, size = build(key, path)
        out.append('\t\tsize = %d,  -- the font size the characters were drawn at' % size)
        for c, x, y, w, left, adv in glyphs:
            out.append('\t\t["%s"] = { %.6f, %.6f, %.6f, %.6f, %d, %d, %.1f },'
                       % (c, x / W, (x + w) / W, y / H, (y + CELL_H) / H, w, left, adv))
        out.append("\t},")
    out += ["}", "ns.CRIT_CELL = %d" % CELL_H, ""]
    with open(os.path.join(ROOT, "CritGlyphs.lua"), "w", encoding="utf-8", newline="\r\n") as f:
        f.write("\n".join(out))


if __name__ == "__main__":
    main()
