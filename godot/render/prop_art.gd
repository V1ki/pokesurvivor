class_name PropArt
extends RefCounted
## Scenery sprites painted in code (tiles.js PAINT / propSprite, §7.7) and their drawing
## (world.js drawProp). Images are cached by "biome/type/variant" (thread-safe: prewarm() paints a
## whole biome on a worker thread), textures and white hit-flash silhouettes on the main thread.
## Pixel-exact against the JS painters (tests/phase3_tests.gd, SHA-256 per sprite).

const PX := 2.0                   # wu per art pixel (G.Sprites.PX)
const CHEST_TIME := 3.5           # Interact.CHEST_TIME (bigchest unlock ring)
const ORB_COL := ["#ff5f6d", "#5fd4ff", "#ff8ad8", "#ffd23f"]
const NONE := -1
## Variants that exist per type (rock 1 = cracked, grass 1 = swaying, spring 1 = dry,
## altar = power*2 + used, trap = kind, rift = frame).
const VARIANTS := {"tree": [0], "rock": [0, 1], "grass": [0, 1], "chest": [0], "altar": [0, 1, 2, 3, 4, 5, 6, 7],
	"spring": [0, 1], "bigchest": [0], "trap": [0, 1, 2]}

static var _img: Dictionary = {}          # "bi/type/v" -> Image (guarded by _mx)
static var _tex: Dictionary = {}          # main thread: int key -> ImageTexture
static var _white: Dictionary = {}        # main thread: int key -> ImageTexture (white silhouette)
const TYPE_IDX := {"tree": 0, "rock": 1, "grass": 2, "chest": 3, "altar": 4, "spring": 5, "bigchest": 6, "trap": 7, "rift": 8}
static var _mx: Mutex = null              # created on first use, dropped by finish() (no leak at exit)
static var _warm: Dictionary = {}         # bi -> WorkerThreadPool task id

## Art-pixel canvas like tiles.js Pix: colours packed ABGR (little-endian RGBA bytes).
class Pix:
	var w := 0
	var h := 0
	var buf := PackedInt32Array()
	func _init(w_: int, h_: int) -> void:
		w = w_
		h = h_
		buf.resize(w * h)
	func put(x: int, y: int, col: int) -> void:
		if x >= 0 and y >= 0 and x < w and y < h:
			buf[y * w + x] = col
	func alpha(x: int, y: int) -> int:
		return (buf[y * w + x] >> 24) & 255
	func image() -> Image:
		return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, buf.to_byte_array())

static func pack(hex: String) -> int:
	var c := Color.html(hex)
	return c.r8 | (c.g8 << 8) | (c.b8 << 16) | (255 << 24)

static func packs(arr: Array) -> PackedInt64Array:
	var out := PackedInt64Array()
	for h in arr:
		out.append(pack(h))
	return out

static func H(x: int, y: int, s: int) -> float:
	return U.hash01(x, y, s)

# ---------------- cache ----------------

## Image of a sprite (painted on first use; safe from any thread).
static func image(bi: int, type: String, variant := 0) -> Image:
	var k := "%d/%s/%d" % [bi, type, variant]
	var mx := _mutex()
	mx.lock()
	var img: Image = _img.get(k)
	mx.unlock()
	if img != null:
		return img
	img = paint(Data.biomes[bi], type, variant).image()
	mx.lock()
	_img[k] = img
	mx.unlock()
	return img

## The cache mutex. Created on the main thread (prewarm/texture) before any worker uses it.
static func _mutex() -> Mutex:
	if _mx == null:
		_mx = Mutex.new()
	return _mx

## Texture of a sprite (main thread; int keys: this runs for every visible prop every frame).
static func texture(bi: int, type: String, variant := 0) -> Texture2D:
	var k: int = (bi * 16 + int(TYPE_IDX.get(type, 15))) * 16 + variant
	var t: Texture2D = _tex.get(k)
	if t == null:
		t = ImageTexture.create_from_image(image(bi, type, variant))
		_tex[k] = t
	return t

