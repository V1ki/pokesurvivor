extends Node
## Game root (G.Game / G.Flow, js/game.js): builds the layers, drives the Sim with real
## input (keyboard / gamepad / touch), mirrors the camera and shows the modal screens.
##
## Debug command-line options (after `--`):
##   --autoshot=<dir>   start a run at once, move in circles, save screenshots and quit
##   --partner=<dex>    partner Pokémon (default 4, Charmander)
##   --seed=<n>         world seed
##   --touch            force the touch UI (pause button, joystick demo)
##   --fps              show the FPS counter
##   --autoplay         the bot plays forever (restarts after each run): device benchmark
##   --god              with --autoplay: the player takes no damage (full 64-enemy load)
##   --bot=<profile>    who plays bot runs: legacy (default) | novice | casual | expert (debug/bot.gd);
##                      --bot-set=k=v,... overrides that profile's numbers
##   --speed=<n>        with --autoplay: fast-forward, n simulation steps per frame (same dt, so the
##                      game plays the same, only n times faster); each run's result is printed
##   --p2               with --autoshot: Phase 2 visual check (debug/autoshot2.gd)
##   --metashot=<dir>   Phase 4 visual check of the meta screens (debug/meta_shots.gd), then quit
##   --import=<file>    import a web-game save JSON through the real import path at start
##   --save=<path>      save file to use (default user://save.json); without it autoshot/autoplay/
##                      metashot use a fresh in-memory save that is never written
##   --learn=a,b --move-lvl=n --evolve --boss-at=s --boss-gap=s --force-shiny=n --item=id --cycle --start-t=s
##                      Phase 2 debug options (see debug/autoshot2.gd)
##   --event=horde,gold,lost,thief --event-at=s --rift-at=s --rift-type=t --bonds=n --seek
##                      Phase 3b debug options (see debug/autoshot2.gd); --p3b with --autoshot:
##                      Phase 3b visual check (debug/autoshot3b.gd)
##   --p3a              with --autoshot: Phase 3a visual check (debug/autoshot3a.gd: biomes, liquids,
##                      props, weathers, crossfade); every autoshot paints the visible ground synchronously
## Debug builds also print a "[perf]" line every 5 s (logcat tag "godot" on Android).

## Vignette (world.js drawVignette) + fog (game.js: rgba(200,205,220, 0.45*fog) from 0.32*min to
## 0.62*max, drawn over it), composited into one "over" colour. fog = Weather.vignette() (WeatherLayer).
const VIGNETTE_SHADER := """
shader_type canvas_item;
uniform vec2 size = vec2(1280.0, 720.0);
uniform float fog = 0.0;
void fragment() {
	vec2 p = UV * size;
	float d = length(p - size * 0.5);
	float r0 = 0.34 * min(size.x, size.y);
	float r1 = 0.78 * max(size.x, size.y);
	float a1 = 0.5 * clamp((d - r0) / (r1 - r0), 0.0, 1.0);
	float f0 = 0.32 * min(size.x, size.y);
	float f1 = 0.62 * max(size.x, size.y);
	float a2 = 0.45 * fog * clamp((d - f0) / (f1 - f0), 0.0, 1.0);
	float a = 1.0 - (1.0 - a1) * (1.0 - a2);
	vec3 c = a > 0.0 ? vec3(200.0, 205.0, 220.0) / 255.0 * (a2 / a) : vec3(0.0);
	COLOR = vec4(c, a);
}
"""

var sim: Sim
var world_view: Node2D
var overlay: Control
var hud: Control
var touch: TouchInput
var screens: Screens
var item_ui: ItemChoice
var bond_ui: BondUI
var meta: MetaUI
var backdrop: MenuBackdrop
var vignette: ColorRect
var partner := 4
var seed_arg := -1
var args: Dictionary = {}

# autoshot state
var _shot_dir := ""
var _shots_done: Dictionary = {}
var _real_t := 0.0

