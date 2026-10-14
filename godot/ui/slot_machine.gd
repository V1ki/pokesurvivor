class_name SlotMachine
extends Control
## Pixel-art gacha slot machine (port of js/ui/slots.js). Drawn at art resolution (176x170) and
## scaled by an integer factor `k`. The pull is already resolved; this is cosmetic:
## lever -> 3 reels spin -> stop one by one on the rarity symbol (Poké / Great / Ultra / Luxury /
## Master Ball, red star = shiny). For Epic, Legendary or shiny the last reel slows down and the
## lights go crazy. x10 = 10 quick spins, each prize drops as a ball into the tray. Click = faster.

signal finished

const W := 176
const H := 170
const CELL := 30
const STRIP := ["ball", "ball2", "ball", "ball3", "ball", "ball2", "ballLux", "ball", "ball4", "ball2", "ball3", "shiny", "ball", "ball2"]
const REEL_X := [26, 65, 104]
const REEL_W := 36
const REEL_Y := 44
const REEL_H := 46
const MID := REEL_Y + REEL_H / 2
const C := {
	"body": "#c8323c", "bodyD": "#8e1f2a", "bodyL": "#ef6464", "trim": "#ffd23f", "trimD": "#c08a10",
	"dark": "#1b1528", "glass": "#0d1230", "reel": "#f4efe2", "reelD": "#c9c1ad", "chrome": "#c9d2de", "chromeD": "#7d8899",
	"led": "#2a0f14", "bulbOn": "#ffe9a0", "bulbOff": "#6b4a20",
}

var k := 3
var fast := false
var running := false
var st: Dictionary = {}
var _col: Dictionary = {}

func _ready() -> void:
	for key in C:
		_col[key] = Color.html(C[key])
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(func(ev: InputEvent):
		if (ev is InputEventMouseButton and ev.pressed) or (ev is InputEventScreenTouch and ev.pressed):
			fast = true)
	set_scale_k(k)

func set_scale_k(kk: int) -> void:
	k = kk
	custom_minimum_size = Vector2(W * k, H * k)

static func sym_of(r: Dictionary) -> String:
	return "shiny" if r["shiny"] else str(Data.icons["rarity_ball"][str(r["rarity"])])

static func col_of(r: Dictionary) -> Color:
	return UIKit.SHINY if r["shiny"] else Gacha.rarity_color(int(r["rarity"]))

## Animates the pulls; emits `finished` (and returns) at the end.
func play(results: Array) -> void:
	fast = false
	running = true
	var ten := results.size() == 10
	st = {"t": 0.0, "lever": 0.0, "reels": [], "ten": ten, "tray": [], "led": "TIRADA ×10" if ten else "¡SUERTE!",
		"led_col": _col["bulbOn"], "win": {}, "frenzy": 0, "sparks": []}
	for i in 3:
		st["reels"].append({"off": randf() * 400.0, "spin": false, "sym": "ball", "bounce": 0.0, "speed": 0.0})
	for i in results.size():
		var r: Dictionary = results[i]
		if ten:
			st["led"] = "TIRADA %d/10" % (i + 1)
		Sfx.play("ball")
		await _tween(func(v): st["lever"] = v, 0.0, 1.0, 0.12 if ten else 0.22)
		for rl in st["reels"]:
			rl["spin"] = true
			rl["speed"] = 520.0
		await _tween(func(v): st["lever"] = v, 1.0, 0.0, 0.1 if ten else 0.2)
		st["win"] = {}
		await _wait(0.18 if ten else 0.6)
		var big: bool = int(r["rarity"]) >= 4 or r["shiny"]
		for kk in 3:
			if kk == 2 and big:
				# suspense: the last reel brakes slowly and the lights blink
				st["frenzy"] = 1
				st["led"] = "¡¿SHINY?!" if r["shiny"] else ("¡¿LEGENDARIO?!" if int(r["rarity"]) == 5 else "¡¿ÉPICO?!")
				st["led_col"] = col_of(r)
				await _tween(func(v): st["reels"][2]["speed"] = v, 520.0, 120.0, 0.5 if ten else 1.1)
			var rl: Dictionary = st["reels"][kk]
			rl["spin"] = false
			rl["sym"] = sym_of(r)
			rl["bounce"] = 1.0
			rl["speed"] = 0.0
			Sfx.play("shake")
			await _wait(0.08 if ten else 0.32)
		st["frenzy"] = 0
		st["win"] = {"col": col_of(r), "t": 0.0}
		st["led"] = ("SHINY · " if r["shiny"] else "") + Gacha.rarity_name(int(r["rarity"])).to_upper()
		st["led_col"] = col_of(r)
		Sfx.play("reveal", {"rarity": int(r["rarity"])})
		if int(r["rarity"]) == 5:
			Sfx.play("legend")
		if r["shiny"]:
			Sfx.play("shiny")
		if big:
			_burst(col_of(r), 60 if int(r["rarity"]) == 5 or r["shiny"] else 30)
		st["tray"].append({"sym": sym_of(r), "y": 104.0, "vy": 0.0, "done": false})
		await _wait((0.7 if big else 0.28) if ten else 1.0)
	await _wait(0.4)
	running = false
	finished.emit()

