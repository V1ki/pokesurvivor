class_name Screens
extends Control
## In-run modal screens built in code: level-up cards (#scr-levelup), pause (#scr-pause), plus the
## Phase 1 title / results screens (the meta UI replaced them in the normal flow). Styled with the
## shared UIKit theme (PMD box, .card list, gold buttons); compact on short phone canvases.
## Spanish strings are the source language: Controls are translated centrally (I18n).

signal play_pressed
signal card_picked(i: int)
signal reroll_pressed
signal resume_pressed
signal quit_pressed
signal again_pressed
signal menu_pressed
signal settings_pressed

const INK := UIKit.INK
const MUTED := UIKit.MUTED
const GOLD := UIKit.GOLD

var _title: Control
var _levelup: Control
var _pause: Control
var _over: Control
var _lvl_title: Label
var _lvl_sub: Label
var _cards_box: VBoxContainer
var _reroll_btn: Button
var _pause_hint: Label
var _pause_sound: SoundControls
var _over_title: Label
var _over_body: VBoxContainer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UIKit.theme()
	_build_title()
	_build_levelup()
	_build_pause()
	_build_over()
	hide_all()

# ---------------- helpers ----------------

## Kept for compatibility (other screens build flat boxes with it).
static func _box(bg: Color, border: Color, bw: int, radius: int, pad_x := 0, pad_y := 0) -> StyleBoxFlat:
	return UIKit.sb(bg, border, bw, radius, pad_x, pad_y)

func _screen() -> Control:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.set_script(load("res://ui/dim_bg.gd"))
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return root

func _center_panel(root: Control) -> VBoxContainer:
	var cc := CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cc)
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var pc := PanelContainer.new()
	cc.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6 if UIKit.compact else 10)
	pc.add_child(vb)
	return vb

