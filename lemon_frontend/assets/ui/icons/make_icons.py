# Rasterize the lemonade-stand icon set to 256x256 PNGs with a real alpha channel.
# No external imaging library: shapes are filled, outlined, then antialiased by
# supersampling. Background pixels stay alpha 0.
import math
import os
import struct
import zlib

OUT = os.path.dirname(os.path.abspath(__file__))
SIZE = 256
SS = 4
N = SIZE * SS
WOOD = (0x5C, 0x3A, 0x21)
WOOD_MID = (0x8C, 0x61, 0x38)
CREAM = (0xFC, 0xF6, 0xE3)
WHITE = (0xFF, 0xFB, 0xF0)
GREEN = (0xA9, 0xCE, 0x7A)
GREEN_DARK = (0x3F, 0x5A, 0x2C)
LEMON = (0xF8, 0xDB, 0x52)
LEMON_HI = (0xFF, 0xF3, 0xB0)
ICE = (0xBF, 0xE3, 0xF2)
ICE_EDGE = (0x4A, 0x6B, 0x7A)
ORANGE = (0xF8, 0x9E, 0x3D)
GOLD = (0xE8, 0xC8, 0x7A)
TAG = (0xF4, 0xC9, 0x6A)


def blank():
	return bytearray(N * N * 4)


def set_px(buf, x, y, rgb, a=255):
	if x < 0 or y < 0 or x >= N or y >= N or a <= 0:
		return
	i = (y * N + x) * 4
	if a >= 255 or buf[i + 3] == 0:
		buf[i:i + 4] = bytes((rgb[0], rgb[1], rgb[2], a))
		return
	oa = buf[i + 3] / 255.0
	na = a / 255.0
	out_a = na + oa * (1.0 - na)
	for c in range(3):
		buf[i + c] = int((rgb[c] * na + buf[i + c] * oa * (1.0 - na)) / out_a)
	buf[i + 3] = int(out_a * 255)


def fill_poly(buf, pts, rgb):
	if len(pts) < 3:
		return
	ys = [p[1] for p in pts]
	y0 = max(0, int(math.floor(min(ys))))
	y1 = min(N - 1, int(math.ceil(max(ys))))
	for y in range(y0, y1 + 1):
		scan = y + 0.5
		xs = []
		for i in range(len(pts)):
			x1, y1 = pts[i]
			x2, y2 = pts[(i + 1) % len(pts)]
			if (y1 <= scan < y2) or (y2 <= scan < y1):
				t = (scan - y1) / (y2 - y1)
				xs.append(x1 + t * (x2 - x1))
		xs.sort()
		for i in range(0, len(xs) - 1, 2):
			xa = max(0, int(math.floor(xs[i])))
			xb = min(N - 1, int(math.ceil(xs[i + 1])))
			for x in range(xa, xb + 1):
				set_px(buf, x, y, rgb)


def fill_ellipse(buf, cx, cy, rx, ry, rgb):
	if rx <= 0 or ry <= 0:
		return
	x0 = max(0, int(cx - rx - 1))
	x1 = min(N - 1, int(cx + rx + 1))
	y0 = max(0, int(cy - ry - 1))
	y1 = min(N - 1, int(cy + ry + 1))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			dx = (x + 0.5 - cx) / rx
			dy = (y + 0.5 - cy) / ry
			if dx * dx + dy * dy <= 1.0:
				set_px(buf, x, y, rgb)


def stroke_poly(buf, pts, rgb, width, closed=True):
	seq = list(pts)
	if closed and seq:
		seq.append(seq[0])
	for i in range(len(seq) - 1):
		stroke_line(buf, seq[i], seq[i + 1], rgb, width)


def stroke_line(buf, a, b, rgb, width):
	x1, y1 = a
	x2, y2 = b
	dx = x2 - x1
	dy = y2 - y1
	dist = math.hypot(dx, dy)
	steps = max(1, int(dist * 2))
	r = width * 0.5
	for i in range(steps + 1):
		t = i / steps
		fill_ellipse(buf, x1 + dx * t, y1 + dy * t, r, r, rgb)


def stroke_ellipse(buf, cx, cy, rx, ry, rgb, width):
	steps = max(48, int((rx + ry) * 0.5))
	pts = []
	for i in range(steps):
		a = math.tau * i / steps
		pts.append((cx + math.cos(a) * rx, cy + math.sin(a) * ry))
	stroke_poly(buf, pts, rgb, width, True)


def u(v):
	return v * SS


def upts(pts):
	return [(u(x), u(y)) for x, y in pts]


def ellipse(buf, cx, cy, rx, ry, fill, outline=WOOD, w=2.5):
	fill_ellipse(buf, u(cx), u(cy), u(rx), u(ry), fill)
	if w > 0:
		stroke_ellipse(buf, u(cx), u(cy), u(rx), u(ry), outline, u(w))


