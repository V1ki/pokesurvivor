class_name GachaScreen
extends Control
## Gacha (js/ui/gacha-ui.js): 9 banner tabs, banner (3-colour gradient, "<Region> Misterioso",
## owned count, 3 featured sprites), pulls x1 / x10 (10 tickets) / x10 (1 x10 ticket), tickets
## and pity lines, rates panel. A pull is resolved first (Gacha.pull + checkAch + commit), then
## the slot machine plays and the result cards are revealed 150 ms apart.

var ui: MetaUI
var gen := 1
var _busy := false
var _tabs: HBoxContainer
var _banner: PanelContainer
var _b_title: Label
var _b_desc: Label
var _b_owned: HBoxContainer
var _feat: HBoxContainer
var _p1: Button
var _p10: Button
var _p10b: Button
var _tickets: HBoxContainer
var _pity: Label
var _rates: VBoxContainer
var _fx: Control                 # pull overlay
var _slot: SlotMachine
var _cards: HFlowContainer
var _close: Button
var _cols: Array = []

func busy() -> bool:
	return _busy

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pg := MetaUI.page(self, "Gacha", func(): ui.open_menu())
	var root: VBoxContainer = pg["root"]
	_tabs = UIKit.hbox(6)
	root.add_child(_tabs)
	for b in Gacha.banners():
		var g := int(b["gen"])
		var t := UIKit.button("%s\nGen %d" % [b["name"], g], "GenTab", func():
			gen = g
			refresh(), "click")
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.add_theme_font_size_override("font_size", 12 if UIKit.compact else 14)
		_tabs.add_child(t)
	var split := UIKit.hbox(14)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)
	var left := UIKit.vbox(10)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(left)
	_banner = PanelContainer.new()
	_banner.theme_type_variation = "Bare"
	_banner.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_banner.draw.connect(_draw_banner)
	_banner.clip_contents = true
	left.add_child(_banner)
	var bm := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		bm.add_theme_constant_override("margin_" + side, 8 if UIKit.compact else 18)
	_banner.add_child(bm)
	var bv := UIKit.vbox(2)
	bm.add_child(bv)
	_b_title = UIKit.label("", 26, UIKit.GOLD)
	_b_desc = UIKit.label("", 13 if UIKit.compact else 15)
	_b_owned = UIKit.hbox(5)
	bv.add_child(_b_title)
	bv.add_child(_b_desc)
	bv.add_child(_b_owned)
	_feat = UIKit.hbox(0)
	_feat.alignment = BoxContainer.ALIGNMENT_CENTER
	_feat.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bv.add_child(_feat)
	var row := UIKit.hbox(10)
	_p1 = _pull_btn("Tirar ×1 ·", "ticket", 1, "", func(): _pull(1, "t1"))
	_p10 = _pull_btn("Tirar ×10 ·", "ticket", 10, "GoldButton", func(): _pull(10, "t1"))
	_p10b = _pull_btn("Tirar ×10 ·", "ticket10", 1, "GoldButton", func(): _pull(10, "t10"))
	for b in [_p1, _p10, _p10b]:
		row.add_child(b)
	left.add_child(row)
	_tickets = UIKit.hbox(5)
	_pity = UIKit.label("", 12 if UIKit.compact else 14, UIKit.MUTED)
	left.add_child(_tickets)
	left.add_child(_pity)
	var rp := UIKit.panel("Inset")
	rp.custom_minimum_size = Vector2(230 if UIKit.compact else 320, 0)
	split.add_child(rp)
	_rates = UIKit.vbox(5)
	rp.add_child(_rates)
	_build_fx()

