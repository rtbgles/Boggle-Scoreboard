# Paints the draw calls recorded by render.lua to PNG, approximating GMod's
# surface/draw behaviour (alpha blending, text alignment, gradients, the logo).
import json
import sys
from PIL import Image, ImageDraw, ImageFont

SCALE = 2
EM = 1 / 1.12
BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
SIZES = {
    "BoggleKills_Brand": 42, "BoggleKills_Sub": 16, "BoggleKills_Head": 16, "BoggleKills_Row": 25,
    "BoggleKills_Num": 22, "BoggleKills_Key": 25, "BoggleKills_Stat": 30, "BoggleKills_Badge": 18,
    "BoggleKills_Tab": 15, "BoggleKills_Ticker": 17, "BoggleKills_Small": 14,
}
fonts = {k: ImageFont.truetype(BOLD, round(v * EM * SCALE)) for k, v in SIZES.items()}


def rgba(c):
    return tuple(int(max(0, min(255, round(v)))) for v in c)


def gradient(kind, w, h, color):
    w, h = max(1, int(w)), max(1, int(h))
    img = Image.new("RGBA", (w, h))
    px = img.load()
    for yy in range(h):
        for xx in range(w):
            if kind == "l":
                t = 1 - xx / max(w - 1, 1)
            elif kind == "r":
                t = xx / max(w - 1, 1)
            elif kind == "d":
                t = yy / max(h - 1, 1)
            else:
                t = 1 - yy / max(h - 1, 1)
            px[xx, yy] = (color[0], color[1], color[2], int(color[3] * t))
    return img


def paint(path_in, path_out, logo_path):
    data = json.load(open(path_in))
    W, H = data["w"] * SCALE, data["h"] * SCALE
    base = Image.new("RGBA", (W, H), (40, 44, 52, 255))  # wall behind the board
    logo = Image.open(logo_path).convert("RGBA") if logo_path else None
    for op in data["ops"]:
        layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        c = rgba(op["c"])
        kind = op["op"]
        if kind == "rect":
            x, y, w, h = (int(op[k]) * SCALE for k in ("x", "y", "w", "h"))
            if w > 0 and h > 0:
                d.rectangle([x, y, x + w - 1, y + h - 1], fill=c)
        elif kind == "outline":
            x, y, w, h = (int(op[k]) * SCALE for k in ("x", "y", "w", "h"))
            d.rectangle([x, y, x + w - 1, y + h - 1], outline=c, width=op["t"] * SCALE)
        elif kind == "poly":
            d.polygon([(px * SCALE, py * SCALE) for px, py in op["pts"]], fill=c)
        elif kind == "tex":
            x, y, w, h = (op[k] * SCALE for k in ("x", "y", "w", "h"))
            mat = op["mat"]
            if mat.startswith("boggle_kills/logo") and logo:
                img = logo.resize((int(w), int(h)))
                if c[3] < 255:
                    a = img.getchannel("A").point(lambda v: v * c[3] // 255)
                    img.putalpha(a)
                layer.paste(img, (int(x), int(y)))
            elif mat.startswith("vgui/gradient-"):
                g = gradient(mat[-1], w, h, c)
                layer.paste(g, (int(x), int(y)))
        elif kind == "text":
            f = fonts[op["font"]]
            tw = f.getlength(op["text"])
            asc, desc = f.getmetrics()
            th = asc + desc
            x, y = op["x"] * SCALE, op["y"] * SCALE
            if op["xa"] == 1:
                x -= tw / 2
            elif op["xa"] == 2:
                x -= tw
            if op["ya"] == 1:
                y -= th / 2
            elif op["ya"] == 4:
                y -= th
            d.text((x, y), op["text"], font=f, fill=c)
        base = Image.alpha_composite(base, layer)
    base.convert("RGB").save(path_out)


if __name__ == "__main__":
    paint(sys.argv[1], sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else None)
