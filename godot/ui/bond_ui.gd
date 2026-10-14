class_name BondUI
extends Control
## Bond (move fusion) picker (#scr-bond, js/ui/run-ui.js showBond): in "add" mode you pick the
## loose move that joins the growing group; in "pair" mode two loose moves, in two steps
## ("Atrás" goes back to the first). Keys 1-4 (main.gd), click or tap. The game is paused
## (Sim state "choice") until the moves are chosen; then `picked` carries them.

signal picked(moves: Array)

const INK := Color(1, 1, 1)
const MUTED := Color(0.725, 0.796, 0.941)        # #b9cbf0
const BOND := Color(1.0, 0.541, 0.847)            # #ff8ad8

var opt: Dictionary = {}
var first: Dictionary = {}        # pair mode: the first move chosen
var list: Array = []              # moves on the cards right now
var _sub: Label
var _cards: GridContainer
var _back: Button

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.set_script(load("res://ui/dim_bg.gd"))          # .scr.dim radial backdrop, like level-up / pause
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var cc := CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cc)
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UIKit.theme()
	var pc := PanelContainer.new()          # the theme's PMD box (like ItemChoice)
	cc.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	pc.add_child(vb)
	vb.add_child(ItemChoice._label("¡Vínculo!", UIKit.fs(26), BOND))
	var hint := ItemChoice._label("Los movimientos unidos se lanzan a la vez y ocupan un solo hueco", 13, MUTED)
	hint.visible = not UIKit.compact          # css: hidden on small screens
	vb.add_child(hint)
	_sub = ItemChoice._label("", 15, INK)
	vb.add_child(_sub)
	# #bond-cards: one column; css @media (max-height: 520px): a 2-column grid in a wider box
	_cards = GridContainer.new()
	_cards.columns = 2 if UIKit.compact else 1
	_cards.add_theme_constant_override("h_separation", 8)
	_cards.add_theme_constant_override("v_separation", 8)
	vb.add_child(_cards)
	_back = UIKit.button("Atrás", "", back, "click")        # #bond-back: a .btn
	_back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(_back)
	visible = false

func open(o: Dictionary) -> void:
	opt = o
	first = {}
	_render()
	visible = true

func close() -> void:
	visible = false
	opt = {}
	first = {}
	list = []

static func _names(ms: Array) -> String:
	return " + ".join(ms.map(func(m): return str(m["name"])))

func _render() -> void:
	for c in _cards.get_children():
		_cards.remove_child(c)
		c.queue_free()
	var add: bool = opt.get("mode", "") == "add"
	var step2: bool = opt.get("mode", "") == "pair" and not first.is_empty()
	if add:
		_sub.text = "Elige qué movimiento se une a " + _names(opt["group"])
	elif step2:
		_sub.text = "¿Con cuál unes " + str(first["name"]) + "?"
	else:
		_sub.text = "Elige el primer movimiento que vas a unir"
	_back.visible = step2
	list = (opt.get("loose", []) as Array).filter(func(m): return not is_same(m, first)) if step2 else (opt.get("loose", []) as Array).duplicate()
	var vw := _view_w()
	var width := minf(560.0, vw - 60.0)
	if UIKit.compact:                      # #scr-bond .box: min(820px, 100%), two cards per row
		width = (minf(820.0, vw - 16.0) - 2.0 * 14.0 - 8.0) / 2.0
	var touch := Screens.touch_active(self)
	for i in list.size():
		var m: Dictionary = list[i]
		var desc: String
		if add:
			desc = "Se lanzará a la vez que " + _names(opt["group"]) + "."
		elif step2:
			desc = "Se lanzará a la vez que " + str(first["name"]) + ". Queda un hueco libre."
		else:
			desc = str(m.get("desc", ""))
		_cards.add_child(_card(m, desc, i, width, add or step2, touch))

func _card(m: Dictionary, desc: String, i: int, width: float, bond: bool, touch := false) -> Control:
	var col := Data.tcolor(m["type"])
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(width, 0)
	var normal := "CardBond" if bond else "Card"
	var hover := "CardBond" if bond else "CardHover"
	pc.theme_type_variation = normal
	pc.mouse_filter = Control.MOUSE_FILTER_STOP
	pc.mouse_entered.connect(func(): pc.theme_type_variation = hover)
	pc.mouse_exited.connect(func(): pc.theme_type_variation = normal)
	UIKit.hover_sfx(pc)
	# a tap arrives as an emulated mouse press too: handling ScreenTouch as well made one tap
	# pick both moves of a pair (the first event re-renders the cards under the finger)
	pc.gui_input.connect(func(ev: InputEvent):
		var mb := ev as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			pick(i))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(hb)
	# move emblem on a tinted square (type colour at 20 %)
	var ib := PanelContainer.new()
	ib.add_theme_stylebox_override("panel", ItemChoice._box(Color(col, 0.2), Color(0, 0, 0, 0), 0, 8, 4, 4))
	ib.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ib.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var ico := TextureRect.new()
	ico.texture = Icons.tex("move:" + str(m["id"]))
	ico.custom_minimum_size = Vector2(32, 32)
	ico.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ico.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ico.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ico.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ib.add_child(ico)
	hb.add_child(ib)
	var txt := VBoxContainer.new()
	txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	txt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	txt.add_theme_constant_override("separation", 2)
	hb.add_child(txt)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	row.add_child(ItemChoice._label(str(m["name"]), 17, BOND if bond else INK, HORIZONTAL_ALIGNMENT_LEFT))
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", ItemChoice._box(col, Color(0, 0, 0, 0), 0, 6, 6, 1))
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var cl := ItemChoice._label("Nv." + str(int(m["lvl"])), 11, Color.html("#10131a"))      # .tag-chip: dark text, no shadow
	cl.add_theme_constant_override("shadow_offset_x", 0)
	cl.add_theme_constant_override("shadow_offset_y", 0)
	chip.add_child(cl)
	row.add_child(chip)
	txt.add_child(row)
	var d := ItemChoice._label(desc, 13, MUTED, HORIZONTAL_ALIGNMENT_LEFT)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(width - 120.0, 0)
	txt.add_child(d)
	if not touch:
		hb.add_child(Screens.key_chip(i + 1))
	return pc

## Card i chosen (keys 1-4 / click / tap).
func pick(i: int) -> void:
	if opt.is_empty() or i < 0 or i >= list.size():
		return
	var m: Dictionary = list[i]
	if opt["mode"] == "pair" and first.is_empty():
		first = m
		Sfx.play("select")
		_render()
		return
	var moves: Array = [m] if opt["mode"] == "add" else [first, m]
	close()
	picked.emit(moves)

func back() -> void:
	if opt.is_empty():
		return
	first = {}
	_render()

## Canvas width (1280 outside the tree: the headless tap tests build the cards detached).
func _view_w() -> float:
	return get_viewport_rect().size.x if is_inside_tree() else 1280.0
