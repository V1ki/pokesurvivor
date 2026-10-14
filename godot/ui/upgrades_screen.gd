class_name UpgradesScreen
extends Control
## Per-Pokémon upgrade shop (js/ui/menu.js openUpgrades / renderUpgrades / banPicker / bindPanel):
## Pokémon selector (partner first, then most levels, then dex), 13 upgrade cards (icon, name,
## unit, pips, buy "coin cost" / "Máx."), the Veto ban picker and the 4 move hotkey selects.

var ui: MetaUI
var dex := 0
var ban_open := false
var _stage: PokeView
var _sel: OptionButton
var _list: VBoxContainer
var _scroll: ScrollContainer
var _mons: Array = []

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
	hv.add_child(UIKit.label("Cada Pokémon tiene sus propias mejoras: sólo cuentan cuando juegas con él.", 15, UIKit.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	_sel = OptionButton.new()
	_sel.focus_mode = Control.FOCUS_NONE
	_sel.custom_minimum_size = Vector2(280, 0)
	_sel.item_selected.connect(func(i: int):
		dex = _mons[i]          # menu.js keeps the Veto picker open (banOpen) across Pokémon
		Sfx.play("select")
		_render())
	hv.add_child(UIKit.hbox(10, [UIKit.label("Pokémon", 14, UIKit.MUTED), _sel]))
	head.add_child(hv)
	root.add_child(head)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(_scroll)
	_list = UIKit.vbox(8)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)

static func levels_total(d: int) -> int:
	var n := 0
	var u: Variant = Save.data["pupg"].get(str(d))
	if u is Dictionary:
		for k in u:
			n += int(u[k])
	return n

func open() -> void:
	var p := Save.partner()
	if dex == 0 or not Save.owns(dex):
		dex = p
	_mons = Save.owned_list()
	_mons.sort_custom(func(a, b):
		if (a == p) != (b == p):
			return a == p
		var la := levels_total(a)
		var lb := levels_total(b)
		if la != lb:
			return la > lb
		return a < b)
	_sel.clear()
	for d in _mons:
		var lv := levels_total(d)
		_sel.add_item(str(Data.dex_by[d]["name"]) + (" (compañero)" if d == p else "") + (" · %d niveles" % lv if lv else ""))
	_sel.select(maxi(0, _mons.find(dex)))
	_render()

func _render() -> void:
	var keep := _scroll.scroll_vertical
	for c in _list.get_children():
		c.queue_free()
	if dex <= 0:
		return
	var s := Save.data
	var mon: Dictionary = Data.dex_by[dex]
	var shiny := dex == Save.partner() and bool(s.get("partnerShiny", false)) and Save.owns_shiny(dex)
	_stage.set_dex(dex, shiny)
	_stage.stage_color = UIKit.SHINY if shiny else Data.tcolor(str(mon["types"][0]))
	var levels := Save.upgrades_of(dex)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_child(grid)
	var ban_lvl := 0
	for u in Upgrades.list():
		var id: String = u["id"]
		var lvl := int(levels.get(id, 0))
		if id == "ban":
			ban_lvl = lvl
		grid.add_child(_card(u, lvl, int(s["coins"])))
	if ban_lvl > 0 and ban_open:
		_list.add_child(_ban_picker(ban_lvl))
	_list.add_child(_bind_panel())
	await get_tree().process_frame
	_scroll.scroll_vertical = keep

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
	var bv := UIKit.vbox(4)
	bv.alignment = BoxContainer.ALIGNMENT_CENTER
	if id == "ban" and lvl > 0:
		bv.add_child(UIKit.button("Elegir (%d/%d)" % [_ban_list().size(), lvl], "SmallButton", func():
			ban_open = not ban_open
			_render(), "click"))
	var buy := UIKit.button("Máx." if maxed else str(cost), "SmallButton" if maxed else "SmallGold", func(): _buy(id), "")
	if not maxed:
		buy.icon = UIKit.icon_tex("coin", 18)
	buy.custom_minimum_size = Vector2(96, 0)
	buy.disabled = maxed or coins < cost
	bv.add_child(buy)
	h.add_child(bv)
	return p

func _buy(id: String) -> void:
	# everything is re-read on press (menu.js: the save may have changed since the draw)
	var s := Save.data
	var lv := Save.upgrades_of(dex)
	var now := int(lv.get(id, 0))
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
	lv[id] = now + 1
	Save.commit()
	Sfx.play("buy")
	ui.refresh_coins()
	ui.toast("%s · %s: nivel %d" % [Data.dex_by[dex]["name"], u["name"], now + 1])
	_render()

# ---------------- veto (save.pban[dex]) ----------------

func _ban_list() -> Array:
	var s := Save.data
	if not (s.get("pban") is Dictionary):
		s["pban"] = {}
	if not (s["pban"].get(str(dex)) is Array):
		s["pban"][str(dex)] = []
	return s["pban"][str(dex)]

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

func _ban_picker(mx: int) -> PanelContainer:
	var start := Moves.start_move_of(dex)
	var ids := _by_name(Moves.pool_for(Data.dex_by[dex]).filter(func(id): return id != start))
	var list := _ban_list()
	var p := UIKit.panel("Inset")
	var v := UIKit.vbox(8)
	p.add_child(v)
	v.add_child(UIKit.label("Toca los movimientos que no quieres que te salgan en las cartas (%d/%d). El movimiento de inicio no se puede vetar." % [list.size(), mx],
		14, UIKit.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", 6)
	f.add_theme_constant_override("v_separation", 6)
	for id in ids:
		var on := list.has(id)
		var b := UIKit.button(str(Moves.def(id).get("name", id)), "ChipBan" if on else "Chip", func():
			var l := _ban_list()
			var i := l.find(id)
			if i >= 0:
				l.remove_at(i)
			elif l.size() >= mx:
				ui.toast("Ya tienes %d vetados: quita uno primero" % mx)
				return
			else:
				l.append(id)
			Save.commit()
			Sfx.play("select")
			_render(), "click")
		b.icon = UIKit.icon_tex("move:" + str(id), 16)
		if on:
			_mark_banned(b)
		f.add_child(b)
	v.add_child(f)
	return p

## .chip.on.ban: the name struck through and a `ban` icon after it (room made in the right padding).
static func _mark_banned(b: Button) -> void:
	var st := (UIKit.theme().get_stylebox("normal", "ChipBan") as StyleBoxFlat).duplicate() as StyleBoxFlat
	var pad := st.content_margin_right
	st.content_margin_right = pad + 19.0
	for k in ["normal", "hover", "pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(k, st)
	b.draw.connect(func():
		var x0 := st.content_margin_left + 16.0 + float(b.get_theme_constant("h_separation"))
		var x1 := b.size.x - st.content_margin_right
		var y := roundf(b.size.y / 2.0) + 1.0
		b.draw_line(Vector2(x0, y), Vector2(x1, y), Color.html("#ffd3d8"), 1.0)
		var ico := UIKit.icon_tex("ban", 14)
		b.draw_texture(ico, Vector2(b.size.x - pad - 14.0, roundf((b.size.y - ico.get_height()) / 2.0))))

# ---------------- hotkeys (save.pbind[dex]) ----------------

func _bind_panel() -> PanelContainer:
	var s := Save.data
	if not (s.get("pbind") is Dictionary):
		s["pbind"] = {}
	var cur: Array = s["pbind"].get(str(dex), [null, null, null, null])
	var ids := Moves.pool_for(Data.dex_by[dex]).duplicate()
	var sm := Moves.start_move_of(dex)
	if not ids.has(sm):
		ids.append(sm)
	ids = _by_name(ids)
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