# autoplay + perf log state (debug only)
var _autoplay := false
var _auto_wait := 0.0
var _speed := 1                  # --speed: sim steps per frame in --autoplay
var _auto_runs := 0              # --autoplay: runs played, best one, result already printed
var _auto_best: Dictionary = {}
var _auto_logged := false
var _perf := {"t": 0.0, "frames": 0, "max": 0.0, "sim_us": 0, "sim_max_us": 0}
var _bench: BenchDraw = null       # --bench=<frames>: windowed frame benchmark (debug/bench_draw.gd)

func _ready() -> void:
	_parse_args()
	add_child(AndroidDisplay.new())   # 120 Hz on Android 15+ (no-op elsewhere)
	_presentation()
	Data.ensure()
	DrawUtil.fonts()
	sim = Sim.new()
	sim.level_up_ready.connect(_on_level_up)
	sim.run_over.connect(_on_run_over)
	sim.item_choice_ready.connect(func(cur: String, next: String): item_ui.open(cur, next))
	sim.bond_ready.connect(func(opt: Dictionary): bond_ui.open(opt))
	sim.debug = Autoshot2.debug_from_args(args)

	world_view = Node2D.new()
	world_view.name = "WorldView"
	world_view.set_script(load("res://render/world_view.gd"))
	world_view.set("sim", sim)
	add_child(world_view)
	backdrop = MenuBackdrop.new()
	backdrop.name = "MenuBackdrop"
	add_child(backdrop)

	vignette = ColorRect.new()
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = VIGNETTE_SHADER
	mat.shader = sh
	vignette.material = mat
	var vl := _layer(2, "Vignette")               # above the damage numbers (Overlay), like game.js
	var weather_layer := WeatherLayer.new()      # weather tint + particles, under the vignette (Phase 3a)
	weather_layer.sim = sim
	weather_layer.vignette_mat = mat
	vl.add_child(weather_layer)
	vl.add_child(vignette)
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	overlay = Control.new()
	overlay.set_script(load("res://render/overlay.gd"))
	overlay.set("sim", sim)
	_layer(1, "Overlay").add_child(overlay)        # fx.js texts are world-pass: under weather, fog and vignette

	touch = TouchInput.new()
	touch.game = self
	hud = Control.new()
	hud.set_script(load("res://ui/hud.gd"))
	hud.set("sim", sim)
	hud.set("touch", touch)
	hud.set("game", self)
	_layer(3, "HUD").add_child(hud)
	_layer(4, "Touch").add_child(touch)
	if args.has("touch"):
		touch.active = true

	screens = Screens.new()
	_layer(5, "Screens").add_child(screens)
	screens.play_pressed.connect(start_run)
	screens.card_picked.connect(func(i: int): _pick(i))
	screens.reroll_pressed.connect(func(): _reroll())
	screens.resume_pressed.connect(func(): toggle_pause())
	screens.quit_pressed.connect(func(): sim.end_run(false))
	screens.again_pressed.connect(start_run)
	screens.menu_pressed.connect(_to_menu)
	screens.settings_pressed.connect(func(): meta.open_settings("sound"))
	item_ui = ItemChoice.new()
	screens.get_parent().add_child(item_ui)
	item_ui.chosen.connect(_choose_item)
	bond_ui = BondUI.new()
	screens.get_parent().add_child(bond_ui)
	bond_ui.picked.connect(func(ms: Array): sim.choose_bond(ms))
	meta = MetaUI.new()
	_layer(6, "Meta").add_child(meta)
	meta.play_pressed.connect(start_run)
	meta.results_closed.connect(_to_menu)
	meta.quit_run_requested.connect(_quit_run)
	meta.save_replaced.connect(_on_save_replaced)

	get_viewport().size_changed.connect(_on_resize)
	_on_resize()
	_load_profile()
	if OS.is_debug_build():
		SimProf.enable(true)        # per-system breakdown in the [perf] lines
		if args.has("bench"):
			_bench = BenchDraw.new(int(args["bench"]), int(args.get("bench-warm", "600")))
	if args.has("fps"):
		Settings.show_fps = true
	if _shot_dir != "":
		DirAccess.make_dir_recursive_absolute(_shot_dir)
		world_view.get("ground").set("sync_paint", true)     # screenshots never show placeholder ground
	_enter_meta()
	if args.has("metashot"):
		MetaShots.new().run(self, str(args["metashot"]))

