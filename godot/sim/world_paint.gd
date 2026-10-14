class_name WorldPaint
extends RefCounted
## Ground painter: literal port of js/world/tiles.js paintChunk / dirtMask / paintFloor /
## paintWall / paintLiquid (§7.7), pixel-exact against the JS (tests/phase3_tests.gd).
##
## Instead of RGBA it writes one PALETTE SLOT per art pixel (24 slots, identical layout for all
## 21 biomes): the index map depends only on (seed, terrain), so a biome change or the 2.6 s
## crossfade never repaints anything — render/ground_layer.gd draws the R8 index texture with a
## palette shader (old/new palette mixed by fadeK). to_rgba() gives the exact JS bytes.
##
## Pure static functions over packed arrays: safe on WorkerThreadPool threads. The 32-bit hash
## (G.U.hash) is inlined with incremental x terms; every float operation keeps the JS order.

const T := 16                     # art px per tile
const W := 256                    # art px per chunk side (16 tiles)

# palette slots
const I_FLOOR := 0                # 0..2
const I_DIRT := 3                 # 3..5
const I_SPECK := 6
const I_LIGHT := 7
const I_FLOWER := 8               # 8..10
const I_WTOP := 11                # 11..13
const I_WLIGHT := 14
const I_WEDGE := 15
const I_WFACE := 16               # 16..17
const I_WFDARK := 18
const I_LIQ := 19
const I_LDEEP := 20
const I_FOAM := 21
const I_SHORE := 22
const I_LLIGHT := 23
const NPAL := 24

const FLOOR := 0
const WALL := 1
const LIQUID := 2

# G.U.hash constants
const M32 := 0xFFFFFFFF
const HX := 374761393
const HY := 668265263
const HS := 2246822519
const HM := 1274126177
const INV32 := 1.0 / 4294967296.0

const FULL := [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]
const CORNERS := [0, 1, 2, 13, 14, 15]      # wall / liquid tiles only show floor in their corners

## Seed term of the hash: Math.imul(seed, 2246822519) as uint32.
static func _sterm(s: int) -> int:
	return U.imul32(s, HS)

# ---------------- palettes ----------------

## The 24 palette colours of biome bi, in slot order (packed like tiles.js pack()).
static func palette(bi: int) -> PackedColorArray:
	var B: Dictionary = Data.biomes[bi]
	var out := PackedColorArray()
	for k in ["floor", "dirt"]:
		for h in B[k]:
			out.append(Color.html(h))
	out.append(Color.html(B["speck"]))
	out.append(Color.html(B["light"]))
	for h in B["flowers"]:
		out.append(Color.html(h))
	for h in B["wallTop"]:
		out.append(Color.html(h))
	out.append(Color.html(B["wallLight"]))
	out.append(Color.html(B["wallEdge"]))
	for h in B["wallFace"]:
		out.append(Color.html(h))
	for k in ["wallFaceDark", "liq", "liqDeep", "foam", "shore"]:
		out.append(Color.html(B[k]))
	# liqLight = mixPack(liq, foam, 0.28): per channel Math.round(v + (b - v) * t)
	var a := Color.html(B["liq"])
	var b := Color.html(B["foam"])
	out.append(Color8(U.jroundi(a.r8 + (b.r8 - a.r8) * 0.28), U.jroundi(a.g8 + (b.g8 - a.g8) * 0.28),
		U.jroundi(a.b8 + (b.b8 - a.b8) * 0.28)))
	return out

## Index map -> RGBA8 bytes (tiles.js ImageData), for tests and CPU fallbacks.
static func to_rgba(idx: PackedByteArray, pal: PackedColorArray) -> PackedByteArray:
	var lut := PackedInt32Array()
	lut.resize(256)
	for i in pal.size():
		var c := pal[i]
		lut[i] = c.r8 | (c.g8 << 8) | (c.b8 << 16) | (255 << 24)
	var px := PackedInt32Array()
	px.resize(idx.size())
	for i in idx.size():
		px[i] = lut[idx[i]]
	return px.to_byte_array()

