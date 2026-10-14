class_name ItemChoice
extends Control
## Held-item swap screen (#scr-item, js/ui/run-ui.js showItemChoice): you can only carry
## one item, so picking up another opens two cards, "keep X" / "switch to Y" (keys 1 / 2).
## The game is paused (Sim state "choice") until a card is chosen.

signal chosen(i: int)

const INK := Color(1, 1, 1)
const MUTED := Color(0.725, 0.796, 0.941)        # #b9cbf0
const GOLD := Color(1.0, 0.824, 0.247)            # #ffd23f

var _cards: VBoxContainer
var _sub: Label

static func _box(bg: Color, border: Color, bw: int, radius: int, pad_x := 0, pad_y := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad_x
	sb.content_margin_right = pad_x
	sb.content_margin_top = pad_y
	sb.content_margin_bottom = pad_y
	return sb

static func _label(text: String, size := 17, col := INK, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_override("font", DrawUtil.font(700))
	l.add_theme_color_override("font_shadow_color", Color.html("#0a1430"))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l

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
	var pc := PanelContainer.new()          # the theme's PMD box
	cc.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	pc.add_child(vb)
	vb.add_child(_label("¡Un objeto!", UIKit.fs(26), INK))
	_sub = _label("Sólo puedes llevar uno · 1 2", 13 if UIKit.compact else 15, MUTED)
	vb.add_child(_sub)
	_cards = VBoxContainer.new()
	_cards.add_theme_constant_override("separation", 10)
	vb.add_child(_cards)
	visible = false

func open(cur: String, next: String) -> void:
	for c in _cards.get_children():
		c.queue_free()
	var width := minf(560.0, _view_w() - (40.0 if UIKit.compact else 80.0))
	var touch := Screens.touch_active(self)
	_sub.text = "Sólo puedes llevar uno" if touch else "Sólo puedes llevar uno · 1 2"
	var pairs := [[cur, "Quedarme con"], [next, "Cambiar a"]]
	for i in 2:
		_cards.add_child(_card(pairs[i][0], pairs[i][1], i, width, touch))
	visible = true

func close() -> void:
	visible = false

func _card(id: String, verb: String, i: int, width: float, touch := false) -> Control:
	var it := Items.by_id(id)
	var gold := i == 1
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(width, 0)
	var normal := "CardEvo" if gold else "Card"
	var hover := "CardEvoHover" if gold else "CardHover"
	pc.theme_type_variation = normal
	pc.mouse_filter = Control.MOUSE_FILTER_STOP
	pc.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	pc.mouse_entered.connect(func(): pc.theme_type_variation = hover)
	pc.mouse_exited.connect(func(): pc.theme_type_variation = normal)
	UIKit.hover_sfx(pc)
	# a tap arrives as an emulated mouse press too (handling ScreenTouch as well picked twice)
	pc.gui_input.connect(func(ev: InputEvent):
		var mb := ev as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			chosen.emit(i))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(hb)
	var ico := TextureRect.new()
	ico.texture = Icons.tex(id)
	ico.custom_minimum_size = Vector2(36, 36)
	ico.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ico.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ico.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ico.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ico.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(ico)
	var txt := VBoxContainer.new()
	txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	txt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	txt.add_theme_constant_override("separation", 2)
	hb.add_child(txt)
	txt.add_child(_label(verb + " " + str(it.get("name", id)), 16 if UIKit.compact else 18, GOLD if gold else INK, HORIZONTAL_ALIGNMENT_LEFT))
	var desc := _label(str(it.get("desc", "")), 13 if UIKit.compact else 14, MUTED, HORIZONTAL_ALIGNMENT_LEFT)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(width - 120.0, 0)
	txt.add_child(desc)
	if not touch:
		hb.add_child(Screens.key_chip(i + 1))
	return pc

## Canvas width (1280 outside the tree: the headless tap tests build the cards detached).
func _view_w() -> float:
	return get_viewport_rect().size.x if is_inside_tree() else 1280.0
