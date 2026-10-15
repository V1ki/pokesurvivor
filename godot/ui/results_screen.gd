class_name ResultsScreen
extends Control
## Run results (js/ui/run-ui.js showOver, #scr-over): "Has caído…" / "Run terminada", time, level,
## kills, bosses, coins earned + breakdown, the partner's family (level, XP, moves learned,
## evolutions now possible), tickets, moves with levels, shinies caught, new time record,
## "Volver al menú". The save was already updated (Meta.apply_run).

var ui: MetaUI
var result: Dictionary = {}
var _box: VBoxContainer
var _panel: PanelContainer

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cc := CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cc)
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(520, 0)
	cc.add_child(_panel)
	_box = UIKit.vbox(8)
	_panel.add_child(_box)

## The partner's family (run-ui.js famRow): level (+levels gained), XP bar, XP gained, the moves it
## learned and the forms it can evolve into now.
func _fam_row(r: Dictionary) -> VBoxContainer:
	var f: Dictionary = r["fam"]
	var dex := int(r.get("dex", 0))
	var lv := int(f["lv"])
	var from := lv - int(f["ups"])
	var head := UIKit.hbox(8, [UIKit.label("Familia de %s" % Families.fam_name(int(f["f"])), 13, UIKit.MUTED),
		UIKit.label("Nv. %d" % lv, 20, UIKit.INK)])
	if int(f["ups"]) > 0:
		head.add_child(UIKit.label("(+%d)" % int(f["ups"]), 18, UIKit.GOLD))
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	var v := UIKit.vbox(3, [head])
	if lv < int(Families.R["cap"]):
		v.add_child(UIKit.bar(minf(1.0, float(f["xp"]) / maxf(1.0, float(f["need"]))), UIKit.GOLD, 0.0, 8.0))
	v.add_child(UIKit.label("+%d de experiencia" % int(f["gained"]), 12, UIKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	if int(f["ups"]) > 0 and dex > 0:
		var learned := Families.moves_of(dex).filter(func(e): return int(e[1]) > from and int(e[1]) <= lv)
		if not learned.is_empty():
			var row := HFlowContainer.new()
			row.alignment = FlowContainer.ALIGNMENT_CENTER
			row.add_theme_constant_override("h_separation", 6)
			row.add_child(UIKit.label("Aprende:", 13, UIKit.MUTED))
			for e in learned:
				row.add_child(UIKit.hbox(3, [UIKit.icon("move:" + str(e[0]), 14), UIKit.label(str(Moves.def(e[0]).get("name", e[0])), 13)]))
			v.add_child(row)
	for d in Families.members(int(f["f"])):
		if d == dex or not Data.dex_by.has(d) or Families.req_level(d) <= from or Families.req_level(d) > lv:
			continue
		var nm := str(Data.dex_by[d]["name"])
		if Save.owns(d):
			v.add_child(UIKit.label("¡Ya puede evolucionar a %s!" % nm, 14, UIKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER, true))
		else:
			v.add_child(UIKit.label("Ya tiene nivel para %s: consíguelo en el gacha o con fragmentos." % nm, 13, UIKit.INK, HORIZONTAL_ALIGNMENT_CENTER, true))
	return v

## .stats > div: a muted UPPER-CASE 12 px caption over the value.
func _cell(lbl: String, val: Control) -> VBoxContainer:
	var cap := UIKit.label(lbl, 12, UIKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	cap.uppercase = true
	var v := UIKit.vbox(0, [cap])
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if val is BoxContainer:
		(val as BoxContainer).alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(val)
	return v

func open() -> void:
	for c in _box.get_children():
		c.queue_free()
	var r := result
	var cpt := UIKit.compact
	# compact (short phone canvas): two columns, stats + coins on the left, the rest on the right
	var col_a: VBoxContainer = _box
	var col_b: VBoxContainer = _box
	_panel.custom_minimum_size = Vector2(minf(760.0, size.x - 16.0) if cpt else 520.0, 0)
	_box.add_child(UIKit.label("Has caído…" if r.get("dead", true) else "Run terminada", 28, UIKit.INK, HORIZONTAL_ALIGNMENT_CENTER))
	if cpt:
		var cols := UIKit.hbox(10)
		col_a = UIKit.vbox(6)
		col_b = UIKit.vbox(6)
		col_a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cols.add_child(col_a)
		cols.add_child(col_b)
		_box.add_child(cols)
	# .stats: a 2×2 grid of boxes (Tiempo, Nivel, Derrotados as a plain number, Jefes)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for pair in [["Tiempo", U.mmss(float(r.get("time", 0)))], ["Nivel", str(int(r.get("level", 1)))],
			["Derrotados", str(int(r.get("kills", 0)))], ["Jefes", str(int(r.get("bosses", 0)))]]:
		var cell := UIKit.panel("", _cell(pair[0], UIKit.label(pair[1], 22, UIKit.INK, HORIZONTAL_ALIGNMENT_CENTER)))
		cell.add_theme_stylebox_override("panel", UIKit.sb(Color(0, 0, 0, 0.22), Color(0, 0, 0, 0), 0, 9, 10, 6 if cpt else 8))
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(cell)
	col_a.add_child(grid)
	var coins := UIKit.hbox(6, [UIKit.icon("coin", 18), UIKit.label("+%d" % int(r.get("coins", 0)), 24, UIKit.GOLD)])
	var cv := _cell("Pokémonedas ganadas", coins)
	var bd := UIKit.label(str(r.get("breakdown", "")), 12, UIKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER, true)
	bd.custom_minimum_size = Vector2(300 if cpt else 440, 0)
	cv.add_child(bd)
	col_a.add_child(UIKit.panel("Inset", cv))
	if r.get("fam") is Dictionary:
		col_a.add_child(UIKit.panel("Inset", _fam_row(r)))
	if int(r.get("t1", 0)) or int(r.get("t10", 0)):
		var th := UIKit.hbox(6)
		if int(r.get("t1", 0)):
			th.add_child(UIKit.icon("ticket", 22))
			th.add_child(UIKit.label("+%d" % int(r["t1"]), 18))
		if int(r.get("t10", 0)):
			th.add_child(UIKit.icon("ticket10", 22))
			th.add_child(UIKit.label("+%d ×10" % int(r["t10"]), 18))
		col_b.add_child(UIKit.panel("Inset", _cell("Tickets del gacha", th)))
	var mv := HFlowContainer.new()
	mv.alignment = FlowContainer.ALIGNMENT_CENTER
	mv.add_theme_constant_override("h_separation", 10)
	var moves: Array = r.get("moves", [])
	for i in moves.size():
		var m: Dictionary = moves[i]
		var it := UIKit.hbox(4, [UIKit.icon("move:" + str(m["id"]), 16), UIKit.label("%s Nv.%d" % [m["name"], int(m["lvl"])], 15)])
		if i < moves.size() - 1:
			it.add_child(UIKit.label("·", 15))           # joined with " · "
		mv.add_child(it)
	if moves.is_empty():
		mv.add_child(UIKit.label("—", 15))
	var mvc := UIKit.vbox(2, [UIKit.label("Movimientos", 13, UIKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER), mv])
	col_b.add_child(UIKit.panel("Inset", mvc))
	var caught: Array = r.get("caught", [])
	if not caught.is_empty():
		var row := UIKit.hbox(8)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		for c in caught:
			var d := int(c["dex"])
			row.add_child(UIKit.vbox(0, [PokeView.make(d, 70 if cpt else 90, 56 if cpt else 72, {"shiny": true, "full": true, "lively": true, "px": 1 if cpt else 2}),
				UIKit.label(str(Data.dex_by[d]["name"]) + (" · ¡nuevo!" if c.get("isNew", false) else ""), 12, UIKit.INK, HORIZONTAL_ALIGNMENT_CENTER)]))
		var head := UIKit.hbox(4, [UIKit.icon("shiny", 12), UIKit.label("Shinies conseguidos", 13, UIKit.MUTED)])
		head.alignment = BoxContainer.ALIGNMENT_CENTER
		col_b.add_child(UIKit.panel("Inset", UIKit.vbox(4, [head, row])))
	if r.get("record", false):
		col_b.add_child(UIKit.label("¡Nuevo récord de tiempo!", 15 if cpt else 17, UIKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	var bc := CenterContainer.new()
	var back := UIKit.button("Volver al menú", "GoldButton", func(): ui.results_closed.emit(), "click")
	back.set_meta("focus_first", true)
	bc.add_child(back)
	col_b.add_child(bc)
