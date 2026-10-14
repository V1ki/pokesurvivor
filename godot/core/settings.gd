class_name Settings
extends RefCounted
## Per-device settings (js/core/settings.js + the ps.audio / ps.lang keys), persisted in
## user://settings.cfg (ConfigFile). Nothing is read or written until load_cfg() is called, so
## headless tests keep the defaults (= the JS "high" profile).
##   quality   "auto" | "high" | "mid" | "low"   FX/particle caps (fx = 0..2, auto resolved)
##   dmg_numbers, calm, show_fps, stick (0.8 / 1 / 1.25)
##   music, sfx (0..1), muted       stored for the audio port (Phase 5)
##   lang      "es" | "en" | "zh"  (I18n; default from the OS language, like the browser's in JS)

const PATH := "user://settings.cfg"

static var fx := 2                  # effective quality 0 low / 1 mid / 2 high (FX caps)
static var dmg_numbers := true      # show numeric damage texts
static var calm := false            # fewer shakes / flashes
static var show_fps := false
static var stick := 1.0             # joystick size multiplier (0.8 / 1 / 1.25)
static var quality := "auto"
static var music := 0.55
static var sfx := 0.7
static var muted := false
static var lang := "es"
static var touch_device := false    # auto quality starts at mid on touch devices
static var read_only := false       # debug runs (bots, screenshots): never written
static var lang_chosen := false     # picked in Settings (else the OS language is used, like JS ps.lang)
static var auto_level := 2
static var _loaded := false
static var _acc := 0.0
static var _frames := 0
static var _slow := 0
static var _fast := 0

## Reads user://settings.cfg once (later calls keep the values, e.g. a --lang debug override).
static func load_cfg() -> void:
	if _loaded:
		return
	_loaded = true
	touch_device = DisplayServer.is_touchscreen_available() and OS.has_feature("mobile")
	auto_level = 1 if touch_device else 2
	lang = I18n.os_lang()
	var c := ConfigFile.new()
	if c.load(PATH) == OK:
		quality = str(c.get_value("gfx", "quality", quality))
		dmg_numbers = bool(c.get_value("gfx", "dmgNumbers", dmg_numbers))
		calm = bool(c.get_value("gfx", "calm", calm))
		show_fps = bool(c.get_value("gfx", "fps", show_fps))
		stick = float(c.get_value("controls", "stick", stick))
		music = clampf(float(c.get_value("audio", "music", music)), 0.0, 1.0)
		sfx = clampf(float(c.get_value("audio", "sfx", sfx)), 0.0, 1.0)
		muted = bool(c.get_value("audio", "muted", muted))
		# Phase 4 always wrote "es" (no choice existed): only a language picked in Settings counts
		lang_chosen = bool(c.get_value("general", "lang_chosen", false))
		if lang_chosen:
			lang = str(c.get_value("general", "lang", lang))
	if not quality in ["auto", "high", "mid", "low"]:
		quality = "auto"
	if not stick in [0.8, 1.0, 1.25]:
		stick = 1.0
	if not lang in I18n.LANGS:
		lang = I18n.os_lang()
	_resolve()

static func save_cfg() -> void:
	_resolve()
	if not _loaded or read_only:
		return
	var c := ConfigFile.new()
	c.set_value("gfx", "quality", quality)
	c.set_value("gfx", "dmgNumbers", dmg_numbers)
	c.set_value("gfx", "calm", calm)
	c.set_value("gfx", "fps", show_fps)
	c.set_value("controls", "stick", stick)
	c.set_value("audio", "music", music)
	c.set_value("audio", "sfx", sfx)
	c.set_value("audio", "muted", muted)
	if lang_chosen:
		c.set_value("general", "lang", lang)
		c.set_value("general", "lang_chosen", true)
	c.save(PATH)

static func _resolve() -> void:
	match quality:
		"high": fx = 2
		"mid": fx = 1
		"low": fx = 0
		_: fx = auto_level

## Auto quality (settings.js sample): called every frame while playing. < 45 FPS for 3
## consecutive seconds -> one level down; > 57 FPS for 8 -> one level up (max 1 on touch).
static func sample(dt: float) -> void:
	if quality != "auto" or dt <= 0.0:
		return
	_acc += dt
	_frames += 1
	if _acc < 1.0:
		return
	var f := _frames / _acc
	_acc = 0.0
	_frames = 0
	if f < 45.0:
		_slow += 1
		_fast = 0
	elif f > 57.0:
		_fast += 1
		_slow = 0
	else:
		_slow = 0
		_fast = 0
	if _slow >= 3 and auto_level > 0:
		auto_level -= 1
		_slow = 0
	if _fast >= 8 and auto_level < (1 if touch_device else 2):
		auto_level += 1
		_fast = 0
	_resolve()

## Language picked in Settings: saved and applied at once (Controls re-translate themselves).
static func set_lang(l: String) -> void:
	lang = l if l in I18n.LANGS else "es"
	lang_chosen = true
	I18n.set_lang(lang)
	save_cfg()
