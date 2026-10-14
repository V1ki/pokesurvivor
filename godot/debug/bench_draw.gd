class_name BenchDraw
extends RefCounted
## Windowed frame benchmark for main.gd (`--bench=<frames>`, debug builds): after the run has
## played `--bench-warm` frames (default 600) it records `frames` frames of sim time, the world
## view's draw recording (with SimProf's per-pass sections), the RenderingServer's measured CPU /
## GPU render time of the viewport, draw calls and the wall time per frame, prints a summary and
## quits. Use it with the scenario flags of tests/bench.gd and a fixed frame step, e.g.
##   godot --path godot --fixed-fps 60 --disable-vsync --resolution 1320x608 -- --autoplay --god \
##       --bench=1800 --start-t=600 --learn=ember,heat-wave,rock-slide,spikes --move-lvl=5 --evolve \
##       --bonds=3 --boss-at=625 --event=horde --event-at=605 --seed=7

var frames := 1800
var warm := 600
var _n := 0
var _done := false
var _seen := 0
var _last_us := 0
var _vp := RID()
var sim_us := PackedInt32Array()
var draw_us := PackedInt32Array()
var wall_us := PackedInt32Array()
var rs_cpu := PackedFloat32Array()
var rs_gpu := PackedFloat32Array()
var calls := PackedInt32Array()
var prims := PackedInt32Array()
var items := PackedInt32Array()
var sections: Array[PackedInt32Array] = []

func _init(frames_: int, warm_: int) -> void:
	frames = maxi(1, frames_)
	warm = maxi(0, warm_)
	for i in SimProf.COUNT:
		sections.append(PackedInt32Array())
	SimProf.enable(true)

## Called by main.gd every frame after the simulation step.
func tick(game: Node, sim_time_us: int) -> void:
	if _done:
		return
	var sim: Sim = game.sim
	var wv: Node2D = game.world_view
	if not _vp.is_valid():
		_vp = game.get_viewport().get_viewport_rid()
		RenderingServer.viewport_set_measure_render_time(_vp, true)
		# --bench-hide=Ground,HUD,...: hide these nodes / layers (draw-call accounting per layer)
		for nm in str(game.args.get("bench-hide", "")).split(",", false):
			var nd: Node = game.find_child(nm, true, false)
			if nd != null:
				nd.set("visible", false)
				print("bench_draw: hidden ", nd.get_path())
	var now := Time.get_ticks_usec()
	var wall := now - _last_us
	_last_us = now
	# the previous frame's draw (recorded after this _process last frame)
	var d: int = wv.get("draw_us_acc")
	wv.set("draw_us_acc", 0)
	if sim.state != "playing":
		SimProf.reset()
		return
	_seen += 1
	if _seen <= warm:
		SimProf.reset()
		return
	sim_us.append(sim_time_us)
	draw_us.append(d)
	wall_us.append(wall)
	rs_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(_vp))
	rs_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(_vp))
	calls.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	prims.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	items.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME))
	for i in SimProf.COUNT:
		sections[i].append(SimProf.us[i])
	SimProf.reset()
	_n += 1
	if _n >= frames:
		_done = true
		_report(sim)
		# --bench-shot=<png>: the last frame, for a visual comparison between builds
		var shot := str(game.args.get("bench-shot", ""))
		if shot != "":
			await RenderingServer.frame_post_draw
			game.get_viewport().get_texture().get_image().save_png(shot)
		game.get_tree().quit(0)

static func _st(v: Variant, scale := 0.001) -> String:
	var s: Variant = v.duplicate()
	s.sort()
	var n: int = s.size()
	if n == 0:
		return "-"
	var sum := 0.0
	for x in s:
		sum += float(x)
	return "mean %7.3f  median %7.3f  p95 %7.3f  max %7.3f" % [sum / n * scale, float(s[n / 2]) * scale,
		float(s[mini(n - 1, int(n * 0.95))]) * scale, float(s[n - 1]) * scale]

func _report(sim: Sim) -> void:
	print("bench_draw: %d frames, %s, enemies %d, projectiles %d, fx %d, window %s" % [_n, Engine.get_version_info()["string"],
		sim.enemies.count(), sim.projectiles.count(), sim.fx.count(), str(DisplayServer.window_get_size())])
	print("  sim (ms)          " + _st(sim_us))
	print("  draw rec (ms)     " + _st(draw_us))
	for i in range(SimProf.FIRST_DRAW, SimProf.COUNT):
		print("    %-14s  %s" % [SimProf.NAMES[i], _st(sections[i])])
	print("  RS cpu (ms)       " + _st(rs_cpu, 1.0))
	print("  RS gpu (ms)       " + _st(rs_gpu, 1.0))
	print("  wall/frame (ms)   " + _st(wall_us))
	print("  draw calls        " + _st(calls, 1.0))
	print("  primitives        " + _st(prims, 1.0))
	print("  objects           " + _st(items, 1.0))
	var parts: PackedStringArray = []
	for i in SimProf.FIRST_DRAW:
		var s: PackedInt32Array = sections[i]
		var sum := 0
		for x in s:
			sum += x
		parts.append("%s=%.3f" % [SimProf.NAMES[i], sum / 1000.0 / maxf(1.0, s.size())])
	print("  sim sections (mean ms): " + " ".join(parts))
