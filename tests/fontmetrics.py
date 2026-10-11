# Emits a Lua table of per-character advance widths for each board font, using
# DejaVu Sans as a deliberately wide stand-in for Tahoma / Trebuchet MS.
import sys
from PIL import ImageFont

FONTS = {
    "BoggleKills_Brand": (42, True), "BoggleKills_Sub": (16, True), "BoggleKills_Head": (16, True),
    "BoggleKills_Row": (25, True), "BoggleKills_Num": (22, True), "BoggleKills_Key": (25, True),
    "BoggleKills_Stat": (30, True), "BoggleKills_Badge": (18, True), "BoggleKills_Tab": (15, True),
    "BoggleKills_Ticker": (17, True), "BoggleKills_Small": (14, True),
}
EM = 1 / 1.12
SCALE = float(sys.argv[1]) if len(sys.argv) > 1 else 1.0
REG = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
chars = [chr(c) for c in range(32, 127)] + ["…", "·", "×"]
out = ["return {"]
for name, (size, bold) in FONTS.items():
    f = ImageFont.truetype(BOLD if bold else REG, round(size * EM * SCALE))
    asc, desc = f.getmetrics()
    out.append(f'  ["{name}"] = {{ h = {(asc + desc) / SCALE:.2f}, w = {{')
    for ch in chars:
        esc = ch.replace("\\", "\\\\").replace('"', '\\"')
        out.append(f'    ["{esc}"] = {f.getlength(ch) / SCALE:.3f},')
    out.append("  } },")
out.append("}")
print("\n".join(out))
