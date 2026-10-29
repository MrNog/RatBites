"""Draw the characters a crit number uses into one texture per font, for big crits drawn as images.

    python scripts/crit_glyphs.py <SharedMedia fonts folder>

Each character is white with a black outline baked in, so the game can tint it to the crit's colour
(the black stays black). For every font in FONTS this writes Media/Crit/<file>.png, converts it to
Media/Crit/<file>.blp through Okanvil's png2blp_dxt5.py, and writes CritGlyphs.lua with each
character's spot in its texture, keyed by the font's name in the Font list.

DXT5 needs Pillow 11.2 or later: older ones silently write raw pixels under a DXT5 header, which
the game draws as garbage. Each texture is checked for that.
"""
import os
import re
import subprocess
import sys

import PIL
from PIL import Image, ImageDraw, ImageFont

# name in the Font list (LibSharedMedia) -> font file drawn for it. Blender Pro's crits are drawn
# in its bold cut, which reads better that big.
FONTS = [
    ("Blender Pro", "BlenderProBold.ttf"),
    ("Blender Pro Bold", "BlenderProBold.ttf"),
    ("Blender Pro Heavy", "BlenderProHeavy.ttf"),
    ("Pokemon Solid", "PokemonSolid.ttf"),
    ("Expressway", "Expressway.ttf"),
    ("Bazooka", "Bazooka.ttf"),
    ("BigNoodleToo", "BigNoodleToo.ttf"),
    ("Impact", "Impact.ttf"),
    ("Oswald", "Oswald.ttf"),
    ("FrancoisOne", "FrancoisOne.ttf"),
    ("Gotham Ultra", "GothamUltra.ttf"),
    ("Futura PT Bold", "FuturaPTBold.ttf"),
    ("SF Wonder Comic", "SFWonderComic.ttf"),
    ("Yellowjacket", "Yellowjacket.ttf"),
    ("X360", "X360.ttf"),
    ("Porky", "Porky.ttf"),
    ("Steelfish Rg", "SteelfishRg.ttf"),
    ("Diogenes", "Diogenes.ttf"),
    ("Bavaria", "Bavaria.ttf"),
]

CHARS = "0123456789.,km+-"
W, H = 512, 512           # square (the client loads square custom textures), four rows of cells
CELL_H = 128
PAD = 4
STROKE = 7

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BLP = os.path.join(ROOT, "..", "Okanvil", "scripts", "png2blp_dxt5.py")


def fit(path):
    # The biggest size at which every character, outline included, fits a cell with the digits
    # centred in it, so the number sits level with the icon beside it (the comma hangs below).
    size = CELL_H
    while size > 10:
        font = ImageFont.truetype(path, size)
        box = lambda c: font.getbbox(c, anchor="ls", stroke_width=STROKE)
        baseline = CELL_H / 2 - (min(box(c)[1] for c in "0123456789") + max(box(c)[3] for c in "0123456789")) / 2
        top = min(box(c)[1] for c in CHARS) + baseline
        bottom = max(box(c)[3] for c in CHARS) + baseline
        if top >= PAD and bottom <= CELL_H - PAD:
            return font, round(baseline)
        size -= 2
    sys.exit("font too tall")


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


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    if tuple(int(v) for v in PIL.__version__.split(".")[:2]) < (11, 2):
        sys.exit(f"Pillow {PIL.__version__} can't write DXT5: 11.2 or later is needed")
    folder = sys.argv[1]
    out = ["local ADDON, ns = ...", "",
           "-- Made by scripts/crit_glyphs.py: per font in the Font list, its texture in Media\\Crit, the size",
           "-- its characters were drawn at, and each character's cell (left, right, top, bottom as texture",
           "-- coordinates), its width and its pen offset and advance, in pixels of a %d-pixel-high cell." % CELL_H,
           "ns.CRIT_GLYPHS = {"]
    for name, ttf in FONTS:
        file = re.sub(r"[^A-Za-z0-9]", "", os.path.splitext(ttf)[0])
        glyphs, size = build(file, os.path.join(folder, ttf))
        out.append('\t["%s"] = {' % name)
        out.append('\t\tfile = "%s",' % file)
        out.append('\t\tsize = %d,' % size)
        for c, x, y, w, left, adv in glyphs:
            out.append('\t\t["%s"] = { %.6f, %.6f, %.6f, %.6f, %d, %d, %.1f },'
                       % (c, x / W, (x + w) / W, y / H, (y + CELL_H) / H, w, left, adv))
        out.append("\t},")
    out += ["}", "ns.CRIT_CELL = %d" % CELL_H, ""]
    with open(os.path.join(ROOT, "CritGlyphs.lua"), "w", encoding="utf-8", newline="\r\n") as f:
        f.write("\n".join(out))


if __name__ == "__main__":
    main()
