class_name DexScreen
extends Control
## Collection (js/ui/menu.js openDex / renderGrid / showDetail): generation tabs (have/total),
## filters (all / owned / missing / shiny / rarity 5..1), grid (unowned = silhouette "???",
## crown on the partner, star on owned shinies) and a detail pane (stats, start move, learnable
## moves, Normal/Shiny view, "Choose as partner").

var ui: MetaUI
var gen := 1
var filter := "all"
var sel := 0
var view_shiny := false
var _last_detail := 0
var _total: Label
var _tabs: HBoxContainer
var _filters: Container
var _grid: GridContainer
var _scroll: ScrollContainer
var _detail: VBoxContainer
var _cells: Dictionary = {}      # dex -> Button

const CELL := Vector2(100, 116)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pg := MetaUI.page(self, "Pokémon", func(): ui.open_menu())
	var root: VBoxContainer = pg["root"]
	_total = UIKit.label("", 15, UIKit.MUTED)
	(pg["head"] as HBoxContainer).add_child(_total)
	(pg["head"] as HBoxContainer).move_child(_total, 1)
	_tabs = UIKit.hbox(6)
	root.add_child(_tabs)
	var split := UIKit.hbox(14)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)
	var left := UIKit.vbox(8)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(left)
	if UIKit.compact:
		var fl := HFlowContainer.new()        # compact: the filter chips wrap
		fl.add_theme_constant_override("h_separation", 4)
		fl.add_theme_constant_override("v_separation", 4)
		_filters = fl
	else:
		_filters = UIKit.hbox(6)
	left.add_child(_filters)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(_scroll)
	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_grid)
	_scroll.resized.connect(func(): _grid.columns = maxi(1, int((_scroll.size.x - 14.0) / (CELL.x + 8.0))))
	var dp := UIKit.panel("Inset")
	dp.custom_minimum_size = Vector2(250 if UIKit.compact else 330, 0)
	split.add_child(dp)
	var ds := ScrollContainer.new()
	ds.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dp.add_child(ds)
	_detail = UIKit.vbox(6)
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ds.add_child(_detail)

func open() -> void:
	if sel == 0 or not Data.dex_by.has(sel):
		sel = Save.partner()
		if Data.dex_by.has(sel):
			gen = int(Data.dex_by[sel]["gen"])
	_total.text = "%d / %d" % [Save.owned_count(), Data.dex.size()]
	_build_tabs()
	_build_filters()
	_render_grid()
	_show_detail(sel)

func _build_tabs() -> void:
	for c in _tabs.get_children():
		c.queue_free()
	var owned: Dictionary = Save.data["owned"]
	for i in 9:
		var g := i + 1
		var total := 0
		var have := 0
		for p in Data.dex:
			if int(p["gen"]) == g:
				total += 1
				if owned.has(str(p["dex"])):
					have += 1
		var b := UIKit.button("%s\n%d/%d" % [UIKit.GEN_NAMES[i], have, total], "GenTabOn" if g == gen else "GenTab", func():
			gen = g
			open(), "click")
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 12 if UIKit.compact else 14)
		_tabs.add_child(b)

func _build_filters() -> void:
	for c in _filters.get_children():
		c.queue_free()
	for f in [["all", "Todos"], ["own", "Tengo"], ["miss", "Me faltan"], ["shiny", "Shiny"], ["5", ""], ["4", ""], ["3", ""], ["2", ""], ["1", ""]]:
		var k: String = f[0]
		var txt: String = f[1] if f[1] != "" else Gacha.rarity_name(int(k))
		var b := UIKit.button(txt, "ChipOn" if k == filter else "Chip", func():
			filter = k
			_build_filters()
			_render_grid(), "click")
		if k == "shiny":
			b.icon = UIKit.icon_tex("shiny", 12)
		elif k.is_valid_int():
			b.icon = UIKit.icon_tex(str(Data.icons["rarity_ball"][k]), 12)
		_filters.add_child(b)

func _render_grid() -> void:
	for c in _grid.get_children():
		c.queue_free()
	_cells.clear()
	var s := Save.data
	var owned: Dictionary = s["owned"]
	var shinies: Dictionary = s["shiny"]
	var partner := Save.partner()
	var n := 0
	for p in Data.dex:
		if int(p["gen"]) != gen:
			continue
		var d := int(p["dex"])
		var own := owned.has(str(d))
		var sh := shinies.has(str(d))
		if filter == "own" and not own or filter == "miss" and own or filter == "shiny" and not sh:
			continue
		if filter.is_valid_int() and int(p["rarity"]) != int(filter):
			continue
		var use_shiny := sh and d == partner and bool(s.get("partnerShiny", false))
		var cell := _cell(p, own, sh, use_shiny, d == partner)
		_grid.add_child(cell)
		_cells[d] = cell
		n += 1
	if n == 0:
		_grid.add_child(UIKit.label("Ninguno con este filtro.", 15, UIKit.MUTED))
	_scroll.scroll_vertical = 0

