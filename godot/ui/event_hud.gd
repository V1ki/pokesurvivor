class_name EventHud
extends RefCounted
## Phase 3b HUD pieces in screen space, called from ui/hud.gd (js/ui/hud.js + events.js drawHud):
## rift arrow (pulsing on the edge when off-screen, bouncing over it when visible), arena
## countdown, event countdown, edge arrows to the lost Pokémon / its mark and to thieves,
## the "rift opened" popup, the altar power chip and the full-screen flash.

const RIFT_HI := Color(0.886, 0.816, 1.0)        # #e2d0ff
const RIFT_LO := Color(0.627, 0.42, 1.0)         # #a06bff
const RIFT_DARK := Color(0.102, 0.043, 0.2)      # #1a0b33

static func _c(hex: String) -> Color:
	return Color.html(hex)

## Altar power chip in the buff row (hud.js): returns the next chip x.
static func power_chip(ci: CanvasItem, pl: Player, bx: float, py: float) -> float:
	if pl.power.is_empty():
		return bx
	var pw: Dictionary = pl.power["def"]
	var txt := str(pw["name"]).to_upper() + " " + str(int(ceil(float(pl.power["t"])))) + "s"
	var tw := DrawUtil.text_width(txt, 9, 800) + 12.0
	DrawUtil.round_rect(ci, Rect2(bx, py + 34.0, tw, 15.0), 7, Color(0, 0, 0, 0.6))
	DrawUtil.text(ci, txt, bx + 6.0, py + 45.0, 9, _c(pw["color"]), -1, 800)
	return bx + tw + 5.0

## Everything between the shiny arrows and the banner (hud.js order).
static func draw(ci: CanvasItem, sim: Sim, w: float, h: float) -> void:
	var pl := sim.player
	var cam := sim.cam
	var now := Time.get_ticks_msec() / 1000.0
	var rift := sim.rift
	var boss := false
	for e in sim.enemies.list:
		if e.boss and not e.dead:
			boss = true
			break
	# ---- rift arrow ----
	if not rift.portal.is_empty():
		var r := rift.portal
		var sp := cam.world_to_screen_steady(r["x"], float(r["y"]) - 40.0)
		var beat := 0.5 + sin(now * 7.0) * 0.5
		var fill := RIFT_HI if beat > 0.5 else RIFT_LO
		var off := sp.x < 0.0 or sp.x > w or sp.y < 0.0 or sp.y > h
		if off:
			var label := "GRIETA · " + str(U.jroundi(U.dist(pl.x, pl.y, r["x"], r["y"]) / 32.0)) + " m · " + str(int(ceil(float(r["ttl"])))) + " s"
			var M := 52.0
			var ex := clampf(sp.x, M, w - M)
			var ey := clampf(sp.y, M + 70.0, h - M - 80.0)
			var a := atan2(sp.y - ey, sp.x - ex)
			var ca := cos(a)
			var sa := sin(a)
			ci.draw_circle(Vector2(ex, ey), 30.0 + beat * 8.0, Color(_c("#b48aff"), 0.18 + beat * 0.22))
			ci.draw_colored_polygon(_tri(ex, ey, a, 40.0 * 1.12, 20.0 * 1.12), RIFT_DARK)
			ci.draw_colored_polygon(_tri(ex, ey, a, 40.0, 20.0), fill)
			var al := 1 if ca > 0.3 else (-1 if ca < -0.3 else 0)
			DrawUtil.text(ci, label, ex - ca * 34.0, ey - sa * 30.0 + 4.0, 12, RIFT_HI, al, 800, 4, Color(0, 0, 0, 0.85))
		else:
			# over the rift: a bouncing arrow pointing down
			var by := sp.y - 46.0 - absf(sin(now * 4.0)) * 10.0
			var pts := PackedVector2Array([Vector2(sp.x - 15, by - 12), Vector2(sp.x + 15, by - 12), Vector2(sp.x, by + 8)])
			ci.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), RIFT_DARK, 4.0)
			ci.draw_colored_polygon(pts, fill)
			DrawUtil.text(ci, "GRIETA · " + str(int(ceil(float(r["ttl"])))) + " s", sp.x, by - 18.0, 11, RIFT_HI, 0, 800, 4, Color(0, 0, 0, 0.85))
	if rift.in_arena:
		DrawUtil.text(ci, "GRIETA · " + U.mmss(rift.time_left()), w / 2.0, 98.0 if boss else 76.0, 12, _c("#d9c2ff"), 0, 800)

	# ---- events: lost Pokémon / mark, thieves, countdown ----
	var ev := sim.events
	var pulse := 0.65 + sin(Time.get_ticks_msec() / 160.0) * 0.35
	if ev.lost != null:
		var L := ev.lost
		var to := Vector2(L.x, L.y - 10.0) if L.state == "wait" else Vector2(L.tx, L.ty)
		var lbl := (L.name if L.state == "wait" else "Marca") + " · " + str(U.jroundi(U.dist(pl.x, pl.y, to.x, to.y) / 32.0)) + " m"
		_edge_arrow(ci, w, h, cam, to.x, to.y, _c("#7dffb0"), lbl, pulse)
	for e in sim.enemies.list:
		if e.behavior == "thief" and not e.dead:
			_edge_arrow(ci, w, h, cam, e.x, e.y - 10.0, _c("#ffd23f"), e.name, pulse)
	if not ev.cur.is_empty() and ev.cur["id"] != "lost":
		var left := maxi(0, int(ceil(float(ev.cur["dur"]) - float(ev.cur["t"]))))
		var gold: bool = ev.cur["id"] == "gold"
		var txt := ("HORA DORADA" if gold else "HORDA " + str(Data.type_name.get(ev.cur["type"], "")).to_upper()) + " · " + str(left) + " s"
		var col := _c("#ffd23f") if gold else Data.tcolor(ev.cur["type"])
		DrawUtil.text(ci, txt, w / 2.0, 112.0, 12, col, 0, 800, 4, Color(0, 0, 0, 0.8))

	# ---- "a rift has opened" popup (the other banners don't cover it) ----
	if not rift.portal.is_empty() and float(rift.portal["t"]) < 4.5:
		var t: float = rift.portal["t"]
		var a := minf(1.0, minf(t * 4.0, (4.5 - t) * 2.0))
		var pop := 1.0 + maxf(0.0, 0.25 - t) * 1.6
		var t1 := "¡SE HA ABIERTO UNA GRIETA!"
		var t2 := "Sigue la flecha morada: dentro te espera un legendario"
		var bw := minf(w - 24.0, maxf(DrawUtil.text_width(t1, 20, 800), DrawUtil.text_width(t2, 11, 700)) + 36.0)
		ci.draw_set_transform(Vector2(w / 2.0, h * 0.2), 0.0, Vector2(pop, pop))
		DrawUtil.round_rect(ci, Rect2(-bw / 2.0, -26.0, bw, 52.0), 10, Color(26 / 255.0, 11 / 255.0, 51 / 255.0, 0.88 * a), Color(_c("#b48aff"), a), 2.0)
		DrawUtil.text(ci, t1, 0.0, -2.0, 20, Color(RIFT_HI, a), 0, 800)
		DrawUtil.text(ci, t2, 0.0, 16.0, 11, Color(_c("#c9b0ff"), a), 0, 700)
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

