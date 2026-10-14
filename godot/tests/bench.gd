extends SceneTree
## Deterministic hot-path benchmark (headless): a fixed-seed god-mode run at the 64-enemy cap,
## fixed dt = 1/60, scripted bot input, per-system timings from SimProf (Sim.update laps and
## world_view._draw laps), plus a state checksum to prove optimizations keep the results.
##   godot --headless --path godot --script res://tests/bench.gd -- [--frames=1800] [--warm=600]
##       [--seed=7] [--partner=4] [--no-draw] [--trace] [--json] [scenario flags]
## Default scenario (worst normal case): --start-t=600 (enemy cap, late tiers), four L5 evolved
## moves fused into one slot by 3 bonds (projectile + nova + meteor + mines all casting),
## a horde at 605 s and a boss at 625 s. Any Phase 2 / 3b debug flag (debug/autoshot2.gd)
## overrides the defaults, e.g. `--learn=ember --bonds=0`.
## The world view (render/world_view.gd) and the damage numbers (render/overlay.gd) record their
## draw commands every frame like in game
## (headless: the dummy RenderingServer discards them, so this is the GDScript recording cost;
## the windowed number is the "[perf] draw" line of `--autoplay --fixed-fps`). --no-draw skips it.
## Output: per-section mean / median / p95 / max in ms over the measured frames, the checksum
## (`--trace`: also every 60 frames) and with --json one "BENCH_JSON {...}" line for scripts.

const DEFAULTS := {"start-t": "600", "learn": "ember,heat-wave,rock-slide,spikes", "move-lvl": "5",
	"evolve": "", "bonds": "3", "boss-at": "625", "event": "horde", "event-at": "605"}

var sim: Sim
var view: Node2D
var overlay: Control
var args := {}
var dt := 1.0 / 60.0
var warm := 600
var frames := 1800
var frame := 0
var draw := true
var trace := false
var samples: Array[PackedInt32Array] = []     # per section, per measured frame (us)
var total_sim := PackedInt32Array()
var total_draw := PackedInt32Array()
var counts := {"enemies": 0, "proj": 0, "fields": 0, "hazards": 0, "parts": 0, "sprites": 0, "pickups": 0, "corpses": 0}
var _pending_draw := false
var _t_start := 0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var custom := args.has("learn") or args.has("start-t")
	for k in DEFAULTS:
		if not custom and not args.has(k):
			args[k] = DEFAULTS[k]
	warm = int(args.get("warm", "600"))
	frames = int(args.get("frames", "1800"))
	draw = not args.has("no-draw")
	trace = args.has("trace")
	var seed_v := int(args.get("seed", "7"))
	seed(seed_v)
	sim = Sim.new()
	sim.render = false
	sim.debug = Autoshot2.debug_from_args(args)
	sim.start_run(int(args.get("partner", "4")), seed_v)
	for i in SimProf.COUNT:
		samples.append(PackedInt32Array())
	SimProf.enable(true)
	if draw:
		view = Node2D.new()
		view.set_script(load("res://render/world_view.gd"))
		view.set("sim", sim)
		root.add_child(view)
		# only the world view's own _draw: drop the ground / liquid layers (Phase 3a painters)
		for c in view.get_children():
			if not (c is Camera2D):
				c.queue_free()
		# damage numbers (render/overlay.gd), screen space
		overlay = Control.new()
		overlay.set_script(load("res://render/overlay.gd"))
		overlay.set("sim", sim)
		root.add_child(overlay)
	print("bench: seed %d, warm %d + %d frames at dt=1/60, draw %s, debug %s" % [seed_v, warm, frames, draw, str(sim.debug)])
	_t_start = Time.get_ticks_msec()

func _process(_delta: float) -> bool:
	if sim == null or sim.player == null:
		push_error("bench: the simulation did not start (script error?)")
		quit(1)
		return true
	# the draw recorded at the end of the previous iteration
	if _pending_draw:
		_pending_draw = false
		_collect(false)
	if frame >= warm + frames:
		_report()
		return true
	# frozen states (level-up cards, item / bond choice) are resolved by the bot, untimed
	var guard := 0
	while sim.state == "levelup" or sim.state == "choice":
		Bot.pick(sim)
		guard += 1
		if guard > 20:
			break
	sim.input_axis = Bot.axis(sim)
	sim.player.god = true
	sim.player.hp = sim.player.max_hp
	SimProf.reset()
	var t0 := Time.get_ticks_usec()
	sim.update(dt)
	var us := Time.get_ticks_usec() - t0
	if frame >= warm:
		total_sim.append(us)
		_collect(true)
		counts["enemies"] += sim.enemies.count()
		counts["proj"] += sim.projectiles.count()
		counts["fields"] += sim.combat.field_count()
		counts["hazards"] += sim.hazards.count()
		counts["parts"] += _parts()
		counts["sprites"] += sim.fx.sprites.size()
		counts["pickups"] += sim.pickups.count()
		counts["corpses"] += sim.enemies.corpses.size()
		if draw:
			view.call("sync_camera")
			view.queue_redraw()
			overlay.queue_redraw()
			_pending_draw = true
	if trace and frame % 60 == 0:
		print("trace %5d t=%.3f %s" % [frame, sim.time, checksum()])
	frame += 1
	return false

