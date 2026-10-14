class_name MetaUI
extends Control
## Root of the out-of-run screens (Phase 4): main menu, collection, upgrades, gacha (+ slot
## machine), missions/achievements/profile, settings, personality test + starters and the run
## results; plus the top bar (coins, tickets, user pill, sound button + panel, settings), the
## credits line, toasts and achievement popups (G.UI / G.Flow,
## js/ui/*.js). Screens are mutually exclusive like G.UI.SCREENS; sub-screens keep the menu
## underneath (keepMenu) and Esc goes back (game.js Esc priority).

signal play_pressed
signal results_closed
signal quit_run_requested          # Settings › Cuenta is about to delete / replace the save (main.gd ends a run)
signal save_replaced               # ... and did: the menu flow starts again (main.gd)

var screens: Dictionary = {}       # name -> Control (has open())
var current := ""
var topbar: Control
var popups: MetaPopups
var settings_screen: SettingsScreen
var _coins_l: Label
var _t1_l: Label
var _t10_l: Label
var _dim: Control
var _sound_btn: Button
var _sound_panel: PanelContainer
var _credits: HBoxContainer
var _chrome := false               # ui.js chrome(): top bar + credits line (menu and sub-screens)
var _covered := false              # the gacha pull overlay covers the chrome (#pull-fx z 40)
var settings_closed_frame := -1    # the Esc that closed Ajustes must not also resume the pause (main.gd)

const SUB := ["dex", "upgrades", "gacha", "goals"]

func _ready() -> void:
	theme = UIKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim = ColorRect.new()
	_dim.set_script(load("res://ui/dim_bg.gd"))
	add_child(_dim)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.visible = false
	for pair in [["menu", MenuScreen], ["dex", DexScreen], ["upgrades", UpgradesScreen], ["gacha", GachaScreen],
			["goals", GoalsScreen], ["test", TestScreen], ["results", ResultsScreen]]:
		var s: Control = pair[1].new()
		s.set("ui", self)
		s.name = pair[0]
		add_child(s)
		s.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		s.visible = false
		screens[pair[0]] = s
	_build_topbar()
	settings_screen = SettingsScreen.new()
	settings_screen.ui = self
	add_child(settings_screen)
	settings_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	settings_screen.visible = false
	popups = MetaPopups.new()
	add_child(popups)
	popups.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hide_all()

# ---------------- navigation ----------------

func hide_all() -> void:
	for k in screens:
		screens[k].visible = false
	settings_screen.visible = false
	_set_chrome(false)
	_dim.visible = false
	current = ""

## ui.js chrome(on): the top bar and the credits line only out of a run (sound panel closed when off).
func _set_chrome(on: bool) -> void:
	_chrome = on
	topbar.visible = on and not _covered
	_credits.visible = on and not _covered and not UIKit.compact      # css compact: .credits-line hidden
	if not on or _covered:
		_sound_panel.visible = false

func set_chrome_covered(on: bool) -> void:
	_covered = on
	_set_chrome(_chrome)

## Shows a screen; sub-screens keep the menu visible underneath with a dim backdrop.
func show_screen(name: String) -> void:
	for k in screens:
		screens[k].visible = (k == name) or (name in SUB and k == "menu")
	_dim.visible = name in SUB or name in ["test", "results"]
	move_child(_dim, screens["menu"].get_index() + 1)
	current = name
	_set_chrome(name == "menu" or name in SUB)
	refresh_coins()
	screens[name].call("open")

func open_menu() -> void:
	show_screen("menu")

func open(name: String) -> void:
	show_screen(name)

func open_settings(tab := "") -> void:
	settings_screen.open(tab)
	move_child(settings_screen, get_child_count() - 2)

func show_results(r: Dictionary) -> void:
	(screens["results"] as ResultsScreen).result = r
	show_screen("results")

func start_test() -> void:
	show_screen("test")

func is_open() -> bool:
	return current != "" or settings_screen.visible

