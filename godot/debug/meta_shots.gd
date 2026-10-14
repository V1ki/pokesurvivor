class_name MetaShots
extends Node
## Visual check of the Phase 4 screens (part of the autoshot harness):
##   godot --path godot -- --metashot=<dir> [--import-ui=<web save .json>] [--save=user://x.json]
## (--import-ui pastes the file into Settings > Partida and presses Importar + confirm, like a player)
## Walks menu -> collection -> upgrades (+ ban picker) -> gacha -> x10 pull (slot machine + reveal)
## -> missions / achievements / legendaries / profile -> settings -> personality test / result /
## starters -> run results -> achievement popup, saving one PNG per step, then quits.
## Runs on an in-memory save (nothing is written) unless --save is given.

var g: Node
var dir := ""
var meta: MetaUI

func run(game: Node, d: String) -> void:
	g = game
	dir = d
	meta = game.get("meta")
	DirAccess.make_dir_recursive_absolute(dir)
	game.add_child(self)          # keeps this object (and its coroutine) alive
	_seq()

func _wait(s: float) -> void:
	await g.get_tree().create_timer(s).timeout

func _shot(key: String) -> void:
	await RenderingServer.frame_post_draw
	var img := g.get_viewport().get_texture().get_image()
	var path := dir.path_join(key + ".png")
	img.save_png(path)
	print("metashot: ", path)

## First Button under `root` whose text is `text`.
static func _button(root: Node, text: String) -> Button:
	for c in root.find_children("*", "Button", true, false):
		if (c as Button).text == text:
			return c
	return null