## White silhouette (Sprites.white: source-in white fill) for the hit flash.
static func white(bi: int, type: String, variant := 0) -> Texture2D:
	var k: int = (bi * 16 + int(TYPE_IDX.get(type, 15))) * 16 + variant
	var t: Texture2D = _white.get(k)
	if t == null:
		var img := image(bi, type, variant).duplicate() as Image
		for y in img.get_height():
			for x in img.get_width():
				var a := img.get_pixel(x, y).a
				img.set_pixel(x, y, Color(1, 1, 1, a))
		t = ImageTexture.create_from_image(img)
		_white[k] = t
	return t

## Paints every sprite of a biome on a worker thread (biome changes don't stall a frame).
static func prewarm(bi: int) -> void:
	if bi < 0 or bi >= Data.biomes.size() or _warm.has(bi):
		return
	_mutex()
	_warm[bi] = WorkerThreadPool.add_task(_warm_job.bind(bi), false, "prop sprites")

static func _warm_job(bi: int) -> void:
	for t in VARIANTS:
		for v in VARIANTS[t]:
			image(bi, t, v)

## Waits for the prewarm tasks and drops the caches (call before quitting).
static func finish() -> void:
	for bi in _warm:
		WorkerThreadPool.wait_for_task_completion(_warm[bi])
	_warm.clear()
	_img.clear()
	_tex.clear()
	_white.clear()
	_mx = null

# ---------------- painters (tiles.js PAINT) ----------------

static func paint(B: Dictionary, type: String, variant := 0) -> Pix:
	match type:
		"tree":
			if B["prop"] == "crystal":
				return _crystal(B)
			if B["prop"] == "dead":
				return _deadtree(B)
			return _tree(B)
		"rock":
			return _rock(B, variant)
		"grass":
			return _grass(B, variant)
		"altar":
			return _altar(B, variant)
		"spring":
			return _spring(B, variant)
		"bigchest":
			return _bigchest()
		"trap":
			return _trap(variant)
		"rift":
			return _rift(variant)
		"chest":
			return _chest()
	return Pix.new(1, 1)

## Filled circle: fn(x, y, d/r) -> packed colour or NONE.
static func _disc(P: Pix, cx: float, cy: float, r: float, fn: Callable) -> void:
	for y in range(int(floorf(cy - r)), int(ceilf(cy + r)) + 1):
		for x in range(int(floorf(cx - r)), int(ceilf(cx + r)) + 1):
			var d := sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy))
			if d <= r:
				var c: int = fn.call(x, y, d / r)
				if c != NONE:
					P.put(x, y, c)

## 1-px outline around everything opaque.
static func _outline(P: Pix, col: int) -> void:
	var marks: Array[Vector2i] = []
	for y in P.h:
		for x in P.w:
			if P.alpha(x, y) != 0:
				continue
			if (x + 1 < P.w and P.alpha(x + 1, y) != 0) or (x > 0 and P.alpha(x - 1, y) != 0) \
					or (y + 1 < P.h and P.alpha(x, y + 1) != 0) or (y > 0 and P.alpha(x, y - 1) != 0):
				marks.append(Vector2i(x, y))
	for m in marks:
		P.put(m.x, m.y, col)

static func _tree(B: Dictionary) -> Pix:
	var P := Pix.new(30, 40)
	var L := packs(B["leaf"])
	var Tr := packs(B["trunk"])
	for y in range(26, 38):
		for x in range(13, 18):
			P.put(x, y, Tr[0] if (x == 13 or x == 17) else Tr[1])
	P.put(12, 37, Tr[0])
	P.put(18, 37, Tr[0])
	P.put(11, 38, Tr[0])
	P.put(19, 38, Tr[0])
	for bl in [[15, 20, 10], [9, 16, 7], [21, 16, 7], [15, 10, 8], [10, 23, 6], [20, 23, 6]]:
		var bx: float = bl[0]
		var by: float = bl[1]
		var br: float = bl[2]
		_disc(P, bx, by, br, func(x: int, y: int, _d: float) -> int:
			# light from the top left
			var lit := ((x - bx) * -0.6 + (y - by) * -0.8) / br
			var idx := 3 if lit > 0.45 else (2 if lit > 0.05 else (1 if lit > -0.45 else 0))
			return L[idx - 1] if (H(x, y, 41) < 0.12 and idx > 0) else L[idx])
	_outline(P, pack("#14200f"))
	return P