func _wait(s: float) -> void:
	await get_tree().create_timer(s * (0.25 if fast else 1.0)).timeout

func _tween(set_v: Callable, a: float, b: float, dur: float) -> void:
	var t0 := Time.get_ticks_msec()
	var d := dur * 1000.0 * (0.25 if fast else 1.0)
	while true:
		var kk := minf(1.0, (Time.get_ticks_msec() - t0) / d)
		set_v.call(a + (b - a) * kk)
		if kk >= 1.0:
			break
		await get_tree().process_frame

func _burst(col: Color, n: int) -> void:
	for i in n:
		var a := randf() * TAU
		var s := 30.0 + randf() * 70.0
		st["sparks"].append({"x": W / 2.0, "y": float(MID), "vx": cos(a) * s, "vy": sin(a) * s - 30.0, "t": 0.0,
			"life": 0.6 + randf() * 0.6, "col": col if randf() < 0.5 else Color.WHITE})

func _process(delta: float) -> void:
	if st.is_empty():
		return
	var dt := minf(0.05, delta) * (2.0 if fast else 1.0)
	st["t"] += dt
	var tick := false
	for rl in st["reels"]:
		if rl["spin"]:
			var before := int(floor(rl["off"] / CELL))
			rl["off"] += rl["speed"] * dt
			if int(floor(rl["off"] / CELL)) != before:
				tick = true
		if rl["bounce"] > 0.0:
			rl["bounce"] = maxf(0.0, rl["bounce"] - dt * 5.0)
	if tick and randf() < 0.5:
		Sfx.play("hover")
	if not st["win"].is_empty():
		st["win"]["t"] += dt
	for b in st["tray"]:
		if not b["done"]:
			b["vy"] += 400.0 * dt
			b["y"] += b["vy"] * dt
			if b["y"] >= 132.0:
				b["y"] = 132.0
				b["vy"] *= -0.35
				if absf(b["vy"]) < 20.0:
					b["done"] = true
	for p in st["sparks"]:
		p["t"] += dt
		p["x"] += p["vx"] * dt
		p["y"] += p["vy"] * dt
		p["vy"] += 120.0 * dt
	st["sparks"] = st["sparks"].filter(func(p): return p["t"] < p["life"])
	queue_redraw()

# ---------------- drawing (art pixels; the canvas transform scales by k) ----------------

func R(x: float, y: float, w: float, h: float, c: Variant, a := 1.0) -> void:
	var col: Color = _col[c] if c is String and _col.has(c) else (Color.html(c) if c is String else c)
	draw_rect(Rect2(x, y, w, h), Color(col, col.a * a))

func _draw() -> void:
	if st.is_empty():
		return
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(k, k))
	var t: float = st["t"]
	# --- cabinet ---
	R(10, 30, 142, 132, "dark")
	R(11, 31, 140, 130, "body")
	R(11, 31, 6, 130, "bodyL")
	R(145, 31, 6, 130, "bodyD")
	R(11, 155, 140, 6, "bodyD")
	R(10, 162, 142, 3, "dark")
	# --- sign with bulbs ---
	R(14, 4, 134, 28, "dark")
	R(15, 5, 132, 26, "trimD")
	R(18, 8, 126, 20, "led")
	var win_col: Variant = null
	if not st["win"].is_empty() and int(floor(st["win"]["t"] * 8.0)) % 2 == 0:
		win_col = st["win"]["col"]
	var i := 0
	for x in range(16, 146, 7):
		_bulb(x, 5, i, win_col)
		i += 1
		_bulb(x, 29, i, win_col)
		i += 1
	for y in range(12, 28, 7):
		_bulb(15, y, i, win_col)
		i += 1
		_bulb(146, y, i, win_col)
		i += 1
	DrawUtil.text(self, "POKé SLOTS", W / 2.0 + 1.0, 23.0, 12, _col["dark"])
	DrawUtil.text(self, "POKé SLOTS", W / 2.0, 22.0, 12, _col["trim"])
	# --- reel window ---
	R(20, 38, 122, 58, "dark")
	R(21, 39, 120, 56, "trimD")
	R(23, 41, 116, 52, "glass")
	for kk in 3:
		_reel(st["reels"][kk], REEL_X[kk])
	var line_col: Color = st["win"]["col"] if not st["win"].is_empty() else Color.html("#ff5f6d")
	R(22, MID - 1, 3, 2, line_col)
	R(137, MID - 1, 3, 2, line_col)
	if not st["win"].is_empty() and st["win"]["t"] < 1.2 and int(floor(st["win"]["t"] * 10.0)) % 2 == 0:
		draw_rect(Rect2(22, 40, 118, 54), Color(st["win"]["col"], 0.5), false, 2.0)
	# --- LED board ---
	R(36, 100, 90, 16, "dark")
	R(37, 101, 88, 14, "led")
	if not st["frenzy"] or int(floor(t * 10.0)) % 2 == 0:
		DrawUtil.text(self, str(st["led"]), 81.0, 111.0, 8, st["led_col"])
	R(132, 102, 8, 6, "trim")
	R(132, 108, 8, 2, "trimD")
	R(22, 102, 8, 6, "#5fe08a")
	R(22, 108, 8, 2, "#2f9a52")
	# --- tray ---
	R(26, 122, 110, 26, "dark")
	R(28, 124, 106, 22, "#0a0712")
	R(28, 144, 106, 2, "chromeD")
	var j := 0
	for b in st["tray"]:
		var one: bool = not st["ten"]
		var x := (81.0 - 12.0) if one else 30.0 + j * 10.0
		var size := 24.0 if one else 12.0
		Icons.draw(self, b["sym"], x, round(b["y"] - (10.0 if one else 0.0)), size)
		j += 1
	# --- lever ---
	R(152, 74, 14, 24, "dark")
	R(153, 75, 12, 22, "chrome")
	R(160, 75, 5, 22, "chromeD")
	var knob_y := int(round(34.0 + st["lever"] * 48.0))
	var top := mini(knob_y, 82)
	var bot := maxi(knob_y, 82)
	R(157, top, 4, bot - top, "chromeD")
	R(157, top, 2, bot - top, "chrome")
	_disc(159, knob_y, 6, _col["dark"])
	_disc(159, knob_y, 5, Color.html("#ff4d4d"))
	R(156, knob_y - 3, 2, 2, "#ffd0d0")
	# --- prize sparks ---
	for p in st["sparks"]:
		R(round(p["x"]), round(p["y"]), 2, 2, p["col"])
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _bulb(x: int, y: int, i: int, win_col: Variant) -> void:
	var on: bool
	if st["frenzy"]:
		on = int(floor(st["t"] * 14.0 + i)) % 2 == 0
	else:
		on = int(floor(st["t"] * 4.0 + i)) % 3 != 0
	R(x, y, 3, 3, win_col if win_col != null else (_col["bulbOn"] if on else _col["bulbOff"]))

