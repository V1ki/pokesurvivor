class_name ParityTests
extends RefCounted
## Checks for the rules fixed by the feature-parity audit (docs/PARITY.md), run by
## tests/run_tests.gd: Spanish move-name order (localeCompare 'es'), the hud.js clipped bars,
## the public-profile preview, one pick per tap on the bond / item cards, the silent auto-pause
## and the item-choice click, the aura drain heal, import validation, the shipped credits and
## the zh / en texts added by the audit. Reference values: tests/fixtures/parity_vectors.json
## (exportParity() in tools/export_godot.js).

static func run(t) -> void:
	print("-- parity audit (docs/PARITY.md) --")
	var f := FileAccess.open("res://tests/fixtures/parity_vectors.json", FileAccess.READ)
	t.check("parity vectors exist", f != null)
	if f == null:
		return
	var v: Dictionary = JSON.parse_string(f.get_as_text())
	_sort(t, v)
	_fmt(t, v)
	_bars(t)
	_profile(t)
	_taps(t)
	_sounds(t)
	_drain(t)
	_import(t)
	_credits(t)
	_texts(t)

static func _sort(t, v: Dictionary) -> void:
	var ids: Array = Data.moves.map(func(m): return str(m["id"]))
	var got := UpgradesScreen._by_name(ids)
	var want: Array = v["moves_es"]
	var first_diff := -1
	for i in mini(got.size(), want.size()):
		if got[i] != want[i]:
			first_diff = i
			break
	t.check("ban picker / hotkeys: %d move names in localeCompare('es') order" % want.size(), got == want,
		"" if first_diff < 0 else "first difference at %d: %s vs %s" % [first_diff, got[first_diff], want[first_diff]])

static func _fmt(t, v: Dictionary) -> void:
	var bad := []
	for c in v["fmt"]:
		if GoalsScreen.fmt_time(int(c[0])) != str(c[1]):
			bad.append([c, GoalsScreen.fmt_time(int(c[0]))])
	t.check("profile times: goals-ui.js fmt (m:ss, h:mm:ss from 1 h)", bad.is_empty(), str(bad))

static func _bars(t) -> void:
	# HP bar at 2 %: a 3.36 px sliver inside the pill (it used to be widened to 11 px)
	var p := DrawUtil.clipped_round_rect_points(Rect2(10, 20, 168, 11), 5.5, Rect2(10, 20, 168 * 0.02, 11))
	var mx := -INF
	var mn := INF
	for q in p:
		mx = maxf(mx, q.x)
		mn = minf(mn, q.x)
	t.check("hud.js bar(): fill = rect w·frac clipped to the pill (2 %% -> %.2f px)" % (mx - mn), absf(mx - (10.0 + 3.36)) < 1e-4 and absf(mn - 10.0) < 1e-4)
	# full bar: the whole pill
	var full := DrawUtil.clipped_round_rect_points(Rect2(0, 0, 168, 11), 5.5, Rect2(0, 0, 168, 11))
	var fx := 0.0
	for q in full:
		fx = maxf(fx, q.x)
	t.check("bar at 100 %% reaches the pill end (%.2f)" % fx, absf(fx - 168.0) < 1e-4)
	# slot cooldown: fillRect(x, y, S, S·f) clipped to roundRect(12): flat bottom edge at S·f
	var cd := DrawUtil.clipped_round_rect_points(Rect2(0, 0, 54, 54), 12.0, Rect2(0, 0, 54, 54 * 0.5))
	var bottom := 0
	var maxy := 0.0
	var wide := 0.0
	for q in cd:
		maxy = maxf(maxy, q.y)
		if absf(q.y - 27.0) < 1e-4:
			bottom += 1
			wide = maxf(wide, q.x)
	t.check("slot cooldown at 50 %%: flat bottom edge at 27 px across the slot (%d pts, x up to %.1f)" % [bottom, wide],
		absf(maxy - 27.0) < 1e-4 and bottom == 2 and absf(wide - 54.0) < 1e-4)