## Esc / back: settings -> close; sub-screen -> menu (not during the gacha animation).
func back() -> bool:
	if settings_screen.visible:
		settings_screen.close()
		settings_closed_frame = Engine.get_process_frames()
		return true
	if current == "goals" and (screens["goals"] as GoalsScreen).close_profile():
		return true
	if current in SUB:
		# game.js: Esc does nothing while the pull overlay is up (also after the reveal), and
		# going back with Esc is silent
		var gs := screens["gacha"] as GachaScreen
		if current == "gacha" and (gs.busy() or gs.overlay_open()):
			return true
		open_menu()
		return true
	return false

func _unhandled_input(ev: InputEvent) -> void:
	# Esc (not P: text fields) / gamepad B go back; focused text fields consume keys first
	var k := ev as InputEventKey
	var jb := ev as InputEventJoypadButton
	if (k != null and k.pressed and not k.echo and k.physical_keycode == KEY_ESCAPE) or \
			(jb != null and jb.pressed and jb.button_index == JOY_BUTTON_B):
		if is_open() and back():
			get_viewport().set_input_as_handled()

func toast(msg: String, secs := 2.2) -> void:
	popups.toast(msg, secs)

func _process(_dt: float) -> void:
	if not Progress.popups.is_empty():
		for p in Progress.popups:
			popups.ach(p)
		Progress.popups.clear()
		refresh_coins()

# ---------------- top bar (coins, tickets, settings) ----------------

func _build_topbar() -> void:
	var c := UIKit.compact                  # css @media max-height 520px: .topbar top 5 right 6 gap 5, .pill 13 px
	topbar = UIKit.hbox(5 if c else 10)
	topbar.name = "TopBar"
	add_child(topbar)
	topbar.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	topbar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	topbar.offset_top = 5 if c else 14
	topbar.offset_right = -6 if c else -16
	topbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fsz := 13 if c else 17
	var isz := 12 if c else 18
	_coins_l = UIKit.label("0", fsz)
	topbar.add_child(UIKit.pill([UIKit.icon("coin", isz), _coins_l]))
	_t1_l = UIKit.label("0", fsz)
	_t10_l = UIKit.label("0", fsz)
	var tp := UIKit.pill([UIKit.icon("ticket", isz), _t1_l, UIKit.spacer(2 if c else 4), UIKit.icon("ticket10", isz), _t10_l])
	tp.tooltip_text = "Tickets del gacha"
	tp.mouse_filter = Control.MOUSE_FILTER_PASS
	topbar.add_child(tp)
	# #user-pill: your name opens Misiones › Perfil (game.js); a plain div (no UI sound)
	var up := UIKit.pill([UIKit.icon("user", isz), UIKit.label("Entrenador", 13 if c else 15)])
	up.mouse_filter = Control.MOUSE_FILTER_STOP
	up.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	up.gui_input.connect(func(ev: InputEvent):
		var mb := ev as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			(screens["goals"] as GoalsScreen).tab = "profile"
			open("goals"))
	topbar.add_child(up)
	# #btn-sound: sound / mute icon, toggles the sound panel
	_sound_btn = UIKit.button("", "SmallGhost", func():
		_sound_panel.visible = not _sound_panel.visible
		if _sound_panel.visible:
			(_sound_panel.get_child(0) as SoundControls).render())
	_sound_btn.custom_minimum_size = Vector2(34, 28) if c else Vector2(44, 40)
	_sound_btn.tooltip_text = "Sonido"
	topbar.add_child(_sound_btn)
	refresh_sound_icon()
	var gear := UIKit.button("", "SmallGhost", func(): open_settings())
	gear.icon = UIKit.icon_tex("gear", 12 if c else 24)
	gear.custom_minimum_size = Vector2(34, 28) if c else Vector2(44, 40)
	gear.tooltip_text = "Ajustes"
	topbar.add_child(gear)
	# .sound-panel: a box under the top bar (top 62 / compact 40, right 16, 270 wide)
	_sound_panel = PanelContainer.new()
	_sound_panel.add_theme_stylebox_override("panel", UIKit.box_style(16, 14))
	var sc := SoundControls.make(238.0)
	sc.mute_changed.connect(refresh_sound_icon)
	_sound_panel.add_child(sc)
	add_child(_sound_panel)
	_sound_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_sound_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_sound_panel.custom_minimum_size = Vector2(270, 0)
	_sound_panel.visible = false
	# .credits-line (bottom left, 12 px; its "Aviso legal" opens the offline legal notice)
	_credits = UIKit.hbox(4)
	var cl := UIKit.label("Proyecto de fan sin ánimo de lucro · Sprites: SpriteCollab (CC BY-NC 4.0) · Pokémon © Nintendo/Creatures/GAME FREAK ·", 12, Color(185 / 255.0, 203 / 255.0, 240 / 255.0, 0.7))
	cl.add_theme_color_override("font_shadow_color", Color.BLACK)
	_credits.add_child(cl)
	var legal := LinkButton.new()
	legal.text = "Aviso legal"
	legal.underline = LinkButton.UNDERLINE_MODE_ALWAYS
	legal.add_theme_font_size_override("font_size", 12)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		legal.add_theme_color_override(k, Color(185 / 255.0, 203 / 255.0, 240 / 255.0, 0.7 if k == "font_color" else 1.0))
	legal.focus_mode = Control.FOCUS_NONE
	legal.pressed.connect(func():
		open_settings("about")
		settings_screen.about_sub = "legal"
		settings_screen.render())
	_credits.add_child(legal)
	add_child(_credits)
	_credits.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_credits.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_credits.offset_left = 14
	_credits.offset_bottom = -10
	_credits.visible = false
	get_viewport().size_changed.connect(_apply_safe)
	_apply_safe()