static func _crystal(B: Dictionary) -> Pix:
	var P := Pix.new(26, 40)
	var L := packs(B["leaf"])
	var D := packs(B["trunk"])
	for sp in [[13, 2, 5, 38], [7, 14, 4, 38], [19, 12, 4, 38]]:
		var cx: int = sp[0]
		var top: int = sp[1]
		var half: int = sp[2]
		var bot: int = sp[3]
		for y in range(top, bot + 1):
			var t := minf(1.0, (y - top) / 8.0)
			var hw := U.jroundi(half * t)
			for x in range(cx - hw, cx + hw + 1):
				var side := (3 if x == cx - hw else 2) if x < cx else (1 if x == cx else 0)
				P.put(x, y, L[side] if side >= 2 else (D[1] if y > bot - 4 else L[side]))
	_outline(P, D[0])
	return P

static func _deadtree(B: Dictionary) -> Pix:
	var P := Pix.new(28, 40)
	var Tr := packs(B["trunk"])
	var L := packs(B["leaf"])
	for y in range(12, 38):
		for x in range(12, 16):
			P.put(x, y, Tr[0] if x < 14 else Tr[1])
	for br in [[12, 20, -1, 9], [15, 17, 1, 10], [13, 13, -1, 7], [14, 12, 1, 6]]:
		for i in int(br[3]):
			P.put(br[0] + br[2] * i, br[1] - i, L[1])
			P.put(br[0] + br[2] * i, br[1] - i + 1, L[0])
	_outline(P, pack("#0f0b09"))
	return P

static func _rock(B: Dictionary, variant: int) -> Pix:
	var P := Pix.new(22, 17)
	var R := packs(B["rock"])
	# squat boulder: an ellipse wider than tall, flat base
	for y in range(2, 16):
		for x in range(1, 21):
			var nx := (x - 10.5) / 9.5
			var ny := (y - 9.5) / 7.0
			var d := nx * nx + ny * ny + (H(x, y, 61) - 0.5) * 0.08
			if d > 1.0:
				continue
			var lit := -nx * 0.55 - ny * 0.85 + (H(x, y, 62) - 0.5) * 0.25
			var c := R[2] if lit > 0.4 else (R[1] if lit > -0.15 else R[0])
			if y >= 14:
				c = R[0]
			P.put(x, y, c)
	var shine := pack("#ffffff")
	for q in [[6, 5], [7, 5], [6, 6], [8, 4]]:
		P.put(q[0], q[1], shine)
	for q in [[13, 8], [14, 9], [9, 11], [16, 11], [11, 7]]:
		P.put(q[0], q[1], R[0])
	if variant == 1:                      # cracks on the damaged variant
		var dark := pack("#1b1d22")
		for q in [[9, 4], [10, 5], [10, 6], [11, 7], [10, 8], [12, 8], [13, 9], [8, 9], [7, 10]]:
			P.put(q[0], q[1], dark)
	_outline(P, pack("#17191d"))
	return P

static func _grass(B: Dictionary, variant: int) -> Pix:
	# fan of blades leaning outwards, dark base and light tip; variant 1 = wind frame
	var P := Pix.new(20, 17)
	var Gc := packs(B["grass"])
	var dark := pack(B["speck"])
	var sway := 1.2 if variant == 1 else 0.0
	var blades := 11
	for pass_i in 2:                      # the back ones (darker) first
		var b := pass_i
		while b < blades:
			var t := b / float(blades - 1)
			var x0 := 3.0 + t * 13.0 + (H(b, 7, 52) - 0.5) * 2.0
			var hgt := 8 + int(floorf(H(b, 3, 51) * 6.0)) + (3 if absf(t - 0.5) < 0.25 else 0)
			var lean := (t - 0.5) * 7.0 + sway * (0.6 + H(b, 1, 53))
			for i in hgt + 1:
				var k := float(i) / hgt
				var x := U.jroundi(x0 + lean * k * k)
				var y := 16 - i
				var c := Gc[2] if k > 0.78 else (Gc[1] if k > 0.25 else Gc[0])
				if pass_i == 0 and k <= 0.78:
					c = Gc[0]
				P.put(x, y, c)
				if i < hgt * 0.45:
					P.put(x + 1, y, dark if k < 0.15 else Gc[0])
			b += 2
	_outline(P, pack("#0e1d0c"))
	return P