static func _profile(t) -> void:
	var keep: Dictionary = Save.data
	var kl := Save.loaded
	var s := Save.new_save("Entrenador")
	var list := Progress.ach_list()
	# 10 unlocked: times 100·i; two of the same tier share a time (list order breaks the tie)
	var picked: Array = list.slice(0, 10)
	for i in picked.size():
		s["ach"][picked[i]["id"]] = 1000 + 100 * i
	s["ach"][picked[1]["id"]] = s["ach"][picked[0]["id"]]
	s["stats"]["bestTime"] = 3725
	s["stats"]["bossesTotal"] = 12345
	s["legends"] = {"150": 1, "151": 1}
	s["profile"] = {"favs": [{"dex": 25, "shiny": true}, {"dex": 4, "shiny": false}], "title": "Coleccionista"}
	Save.data = s
	Save.loaded = true
	var d := GoalsScreen.profile_data()
	Save.data = keep
	Save.loaded = kl
	# reference: Array.sort (stable) by tier desc then unlock time desc, top 8
	var idx := {}
	for i in list.size():
		idx[list[i]["id"]] = i
	var want: Array = picked.duplicate()
	want.sort_custom(func(a, b):
		if int(a["tier"]) != int(b["tier"]):
			return int(a["tier"]) > int(b["tier"])
		var ta := int(s["ach"][a["id"]])
		var tb := int(s["ach"][b["id"]])
		if ta != tb:
			return ta > tb
		return int(idx[a["id"]]) < int(idx[b["id"]]))
	want = want.slice(0, 8).map(func(a): return a["id"])
	t.check("profile preview: top-8 medals (tier, then newest; stable)", d["medals"] == want, str(d["medals"]))
	var b: Dictionary = d["best"]
	t.check("profile preview: marks + favourites + title from the save", int(b["solo"]) == 3725 and int(b["bosses"]) == 12345 and int(b["legends"]) == 2
		and int(b["medals"]) == 10 and (d["favs"] as Array).size() == 2 and bool(d["favs"][0]["shiny"]) and d["title"] == "Coleccionista", str(b))

static func _tap(card: Control) -> void:
	# a finger tap reaches a Control twice: as InputEventScreenTouch and as the emulated mouse press
	var st := InputEventScreenTouch.new()
	st.pressed = true
	card.gui_input.emit(st)
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	card.gui_input.emit(mb)

static func _taps(t) -> void:
	# built detached: during SceneTree._initialize the root is not inside the tree yet
	var b := BondUI.new()
	b._ready()
	var got: Array = []
	b.picked.connect(func(ms: Array): got.append(ms))
	var ms := [Moves.instance("ember", 1), Moves.instance("water-gun", 1), Moves.instance("thunder-shock", 1)]
	b.open({"mode": "pair", "loose": ms})
	_tap(b._cards.get_child(0))
	var step1 := got.is_empty() and str(b.first.get("id", "")) == "ember"
	var step2 := false
	var c := b._cards.get_child_count()
	if c > 0:
		_tap(b._cards.get_child(c - 1))
		step2 = got.size() == 1 and (got[0] as Array).size() == 2
	t.check("bond picker (pair): one tap picks one move (step 1 -> step 2 -> fuse)", step1 and step2, "first=%s picked=%d" % [b.first.get("id", ""), got.size()])
	b.free()
	var ic := ItemChoice.new()
	ic._ready()
	var n := [0]
	ic.chosen.connect(func(_i: int): n[0] += 1)
	ic.open("leftovers", "choiceband")
	_tap(ic._cards.get_child(1))
	t.check("item choice: one tap = one choice", n[0] == 1, str(n[0]))
	ic.free()

