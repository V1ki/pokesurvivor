class_name UIKit
extends RefCounted
## Shared look of every screen (menus are DOM + css/style.css in the web game, §9.1): one Theme
## reproducing the PMD boxes (blue gradient, double white border with dark outer ring and blue
## inner ring), the gold / blue / ghost / danger buttons with their dark ring + bottom ledge,
## chips, tabs, cards and fields, plus small widget builders. Boxes and buttons are 9-patch
## StyleBoxTextures painted pixel by pixel at startup (gradients and multi-ring borders that
## StyleBoxFlat can't do); the rest are StyleBoxFlats with the CSS values. main.gd merges the
## theme into the engine default theme, so every Control (also ones under other CanvasLayers)
## gets it. Compact mode (short phone canvases, css @media max-height 520px) shrinks paddings
## and big titles.

const INK := Color(1, 1, 1)
const MUTED := Color(0.725, 0.796, 0.941)        # #b9cbf0
const GOLD := Color(1.0, 0.824, 0.247)            # #ffd23f
const RED := Color(1.0, 0.373, 0.427)             # #ff5f6d
const GREEN := Color(0.373, 0.878, 0.541)         # #5fe08a
const SHINY := Color(0.604, 0.902, 1.0)           # #9ae6ff
const SHADOW := Color(0.039, 0.078, 0.188)        # #0a1430
const EDGE := Color(0.957, 0.973, 1.0)            # #f4f8ff
const EDGE_OUT := Color(0.043, 0.094, 0.22)       # #0b1838
const EDGE_IN := Color(0.357, 0.514, 0.839)       # #5b83d6
const BOX := Color(0.133, 0.255, 0.498)           # between #2c519f and #1a3170
const BOX1 := Color(0.173, 0.318, 0.624)          # #2c519f
const BOX2 := Color(0.102, 0.192, 0.439)          # #1a3170
const GEN_NAMES := ["Kanto", "Johto", "Hoenn", "Sinnoh", "Teselia", "Kalos", "Alola", "Galar", "Paldea"]

static var _theme: Theme = null
static var compact := false        # set by main.gd from the canvas height before the UI is built
static var _box_style: StyleBoxTexture = null