## Power altar: variant = power*2 + (used ? 1 : 0).
static func _altar(B: Dictionary, variant: int) -> Pix:
	var P := Pix.new(18, 27)
	var R := packs(B["rock"])
	var eff := variant >> 1
	var used := variant & 1
	var orb: Array = [["#ff5f6d", "#c23a4b", "#ffd3d8"], ["#5fd4ff", "#2a8fd0", "#d8f6ff"],
		["#ff8ad8", "#b03d84", "#ffe0f4"], ["#ffd23f", "#c08a10", "#fff3b0"]][eff]
	var O := packs(["#6b7380", "#4a505c", "#9aa2ae"] if used else orb)
	# steps, column and slab
	for y in range(21, 26):
		for x in range(1, 17):
			P.put(x, y, R[2] if y == 21 else (R[0] if y >= 24 else R[1]))
	for y in range(12, 21):
		for x in range(5, 13):
			P.put(x, y, R[2] if x == 5 else (R[0] if x >= 11 else R[1]))
	for y in range(10, 12):
		for x in range(3, 15):
			P.put(x, y, R[2] if y == 10 else R[1])
	for q in [[7, 14], [8, 15], [10, 14], [9, 17], [7, 18], [10, 18]]:       # runes
		P.put(q[0], q[1], O[1])
	_disc(P, 8.5, 5.5, 4.2, func(x: int, y: int, d: float) -> int:
		var lit := (8.5 - x) * 0.5 + (5.5 - y) * 0.7
		return O[2] if lit > 1.6 else (O[1] if d > 0.75 else O[0]))
	_outline(P, pack("#120e1a"))
	return P

## Healing spring: variant 1 = dry.
static func _spring(B: Dictionary, variant: int) -> Pix:
	var P := Pix.new(34, 16)
	var R := packs(B["rock"])
	var Wc := packs(["#2f5f68", "#3a6f7a", "#4f8a92"] if variant != 0 else ["#2ba8b8", "#5fe8d8", "#b8fff4"])
	for y in 16:
		for x in 34:
			var nx := (x - 16.5) / 16.5
			var ny := (y - 8) / 7.5
			var d := nx * nx + ny * ny
			if d > 1.0:
				continue
			if d > 0.62:
				P.put(x, y, R[(1 if H(x, y, 71) < 0.5 else 0) + (1 if ny < -0.2 else 0)])
				continue
			var wave := sin(x * 0.7 + y * 1.3) > 0.6
			P.put(x, y, Wc[2] if d < 0.18 else (Wc[2] if wave else (Wc[1] if d < 0.4 else Wc[0])))
	if variant == 0:
		for q in [[10, 6], [11, 5], [22, 9], [23, 8], [16, 11]]:
			P.put(q[0], q[1], pack("#ffffff"))
	_outline(P, pack("#14161c"))
	return P

## Locked chest with a gold padlock.
static func _bigchest() -> Pix:
	var P := Pix.new(24, 20)
	var wood := pack("#6b3a1e")
	var wood_l := pack("#8e5329")
	var wood_d := pack("#432210")
	var iron := pack("#9aa6b5")
	var iron_d := pack("#5d6773")
	var gold := pack("#f2c443")
	var gold_d := pack("#b5832a")
	for y in range(2, 19):
		for x in range(1, 23):
			var c := wood_l if y < 8 else wood
			if y == 8 or y == 9:
				c = iron_d
			if x == 1 or x == 22 or y == 18:
				c = wood_d
			if x == 5 or x == 6 or x == 17 or x == 18:
				c = iron if (x == 5 or x == 17) else iron_d
			if y == 2 and x > 1 and x < 22:
				c = iron
			P.put(x, y, c)
	for x in range(10, 14):              # padlock
		P.put(x, 5, iron)
	P.put(9, 6, iron)
	P.put(14, 6, iron)
	P.put(9, 7, iron)
	P.put(14, 7, iron)
	for y in range(8, 14):
		for x in range(8, 16):
			P.put(x, y, gold if (x + y) % 4 != 0 else gold_d)
	P.put(11, 10, wood_d)
	P.put(12, 10, wood_d)
	P.put(11, 11, wood_d)
	P.put(11, 12, wood_d)
	_outline(P, pack("#1e0f06"))
	return P

