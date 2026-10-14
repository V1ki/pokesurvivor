extends SceneTree
## Headless smoke test of the Phase 4 screens' actions (no rendering checks; script errors fail):
##   godot --headless --path godot --script res://tests/meta_ui_smoke.gd
## In-memory save (never written): personality test -> choose, buy upgrades, ban/hotkeys, partner
## change, gacha pull, mission claim/reroll, favourites/title, settings toggles, import, delete.

var fails := 0

func ok(name: String, cond: bool) -> void:
	print("  %s  %s" % ["PASS" if cond else "FAIL", name])
	if not cond:
		fails += 1

func _initialize() -> void:
	Data.ensure()
	Save.read_only = true
	Save.load_or_create()
	var ui := MetaUI.new()
	root.add_child(ui)
	await process_frame
	ui.start_test()
	var ts: TestScreen = ui.screens["test"]
	for i in ts._q.size():
		ts._answer(ts._q[ts.idx]["a"][(i * 3) % 4])
	ok("test -> result", not ts.result.is_empty())
	ts._open_starters()
	ts.choose(7)
	ok("choose starter: partner 7 owned, personality saved", Save.partner() == 7 and Save.owns(7) and Save.data["personality"] is Dictionary)
	ok("menu open", ui.current == "menu")
	Save.data["coins"] = 100000
	ui.open("upgrades")
	var up: UpgradesScreen = ui.screens["upgrades"]
	for i in 3:
		up._buy("ban")
	up._buy("hp")
	up._buy("moves")
	ok("upgrades bought (ban 3, hp 1, moves 1)", int(Save.upgrades_of(7)["ban"]) == 3 and int(Save.upgrades_of(7)["hp"]) == 1 \
		and int(Save.data["coins"]) == 100000 - 300 - 570 - 1080 - 60 - 1500)
	up.ban_open = true
	up._render()
	await process_frame
	var bl := up._ban_list()
	bl.append_array(["tackle", "bubble"])
	Save.data["pbind"]["7"] = ["water-gun", null, "tackle", null]
	up._render()
	await process_frame
	var setup := Meta.run_setup(4)
	ok("run setup: dex 7, perks hp 8, startMoves 2, bind + ban", int(setup["dex"]) == 7 and float(setup["opts"]["perks"]["hp"]) == 8.0 \
		and int(setup["opts"]["perks"]["startMoves"]) == 2 and setup["opts"]["bind"][2] == "tackle" and setup["opts"]["ban"].size() == 2)
	var sim := Sim.new()
	sim.render = false
	sim.start_run(int(setup["dex"]), 5, setup["opts"])
	ok("run starts with 2 moves, bans and hotkeys applied", sim.player.moves.size() == 2 and sim.player.banned.has("tackle") \
		and sim.player.max_hp == float(Data.dex_by[7]["hp"]) + 8.0)
	sim.time = 125.0
	sim.player.kills = 40
	sim.player.t1 = 2
	Meta.reset_bank()
	Meta.bank_tickets(sim.player)
	var t1 := int(Save.data["tickets"]["t1"])
	sim.end_run(false)
	Meta.apply_run(sim.result, sim.player)
	ok("end of run: runs 1, kills 40, coins +35, tickets banked once", Save.stat("runs") == 1 and Save.stat("totalKills") == 40 \
		and int(sim.result["coins"]) == 35 and int(Save.data["tickets"]["t1"]) == t1)
	ui.show_results(sim.result)
	await process_frame
	ui.open("dex")
	var dx: DexScreen = ui.screens["dex"]
	Save.grant(150, "gacha")
	Save.grant_shiny(150, "gacha")
	dx.gen = 1
	dx.filter = "shiny"
	dx.open()
	dx._select(150)
	dx.view_shiny = true
	dx._pick(150, true)
	ok("collection: choose shiny Mewtwo as partner", Save.partner() == 150 and Save.data["partnerShiny"] == true)
	ui.open("gacha")
	var gs: GachaScreen = ui.screens["gacha"]
	Progress.check_ach()          # grant pending achievements (their rewards include tickets) first
	Save.data["tickets"]["t1"] = 1
	gs._pull(1, "t1")
	ok("gacha x1 pull spent the ticket", int(Save.data["tickets"]["t1"]) == 0 and Save.stat("pulls") == 1)
	gs._pull(10, "t1")          # unaffordable: toast, nothing changes
	ok("gacha unaffordable pull refused", Save.stat("pulls") == 1)
	ui.open("goals")
	var M: Dictionary = Save.data["missions"]
	M["daily"][0]["prog"] = M["daily"][0]["goal"]
	var gl: GoalsScreen = ui.screens["goals"]
	gl.render()
	ok("mission claim", Progress.claim(M["daily"][0]) and Save.stat("missionsDone") == 1)
	ok("mission reroll", Progress.reroll(1))
	gl.tab = "ach"
	gl.cat = "legendarios"
	gl.render()
	gl.tab = "profile"
	gl.render()
	gl._pick_fav(0)
	await process_frame
	ui.open_settings("gfx")
	var st := ui.settings_screen
	for t in ["sound", "gfx", "ctl", "save", "about"]:
		st.tab = t
		st.render()
	Settings.quality = "low"
	Settings.save_cfg()
	ok("settings: quality low -> fx 0", Settings.fx == 0)
	Settings.quality = "auto"
	Settings.save_cfg()
	var raw := FileAccess.get_file_as_string("res://tests/fixtures/web_guest_save.json")
	var err := Save.import_json(raw)
	st.after_save_change()
	ok("import from settings path -> menu with partner 936", err == "" and Save.partner() == 936 and ui.current == "menu")
	Save.delete_save()
	st.after_save_change()
	ok("delete save -> personality test", Save.data["partner"] == null and ui.current == "test")
	print("== meta UI smoke: %d failed ==" % fails)
	quit(1 if fails > 0 else 0)