## gacha-ui.js pull buttons: "Tirar ×N · [ticket 18] cost" (the icon before the number).
func _pull_btn(prefix: String, ico: String, cost: int, variation: String, cb: Callable) -> Button:
	var b := UIKit.button("", variation, cb, "")
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var gold := variation == "GoldButton"
	var col := Color.html("#3a2300") if gold else UIKit.INK
	var h := UIKit.hbox(5)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	for c in [UIKit.label(prefix, 17, col), UIKit.icon(ico, 18), UIKit.label(str(cost), 17, col)]:
		if gold and c is Label:
			c.add_theme_color_override("font_shadow_color", Color(1, 1, 1, 0.4))
			c.add_theme_constant_override("shadow_offset_x", 1)
			c.add_theme_constant_override("shadow_offset_y", 1)
		h.add_child(c)
	b.add_child(h)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.custom_minimum_size = Vector2(0, 40 if UIKit.compact else 46)
	return b

## .btn:disabled: grayscale + darker (the content is a child here, not the button's own text).
static func _set_pull_enabled(b: Button, on: bool) -> void:
	b.disabled = not on
	(b.get_child(0) as Control).modulate = Color(1, 1, 1) if on else Color(0.62, 0.62, 0.66)

func open() -> void:
	# Esc (MetaUI.back) can leave while the result overlay is up: never show stale results
	if not _busy and _fx.visible:
		_fx.visible = false
		ui.set_chrome_covered(false)
	refresh()

func refresh() -> void:
	var s := Save.data
	var banner: Dictionary = Gacha.banners()[gen - 1]
	for i in _tabs.get_child_count():
		(_tabs.get_child(i) as Button).theme_type_variation = "GenTabOn" if i + 1 == gen else "GenTab"
	var all: Array = Data.dex.filter(func(p): return int(p["gen"]) == gen)
	var owned := 0
	var shinies := 0
	for p in all:
		if (s["owned"] as Dictionary).has(str(p["dex"])):
			owned += 1
		if (s["shiny"] as Dictionary).has(str(p["dex"])):
			shinies += 1
	_cols = (banner["color"] as Array).map(func(h): return Color.html(h))
	_banner.queue_redraw()
	_b_title.text = str(banner["name"]) + " Misterioso"
	_b_desc.text = "Los %d Pokémon de la generación %d. ¡Los legendarios esperan!" % [all.size(), gen]
	# "Tienes X de Y · [shiny 12] N shiny"
	for c in _b_owned.get_children():
		c.queue_free()
	var osz := 12 if UIKit.compact else 14
	_b_owned.add_child(UIKit.label("Tienes %d de %d" % [owned, all.size()], osz, UIKit.MUTED))
	if shinies:
		_b_owned.add_child(UIKit.label("·", osz, UIKit.MUTED))
		_b_owned.add_child(UIKit.icon("shiny", 12))
		_b_owned.add_child(UIKit.label("%d shiny" % shinies, osz, UIKit.MUTED))
	for c in _feat.get_children():
		c.queue_free()
	for d in Gacha.featured(gen):
		var fw := 110.0 if UIKit.compact else 170.0
		_feat.add_child(PokeView.make(d, fw, 100.0 if UIKit.compact else 190.0, {"full": true, "lively": true, "px": 2, "dir": 1}))
	var pity := int(s["pity"].get(str(gen), 0))
	_pity.text = "Tiradas sin legendaria en %s: %d / %d" % [banner["name"], pity, int(Gacha.cfg()["pity"])]
	var t: Dictionary = s["tickets"]
	# "Tienes [ticket] <b>N</b> tickets y [ticket10] <b>N</b> tickets ×10"
	for c in _tickets.get_children():
		c.queue_free()
	var tsz := 12 if UIKit.compact else 14
	for part in [["Tienes", ""], ["", "ticket"], [str(int(t["t1"])), "b"], ["tickets y", ""], ["", "ticket10"], [str(int(t["t10"])), "b"], ["tickets ×10", ""]]:
		if part[1] == "ticket" or part[1] == "ticket10":
			_tickets.add_child(UIKit.icon(part[1], 18))
		else:
			var l := UIKit.label(part[0], tsz, UIKit.INK if part[1] == "b" else UIKit.MUTED)
			if part[1] == "b":
				l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			_tickets.add_child(l)
	_set_pull_enabled(_p1, not Gacha.cost_of(s, 1).is_empty())
	_set_pull_enabled(_p10, not Gacha.cost_of(s, 10, "t1").is_empty())
	_set_pull_enabled(_p10b, not Gacha.cost_of(s, 10, "t10").is_empty())
	for c in _rates.get_children():
		c.queue_free()
	_rates.add_child(UIKit.label("Probabilidades", 18))
	var rates: Array = (Gacha.cfg()["rates"] as Array).duplicate()
	rates.reverse()
	for rw in rates:
		var r := int(rw[0])
		var h := UIKit.hbox(6, [UIKit.rarity_icon(r, 12), UIKit.label(Gacha.rarity_name(r), 15, Gacha.rarity_color(r))])
		h.add_child(UIKit.spacer(0, 0, true))
		var pct: float = float(rw[1])
		h.add_child(UIKit.label("%s%% · %d" % [str(int(pct)) if pct == floorf(pct) else str(pct), Gacha.pool(r, gen).size()], 15))
		_rates.add_child(h)
	var hs := UIKit.hbox(6, [UIKit.icon("shiny", 12), UIKit.label("Shiny", 15, UIKit.SHINY), UIKit.spacer(0, 0, true), UIKit.label("1%", 15)])
	_rates.add_child(hs)
	var note := UIKit.label("· La tirada ×10 garantiza al menos una Épica.\n· A las %d tiradas sin Legendaria en un banner, la siguiente lo es.\n· Los repetidos dan Pokémonedas. Los shiny no se repiten.\n· Los tickets se consiguen jugando: algunos Pokémon los sueltan al caer, y los jefes y los legendarios de las grietas, a veces, tickets ×10." % int(Gacha.cfg()["pity"]),
		13, UIKit.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true)
	note.custom_minimum_size = Vector2(200 if UIKit.compact else 290, 0)
	_rates.add_child(UIKit.spacer(0, 6))
	_rates.add_child(note)
	ui.refresh_coins()