static func _tri(x: float, y: float, a: float, tip: float, base: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x + cos(a) * tip, y + sin(a) * tip),
		Vector2(x + cos(a + 2.45) * base, y + sin(a + 2.45) * base), Vector2(x + cos(a - 2.45) * base, y + sin(a - 2.45) * base)])

## Edge arrow toward something off-screen (events.js edgeArrow).
static func _edge_arrow(ci: CanvasItem, w: float, h: float, cam: SimCamera, x: float, y: float, col: Color, label: String, pulse: float) -> void:
	var sp := cam.world_to_screen_steady(x, y)
	if sp.x > 0.0 and sp.x < w and sp.y > 0.0 and sp.y < h:
		return
	var M := 44.0
	var ex := clampf(sp.x, M, w - M)
	var ey := clampf(sp.y, M + 70.0, h - M - 80.0)
	var a := atan2(sp.y - ey, sp.x - ex)
	var ca := cos(a)
	var sa := sin(a)
	var tri := _tri(ex, ey, a, 30.0, 15.0)
	ci.draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), Color(0, 0, 0, pulse), 3.0)
	ci.draw_colored_polygon(tri, Color(col, pulse))
	var al := 1 if ca > 0.3 else (-1 if ca < -0.3 else 0)
	DrawUtil.text(ci, label, ex - ca * 26.0, ey - sa * 24.0 + 4.0, 11, col, al, 800, 4, Color(0, 0, 0, 0.85))

## Full-screen flash (rift travel), drawn last; a third as strong with "calm".
static func draw_flash(ci: CanvasItem, sim: Sim, w: float, h: float) -> void:
	if sim.flash_t <= 0.0:
		return
	var a := minf(1.0, sim.flash_t / sim.flash_dur * 1.4) * (0.3 if Settings.calm else 1.0)
	ci.draw_rect(Rect2(0, 0, w, h), Color(sim.flash_col, a))
