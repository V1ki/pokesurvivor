class_name EventDraw
extends RefCounted
## World-space drawables of Phase 3b for the y-sorted pass of render/world_view.gd:
## the rift portal (rift.js drawable), the lost Pokémon and its green goal mark
## (events.js drawables). collect() adds Items (sorted by feet y); draw_item() draws one.

class Item:
	var y := 0.0
	var kind := ""        # rift | lost | goal

static func collect(sim: Sim, out: Array) -> void:
	if not sim.rift.portal.is_empty():
		var it := Item.new()
		it.kind = "rift"
		it.y = sim.rift.portal["y"]
		out.append(it)
	var L := sim.events.lost
	if L != null:
		var g := Item.new()
		g.kind = "goal"
		g.y = L.ty - 4000.0          # on the ground, under everything
		out.append(g)
		var m := Item.new()
		m.kind = "lost"
		m.y = L.y
		out.append(m)

static func draw_item(ci: CanvasItem, sim: Sim, it: Item) -> void:
	match it.kind:
		"rift":
			_rift(ci, sim.rift.portal)
		"goal":
			if sim.events.lost != null:
				_goal(ci, sim.events.lost)
		"lost":
			if sim.events.lost != null:
				_lost(ci, sim.events.lost)

## The portal: purple ground glow + the 4-frame sprite (8 fps), fading in and out.
static func _rift(ci: CanvasItem, r: Dictionary) -> void:
	var t: float = r["t"]
	var fade := minf(1.0, t * 2.0) * minf(1.0, float(r["ttl"]) / 1.5)
	var x: float = r["x"]
	var y: float = r["y"]
	DrawUtil.ellipse(ci, x, y, 34.0, 12.0, Color(Color.html("#7b3cff"), 0.25 * fade))
	var tex: Texture2D = portal_texture(int(floorf(t * 8.0)) % 4)
	if tex != null:
		var w := tex.get_width() * Sprites.PX
		var h := tex.get_height() * Sprites.PX
		ci.draw_texture_rect(tex, Rect2(roundf(x - w / 2.0), roundf(y - h + 4.0), w, h), false, Color(1, 1, 1, fade))
	else:
		# fallback (no portal art): a pulsing purple oval
		DrawUtil.ellipse(ci, x, y - 40.0, 24.0, 40.0, Color(Color.html("#a06bff"), 0.7 * fade))

## Portal art frame (tiles.js propSprite(0, 'rift', f), painted by Phase 3a's PropArt).
static func portal_texture(frame: int) -> Texture2D:
	return PropArt.texture(0, "rift", frame)

## The green goal mark with a bobbing heart.
static func _goal(ci: CanvasItem, L: Events.Lost) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var k := 0.5 + sin(now * 4.0) * 0.5
	DrawUtil.ellipse(ci, L.tx, L.ty, 56.0, 40.0, Color(Color.html("#5fe08a"), 0.25 + k * 0.15))
	DrawUtil.dashed_ellipse(ci, L.tx, L.ty, 56.0, 40.0, Color(Color.html("#7dffb0"), 0.9), 2.0, 6.0, 5.0)
	Icons.draw(ci, "heart", roundf(L.tx - 8.0), roundf(L.ty - 30.0 - k * 6.0), 16)

## The lost Pokémon: green ground ring, sprite, bouncing "!" while it waits, HP bar.
static func _lost(ci: CanvasItem, L: Events.Lost) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	DrawUtil.ellipse(ci, L.x, L.y, L.r * 1.5, L.r * 0.6, Color(Color.html("#7dffb0"), 0.3))
	DrawUtil.shadow(ci, L.dex, L.x, L.y, 1.0)
	DrawUtil.pmd(ci, L.anim, L.x, L.y, L.flash > 0.0)
	var h := Sprites.body_height(L.dex, 1.0)
	if L.state == "wait":
		# "!" bouncing on top: it waits for you to touch it
		var by := L.y - h - 14.0 - absf(sin(now * 5.0)) * 6.0
		DrawUtil.text(ci, "!", L.x, by, 16, Color.html("#7dffb0"), 0, 700, 4, Color.BLACK)
	var w := 30.0
	var y := L.y - h - 6.0
	ci.draw_rect(Rect2(L.x - w / 2.0, y, w, 3.4), Color(0, 0, 0, 0.6))
	ci.draw_rect(Rect2(L.x - w / 2.0, y, w * maxf(0.0, L.hp / L.max_hp), 3.4), Color.html("#5fe08a"))