func _seq() -> void:
	# --import-ui=<file>: import a web save through Settings > Partida exactly like a player
	var imp := str((g.get("args") as Dictionary).get("import-ui", ""))
	if imp != "":
		await _wait(1.0)
		meta.open_settings("save")
		var st := meta.settings_screen
		st._import_text.text = FileAccess.get_file_as_string(imp)
		await _wait(0.3)
		await _shot("import_paste")
		_button(st, "Importar").pressed.emit()
		await _wait(0.3)
		await _shot("import_confirm")
		_button(st, "Importar").pressed.emit()        # the confirmation's "Importar"
		print("metashot: imported via Settings: %d Pokémon, %d coins, partner %d" % [Save.owned_count(), int(Save.data["coins"]), Save.partner()])
	await _wait(2.0)                       # backdrop / partner atlases load
	await _shot("menu")
	meta._sound_btn.pressed.emit()          # top bar: sound panel (ui.js soundControls)
	await _wait(0.3)
	await _shot("menu_sound")
	meta._sound_btn.pressed.emit()
	meta.open("dex")
	await _wait(1.2)
	await _shot("collection")
	var dex: DexScreen = meta.screens["dex"]
	dex.filter = "miss"
	dex._build_filters()
	dex._render_grid()
	await _wait(0.8)
	await _shot("collection_missing")
	dex.filter = "all"
	meta.open("upgrades")
	# the most upgraded Pokémon (shows pips, maxed cards and the Veto picker when it has bans)
	var up: UpgradesScreen = meta.screens["upgrades"]
	var best := Save.partner()
	for d in Save.owned_list():
		if UpgradesScreen.levels_total(d) > UpgradesScreen.levels_total(best):
			best = d
	up.dex = best
	if Save.read_only:                     # debug save: show the Veto picker with banned chips
		Save.upgrades_of(best)["ban"] = 2
		var pool := Moves.pool_for(Data.dex_by[best]).filter(func(id): return id != Moves.start_move_of(best))
		Save.data["pban"] = {str(best): pool.slice(0, 2)}
	up.open()
	if int(Save.upgrades_of(best).get("ban", 0)) > 0:
		up.ban_open = true
		up._render()
	await _wait(1.0)
	up._scroll.scroll_vertical = 100000          # down to the Veto picker and the hotkeys
	await _wait(0.2)
	await _shot("upgrades")
	meta.open("gacha")
	await _wait(1.2)
	await _shot("gacha")
	# x10 pull on the debug save (free tickets so the harness can always pull)
	if Save.read_only:
		Save.data["tickets"]["t1"] = int(Save.data["tickets"]["t1"]) + 10
	var gs: GachaScreen = meta.screens["gacha"]
	Gacha.force_shiny = 1
	var res := Gacha.pull(Save.data, 10, gs.gen, "t1")
	Progress.check_ach()
	Save.commit()
	gs.play_results(res)
	await _wait(0.9)
	await _shot("gacha_slots")
	# wait for the 3rd reel's suspense on a big prize if any
	await _wait(1.6)
	await _shot("gacha_slots2")
	var guard := 0
	while not gs._close.visible and guard < 400:
		await _wait(0.1)
		guard += 1
	await _wait(0.5)
	await _shot("gacha_reveal")
	gs._close_fx()
	meta.open("goals")
	await _wait(0.6)
	await _shot("missions")
	var goals: GoalsScreen = meta.screens["goals"]
	goals.tab = "ach"
	goals.cat = "coleccion"
	goals.render()
	await _wait(0.6)
	await _shot("achievements")
	goals.cat = "legendarios"
	goals.render()
	await _wait(1.2)
	await _shot("achievements_legend")
	goals.tab = "profile"
	goals.render()
	await _wait(1.0)
	await _shot("profile")
	goals.show_profile()
	await _wait(1.0)
	await _shot("profile_view")
	goals.close_profile()
	meta.open_menu()
	meta.open_settings("gfx")
	await _wait(0.4)
	await _shot("settings")
	meta.settings_screen.tab = "save"
	meta.settings_screen.render()
	await _wait(0.4)
	await _shot("settings_save")
	# About + its sub-pages (credits / licences / legal notice)
	for sub in ["", "credits", "fusion", "legal"]:
		meta.settings_screen.tab = "about"
		meta.settings_screen.about_sub = sub
		meta.settings_screen.render()
		await _wait(0.4)
		await _shot("settings_about" + ("_" + sub if sub != "" else ""))
	meta.settings_screen.close()
	# personality test (nothing is chosen: the save is not changed)
	meta.start_test()
	await _wait(0.4)
	await _shot("test")
	var ts: TestScreen = meta.screens["test"]
	for i in ts._q.size():
		ts._answer(ts._q[ts.idx]["a"][i % 4])
	await _wait(1.0)
	await _shot("test_result")
	ts._open_starters()
	await _wait(1.0)
	await _shot("starters")
	# run results (a sample run: the real end-of-run path is covered by --autoshot)
	var r := {"dead": true, "time": 312.4, "level": 14, "kills": 655, "bosses": 1, "coins": 391, "t1": 2, "t10": 1,
		"moves": [{"id": "ember", "name": "Ascuas", "lvl": 5}, {"id": "tackle", "name": "Placaje", "lvl": 3}],
		"breakdown": Meta.run_coins(312.4, 655, 1, 37, 1.4)["breakdown"], "record": true,
		"caught": [{"dex": 25, "isNew": true}]}
	meta.show_results(r)
	await _wait(1.0)
	await _shot("results")
	meta.open_menu()
	Progress.notify("¡Logro: Vence a Mewtwo!", "", Progress.ach_by("leg_150"))
	Progress.notify("¡Logro: Coleccionista!", "Nuevo título: Coleccionista", Progress.ach_by("own50"))
	await _wait(0.8)
	await _shot("popup")
	# a real (short) run through the normal flow: start from the menu, quit -> results -> menu
	var runs0 := Save.stat("runs")
	g.call("start_run")
	await _wait(4.0)
	await _shot("run")
	# Phase 5: the in-run modals in the current language / layout (level-up, item swap, pause)
	var sim: Sim = g.get("sim")
	sim.pending_levels += sim.player.gain_xp(sim.player.xp_next + 1.0)
	sim.maybe_level_up()
	await _wait(0.5)
	await _shot("run_levelup")
	g.call("_pick", 0)
	await _wait(0.2)
	(g.get("item_ui") as ItemChoice).open("leftovers", "choiceband")
	await _wait(0.4)
	await _shot("run_item")
	(g.get("item_ui") as ItemChoice).close()
	# the bond picker (pair mode; compact: two cards per row)
	var bu: BondUI = g.get("bond_ui")
	bu.open({"mode": "pair", "loose": [Moves.instance("ember", 2), Moves.instance("water-gun", 1), Moves.instance("thunder-shock", 3)]})
	await _wait(0.4)
	await _shot("run_bond")
	bu.close()
	g.call("toggle_pause")
	await _wait(0.4)
	await _shot("run_pause")
	g.call("toggle_pause")
	await _wait(0.2)
	g.get("sim").call("end_run", false)
	await _wait(1.2)
	await _shot("results_run")
	meta.results_closed.emit()
	await _wait(1.5)
	await _shot("menu_after_run")
	print("metashot: runs %d -> %d, coins %d" % [runs0, Save.stat("runs"), int(Save.data["coins"])])
	await _wait(0.3)
	g.get_tree().quit()
