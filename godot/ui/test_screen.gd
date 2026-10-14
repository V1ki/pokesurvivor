class_name TestScreen
extends Control
## Personality test -> result -> (optional) starter grid (js/ui/test.js, starters.js).
## Runs when the save has no partner. 8 questions x 4 answers add trait points; the result is the
## top trait and the best-matching starter (Meta.personality_result). "Elegir otro" opens the
## 29 starters. choose(): starter = partner = dex, personality saved, Pokémon granted.

var ui: MetaUI
var idx := 0
var scores: Dictionary = {}
var result: Dictionary = {}
var picked := 0
var _q: Array = []
var _traits: Dictionary = {}
var _starters: Array = []
var _box: VBoxContainer
var _panel: PanelContainer
var _center: CenterContainer

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st: Dictionary = Data._json("starters.json")
	_q = st["test"]
	_traits = st["trait_text"]
	_starters = st["starters"]
	_center = CenterContainer.new()
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_center)
	_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel = PanelContainer.new()
	_center.add_child(_panel)
	_box = UIKit.vbox(10)
	_panel.add_child(_box)

func open() -> void:
	idx = 0
	scores = {}
	result = {}
	_render_q()

func _clear(width: float) -> void:
	for c in _box.get_children():
		c.queue_free()
	_panel.custom_minimum_size = Vector2(minf(width, size.x - 32.0), 0)

func _render_q() -> void:
	_clear(620)
	var q: Dictionary = _q[idx]
	var bar := UIKit.bar(float(idx) / _q.size(), UIKit.GOLD, 0, 8)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_child(bar)
	_box.add_child(UIKit.label("Pregunta %d de %d" % [idx + 1, _q.size()], 15, UIKit.MUTED))
	var ql := UIKit.label(str(q["q"]), 22, UIKit.INK, HORIZONTAL_ALIGNMENT_LEFT, true)
	ql.custom_minimum_size = Vector2(560, 60)
	_box.add_child(ql)
	for a in q["a"]:
		var b := UIKit.button(str(a["t"]), "Answer", func(): _answer(a), "select")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		# .answer:hover::before: the PMD cursor arrow (12×18 at left 10, centred)
		var cur := UIKit.icon("cursor", 12)
		cur.size = cur.custom_minimum_size
		cur.visible = false
		b.add_child(cur)
		b.resized.connect(func(): cur.position = Vector2(10, roundf((b.size.y - cur.custom_minimum_size.y) / 2.0)))
		b.mouse_entered.connect(func(): cur.visible = true)
		b.mouse_exited.connect(func(): cur.visible = b.has_focus())
		b.focus_entered.connect(func(): cur.visible = true)
		b.focus_exited.connect(func(): cur.visible = false)
		_box.add_child(b)

func _answer(a: Dictionary) -> void:
	for k in a["p"]:
		scores[k] = int(scores.get(k, 0)) + int(a["p"][k])
	idx += 1
	if idx < _q.size():
		_render_q()
	else:
		_show_result()

func _show_result() -> void:
	result = Meta.personality_result(scores)
	_render_result()