static func sb(bg: Color, border := Color(0, 0, 0, 0), bw := 0, radius := 8, px := 0, py := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = px
	s.content_margin_right = px
	s.content_margin_top = py
	s.content_margin_bottom = py
	s.corner_detail = 5
	return s

# ---------------- pixel painted 9-patches ----------------

## Is the pixel (x, y) inside the rounded rect inset `ins` from a w x h image, corner radius r?
static func _in_rr(x: int, y: int, w: int, h: int, ins: Vector4, r: float) -> bool:
	var px := x + 0.5
	var py := y + 0.5
	var x0 := ins.x
	var y0 := ins.y
	var x1 := w - ins.z
	var y1 := h - ins.w
	if px < x0 or py < y0 or px > x1 or py > y1:
		return false
	var cx := clampf(px, x0 + r, x1 - r)
	var cy := clampf(py, y0 + r, y1 - r)
	return (px - cx) * (px - cx) + (py - cy) * (py - cy) <= r * r + 0.25

static func _bright(c: Color, k: float) -> Color:
	return Color(minf(1.0, c.r * k), minf(1.0, c.g * k), minf(1.0, c.b * k), c.a)

static func _gray(c: Color) -> Color:
	# CSS grayscale(.8) brightness(.7)
	var l := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
	var g := Color(lerpf(c.r, l, 0.8), lerpf(c.g, l, 0.8), lerpf(c.b, l, 0.8), c.a)
	return _bright(g, 0.7)

## Layered rounded rects: each layer = [inset Vector4 (l, t, r, b), radius, Color or [top, bottom]].
## Later layers paint over earlier ones. A [top, bottom] fill is a vertical gradient over the
## middle (stretched) rows `g0..g1`. The geometry (which layer owns each pixel) is computed once
## per shape and cached; colouring a variant is a cheap pass over that map.
static var _masks: Dictionary = {}
static var _texs: Dictionary = {}

static func _mask(w: int, h: int, layers: Array) -> PackedByteArray:
	var key := "%d,%d,%s" % [w, h, str(layers.map(func(L): return [L[0], L[1]]))]
	if _masks.has(key):
		return _masks[key]
	var m := PackedByteArray()
	m.resize(w * h)
	for y in h:
		for x in w:
			var top := 0
			for i in layers.size():
				var L: Array = layers[i]
				if _in_rr(x, y, w, h, L[0], L[1]):
					top = i + 1
			m[y * w + x] = top
	_masks[key] = m
	return m

static func _paint(w: int, h: int, layers: Array, g0: int, g1: int, fx := "") -> ImageTexture:
	var key := "%d,%d,%s,%d,%d,%s" % [w, h, str(layers), g0, g1, fx]
	if _texs.has(key):
		return _texs[key]
	var m := _mask(w, h, layers)
	var data := PackedByteArray()
	data.resize(w * h * 4)
	for y in h:
		var t := clampf(float(y - g0) / maxf(1.0, float(g1 - g0 - 1)), 0.0, 1.0)
		# per-row colour of every layer
		var row: Array = [Color(0, 0, 0, 0)]
		for L in layers:
			var c: Variant = L[2]
			var col: Color = (c[0] as Color).lerp(c[1], t) if c is Array else c
			if fx == "hover":
				col = _bright(col, 1.15)
			elif fx == "disabled":
				col = _gray(col)
			row.append(col)
		for x in w:
			var col: Color = row[m[y * w + x]]
			var o := (y * w + x) * 4
			data[o] = col.r8
			data[o + 1] = col.g8
			data[o + 2] = col.b8
			data[o + 3] = col.a8
	var tex := ImageTexture.create_from_image(Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data))
	_texs[key] = tex
	return tex

static func _tex_style(tex: Texture2D, margin: int, expand: Vector4, content: Vector4) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = tex
	s.texture_margin_left = margin
	s.texture_margin_right = margin
	s.texture_margin_top = margin
	s.texture_margin_bottom = margin
	s.expand_margin_left = expand.x
	s.expand_margin_top = expand.y
	s.expand_margin_right = expand.z
	s.expand_margin_bottom = expand.w
	s.content_margin_left = content.x
	s.content_margin_top = content.y
	s.content_margin_right = content.z
	s.content_margin_bottom = content.w
	return s

## .box: gradient #2c519f -> #1a3170, border 3 #f4f8ff r 12, outer ring 3 #0b1838 (outside the
## box: expand margin), inner ring 2 #5b83d6.
static func box_style(pad_x := 24, pad_y := 20, edge := EDGE) -> StyleBoxTexture:
	var w := 48
	var h := 112
	var tex := _paint(w, h, [[Vector4(0, 0, 0, 0), 15.0, EDGE_OUT], [Vector4(3, 3, 3, 3), 12.0, edge],
		[Vector4(6, 6, 6, 6), 9.0, EDGE_IN], [Vector4(8, 8, 8, 8), 7.0, [BOX1, BOX2]]], 16, h - 16)
	return _tex_style(tex, 16, Vector4(3, 3, 3, 3), Vector4(3 + pad_x, 3 + pad_y, 3 + pad_x, 3 + pad_y))

## .btn: border 3 r 9 over a vertical gradient, ring 2 #0b1838 + 4 px bottom ledge (outside the
## button: expand margins). Pressed: 2 px lower with a 2 px ledge. fx: "" / "hover" / "disabled".
static func _btn_tex(top: Color, bottom: Color, border: Color, pressed: bool, fx := "", ring := true) -> ImageTexture:
	var w := 40
	var h := 64
	var o := 2 if ring else 0                       # ring width around
	var ledge := (2 if pressed else 4) if ring else 0
	var bot := maxi(o, ledge)
	var layers: Array = []
	if ring:
		# ring around the box + the ledge (the box shape shifted down)
		layers.append([Vector4(0, 0, 0, bot - o), 11.0, EDGE_OUT])
		layers.append([Vector4(o, o + ledge, o, 0), 9.0, EDGE_OUT])
	layers.append([Vector4(o, o, o, bot), 9.0, border])
	layers.append([Vector4(o + 3, o + 3, o + 3, bot + 3), 6.0, [top, bottom]])
	return _paint(w, h, layers, o + 12, h - bot - 12, fx)