## Mystery Dungeon trap: 0 poison, 1 sticky, 2 explosive.
static func _trap(variant: int) -> Pix:
	var P := Pix.new(14, 14)
	var col: Array = [["#b45ec4", "#e6a3f0"], ["#8bd94a", "#d2ff9a"], ["#ff7b3d", "#ffd08a"]][variant]
	var c := pack(col[0])
	var l := pack(col[1])
	var base := pack("#2a2238")
	var base_l := pack("#3b3150")
	for y in range(1, 13):
		for x in range(1, 13):
			var edge := x == 1 or y == 1 or x == 12 or y == 12
			P.put(x, y, c if edge else (base if (x + y) % 2 != 0 else base_l))
	var sym: Array = [
		# poison: dotted skull
		[[5, 4], [6, 4], [7, 4], [8, 4], [4, 5], [9, 5], [4, 6], [6, 6], [7, 6], [9, 6], [5, 7], [8, 7], [5, 8], [6, 8], [7, 8], [8, 8], [5, 9], [8, 9]],
		# sticky: drops
		[[4, 4], [4, 5], [3, 6], [5, 6], [4, 7], [8, 5], [8, 6], [7, 7], [9, 7], [8, 8], [6, 9], [5, 10], [7, 10], [6, 11]],
		# explosive: mine
		[[6, 3], [7, 3], [5, 4], [8, 4], [4, 5], [9, 5], [4, 6], [6, 6], [7, 6], [9, 6], [4, 7], [6, 7], [7, 7], [9, 7], [4, 8], [9, 8], [5, 9], [8, 9], [6, 10], [7, 10]],
	][variant]
	for q in sym:
		P.put(q[0], q[1], l)
	_outline(P, pack("#0c0812"))
	return P

## Rift to the legendary arena: variant = frame 0..3 (no outline).
static func _rift(variant: int) -> Pix:
	var P := Pix.new(30, 46)
	var glow := pack("#7b3cff")
	var mid := pack("#b48aff")
	var core := pack("#140a26")
	var white := pack("#f2e6ff")
	for y in range(2, 44):
		var t := (y - 2) / 42.0
		var w := sin(t * PI) * 9.0 + 1.0
		var off := U.jroundi(sin(t * 9.0 + variant * 1.6) * 2.2 + (H(y, variant, 91) - 0.5) * 2.0)
		var cw := int(ceilf(w))
		for x in range(-cw - 2, cw + 3):
			var ax := absf(x) / w
			var px := 15 + x + off
			if ax <= 0.45:
				P.put(px, y, core)
			elif ax <= 0.75:
				P.put(px, y, white if H(px, y, 92 + variant) < 0.15 else mid)
			elif ax <= 1.15 or H(px, y, 93 + variant) < 0.3:
				P.put(px, y, glow)
	for i in 6:                           # sparks in the middle
		P.put(13 + int(floorf(H(i, variant, 94) * 5.0)), 8 + int(floorf(H(i, variant, 95) * 30.0)), white)
	return P

static func _chest() -> Pix:
	var P := Pix.new(16, 14)
	var gold := pack("#f2c443")
	var gold_d := pack("#b5832a")
	var wood := pack("#8a4f2a")
	var wood_d := pack("#5e3418")
	var lid := pack("#c4662e")
	for y in range(2, 13):
		for x in range(1, 15):
			var c := lid if y < 6 else wood
			if y == 6:
				c = gold_d
			if x == 1 or x == 14:
				c = wood_d
			if (x == 4 or x == 11) and y > 1:
				c = gold if y < 6 else gold_d
			if y == 12:
				c = wood_d
			P.put(x, y, c)
	for x in range(6, 10):
		for y in range(5, 9):
			P.put(x, y, gold if (x + y) % 3 != 0 else gold_d)
	_outline(P, pack("#2a160a"))
	return P