## Phase 5: settings + language (central translation of every Control and drawn text), the
## phone UI scale and the input router (Android back button, gamepad / keyboard focus).
## Debug: --lang=es|en|zh (not saved), --ui-scale=<px per canvas px>.
func _presentation() -> void:
	Settings.load_cfg()
	if _shot_dir != "" or _autoplay or args.has("metashot"):
		Settings.read_only = true
	if args.has("lang"):
		Settings.lang = str(args["lang"])
	I18n.set_lang(Settings.lang)
	I18n.install()
	if args.has("i18n-missing"):            # debug: list the texts left untranslated at exit
		I18n.record_missing = true
	Presentation.setup(get_window(), args)
	UIKit.compact = Presentation.compact(Presentation.canvas_size(get_window()))
	UIKit.install_global()
	var router := InputRouter.new()
	router.name = "InputRouter"
	router.game = self
	add_child(router)

func _exit_tree() -> void:
	if I18n.record_missing:
		var f := FileAccess.open(str(args["i18n-missing"]), FileAccess.WRITE)
		if f != null:
			for k in I18n.missing:
				f.store_line(JSON.stringify(k))
	I18n.uninstall()          # a script Translation left in TranslationServer crashes at exit

func _layer(z: int, nm: String) -> CanvasLayer:
	var l := CanvasLayer.new()
	l.layer = z
	l.name = nm
	add_child(l)
	return l

func _parse_args() -> void:
	var raw: Array = Array(OS.get_cmdline_user_args()) + Array(OS.get_cmdline_args())
	# Debug builds on a phone: Godot 4.7's launcher activity drops intent extras, so the same
	# flags can be put one per line in user://debug_args.txt (adb shell run-as <pkg> ... files/).
	if OS.is_debug_build() and FileAccess.file_exists("user://debug_args.txt"):
		raw += Array(FileAccess.get_file_as_string("user://debug_args.txt").split("\n", false)).map(
			func(s: String) -> String: return s.strip_edges())
	for a: String in raw:
		if not a.begins_with("--"):
			continue
		var kv := a.substr(2).split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	if args.has("autoshot"):
		_shot_dir = args["autoshot"] if args["autoshot"] != "" else "user://shots"
	if args.has("partner"):
		partner = int(args["partner"])
	if args.has("seed"):
		seed_arg = int(args["seed"])
	_autoplay = args.has("autoplay") and _shot_dir == ""
	_speed = clampi(int(args.get("speed", "1")), 1, 64) if _autoplay else 1

func _on_resize() -> void:
	var vs := get_viewport().get_visible_rect().size
	sim.cam.resize(vs.x, vs.y)
	if vignette != null:
		(vignette.material as ShaderMaterial).set_shader_parameter("size", vs)

# ---------------- flow ----------------

## Settings + the local save (Phase 4). Debug runs (bots, screenshot harnesses) use a fresh
## in-memory save that is never written, and bot runs don't advance missions/achievements.
func _load_profile() -> void:
	Settings.load_cfg()
	var debug := _shot_dir != "" or _autoplay or args.has("metashot")
	if args.has("save"):
		Save.path = str(args["save"])
	elif debug:
		Save.read_only = true
		Progress.enabled = args.has("metashot")
	Save.load_or_create()
	if args.has("import"):
		var err := Save.import_json(FileAccess.get_file_as_string(str(args["import"])))
		print("import ", args["import"], ": ", "ok" if err == "" else err)
	# bots need a partner: skip the personality test on a fresh debug save
	if debug and Save.data.get("partner") == null:
		Save.data["partner"] = partner
		Save.data["starter"] = partner
		Save.grant(partner, "starter")
		Save.commit()

## Menu world + menu (or the personality test when the save has no partner yet).
func _enter_meta() -> void:
	screens.hide_all()
	Sfx.music("village")          # G.Flow: every menu (test, menu, after a run) plays the village theme
	backdrop.begin(sim)
	if Save.data.get("partner") == null:
		meta.start_test()
	else:
		meta.open_menu()

