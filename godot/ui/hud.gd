extends Control
## In-run HUD in screen space (port of js/ui/hud.js, Phase 1 subset): XP bar, name/level,
## HP bar, buff chips, timer + sub-line, banner, move slots (cooldown + level pips,
## tappable), held-item slot, touch pause button, control hint, optional FPS.

const S := 54.0
const GAP := 9.0

var sim: Sim
var touch: TouchInput
var game                           # main.gd (untyped)
var _fps_acc := 0.0                # game.js: frames counted over 0.5 s windows (real time)
var _fps_n := 0
var _fps_shown := 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _process(dt: float) -> void:
	_fps_acc += dt
	_fps_n += 1
	if _fps_acc >= 0.5:
		_fps_shown = roundi(_fps_n / _fps_acc)
		_fps_acc = 0.0
		_fps_n = 0

static func _c(hex: String) -> Color:
	return Color.html(hex)

func _draw() -> void:
	if touch != null:
		touch.clear_buttons()
	if sim == null or sim.player == null or sim.state == "ui":
		return
	var pl := sim.player
	var vs := get_viewport_rect().size
	var w := vs.x
	var h := vs.y
	var is_touch: bool = touch != null and touch.active
	var sa: Dictionary = touch.safe_area() if is_touch else {"top": 0.0, "right": 0.0, "bottom": 0.0, "left": 0.0}

	# ---------- XP bar (top edge, gradient over the full width) ----------
	draw_rect(Rect2(0, 0, w, 7), Color(0, 0, 0, 0.5))
	var xf := clampf(pl.xp / pl.xp_next, 0.0, 1.0)
	if xf > 0.0:
		var c0 := _c("#4fd1ff")
		var c1 := c0.lerp(_c("#a98bff"), xf)
		draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w * xf, 0), Vector2(w * xf, 7), Vector2(0, 7)]),
			PackedColorArray([c0, c1, c1, c0]))

	# ---------- name, level, HP ----------
	var px := 16.0 + float(sa["left"])
	var py := 20.0
	DrawUtil.text(self, str(pl.mon["name"]), px, py + 10, 13, _c("#eaf2ff"), -1, 800)
	DrawUtil.text(self, "Nv. %d" % pl.level, px, py + 26, 11, _c("#ffcb3d"), -1, 700)
	DrawUtil.bar(self, px + 48, py + 17, 168, 11, pl.hp / pl.max_hp, _c("#ff5f6d"))
	DrawUtil.text(self, "%d / %d" % [int(ceil(pl.hp)), U.jroundi(pl.max_hp)], px + 48 + 84, py + 26, 10, Color(1, 1, 1, 0.95), 0, 700)

	# buff chips
	var cols := {"atk": "#ff6b4d", "spd": "#7fe0ff", "def": "#b0b8c8", "regen": "#5fe08a"}
	var lbl := {"atk": "ATK", "spd": "VEL", "def": "DEF", "regen": "REG"}
	var bx := px
	for k in pl.buffs:
		var b: Dictionary = pl.buffs[k]
		if int(b["n"]) <= 0:
			continue
		var txt := "%s ×%d" % [lbl[k], int(b["n"])]
		var tw := DrawUtil.text_width(txt, 9, 800) + 12.0
		DrawUtil.round_rect(self, Rect2(bx, py + 34, tw, 15), 7, Color(0, 0, 0, 0.5))
		DrawUtil.text(self, txt, bx + 6, py + 45, 9, _c(cols[k]), -1, 800)
		bx += tw + 5.0
	bx = EventHud.power_chip(self, pl, bx, py)        # altar power (Phase 3b)

	# ---------- timer / biome / kills ----------
	DrawUtil.text(self, U.mmss(sim.time), w / 2.0, 42, 26, Color(1, 1, 1, 0.95), 0, 800)
	DrawUtil.text(self, "%s  ·  %d DERROTADOS  ·  %d MONEDAS" % [sim.world.biome_name().to_upper(), pl.kills, pl.coins],
		w / 2.0, 58, 10, _c("#8fa3c4"), 0, 600)

	# ---------- weather chip (top right, Phase 3a) ----------
	var wx := sim.weather.current()
	if not wx.is_empty():
		var wtxt := "%s · %ds" % [str(wx["name"]).to_upper(), int(ceilf(float(wx["left"])))]
		var wtw := DrawUtil.text_width(wtxt, 11, 800) + 40.0
		var wx0 := w - wtw - 16.0 - (56.0 if is_touch else 0.0)
		DrawUtil.round_rect(self, Rect2(wx0, 14, wtw, 26), 9, Color(0, 0, 0, 0.55))
		Icons.draw(self, str(wx["icon"]), wx0 + 6.0, 17, 20)
		DrawUtil.text(self, wtxt, wx0 + 32.0, 31, 11, _c(wx["color"]), -1, 800)

	# ---------- boss bar (with its level) / else the wild level (js/ui/hud.js) ----------
	var boss_on := false
	for e in sim.enemies.list:
		if e.boss and not e.dead:
			var bw := minf(420.0, w - 80.0)
			DrawUtil.bar(self, (w - bw) / 2.0, 70, bw, 12, e.hp / e.max_hp, _c("#ffcb3d"))
			var lvl := int(e.def.get("level", 0))
			DrawUtil.text(self, e.name.to_upper() + ((" · NV. %d" % lvl) if lvl > 0 else ""), w / 2.0, 80, 10, _c("#20160a"), 0, 800)
			boss_on = true
			break
	if not boss_on and EnemyDefs.mode == "level" and not sim.rift.in_arena:
		DrawUtil.text(self, "POKÉMON SALVAJES NV. %d" % int(floorf(EnemyDefs.wild_level(sim.time))), w / 2.0, 74, 10, _c("#ffcb3d"), 0, 800)

	# ---------- shinies off-screen: pulsing arrow on the edge ----------
	var cam := sim.cam
	var pulse := 0.6 + sin(Time.get_ticks_msec() / 160.0) * 0.4
	for e in sim.enemies.shinies():
		var sp2 := cam.world_to_screen_steady(e.x, e.y)
		if sp2.x > 0.0 and sp2.x < w and sp2.y > 0.0 and sp2.y < h:
			continue
		var M := 34.0
		var ex := clampf(sp2.x, M, w - M)
		var ey := clampf(sp2.y, M + 60.0, h - M - 70.0)
		var a := atan2(sp2.y - ey, sp2.x - ex)
		var cyan := Color(_c("#9ae6ff"), pulse)
		draw_colored_polygon(PackedVector2Array([Vector2(ex + cos(a) * 24.0, ey + sin(a) * 24.0),
			Vector2(ex + cos(a + 2.5) * 12.0, ey + sin(a + 2.5) * 12.0), Vector2(ex + cos(a - 2.5) * 12.0, ey + sin(a - 2.5) * 12.0)]), cyan)
		Icons.draw(self, "shiny", ex - 12.0, ey - 12.0, 24)

	# ---------- rift arrow / arena timer / events / rift popup (Phase 3b) ----------
	EventHud.draw(self, sim, w, h)

	# ---------- banner ----------
	var sp := sim.spawner
	if sp.announce_t > 0.0:
		var a := minf(1.0, sp.announce_t * 1.6)
		DrawUtil.text(self, sp.announce, w / 2.0, h * 0.3, 22, Color(_c("#ffcb3d"), a), 0, 800, 4, Color(0, 0, 0, 0.7 * a))

	# ---------- move slots ----------
	var n := maxi(1, pl.slots.size())
	var total_w := n * S + (n - 1) * GAP
	var sx := (w - total_w) / 2.0
	var sy := h - S - 18.0 - (minf(28.0, sa["bottom"]) if is_touch else 0.0)
	for i in n:
		var g: Array = pl.slots[i] if i < pl.slots.size() else []
		var m: Dictionary = g[0] if not g.is_empty() else {}
		var fused := g.size() > 1
		var on := i == pl.active
		var x := sx + i * (S + GAP)
		var y := sy - 6.0 if on else sy
		if not m.is_empty() and touch != null:
			var idx := i
			touch.add_button(Rect2(x, y, S, S), func(): _slot_pressed(idx), GAP / 2.0 + 3.0)
		var col := Data.tcolor(m["type"]) if not m.is_empty() else _c("#4a5468")
		var stroke := col if on else Color(140 / 255.0, 170 / 255.0, 210 / 255.0, 0.22)
		if fused:
			stroke = _c("#ff8ad8")
		elif not m.is_empty() and m.get("evolved", false):
			stroke = _c("#ffd23f")
		var lw := 2.5 if on else (2.0 if fused or (not m.is_empty() and m.get("evolved", false)) else 1.2)
		DrawUtil.round_rect(self, Rect2(x, y, S, S), 12, Color(20 / 255.0, 30 / 255.0, 50 / 255.0, 0.95) if on else Color(10 / 255.0, 16 / 255.0, 28 / 255.0, 0.8), stroke, lw)
		if m.is_empty():
			continue
		if fused:
			# bond: the moves in a 2x2 grid, each with its own cooldown and a flash when it casts
			var C := 22.0
			var P := (S - C * 2.0) / 3.0
			for k in g.size():
				var gm: Dictionary = g[k]
				var gx := x + P + (k % 2) * (C + P)
				var gy := y + P + (k / 2) * (C + P)
				Icons.draw(self, "move:" + str(gm["id"]), gx, gy, C)
				var f := 0.0 if gm["kind"] == "orbit" else clampf(float(gm["t"]) / (float(gm["cd"]) * pl.cd_mul), 0.0, 1.0)
				if f > 0.0:
					draw_rect(Rect2(gx, gy, C, C * f), Color(0, 0, 0, 0.55))
				if gm.get("evolved", false):
					draw_rect(Rect2(gx + 0.5, gy + 0.5, C - 1.0, C - 1.0), _c("#ffd23f"), false, 1.0)
				var fl := 1.0 - (Time.get_ticks_msec() - int(gm.get("cast_at", 0))) / 180.0
				if fl > 0.0:
					draw_rect(Rect2(gx, gy, C, C), Color(1, 1, 1, fl * 0.55))
		else:
			# cooldown: empties from bottom to top
			var cdf := 0.0 if m["kind"] == "orbit" else clampf(float(m["t"]) / (float(m["cd"]) * pl.cd_mul), 0.0, 1.0)
			if cdf > 0.0:      # fillRect(x, y, S, S·f) clipped to the slot's roundRect(12)
				DrawUtil.clipped_round_rect(self, Rect2(x, y, S, S), 12.0, Rect2(x, y, S, S * cdf), Color(0, 0, 0, 0.6))
			Icons.draw(self, "move:" + str(m["id"]), x + (S - 32.0) / 2.0, y + (S - 32.0) / 2.0 - 2.0, 32)
			var dots := Moves.max_lvl(m)
			var tw := dots * 4.0 + (dots - 1) * 2.0
			for d in dots:
				draw_rect(Rect2(x + (S - tw) / 2.0 + d * 6.0, y + S - 9.0, 4, 3), col if d < int(m["lvl"]) else Color(1, 1, 1, 0.18))
		var bond_c := _c("#ff8ad8")
		DrawUtil.text(self, str(i + 1), x + 3, y + 10, 9, bond_c if fused else (col if on else Color(180 / 255.0, 200 / 255.0, 230 / 255.0, 0.6)), -1, 800)
		if on:
			# with a bond: "Ascuas +2"
			DrawUtil.text(self, (str(m["name"]) + " +" + str(g.size() - 1)) if fused else str(m["name"]), x + S / 2.0, y - 7.0, 10, bond_c if fused else col, 0, 700)

	# ---------- stored bond (no two loose moves yet, Phase 3b) ----------
	if pl.bonds > 0:
		var bdx := sx + total_w + 12.0
		var bdy := sy + S / 2.0 - 12.0
		Icons.draw(self, "bond", bdx, bdy, 24)
		if pl.bonds > 1:
			DrawUtil.text(self, "×" + str(pl.bonds), bdx + 25.0, bdy + 20.0, 10, _c("#ff8ad8"), -1, 800)

	# ---------- held item (left of the moves) ----------
	var ix := sx - S - 18.0
	if pl.item != "":
		DrawUtil.round_rect(self, Rect2(ix, sy, S, S), 12, Color(40 / 255.0, 30 / 255.0, 10 / 255.0, 0.9), _c("#ffd23f"), 2.0)
		Icons.draw(self, pl.item, ix + (S - 36.0) / 2.0, sy + (S - 36.0) / 2.0, 36)
		DrawUtil.text(self, Items.name_of(pl.item), ix + S / 2.0, sy - 6.0, 9, _c("#ffd23f"), 0, 700)
	else:
		DrawUtil.round_rect(self, Rect2(ix, sy, S, S), 12, Color(10 / 255.0, 16 / 255.0, 28 / 255.0, 0.55),
			Color(140 / 255.0, 170 / 255.0, 210 / 255.0, 0.18), 1.0)

	# ---------- pause button (touch) ----------
	if is_touch:
		var pbx := w - 52.0 - minf(44.0, sa["right"])
		var pby := 12.0 + minf(20.0, sa["top"])
		DrawUtil.round_rect(self, Rect2(pbx, pby, 40, 40), 10, Color(10 / 255.0, 16 / 255.0, 28 / 255.0, 0.7), Color(244 / 255.0, 248 / 255.0, 1.0, 0.8), 2.0)
		draw_rect(Rect2(pbx + 13, pby + 11, 5, 18), _c("#f4f8ff"))
		draw_rect(Rect2(pbx + 22, pby + 11, 5, 18), _c("#f4f8ff"))
		if touch != null:
			touch.add_button(Rect2(pbx, pby, 40, 40), func(): _pause_pressed(), 8.0)

	# ---------- control hint (first 14 s) ----------
	if sim.time < 14.0:
		var hint := "Arrastra el dedo para moverte  ·  toca un ataque para cambiarlo" if is_touch \
			else "WASD moverse  ·  1-4 / Q / E o clic en un ataque para cambiarlo  ·  Esc pausa"
		DrawUtil.text(self, hint, w / 2.0, h - 4.0, 10, Color(180 / 255.0, 200 / 255.0, 230 / 255.0, 0.55), 0, 600)

	if Settings.show_fps:
		var fps := _fps_shown
		DrawUtil.text(self, "%d FPS" % fps, w - 10.0, h - 8.0, 11,
			_c("#5fe08a") if fps >= 50 else (_c("#ffd23f") if fps >= 30 else _c("#ff5f6d")), 1, 700)
	# the full-screen flash (rift travel) is drawn by TouchInput, above the joystick like game.js

func _slot_pressed(i: int) -> void:
	if sim != null and sim.state == "playing" and sim.player.active != i:
		sim.player.set_active(i)
		Sfx.play("click")

func _pause_pressed() -> void:
	if game != null:
		game.toggle_pause()