def poly(buf, pts, fill, outline=WOOD, w=2.5, closed=True):
	fill_poly(buf, upts(pts), fill)
	if w > 0:
		stroke_poly(buf, upts(pts), outline, u(w), closed)


def box(buf, x, y, w, h, fill, outline=WOOD, sw=2.5):
	poly(buf, [(x, y), (x + w, y), (x + w, y + h), (x, y + h)], fill, outline, sw)


def line(buf, a, b, color=WOOD, w=2.5):
	stroke_line(buf, (u(a[0]), u(a[1])), (u(b[0]), u(b[1])), color, u(w))


def dot(buf, cx, cy, r, fill, outline=WOOD, w=2.5):
	ellipse(buf, cx, cy, r, r, fill, outline, w)


def downsample(buf):
	out = bytearray(SIZE * SIZE * 4)
	area = SS * SS
	for y in range(SIZE):
		for x in range(SIZE):
			r = g = b = a = 0
			for sy in range(SS):
				row = ((y * SS + sy) * N + x * SS) * 4
				for sx in range(SS):
					i = row + sx * 4
					pa = buf[i + 3]
					r += buf[i] * pa
					g += buf[i + 1] * pa
					b += buf[i + 2] * pa
					a += pa
			o = (y * SIZE + x) * 4
			if a == 0:
				continue
			out[o] = r // a
			out[o + 1] = g // a
			out[o + 2] = b // a
			out[o + 3] = a // area
	return out


def write_png(path, rgba):
	def chunk(tag, data):
		return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

	raw = b"".join(b"\x00" + bytes(rgba[y * SIZE * 4:(y + 1) * SIZE * 4]) for y in range(SIZE))
	ihdr = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0)
	png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
	with open(path, "wb") as f:
		f.write(png)


def save(name, draw):
	buf = blank()
	draw(buf)
	path = os.path.join(OUT, name + ".png")
	write_png(path, downsample(buf))
	print(name, os.path.getsize(path))


def lemon(buf):
	ellipse(buf, 24, 27, 16, 13, LEMON)
	ellipse(buf, 17, 22, 5, 3.4, LEMON_HI, LEMON_HI, 0)
	poly(buf, [(24, 15), (26, 9), (32, 5), (35, 8), (30, 13), (25, 14.5)], GREEN, GREEN_DARK, 2.0)


def sugar(buf):
	box(buf, 6, 20, 20, 20, CREAM)
	box(buf, 22, 10, 20, 20, WHITE)
	line(buf, (10, 27), (22, 27), WOOD_MID, 1.6)
	line(buf, (26, 17), (38, 17), WOOD_MID, 1.6)


def ice(buf):
	poly(buf, [(10, 16), (24, 9), (38, 16), (38, 32), (24, 39), (10, 32)], ICE, ICE_EDGE)
	line(buf, (10, 16), (24, 23), ICE_EDGE, 1.8)
	line(buf, (38, 16), (24, 23), ICE_EDGE, 1.8)
	line(buf, (24, 23), (24, 39), ICE_EDGE, 1.8)
	line(buf, (14, 19), (21, 22.5), WHITE, 2.2)


def cup(buf):
	poly(buf, [(13, 16), (35, 16), (32, 39), (16, 39)], LEMON_HI)
	box(buf, 10, 11, 28, 6, CREAM)
	box(buf, 28, 4, 3.4, 20, ORANGE)
	line(buf, (16, 23), (32, 23), WOOD_MID, 1.6)


def coin(buf):
	dot(buf, 24, 24, 15, LEMON)
	dot(buf, 24, 24, 10, LEMON_HI, WOOD_MID, 1.6)
	line(buf, (24, 16), (24, 32), WOOD_MID, 2.4)
	line(buf, (20.5, 19.5), (27.5, 19.5), WOOD_MID, 2.0)
	line(buf, (20.5, 28.5), (27.5, 28.5), WOOD_MID, 2.0)


def recipe(buf):
	box(buf, 12, 6, 24, 36, CREAM)
	for y in (16, 23, 30):
		line(buf, (16, y), (30, y), WOOD_MID, 2.0)
	line(buf, (16, 36), (24, 36), WOOD_MID, 2.0)


def shop(buf):
	poly(buf, [(8, 18), (40, 18), (36, 40), (12, 40)], GOLD)
	# handle
	steps = 18
	pts = []
	for i in range(steps + 1):
		a = math.pi + math.pi * i / steps
		pts.append((24 + math.cos(a) * 8, 18 + math.sin(a) * 8))
	stroke_poly(buf, upts(pts), WOOD, u(2.4), False)


def upgrades(buf):
	poly(buf, [(24, 6), (38, 20), (31, 20), (31, 32), (17, 32), (17, 20), (10, 20)], GREEN, GREEN_DARK)
	line(buf, (10, 40), (38, 40), WOOD, 3.0)