static var _glows: Dictionary = {}

static func _glow(c: Color) -> Texture2D:
	if not _glows.has(c):
		var g := Gradient.new()
		g.set_color(0, c)
		g.set_color(1, Color(c, 0.0))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 128
		t.height = 128
		_glows[c] = t
	return _glows[c]

func _draw_banner() -> void:
	if _cols.size() < 3:
		return
	var r := Rect2(Vector2.ZERO, _banner.size)
	# linear-gradient(135deg, c1, c2 55%, c3) approximated with a 4-corner polygon
	var c1: Color = _cols[0]
	var c2: Color = _cols[1]
	var c3: Color = _cols[2]
	var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	_banner.draw_polygon(pts, PackedColorArray([c1, c2, c3, c2]))
	# radial-gradient glows: gold at 80% 30%, purple at 15% 80%
	var gw := maxf(r.size.x, r.size.y)
	_banner.draw_texture_rect(_glow(Color(1.0, 0.824, 0.247, 0.3)), Rect2(r.size.x * 0.8 - gw * 0.45, r.size.y * 0.3 - gw * 0.45, gw * 0.9, gw * 0.9), false)
	_banner.draw_texture_rect(_glow(Color(0.77, 0.48, 1.0, 0.3)), Rect2(r.size.x * 0.15 - gw * 0.5, r.size.y * 0.8 - gw * 0.5, gw, gw), false)
	var sbx := UIKit.sb(Color(0, 0, 0, 0), UIKit.EDGE, 3, 12)
	sbx.draw_center = false
	_banner.draw_style_box(sbx, r)

# ---------------- pull animation overlay (#pull-fx) ----------------