func start_run() -> void:
	screens.hide_all()
	meta.hide_all()
	backdrop.end()
	touch.reset()
	# the saved partner with its upgrades / hotkeys / bans; --partner overrides it (debug)
	var setup := Meta.run_setup(partner)
	if args.has("partner"):
		setup = {"dex": partner, "opts": setup["opts"] if int(setup["dex"]) == partner else {}}
	Meta.reset_bank()
	if args.has("bench-sync") and seed_arg >= 0:
		seed(seed_arg)               # reproducible benchmark run (debug/bench_draw.gd)
	sim.start_run(int(setup["dex"]), seed_arg, setup["opts"])
	if args.has("bench-sync"):
		# deterministic frames for comparing builds: terrain and ground painted synchronously
		sim.world.async_chunks = false
		world_view.get("ground").set("sync_paint", true)
	_real_t = 0.0

func _to_menu() -> void:
	sim.state = "ui"
	sim.player = null
	_enter_meta()

## settings-ui.js deleting the save: G.Game.quit() first (the run ends and is banked into the
## save that is about to go; the import does the same before replacing it).
func _quit_run() -> void:
	if sim.state != "ui" and sim.state != "over":
		sim.end_run(false)

## ... then music(null) and the menu flow again (MetaUI opens the test or the menu): the
## village theme restarts and an ended run (or its results) gives way to the menu world.
func _on_save_replaced() -> void:
	Sfx.music("")
	Sfx.music("village")
	if sim.state != "ui":
		sim.state = "ui"
		sim.player = null
		screens.hide_all()
		backdrop.begin(sim)

func toggle_pause(quiet := false) -> void:
	if sim.state == "playing":
		sim.toggle_pause(quiet)
		touch.reset()
		screens.show_pause(touch.active)
	elif sim.state == "paused":
		sim.toggle_pause()
		screens.hide_all()

func _choose_item(i: int) -> void:
	if sim.choose_item(i):
		item_ui.close()

func _on_level_up(level: int, cards: Array) -> void:
	screens.show_level_up(level, cards, sim.rerolls_left())

func _pick(i: int) -> void:
	if sim.pick_card(i):
		screens.hide_all()

func _reroll() -> void:
	sim.reroll()

func _on_run_over(r: Dictionary) -> void:
	screens.hide_all()
	Meta.apply_run(r, sim.player)       # coins, stats, runEnd, achievements, commit (game.js endRun)
	meta.show_results(r)

func _notification(what: int) -> void:
	# game.js autoPause (visibilitychange → hidden): switching apps on a phone, or minimizing the
	# window on desktop, pauses the run silently (losing focus to another window does not)
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		var hidden := OS.has_feature("mobile") or what == NOTIFICATION_APPLICATION_PAUSED \
			or DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED
		if hidden and sim != null and sim.state == "playing" and _shot_dir == "" and not _autoplay:      # the benchmark bot keeps playing
			toggle_pause(true)

# ---------------- frame ----------------

func _axis() -> Vector2:
	var t := touch.vector()
	if t != Vector2.ZERO:
		return t
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")

func _handle_keys() -> void:
	if sim.state == "choice" and not sim.bond_opt.is_empty():
		# bond picker: 1-4 pick a card
		for i in 4:
			if Input.is_action_just_pressed("pick_%d" % (i + 1)):
				bond_ui.pick(i)
				return
		return
	if sim.state == "choice":
		for i in 2:
			if Input.is_action_just_pressed("pick_%d" % (i + 1)):
				_choose_item(i)
				return
		return
	if sim.state == "levelup":
		for i in 3:
			if Input.is_action_just_pressed("pick_%d" % (i + 1)):
				_pick(i)
				return
		if Input.is_action_just_pressed("reroll"):
			_reroll()
		return
	if sim.state == "ui" or sim.state == "over":
		return          # menus: Esc is handled by MetaUI._unhandled_input
	if meta.settings_screen.visible or meta.settings_closed_frame == Engine.get_process_frames():
		return          # settings over the pause screen: Esc closes it (MetaUI), and only that
	if Input.is_action_just_pressed("pause"):
		toggle_pause()
		return
	if sim.state != "playing" or sim.player == null:
		return
	for i in 4:
		if Input.is_action_just_pressed("slot_%d" % (i + 1)):
			sim.player.set_active(i)
	if Input.is_action_just_pressed("cycle_prev"):
		sim.player.cycle(-1)
	if Input.is_action_just_pressed("cycle_next"):
		sim.player.cycle(1)