static func _btn_style(top: Color, bottom: Color, border: Color, pressed: bool, fx: String, pad: Vector2, ring := true) -> StyleBoxTexture:
	var o := 2 if ring else 0
	var ledge := (2 if pressed else 4) if ring else 0
	var bot := maxi(o, ledge)
	var tex := _btn_tex(top, bottom, border, pressed, fx, ring)
	# pressed: the box is drawn 2 px lower (texture top = control top), text 2 px lower too
	var shift := 2.0 if pressed and ring else 0.0
	var s := _tex_style(tex, 14, Vector4(o, o - shift, o, bot + shift), Vector4(3 + pad.x, 3 + pad.y + shift, 3 + pad.x, 3 + pad.y - shift))
	return s

static func _focus_ring(radius := 11) -> StyleBoxFlat:
	var f := sb(Color(0, 0, 0, 0), GOLD, 3, radius)
	f.draw_center = false
	f.set_expand_margin_all(4)
	return f

static func _btn(t: Theme, type: String, top: Color, bottom: Color, font: Color, border := EDGE, pad := Vector2(17, 7),
		ring := true, flat_bg := Color(0, 0, 0, 0)) -> void:
	if ring:
		t.set_stylebox("normal", type, _btn_style(top, bottom, border, false, "", pad))
		t.set_stylebox("hover", type, _btn_style(top, bottom, border, false, "hover", pad))
		t.set_stylebox("pressed", type, _btn_style(top, bottom, border, true, "", pad))
		t.set_stylebox("hover_pressed", type, _btn_style(top, bottom, border, true, "hover", pad))
		t.set_stylebox("disabled", type, _btn_style(top, bottom, border, false, "disabled", pad))
	else:
		# ghost: transparent, light border, no ring
		var n := sb(flat_bg, border, 3, 9, int(pad.x) + 3, int(pad.y) + 3)
		var h := sb(Color(1, 1, 1, 0.1), Color(border, minf(1.0, border.a * 1.6)), 3, 9, int(pad.x) + 3, int(pad.y) + 3)
		var d := sb(flat_bg, Color(border, border.a * 0.5), 3, 9, int(pad.x) + 3, int(pad.y) + 3)
		t.set_stylebox("normal", type, n)
		t.set_stylebox("hover", type, h)
		t.set_stylebox("pressed", type, h)
		t.set_stylebox("hover_pressed", type, h)
		t.set_stylebox("disabled", type, d)
	t.set_stylebox("focus", type, _focus_ring())
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		t.set_color(k, type, font)
	t.set_color("font_disabled_color", type, Color(0.72, 0.74, 0.8))
	t.set_color("font_outline_color", type, SHADOW if font != Color.html("#3a2300") else Color(1, 1, 1, 0.4))

