class_name Autoshot3b
extends RefCounted
## Phase 3b visual check: `--autoshot=<dir> --p3b` (god mode, the player is teleported around).
## Saves, in order: each interactable (altar + power, spring healing, locked chest opening + loot,
## trap + blast), each event (horde, golden hour, lost Pokémon waiting / following / rescued,
## thief), a rift (popup + arrow, portal, arena, legendary fight, win), the bond picker (both
## steps) and the fused slot, a lost arena, and `p3b_arenas.png` (a 6x3 montage of the 18 arena
## themes). Then quits.

static var step := 0
static var t0 := 0.0
static var plan: Dictionary = {}         # type -> WorldProp chosen for the shots
static var arena_i := 0
static var montage: Image = null
static var _flags: Dictionary = {}

const THUMB := Vector2i(320, 180)

## Movement while the harness runs: idle (shots are framed by teleporting).
static func axis(_game: Node) -> Vector2:
	return Vector2.ZERO

static func _elapsed(game: Node) -> float:
	return float(game._real_t) - t0

static func _next(game: Node) -> void:
	step += 1
	t0 = game._real_t
	_flags.clear()

static func _once(k: String) -> bool:
	if _flags.has(k):
		return false
	_flags[k] = true
	return true

static func _place(sim: Sim, x: float, y: float) -> void:
	var pl := sim.player
	pl.x = x
	pl.y = y
	sim.cam.x = x
	sim.cam.y = y

## Teleports next to a prop of this type (south of it), or skips if none was found.
static func _near(sim: Sim, type: String, dy := 70.0) -> bool:
	var p: WorldProp = plan.get(type)
	if p == null:
		return false
	_place(sim, p.x, p.y + dy)
	return true

