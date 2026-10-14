class_name MetaPopups
extends Control
## Toasts (G.UI.toast: bottom centre, 2.2 s) and the achievement / mission popup queue
## (progress.js notify/showNext: top centre, 2.8 s each, 0.25 s gap, medal or legend sprite).

var _toast: PanelContainer
var _toast_l: Label
var _toast_t := 0.0
var _toast_age := 0.0
var _queue: Array = []
var _pop: PanelContainer = null
var _pop_t := 0.0
var _gap := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_l = UIKit.label("", 15, UIKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	_toast = UIKit.panel("Toast", _toast_l)
	_toast_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast)
	_toast.visible = false

func toast(msg: String, secs := 2.2) -> void:
	_toast_l.text = msg
	# long messages wrap instead of running off a phone screen
	var w := DrawUtil.text_width(msg, 15, 700)
	_toast_l.custom_minimum_size = Vector2(minf(w + 2.0, size.x - 80.0), 0) if size.x > 0.0 else Vector2.ZERO
	if not _toast.visible:
		_toast_age = 0.0                  # css .toast animation: pop (only when it appears)
	_toast.visible = true
	_toast_t = secs
	_toast.reset_size()

## css @keyframes pop: scale .94 → 1 and opacity 0 → 1 over 0.2 s, ease-out.
static func _pop_in(c: Control, age: float) -> void:
	var k := clampf(age / 0.2, 0.0, 1.0)
	var e := 1.0 - (1.0 - k) * (1.0 - k)
	c.pivot_offset = c.size / 2.0
	c.scale = Vector2.ONE * (0.94 + 0.06 * e)
	c.modulate.a = e

func ach(p: Dictionary) -> void:
	_queue.append(p)

func _process(dt: float) -> void:
	if _toast.visible:
		_toast_t -= dt
		_toast_age += dt
		_toast.position = Vector2((size.x - _toast.size.x) / 2.0, size.y - _toast.size.y - 30.0)
		_pop_in(_toast, _toast_age)
		if _toast_t <= 0.0:
			_toast.visible = false
	if _pop != null:
		_pop_t -= dt
		# css .ach-pop: top 64 px; compact (short phone canvas): bottom 8 px; pops in, hides at once
		_pop.position = Vector2((size.x - _pop.size.x) / 2.0, size.y - _pop.size.y - 8.0 if UIKit.compact else 64.0)
		_pop_in(_pop, 2.8 - _pop_t)
		if _pop_t <= 0.0:
			_pop.queue_free()
			_pop = null
			_gap = 0.25
	elif _gap > 0.0:
		_gap -= dt
	elif not _queue.is_empty():
		_show(_queue.pop_front())

func _show(n: Dictionary) -> void:
	var a: Dictionary = n.get("ach", {})
	var h := UIKit.hbox(10)
	if a.has("dex"):
		h.add_child(PokeView.make(int(a["dex"]), 48, 40, {"px": 1}))
	else:
		h.add_child(UIKit.icon("medal%d" % int(a.get("tier", 2)) if not a.is_empty() else "medal2", 24))
	var v := UIKit.vbox(0)
	v.add_child(UIKit.label(str(n["title"]), 16, UIKit.GOLD))           # .ach-pop b: always gold
	if str(n.get("sub", "")) != "":
		v.add_child(UIKit.label(str(n["sub"]), 13, UIKit.MUTED))
	h.add_child(v)
	_pop = UIKit.panel("", h)
	_pop.add_theme_stylebox_override("panel", UIKit.box_style(12, 6, UIKit.GOLD))      # .ach-pop: gold edge
	_pop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pop)
	_pop.reset_size()
	_pop_t = 2.8
	Sfx.play("legend" if not a.is_empty() else "confirm")

## Queue empty and nothing showing (autoshot harness).
func idle() -> bool:
	return _pop == null and _queue.is_empty()
