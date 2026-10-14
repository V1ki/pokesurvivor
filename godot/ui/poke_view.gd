class_name PokeView
extends Control
## An animated Pokémon inside a UI box (G.UI.sprite / spriteCanvas, js/ui/ui.js).
##   preview mode (default; grids, gacha cards): the per-generation Idle strip (direction Down),
##     ~10 KB of texture per species instead of the whole species atlas.
##   full mode (full = true; menu partner card, collection detail, results): PmdAnimator over the
##     species atlas, with lively (attacks now and then) and spin (turns around).
## Integer pixel scale; hero = the scale may shrink so a big species fits (only one on screen).

var dex := 0
var shiny := false
var silhouette := false
var lively := false
var spin := false
var hero := false
var full := false
var px := 2                   # art-pixel scale (2 = in-game size)
var shadow := true
var dir := 0
var stage := false            # PMD "stage" box behind the Pokémon
var stage_color := Color.html("#5b83d6")

var _anim: PmdAnimator = null
var _t := 0.0
var _frame := 0
var _ft := 0.0
var _spin_t := 0.0
var _act_t := 0.0
var _tw: Array = []
var _spark_t := 0.0

static func make(dex_: int, w: float, h: float, opts := {}) -> PokeView:
	var v := PokeView.new()
	v.custom_minimum_size = Vector2(w, h)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for k in opts:
		v.set(k, opts[k])
	v.set_dex(dex_, opts.get("shiny", false))
	return v

func set_dex(d: int, sh := false) -> void:
	dex = d
	shiny = sh and Sprites.has_shiny(d)
	_frame = 0
	_ft = 0.0
	_act_t = randf_range(1.0, 3.0)
	_tw.clear()
	if full or lively or spin:
		full = true
		_anim = PmdAnimator.new(dex, 1.0, shiny)
		_anim.dir = dir
		_anim.loop("Idle")
	else:
		_anim = null
	queue_redraw()

func _process(dt: float) -> void:
	if dex <= 0 or not is_visible_in_tree():
		return
	_t += dt
	if _anim != null:
		_anim.update(dt)
		if lively:
			_act_t -= dt
			if _act_t <= 0.0:
				_act_t = randf_range(2.5, 4.5)
				_anim.play(["Attack", "Shoot", "Charge"].pick_random())
		if spin:
			_spin_t += dt
			if _spin_t > 1.4:
				_spin_t = 0.0
				_anim.dir = (_anim.dir + 7) % 8
	else:
		var m := Sprites.anim_meta(dex, "Idle", shiny)
		if not m.is_empty():
			_ft += dt * 60.0
			var d: Array = m["d"]
			var guard := 0
			while _ft >= float(d[_frame % d.size()]) and guard < 32:
				_ft -= float(d[_frame % d.size()])
				_frame = (_frame + 1) % int(m["n"])
				guard += 1
	if shiny and not silhouette:
		_spark_t -= dt
		if _spark_t <= 0.0 and _tw.size() < 4:
			_spark_t = randf_range(0.18, 0.45)
			_tw.append({"x": size.x / 2.0 + randf_range(-0.32, 0.32) * size.x, "y": randf_range(0.12, 0.7) * size.y,
				"t": 0.0, "life": randf_range(0.5, 0.8)})
		for i in range(_tw.size() - 1, -1, -1):
			_tw[i]["t"] += dt
			if _tw[i]["t"] >= _tw[i]["life"]:
				_tw.remove_at(i)
	queue_redraw()

func _draw() -> void:
	if stage:
		_draw_stage()
	if dex <= 0:
		return
	var idle := Sprites.anim_meta(dex, "Idle", shiny)
	if idle.is_empty():
		return
	var ay := float(idle["ay"])
	var k := float(px)
	if hero:
		k = maxf(1.0, minf(k, floor(size.y * 0.8 / ay)))
	var big := ay * k > size.y * 0.8
	var fx := size.x / 2.0
	var fy := (size.y / 2.0 + ay * k * 0.45) if big else size.y * 0.88
	if shadow and not silhouette:
		DrawUtil.ellipse(self, fx, fy, 9.0 * k, 3.4 * k, Color(0, 0, 0, 0.35))
	var mod := Color(0, 0, 0, 0.55) if silhouette else Color.WHITE
	if _anim != null:
		var m := _anim.meta()
		var s := Sprites.sheet(dex, _anim.cur, shiny)
		var frame := _anim.frame
		var row := _anim.dir
		if s == null or s.state != Sprites.READY:
			s = Sprites.sheet(dex, "Idle", shiny)
			m = idle
			frame = 0
		if s != null and s.state == Sprites.READY and not m.is_empty():
			_blit(s.tex, m, mini(frame, int(m["n"]) - 1), mini(row, int(m["r"]) - 1), fx, fy, k, mod)
	else:
		var p := Sprites.preview(dex, shiny)
		if p != null and p.state == Sprites.READY:
			_blit(p.tex, idle, _frame % int(idle["n"]), 0, fx, fy, k, mod)
	if shiny and not silhouette:
		for w in _tw:
			_twinkle(w["x"], w["y"], w["t"] / w["life"], maxf(2.0, k))

func _blit(tex: Texture2D, m: Dictionary, frame: int, row: int, fx: float, fy: float, k: float, mod: Color) -> void:
	var w := float(m["w"])
	var h := float(m["h"])
	var src := Rect2(frame * w, row * h, w, h)
	var dst := Rect2(round(fx - float(m["ax"]) * k), round(fy - float(m["ay"]) * k), w * k, h * k)
	draw_texture_rect_region(tex, dst, src, mod)

func _draw_stage() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if shiny:
		# .stage.shiny: box-shadow 0 0 22px rgba(154,230,255,.55) around the 3 px dark ring
		var glow := UIKit.sb(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 14)
		glow.shadow_color = Color(154 / 255.0, 230 / 255.0, 1.0, 0.55)
		glow.shadow_size = 22
		draw_style_box(glow, r)
	var sbx := UIKit.sb(Color(14 / 255.0, 25 / 255.0, 56 / 255.0, 0.92), stage_color, 3, 14)
	sbx.shadow_color = UIKit.EDGE_OUT
	sbx.shadow_size = 3
	draw_style_box(sbx, r)
	DrawUtil.ellipse(self, size.x / 2.0, size.y * 0.86, size.x * 0.42, size.y * 0.12, Color(120 / 255.0, 170 / 255.0, 1.0, 0.12))

## Shiny sparkle (icons.js twinkle).
func _twinkle(x: float, y: float, phase: float, p: float) -> void:
	var st := 0 if phase < 0.15 else (1 if phase < 0.32 else (2 if phase < 0.62 else (1 if phase < 0.82 else 0)))
	var X: float = round(x / p) * p
	var Y: float = round(y / p) * p
	var arm := Color.html("#fff3a8")
	var tip := Color.html("#9ae6ff")
	draw_rect(Rect2(X, Y, p, p), Color.WHITE)
	if st >= 1:
		for o in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			draw_rect(Rect2(X + o.x * p, Y + o.y * p, p, p), arm)
	if st >= 2:
		for o in [Vector2(2, 0), Vector2(-2, 0), Vector2(0, 2), Vector2(0, -2)]:
			draw_rect(Rect2(X + o.x * p, Y + o.y * p, p, p), arm)
		for o in [Vector2(3, 0), Vector2(-3, 0), Vector2(0, 3), Vector2(0, -3), Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			draw_rect(Rect2(X + o.x * p, Y + o.y * p, p, p), tip)