## Cheap placeholder: one palette slot per tile (16x16) from the 18x18 terrain block.
static func placeholder(k18: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(T * T)
	for j in T:
		for i in T:
			var k := k18[(j + 1) * 18 + i + 1]
			out[j * T + i] = I_WTOP if k == WALL else (I_LIQ if k == LIQUID else I_FLOOR)
	return out

# ---------------- chunk ----------------

## paintChunk(cx, cy, 16, at, dirtField, bi, seed): k18 = terrain kinds of the 18x18 tiles
## around the chunk (1-tile border, row-major). Returns W*W palette slots.
static func paint(cx: int, cy: int, k18: PackedByteArray, seed: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(W * W)
	var gx0 := cx * W
	var gy0 := cy * W
	var mask := dirt_mask(gx0, gy0, seed)
	# H(gx >> 3, gy >> 3, 11) for the 32x32 blocks of 8x8 px
	var band := PackedFloat64Array()
	band.resize(32 * 32)
	for by in 32:
		for bx in 32:
			band[by * 32 + bx] = U.hash01((gx0 >> 3) + bx, (gy0 >> 3) + by, 11)
	var s12 := _sterm(12)
	var s13 := _sterm(13)
	for j in T:
		for i in T:
			var tx := cx * T + i
			var ty := cy * T + j
			var c := (j + 1) * 18 + i + 1
			var kind := k18[c]
			var wall_n := k18[c - 18] == WALL
			# 1) floor under everything (rounded wall / liquid corners show it)
			_floor(out, mask, band, gx0, gy0, i * T, j * T, tx, ty, kind == FLOOR, wall_n, s12, s13)
			if kind == WALL:
				_wall(out, i * T, j * T, tx, ty, wall_n, k18[c + 18] == WALL, k18[c - 1] == WALL, k18[c + 1] == WALL)
			elif kind == LIQUID:
				_liquid(out, i * T, j * T, tx, ty, k18, c)
	return out

## dirtMask: fbm dirt field sampled every 4 px (Float32Array like JS), bilinear per pixel plus
## a 2x2-px hash jitter; 1 = dirt. W*(W+1) bytes: row 0 is the row above the chunk (y = -1).
static func dirt_mask(gx0: int, gy0: int, seed: int) -> PackedByteArray:
	const S := 4
	const GW := 67                 # W / S + 3
	var s1 := seed + 303
	# lattice coordinates per column / row for both fbm octaves (vnoise cell + smoothstep weight)
	var ci1 := PackedInt64Array()
	var cu1 := PackedFloat64Array()
	var ci2 := PackedInt64Array()
	var cu2 := PackedFloat64Array()
	var ri1 := PackedInt64Array()
	var rv1 := PackedFloat64Array()
	var ri2 := PackedInt64Array()
	var rv2 := PackedFloat64Array()
	ci1.resize(GW)
	ci2.resize(GW)
	ri1.resize(GW)
	ri2.resize(GW)
	cu1.resize(GW)
	cu2.resize(GW)
	rv1.resize(GW)
	rv2.resize(GW)
	for i in GW:
		var x := float(gx0 + (i - 1) * S) / 96.0
		var f := floorf(x)
		var xf := x - f
		ci1[i] = int(f)
		cu1[i] = xf * xf * (3.0 - 2.0 * xf)
		var x2 := x * 2.13 + 17.0
		f = floorf(x2)
		xf = x2 - f
		ci2[i] = int(f)
		cu2[i] = xf * xf * (3.0 - 2.0 * xf)
		var y := float(gy0 + (i - 1) * S) / 96.0
		f = floorf(y)
		var yf := y - f
		ri1[i] = int(f)
		rv1[i] = yf * yf * (3.0 - 2.0 * yf)
		var y2 := y * 2.13 - 9.0
		f = floorf(y2)
		yf = y2 - f
		ri2[i] = int(f)
		rv2[i] = yf * yf * (3.0 - 2.0 * yf)
	# corner hashes of the few noise cells covering the chunk
	var x1 := ci1[0]
	var nx1 := ci1[GW - 1] - x1 + 2
	var y1 := ri1[0]
	var x2b := ci2[0]
	var nx2 := ci2[GW - 1] - x2b + 2
	var y2b := ri2[0]
	var h1 := PackedFloat64Array()
	h1.resize(nx1 * (ri1[GW - 1] - y1 + 2))
	for k in h1.size():
		h1[k] = U.hash01(x1 + k % nx1, y1 + k / nx1, s1)
	var h2 := PackedFloat64Array()
	h2.resize(nx2 * (ri2[GW - 1] - y2b + 2))
	for k in h2.size():
		h2[k] = U.hash01(x2b + k % nx2, y2b + k / nx2, s1 + 1)
	var grid := PackedFloat32Array()
	grid.resize(GW * GW)
	for j in GW:
		var v := rv1[j]
		var vb := rv2[j]
		var r1 := (ri1[j] - y1) * nx1 - x1
		var r2 := (ri2[j] - y2b) * nx2 - x2b
		for i in GW:
			var t := r1 + ci1[i]
			var u := cu1[i]
			var a := h1[t]
			var b := h1[t + 1]
			var c := h1[t + nx1]
			var d := h1[t + nx1 + 1]
			var n1 := (a + (b - a) * u) * (1.0 - v) + (c + (d - c) * u) * v
			t = r2 + ci2[i]
			u = cu2[i]
			a = h2[t]
			b = h2[t + 1]
			c = h2[t + nx2]
			d = h2[t + nx2 + 1]
			var n2 := (a + (b - a) * u) * (1.0 - vb) + (c + (d - c) * u) * vb
			grid[j * GW + i] = n1 * 0.65 + n2 * 0.35
	# per-pixel bilinear + jitter
	var mask := PackedByteArray()
	mask.resize(W * (W + 1))
	var hsc := _sterm(seed + 9)
	var hxs := PackedInt64Array()       # imul((gx0 + x) >> 1, HX) for even x
	hxs.resize(W / 2)
	for k in W / 2:
		hxs[k] = ((((gx0 >> 1) + k) & M32) * HX) & M32
	var jit := PackedFloat64Array()     # (H(...) - 0.5) * 0.05 per 2-px column pair of a row
	jit.resize(W / 2)
	var last_hy := 1 << 40
	for y in range(-1, W):
		var fy := float(y + S) / S
		var jj := int(floorf(fy))
		var v := fy - jj
		var g0 := jj * GW
		var g1 := g0 + GW
		var hy := (gy0 + y) >> 1
		if hy != last_hy:
			last_hy = hy
			var yb := (((hy & M32) * HY) & M32) ^ hsc
			for k in W / 2:
				var h := hxs[k] ^ yb
				h = ((h ^ (h >> 13)) * HM) & M32
				h ^= h >> 16
				jit[k] = (h * INV32 - 0.5) * 0.05
		var mrow := (y + 1) * W
		for x in W:
			var fx := float(x + S) / S
			var ii := x / S + 1
			var u := fx - ii
			var a := grid[g0 + ii]
			var b := grid[g0 + ii + 1]
			var c := grid[g1 + ii]
			var d := grid[g1 + ii + 1]
			var val := (a + (b - a) * u) * (1.0 - v) + (c + (d - c) * u) * v
			val += jit[x >> 1]
			mask[mrow + x] = 1 if val > 0.64 else 0
	return mask

## paintFloor for one tile. full = floor tile (all 256 px + details); wall / liquid tiles
## only need the corner pixels (their details never survive the overpaint).
static func _floor(out: PackedByteArray, mask: PackedByteArray, band: PackedFloat64Array, gx0: int, gy0: int,
		ox: int, oy: int, tx: int, ty: int, full: bool, wall_n: bool, s12: int, s13: int) -> void:
	var dirt_count := 0
	var xs: Array = FULL if full else CORNERS
	var bx0 := gx0 >> 3
	for y: int in xs:
		var gy := ty * T + y
		var ly := oy + y
		var yb := ((gy & M32) * HY) & M32
		var t12 := yb ^ s12
		var t13 := yb ^ s13
		var brow := ((gy >> 3) - (gy0 >> 3)) * 32 - bx0
		var mrow := (ly + 1) * W
		var mup := ly * W
		var orow := ly * W
		for x: int in xs:
			var gx := tx * T + x
			var lx := ox + x
			var xa := ((gx & M32) * HX) & M32
			var h := xa ^ t12
			h = ((h ^ (h >> 13)) * HM) & M32
			h ^= h >> 16
			var bnd := band[brow + (gx >> 3)] * 0.7 + h * INV32 * 0.5
			var dirt := mask[mrow + lx]
			var idx := (I_DIRT if dirt != 0 else I_FLOOR) + mini(2, int(bnd * 3.0 / 1.2))
			var g := xa ^ t13
			g = ((g ^ (g >> 13)) * HM) & M32
			g ^= g >> 16
			var r := g * INV32
			if r < 0.035:
				idx = I_SPECK
			elif r > 0.985:
				idx = I_LIGHT
			# dirt edge: dark lip on top, grass creeping in below
			var up := mask[mup + lx]
			if dirt != 0 and up == 0:
				idx = I_SPECK
			elif dirt == 0 and up != 0 and r < 0.5:
				idx = I_LIGHT
			# contact shadow under a wall right to the north
			if wall_n:
				if y == 0:
					idx = I_WFDARK
				elif y == 1 and (x + ty) % 2 != 0:
					idx = I_SPECK
			dirt_count += dirt
			out[orow + lx] = idx
	if not full:
		return
	# details: tuft, pebble or flower
	var d := U.hash01(tx, ty, 14)
	var dx := ox + 3 + int(floorf(U.hash01(tx, ty, 15) * 10.0))
	var dy := oy + 4 + int(floorf(U.hash01(tx, ty, 16) * 9.0))
	if dirt_count > T * T / 2:
		if d < 0.22:
			out[dy * W + dx] = I_LIGHT
			out[dy * W + dx + 1] = I_LIGHT
			out[(dy + 1) * W + dx] = I_SPECK
			out[(dy + 1) * W + dx + 1] = I_SPECK
		return
	if d < 0.18:                          # tuft
		out[dy * W + dx] = I_LIGHT
		out[(dy - 1) * W + dx - 1] = I_LIGHT
		out[(dy - 1) * W + dx + 1] = I_LIGHT
		out[(dy - 2) * W + dx] = I_LIGHT
		out[(dy + 1) * W + dx] = I_SPECK
	elif d < 0.26:                        # flower
		var fc := I_FLOWER + int(floorf(U.hash01(tx, ty, 17) * 3.0))
		out[(dy - 1) * W + dx] = fc
		out[dy * W + dx - 1] = fc
		out[dy * W + dx + 1] = fc
		out[(dy + 1) * W + dx] = fc
		out[dy * W + dx] = I_LIGHT
	elif d < 0.32:                        # pebble
		out[dy * W + dx] = I_LIGHT
		out[dy * W + dx + 1] = I_LIGHT
		out[(dy + 1) * W + dx] = I_SPECK
		out[(dy + 1) * W + dx + 1] = I_SPECK

## paintWall (2.5D: top face, front face rows, rounded outer corners).
static func _wall(out: PackedByteArray, ox: int, oy: int, tx: int, ty: int, n: bool, s: bool, w: bool, e: bool) -> void:
	var face := 0 if s else 6
	var s22 := _sterm(22)
	var s23 := _sterm(23)
	var s24 := _sterm(24)
	var s25 := _sterm(25)
	var s21 := _sterm(21)
	var streak := PackedByteArray()        # H(gx, 0, 21) < 0.5 ? 0 : 1 per column
	if face > 0:
		streak.resize(T)
		for x in T:
			var h := (((tx * T + x) & M32) * HX & M32) ^ s21     # y = 0: imul(0, HY) = 0
			h = ((h ^ (h >> 13)) * HM) & M32
			h ^= h >> 16
			streak[x] = 0 if h * INV32 < 0.5 else 1
	for y in T:
		var gy := ty * T + y
		var yb := ((gy & M32) * HY) & M32
		var yb2 := ((((gy >> 1) & M32) * HY) & M32) ^ s23
		var orow := (oy + y) * W + ox
		for x in T:
			# rounded outer corners: the floor shows through
			if not n and not w and x + y < 3:
				continue
			if not n and not e and (T - 1 - x) + y < 3:
				continue
			if not s and not w and x + (T - 1 - y) < 2:
				continue
			if not s and not e and (T - 1 - x) + (T - 1 - y) < 2:
				continue
			var gx := tx * T + x
			var col: int
			if y >= T - face:
				# front face: vertical streaks and a dark base
				var fy := y - (T - face)
				col = I_WFACE + (1 if (x + streak[x]) % 3 == 0 else 0)
				if fy == 0:
					col = I_WEDGE
				elif y == T - 1:
					col = I_WFDARK
				else:
					var h := (((gx & M32) * HX) & M32) ^ yb ^ s22
					h = ((h ^ (h >> 13)) * HM) & M32
					h ^= h >> 16
					if h * INV32 < 0.08:
						col = I_WFDARK
			else:
				# dithered top face; edges: light to the north, dark outline on the sides
				if (not n and y <= 1) or (not w and x == 0) or (not e and x == T - 1):
					col = I_WEDGE if (not n and y == 0) else I_WLIGHT
				else:
					var h := (((((gx >> 1) & M32) * HX) & M32) ^ yb2)
					h = ((h ^ (h >> 13)) * HM) & M32
					h ^= h >> 16
					var xa := ((gx & M32) * HX) & M32
					var g := xa ^ yb ^ s24
					g = ((g ^ (g >> 13)) * HM) & M32
					g ^= g >> 16
					col = I_WTOP + int(floorf(h * INV32 * 2.2 + g * INV32 * 0.8)) % 3
					var q := xa ^ yb ^ s25
					q = ((q ^ (q >> 13)) * HM) & M32
					q ^= q >> 16
					if q * INV32 < 0.05:
						col = I_WLIGHT
				if not w and x == 0:
					col = I_WEDGE
				if not e and x == T - 1:
					col = I_WEDGE
			out[orow + x] = col

## paintLiquid: distance to the shore (inner corners included) -> shore, foam, shallow, deep;
## loose waves and glints.
static func _liquid(out: PackedByteArray, ox: int, oy: int, tx: int, ty: int, k18: PackedByteArray, c: int) -> void:
	var n := k18[c - 18] == LIQUID
	var s := k18[c + 18] == LIQUID
	var w := k18[c - 1] == LIQUID
	var e := k18[c + 1] == LIQUID
	var nw := k18[c - 19] == LIQUID
	var ne := k18[c - 17] == LIQUID
	var sw := k18[c + 17] == LIQUID
	var se := k18[c + 19] == LIQUID
	const BIG := 99.0
	var s31 := _sterm(31)
	var s33 := _sterm(33)
	var s34 := _sterm(34)
	for y in T:
		var gy := ty * T + y
		var yb := ((gy & M32) * HY) & M32
		var orow := (oy + y) * W + ox
		for x in T:
			# rounded outer corners: the floor below shows through
			if not n and not w and x + y < 3:
				continue
			if not n and not e and (T - 1 - x) + y < 3:
				continue
			if not s and not w and x + (T - 1 - y) < 3:
				continue
			if not s and not e and (T - 1 - x) + (T - 1 - y) < 3:
				continue
			var d := minf(minf(BIG if n else float(y), BIG if s else float(T - 1 - y)),
				minf(BIG if w else float(x), BIG if e else float(T - 1 - x)))
			if n and w and not nw:
				d = minf(d, sqrt(float(x * x + y * y)) - 0.5)
			if n and e and not ne:
				d = minf(d, sqrt(float((T - 1 - x) * (T - 1 - x) + y * y)) - 0.5)
			if s and w and not sw:
				d = minf(d, sqrt(float(x * x + (T - 1 - y) * (T - 1 - y))) - 0.5)
			if s and e and not se:
				d = minf(d, sqrt(float((T - 1 - x) * (T - 1 - x) + (T - 1 - y) * (T - 1 - y))) - 0.5)
			var gx := tx * T + x
			var xa := ((gx & M32) * HX) & M32
			var h := xa ^ yb ^ s31
			h = ((h ^ (h >> 13)) * HM) & M32
			h ^= h >> 16
			var r := h * INV32
			var col: int
			if d < 1.0:
				col = I_SHORE                  # earth lip
			elif d < 2.0:
				col = I_FOAM
			elif d < 4.0:
				col = I_LLIGHT                 # shallow
			elif d < 6.0:
				col = I_LIQ if r < 0.5 else I_LLIGHT
			else:
				col = I_LIQ if (d < 8.0 and r < 0.5) else I_LDEEP
			if d >= 6.0 and d < BIG and r < 0.08:
				col = I_LIQ
			if d >= 3.0:
				# loose waves: short horizontal 3-px strokes, few
				if (gx & 3) != 3:
					var q := (((((gx >> 2) & M32) * HX) & M32) ^ yb ^ s33)
					q = ((q ^ (q >> 13)) * HM) & M32
					q ^= q >> 16
					if q * INV32 < 0.045:
						col = I_LLIGHT
				var g := xa ^ yb ^ s34
				g = ((g ^ (g >> 13)) * HM) & M32
				g ^= g >> 16
				if g * INV32 < 0.004:
					col = I_FOAM
			out[orow + x] = col