func _build_fx() -> void:
	_fx = Control.new()
	_fx.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_fx)
	_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# #pull-fx: radial-gradient(circle at 50% 45%, #1b2d63, #03060f 70%) (farthest corner)
	var dim := Control.new()
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var grad := Gradient.new()
	grad.set_color(0, Color.html("#1b2d63"))
	grad.set_color(1, Color.html("#03060f"))
	var rt := GradientTexture2D.new()
	rt.gradient = grad
	rt.fill = GradientTexture2D.FILL_RADIAL
	rt.fill_from = Vector2(0.5, 0.5)
	rt.fill_to = Vector2(1.0, 0.5)
	rt.width = 256
	rt.height = 256
	dim.draw.connect(func():
		var sz := dim.size
		var ctr := Vector2(sz.x * 0.5, sz.y * 0.45)
		var r := Vector2(maxf(ctr.x, sz.x - ctr.x), maxf(ctr.y, sz.y - ctr.y)).length() * 0.7
		dim.draw_rect(Rect2(Vector2.ZERO, sz), Color.html("#03060f"))
		dim.draw_texture_rect(rt, Rect2(ctr - Vector2(r, r), Vector2(r, r) * 2.0), false))
	dim.resized.connect(dim.queue_redraw)
	var cc := CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.add_child(cc)
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var v := UIKit.vbox(8 if UIKit.compact else 16)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	cc.add_child(v)
	var sc := CenterContainer.new()
	sc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# #slot: filter drop-shadow(0 0 30px rgba(255,90,90,.35)) behind the machine
	var glow := UIKit.sb(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 10)
	glow.shadow_color = Color(1.0, 90 / 255.0, 90 / 255.0, 0.35)
	glow.shadow_size = 30
	sc.draw.connect(func(): if _slot != null: sc.draw_style_box(glow, Rect2(_slot.position, _slot.size)))
	_slot = SlotMachine.new()
	_slot.item_rect_changed.connect(sc.queue_redraw)
	_slot.tooltip_text = "Clic para acelerar"
	sc.add_child(_slot)
	v.add_child(sc)
	_cards = HFlowContainer.new()
	_cards.alignment = FlowContainer.ALIGNMENT_CENTER
	_cards.add_theme_constant_override("h_separation", 6 if UIKit.compact else 10)
	_cards.add_theme_constant_override("v_separation", 6 if UIKit.compact else 10)
	_cards.custom_minimum_size = Vector2(840, 0)
	_cards.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_cards)
	var bc := CenterContainer.new()
	_close = UIKit.button("Continuar", "GoldButton", _close_fx, "click")        # #pull-close: a plain .btn
	_close.custom_minimum_size = Vector2(220, 0)
	bc.add_child(_close)
	v.add_child(bc)
	_fx.visible = false

func _pull(n: int, use: String) -> void:
	if _busy:
		return
	var res := Gacha.pull(Save.data, n, gen, use)
	if res.is_empty():
		Sfx.play("error")
		ui.toast("No tienes tickets suficientes: consíguelos jugando")
		return
	Progress.check_ach()
	Save.commit()
	_busy = true
	await play_results(res)
	_busy = false

## Slot machine then result cards (also used by the autoshot harness).
func play_results(res: Array) -> void:
	var best := 0
	for r in res:
		best = maxi(best, int(r["rarity"]))
	for c in _cards.get_children():
		c.queue_free()
	_close.visible = false
	# css #slot: width min(528px, 92vw, 66vh): k = 1 on short phone canvases (crisp at the 3x phone scale)
	_slot.set_scale_k(clampi(int((size.y - 120.0) / SlotMachine.H), 1, 4))
	_slot.get_parent().visible = true
	_cards.visible = false
	_fx.visible = true
	# #slot animation: pop .25s ease-out (scale .94 -> 1, fade in)
	_slot.pivot_offset = _slot.custom_minimum_size / 2.0
	_slot.scale = Vector2(0.94, 0.94)
	_slot.modulate.a = 0.0
	var pop := _slot.create_tween().set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	pop.tween_property(_slot, "scale", Vector2.ONE, 0.25)
	pop.tween_property(_slot, "modulate:a", 1.0, 0.25)
	(_slot.get_parent() as Control).queue_redraw()
	ui.set_chrome_covered(true)             # #pull-fx (z 40) covers the top bar and the credits line
	await _slot.play(res)
	Sfx.play("burst", {"rarity": best})
	_slot.get_parent().visible = false
	_cards.visible = true
	_cards.custom_minimum_size.x = minf(840.0, size.x - 40.0)
	for r in res:
		_cards.add_child(_card(r))
		Sfx.play("reveal", {"rarity": int(r["rarity"])})
		if res.size() == 10:
			await get_tree().create_timer(0.15).timeout
	_close.visible = true
	ui.refresh_coins()