func refresh_sound_icon() -> void:
	_sound_btn.icon = UIKit.icon_tex("mute" if Settings.muted else "sound", 12 if UIKit.compact else 20)

## Phone cut-outs / rounded corners: keep the top bar and the pages inside the safe area.
func _apply_safe() -> void:
	var ins := Presentation.safe_insets(get_viewport())
	var c := UIKit.compact
	topbar.offset_top = (5 if c else 14) + float(ins["top"])
	topbar.offset_right = -(6 if c else 16) - float(ins["right"])
	_sound_panel.offset_top = (40 if c else 62) + float(ins["top"])
	_sound_panel.offset_right = -16 - float(ins["right"])
	_credits.offset_left = 14 + float(ins["left"])
	for m in get_tree().get_nodes_in_group("ui_page_margin"):
		var mc := m as MarginContainer
		mc.add_theme_constant_override("margin_left", (8 if c else 16) + int(ins["left"]))
		mc.add_theme_constant_override("margin_right", (8 if c else 16) + int(ins["right"]))

func refresh_coins() -> void:
	if not Save.loaded:
		return
	_coins_l.text = UIKit.num_es(int(Save.data["coins"]))
	_t1_l.text = str(int(Save.data["tickets"]["t1"]))
	_t10_l.text = str(int(Save.data["tickets"]["t10"]))

# ---------------- page helper (the .box.wide sub-screens) ----------------

## A sub-screen page: centred PMD box under the top bar with a title row + "Volver".
## Returns {root: the box's content VBox, head: the title row HBox, title: Label}.
static func page(owner: Control, title: String, back_cb: Callable, max_w := 1180.0) -> Dictionary:
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	owner.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# css: sub-screens start under the top bar (padding-top 66; compact: 50 px .scr / 6 px bottom)
	var c := UIKit.compact
	margin.add_theme_constant_override("margin_top", 40 if c else 66)
	margin.add_theme_constant_override("margin_bottom", 6 if c else 14)
	margin.add_theme_constant_override("margin_left", 8 if c else 16)
	margin.add_theme_constant_override("margin_right", 8 if c else 16)
	margin.add_to_group("ui_page_margin")
	var center := HBoxContainer.new()
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(center)
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(0, 0)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(box)
	box.set_meta("max_w", max_w)
	var fit := func():
		var wide := owner.size.x - 32.0 > max_w
		box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER if wide else Control.SIZE_EXPAND_FILL
		box.custom_minimum_size.x = max_w if wide else 0.0
	owner.resized.connect(fit)
	fit.call()
	var v := UIKit.vbox(4 if c else 8)
	box.add_child(v)
	var head := UIKit.hbox(10)
	var tl := UIKit.label(title, 26)
	head.add_child(tl)
	head.add_child(UIKit.spacer(0, 0, true))
	if back_cb.is_valid():
		head.add_child(UIKit.button("Volver", "SmallGhost", back_cb, "back"))
	v.add_child(head)
	return {"root": v, "head": head, "title": tl, "box": box}
