class_name MenuScreen
extends Control
## Main menu (js/ui/menu.js open, #scr-menu): logo + partner card on the left (stage, name, types,
## rarity ball, Normal/Shiny toggle when the shiny is owned), menu list + stats box on the right.
## Friends / Ranking are online-only and dropped (§8.9).

var ui: MetaUI
var _partner: PokeView
var _name: Label
var _shiny_ico: TextureRect
var _info: HBoxContainer
var _seg: PanelContainer
var _seg_n: Button
var _seg_s: Button
var _dex_sub: Label
var _goals_sub: Label
var _stats1: Array = []          # value labels of "Runs N · Mejor tiempo m:ss"
var _stats2: Array = []          # value labels of "Mejor nivel N · Derrotados N"
var _items: Array = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 0)
	# ---- left: logo + partner card ----
	var left := CenterContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(left)
	var c := UIKit.compact          # css @media max-height 520px: smaller logo / stage, 2-column menu list
	var lv := UIKit.vbox(2 if c else 4)
	lv.alignment = BoxContainer.ALIGNMENT_CENTER
	left.add_child(lv)
	var t1 := UIKit.label("PokéSurvivor", 60, UIKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	t1.add_theme_color_override("font_shadow_color", Color.html("#a55f00"))
	t1.add_theme_constant_override("shadow_offset_x", 3)
	t1.add_theme_constant_override("shadow_offset_y", 3)
	t1.add_theme_constant_override("outline_size", 0)
	lv.add_child(t1)
	# .logo .t2: "Mundo Misterioso", upper case with 3 px letter spacing (translated as a whole)
	var t2 := UIKit.label("Mundo Misterioso", 11 if c else 18, UIKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	t2.uppercase = true
	var spaced := FontVariation.new()
	spaced.base_font = DrawUtil.font(700)
	spaced.spacing_glyph = 2 if c else 3
	t2.add_theme_font_override("font", spaced)
	lv.add_child(t2)
	lv.add_child(UIKit.spacer(0, 2 if c else 18))
	var stage_row := CenterContainer.new()
	stage_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_partner = PokeView.make(4, 169 if c else 260, 130 if c else 200, {"full": true, "lively": true, "hero": true, "px": 3 if c else 4, "stage": true})
	stage_row.add_child(_partner)
	lv.add_child(stage_row)
	var nm_row := UIKit.hbox(6)
	nm_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_name = UIKit.label("", 17 if c else 26, UIKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	_name.add_theme_constant_override("shadow_offset_x", 3)
	_name.add_theme_constant_override("shadow_offset_y", 3)
	nm_row.add_child(_name)
	_shiny_ico = UIKit.icon("shiny", 24)
	nm_row.add_child(_shiny_ico)
	lv.add_child(nm_row)
	_info = UIKit.hbox(6)
	_info.alignment = BoxContainer.ALIGNMENT_CENTER
	lv.add_child(_info)
	# .seg plain buttons: outside ui.js CLICKABLE (no hover / click sound; confirm on a change)
	_seg_n = UIKit.button("Normal", "", func(): _set_shiny(false), "", false)
	_seg_s = UIKit.button("Shiny", "", func(): _set_shiny(true), "", false)
	_seg_s.icon = UIKit.icon_tex("shiny", 12)
	_seg = UIKit.seg([_seg_n, _seg_s])
	lv.add_child(UIKit.spacer(0, 4))
	lv.add_child(_seg)
	# ---- right: menu list + stats ----
	var right := PanelContainer.new()
	right.theme_type_variation = "Bare"
	right.custom_minimum_size = Vector2(400 if c else 420, 0)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.draw.connect(func():
		# linear-gradient(90deg, transparent, rgba(5,10,25,.65) 30%)
		var w := right.size.x
		var h := right.size.y
		var c0 := Color(5 / 255.0, 10 / 255.0, 25 / 255.0, 0.0)
		var c1 := Color(5 / 255.0, 10 / 255.0, 25 / 255.0, 0.65)
		right.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w * 0.3, 0), Vector2(w * 0.3, h), Vector2(0, h)]), PackedColorArray([c0, c1, c1, c0]))
		right.draw_rect(Rect2(w * 0.3, 0, w * 0.7, h), c1))
	right.resized.connect(right.queue_redraw)
	row.add_child(right)
	var rm := MarginContainer.new()
	rm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rm.add_theme_constant_override("margin_top", 44 if c else 70)
	rm.add_theme_constant_override("margin_bottom", 6 if c else 18)
	rm.add_theme_constant_override("margin_left", 8 if c else 24)
	rm.add_theme_constant_override("margin_right", 8 if c else 24)
	right.add_child(rm)
	var rv := UIKit.vbox(6 if c else 12)
	rv.alignment = BoxContainer.ALIGNMENT_BEGIN if c else BoxContainer.ALIGNMENT_CENTER
	rm.add_child(rv)
	var list := UIKit.vbox(2)
	var lp := UIKit.panel("", list)
	if c:
		lp.add_theme_stylebox_override("panel", UIKit.box_style(6, 4))
	rv.add_child(lp)
	var rest: Control = list
	if c:
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 4)
		grid.add_theme_constant_override("v_separation", 2)
		grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rest = grid
	_items = [
		_item(list, "play", "ball", "Jugar", "Entra en la mazmorra", func(): ui.play_pressed.emit(), true),
		_item(rest, "dex", "book", "Pokémon", "Tu colección", func(): ui.open("dex")),
		_item(rest, "upgrades", "up", "Mejoras", "Haz más fuerte cada run", func(): ui.open("upgrades")),
		_item(rest, "gacha", "ball4", "Gacha", "9 regiones · Pokémon y shinies", func(): ui.open("gacha")),
		_item(rest, "goals", "medal3", "Misiones", "Misiones, logros y perfil", func(): ui.open("goals")),
		_item(rest, "settings", "gear", "Ajustes", "Sonido, gráficos, controles y cuenta", func(): ui.open_settings()),
	]
	if rest != list:
		list.add_child(rest)
	(_items[0]["btn"] as Button).set_meta("focus_first", true)
	_dex_sub = _items[1]["sub"]
	_goals_sub = _items[4]["sub"]
	# menu.js: "Runs <b>N</b> · Mejor tiempo <b>m:ss</b>" / "Mejor nivel <b>N</b> · Derrotados <b>N</b>"
	# (muted words, white values; the words are the web's text nodes)
	var stats := UIKit.vbox(2)
	stats.add_child(_stat_line(["Runs", "· Mejor tiempo"], _stats1))
	stats.add_child(_stat_line(["Mejor nivel", "· Derrotados"], _stats2))
	var sp := UIKit.panel("", stats)
	sp.add_theme_stylebox_override("panel", _box_small())
	sp.visible = not c                 # css: .menu-right > .box:last-child { display: none }
	rv.add_child(sp)

