class_name Autoshot2
extends RefCounted
## Phase 2 debug helpers for main.gd:
##   debug_from_args(args)  command-line options -> Sim.debug (+ Bot.cycle_slots)
##     --learn=id,id,...  learn these moves at start      --move-lvl=<n>  their level (1-5)
##     --evolve           evolve maxed moves              --boss-at=<s>   first boss time
##     --boss-gap=<s>     time between bosses (90)        --force-shiny=<n> next n spawns shiny
##     --item=<id>        start with a held item          --cycle         bot rotates move slots
##     --start-t=<s>      start the run clock at s (perf at the enemy cap)
##   tick(game)  visual check with `--autoshot=<dir> --p2`: plays a run with the bot (god mode
##   with --god) and saves event screenshots (boss, boss cast, telegraph, enemy shots, shiny
##   on screen / off-screen arrow, item choice) plus one every 5 s; quits at --p2-end (75 s).

static func debug_from_args(args: Dictionary) -> Dictionary:
	var d := {}
	if args.has("learn"):
		d["moves"] = Array(str(args["learn"]).split(",", false))
	if args.has("move-lvl"):
		d["move_lvl"] = int(args["move-lvl"])
	if args.has("evolve"):
		d["evolve"] = true
	if args.has("boss-at"):
		d["boss_at"] = float(args["boss-at"])
	if args.has("boss-gap"):
		d["boss_gap"] = float(args["boss-gap"])
	if args.has("force-shiny"):
		d["force_shiny"] = int(args["force-shiny"]) if str(args["force-shiny"]) != "" else 1
	if args.has("item"):
		d["item"] = str(args["item"])
	if args.has("start-t"):
		d["start_t"] = float(args["start-t"])
	Bot.cycle_slots = args.has("cycle")
	# Phase 3b: --event=horde,gold,lost,thief (from --event-at=s, default 5, one after another),
	# --rift-at=s (open a rift then), --rift-type=<type> (its arena), --bonds=n, --seek (bot goals)
	if args.has("event"):
		var at := float(args.get("event-at", "5")) if str(args.get("event-at", "")) != "" else 5.0
		d["events"] = Array(str(args["event"]).split(",", false)).map(func(id): return [at, id])
	if args.has("rift-at"):
		d["rift_at"] = float(args["rift-at"]) if str(args["rift-at"]) != "" else 2.0
	if args.has("rift-type"):
		d["rift_type"] = str(args["rift-type"])
	if args.has("bonds"):
		d["bonds"] = int(args["bonds"]) if str(args["bonds"]) != "" else 1
	Bot.seek = args.has("seek")
	return d

## Called every frame by main.gd in --p2 autoshot mode (after the sim step).
static func tick(game: Node) -> void:
	var sim: Sim = game.sim
	var done: Dictionary = game._shots_done
	var args: Dictionary = game.args
	var real_t: float = game._real_t
	match sim.state:
		"ui":
			if real_t > 0.3:
				game.start_run()
			return
		"levelup":
			if not done.has("p2_levelup"):
				game._shot("p2_levelup")
			if not done.has("_wait"):
				done["_wait"] = real_t
			elif real_t - float(done["_wait"]) > 0.3:
				done.erase("_wait")
				Bot.pick(sim)
				game.screens.hide_all()
			return
		"choice":
			if not done.has("p2_item"):
				game._shot("p2_item")
			if not done.has("_wait"):
				done["_wait"] = real_t
			elif real_t - float(done["_wait"]) > 0.5:
				done.erase("_wait")
				Bot.pick(sim)
				game.item_ui.close()
			return
		"over":
			if not done.has("p2_over"):
				game._shot("p2_over")
				game.get_tree().create_timer(1.0).timeout.connect(func(): game.get_tree().quit())
			return
	if sim.state != "playing" or sim.player == null:
		return
	var pl := sim.player
	if args.has("god"):
		pl.god = true
		pl.hp = pl.max_hp
	var cam := sim.cam
	# --- event shots ---
	for e in sim.enemies.list:
		if e.boss and cam.sees(e.x, e.y, -60.0):
			if not done.has("p2_boss"):
				game._shot("p2_boss")
			if e.ai != null and not e.ai.cast.is_empty() and not sim.hazards.list.is_empty() and not done.has("p2_boss_cast"):
				game._shot("p2_boss_cast")
			if e.ai != null and e.ai.fury and not done.has("p2_boss_fury"):
				game._shot("p2_boss_fury")
		if e.shiny:
			if cam.sees(e.x, e.y, -40.0):
				if not done.has("p2_shiny"):
					game._shot("p2_shiny")
					print("autoshot2: shiny %s at screen %s" % [e.name, str(cam.world_to_screen(e.x, e.y))])
			elif not done.has("p2_shiny_arrow") and sim.time > 2.0:
				game._shot("p2_shiny_arrow")
	for h in sim.hazards.list:
		if not h.hit and h.t > h.delay * 0.6 and cam.sees(h.x, h.y, -40.0) and not done.has("p2_telegraph"):
			game._shot("p2_telegraph")
	var shots := 0
	for p in sim.projectiles.list:
		if not p.friendly and cam.sees(p.x, p.y, -20.0):
			shots += 1
	if shots >= 3 and not done.has("p2_enemy_shots"):
		game._shot("p2_enemy_shots")
	if not sim.combat.fields.is_empty() and not done.has("p2_fields"):
		var vis := 0
		for f in sim.combat.fields:
			if cam.sees(f.x, f.y, -40.0):
				vis += 1
		if vis >= 2:
			game._shot("p2_fields")
	# --- every 5 s ---
	var k := "p2_t%02d" % (int(sim.time / 5.0) * 5)
	if sim.time >= 3.0 + float(sim.debug.get("start_t", 0.0)) and not done.has(k):
		game._shot(k)
	var end := float(args.get("p2-end", "75")) if str(args.get("p2-end", "")) != "" else 75.0
	end += float(sim.debug.get("start_t", 0.0))
	if sim.time >= end and not done.has("quit"):
		done["quit"] = true
		var mv: Array = []
		for m in pl.moves:
			mv.append("%s%d%s" % [m["id"], int(m["lvl"]), "*" if m.get("evolved", false) else ""])
		print("autoshot2: end t=%.1f level %d kills %d bosses %d shinies %d moves %s" % [sim.time, pl.level, pl.kills,
			pl.bosses, sim.caught.size(), " ".join(mv)])
		game.get_tree().create_timer(0.5).timeout.connect(func(): game.get_tree().quit())
