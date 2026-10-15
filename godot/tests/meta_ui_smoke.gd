extends SceneTree
## Headless smoke test of the Phase 4 screens' actions (no rendering checks; script errors fail):
##   godot --headless --path godot --script res://tests/meta_ui_smoke.gd
## In-memory save (never written): personality test -> choose, buy trainer upgrades, hotkeys, the
## family (unlock a form with shards, pick it), partner change, gacha pull, mission claim/reroll,
## favourites/title, settings toggles, import, delete.

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
	up._buy("hp")
	up._buy("hp")
	up._buy("regen")
	up._buy("atk")              # not a trainer upgrade any more: nothing happens
	ok("trainer upgrades bought (hp 2, regen 1)", int(Save.data["trainer"]["hp"]) == 2 and int(Save.data["trainer"]["regen"]) == 1 \
		and not Save.data["trainer"].has("atk") \
		and int(Save.data["coins"]) == 100000 - Upgrades.cost("hp", 0) - Upgrades.cost("hp", 1) - Upgrades.cost("regen", 0))
	Save.data["pbind"]["7"] = ["water-gun", null, "tackle", null]
	up._render()
	await process_frame
	var setup := Meta.run_setup(4)
	var sm: Array = setup["opts"]["start_moves"]
	ok("run setup: dex 7, trainer hp 16, its family's moves, hotkeys", int(setup["dex"]) == 7 and float(setup["opts"]["perks"]["hp"]) == 16.0 \
		and sm.size() == 1 and Moves.def(sm[0])["type"] == "water" and (setup["opts"]["pool"] as Array).has(sm[0]) \
		and setup["opts"]["bind"][2] == "tackle" and not setup["opts"].has("ban"))
	var sim := Sim.new()
	sim.render = false
	sim.start_run(int(setup["dex"]), 5, setup["opts"])
	ok("run starts with the family's move, the cards' pool and the trainer's HP", sim.player.moves.size() == 1 \
		and sim.player.moves[0]["id"] == sm[0] and sim.player.move_pool == setup["opts"]["pool"] \
		and sim.player.max_hp == float(Data.dex_by[7]["hp"]) + 16.0)
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
	var fx: Dictionary = sim.result.get("fam", {})
	ok("end of run: family XP 0.5/s + 1/kill (62.5 + 40 -> 103; level 2 needs 120)", int(fx.get("gained", 0)) == 103 \
		and int(fx.get("lv", 0)) == 1 and int(fx.get("need", 0)) == 120 and int(Families.fam(Save.data, Families.fam_of(7))["xp"]) == 103)
	ui.show_results(sim.result)
	await process_frame
	# the family: Wartortle needs level 16 and 20 shards (rarity 2), then it can be picked
	ui.open("upgrades")
	var f7 := Families.fam_of(7)
	Families.fam(Save.data, f7)["shards"] = 25
	up._unlock(8)
	ok("family level 1: Wartortle can't be unlocked yet", not Save.owns(8))
	Families.fam(Save.data, f7)["lv"] = 16
	up._unlock(8)
	ok("family level 16: Wartortle unlocked with 20 shards", Save.owns(8) and int(Families.fam(Save.data, f7)["shards"]) == 5)
	up._pick(8)
	ok("Wartortle picked as partner", Save.partner() == 8)
	up._render()
	await process_frame
	Save.data["partner"] = 7
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