func _cell(p: Dictionary, own: bool, sh: bool, use_shiny: bool, is_partner: bool) -> Button:
	var d := int(p["dex"])
	var b := UIKit.button("", "CellOn" if d == sel else "Cell", func(): _select(d), "click" if own else "", own)   # .cell.locked: silent
	b.custom_minimum_size = CELL
	if not own:
		b.modulate = Color(1, 1, 1, 0.8)
	var no := UIKit.label(UIKit.dex_no(d), 11, UIKit.MUTED)
	no.position = Vector2(6, 2)
	b.add_child(no)
	if is_partner or sh:
		var bd := UIKit.icon("crown" if is_partner else "shiny", 14 if is_partner else 12)
		bd.tooltip_text = "Compañero" if is_partner else "Tienes su shiny"
		bd.mouse_filter = Control.MOUSE_FILTER_PASS
		bd.position = Vector2(CELL.x - 20, 4)
		bd.size = bd.custom_minimum_size
		b.add_child(bd)
	var pv := PokeView.make(d, 92, 80, {"px": 2, "silhouette": not own, "shadow": own, "shiny": use_shiny})
	pv.position = Vector2(4, 4)
	b.add_child(pv)
	var nm := UIKit.label(str(p["name"]) if own else "???", 13, UIKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	nm.position = Vector2(2, 80)
	nm.size = Vector2(CELL.x - 4, 18)
	nm.clip_text = true
	b.add_child(nm)
	var rb := UIKit.rarity_icon(int(p["rarity"]), 12)
	rb.position = Vector2((CELL.x - 12) / 2.0, 99)
	rb.size = Vector2(12, 12)
	b.add_child(rb)
	return b

func _select(d: int) -> void:
	if _cells.has(sel):
		(_cells[sel] as Button).theme_type_variation = "Cell"
	sel = d
	if _cells.has(sel):
		(_cells[sel] as Button).theme_type_variation = "CellOn"
	_show_detail(d)

func _bar(lbl: String, v: float, mx: float, txt: String) -> HBoxContainer:
	var h := UIKit.hbox(8)
	var l := UIKit.label(lbl, 13, UIKit.MUTED)
	l.custom_minimum_size = Vector2(76, 0)
	h.add_child(l)
	var b := UIKit.bar(minf(1.0, v / mx), UIKit.GOLD, 0, 10)       # css .stat .bar i: var(--gold)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(b)
	var r := UIKit.label(txt, 13, UIKit.INK, HORIZONTAL_ALIGNMENT_RIGHT)
	r.custom_minimum_size = Vector2(48, 0)
	h.add_child(r)
	return h

func _show_detail(d: int) -> void:
	for c in _detail.get_children():
		c.queue_free()
	if not Data.dex_by.has(d):
		return
	var s := Save.data
	var p: Dictionary = Data.dex_by[d]
	var own := Save.owns(d)
	var has_sh := Save.owns_shiny(d)
	var is_partner := d == Save.partner()
	if not has_sh:
		view_shiny = false
	elif is_partner and d != _last_detail:
		view_shiny = bool(s.get("partnerShiny", false))
	_last_detail = d
	var using_this := is_partner and (not has_sh or bool(s.get("partnerShiny", false)) == view_shiny)
	var cc := CenterContainer.new()
	var st := PokeView.make(d, 160 if UIKit.compact else 220, 120 if UIKit.compact else 190, {"full": own, "lively": own, "spin": own, "hero": true, "px": 2 if UIKit.compact else 3, "stage": true,
		"silhouette": not own, "shiny": own and view_shiny})
	st.stage_color = UIKit.EDGE_IN if not own else (UIKit.SHINY if view_shiny else Data.tcolor(str(p["types"][0])))
	cc.add_child(st)
	_detail.add_child(cc)
	if has_sh:
		# .seg plain buttons: silent (outside ui.js CLICKABLE)
		var bn := UIKit.button("Normal", "", func():
			view_shiny = false
			_show_detail(d), "", false)
		var bs := UIKit.button("Shiny", "", func():
			view_shiny = true
			_show_detail(d), "", false)
		bs.icon = UIKit.icon_tex("shiny", 12)
		UIKit.seg_set([bn, bs], 1 if view_shiny else 0)
		_detail.add_child(UIKit.seg([bn, bs]))
	_detail.add_child(UIKit.label("Nº %s · %s" % [UIKit.dex_no(d), UIKit.GEN_NAMES[int(p["gen"]) - 1]], 13, UIKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	_detail.add_child(UIKit.label(str(p["name"]) if own else "???", 22, UIKit.INK, HORIZONTAL_ALIGNMENT_CENTER))
	var rr := UIKit.hbox(6, [UIKit.rarity_icon(int(p["rarity"]), 24), UIKit.label(Gacha.rarity_name(int(p["rarity"])), 15, Gacha.rarity_color(int(p["rarity"])))])
	rr.alignment = BoxContainer.ALIGNMENT_CENTER
	_detail.add_child(rr)
	var req := Families.req_level(d)
	if not own:
		var l := UIKit.label("Aún no lo tienes.\nConsíguelo en el banner de %s o derrotándolo cuando salga shiny." % UIKit.GEN_NAMES[int(p["gen"]) - 1],
			14, UIKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER, true)
		l.custom_minimum_size = Vector2(210 if UIKit.compact else 290, 0)
		_detail.add_child(l)
		if req > 1:
			var l2 := UIKit.label("También se desbloquea con fragmentos en Mejoras cuando su familia llega al nivel %d." % req,
				13, UIKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER, true)
			l2.custom_minimum_size = l.custom_minimum_size
			_detail.add_child(l2)
		return
	var tc := UIKit.type_chips(p["types"])
	tc.alignment = BoxContainer.ALIGNMENT_CENTER
	_detail.add_child(tc)
	_detail.add_child(_bar("Vida", float(p["hp"]), 183.0, str(int(p["hp"]))))
	_detail.add_child(_bar("Ataque", float(p["atk"]), 1.55, "×%.2f" % float(p["atk"])))
	_detail.add_child(_bar("Velocidad", float(p["spd"]), 137.0, str(int(p["spd"]))))
	# its family (core/families.gd): level, the moves it starts with, every move by level
	var fm := Families.fam_of_dex(s, d)
	var fl := UIKit.hbox(6, [UIKit.label("Familia de %s" % Families.fam_name(Families.fam_of(d)), 14), UIKit.label("·", 14, UIKit.MUTED),
		UIKit.label("Nv. %d" % int(fm["lv"]), 14, UIKit.GOLD)])
	_detail.add_child(fl)
	var sl := UIKit.hbox(6, [UIKit.label("Empieza con", 14)])
	var smv := Families.start_moves(s, d)
	for i in smv.size():
		sl.add_child(UIKit.icon("move:" + str(smv[i]), 16))
		sl.add_child(UIKit.label(str(Moves.def(smv[i]).get("name", smv[i])) + (" +" if i < smv.size() - 1 else ""), 14, UIKit.GOLD))
	_detail.add_child(sl)
	var mf := HFlowContainer.new()
	mf.tooltip_text = "Movimientos que aprende (los apagados, con más nivel de familia)"
	mf.mouse_filter = Control.MOUSE_FILTER_PASS
	mf.add_theme_constant_override("h_separation", 4)
	mf.add_theme_constant_override("v_separation", 4)
	for e in Families.shown(s, d):
		var ic := UIKit.icon("move:" + str(e[0]), 16)
		var basic: bool = (e as Array).size() > 2 and e[2] == "basic"
		ic.tooltip_text = "%s · %s" % [Moves.def(e[0]).get("name", e[0]), "Básico" if basic else "Nv. %d" % int(e[1])]
		ic.mouse_filter = Control.MOUSE_FILTER_PASS
		if int(e[1]) > int(fm["lv"]):
			ic.modulate.a = 0.35
		mf.add_child(ic)
	_detail.add_child(mf)
	if using_this:
		var b := UIKit.button("Es tu compañero", "")
		b.disabled = true
		_detail.add_child(b)
	elif Families.usable(s, d):
		_detail.add_child(UIKit.button("Elegir de compañero" + (" (shiny)" if view_shiny else ""), "GoldButton", func(): _pick(d, has_sh), "confirm"))
	else:
		var nb := UIKit.button("Necesita su familia a nivel %d" % req, "")
		nb.disabled = true
		_detail.add_child(nb)

func _pick(d: int, has_sh: bool) -> void:
	var s := Save.data
	if not Families.usable(s, d):
		return
	s["partner"] = d
	s["partnerShiny"] = has_sh and view_shiny
	Save.commit()
	ui.toast(str(Data.dex_by[d]["name"]) + (" shiny" if s["partnerShiny"] else "") + " es ahora tu compañero")
	_render_grid()
	_show_detail(d)