static func tick(game: Node) -> void:
	var sim: Sim = game.sim
	var pl := sim.player
	if sim.state == "over":
		game.get_tree().quit()
		return
	if pl == null:
		return
	if sim.state == "levelup" or (sim.state == "choice" and sim.bond_opt.is_empty()):
		Bot.pick(sim)
		game.screens.hide_all()
		game.item_ui.close()
		return
	if not _flags.has("_mortal"):
		pl.god = true
		pl.hp = maxf(pl.hp, 1.0)
	var e := _elapsed(game)
	match step:
		0:
			# setup: a few moves (for the bond), find the interactables around the start
			if _once("setup"):
				for id in ["ember", "water-gun", "thunder-shock"]:
					pl.add_move(id)
				_find_specials(sim)
				print("autoshot3b: specials found ", plan.keys().map(func(k): return "%s@(%d,%d)" % [k, plan[k].tx, plan[k].ty]))
			if e > 1.0:
				_next(game)
		1:
			if not _near(sim, "altar"):
				_next(game)
				return
			if e > 0.8 and _once("a"):
				game._shot("p3b_altar")
			if e > 1.0 and _once("go"):
				_near(sim, "altar", 18.0)
			if e > 1.6 and _once("b"):
				game._shot("p3b_altar_power")
			if e > 1.8:
				_next(game)
		2:
			var p: WorldProp = plan.get("spring")
			if p == null:
				_next(game)
				return
			if _once("go"):
				pl.hp = pl.max_hp * 0.35
				_place(sim, p.x, p.y - 8.0)
			if e > 1.5 and _once("a"):
				game._shot("p3b_spring")
			if e > 1.7:
				_next(game)
		3:
			if plan.get("bigchest") == null:
				_next(game)
				return
			if _once("go"):
				_near(sim, "bigchest", 30.0)
			if e > 2.0 and _once("a"):
				game._shot("p3b_chest_open")
			if e > 4.3 and _once("b"):
				game._shot("p3b_chest_loot")
			if e > 4.5:
				_next(game)
		4:
			var p: WorldProp = plan.get("trap")
			if p == null:
				_next(game)
				return
			if _once("go"):
				_place(sim, p.x + 60.0, p.y + 40.0)
			if e > 0.8 and _once("a"):
				game._shot("p3b_trap")
			if e > 1.0 and _once("step"):
				_place(sim, p.x, p.y - 8.0)
			if e > 1.25 and _once("b"):
				game._shot("p3b_trap_boom")
			if e > 1.5:
				_place(sim, 0.0, 0.0)
				_next(game)
		5:
			if _once("go"):
				sim.events.debug_start("horde")
			if e > 1.0 and _once("a"):
				game._shot("p3b_horde")
			if e > 1.2:
				sim.events.end()
				_next(game)
		6:
			if _once("go"):
				sim.events.debug_start("gold")
			if e > 4.0 and _once("a"):
				game._shot("p3b_gold")
			if e > 4.2:
				sim.events.end()
				_next(game)
		7:
			if _once("go"):
				sim.events.debug_start("lost")
			var L := sim.events.lost
			if L == null:
				if e > 0.5:
					_next(game)
				return
			if e > 0.6 and _once("a"):
				game._shot("p3b_lost_arrow")
			if e > 0.8 and _once("near"):
				_place(sim, L.x + 90.0, L.y + 10.0)
			if e > 1.4 and _once("b"):
				game._shot("p3b_lost")
			if e > 1.6 and _once("touch"):
				_place(sim, L.x + 20.0, L.y)
			if e > 2.6 and _once("c"):
				game._shot("p3b_lost_follow")
			if e > 2.8 and _once("goal"):
				_place(sim, L.tx, L.ty + 100.0)
				L.x = L.tx + 30.0
				L.y = L.ty + 110.0
			if e > 3.4 and _once("d"):
				game._shot("p3b_lost_goal")
			if e > 3.6 and _once("home"):
				_place(sim, L.tx, L.ty)
		8:
			if _once("go"):
				game._shot("p3b_lost_rescued")
			if e > 0.4 and _once("thief"):
				sim.events.debug_start("thief")
			if e > 1.0 and _once("a"):
				game._shot("p3b_thief")
			if e > 1.2:
				_next(game)
		9:
			if _once("go"):
				sim.rift.debug_open()
			if sim.rift.in_arena:
				_next(game)
				return
			if sim.rift.portal.is_empty():
				if e > 0.5:
					print("autoshot3b: no room for a rift")
					_next(game)
				return
			if e > 0.6 and _once("a"):
				game._shot("p3b_rift_popup")
			if e > 0.8 and _once("near"):
				_place(sim, sim.rift.portal["x"] + 60.0, float(sim.rift.portal["y"]) + 40.0)
			# after the popup (4.5 s): the portal sprite + the bouncing arrow over it
			if e > 5.0 and _once("b"):
				game._shot("p3b_rift_portal")
			if e > 5.2 and _once("enter"):
				_place(sim, sim.rift.portal["x"], float(sim.rift.portal["y"]) - 10.0)
			if sim.rift.in_arena:
				_next(game)
		10:
			if e > 1.6 and _once("a"):
				game._shot("p3b_arena")
			if e > 5.0 and _once("hold"):
				# hold fire for a second so the legendary isn't flashing white; frame it
				for m in pl.moves:
					m["t"] = 99.0
				var lg := sim.enemies.get_enemy(int(sim.rift.arena["boss_id"]))
				if lg != null:
					_place(sim, lg.x + 30.0, lg.y + 90.0)
			if e > 5.7 and _once("b"):
				game._shot("p3b_legend")
				for m in pl.moves:
					m["t"] = 0.0
			if e > 6.2 and _once("kill"):
				var boss := sim.enemies.get_enemy(int(sim.rift.arena["boss_id"]))
				if boss != null:
					boss.hurt(boss.hp + 1.0, Color.WHITE)
			if e > 7.2 and _once("c"):
				game._shot("p3b_rift_won")
			if not sim.rift.in_arena:
				_next(game)
		11:
			# back on the map: the bond picker opens (pair mode, two steps)
			if sim.state == "choice" and not sim.bond_opt.is_empty():
				if e > 0.6 and _once("a"):
					game._shot("p3b_bond")
				if e > 0.8 and _once("p1"):
					game.bond_ui.pick(0)
				if e > 1.2 and _once("b"):
					game._shot("p3b_bond_step2")
				if e > 1.4 and _once("p2"):
					game.bond_ui.pick(0)
			elif e > 2.0 and _once("c"):
				game._shot("p3b_fused")
			if e > 2.4:
				_next(game)
		12:
			# lose a rift: fall inside the arena
			if _once("go"):
				sim.rift.debug_arena("ghost")
			if e > 1.0 and _once("die"):
				_flags["_mortal"] = true
				pl.god = false
				pl.invuln = 0.0
				pl.hurt(pl.hp + 9999.0)
			if e > 2.8 and _once("a"):
				game._shot("p3b_rift_lost")
			if not sim.rift.in_arena and e > 1.0:
				pl.god = true
				_next(game)
		13:
			# the 18 arena themes as one montage
			var types: Array = WorldMap.world_json()["arena_types"]
			if arena_i >= types.size():
				_next(game)
				return
			if _once("go"):
				sim.rift.debug_arena(types[arena_i])
				sim.player.x = float(sim.rift.arena["x"]) + 64.0
				sim.player.y = float(sim.rift.arena["y"]) + 40.0
			if e > 1.6 and _once("snap"):
				_thumb(game, arena_i)
			if e > 2.0:
				sim.rift._finish()
				arena_i += 1
				t0 = game._real_t
				_flags.clear()
		14:
			if _once("save"):
				var path: String = str(game._shot_dir).path_join("p3b_arenas.png")
				montage.save_png(path)
				print("autoshot3b: ", path)
				print("autoshot3b: interact ", sim.interact.stats, " rift ", sim.rift.history, " events ", sim.events.history)
			# let in-flight worker jobs (ground painter, sprite loads) settle before quitting
			if e > 2.0:
				game.get_tree().quit()

static func _find_specials(sim: Sim) -> void:
	var r := 2200.0
	while r <= 6600.0 and plan.size() < 4:
		var best: Dictionary = {}
		for p: WorldProp in sim.world.specials_near(0.0, 0.0, r):
			var d := p.x * p.x + p.y * p.y
			if not best.has(p.type) or d < float(best[p.type][0]):
				best[p.type] = [d, p]
		for k in best:
			plan[k] = best[k][1]
		r += 2200.0

static func _thumb(game: Node, i: int) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = game.get_viewport().get_texture().get_image()
	img.resize(THUMB.x, THUMB.y, Image.INTERPOLATE_BILINEAR)
	if montage == null:
		montage = Image.create(THUMB.x * 6, THUMB.y * 3, false, img.get_format())
	montage.blit_rect(img, Rect2i(Vector2i.ZERO, THUMB), Vector2i((i % 6) * THUMB.x, (i / 6) * THUMB.y))