func _disc(cx: int, cy: int, r: int, col: Color) -> void:
	for y in range(-r, r + 1):
		var w := int(round(sqrt(r * r - y * y)))
		draw_rect(Rect2(cx - w, cy + y, w * 2, 1), col)

## Icon clipped to the reel window (canvas clip() in JS).
func _icon_clip(name: String, x: float, y: float, size: float, clip: Rect2, a := 1.0) -> void:
	var tex := Icons.tex(name)
	var s2 := Icons.snap(name, size)
	x += (size - s2) / 2.0
	y += (size - s2) / 2.0
	var dst := Rect2(round(x), round(y), s2, s2)
	var vis := dst.intersection(clip)
	if vis.size.x <= 0.0 or vis.size.y <= 0.0:
		return
	var f := tex.get_width() / s2
	var src := Rect2((vis.position - dst.position) * f, vis.size * f)
	draw_texture_rect_region(tex, vis, src, Color(1, 1, 1, a))

func _reel(rl: Dictionary, x: int) -> void:
	var clip := Rect2(x, REEL_Y, REEL_W, REEL_H)
	R(x, REEL_Y, REEL_W, REEL_H, "reel")
	if rl["spin"]:
		var base: float = fmod(float(rl["off"]), float(CELL))
		var i0 := int(floor(rl["off"] / CELL))
		for kk in range(-2, 3):
			var nm: String = STRIP[posmod(i0 - kk, STRIP.size())]
			var y := roundf(MID - 12.0 + kk * CELL + base)
			var fastr: bool = rl["speed"] > 300.0
			_icon_clip(nm, x + 6, y, 24, clip, 0.75 if fastr else 1.0)
			if fastr:
				_icon_clip(nm, x + 6, y - 6, 24, clip, 0.25)
	else:
		var by: float = round(sin(float(rl["bounce"]) * PI) * 5.0)
		var n := STRIP.find(rl["sym"])
		_icon_clip(STRIP[(n + 3) % STRIP.size()], x + 6, MID - 12 - CELL + by, 24, clip, 0.35)
		_icon_clip(STRIP[(n + 5) % STRIP.size()], x + 6, MID - 12 + CELL + by, 24, clip, 0.35)
		_icon_clip(rl["sym"], x + 6, MID - 12 + by, 24, clip)
	# curved reel shading
	R(x, REEL_Y, REEL_W, 6, "reelD", 0.28)
	R(x, REEL_Y + REEL_H - 6, REEL_W, 6, "reelD", 0.28)
	R(x, REEL_Y, REEL_W, 3, Color.BLACK, 0.18)
	R(x, REEL_Y + REEL_H - 3, REEL_W, 3, Color.BLACK, 0.18)
	R(x - 1, REEL_Y, 1, REEL_H, "dark")
	R(x + REEL_W, REEL_Y, 1, REEL_H, "dark")
