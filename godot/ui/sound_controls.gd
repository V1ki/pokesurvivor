class_name SoundControls
extends VBoxContainer
## ui.js soundControls(): "Música" and "Efectos" sliders (0-100, applied live; "click" when one is
## released after a change) and "Silenciar todo" / "Activar sonido" (gold while muted). Used by
## Settings › Sonido, the top bar's sound panel and the pause screen (#pause-sound).

signal mute_changed

var _width := 280.0

static func make(width := 280.0) -> SoundControls:
	var s := SoundControls.new()
	s._width = width
	return s

func _ready() -> void:
	add_theme_constant_override("separation", 10)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	render()

func render() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_slider("Música", Settings.music, func(v: float): Settings.music = v)
	_slider("Efectos", Settings.sfx, func(v: float): Settings.sfx = v)
	var mute := UIKit.button("Activar sonido" if Settings.muted else "Silenciar todo", "SmallGold" if Settings.muted else "SmallButton", func():
		Settings.muted = not Settings.muted
		Settings.save_cfg()
		render()
		mute_changed.emit(), "click")
	mute.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	add_child(mute)

## .snd-row: 20 px icon, 64 px label, the range input.
func _slider(label: String, val: float, setter: Callable) -> void:
	var s := HSlider.new()
	s.min_value = 0
	s.max_value = 100
	s.value = roundf(val * 100.0)
	s.custom_minimum_size = Vector2(maxf(120.0, _width - 100.0), 24)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.focus_mode = Control.FOCUS_NONE
	s.value_changed.connect(func(v: float): setter.call(v / 100.0))
	s.drag_ended.connect(func(changed: bool):
		Settings.save_cfg()
		if changed:
			Sfx.play("click"))            # ui.js: range onchange
	var l := UIKit.label(label, 14)
	l.custom_minimum_size = Vector2(64, 0)
	add_child(UIKit.hbox(8, [UIKit.icon("sound", 18), l, s]))