static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = DrawUtil.font(700)
	t.default_font_size = 17
	t.set_color("font_color", "Label", INK)
	t.set_color("font_shadow_color", "Label", SHADOW)
	t.set_constant("shadow_offset_x", "Label", 2)
	t.set_constant("shadow_offset_y", "Label", 2)
	t.set_constant("line_spacing", "Label", 1)
	# PMD box (.box) and the inner panels (.panel, transparent "Bare")
	_box_style = box_style(14 if compact else 22, 10 if compact else 18)
	t.set_stylebox("panel", "PanelContainer", _box_style)
	t.set_stylebox("panel", "Panel", _box_style)
	t.add_type("Inset")
	t.set_type_variation("Inset", "PanelContainer")
	t.set_stylebox("panel", "Inset", sb(Color(0, 0, 0, 0.2), Color(EDGE, 0.2), 2, 10, 8 if compact else 12, 6 if compact else 10))
	t.add_type("Bare")
	t.set_type_variation("Bare", "PanelContainer")
	t.set_stylebox("panel", "Bare", StyleBoxEmpty.new())
	# clickable cards (level-up, item, bond): .card / .card:hover / .card.evo
	for v in ["Card", "CardHover", "CardEvo", "CardEvoHover", "CardBond", "Toast"]:
		t.add_type(v)
		t.set_type_variation(v, "PanelContainer")
	var cpx := 10 if compact else 14
	var cpy := 6 if compact else 11
	t.set_stylebox("panel", "Card", sb(Color(0, 0, 0, 0.2), Color(EDGE, 0.3), 2, 12, cpx, cpy))
	t.set_stylebox("panel", "CardHover", sb(Color(1, 1, 1, 0.1), EDGE, 2, 12, cpx, cpy))
	t.set_stylebox("panel", "CardEvo", sb(Color(1.0, 0.824, 0.247, 0.12), GOLD, 2, 12, cpx, cpy))
	t.set_stylebox("panel", "CardEvoHover", sb(Color(1.0, 0.824, 0.247, 0.22), GOLD, 3, 12, cpx, cpy))
	t.set_stylebox("panel", "CardBond", sb(Color(1.0, 0.541, 0.847, 0.12), Color.html("#ff8ad8"), 2, 12, cpx, cpy))
	var toast := sb(Color(10 / 255.0, 20 / 255.0, 50 / 255.0, 0.95), EDGE, 2, 10, 18, 10)
	t.set_stylebox("panel", "Toast", toast)
	# buttons (.btn, .gold, .ghost, .danger, .small)
	var pad := Vector2(14, 5) if compact else Vector2(18, 8)
	var spad := Vector2(9, 3) if compact else Vector2(11, 4)
	_btn(t, "Button", Color.html("#3d67c0"), Color.html("#26468f"), INK, EDGE, pad)
	t.set_font_size("font_size", "Button", 17)
	for v in ["GoldButton", "GhostButton", "DangerButton", "SmallButton", "SmallGold", "SmallGhost", "MenuItem", "Chip", "ChipOn", "ChipBan", "Tab", "TabOn", "GenTab", "GenTabOn", "Answer", "Cell", "CellOn"]:
		t.add_type(v)
		t.set_type_variation(v, "Button")
	_btn(t, "GoldButton", Color.html("#ffe37a"), Color.html("#f0a31e"), Color.html("#3a2300"), Color.html("#fff7d6"), pad)
	_btn(t, "GhostButton", Color(0, 0, 0, 0), Color(0, 0, 0, 0), INK, Color(EDGE, 0.35), pad, false)
	_btn(t, "DangerButton", Color.html("#a8293b"), Color.html("#8a1f2e"), INK, Color.html("#ff8a96"), pad)
	_btn(t, "SmallButton", Color.html("#3d67c0"), Color.html("#26468f"), INK, EDGE, spad)
	_btn(t, "SmallGold", Color.html("#ffe37a"), Color.html("#f0a31e"), Color.html("#3a2300"), Color.html("#fff7d6"), spad)
	_btn(t, "SmallGhost", Color(0, 0, 0, 0), Color(0, 0, 0, 0), INK, Color(EDGE, 0.35), spad, false)
	for v in ["SmallButton", "SmallGold", "SmallGhost"]:
		t.set_font_size("font_size", v, 13 if compact else 14)
	# menu list item (.menu-item): transparent, highlight on hover / focus (the PMD cursor is a child)
	var mi := sb(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 6, 10, 4)
	var mh := sb(Color(1, 1, 1, 0.08), Color(0, 0, 0, 0), 0, 6, 10, 4)
	for st in ["normal", "disabled"]:
		t.set_stylebox(st, "MenuItem", mi)
	for st in ["hover", "pressed", "hover_pressed"]:
		t.set_stylebox(st, "MenuItem", mh)
	var mf := sb(Color(1, 1, 1, 0.1), GOLD, 2, 6, 10, 4)
	t.set_stylebox("focus", "MenuItem", mf)
	# chips / tabs / answers / grid cells
	var cx := 8 if compact else 10
	var chip := sb(Color(0, 0, 0, 0.25), Color(EDGE, 0.25), 2, 20, cx, 3)
	var chip_h := sb(Color(1, 1, 1, 0.1), Color(EDGE, 0.5), 2, 20, cx, 3)
	var chip_on := sb(Color(1.0, 0.824, 0.247, 0.12), GOLD, 2, 20, cx, 3)
	# .chip.on.ban (upgrades › Veto): red tint and border, light red text (the strike-through is drawn by the screen)
	var chip_ban := sb(Color(1.0, 0.373, 0.427, 0.25), RED, 2, 20, cx, 3)
	_set_states(t, "Chip", chip, chip_h, chip_h)
	_set_states(t, "ChipOn", chip_on, chip_on, chip_on)
	_set_states(t, "ChipBan", chip_ban, chip_ban, chip_ban)
	for v in ["Chip", "ChipOn", "ChipBan"]:
		t.set_font_size("font_size", v, 13)
		for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
			t.set_color(k, v, GOLD if v == "ChipOn" else (Color.html("#ffd3d8") if v == "ChipBan" else MUTED))
	var tpy := 4 if compact else 7
	var tab := sb(Color(0, 0, 0, 0.2), Color(0, 0, 0, 0), 2, 8, 10, tpy)
	var tab_h := sb(Color(1, 1, 1, 0.07), Color(EDGE, 0.3), 2, 8, 10, tpy)
	var tab_on := sb(Color(1, 1, 1, 0.1), EDGE, 2, 8, 10, tpy)
	_set_states(t, "Tab", tab, tab_h, tab_h)
	_set_states(t, "TabOn", tab_on, tab_on, tab_on)
	t.set_font_size("font_size", "Tab", 14 if compact else 15)
	t.set_font_size("font_size", "TabOn", 14 if compact else 15)
	# .gen-tab (collection / gacha generations, settings tabs): .on = gold border + tint + name
	var gtab := sb(Color(0, 0, 0, 0.25), Color(EDGE, 0.22), 2, 9, 10, tpy)
	var gtab_h := sb(Color(0, 0, 0, 0.25), EDGE, 2, 9, 10, tpy)
	var gtab_on := sb(Color(1.0, 0.824, 0.247, 0.14), GOLD, 2, 9, 10, tpy)
	_set_states(t, "GenTab", gtab, gtab_h, gtab_h)
	_set_states(t, "GenTabOn", gtab_on, gtab_on, gtab_on)
	for v in ["GenTab", "GenTabOn"]:
		t.set_font_size("font_size", v, 14 if compact else 15)
		for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
			t.set_color(k, v, GOLD if v == "GenTabOn" else INK)
	var apy := 6 if compact else 11
	var ans := sb(Color(0, 0, 0, 0.18), Color(EDGE, 0.25), 2, 9, 16, apy)
	var ans_h := sb(Color(1, 1, 1, 0.1), EDGE, 2, 9, 16, apy)
	for st in [ans, ans_h]:
		st.content_margin_left = 34           # .answer: padding-left 34 px (room for the cursor arrow)
	_set_states(t, "Answer", ans, ans_h, ans_h)
	t.set_font_size("font_size", "Answer", 14 if compact else 17)
	var cell := sb(Color(0, 0, 0, 0.2), Color(EDGE, 0.18), 2, 10, 2, 2)
	var cell_h := sb(Color(1, 1, 1, 0.08), EDGE, 2, 10, 2, 2)
	var cell_on := sb(Color(1.0, 0.824, 0.247, 0.14), GOLD, 2, 10, 2, 2)
	_set_states(t, "Cell", cell, cell_h, cell_h)
	_set_states(t, "CellOn", cell_on, cell_on, cell_on)
	# scroll bars
	var grab := sb(Color(EDGE, 0.3), Color(0, 0, 0, 0), 0, 5)
	for sbt in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", sbt, sb(Color(0, 0, 0, 0.15), Color(0, 0, 0, 0), 0, 5, 3, 3))
		t.set_stylebox("grabber", sbt, grab)
		t.set_stylebox("grabber_highlight", sbt, sb(Color(EDGE, 0.5), Color(0, 0, 0, 0), 0, 5))
		t.set_stylebox("grabber_pressed", sbt, sb(EDGE, Color(0, 0, 0, 0), 0, 5))
	# fields (.field)
	var field := sb(Color.html("#0f1f4a"), EDGE_IN, 2, 8, 10, 6 if compact else 8)
	var field_f := sb(Color.html("#0f1f4a"), EDGE, 2, 8, 10, 6 if compact else 8)
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", field_f)
	t.set_stylebox("normal", "TextEdit", field)
	t.set_stylebox("focus", "TextEdit", field_f)
	t.set_font_size("font_size", "TextEdit", 13)
	t.set_font_size("font_size", "LineEdit", 15)
	t.set_color("font_placeholder_color", "LineEdit", Color(MUTED, 0.6))
	t.set_color("font_placeholder_color", "TextEdit", Color(MUTED, 0.6))
	t.set_stylebox("normal", "OptionButton", field)
	t.set_stylebox("hover", "OptionButton", sb(Color.html("#15295c"), EDGE, 2, 8, 10, 6 if compact else 8))
	t.set_stylebox("pressed", "OptionButton", field_f)
	t.set_stylebox("hover_pressed", "OptionButton", field_f)
	t.set_stylebox("disabled", "OptionButton", field)
	t.set_stylebox("focus", "OptionButton", _focus_ring(9))
	t.set_font_size("font_size", "OptionButton", 14)
	t.set_stylebox("panel", "PopupMenu", sb(Color.html("#15295c"), EDGE, 2, 8, 6, 6))
	t.set_stylebox("hover", "PopupMenu", sb(Color(1, 1, 1, 0.12), Color(0, 0, 0, 0), 0, 4))
	t.set_font_size("font_size", "PopupMenu", 15)
	t.set_color("font_color", "PopupMenu", INK)
	t.set_color("font_hover_color", "PopupMenu", GOLD)
	t.set_stylebox("panel", "TooltipPanel", sb(Color(10 / 255.0, 20 / 255.0, 50 / 255.0, 0.95), EDGE, 2, 8, 10, 6))
	t.set_font_size("font_size", "TooltipLabel", 14)
	t.set_color("font_color", "TooltipLabel", INK)
	# sliders
	t.set_stylebox("slider", "HSlider", sb(Color(0, 0, 0, 0.35), Color(EDGE, 0.25), 2, 6, 0, 4))
	t.set_stylebox("grabber_area", "HSlider", sb(GOLD, Color(0, 0, 0, 0), 0, 6, 0, 4))
	t.set_stylebox("grabber_area_highlight", "HSlider", sb(Color.html("#ffe37a"), Color(0, 0, 0, 0), 0, 6, 0, 4))
	t.set_icon("grabber", "HSlider", _knob(false))
	t.set_icon("grabber_highlight", "HSlider", _knob(true))
	t.set_stylebox("focus", "HSlider", _focus_ring(8))
	_theme = t
	return t