## #scr-result for the computed `result` ("Volver" from the starters shows it again as it was).
func _render_result() -> void:
	var mon: Dictionary = Data.dex_by[int(result["dex"])]
	_clear(560)
	_box.add_child(UIKit.label("Tu personalidad es…", 15, UIKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	var tr: String = result["trait"]
	_box.add_child(UIKit.label(tr.substr(0, 1).to_upper() + tr.substr(1), 30, UIKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	var tx := UIKit.label(str(_traits.get(tr, "")), 17, UIKit.INK, HORIZONTAL_ALIGNMENT_CENTER, true)
	tx.custom_minimum_size = Vector2(500, 0)
	_box.add_child(tx)
	var cc := CenterContainer.new()
	var st := PokeView.make(int(result["dex"]), 160 if UIKit.compact else 200, 110 if UIKit.compact else 150, {"full": true, "lively": true, "hero": true, "px": 3 if UIKit.compact else 4, "stage": true})
	st.stage_color = Data.tcolor(str(mon["types"][0]))
	cc.add_child(st)
	_box.add_child(cc)
	var nm := UIKit.hbox(6, [UIKit.label("Tu compañero:", 19), UIKit.label(str(mon["name"]), 19, UIKit.GOLD)])
	nm.alignment = BoxContainer.ALIGNMENT_CENTER
	_box.add_child(nm)
	var row := UIKit.hbox(10, [UIKit.button("¡Vamos juntos!", "GoldButton", func(): choose(int(result["dex"])), "click"),
		UIKit.button("Elegir otro", "", _open_starters)])
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_box.add_child(row)

func _open_starters() -> void:
	picked = int(result.get("dex", 0))
	_clear(1000)
	_box.add_child(UIKit.label("Elige a tu compañero", 26))
	_box.add_child(UIKit.label("Los iniciales de todas las regiones, y dos amigos más.", 13 if UIKit.compact else 15, UIKit.MUTED))
	var cpt := UIKit.compact
	var cw := 86.0 if cpt else 100.0
	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 6 if cpt else 8)
	grid.add_theme_constant_override("v_separation", 6 if cpt else 8)
	var info := UIKit.hbox(6)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ok := UIKit.button("Elegir", "GoldButton", func():
		if picked:
			choose(picked), "click")
	var cells: Array = []
	for s in _starters:
		var d := int(s["dex"])
		var b := UIKit.button("", "CellOn" if d == picked else "Cell", Callable(), "click")
		b.custom_minimum_size = Vector2(cw, 86.0 if cpt else 100.0)
		var pv := PokeView.make(d, cw - 8.0, 66.0 if cpt else 80.0, {"px": 2})
		pv.position = Vector2(4, 2)
		b.add_child(pv)
		var l := UIKit.label(str(Data.dex_by[d]["name"]), 12 if cpt else 13, UIKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
		l.position = Vector2(0, 66.0 if cpt else 80.0)
		l.size = Vector2(cw, 18)
		l.clip_text = true
		b.add_child(l)
		b.pressed.connect(func():
			Sfx.play("click")                   # .cell: ui.js click
			for c in cells:
				c.theme_type_variation = "Cell"
			b.theme_type_variation = "CellOn"
			picked = d
			_info(info, s)
			ok.disabled = false)
		cells.append(b)
		grid.add_child(b)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, minf(440.0, size.y - (150.0 if cpt else 260.0)))
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.add_child(grid)
	_box.add_child(sc)
	ok.disabled = picked == 0
	if picked:
		for s in _starters:
			if int(s["dex"]) == picked:
				_info(info, s)
	else:
		info.add_child(UIKit.label("Selecciona un Pokémon", 15, UIKit.MUTED))
	var back := UIKit.button("Volver", "GhostButton", func():
		if result.is_empty():
			open()
		else:
			_render_result(), "click")
	var row := UIKit.hbox(10, [back, info, ok])
	_box.add_child(row)

func _info(box: HBoxContainer, s: Dictionary) -> void:
	for c in box.get_children():
		c.queue_free()
	var mon: Dictionary = Data.dex_by[int(s["dex"])]
	box.add_child(UIKit.type_chips(mon["types"]))
	box.add_child(UIKit.icon("move:" + str(s["start"]), 16))
	box.add_child(UIKit.label("%s · %s" % [Moves.def(s["start"]).get("name", s["start"]), ", ".join(s["traits"])], 15, UIKit.MUTED))

func choose(dex: int) -> void:
	var s := Save.data
	s["starter"] = dex
	s["partner"] = dex
	s["personality"] = {"trait": result["trait"], "scores": scores} if not result.is_empty() else null
	Save.grant(dex, "starter")
	Save.commit()
	ui.toast("¡%s se une a ti!" % Data.dex_by[dex]["name"])
	ui.open_menu()
