import math
from PIL import Image, ImageDraw

S = 2048  # supersample master, downscale to 1024
img = Image.new('RGBA', (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(img)

def lerp(a, b, t): return tuple(int(a[i] + (b[i]-a[i])*t) for i in range(3))
TOP = (0x63, 0x66, 0xF1)   # indigo-500
BOT = (0x43, 0x38, 0xCA)   # indigo-700

# vertical gradient
grad = Image.new('RGBA', (S, S))
gp = grad.load()
for y in range(S):
    c = lerp(TOP, BOT, y/(S-1)) + (255,)
    for x in range(S):
        gp[x, y] = c

# rounded-square mask (with margin so it looks like an app icon tile)
mask = Image.new('L', (S, S), 0)
md = ImageDraw.Draw(mask)
m = int(S*0.06); r = int(S*0.20)
md.rounded_rectangle([m, m, S-m, S-m], radius=r, fill=255)
img = Image.composite(grad, img, mask)
d = ImageDraw.Draw(img)

cx = cy = S//2

# --- knob ---
OUT = (0xEE, 0xF2, 0xFF, 255)   # near-white ring
FACE = (0x1E, 0x1B, 0x4B, 255)  # dark indigo face
TICK = (0xC7, 0xD2, 0xFE, 255)  # light ticks
PTR = (0xFB, 0xBF, 0x24, 255)   # amber pointer

r_ring = int(S*0.30)
r_face = int(S*0.235)
d.ellipse([cx-r_ring, cy-r_ring, cx+r_ring, cy+r_ring], fill=OUT)
d.ellipse([cx-r_face, cy-r_face, cx+r_face, cy+r_face], fill=FACE)

# tick marks: 270-degree arc (gap at bottom), from 225deg to -45deg going CW through top
r_tick = int(S*0.365)
n = 11
start, end = 225, -45  # degrees, standard math (0=right, CCW+); go from 225 down to -45
for i in range(n):
    ang = math.radians(start + (end-start)*i/(n-1))
    tx, ty = cx + r_tick*math.cos(ang), cy - r_tick*math.sin(ang)
    tr = int(S*0.018)
    d.ellipse([tx-tr, ty-tr, tx+tr, ty+tr], fill=TICK)

# pointer indicator: from center toward ~1 o'clock (60deg math = up-right)
pang = math.radians(65)
x0, y0 = cx + int(S*0.03)*math.cos(pang), cy - int(S*0.03)*math.sin(pang)
x1, y1 = cx + int(S*0.20)*math.cos(pang), cy - int(S*0.20)*math.sin(pang)
d.line([x0, y0, x1, y1], fill=PTR, width=int(S*0.03))
# rounded cap dot
cr = int(S*0.018)
d.ellipse([x1-cr, y1-cr, x1+cr, y1+cr], fill=PTR)
# center hub
hr = int(S*0.03)
d.ellipse([cx-hr, cy-hr, cx+hr, cy+hr], fill=TICK)

out = img.resize((1024, 1024), Image.LANCZOS)
out.save(f"{__import__('os').path.dirname(__file__)}/pocketedit_icon.png")
print("wrote pocketedit_icon.png 1024x1024")