static func _box_small() -> StyleBox:
	return UIKit.box_style(14, 8)

func _stat_line(words: Array, values: Array) -> HBoxContainer:
	var h := UIKit.hbox(5)
	for w in words:
		h.add_child(UIKit.label(w, 14, UIKit.MUTED))
		var v := UIKit.label("", 14, UIKit.INK)
		v.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		values.append(v)
		h.add_child(v)
	return h

func _item(list: Control, id: String, ico: String, title: String, sub: String, cb: Callable, play := false) -> Dictionary:
	var c := UIKit.compact
	var b := UIKit.button("", "MenuItem", cb, "confirm" if play else "click")
	b.custom_minimum_size = Vector2(0 if c else 320, (44 if play else 38) if c else (62 if play else 50))
	if c:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var m := MarginContainer.new()
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_theme_constant_override("margin_left", 6 if c else 26)
	m.add_theme_constant_override("margin_right", 4 if c else 8)
	b.add_child(m)
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var h := UIKit.hbox(6 if c else 10)
	m.add_child(h)
	h.add_child(UIKit.icon(ico, 20 if c else 26))
	var v := UIKit.vbox(-2)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var tl := UIKit.label(title, (21 if play else 15) if c else (30 if play else 22), UIKit.GOLD if play else UIKit.INK)
	v.add_child(tl)
	var sl := UIKit.label(sub, 10 if c else 13, UIKit.MUTED)
	if c:
		sl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		sl.clip_text = true
	sl.add_theme_constant_override("shadow_offset_x", 1)
	sl.add_theme_constant_override("shadow_offset_y", 1)
	v.add_child(sl)
	h.add_child(v)
	# PMD cursor arrow while hovered
	var cur := UIKit.icon("cursor", 16)
	cur.position = Vector2(6, (b.custom_minimum_size.y - 24) / 2.0)
	cur.size = Vector2(16, 24)
	cur.visible = false
	b.add_child(cur)
	b.mouse_entered.connect(func(): cur.visible = not c)      # css compact: no cursor arrow (hover sfx: UIKit)
	b.mouse_exited.connect(func(): cur.visible = false)
	b.focus_entered.connect(func(): cur.visible = not c)
	b.focus_exited.connect(func(): cur.visible = false)
	b.name = id
	list.add_child(b)
	return {"btn": b, "sub": sl}

func open() -> void:
	var s := Save.data
	var dex := Save.partner()
	if dex <= 0 or not Data.dex_by.has(dex):
		return
	var mon: Dictionary = Data.dex_by[dex]
	var shiny := bool(s.get("partnerShiny", false)) and Save.owns_shiny(dex)
	_partner.set_dex(dex, shiny)
	_partner.stage_color = UIKit.SHINY if shiny else Data.tcolor(str(mon["types"][0]))
	_name.text = str(mon["name"])
	_shiny_ico.visible = shiny
	for c in _info.get_children():
		c.queue_free()
	_info.add_child(UIKit.type_chips(mon["types"]))
	_info.add_child(UIKit.rarity_icon(int(mon["rarity"]), 12))
	_seg.visible = Save.owns_shiny(dex)
	UIKit.seg_set([_seg_n, _seg_s], 1 if shiny else 0)
	var owned := Save.owned_count()
	var shinies := (s["shiny"] as Dictionary).size()
	_dex_sub.text = "%d / %d" % [owned, Data.dex.size()] + (" · %d shiny" % shinies if shinies else "")
	var st: Dictionary = s["stats"]
	(_stats1[0] as Label).text = str(int(st["runs"]))
	(_stats1[1] as Label).text = U.mmss(float(st["bestTime"]))
	(_stats2[0] as Label).text = str(int(st["bestLevel"]))
	(_stats2[1] as Label).text = UIKit.num_es(int(st["totalKills"]))
	# css @media (max-height: 400px): only Play keeps its subtitle
	var tiny := Presentation.tiny(get_viewport_rect().size)
	for i in range(1, _items.size()):
		(_items[i]["sub"] as Label).visible = not tiny
	Progress.check_ach()
	var pend := Progress.pending()
	_goals_sub.text = ("%d premio%s por recoger" % [pend, "" if pend == 1 else "s"]) if pend else "Misiones, logros y perfil"
	_goals_sub.add_theme_color_override("font_color", UIKit.GOLD if pend else UIKit.MUTED)
	ui.refresh_coins()

func _set_shiny(on: bool) -> void:
	var s := Save.data
	if bool(s.get("partnerShiny", false)) == on:
		return
	s["partnerShiny"] = on
	Save.commit()
	Sfx.play("confirm")
	open()