func _process(delta: float) -> void:
	# JS: dt = min(1/30, real) — below 30 FPS the simulation slows down (no catch-up)
	var dt := minf(delta, 1.0 / 30.0)
	_real_t += delta
	if _autoplay:
		_autoplay_tick(delta)
	elif _shot_dir == "":
		_handle_keys()
		sim.input_axis = _axis()
	else:
		_autoshot_input()
	var t0 := Time.get_ticks_usec()
	if sim.state == "playing":
		sim.update(dt)
		# --autoplay --speed=n: n-1 more steps of the same dt this frame (fast-forward)
		for i in _speed - 1:
			if sim.state != "playing":
				break
			sim.input_axis = Bot.axis(sim)
			sim.update(dt)
		Meta.bank_tickets(sim.player)     # tickets are saved as soon as they are picked up
		Settings.sample(delta)
	else:
		sim.idle_tick(dt)
		if sim.state == "ui":
			backdrop.step(dt)
	if OS.is_debug_build():
		var sim_us := Time.get_ticks_usec() - t0
		_perf_log(delta, sim_us)
		if _bench != null:
			_bench.tick(self, sim_us)
	(world_view as Node2D).call("sync_camera")
	world_view.queue_redraw()
	overlay.queue_redraw()
	hud.queue_redraw()
	if _shot_dir != "":
		_autoshot_tick()

# ---------------- autoplay + perf log (device benchmark, debug only) ----------------

func _autoplay_tick(delta: float) -> void:
	_auto_wait += delta * _speed
	if sim.state == "over" and not _auto_logged:
		_auto_logged = true
		_auto_runs += 1
		var r := sim.result
		if _auto_best.is_empty() or float(r["time"]) > float(_auto_best["time"]):
			_auto_best = r
		print("[autoplay] run %d (%s): %d:%02d, level %d, %d kills, %d coins · best %d:%02d" % [_auto_runs, Bot.profile,
			int(r["time"]) / 60, int(r["time"]) % 60, r["level"], r["kills"], r["coins"],
			int(_auto_best["time"]) / 60, int(_auto_best["time"]) % 60])
	match sim.state:
		"ui", "over":
			if _auto_wait > 2.0:
				_auto_wait = 0.0
				_auto_logged = false
				start_run()
		"levelup", "choice":
			if _auto_wait > 0.3:
				_auto_wait = 0.0
				Bot.pick(sim)
				screens.hide_all()
				item_ui.close()
				bond_ui.close()
		"playing":
			_auto_wait = 0.0
			sim.input_axis = Bot.axis(sim)
			if args.has("god") and sim.player != null:
				sim.player.invuln = 1.0
				sim.player.god = true          # telegraphs ignore i-frames

func _perf_log(delta: float, sim_us: int) -> void:
	_perf.t += delta
	_perf.frames += 1
	_perf.max = maxf(_perf.max, delta)
	_perf.sim_us += sim_us
	_perf.sim_max_us = maxi(_perf.sim_max_us, sim_us)
	if _perf.t < 5.0:
		return
	var n: int = _perf.frames
	var dacc: int = world_view.get("draw_us_acc")
	var dmax: int = world_view.get("draw_us_max")
	world_view.set("draw_us_acc", 0)
	world_view.set("draw_us_max", 0)
	print("[perf] fps=%.1f frame_avg=%.2fms frame_max=%.1fms sim_avg=%.2fms sim_max=%.2fms draw_avg=%.2fms draw_max=%.2fms state=%s t=%.0f lvl=%d enemies=%d proj=%d fx=%d refresh=%.0fHz" % [
		n / _perf.t, _perf.t * 1000.0 / n, _perf.max * 1000.0, _perf.sim_us / 1000.0 / n, _perf.sim_max_us / 1000.0,
		dacc / 1000.0 / n, dmax / 1000.0, sim.state, sim.time, sim.player.level if sim.player != null else 0, sim.enemies.count(),
		sim.projectiles.count(), sim.fx.count(), DisplayServer.screen_get_refresh_rate()])
	# ground (Phase 3a): chunks painted on workers (avg/max per chunk) and main-thread cost of the layers
	print("[perf] ground ", world_view.get("ground").call("take_perf", world_view.get("liquid")))
	if SimProf.on and _bench == null:
		print("[perf] sim  ", SimProf.take(0, SimProf.FIRST_DRAW, n))
		print("[perf] draw ", SimProf.take(SimProf.FIRST_DRAW, SimProf.COUNT, n))
	_perf = {"t": 0.0, "frames": 0, "max": 0.0, "sim_us": 0, "sim_max_us": 0}

