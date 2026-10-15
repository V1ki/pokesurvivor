class_name UpgradesScreen
extends Control
## Upgrades: family and trainer (js/ui/menu.js openUpgrades / renderUpgrades / famPanel /
## bindPanel, core/families.gd): a family selector (the partner's first, then by level, then by
## name), the family panel (level, XP, what it gives, shards, its forms to pick / unlock with
## shards, stars, the moves of the shown form by level), the 8 trainer upgrade cards (icon, name,
## unit, pips, buy "coin cost" / "Máx.") and the 4 move hotkey selects.

var ui: MetaUI
var fam := 0                  # family being shown (menu.js upgFam)
var _stage: PokeView
var _sel: OptionButton
var _list: VBoxContainer
var _scroll: ScrollContainer
var _fams: Array = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pg := MetaUI.page(self, "Mejoras", func(): ui.open_menu(), 1040.0)
	var root: VBoxContainer = pg["root"]
	var head := UIKit.hbox(14)
	_stage = PokeView.make(4, 120, 96, {"full": true, "lively": true, "hero": true, "px": 2, "stage": true})
	head.add_child(_stage)
	var hv := UIKit.vbox(8)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.alignment = BoxContainer.ALIGNMENT_CENTER
	hv.add_child(UIKit.label("Las mejoras del entrenador valen para todos tus Pokémon. Cada familia sube de nivel jugando con ella.", 15, UIKit.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	_sel = OptionButton.new()
	_sel.focus_mode = Control.FOCUS_NONE
	_sel.custom_minimum_size = Vector2(280, 0)
	_sel.item_selected.connect(func(i: int):
		fam = _fams[i]
		Sfx.play("select")
		_render())
	hv.add_child(UIKit.hbox(10, [UIKit.label("Familia", 14, UIKit.MUTED), _sel]))
	head.add_child(hv)
	root.add_child(head)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(_scroll)
	_list = UIKit.vbox(8)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)

## The form that stands for a family: the partner if it belongs to it; else the most evolved one
## you can use (or the first one you own).
static func fam_form(f: int) -> int:
	var s := Save.data
	if Families.fam_of(Save.partner()) == f:
		return Save.partner()
	var m: Array = Families.members(f).filter(func(d): return Data.dex_by.has(d))
	var ok: Array = m.filter(func(d): return Families.usable(s, d))
	ok.sort_custom(func(a, b): return Families.stage(a) > Families.stage(b))
	if not ok.is_empty():
		return ok[0]
	for d in m:
		if Save.owns(d):
			return d
	return m[0] if not m.is_empty() else Save.partner()

func open() -> void:
	var s := Save.data
	var mine := Families.fam_of(Save.partner())
	_fams = []
	for d in Save.owned_list():
		var f := Families.fam_of(d)
		if not _fams.has(f):
			_fams.append(f)
	if fam == 0 or not _fams.has(fam):
		fam = mine
	var lv := func(f: int) -> int: return int(Families.fam(s, f)["lv"])
	_fams.sort_custom(func(a, b):
		if (a == mine) != (b == mine):
			return a == mine
		if lv.call(a) != lv.call(b):
			return lv.call(a) > lv.call(b)
		return es_less(Families.fam_name(a), Families.fam_name(b)))
	_sel.clear()
	for f in _fams:
		_sel.add_item("%s · Nv. %d%s" % [Families.fam_name(f), lv.call(f), " (compañero)" if f == mine else ""])
	_sel.select(maxi(0, _fams.find(fam)))
	_render()

func _render() -> void:
	var keep := _scroll.scroll_vertical
	for c in _list.get_children():
		c.queue_free()
	if fam == 0:
		return
	var s := Save.data
	var dex := fam_form(fam)
	var mon: Dictionary = Data.dex_by[dex]
	var shiny := dex == Save.partner() and bool(s.get("partnerShiny", false)) and Save.owns_shiny(dex)
	_stage.set_dex(dex, shiny)
	_stage.stage_color = UIKit.SHINY if shiny else Data.tcolor(str(mon["types"][0]))
	_list.add_child(_fam_panel(fam, dex))
	_list.add_child(UIKit.vbox(2, [UIKit.label("Entrenador", 18, UIKit.INK),
		UIKit.label("Se compran con Pokémonedas y valen para todos tus Pokémon.", 13, UIKit.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true)]))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_child(grid)
	var tr: Dictionary = s["trainer"] if s.get("trainer") is Dictionary else {}
	for u in Upgrades.list():
		if (Families.R["trainer"] as Array).has(u["id"]):
			grid.add_child(_card(u, int(tr.get(u["id"], 0)), int(s["coins"])))
	_list.add_child(_bind_panel(dex))
	await get_tree().process_frame
	_scroll.scroll_vertical = keep

# ---------------- family (core/families.gd) ----------------

## Level, XP, what it gives, shards, forms (pick / unlock), stars and moves.
func _fam_panel(f: int, dex: int) -> PanelContainer:
	var s := Save.data
	var fm := Families.fam(s, f)
	var lv := int(fm["lv"])
	var b := Families.level_bonus(lv)
	var need := Families.xp_need(lv)
	var p := UIKit.panel("Inset")
	var v := UIKit.vbox(6)
	p.add_child(v)
	var top := UIKit.hbox(8, [UIKit.label("Familia de %s" % Families.fam_name(f), 18), UIKit.spacer(0, 0, true),
		UIKit.label("Nv. %d / %d" % [lv, int(Families.R["cap"])], 18, UIKit.GOLD)])
	v.add_child(top)
	if lv < int(Families.R["cap"]):
		v.add_child(UIKit.bar(minf(1.0, float(fm["xp"]) / float(need)), UIKit.GOLD, 0.0, 8.0))
		v.add_child(UIKit.label("Faltan %d de experiencia para el siguiente nivel." % int(ceil(need - float(fm["xp"]))), 13, UIKit.MUTED))
		v.add_child(UIKit.label("Sube jugando con cualquier Pokémon de la familia.", 13, UIKit.MUTED))
	var bonus := HFlowContainer.new()
	bonus.add_theme_constant_override("h_separation", 6)
	var parts := ["+%d%% de daño" % int(b["atk"]), "−%d%% de recarga" % int(b["cd"]), "+%d%% de críticos" % int(b["crit"]),
		"Empieza con 2 movimientos" if b["two"] else "Empieza con 2 movimientos desde el nivel %d" % int(Families.R["moves2Lv"])]
	if int(fm["stars"]) > 0:
		parts.append("%d estrellas: +%d%% de daño y de vida" % [int(fm["stars"]), U.jroundi(int(fm["stars"]) * float(Families.R["starAtk"]) * 100.0)])
	for i in parts.size():
		bonus.add_child(UIKit.label(parts[i], 14, UIKit.INK))          # each part translated on its own
		if i < parts.size() - 1:
			bonus.add_child(UIKit.label("·", 14, UIKit.MUTED))
	v.add_child(bonus)
	v.add_child(UIKit.hbox(6, [UIKit.icon("star", 12), UIKit.label("Fragmentos: %d" % int(fm["shards"]), 13, UIKit.MUTED),
		UIKit.label("·", 13, UIKit.MUTED), UIKit.label("Universales: %d" % int(s.get("uni", 0)), 13, UIKit.MUTED),
		UIKit.label("(%d valen 1)" % int(Families.R["uniRate"]), 13, UIKit.MUTED)]))
	# the family's forms: the one you can use is picked, a missing one is unlocked
	var forms: Array = Families.members(f).filter(func(d): return Data.dex_by.has(d))
	forms.sort_custom(func(a, c):
		if Families.req_level(a) != Families.req_level(c):
			return Families.req_level(a) < Families.req_level(c)
		if Families.stage(a) != Families.stage(c):
			return Families.stage(a) < Families.stage(c)
		return a < c)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 8)
	for d in forms:
		row.add_child(_form_card(f, d))
	if Families.complete(s, f) and int(fm["stars"]) < int(Families.R["stars"]):
		var st := UIKit.button("Estrella %d" % int(Families.R["starCost"]), "SmallGold", func(): _star(f), "")
		st.icon = UIKit.icon_tex("star", 12)
		st.disabled = not Families.can_star(s, f)
		var sv := UIKit.vbox(4, [UIKit.label("%d / %d" % [int(fm["stars"]), int(Families.R["stars"])], 16, UIKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER), st,
			UIKit.label("+5% de daño y de vida", 12, UIKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER)])
		sv.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_child(UIKit.panel("Inset", sv))
	v.add_child(row)
	# the moves of this form, with the family level that unlocks them
	v.add_child(UIKit.label("Movimientos de %s" % Data.dex_by[dex]["name"], 13, UIKit.MUTED))
	var mv := HFlowContainer.new()
	mv.add_theme_constant_override("h_separation", 6)
	mv.add_theme_constant_override("v_separation", 6)
	var shown := Families.shown(s, dex)
	for e in shown:
		var basic: bool = (e as Array).size() > 2 and e[2] == "basic"
		var on := int(e[1]) <= lv
		var chip := UIKit.pill([UIKit.icon("move:" + str(e[0]), 14), UIKit.label(str(Moves.def(e[0]).get("name", e[0])), 13, UIKit.INK if on else UIKit.MUTED),
			UIKit.label("Básico" if basic else "Nv. %d" % int(e[1]), 11, UIKit.GOLD if on else UIKit.MUTED)])
		chip.modulate.a = 1.0 if on else 0.55
		mv.add_child(chip)
	v.add_child(mv)
	if not shown.is_empty() and (shown[0] as Array).size() > 2 and shown[0][2] == "basic":
		v.add_child(UIKit.label("Mientras sepa menos de 4 ataques, los básicos de su tipo completan la lista.", 12, UIKit.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	return p

## One form of the family: sprite (a silhouette if missing), name, rarity and what can be done.
func _form_card(f: int, d: int) -> PanelContainer:
	var s := Save.data
	var p: Dictionary = Data.dex_by[d]
	var own := Save.owns(d)
	var ok := Families.usable(s, d)
	var req := Families.req_level(d)
	var lv := int(Families.fam(s, f)["lv"])
	var v := UIKit.vbox(3)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var pv := PokeView.make(d, 84, 72, {"px": 2, "silhouette": not own, "shadow": own})
	pv.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(pv)
	# the name even if you don't own it: it's the family's goal
	v.add_child(UIKit.hbox(4, [UIKit.label(str(p["name"]), 14), UIKit.rarity_icon(int(p["rarity"]), 8)]))
	if d == Save.partner():
		v.add_child(UIKit.label("Compañero", 12, UIKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	elif ok:
		v.add_child(UIKit.button("Elegir", "SmallGold", func(): _pick(d), "confirm"))
	elif own:
		v.add_child(UIKit.label("Necesita nivel %d" % req, 12, UIKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	elif lv >= req:
		var ub := UIKit.button("Desbloquear %d" % Families.unlock_cost(d), "SmallButton", func(): _unlock(d), "")
		ub.icon = UIKit.icon_tex("star", 12)
		ub.disabled = not Families.can_unlock(s, d)
		v.add_child(ub)
	else:
		v.add_child(UIKit.hbox(4, [UIKit.label("Nivel %d" % req, 12, UIKit.MUTED), UIKit.label("·", 12, UIKit.MUTED),
			UIKit.icon("star", 12), UIKit.label(str(Families.unlock_cost(d)), 12, UIKit.MUTED)]))
	var card := UIKit.panel("Inset", v)
	if d == Save.partner() or ok:
		card.add_theme_stylebox_override("panel", UIKit.sb(Color(0, 0, 0, 0.22), UIKit.GOLD if d == Save.partner() else UIKit.GREEN, 2, 9, 8, 6))
	return card

func _pick(d: int) -> void:
	if not Families.usable(Save.data, d):
		return
	Save.data["partner"] = d
	Save.data["partnerShiny"] = false
	Save.commit()
	ui.toast("%s es ahora tu compañero" % Data.dex_by[d]["name"])
	open()

func _unlock(d: int) -> void:
	if not Families.unlock(Save.data, d):
		Sfx.play("error")
		return
	Save.commit()
	Sfx.play("legend")
	ui.toast("¡%s desbloqueado!" % Data.dex_by[d]["name"])
	_render()

func _star(f: int) -> void:
	if not Families.star(Save.data, f):
		Sfx.play("error")
		return
	Save.commit()
	Sfx.play("legend")
	ui.toast("Familia de %s: %d estrellas" % [Families.fam_name(f), int(Families.fam(Save.data, f)["stars"])])
	_render()

# ---------------- trainer (save.trainer) ----------------

func _card(u: Dictionary, lvl: int, coins: int) -> PanelContainer:
	var id: String = u["id"]
	var mx := int(u["max"])
	var maxed := lvl >= mx
	var cost := 0 if maxed else Upgrades.cost(id, lvl)
	var p := UIKit.panel("Inset")
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var h := UIKit.hbox(10)
	p.add_child(h)
	h.add_child(UIKit.icon(str(u["icon"]), 32))
	var v := UIKit.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(UIKit.label(str(u["name"]), 16))
	var unit := UIKit.label(str(u["unit"]), 12, UIKit.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true)
	unit.custom_minimum_size = Vector2(180, 0)
	v.add_child(unit)
	var pips := UIKit.hbox(3)
	for i in mx:
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(12, 6)
		pip.color = UIKit.GOLD if i < lvl else Color(0, 0, 0, 0.4)
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pips.add_child(pip)
	v.add_child(pips)
	h.add_child(v)
	var buy := UIKit.button("Máx." if maxed else str(cost), "SmallButton" if maxed else "SmallGold", func(): _buy(id), "")
	if not maxed:
		buy.icon = UIKit.icon_tex("coin", 18)
	buy.custom_minimum_size = Vector2(96, 0)
	buy.disabled = maxed or coins < cost
	var bv := UIKit.vbox(4, [buy])
	bv.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(bv)
	return p

func _buy(id: String) -> void:
	# everything is re-read on press (menu.js: the save may have changed since the draw)
	if not (Families.R["trainer"] as Array).has(id):
		return
	var s := Save.data
	if not (s.get("trainer") is Dictionary):
		s["trainer"] = {}
	var tr: Dictionary = s["trainer"]
	var now := int(tr.get(id, 0))
	var u := Upgrades.by_id(id)
	if now >= int(u["max"]):
		_render()
		return
	var price := Upgrades.cost(id, now)
	if int(s["coins"]) < price:
		Sfx.play("error")
		_render()
		return
	s["coins"] = int(s["coins"]) - price
	tr[id] = now + 1
	Save.commit()
	Sfx.play("buy")
	ui.refresh_coins()
	ui.toast("Entrenador · %s: nivel %d" % [u["name"], now + 1])
	_render()

static func _by_name(ids: Array) -> Array:
	var out := ids.duplicate()
	out.sort_custom(func(a, b): return es_less(str(Moves.def(a).get("name", a)), str(Moves.def(b).get("name", b))))
	return out

## `a.localeCompare(b, 'es') < 0` for the move names: accents and case only break ties, ñ is a
## letter between n and o, spaces / punctuation / digits sort before letters.
static func es_less(a: String, b: String) -> bool:
	var ka := es_key(a)
	var kb := es_key(b)
	if ka != kb:
		return ka < kb
	return a < b

static func es_key(t: String) -> String:
	var k := t.to_lower()
	for pair in [["á", "a"], ["à", "a"], ["é", "e"], ["è", "e"], ["í", "i"], ["ó", "o"], ["ú", "u"], ["ü", "u"], ["ñ", "n{"]]:
		k = k.replace(pair[0], pair[1])
	return k

# ---------------- hotkeys (save.pbind[dex]) ----------------

func _bind_panel(dex: int) -> PanelContainer:
	var s := Save.data
	if not (s.get("pbind") is Dictionary):
		s["pbind"] = {}
	var cur: Array = s["pbind"].get(str(dex), [null, null, null, null])
	# every move this form knows or will learn (and the basic ones filling its list now)
	var ids := _by_name(Families.shown(s, dex).map(func(e): return e[0]))
	var p := UIKit.panel("Inset")
	var v := UIKit.vbox(6)
	p.add_child(v)
	v.add_child(UIKit.label("Atajos de movimientos", 17))
	v.add_child(UIKit.label("Elige qué movimiento va siempre en cada hueco (teclas 1-4 o los iconos de abajo), para la memoria muscular. Si aún no tienes tantos movimientos, va al hueco más cercano.",
		13, UIKit.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	var row := UIKit.hbox(10)
	for i in 4:
		var ob := OptionButton.new()
		ob.focus_mode = Control.FOCUS_NONE
		ob.add_item("Libre")
		for id in ids:
			ob.add_icon_item(UIKit.icon_tex("move:" + str(id), 16), str(Moves.def(id).get("name", id)))
		var have: Variant = cur[i] if i < cur.size() else null
		ob.select(ids.find(have) + 1 if have != null else 0)
		ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ob.item_selected.connect(func(k: int):
			var l: Array = (s["pbind"].get(str(dex), [null, null, null, null]) as Array).slice(0, 4)
			while l.size() < 4:
				l.append(null)
			var id: Variant = ids[k - 1] if k > 0 else null
			# a move can only be in one slot
			for j in 4:
				if id != null and l[j] == id:
					l[j] = null
			l[i] = id
			s["pbind"][str(dex)] = l
			Save.commit()
			Sfx.play("select")
			_render())
		row.add_child(UIKit.hbox(4, [UIKit.label(str(i + 1), 18, UIKit.GOLD), ob]))
		row.get_child(i).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(row)
	return p
