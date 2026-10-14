class_name LiquidLayer
extends Node2D
## Animated glints on water / bubbles on lava, poison and sparks (world.js drawLiquid, §7.7).
## Child of WorldView drawn behind it, right after GroundLayer. The per-tile hashes (phase and
## glint position) are cached per chunk.

const PX := 2.0

var sim: Sim
var _cache: Dictionary = {}        # Vector2i -> PackedFloat64Array [x, y, ph, sx, sy] per liquid tile
var _ver := -1
var _purge := -1

func _ready() -> void:
	show_behind_parent = true

func _process(_dt: float) -> void:
	queue_redraw()

func _tiles(cx: int, cy: int) -> PackedFloat64Array:
	var k := Vector2i(cx, cy)
	var c: PackedFloat64Array = _cache.get(k, PackedFloat64Array())
	if not c.is_empty() or _cache.has(k):
		return c
	var liq := sim.world.liquids_of(cx, cy)
	if liq.is_empty() and not sim.world.has_chunk(cx, cy):
		return c                       # not generated yet: try again next frame
	for i in range(0, liq.size(), 2):
		var tx := liq[i]
		var ty := liq[i + 1]
		var x := tx * WorldMap.TS
		var y := ty * WorldMap.TS
		c.append_array([x, y, U.hash01(tx, ty, 77) * 6.28, x + floorf(U.hash01(tx, ty, 78) * 12.0 + 2.0) * PX,
			y + floorf(U.hash01(tx, ty, 79) * 12.0 + 2.0) * PX])
	_cache[k] = c
	return c

var draw_us_acc := 0             # read and reset by GroundLayer.take_perf ([perf] line)
var draw_us_max := 0

func _draw() -> void:
	var t0 := Time.get_ticks_usec()
	_draw_liquid()
	var us := Time.get_ticks_usec() - t0
	draw_us_acc += us
	draw_us_max = maxi(draw_us_max, us)

func _draw_liquid() -> void:
	if sim == null or not (sim.player != null or sim.state == "ui"):
		return
	var w := sim.world
	if w.terrain_version != _ver or w.purge_serial != _purge:
		_ver = w.terrain_version
		_purge = w.purge_serial
		_cache.clear()
	var B: Dictionary = Data.biomes[w.biome]
	var liq: String = B["liquid"]
	var hot := liq == "lava" or liq == "poison" or liq == "spark"
	var foam := Color.html(B["foam"])
	var t := Time.get_ticks_msec() / 1000.0
	var c := sim.cam
	var CW := WorldMap.CW
	var TS := WorldMap.TS
	var speed := 2.2 if hot else 1.6
	var ww := PX * (2.0 if hot else 3.0)
	for cy in range(int(floorf(c.top() / CW)), int(floorf((c.top() + c.h) / CW)) + 1):
		for cx in range(int(floorf(c.left() / CW)), int(floorf((c.left() + c.w) / CW)) + 1):
			var a := _tiles(cx, cy)
			for i in range(0, a.size(), 5):
				var x := a[i]
				var y := a[i + 1]
				if not c.sees(x + TS / 2.0, y + TS / 2.0, TS):
					continue
				var k := (sin(t * speed + a[i + 2]) + 1.0) / 2.0
				var col := Color(foam, 0.35 + k * 0.5 if hot else k * 0.7)
				var sx := a[i + 3]
				var sy := a[i + 4]
				draw_rect(Rect2(sx + U.jround(k * 2.0) * PX, sy, ww, PX), col)
				if hot and k > 0.8:
					draw_rect(Rect2(sx, sy - PX * 2.0, PX, PX), col)