# ---------------- autoshot (visual check harness) ----------------

func _autoshot_input() -> void:
	if args.has("p3a"):
		sim.input_axis = Autoshot3a.axis(self)
		return
	if args.has("p3b"):
		sim.input_axis = Autoshot3b.axis(self)
		return
	var a := sim.time * 0.7
	sim.input_axis = Bot.axis(sim) if sim.time > 1.0 else Vector2.ZERO
	if args.has("touch") and sim.state == "playing" and sim.time > 1.0:
		# draw the joystick as if a finger were dragging it
		var vs := get_viewport().get_visible_rect().size
		var o := Vector2(vs.x * 0.18, vs.y * 0.72)
		touch.stick = {"id": 0, "ox": o.x, "oy": o.y, "x": o.x + cos(a) * 40.0, "y": o.y + sin(a) * 40.0}

func _autoshot_tick() -> void:
	if sim.state == "ui":
		if _real_t > 0.6 and not _shots_done.has("title"):
			_shot("title")
		elif _shots_done.has("title") and _real_t > 1.0:
			start_run()
		return
	if args.has("p2"):
		Autoshot2.tick(self)
		return
	if args.has("p3b"):
		Autoshot3b.tick(self)
		return
	if args.has("p3a"):
		Autoshot3a.tick(self)
		return
	if sim.state == "choice":
		Bot.pick(sim)
		item_ui.close()
		bond_ui.close()
		return
	if sim.state == "levelup":
		if not _shots_done.has("levelup"):
			_shot("levelup")
		elif _real_t > 0.0 and not _shots_done.has("_lv_wait"):
			_shots_done["_lv_wait"] = _real_t
		elif _shots_done.has("_lv_wait") and _real_t - float(_shots_done["_lv_wait"]) > 0.4:
			_shots_done.erase("_lv_wait")
			Bot.pick(sim)
			screens.hide_all()
		return
	if sim.state == "over" and not _shots_done.has("over"):
		_shot("over")
		get_tree().create_timer(1.0).timeout.connect(func(): get_tree().quit())
		return
	if sim.state == "playing" and sim.time >= 30.0 and not _shots_done.has("pause"):
		toggle_pause()
		_shot("pause")
		get_tree().create_timer(0.4).timeout.connect(func(): toggle_pause())
		return
	for t in [3.0, 20.0, 45.0]:
		var key := "t%02d" % int(t)
		if sim.time >= t and not _shots_done.has(key):
			_shot(key)
	if sim.time >= 46.0 and not _shots_done.has("quit"):
		_shots_done["quit"] = true
		get_tree().create_timer(0.5).timeout.connect(func(): get_tree().quit())

func _shot(key: String) -> void:
	_shots_done[key] = true
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := _shot_dir.path_join("%s.png" % key)
	img.save_png(path)
	var ready := 0
	var total := 0
	for e in sim.enemies.drawables(sim.cam):
		total += 1
		var sh := Sprites.sheet(e.dex, e.anim.cur)
		if sh != null and sh.state == Sprites.READY:
			ready += 1
	var ps: Sprites.Sheet = Sprites.sheet(partner, "Idle") if sim.player != null else null
	print("autoshot: ", path, " (t=%.1f, level %d, kills %d, enemies %d; partner sheet %s, on-screen enemy sheets ready %d/%d)" % [
		sim.time, sim.player.level if sim.player else 0, sim.player.kills if sim.player else 0, sim.enemies.count(),
		"ready" if ps != null and ps.state == Sprites.READY else "MISSING", ready, total])