# ---------------- drawing (world.js drawProp) ----------------

static func variant_of(p: WorldProp, t: float) -> int:
	match p.type:
		"grass":
			return 1 if sin(t * 2.4 + p.wiggle) > 0.55 else 0
		"rock":
			return 1 if p.hp < p.max_hp * 0.5 else 0
		"altar":
			return p.kind * 2 + (1 if p.used else 0)
		"spring":
			return 1 if p.charge < 0.15 else 0
		"trap":
			return p.kind
	return 0

## Draws one prop in world space (y-sorted pass). t = real time in seconds.
static func draw(ci: CanvasItem, p: WorldProp, world: WorldMap, t: float) -> void:
	var variant := variant_of(p, t)
	var tex := texture(world.biome, p.type, variant)
	var w := tex.get_width() * PX
	var h := tex.get_height() * PX
	if p.flat:
		# flat ones (spring, trap): stuck to the ground, centred on their tile
		ci.draw_texture_rect(tex, Rect2(U.jround(p.x - w / 2.0), U.jround(p.y - 8.0 - h / 2.0), w, h), false)
		if p.type == "spring" and p.charge >= 0.15 and sin(t * 3.0 + p.wiggle) > 0.92 and Sim.cur != null:
			Sim.cur.fx.twinkle(p.x + U.rand(-20.0, 20.0), p.y - 8.0 + U.rand(-6.0, 6.0))
		return
	if p.type == "altar" and not p.used:
		# orb halo, pulsing
		ci.draw_circle(Vector2(p.x, p.y - h + 11.0 * PX), 13.0, Color(Color.html(ORB_COL[p.kind]), 0.22 + sin(t * 3.0 + p.wiggle) * 0.1))
	if p.type == "bigchest" and p.open > 0.0:
		var sweep := TAU * minf(1.0, p.open / CHEST_TIME)
		ci.draw_arc(Vector2(p.x, p.y - h / 2.0), 26.0, -PI / 2.0, -PI / 2.0 + sweep, maxi(6, int(sweep * 8.0)), Color.html("#ffd23f"), 3.0)
	if p.type != "grass":
		if DrawUtil.flash_marked(ci):
			# shader ellipse on the prop's own texture: shadow + prop are one batch
			DrawUtil.ellipse_t(ci, tex, p.x, p.y, p.r * 1.1, p.r * 0.38, Color(0, 0, 0, 0.3))
		else:
			DrawUtil.ellipse(ci, p.x, p.y, p.r * 1.1, p.r * 0.38, Color(0, 0, 0, 0.3))
	var lift := 4.0 if p.type == "grass" else 2.0
	var x := U.jround(p.x - w / 2.0)
	var y := U.jround(p.y - h + lift)
	var k := world.fade_k()
	var a := 1.0
	if k >= 0.0:
		# the old biome's sprite fades out while the new one fades in
		var old := texture(world.fade_from, p.type, variant)
		var ow := old.get_width() * PX
		var oh := old.get_height() * PX
		ci.draw_texture_rect(old, Rect2(U.jround(p.x - ow / 2.0), U.jround(p.y - oh + lift), ow, oh), false, Color(1, 1, 1, 1.0 - k))
		a = k
	ci.draw_texture_rect(tex, Rect2(x, y, w, h), false, Color(1, 1, 1, a))
	if p.flash > 0.0:
		if DrawUtil.flash_marked(ci):
			# white with the sprite's alpha via the world view's flash shader (no white texture)
			ci.draw_texture_rect(tex, Rect2(x, y, w, h), false, Color(DrawUtil.FLASH_ALPHA, 1, 1, 0.6))
		else:
			ci.draw_texture_rect(white(world.biome, p.type, variant), Rect2(x, y, w, h), false, Color(1, 1, 1, 0.6))
