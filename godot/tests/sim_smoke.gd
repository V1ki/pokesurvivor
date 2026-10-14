extends SceneTree
## Headless simulation smoke test: the full game loop (spawner, bosses, enemies + their
## shots/hazards, pathing, combat + fields, projectiles, pickups, level-ups, held items)
## without rendering, fixed dt = 1/60, scripted input (debug/bot.gd).
##   godot --headless --path godot --script res://tests/sim_smoke.gd -- [--seconds=120] [--seed=7]
##       [--partner=4] [--god] [--learn=id,id] [--move-lvl=5] [--evolve] [--boss-at=30]
##       [--boss-gap=90] [--force-shiny=1] [--item=id] [--cycle] [--quiet]
##       Phase 3b: [--event=horde,gold,lost,thief] [--event-at=5] [--rift-at=s] [--rift-type=t] [--bonds=n] [--seek]
## Prints a stats line every 10 s and the per-step time (avg / max, and at the 64-enemy cap).

func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var seconds := float(args.get("seconds", "120"))
	var seed := int(args.get("seed", "7"))
	var partner := int(args.get("partner", "4"))
	var god := args.has("god")          # no damage taken (exercise the late loop)
	var quiet := args.has("quiet")
	seed(seed)                       # Math.random equivalent, reproducible run
	var sim := Sim.new()
	sim.render = false
	sim.debug = Autoshot2.debug_from_args(args)
	sim.start_run(partner, seed)
	var dt := 1.0 / 60.0
	var picks := 0
	var fusions := 0
	var arena_s := 0.0
	var arena_max := 0
	var next_print := 0.0
	var max_alive := 0
	var max_proj := 0
	var max_enemy_shots := 0
	var max_hazards := 0
	var max_fields := 0
	var kinds_cast := {}
	var behaviors := {}
	var bosses_seen := {}
	var shinies_seen := {}
	var items_taken := {}
	var st := {"n": 0, "us": 0, "max": 0, "max_t": 0.0, "cap_n": 0, "cap_us": 0, "cap_max": 0}
	var t0 := Time.get_ticks_usec()
	print("smoke: partner %s (dex %d), seed %d, %d s at dt=1/60%s%s" % [sim.player.mon["name"], partner, seed, int(seconds),
		" (god mode)" if god else "", (" debug " + str(sim.debug)) if not sim.debug.is_empty() else ""])
	if not quiet:
		print("   time  level   kills  alive  proj eshot hz fld  gems   hp/max    moves")
	while sim.time < seconds and sim.state != "over":
		if sim.state == "levelup" or sim.state == "choice":
			if sim.state == "choice" and not sim.bond_opt.is_empty():
				fusions += 1
			elif sim.state == "choice":
				items_taken[sim.item_choice[1]] = true
			Bot.pick(sim)
			picks += 1
			continue
		sim.input_axis = Bot.axis(sim)
		if god:
			sim.player.god = true
			sim.player.hp = sim.player.max_hp
		var s0 := Time.get_ticks_usec()
		sim.update(dt)
		var us := Time.get_ticks_usec() - s0
		st.n += 1
		st.us += us
		if us > st.max:
			st.max = us
			st.max_t = sim.time
		if sim.enemies.count() >= Spawner.CAP:
			st.cap_n += 1
			st.cap_us += us
			st.cap_max = maxi(st.cap_max, us)
		max_alive = maxi(max_alive, sim.enemies.count())
		if sim.rift.in_arena:
			arena_s += dt
			arena_max = maxi(arena_max, sim.enemies.count())
		max_proj = maxi(max_proj, sim.projectiles.count())
		max_hazards = maxi(max_hazards, sim.hazards.count())
		max_fields = maxi(max_fields, sim.combat.field_count())
		var es := 0
		for p in sim.projectiles.list:
			if not p.friendly:
				es += 1
		max_enemy_shots = maxi(max_enemy_shots, es)
		for m in sim.player.active_group():
			if m.has("cast_at") and int(m["cast_at"]) > 0:
				kinds_cast[m["kind"]] = true
		for e in sim.enemies.list:
			behaviors[e.behavior] = true
			if e.boss:
				bosses_seen[e.name] = true
			if e.shiny:
				shinies_seen[e.name] = true
		if sim.player.item != "":
			items_taken[sim.player.item] = true
		if sim.time >= next_print:
			next_print += 10.0
			if not quiet:
				var mv: Array = []
				for m in sim.player.moves:
					mv.append("%s%d%s" % [m["id"], int(m["lvl"]), "*" if m.get("evolved", false) else ""])
				print("  %5.1f  %5d  %6d  %5d  %4d  %4d %2d %3d  %4d  %4d/%-4d  %s" % [sim.time, sim.player.level, sim.player.kills,
					sim.enemies.count(), sim.projectiles.count(), es, sim.hazards.count(), sim.combat.field_count(),
					sim.pickups.count(), int(ceil(sim.player.hp)), int(sim.player.max_hp), " ".join(mv)])
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var frames := int(sim.time / dt)
	print("smoke: end t=%.1f s, state=%s, level %d, kills %d, bosses %d, alive %d (max %d), max projectiles %d, level-up/item picks %d, HP %d/%d" % [
		sim.time, sim.state, sim.player.level, sim.player.kills, sim.player.bosses, sim.enemies.count(), max_alive, max_proj, picks,
		int(ceil(sim.player.hp)), int(sim.player.max_hp)])
	print("smoke: max enemy shots %d, max hazards %d, max fields %d; kinds cast %s" % [max_enemy_shots, max_hazards, max_fields, str(kinds_cast.keys())])
	print("smoke: behaviors seen %s" % str(behaviors.keys()))
	print("smoke: bosses %s; shinies seen %s caught %d; items %s" % [str(bosses_seen.keys()), str(shinies_seen.keys()), sim.caught.size(), str(items_taken.keys())])
	# Phase 3b: interactables, events, rifts, bonds
	print("smoke: interact %s; events %s" % [str(sim.interact.stats), str(sim.events.history.map(func(h): return "%.0f:%s" % [h[0], h[1]]))])
	print("smoke: rifts %s; %.1f s in arenas (max %d enemies there); fusions %d; slots %s" % [
		str(sim.rift.history.map(func(h): return "%.0f:%s%s" % [h[0], h[1], (":" + str(h[2])) if h.size() > 2 and h[1] != "open" else ""])),
		arena_s, arena_max, fusions, str(sim.player.slots.map(func(g): return (g as Array).map(func(m): return m["id"])))])
	print("smoke: %d frames simulated in %.0f ms (%.2f ms/frame incl. bot, headless GDScript)" % [frames, ms, ms / maxf(1, frames)])
	print("smoke: Sim.update avg %.3f ms, max %.2f ms (at t=%.2f s); at the 64-enemy cap (%d frames): avg %.3f ms, max %.2f ms" % [
		st.us / 1000.0 / maxf(1, st.n), st.max / 1000.0, st.max_t, st.cap_n, st.cap_us / 1000.0 / maxf(1, st.cap_n), st.cap_max / 1000.0])
	quit(0)
