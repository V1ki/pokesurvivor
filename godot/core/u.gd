class_name U
extends RefCounted
## Shared helpers (port of js/core/util.js, G.U). Bit-exact 32-bit hashing (§10.4)
## and JS numeric semantics where they matter.

const M32 := 0xFFFFFFFF
## Height at which projectiles/effects are drawn above the ground plane (G.LIFT).
const LIFT := 18.0
## JS code uses the literal 6.2832 for a full turn in many places; keep it identical.
const TAU_JS := 6.2832

# ---------------- 32-bit integer math ----------------

## Math.imul on 64-bit ints (never overflows int64). Result in [0, 2^32).
static func imul32(a: int, b: int) -> int:
	a &= M32
	b &= M32
	return ((a & 0xFFFF) * b + ((((a >> 16) * b) & 0xFFFF) << 16)) & M32

## G.U.hash(x, y, seed) -> [0,1). Pass ints (JS `x|0` truncates toward zero: use int(x)).
static func hash01(x: int, y: int, seed: int = 0) -> float:
	var h := imul32(x, 374761393) ^ imul32(y, 668265263) ^ imul32(seed, 2246822519)
	h = imul32(h ^ (h >> 13), 1274126177)
	h ^= h >> 16
	return float(h) / 4294967296.0

# ---------------- float helpers ----------------

static func clampf_(v: float, a: float, b: float) -> float:
	return a if v < a else (b if v > b else v)

static func lerpf_(a: float, b: float, t: float) -> float:
	return a + (b - a) * t

## Frame-rate independent interpolation (G.U.damp).
static func damp(a: float, b: float, rate: float, dt: float) -> float:
	return b + (a - b) * exp(-rate * dt)

## JS Math.round: halves round toward +infinity.
static func jround(x: float) -> float:
	return floor(x + 0.5)

static func jroundi(x: float) -> int:
	return int(floor(x + 0.5))

## Number.prototype.toFixed(2) then unary + (used by defFor shotCd).
static func round2(x: float) -> float:
	return floor(x * 100.0 + 0.5) / 100.0

static func dist(ax: float, ay: float, bx: float, by: float) -> float:
	return sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay))

static func dist2(ax: float, ay: float, bx: float, by: float) -> float:
	var dx := bx - ax
	var dy := by - ay
	return dx * dx + dy * dy

## Normalized vector, or (0,0) if null (G.U.norm). Returned as doubles in an Array-free struct.
static func norm(x: float, y: float) -> Vector2:
	var m := sqrt(x * x + y * y)
	return Vector2(x / m, y / m) if m > 1e-6 else Vector2.ZERO

## "3:07" from seconds.
static func mmss(s: float) -> String:
	var m := int(floor(s / 60.0))
	return "%d:%02d" % [m, int(floor(fmod(s, 60.0)))]

# ---------------- randomness (Math.random based in JS) ----------------

static func rand(a: float, b: float) -> float:
	return a + randf() * (b - a)

static func rand_int(a: int, b: int) -> int:
	return randi_range(a, b)

static func pick(arr: Array) -> Variant:
	return arr[randi() % arr.size()] if arr.size() > 0 else null

## n distinct random elements (G.U.pickN).
static func pick_n(arr: Array, n: int) -> Array:
	var c := arr.duplicate()
	var out: Array = []
	while out.size() < n and c.size() > 0:
		out.append(c.pop_at(randi() % c.size()))
	return out

# ---------------- colors ----------------

static func col(hex: String) -> Color:
	return Color.html(hex)

## Same as JS `rgba(r,g,b,a)` strings.
static func rgba(r: int, g: int, b: int, a: float) -> Color:
	return Color8(r, g, b, int(round(a * 255.0)))
