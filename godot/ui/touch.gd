class_name TouchInput
extends Control
## Touch controls (js/core/touch.js): a floating joystick that appears wherever a finger goes
## down (not on a HUD button; first finger owns it; the base follows the finger beyond the
## radius; size from Settings.stick) plus tappable HUD buttons registered every frame by the
## HUD (move slots, pause; hit areas padded like G.Touch.addButton). Desktop mouse clicks press
## the same buttons.

const DEAD := 7.0

var game                           # main.gd (untyped: dynamic state queries)
var active := false                # touch UI mode (pause button, safe areas)
var buttons: Array = []            # [{rect: Rect2, pad: float, fn: Callable}]
var stick: Dictionary = {}         # {id, ox, oy, x, y}
var _last_key := ""
var _last_at := 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	active = OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")

func radius() -> float:
	return 56.0 * Settings.stick

func clear_buttons() -> void:
	buttons.clear()

func add_button(r: Rect2, fn: Callable, pad := 6.0) -> void:
	buttons.append({"rect": r, "pad": pad, "fn": fn})

func _hit(p: Vector2) -> Variant:
	for i in range(buttons.size() - 1, -1, -1):
		var b: Dictionary = buttons[i]
		if (b["rect"] as Rect2).grow(b["pad"]).has_point(p):
			return b
	return null

## De-dupe: the same button within 350 ms presses once.
func _press(b: Dictionary) -> void:
	var r: Rect2 = b["rect"]
	var k := "%d,%d" % [int(r.position.x), int(r.position.y)]
	var now := Time.get_ticks_msec()
	if k == _last_key and now - _last_at < 350:
		return
	_last_key = k
	_last_at = now
	(b["fn"] as Callable).call()

func reset() -> void:
	stick = {}

## Joystick vector (strength 0..1), ZERO when idle.
func vector() -> Vector2:
	if stick.is_empty():
		return Vector2.ZERO
	var dx: float = stick["x"] - stick["ox"]
	var dy: float = stick["y"] - stick["oy"]
	var d := sqrt(dx * dx + dy * dy)
	if d < DEAD:
		return Vector2.ZERO
	# full speed from half the radius on
	var k := minf(1.0, (d - DEAD) / (radius() * 0.5 - DEAD))
	return Vector2(dx / d * k, dy / d * k)

func _playing() -> bool:
	return game != null and game.sim != null and game.sim.state == "playing"

func _input(event: InputEvent) -> void:
	# only while playing: modal screens (level-up, pause, results) get the events instead
	if not _playing():
		if not stick.is_empty():
			stick = {}
		if event is InputEventScreenTouch and not active:
			active = true
		return
	if event is InputEventScreenTouch:
		var t: InputEventScreenTouch = event
		if t.pressed:
			if not active:
				active = true
			var b: Variant = _hit(t.position)
			if b != null:
				_press(b)
				get_viewport().set_input_as_handled()
				return
			if stick.is_empty() and _playing():
				stick = {"id": t.index, "ox": t.position.x, "oy": t.position.y, "x": t.position.x, "y": t.position.y}
				get_viewport().set_input_as_handled()
		else:
			if not stick.is_empty() and t.index == stick["id"]:
				stick = {}
	elif event is InputEventScreenDrag:
		var d: InputEventScreenDrag = event
		if stick.is_empty() or d.index != stick["id"]:
			return
		stick["x"] = d.position.x
		stick["y"] = d.position.y
		var dx: float = stick["x"] - stick["ox"]
		var dy: float = stick["y"] - stick["oy"]
		var dist := sqrt(dx * dx + dy * dy)
		var r := radius()
		if dist > r:
			stick["ox"] = stick["x"] - dx / dist * r
			stick["oy"] = stick["y"] - dy / dist * r
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		# touches also arrive as emulated mouse events: those are handled above
		if mb.device == InputEvent.DEVICE_ID_EMULATION or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
			return
		var b: Variant = _hit(mb.position)
		if b != null:
			_press(b)
			get_viewport().set_input_as_handled()

## Safe-area insets in canvas units (notches / cut-outs / gesture bar on phones).
func safe_area() -> Dictionary:
	return Presentation.safe_insets(get_viewport())

func _process(_delta: float) -> void:
	if not stick.is_empty() and not _playing():
		stick = {}
	queue_redraw()

func _draw() -> void:
	_draw_stick()
	# game.js draws the full-screen flash after the HUD and the joystick (it covers both)
	var sim: Variant = game.get("sim") if game != null else null
	if sim is Sim and (sim as Sim).state != "ui":
		var vs := get_viewport_rect().size
		EventHud.draw_flash(self, sim, vs.x, vs.y)

func _draw_stick() -> void:
	if stick.is_empty():
		return
	var r := radius()
	var dx: float = stick["x"] - stick["ox"]
	var dy: float = stick["y"] - stick["oy"]
	var d := sqrt(dx * dx + dy * dy)
	var kx: float = stick["ox"] + (dx / d * r if d > r else dx)
	var ky: float = stick["oy"] + (dy / d * r if d > r else dy)
	var o := Vector2(stick["ox"], stick["oy"])
	draw_circle(o, r, Color(10 / 255.0, 20 / 255.0, 48 / 255.0, 0.55 * 0.5))
	draw_arc(o, r, 0.0, TAU, 48, Color(Color.html("#f4f8ff"), 0.5), 3.0, true)
	draw_circle(Vector2(kx, ky), r * 0.42, Color(Color.html("#ffd23f"), 0.85))
	draw_arc(Vector2(kx, ky), r * 0.42, 0.0, TAU, 32, Color(Color.html("#a55f00"), 0.85), 3.0, true)
