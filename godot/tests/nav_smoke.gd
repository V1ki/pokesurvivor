extends SceneTree
## Keyboard / gamepad-only navigation smoke test (Phase 5), with scripted input events through the
## real game scene (main.tscn) in Chinese:
##   godot --headless --path godot --script res://tests/nav_smoke.gd
## personality test (keyboard arrows + Enter) -> result (gamepad A) -> menu (d-pad + A on "Jugar")
## -> run -> forced level-up: d-pad down + A picks the 2nd card -> Start pauses -> d-pad + A opens
## Ajustes -> B closes it -> B resumes -> Android back pauses / resumes -> Esc pauses / resumes ->
## end of run -> results (Enter) -> menu -> back opens the quit dialog -> B closes it.
## In-memory save and settings (nothing is written). Exit code 0 = all passed.

var fails := 0
var game: Node
var picked := -1

func ok(name: String, cond: bool, detail := "") -> void:
	print("  %s  %s%s" % ["PASS" if cond else "FAIL", name, ("  (" + detail + ")") if detail != "" else ""])
	if not cond:
		fails += 1

func frames(n := 3) -> void:
	for i in n:
		await process_frame

func key(code: Key) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = down
		Input.parse_input_event(e)
		await frames(2)

func pad(btn: JoyButton) -> void:
	for down in [true, false]:
		var e := InputEventJoypadButton.new()
		e.device = 0
		e.button_index = btn
		e.pressed = down
		e.pressure = 1.0 if down else 0.0
		Input.parse_input_event(e)
		await frames(2)

func focus() -> Control:
	return root.gui_get_focus_owner()

func focus_text() -> String:
	var f := focus()
	return (f as Button).text if f is Button else (f.get_class() if f != null else "<none>")

func _initialize() -> void:
	Save.read_only = true
	Settings.load_cfg()
	Settings.read_only = true
	Settings.lang = "zh"
	game = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await frames(4)
	var meta: MetaUI = game.get("meta")
	var sim: Sim = game.get("sim")
	var screens: Screens = game.get("screens")
	var router: InputRouter = game.get_node("InputRouter")
	ok("zh active: Pausa -> 暂停", I18n.t("Pausa") == "暂停", I18n.t("Pausa"))
	ok("fresh save opens the personality test", meta.current == "test", meta.current)

	# ---- personality test with the keyboard: Down focuses the first answer, Enter answers ----
	var ts: TestScreen = meta.screens["test"]
	await key(KEY_DOWN)
	ok("keyboard focus lands on an answer", focus() is Button and (focus() as Button).theme_type_variation == "Answer", focus_text())
	for q in ts._q.size():
		await key(KEY_DOWN if q % 2 == 0 else KEY_UP)
		await key(KEY_ENTER)
	ok("8 answers given with Enter -> result", not ts.result.is_empty(), str(ts.idx))
	# ---- result: gamepad A on the focused "¡Vamos juntos!" ----
	await frames(2)
	ok("result: focus on ¡Vamos juntos!", focus_text() == "¡Vamos juntos!", focus_text())
	await pad(JOY_BUTTON_A)
	ok("A chose the partner -> menu", meta.current == "menu" and Save.partner() > 0, "%s partner %d" % [meta.current, Save.partner()])

	# ---- menu: focus on Jugar, d-pad moves, A plays ----
	await frames(2)
	var play_btn := focus()
	ok("menu: focus starts on Jugar", play_btn != null and play_btn.name == "play", str(play_btn.name if play_btn else "none"))
	await pad(JOY_BUTTON_DPAD_DOWN)
	ok("d-pad down moves the focus", focus() != null and focus() != play_btn, str(focus().name if focus() else "none"))
	await pad(JOY_BUTTON_DPAD_UP)
	ok("d-pad up comes back to Jugar", focus() == play_btn)
	await pad(JOY_BUTTON_A)
	await frames(4)
	ok("A on Jugar starts a run", sim.state == "playing" and sim.player != null, sim.state)

	# ---- level-up: d-pad down + A picks the second card ----
	screens.card_picked.connect(func(i: int): picked = i)
	sim.pending_levels += sim.player.gain_xp(sim.player.xp_next + 1.0)
	sim.maybe_level_up()
	await frames(4)
	ok("level-up screen open", sim.state == "levelup" and screens.is_open(), sim.state)
	ok("focus on the first card", focus() is PanelContainer, focus().get_class() if focus() else "none")
	var lvl := sim.player.level
	await pad(JOY_BUTTON_DPAD_DOWN)
	await pad(JOY_BUTTON_A)
	await frames(2)
	ok("d-pad down + A picked card 2", picked == 1 and sim.state == "playing", "picked %d state %s level %d" % [picked, sim.state, lvl])

	# ---- pause with Start, settings with d-pad + A, B closes / resumes ----
	await pad(JOY_BUTTON_START)
	ok("Start pauses", sim.state == "paused", sim.state)
	await frames(2)
	ok("pause: focus on Continuar", focus_text() == "Continuar", focus_text())
	await pad(JOY_BUTTON_DPAD_RIGHT)
	ok("d-pad right -> Ajustes", focus_text() == "Ajustes", focus_text())
	await pad(JOY_BUTTON_A)
	ok("A opens the settings over the pause", meta.settings_screen.visible and sim.state == "paused")
	await frames(2)
	ok("settings: focus inside the settings", focus() != null and meta.settings_screen.is_ancestor_of(focus()), focus_text())
	await pad(JOY_BUTTON_B)
	ok("B closes the settings, still paused", not meta.settings_screen.visible and sim.state == "paused", sim.state)
	await pad(JOY_BUTTON_B)
	ok("B resumes", sim.state == "playing", sim.state)

	# ---- Android back and Esc ----
	router.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await frames(2)
	ok("Android back pauses the run", sim.state == "paused", sim.state)
	router.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await frames(2)
	ok("Android back resumes", sim.state == "playing", sim.state)
	await key(KEY_ESCAPE)
	ok("Esc pauses", sim.state == "paused", sim.state)
	# game.js:456: with Ajustes open over the pause, Esc only closes it (the pause stays)
	meta.open_settings("sound")
	await frames(2)
	await key(KEY_ESCAPE)
	ok("Esc closes the settings over the pause, still paused", not meta.settings_screen.visible and sim.state == "paused", sim.state)
	await key(KEY_ESCAPE)
	ok("Esc resumes", sim.state == "playing", sim.state)

	# ---- results -> menu with Enter, back -> quit dialog, B closes it ----
	sim.end_run(false)
	await frames(6)
	ok("results open", meta.current == "results", meta.current)
	ok("results: focus on Volver al menú", focus_text() == "Volver al menú", focus_text())
	await key(KEY_ENTER)
	await frames(4)
	ok("Enter -> menu", meta.current == "menu", meta.current)
	router.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await frames(2)
	ok("back on the menu opens the quit dialog", router.quit_open())
	await frames(2)
	ok("quit dialog: focus on Cancelar", focus_text() == "Cancelar", focus_text())
	await pad(JOY_BUTTON_B)
	ok("B closes the quit dialog", not router.quit_open())

	print("== nav smoke: %s ==" % ("all passed" if fails == 0 else "%d failed" % fails))
	# let the threaded sprite loads of the run finish: quitting with loads in flight can crash the
	# engine at exit (unrelated to this test)
	await frames(300)
	root.remove_child(game)
	game.queue_free()
	await frames(2)
	quit(1 if fails > 0 else 0)
