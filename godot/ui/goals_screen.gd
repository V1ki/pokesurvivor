class_name GoalsScreen
extends Control
## Missions / Achievements / Profile (js/ui/goals-ui.js). Missions: 3 daily + 2 weekly with
## progress bars, reset countdown (Madrid time), claim / reroll. Achievements: category chips,
## medal cards with progress, the legendary silhouette grid. Profile: 3 favourites, a title and
## the public-profile preview (#scr-profile, built from the local save like the web's app mode).

var ui: MetaUI
var tab := "missions"
var cat := "coleccion"
var _tabs: HBoxContainer
var _scroll: ScrollContainer
var _body: VBoxContainer
var _view: Control = null          # #scr-profile (the public-profile preview)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pg := MetaUI.page(self, "Misiones", func(): ui.open_menu(), 1000.0)
	var root: VBoxContainer = pg["root"]
	_tabs = UIKit.hbox(6)
	root.add_child(_tabs)
	for pair in [["missions", "Misiones"], ["ach", "Logros"], ["profile", "Perfil"]]:
		var id: String = pair[0]
		var b := UIKit.button(pair[1], "Tab", func():
			tab = id
			render(), "click")
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_tabs.add_child(b)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(_scroll)
	_body = UIKit.vbox(8)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_body)

func open(t := "") -> void:
	if t != "":
		tab = t
	close_profile()
	Progress.ensure(Save.data)
	Progress.check_ach()
	render()

func render() -> void:
	for i in _tabs.get_child_count():
		(_tabs.get_child(i) as Button).theme_type_variation = "TabOn" if ["missions", "ach", "profile"][i] == tab else "Tab"
	for c in _body.get_children():
		c.queue_free()
	match tab:
		"missions": _missions()
		"ach": _achievements()
		_: _profile()
	ui.refresh_coins()

# ---------------- missions ----------------

## "Se renuevan en ..." — next Madrid midnight (daily) or next Monday 00:00 (weekly).
static func until_text(weekly: bool) -> String:
	var now := Save.now_ms() / 1000
	var off := Progress.madrid_offset(now)
	var loc: Dictionary = Time.get_datetime_dict_from_unix_time(now + off)
	var secs_today: int = int(loc["hour"]) * 3600 + int(loc["minute"]) * 60 + int(loc["second"])
	var left := 86400 - secs_today
	if weekly:
		var wd: int = int(loc["weekday"])
		if wd == 0:
			wd = 7
		left += ((8 - wd) % 7) * 86400
	var mins := maxi(1, int(round(left / 60.0)))
	if mins >= 1440:
		return "%d d %d h" % [mins / 1440, (mins % 1440) / 60]
	return "%d h %d min" % [mins / 60, mins % 60]

func _reward_box(r: Dictionary) -> HBoxContainer:
	var h := UIKit.hbox(4)
	if r.get("t10", 0):
		h.add_child(UIKit.icon("ticket10", 12))
		h.add_child(UIKit.label("%d ×10" % int(r["t10"]), 13))
	if r.get("t1", 0):
		h.add_child(UIKit.icon("ticket", 12))
		h.add_child(UIKit.label(str(int(r["t1"])), 13))
	if r.get("coins", 0):
		h.add_child(UIKit.icon("coin", 12))
		h.add_child(UIKit.label(str(int(r["coins"])), 13))
	return h

func _missions() -> void:
	var M: Dictionary = Save.data["missions"]
	for sec in [["Diarias", "daily", false], ["Semanales", "weekly", true]]:
		var head := UIKit.hbox(8, [UIKit.label(sec[0], 19), UIKit.spacer(0, 0, true), UIKit.label("Se renuevan en " + until_text(sec[2]), 14, UIKit.MUTED)])
		_body.add_child(head)
		var list: Array = M.get(sec[1], [])
		for i in list.size():
			_body.add_child(_mission_row(list[i], i, sec[2], bool(M.get("rerolled", false))))
		_body.add_child(UIKit.spacer(0, 6))