## Slider knob: a small gold PMD ball (pixel painted).
static func _knob(hi: bool) -> ImageTexture:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in 16:
		for x in 16:
			var d := Vector2(x + 0.5 - 8.0, y + 0.5 - 8.0).length()
			if d <= 7.6:
				img.set_pixel(x, y, EDGE_OUT if d > 6.0 else (Color.html("#ffe37a") if hi else GOLD))
	return ImageTexture.create_from_image(img)

static func _set_states(t: Theme, type: String, n: StyleBox, h: StyleBox, p: StyleBox) -> void:
	t.set_stylebox("normal", type, n)
	t.set_stylebox("hover", type, h)
	t.set_stylebox("pressed", type, p)
	t.set_stylebox("hover_pressed", type, p)
	t.set_stylebox("disabled", type, n)
	var f: StyleBoxFlat = (h as StyleBoxFlat).duplicate() if h is StyleBoxFlat else sb(Color(1, 1, 1, 0.1), GOLD, 2, 8)
	f.border_color = GOLD
	t.set_stylebox("focus", type, _focus_ring(int((n as StyleBoxFlat).corner_radius_top_left) + 2) if n is StyleBoxFlat else f)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color", "font_disabled_color"]:
		t.set_color(k, type, INK)

## Installs the theme as the fallback of every Control (merged into the engine default theme),
## so screens under any CanvasLayer (HUD helpers, run modals, other agents' screens) share it.
static func install_global() -> void:
	var def := ThemeDB.get_default_theme()
	if def != null:
		def.merge_with(theme())
		def.default_font = theme().default_font
		def.default_font_size = theme().default_font_size
	ThemeDB.fallback_font = theme().default_font