static func _label(text: String, size := 17, col := INK, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	return UIKit.label(text, size, col, align)

func _button(text: String, variation := "", cb := Callable(), sfx := "") -> Button:
	return UIKit.button(text, variation, cb, sfx)

## .card .key: the muted, bordered key number (hidden on touch screens: body.touch .card .key).
static func key_chip(n: int) -> PanelContainer:
	var key := PanelContainer.new()
	key.add_theme_stylebox_override("panel", UIKit.sb(Color(0, 0, 0, 0), Color(UIKit.EDGE, 0.3), 2, 6, 7, 1))
	key.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	key.add_child(_label(str(n), 13, MUTED))
	return key

## Touch UI active (main.gd's TouchInput) for any node in the game tree.
static func touch_active(n: Node) -> bool:
	var g: Node = n.get_tree().current_scene if n.is_inside_tree() else null
	var t: Variant = g.get("touch") if g != null else null
	return t is Object and bool((t as Object).get("active"))

func hide_all() -> void:
	for s in [_title, _levelup, _pause, _over]:
		s.visible = false

func is_open() -> bool:
	return _title.visible or _levelup.visible or _pause.visible or _over.visible

# ---------------- title ----------------

func _build_title() -> void:
	_title = _screen()
	var vb := _center_panel(_title)
	vb.add_child(_label("PokéSurvivor", 44, GOLD))
	vb.add_child(UIKit.spacer(0, 8))
	var play := _button("Jugar", "GoldButton", func(): play_pressed.emit())
	play.set_meta("focus_first", true)
	vb.add_child(play)
	vb.add_child(_label("WASD / flechas para moverte · 1-4 / Q / E cambian de ataque · Esc pausa", 11, MUTED))

func show_title() -> void:
	hide_all()
	_title.visible = true

# ---------------- level-up ----------------

func _build_levelup() -> void:
	_levelup = _screen()
	var vb := _center_panel(_levelup)
	_lvl_title = _label("¡Nivel 2!", 26, INK)
	vb.add_child(_lvl_title)
	_lvl_sub = _label("Elige una recompensa · 1 2 3", 15 if not UIKit.compact else 13, MUTED)
	vb.add_child(_lvl_sub)
	_cards_box = VBoxContainer.new()
	_cards_box.add_theme_constant_override("separation", 6 if UIKit.compact else 10)
	vb.add_child(_cards_box)
	_reroll_btn = _button("Cambiar opciones (1) · R", "SmallGhost", func(): reroll_pressed.emit())
	_reroll_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(_reroll_btn)

## Touch UI active (main.gd's TouchInput): no key hints on touch screens (css body.touch kbd).
func _touch() -> bool:
	return touch_active(self)

func show_level_up(level: int, cards: Array, rerolls_left: int) -> void:
	hide_all()
	_levelup.visible = true
	_lvl_title.text = "¡Nivel %d!" % level
	var touch := _touch()
	_lvl_sub.text = "Elige una recompensa" if touch else "Elige una recompensa · 1 2 3"
	for c in _cards_box.get_children():
		_cards_box.remove_child(c)
		c.queue_free()
	var vw := get_viewport_rect().size.x
	var cw := minf(560.0, vw - (40.0 if UIKit.compact else 80.0))
	for i in cards.size():
		_cards_box.add_child(_card(cards[i], i, cw, touch))
	_reroll_btn.text = ("Cambiar opciones (%d)" % rerolls_left) if touch else ("Cambiar opciones (%d) · R" % rerolls_left)
	_reroll_btn.visible = rerolls_left > 0

## A .card: tinted icon square, title + tag chip, description, key hint (not on touch).
func _card(c: Dictionary, i: int, width: float, touch := false) -> Control:
	var col: Color = c["color"]
	var evo: bool = c["type"] == "evo"
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(width, 0)
	var normal := "CardEvo" if evo else "Card"
	var hover := "CardEvoHover" if evo else "CardHover"
	pc.theme_type_variation = normal
	pc.mouse_filter = Control.MOUSE_FILTER_STOP
	pc.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	pc.mouse_entered.connect(func(): pc.theme_type_variation = hover)
	pc.mouse_exited.connect(func(): pc.theme_type_variation = normal)
	UIKit.hover_sfx(pc)
	pc.gui_input.connect(_on_card_input.bind(i))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10 if UIKit.compact else 14)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(hb)
	# icon on a square tinted with the type colour (.card .ico, background color + 33)
	var ico_bg := PanelContainer.new()
	var isz := 38.0 if UIKit.compact else 46.0
	ico_bg.add_theme_stylebox_override("panel", UIKit.sb(Color(col, 0.2), Color(0, 0, 0, 0), 0, 10))
	ico_bg.custom_minimum_size = Vector2(isz, isz)
	ico_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ico_bg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var ico := UIKit.icon(str(c["icon"]), 32 if not UIKit.compact else 24)
	ico.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ico_bg.add_child(ico)
	hb.add_child(ico_bg)
	var txt := VBoxContainer.new()
	txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	txt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	txt.add_theme_constant_override("separation", 1 if UIKit.compact else 2)
	hb.add_child(txt)
	var row := HFlowContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("h_separation", 8)
	txt.add_child(row)
	row.add_child(_label(str(c["title"]), 18 if not UIKit.compact else 16, GOLD if evo else INK, HORIZONTAL_ALIGNMENT_LEFT))
	var tag_text: String = ("Nuevo · " + str(c["tag"])) if c["type"] == "new" else str(c["tag"])
	var chip_col: Color = col if (c["type"] != "stat" or col == GOLD) else Color.html("#9fb1c9")
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", UIKit.sb(chip_col, Color(0, 0, 0, 0), 0, 5, 7, 1))
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var chip_l := _label(tag_text, 11, Color.html("#10131a"))
	chip_l.add_theme_constant_override("shadow_offset_x", 0)
	chip_l.add_theme_constant_override("shadow_offset_y", 0)
	chip.add_child(chip_l)
	row.add_child(chip)
	var desc := _label(str(c["desc"]), 14 if not UIKit.compact else 13, MUTED, HORIZONTAL_ALIGNMENT_LEFT)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(width - (isz + 90.0), 0)
	txt.add_child(desc)
	if not touch:
		hb.add_child(key_chip(i + 1))
	return pc

