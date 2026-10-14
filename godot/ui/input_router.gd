class_name InputRouter
extends Node
## Global input glue (Phase 5), added by main.gd:
##  - Android back button (and gamepad B / Esc where main.gd / MetaUI don't handle it): pause during
##    a run, close the open screen, and a quit dialog on the main menu.
##  - Keyboard / gamepad focus navigation of every menu and modal screen: the first arrow / d-pad /
##    stick / Tab press focuses the first control of the screen on top (or the one marked with
##    meta "focus_first"), A / Enter / Space press it. Clickable cards (PanelContainers with a
##    gui_input handler: level-up, item, bond cards...) become focusable and get a synthetic click,
##    and show their hover look while focused. Scroll containers follow the focus.
##  - Pointer input (mouse / touch) leaves navigation mode again.

var game                               # main.gd (untyped: dynamic state queries)
var nav := false                       # last input was keyboard / gamepad navigation
var _quit: Control = null              # quit dialog (main menu + back)
var _prepared: Dictionary = {}         # instance id -> true (focus hooks installed)

const NAV_ACTIONS := ["ui_up", "ui_down", "ui_left", "ui_right", "ui_focus_next", "ui_focus_prev"]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().quit_on_go_back = false
	get_tree().node_added.connect(_on_node_added)

func _on_node_added(n: Node) -> void:
	var sc := n as ScrollContainer
	if sc != null:
		sc.follow_focus = true

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		back()

# ---------------- back ----------------

## Android back: the same priorities as Esc in game.js, plus the quit dialog on the menu.
func back() -> void:
	if game == null:
		return
	if _quit != null:
		_close_quit()
		return
	var sim: Sim = game.sim
	var meta: MetaUI = game.meta
	if meta.settings_screen.visible:
		meta.back()
		return
	match sim.state:
		"playing", "paused":
			game.toggle_pause()
		"levelup", "choice":
			pass                       # a card must be chosen
		_:
			if meta.is_open() and meta.back():
				return
			if meta.current == "results":
				meta.results_closed.emit()
			elif meta.current == "menu" or meta.current == "":
				_open_quit()

func _open_quit() -> void:
	var root := Control.new()
	root.name = "QuitDialog"
	root.theme = UIKit.theme()
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.set_script(load("res://ui/dim_bg.gd"))
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var cc := CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cc)
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var v := UIKit.vbox(14)
	v.add_child(UIKit.label("¿Salir del juego?", 22, UIKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	var stay := UIKit.button("Cancelar", "GhostButton", _close_quit, "back")
	stay.set_meta("focus_first", true)
	var row := UIKit.hbox(12, [stay, UIKit.button("Salir del juego", "DangerButton", func(): get_tree().quit(), "click")])
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	cc.add_child(UIKit.panel("", v))
	var layer := CanvasLayer.new()
	layer.layer = 50
	layer.name = "QuitLayer"
	add_child(layer)
	layer.add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_quit = root

func _close_quit() -> void:
	if _quit != null:
		_quit.get_parent().queue_free()
		_quit = null

func quit_open() -> bool:
	return _quit != null

# ---------------- focus navigation ----------------

## The screen on top (where keyboard / gamepad focus belongs), or null while playing.
func active_root() -> Control:
	if game == null:
		return null
	if _quit != null:
		return _quit
	var sim: Sim = game.sim
	var meta: MetaUI = game.meta
	if meta.settings_screen.visible:
		return meta.settings_screen
	for n in ["bond_ui", "item_ui"]:
		var c: Variant = game.get(n)
		if c is Control and (c as Control).visible:
			return c
	var sc: Control = game.screens
	if sc != null and sc.is_open():
		return sc
	if sim.state == "playing":
		return null
	var gs: Variant = meta.screens.get("gacha")
	if meta.current == "gacha" and gs is Object:
		var fx: Variant = (gs as Object).get("_fx")          # the pull overlay covers the screen
		if fx is Control and (fx as Control).is_visible_in_tree():
			return fx
	if meta.current != "" and meta.screens.has(meta.current):
		return meta.screens[meta.current]
	return null

func _input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton or ev is InputEventScreenTouch:
		if ev.is_pressed():
			nav = false
		return
	if not (ev is InputEventKey or ev is InputEventJoypadButton or ev is InputEventJoypadMotion):
		return
	if not ev.is_pressed() or ev.is_echo():
		return
	var is_nav := false
	for a in NAV_ACTIONS:
		if ev.is_action_pressed(a, false, true):
			is_nav = true
			break
	var root := active_root()
	if root == null:
		return
	var vp := get_viewport()
	var owner := vp.gui_get_focus_owner()
	var inside := owner != null and owner.is_visible_in_tree() and root.is_ancestor_of(owner)
	if is_nav:
		nav = true
		if not inside:
			var f := first_focusable(root)
			if f != null:
				f.grab_focus()
				vp.set_input_as_handled()
		return
	if inside and ev.is_action_pressed("ui_accept", false, true) and _is_card(owner):
		click(owner)
		vp.set_input_as_handled()
		return
	if ev.is_action_pressed("ui_cancel", false, true) and ev is InputEventJoypadButton:
		# gamepad B: MetaUI handles it in the menus; in-run modals go back like Android back
		if root == game.screens or root == _quit:
			back()
			vp.set_input_as_handled()

func _process(_dt: float) -> void:
	if not nav:
		return
	var root := active_root()
	if root == null:
		return
	var owner := get_viewport().gui_get_focus_owner()
	if owner == null or not owner.is_visible_in_tree() or not root.is_ancestor_of(owner):
		var f := first_focusable(root)
		if f != null:
			f.grab_focus()

## First focusable control of a screen (meta "focus_first" wins), preparing cards on the way.
func first_focusable(root: Control) -> Control:
	var best: Control = null
	for c in root.find_children("*", "Control", true, false):
		var ctl := c as Control
		if not ctl.is_visible_in_tree():
			continue
		_prepare(ctl)
		if ctl.focus_mode != Control.FOCUS_ALL:
			continue
		var bb := ctl as BaseButton
		if bb != null and bb.disabled:
			continue
		if ctl.has_meta("focus_first"):
			return ctl
		if best == null:
			best = ctl
	return best

## Buttons / sliders / selects get keyboard focus; text fields only by click (the d-pad would
## move their caret); clickable cards become focusable with their hover look.
func _prepare(c: Control) -> void:
	var id := c.get_instance_id()
	if _prepared.has(id):
		return
	_prepared[id] = true
	if c is LineEdit or c is TextEdit:
		c.focus_mode = Control.FOCUS_CLICK
	elif c is BaseButton or c is Slider:
		if c.focus_mode == Control.FOCUS_NONE:
			c.focus_mode = Control.FOCUS_ALL
	elif _is_card(c):
		c.focus_mode = Control.FOCUS_ALL
		c.focus_entered.connect(func(): c.mouse_entered.emit())
		c.focus_exited.connect(func(): c.mouse_exited.emit())

static func _is_card(c: Control) -> bool:
	return c is PanelContainer and c.mouse_filter == Control.MOUSE_FILTER_STOP and c.gui_input.get_connections().size() > 0

## A synthetic left click (press + release) at the control's centre, through its gui_input.
static func click(c: Control) -> void:
	for down in [true, false]:
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = down
		mb.position = c.size / 2.0
		mb.global_position = c.get_global_rect().get_center()
		c.gui_input.emit(mb)