static func _sounds(t) -> void:
	var sim := Phase2Tests.new_sim(3)
	Sfx.test_log = []
	sim.toggle_pause(true)
	var quiet: bool = sim.state == "paused" and (Sfx.test_log as Array).is_empty()
	sim.toggle_pause()
	sim.toggle_pause()
	var loud: bool = (Sfx.test_log as Array) == ["pause"]
	t.check("auto-pause is silent (game.js autoPause); Esc / P pause plays 'pause'", quiet and loud, str(Sfx.test_log))
	sim.toggle_pause()
	sim.player.item = "leftovers"
	sim.offer_item("choiceband")
	Sfx.test_log = []
	var ok := sim.choose_item(1)
	t.check("item choice plays the card's UI 'click' (run-ui.js), not 'confirm'", ok and (Sfx.test_log as Array).has("click") and not (Sfx.test_log as Array).has("confirm"), str(Sfx.test_log))
	Sfx.test_log = null

static func _drain(t) -> void:
	var sim := Phase2Tests.new_sim(4)
	var pl := sim.player
	pl.x = 0.0
	pl.y = 0.0
	for i in 3:
		sim.enemies.add(Phase2Tests.enemy_of(19, 12.0 + i * 6.0, 0.0, 0, {"hp": 1000.0, "dmg": 1.0, "spd": 1.0}))
	sim.enemies.rebuild_grid()
	var m := Moves.instance("bulldoze", 1)
	pl.hp = pl.max_hp - 20.0
	var h0 := pl.hp
	sim.combat._aura(pl, m)
	var plain := pl.hp - h0
	m["drain"] = 3.0
	sim.combat._aura(pl, m)
	var drained := pl.hp - h0 - plain
	t.check("aura drain: heal min(Σ drain per enemy hit, 6) (combat.js; no move has it yet)", plain == 0.0 and absf(drained - 6.0) < 1e-9, "%.2f / %.2f" % [plain, drained])

static func _import(t) -> void:
	t.check("Save.import_error: garbage / a newer save / a valid one",
		Save.import_error("nope") != "" and Save.import_error("{\"v\":99}").contains("v99") and Save.import_error("{\"v\":3,\"coins\":5}") == "")

static func _credits(t) -> void:
	var names := SettingsScreen.credit_artists()
	t.check("CREDITS.md shipped: %d SpriteCollab artists listed in Acerca de" % names.size(), names.size() > 100 and names.has("CHUNSOFT") and names.has("Reimu_needs_$$$"))
	var ok := true
	for p in ["res://assets/fonts/OFL.txt", "res://assets/fonts/fusion-pixel/OFL.txt", "res://assets/fonts/fusion-pixel/LICENSES/ark-pixel/OFL.txt",
			"res://assets/fonts/fusion-pixel/LICENSES/cubic-11/OFL.txt", "res://assets/fonts/fusion-pixel/LICENSES/galmuri/LICENSE.txt"]:
		ok = ok and FileAccess.get_file_as_string(p).contains("Open Font License")
	t.check("font licences shipped (Pixelify Sans OFL, Fusion Pixel OFL + its sources)", ok)

static func _texts(t) -> void:
	var texts := ["Créditos completos", "Artistas (114)", "Licencia de Fusion Pixel Font", "Ocupa toda la pantalla, sin el marco de la ventana.",
		"Esta versión no tiene cuentas ni conexión: tu partida se guarda sólo en este dispositivo y no se envía a ningún sitio. No hay publicidad ni seguimiento.",
		"Tienes", "tickets y", "Sonido, gráficos, controles y cuenta", "Ver mi perfil público", "Aún sin medallas.", "Salir"]
	var keep := I18n.lang
	var keep_extra := I18n.use_extra
	I18n.use_extra = true
	var bad := []
	for l in ["en", "zh"]:
		I18n.set_lang(l)
		for s in texts:
			var tr := I18n.t(s)
			if tr == s or (l == "en" and s == "Salir" and tr != "Exit"):
				bad.append("%s:%s" % [l, s])
	I18n.use_extra = keep_extra
	I18n.set_lang(keep)
	t.check("audit texts translated in en and zh (I18nExtra / web dictionaries)", bad.is_empty(), str(bad))