func _on_card_input(ev: InputEvent, i: int) -> void:
	var mb := ev as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		card_picked.emit(i)

# ---------------- pause ----------------

func _build_pause() -> void:
	_pause = _screen()
	var vb := _center_panel(_pause)
	vb.add_child(_label("Pausa", 26, INK))
	_pause_hint = _label("WASD moverse · 1–4 movimiento · Q/E ciclar · Esc pausa", 13, MUTED)
	vb.add_child(_pause_hint)
	# #pause-sound: the same sound controls as the top bar's panel (.sound-inline, max 320 px)
	var sc := CenterContainer.new()
	sc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_sound = SoundControls.make(320.0)
	sc.add_child(_pause_sound)
	vb.add_child(sc)
	vb.add_child(UIKit.spacer(0, 4))
	var row := HFlowContainer.new()
	row.alignment = FlowContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("h_separation", 10)
	row.add_theme_constant_override("v_separation", 10)
	var cont := _button("Continuar", "GoldButton", func(): resume_pressed.emit(), "click")
	cont.set_meta("focus_first", true)
	row.add_child(cont)
	row.add_child(_button("Ajustes", "", func(): settings_pressed.emit(), "click"))
	row.add_child(_button("Abandonar run", "", func(): quit_pressed.emit(), "click"))
	vb.add_child(row)

func show_pause(touch := false) -> void:
	hide_all()
	_pause_hint.text = "Arrastra el dedo para moverte · toca un ataque para cambiarlo" if touch \
		else "WASD moverse · 1–4 movimiento · Q/E ciclar · Esc pausa"
	_pause_sound.render()            # run-ui.js showPause: soundControls($('pause-sound'))
	_pause.visible = true

# ---------------- results (Phase 1; the meta results screen is used in the normal flow) ----------------

func _build_over() -> void:
	_over = _screen()
	var vb := _center_panel(_over)
	_over_title = _label("Has caído…", 26, INK)
	vb.add_child(_over_title)
	_over_body = VBoxContainer.new()
	_over_body.add_theme_constant_override("separation", 6)
	vb.add_child(_over_body)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 12)
	hb.add_child(_button("Volver a jugar", "GoldButton", func(): again_pressed.emit()))
	hb.add_child(_button("Menú", "", func(): menu_pressed.emit()))
	vb.add_child(hb)

func show_over(r: Dictionary) -> void:
	hide_all()
	_over.visible = true
	_over_title.text = "Has caído…" if r.get("dead", true) else "Run terminada"
	for c in _over_body.get_children():
		c.queue_free()
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 26)
	for pair in [["Tiempo", U.mmss(r["time"])], ["Nivel", str(r["level"])], ["Derrotados", str(r["kills"])], ["Jefes", str(r["bosses"])]]:
		var cell := VBoxContainer.new()
		cell.add_child(_label(pair[0], 12, MUTED))
		cell.add_child(_label(pair[1], 22, INK))
		grid.add_child(cell)
	var gc := CenterContainer.new()
	gc.add_child(grid)
	_over_body.add_child(gc)
	_over_body.add_child(_label("Pokémonedas ganadas: +%d" % int(r["coins"]), 17, GOLD))
	if str(r.get("breakdown", "")) != "":
		_over_body.add_child(_label(str(r["breakdown"]), 12, MUTED))
	if int(r.get("t1", 0)) > 0 or int(r.get("t10", 0)) > 0:
		_over_body.add_child(_label("Tickets: +%d · ×10: +%d" % [int(r["t1"]), int(r["t10"])], 13, INK))
	var names: Array = []
	for m in r.get("moves", []):
		names.append("%s Nv.%d" % [m["name"], int(m["lvl"])])
	_over_body.add_child(_label("Movimientos: " + (" · ".join(names) if not names.is_empty() else "—"), 13, INK))