## Moves this frame's SimProf sections into the samples (sim sections or draw sections).
func _collect(sim_part: bool) -> void:
	var a := 0 if sim_part else SimProf.FIRST_DRAW
	var b := SimProf.FIRST_DRAW if sim_part else SimProf.COUNT
	var tot := 0
	for i in range(a, b):
		samples[i].append(SimProf.us[i])
		tot += SimProf.us[i]
		SimProf.us[i] = 0
	if not sim_part:
		total_draw.append(tot)

## Exact state digest: run clock, player, every enemy / projectile / pickup / field / hazard,
## kills; `final` also adds the next global random number (any change in RNG use shows up).
func checksum(final := false) -> String:
	var f := PackedFloat64Array()
	var pl := sim.player
	f.append_array([sim.time, pl.x, pl.y, pl.hp, pl.xp, pl.level, pl.kills, pl.coins, pl.dmg_dealt])
	for e in sim.enemies.list:
		f.append_array([e.id, e.x, e.y, e.hp, e.kx, e.ky, e.shot_cd, e.shield])
	for e in sim.enemies.corpses:
		f.append_array([e.id, e.fade])
	for p in sim.projectiles.list:
		f.append_array([p.x, p.y, p.vx, p.vy, p.t])
	for p in sim.pickups.list:
		f.append_array([p.x, p.y, p.vx, p.vy])
	for fl in sim.combat.fields:
		f.append_array([fl.x, fl.y, fl.t])
	for h in sim.hazards.list:
		f.append_array([h.x, h.y, h.t])
	f.append(_parts())
	f.append(sim.fx.sprites.size())
	if final:
		f.append(randi())
	return "%08x" % (hash(f.to_byte_array()) & 0xFFFFFFFF)

## Live FX particles (array of objects before the packed rewrite, so the bench runs on both).
func _parts() -> int:
	return sim.fx.n_parts if "n_parts" in sim.fx else (sim.fx.get("parts") as Array).size()

static func _stats(v: PackedInt32Array) -> Array:
	if v.is_empty():
		return [0.0, 0.0, 0.0, 0.0]
	var s := v.duplicate()
	s.sort()
	var sum := 0
	for x in s:
		sum += x
	var n := s.size()
	return [sum / 1000.0 / n, s[n / 2] / 1000.0, s[mini(n - 1, int(n * 0.95))] / 1000.0, s[n - 1] / 1000.0]

func _report() -> void:
	var n := maxi(1, total_sim.size())
	var out := {"sections": {}, "total_sim": _stats(total_sim), "total_draw": _stats(total_draw)}
	print("bench: %d frames measured in %.1f s wall; avg alive %.1f, corpses %.1f, projectiles %.1f, fields %.1f, hazards %.1f, particles %.0f, fx sprites %.0f, pickups %.0f" % [
		n, (Time.get_ticks_msec() - _t_start) / 1000.0, counts["enemies"] / float(n), counts["corpses"] / float(n),
		counts["proj"] / float(n), counts["fields"] / float(n), counts["hazards"] / float(n), counts["parts"] / float(n),
		counts["sprites"] / float(n), counts["pickups"] / float(n)])
	print("bench: kills %d, level %d, t=%.1f s" % [sim.player.kills, sim.player.level, sim.time])
	print("  section          mean    median     p95      max   (ms)")
	for i in SimProf.COUNT:
		if i == SimProf.FIRST_DRAW:
			var t := _stats(total_sim)
			print("  %-12s %8.3f %8.3f %8.3f %8.3f" % ["SIM TOTAL", t[0], t[1], t[2], t[3]])
			if not draw:
				break
		var s := _stats(samples[i])
		out["sections"][SimProf.NAMES[i]] = s
		print("  %-12s %8.3f %8.3f %8.3f %8.3f" % [SimProf.NAMES[i], s[0], s[1], s[2], s[3]])
	if draw:
		var t := _stats(total_draw)
		print("  %-12s %8.3f %8.3f %8.3f %8.3f" % ["DRAW TOTAL", t[0], t[1], t[2], t[3]])
	var cs := checksum(true)
	print("bench: checksum %s" % cs)
	if args.has("json"):
		out["checksum"] = cs
		print("BENCH_JSON " + JSON.stringify(out))