func _mission_row(m: Dictionary, i: int, weekly: bool, rerolled: bool) -> PanelContainer:
	var def := Progress.mission_def(str(m["id"]))
	var done := Progress.done(m)
	var p := UIKit.panel("Inset")
	if m.get("claimed", false):
		p.modulate = Color(1, 1, 1, 0.6)
	elif done:
		p.add_theme_stylebox_override("panel", UIKit.sb(Color(1.0, 0.824, 0.247, 0.12), UIKit.GOLD, 2, 10, 10, 8))
	var h := UIKit.hbox(12)
	p.add_child(h)
	var v := UIKit.vbox(4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(UIKit.label(Progress.text(m), 16))
	var b := UIKit.bar(float(m["prog"]) / float(m["goal"]), UIKit.GOLD, 0, 8)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(b)
	v.add_child(UIKit.label("%s / %s" % [UIKit.num_es(mini(int(m["prog"]), int(m["goal"]))), UIKit.num_es(int(m["goal"]))], 12, UIKit.MUTED))
	h.add_child(v)
	h.add_child(_reward_box(def.get("reward", {})))
	var btn: Button
	if m.get("claimed", false):
		btn = UIKit.button("Recogido", "SmallButton")
		btn.disabled = true
	elif done:
		btn = UIKit.button("Recoger", "SmallGold", func():
			if Progress.claim(m, weekly):
				Sfx.play("buy")
				ui.toast("¡Premio recogido!")
				render(), "")
	elif not weekly and not rerolled:
		btn = UIKit.button("Cambiar", "SmallGhost", func():
			if Progress.reroll(i):
				render(), "click")
		btn.tooltip_text = "Cambia esta misión por otra (una vez al día)"
	else:
		btn = UIKit.button("En curso", "SmallGhost")
		btn.disabled = true
	btn.custom_minimum_size = Vector2(110, 0)
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(btn)
	return p

# ---------------- achievements ----------------

func _achievements() -> void:
	var s := Save.data
	var all := Progress.ach_list()
	var got := 0
	for a in all:
		if (s["ach"] as Dictionary).has(a["id"]):
			got += 1
	_body.add_child(UIKit.label("%d de %d logros · títulos: %d" % [got, all.size(), Progress.titles().size()], 15, UIKit.MUTED))
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 6)
	chips.add_theme_constant_override("v_separation", 6)
	for c in Progress.ach_cats():
		var k: String = c[0]
		var list := all.filter(func(a): return a["cat"] == k)
		var n := list.filter(func(a): return (s["ach"] as Dictionary).has(a["id"])).size()
		chips.add_child(UIKit.button("%s %d/%d" % [c[1], n, list.size()], "ChipOn" if k == cat else "Chip", func():
			cat = k
			render(), "click"))
	_body.add_child(chips)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for a in all:
		if a["cat"] == cat and not a.has("dex"):
			grid.add_child(_ach_card(a, s))
	_body.add_child(grid)
	if cat == "legendarios":
		var legs := all.filter(func(a): return a.has("dex"))
		var beaten := legs.filter(func(a): return (s["legends"] as Dictionary).has(str(a["dex"]))).size()
		_body.add_child(UIKit.label("Legendarios vencidos %d / %d" % [beaten, legs.size()], 18))
		var lg := HFlowContainer.new()
		lg.add_theme_constant_override("h_separation", 6)
		lg.add_theme_constant_override("v_separation", 6)
		for a in legs:
			var ok := (s["legends"] as Dictionary).has(str(a["dex"]))
			var cell := UIKit.panel("Inset")
			cell.custom_minimum_size = Vector2(84, 0)
			if ok:
				cell.add_theme_stylebox_override("panel", UIKit.sb(Color(1.0, 0.824, 0.247, 0.12), UIKit.GOLD, 2, 10, 4, 4))
			var cv := UIKit.vbox(0)
			cv.add_child(PokeView.make(int(a["dex"]), 64, 56, {"px": 1, "silhouette": not ok, "shadow": ok}))
			cv.add_child(UIKit.label(str(Data.dex_by[int(a["dex"])]["name"]) if ok else "???", 11, UIKit.INK if ok else UIKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
			cell.add_child(cv)
			cell.tooltip_text = str(a["name"]) + (" · ¡vencido!" if ok else "")
			lg.add_child(cell)
		_body.add_child(lg)

func _ach_card(a: Dictionary, s: Dictionary) -> PanelContainer:
	var ok := (s["ach"] as Dictionary).has(a["id"])
	var v := mini(int(a["goal"]), Progress.ach_value(a, s))
	var p := UIKit.panel("Inset")
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if ok:
		p.add_theme_stylebox_override("panel", UIKit.sb(Color(1.0, 0.824, 0.247, 0.1), Color(UIKit.GOLD, 0.7), 2, 10, 10, 8))
	var h := UIKit.hbox(10)
	p.add_child(h)
	h.add_child(UIKit.icon("medal%d" % int(a["tier"]) if ok else "medalOff", 36))
	var tv := UIKit.vbox(2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(UIKit.label(str(a["name"]), 16, UIKit.INK))
	var d := UIKit.label(str(a["desc"]), 13, UIKit.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true)
	d.custom_minimum_size = Vector2(240, 0)
	tv.add_child(d)
	if not ok:
		var b := UIKit.bar(float(v) / float(a["goal"]), UIKit.GOLD, 0, 6)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.add_child(b)
	var rw := UIKit.hbox(4, [UIKit.label("¡Conseguido!" if ok else "%s / %s" % [UIKit.num_es(v), UIKit.num_es(int(a["goal"]))], 12, UIKit.GOLD if ok else UIKit.INK),
		UIKit.label("·", 12, UIKit.MUTED), _reward_box(a["reward"])])
	if str(a.get("title", "")) != "":
		rw.add_child(UIKit.label("· Título: " + str(a["title"]), 12, UIKit.GOLD))
	tv.add_child(rw)
	h.add_child(tv)
	return p

# ---------------- profile ----------------

func _profile() -> void:
	var s := Save.data
	if not (s.get("profile") is Dictionary):
		s["profile"] = {"favs": [], "title": ""}
	var P: Dictionary = s["profile"]
	_body.add_child(UIKit.label("Tu perfil se publica cuando juegas con una cuenta online.", 14, UIKit.MUTED))      # goals-ui.js, offline text
	_body.add_child(UIKit.label("Tus 3 Pokémon favoritos", 18))
	var favs := UIKit.hbox(10)
	var list: Array = P.get("favs", [])
	for i in 3:
		var f: Variant = list[i] if i < list.size() else null
		# .fav-slot: a div outside ui.js CLICKABLE (no UI sound)
		var b := UIKit.button("", "Cell", func(): _pick_fav(i), "", false)
		b.custom_minimum_size = Vector2(150, 140)
		if f is Dictionary and Data.dex_by.has(int(f["dex"])):
			b.add_child(_fav_view(f, 150.0))
		else:
			b.text = "Elegir"
		favs.add_child(b)
	_body.add_child(favs)
	_body.add_child(UIKit.spacer(0, 8))
	_body.add_child(UIKit.label("Título", 18))
	var titles := Progress.titles()
	var ob := OptionButton.new()
	ob.focus_mode = Control.FOCUS_NONE
	ob.custom_minimum_size = Vector2(320, 0)
	ob.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	ob.add_item("(sin título)")
	for t in titles:
		ob.add_item(str(t))
	ob.select(titles.find(P.get("title", "")) + 1)
	ob.item_selected.connect(func(k: int):
		P["title"] = titles[k - 1] if k > 0 else ""
		Save.commit()
		Sfx.play("confirm"))
	_body.add_child(ob)
	if titles.is_empty():
		_body.add_child(UIKit.label("Consigue logros para desbloquear títulos.", 13, UIKit.MUTED))
	var prev := UIKit.button("Ver mi perfil público", "GoldButton", show_profile)
	prev.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_body.add_child(UIKit.spacer(0, 6))
	_body.add_child(prev)

## A favourite inside a 140 px slot: lively sprite + "[shiny] Name".
static func _fav_view(f: Dictionary, w: float) -> Control:
	var d := int(f["dex"])
	var sh := bool(f.get("shiny", false))
	var v := UIKit.vbox(0)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.size = Vector2(w, 136)
	var pv := PokeView.make(d, 120, 100, {"px": 2, "full": true, "lively": true, "shiny": sh})
	pv.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(pv)
	var nm := UIKit.hbox(4)
	nm.alignment = BoxContainer.ALIGNMENT_CENTER
	if sh:
		nm.add_child(UIKit.icon("shiny", 12))
	nm.add_child(UIKit.label(str(Data.dex_by[d]["name"]), 14, UIKit.INK, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(nm)
	return v

# ---------------- public profile preview (G.ProfileUI.showData(G.Social.profileData())) ----------------

## Social.profileData(): what others would see — built from the local save (offline).
static func profile_data() -> Dictionary:
	var s := Save.data
	var st: Dictionary = s["stats"]
	var prof: Dictionary = s.get("profile", {}) if s.get("profile") is Dictionary else {}
	var ach: Dictionary = s["ach"] if s.get("ach") is Dictionary else {}
	var unlocked: Array = []
	var order := {}
	for a in Progress.ach_list():
		order[a["id"]] = order.size()
		if ach.has(a["id"]):
			unlocked.append(a)
	# tier desc, then most recent first (JS Array.sort is stable: list order breaks ties)
	unlocked.sort_custom(func(a, b):
		if int(a["tier"]) != int(b["tier"]):
			return int(a["tier"]) > int(b["tier"])
		if int(ach[a["id"]]) != int(ach[b["id"]]):
			return int(ach[a["id"]]) > int(ach[b["id"]])
		return int(order[a["id"]]) < int(order[b["id"]]))
	var favs: Array = []
	for f in (prof.get("favs", []) as Array).slice(0, 3):
		if f is Dictionary:
			favs.append({"dex": int(f.get("dex", 0)), "shiny": bool(f.get("shiny", false))})
	var legends: Variant = s.get("legends")
	return {"name": str(s.get("name", "Invitado")), "favs": favs, "title": str(prof.get("title", "")),
		"best": {"solo": int(st.get("bestTime", 0)), "group": int(st.get("bestGroupTime", 0)), "level": int(st.get("bestLevel", 0)),
			"bosses": int(st.get("bossesTotal", 0)), "legends": (legends as Dictionary).size() if legends is Dictionary else 0,
			"kills": int(st.get("totalKills", 0)), "medals": unlocked.size()},
		"medals": unlocked.slice(0, 8).map(func(a): return a["id"])}

## goals-ui.js fmt: h:mm:ss from one hour on.
static func fmt_time(t: int) -> String:
	if t >= 3600:
		return "%d:%s" % [t / 3600, U.mmss(float(t % 3600)).lpad(5, "0")]
	return U.mmss(float(t))

func show_profile() -> void:
	close_profile()
	var d := profile_data()
	var b: Dictionary = d["best"]
	_view = Control.new()
	_view.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_view)
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.set_script(load("res://ui/dim_bg.gd"))
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(ev: InputEvent):          # a click outside the box closes it
		if ev is InputEventMouseButton and ev.pressed:
			close_profile())
	_view.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var cc := CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.add_child(cc)
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := PanelContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.custom_minimum_size = Vector2(minf(640.0, size.x - 24.0), 0)
	cc.add_child(box)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var lim := minf(560.0, size.y * 0.9 - 50.0)          # .profile-box: max-height 90vh, scrolls
	sc.custom_minimum_size = Vector2(0, lim)
	box.add_child(sc)
	var v := UIKit.vbox(8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	var close := UIKit.button("Cerrar", "SmallGhost", close_profile)
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.set_meta("focus_first", true)
	v.add_child(close)
	var nm := UIKit.label(str(d["name"]), 26)
	nm.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED     # <h2 translate="no">
	var head := UIKit.hbox(12, [nm])
	if str(d["title"]) != "":
		var tl := UIKit.panel("", UIKit.label(str(d["title"]), 15, UIKit.GOLD))
		tl.add_theme_stylebox_override("panel", UIKit.sb(Color(0, 0, 0, 0), UIKit.GOLD, 2, 8, 8, 1))
		tl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(tl)
	v.add_child(head)
	var favs := HFlowContainer.new()
	favs.add_theme_constant_override("h_separation", 12)
	for f in d["favs"]:
		if not Data.dex_by.has(int(f["dex"])):
			continue
		var slot := PanelContainer.new()       # .fav-slots.view .fav-slot: solid gold border
		slot.add_theme_stylebox_override("panel", UIKit.sb(Color(0, 0, 0, 0.28), Color(1.0, 0.824, 0.247, 0.55), 3, 10))
		slot.custom_minimum_size = Vector2(140, 140)
		slot.add_child(_fav_view(f, 134.0))
		favs.add_child(slot)
	if favs.get_child_count() == 0:
		v.add_child(UIKit.label("Sin favoritos todavía.", 14, UIKit.MUTED))
	else:
		v.add_child(favs)
	var marks := GridContainer.new()
	marks.columns = 3 if size.x > 600.0 else 2
	marks.add_theme_constant_override("h_separation", 6)
	marks.add_theme_constant_override("v_separation", 6)
	for m in [["Mejor tiempo", fmt_time(int(b["solo"]))], ["En grupo", fmt_time(int(b["group"]))], ["Nivel máximo", str(int(b["level"]))],
			["Jefes", UIKit.num_es(int(b["bosses"]))], ["Legendarios", str(int(b["legends"]))], ["Derrotados", UIKit.num_es(int(b["kills"]))]]:
		var val := UIKit.label(m[1], 18)
		val.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		var cell := UIKit.panel("", UIKit.vbox(0, [UIKit.label(m[0], 12, UIKit.MUTED), val]))
		cell.add_theme_stylebox_override("panel", UIKit.sb(Color(0, 0, 0, 0.25), Color(0, 0, 0, 0), 0, 8, 8, 6))
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		marks.add_child(cell)
	v.add_child(marks)
	v.add_child(UIKit.hbox(8, [UIKit.label("Medallas", 18), UIKit.label(str(int(b["medals"])), 14, UIKit.MUTED)]))
	var med := HFlowContainer.new()
	med.add_theme_constant_override("h_separation", 8)
	med.add_theme_constant_override("v_separation", 8)
	for id in d["medals"]:
		var a := Progress.ach_by(str(id))
		if a.is_empty():
			continue
		var pm := UIKit.vbox(2)
		pm.custom_minimum_size = Vector2(84, 0)
		pm.tooltip_text = str(a["name"])
		pm.mouse_filter = Control.MOUSE_FILTER_PASS
		var ico: Control = PokeView.make(int(a["dex"]), 48, 40, {"px": 1}) if a.has("dex") else UIKit.icon("medal%d" % int(a["tier"]), 36)
		ico.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		pm.add_child(ico)
		var nl := UIKit.label(str(a["name"]), 10, UIKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER, true)
		nl.custom_minimum_size = Vector2(84, 0)
		pm.add_child(nl)
		med.add_child(pm)
	if med.get_child_count() == 0:
		v.add_child(UIKit.label("Aún sin medallas.", 14, UIKit.MUTED))
	else:
		v.add_child(med)
	(func(): if is_instance_valid(sc): sc.custom_minimum_size.y = minf(lim, v.get_combined_minimum_size().y)).call_deferred()

func close_profile() -> bool:
	if _view == null:
		return false
	_view.queue_free()
	_view = null
	return true

func _pick_fav(i: int) -> void:
	for c in _body.get_children():
		c.queue_free()
	var s := Save.data
	var head := UIKit.hbox(8, [UIKit.label("Elige el favorito %d" % (i + 1), 18), UIKit.spacer(0, 0, true),
		UIKit.button("Volver", "SmallGhost", func():
			tab = "profile"
			render(), "click")])                     # #fav-back: a plain .btn (no data-back)
	_body.add_child(head)
	var q := LineEdit.new()
	q.placeholder_text = "Buscar por nombre"
	q.custom_minimum_size = Vector2(320, 0)
	q.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_body.add_child(q)
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_body.add_child(grid)
	var fill := func(text: String):
		for c in grid.get_children():
			c.queue_free()
		var n := 0
		for d in Save.owned_list():
			if n >= 120:
				break
			var nm := str(Data.dex_by[d]["name"])
			if text != "" and not nm.to_lower().contains(text):
				continue
			n += 1
			for shiny in ([false, true] if Save.owns_shiny(d) else [false]):
				var b := UIKit.button("", "Cell", func():
					var favs: Array = (s["profile"].get("favs", []) as Array).duplicate()
					while favs.size() <= i:
						favs.append(null)
					favs[i] = {"dex": d, "shiny": shiny}
					s["profile"]["favs"] = favs.filter(func(x): return x != null).slice(0, 3)
					Save.commit()
					Sfx.play("confirm")
					tab = "profile"
					render(), "click")                   # .cell: UI click, then save()'s confirm
				b.custom_minimum_size = Vector2(100, 104)
				var pv := PokeView.make(d, 92, 80, {"px": 2, "shiny": shiny})
				pv.position = Vector2(4, 2)
				b.add_child(pv)
				var l := UIKit.hbox(3)                  # "<b>[shiny 12] Name</b>"
				l.alignment = BoxContainer.ALIGNMENT_CENTER
				if shiny:
					l.add_child(UIKit.icon("shiny", 12))
				var ln := UIKit.label(nm, 12, UIKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
				ln.clip_text = true
				l.add_child(ln)
				l.position = Vector2(0, 82)
				l.size = Vector2(100, 18)
				b.add_child(l)
				grid.add_child(b)
	q.text_changed.connect(func(t: String): fill.call(t.strip_edges().to_lower()))
	fill.call("")