## Font size for this canvas: compact (phone) layouts shrink the big titles like the CSS
## (@media max-height 520px: h2 26 -> 20, logo 46 -> 30, menu items 22 -> 15...).
static func fs(size: int) -> int:
	if not compact or size <= 17:
		return size
	if size >= 40:
		return int(round(size * 0.55))
	if size >= 24:
		return int(round(size * 0.76))
	return int(round(size * 0.86))

# ---------------- widgets ----------------

static func label(text: String, size := 17, col := INK, align := HORIZONTAL_ALIGNMENT_LEFT, wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", fs(size))
	l.add_theme_color_override("font_color", col)
	if size <= 13:
		l.add_theme_constant_override("shadow_offset_x", 1)
		l.add_theme_constant_override("shadow_offset_y", 1)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## Button with the theme variation; focusable (keyboard / gamepad navigation shows a gold
## ring, mouse / touch clicks don't: gui/common/show_focus_state_on_pointer_event).
## `hover` = ui.js wireSounds: every clickable plays "hover" when the pointer enters it (false
## for the elements outside its CLICKABLE list: .seg buttons, favourite slots, locked cells).
static func button(text: String, variation := "", cb := Callable(), sfx := "click", hover := true) -> Button:
	var b := Button.new()
	b.text = text
	if variation != "":
		b.theme_type_variation = variation
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if cb.is_valid():
		b.pressed.connect(func():
			if sfx != "":
				Sfx.play(sfx)
			cb.call())
	if hover:
		hover_sfx(b)
	return b

## "hover" when the pointer really enters `c` (not disabled; not on keyboard / gamepad focus,
## which InputRouter mirrors as mouse_entered on clickable cards).
static func hover_sfx(c: Control) -> void:
	c.mouse_entered.connect(func():
		var bb := c as BaseButton
		if (bb == null or not bb.disabled) and c.get_global_rect().has_point(c.get_global_mouse_position()):
			Sfx.play("hover"))

## .seg (menu / collection Normal-Shiny): joined buttons in a 2 px rounded frame (no own sounds).
static func seg(btns: Array) -> PanelContainer:
	var p := panel("", hbox(0, btns))
	p.add_theme_stylebox_override("panel", sb(Color(0, 0, 0, 0), Color(EDGE, 0.35), 2, 9))
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

## Marks the active .seg button (`.seg button.on`: cyan background, #c9f3ff text).
static func seg_set(btns: Array, on: int) -> void:
	for i in btns.size():
		var b: Button = btns[i]
		var st := sb(Color(154 / 255.0, 230 / 255.0, 1.0, 0.22) if i == on else Color(0, 0, 0, 0.25), Color(0, 0, 0, 0), 0, 0, 14, 5)
		var r := 7
		st.corner_radius_top_left = r if i == 0 else 0
		st.corner_radius_bottom_left = r if i == 0 else 0
		st.corner_radius_top_right = r if i == btns.size() - 1 else 0
		st.corner_radius_bottom_right = r if i == btns.size() - 1 else 0
		for k in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			b.add_theme_stylebox_override(k, st)
		var fc := Color.html("#c9f3ff") if i == on else INK
		for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
			b.add_theme_color_override(k, fc)
		b.add_theme_font_size_override("font_size", 14)

## Pixel icon at an integer scale (icons.js size snapping).
static func icon(name: String, size := 24.0) -> TextureRect:
	var r := TextureRect.new()
	r.texture = Icons.tex(name)
	var s := Icons.snap(name, size)
	r.custom_minimum_size = Vector2(s, s * r.texture.get_height() / r.texture.get_width())
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return r

static var _scaled: Dictionary = {}

## Icon texture pre-scaled (nearest) to the snapped size, for Button.icon (buttons don't scale icons).
static func icon_tex(name: String, size := 18.0) -> Texture2D:
	var key := "%s@%d" % [name, int(size)]
	if _scaled.has(key):
		return _scaled[key]
	var base := Icons.tex(name)
	var s := Icons.snap(name, size)
	var img := base.get_image()
	img.resize(int(s), int(s * base.get_height() / base.get_width()), Image.INTERPOLATE_NEAREST)
	var t := ImageTexture.create_from_image(img)
	_scaled[key] = t
	return t

## Rarity ball (G.Icons.rarity): Poké / Great / Ultra / Luxury / Master Ball.
static func rarity_icon(r: int, size := 12.0) -> TextureRect:
	var balls: Dictionary = Data.icons.get("rarity_ball", {})
	return icon(str(balls.get(str(r), "ball")), size)

static func hbox(sep := 8, children: Array = []) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in children:
		h.add_child(c)
	return h

static func vbox(sep := 8, children: Array = []) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in children:
		v.add_child(c)
	return v

static func panel(variation := "", child: Control = null) -> PanelContainer:
	var p := PanelContainer.new()
	if variation != "":
		p.theme_type_variation = variation
	if child != null:
		p.add_child(child)
	return p

static func spacer(w := 0.0, h := 0.0, expand_h := false, expand_v := false) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if expand_h:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if expand_v:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c

## Type chip: type colour pill with the Spanish name.
static func type_chip(t: String) -> PanelContainer:
	var p := panel("", label(str(Data.type_name.get(t, t)), 12, INK, HORIZONTAL_ALIGNMENT_CENTER))
	p.add_theme_stylebox_override("panel", sb(Data.tcolor(t), Color(0, 0, 0, 0.35), 1, 6, 7, 1))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return p

static func type_chips(types: Array) -> HBoxContainer:
	var h := hbox(4)
	h.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for t in types:
		h.add_child(type_chip(str(t)))
	return h

## Pill (top bar): dark rounded box with a white border.
static func pill(children: Array) -> PanelContainer:
	var p := panel("", hbox(5 if compact else 6, children))
	var s := sb(Color(10 / 255.0, 20 / 255.0, 50 / 255.0, 0.85), EDGE, 2, 16, 8 if compact else 12, 2 if compact else 4)
	s.shadow_color = EDGE_OUT
	s.shadow_size = 2
	p.add_theme_stylebox_override("panel", s)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

## Thin progress bar (missions, achievements, stats).
static func bar(frac: float, col := GOLD, w := 0.0, h := 8.0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func():
		DrawUtil.round_rect(c, Rect2(Vector2.ZERO, c.size), c.size.y / 2.0, Color(0, 0, 0, 0.35))
		var f := clampf(frac, 0.0, 1.0)
		if f > 0.0:
			DrawUtil.round_rect(c, Rect2(0, 0, maxf(c.size.y, c.size.x * f), c.size.y), c.size.y / 2.0, col))
	return c

static func num(n: int) -> String:
	return Progress._num(n) if n >= 10000 else str(n)

## Thousands with '.' like toLocaleString('es'): Spanish only groups from 5 digits (4331, 12.345).
static func num_es(n: int) -> String:
	var s := str(n)
	if s.length() <= 4:
		return s
	var out := ""
	while s.length() > 3:
		out = "." + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out

static func dex_no(d: int) -> String:
	return "%03d" % d