def map_icon(buf):
	poly(buf, [(8, 12), (18, 8), (30, 13), (40, 9), (40, 38), (30, 42), (18, 37), (8, 41)], CREAM)
	line(buf, (18, 8), (18, 37), WOOD_MID, 1.6)
	line(buf, (30, 13), (30, 42), WOOD_MID, 1.6)
	line(buf, (12, 32), (34, 18), GREEN_DARK, 2.0)
	dot(buf, 24, 25, 3.4, LEMON)


def settings(buf):
	dot(buf, 24, 24, 6.5, CREAM)
	for i in range(8):
		a = math.tau * i / 8.0
		d = (math.cos(a), math.sin(a))
		line(buf, (24 + d[0] * 11, 24 + d[1] * 11), (24 + d[0] * 18, 24 + d[1] * 18), WOOD, 3.2)


def staff(buf):
	dot(buf, 18, 16, 5.2, LEMON_HI)
	poly(buf, [(10, 24), (26, 24), (28, 40), (8, 40)], GREEN, GREEN_DARK, 2.0)
	dot(buf, 30, 14, 5.6, CREAM)
	poly(buf, [(22, 22), (40, 22), (42, 40), (20, 40)], GOLD, WOOD, 2.2)


def sun(buf, base, n, inner, outer):
	dot(buf, 24, 24, 10, base, base, 0)
	for i in range(n):
		a = math.tau * i / n
		d = (math.cos(a), math.sin(a))
		line(buf, (24 + d[0] * inner, 24 + d[1] * inner), (24 + d[0] * outer, 24 + d[1] * outer), base, 3.0)


def cold(buf):
	for i in range(6):
		a = math.tau * i / 6.0
		d = (math.cos(a), math.sin(a))
		line(buf, (24, 24), (24 + d[0] * 16, 24 + d[1] * 16), ICE_EDGE, 2.8)
		line(buf, (24 + d[0] * 10, 24 + d[1] * 10), (24 + d[0] * 10 + d[1] * 3.2, 24 + d[1] * 10 - d[0] * 3.2), ICE_EDGE, 2.0)
	dot(buf, 24, 24, 3.2, WHITE, ICE_EDGE, 1.6)


def cloud(buf, cy=24):
	ellipse(buf, 17, cy, 8, 8, WHITE)
	ellipse(buf, 26, cy - 3, 10, 10, WHITE)
	ellipse(buf, 34, cy + 1, 7.5, 7.5, WHITE)
	box(buf, 10, cy, 30, 8, WHITE, WHITE, 0)
	# redraw the lower outline so the boxes do not leave a seam
	line(buf, (10, cy + 8), (40, cy + 8), WOOD, 2.4)


def rain(buf):
	cloud(buf, 18)
	for x in (16, 24, 32):
		line(buf, (x, 32), (x - 2, 41), ICE_EDGE, 2.6)


def heart(buf):
	ellipse(buf, 17, 18, 8, 8, GREEN, GREEN, 0)
	ellipse(buf, 31, 18, 8, 8, GREEN, GREEN, 0)
	poly(buf, [(9, 20), (24, 40), (39, 20), (31, 14), (24, 22), (17, 14)], GREEN, GREEN_DARK, 2.2)


def price(buf):
	poly(buf, [(8, 20), (26, 8), (40, 22), (22, 40)], TAG)
	dot(buf, 16, 26, 2.4, WOOD, WOOD, 0)
	line(buf, (18, 22), (30, 30), WOOD_MID, 1.8)


def clock(buf):
	dot(buf, 24, 24, 15, CREAM)
	dot(buf, 24, 24, 1.6, WOOD, WOOD, 0)
	line(buf, (24, 24), (24, 13), WOOD, 2.2)
	line(buf, (24, 24), (32, 28), WOOD, 2.2)
	for i in range(12):
		a = math.tau * i / 12.0 - math.pi / 2.0
		d = (math.cos(a), math.sin(a))
		line(buf, (24 + d[0] * 12, 24 + d[1] * 12), (24 + d[0] * 14, 24 + d[1] * 14), WOOD_MID, 1.6)


ICONS = {
	"lemon": lemon,
	"sugar": sugar,
	"ice": ice,
	"cup": cup,
	"coin": coin,
	"recipe": recipe,
	"shop": shop,
	"upgrades": upgrades,
	"map": map_icon,
	"settings": settings,
	"staff": staff,
	"sun": lambda b: sun(b, LEMON, 8, 14, 19),
	"hot": lambda b: sun(b, ORANGE, 12, 14, 20),
	"cold": cold,
	"rain": rain,
	"cloudy": lambda b: cloud(b, 24),
	"heart": heart,
	"price": price,
	"clock": clock,
}

if __name__ == "__main__":
	for name, fn in ICONS.items():
		save(name, fn)