func _card(r: Dictionary) -> PanelContainer:
	var rc: Color = UIKit.SHINY if r["shiny"] else Gacha.rarity_color(int(r["rarity"]))
	var p := PanelContainer.new()
	var sbx := UIKit.sb(Color(10 / 255.0, 20 / 255.0, 50 / 255.0, 0.9), rc, 3, 12, 6, 6)
	sbx.shadow_color = Color(rc, 0.6)          # .pcard: box-shadow 0 0 22px var(--rc) on every card
	sbx.shadow_size = 11
	p.add_theme_stylebox_override("panel", sbx)
	var c := UIKit.compact                 # css @media max-height 520px: .pcard 100 px, canvas 84 px
	p.custom_minimum_size = Vector2(100 if c else 150, 0)
	var v := UIKit.vbox(1 if c else 2)
	p.add_child(v)
	var st := UIKit.rarity_icon(int(r["rarity"]), 12 if c else 24)
	st.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(st)
	var big: bool = int(r["rarity"]) >= 4 or r["shiny"]
	var pv := PokeView.make(int(r["dex"]), 84 if c else 132, 64 if c else 120, {"full": big, "lively": big, "px": 1 if c else 2, "shiny": r["shiny"]})
	pv.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(pv)
	var nm := UIKit.hbox(4)
	nm.alignment = BoxContainer.ALIGNMENT_CENTER
	if r["shiny"]:
		nm.add_child(UIKit.icon("shiny", 12))
	nm.add_child(UIKit.label(str(Data.dex_by[int(r["dex"])]["name"]), 12 if c else 16, UIKit.INK, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(nm)
	if r["isNew"]:
		v.add_child(UIKit.label("¡SHINY NUEVO!" if r["shiny"] else "¡NUEVO!", 10 if c else 13, UIKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	else:
		var tg := UIKit.hbox(4, [UIKit.label("Repetido ·", 10 if c else 12, UIKit.MUTED), UIKit.icon("coin", 12), UIKit.label("+%d" % int(r["refund"]), 10 if c else 12, UIKit.GOLD)])
		tg.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_child(tg)
	# pop-in (scale .94 -> 1 + fade, .3 s); legendaries (1.4 s) and shinies (1.1 s) pulse their
	# glow to 0 0 40px + 0 0 80px (@keyframes legend, ease-in-out, alternate)
	p.modulate.a = 0.0
	p.pivot_offset = Vector2(50, 66) if c else Vector2(75, 100)
	p.scale = Vector2(0.94, 0.94)
	var tw := p.create_tween()
	tw.set_parallel(true)
	tw.tween_property(p, "modulate:a", 1.0, 0.3)
	tw.tween_property(p, "scale", Vector2.ONE, 0.3)
	if int(r["rarity"]) == 5 or r["shiny"]:
		var per := 1.1 if r["shiny"] else 1.4
		var glow := func(k: float):
			sbx.shadow_size = int(lerpf(11.0, 34.0, k))
			sbx.shadow_color = Color(rc, lerpf(0.6, 0.85, k))
		var pulse := p.create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		pulse.tween_method(glow, 0.0, 1.0, per)
		pulse.tween_method(glow, 1.0, 0.0, per)
	return p

func _close_fx() -> void:
	_fx.visible = false
	ui.set_chrome_covered(false)
	refresh()

func overlay_open() -> bool:
	return _fx.visible
