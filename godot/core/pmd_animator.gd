class_name PmdAnimator
extends RefCounted
## Plays PMD animations (port of the JS Animator, js/core/sprites.js):
##   loop(anim)  background animation (Idle / Walk); not restarted if already playing
##   play(anim)  one-shot (Attack, Shoot, Hurt...) over the background until it ends;
##               hold=true freezes on the last frame (Faint)
## Frame durations are in 1/60 s ticks. Pure data: drawing lives in render/draw_util.gd.

var dex := 0
var shiny := false
var scale := 1.0
var base := "Idle"
var cur := "Idle"
var frame := 0
var t := 0.0
var speed := 1.0
var once := false
var hold := false
var done := false
var dir := 0
var _m: Dictionary = {}          # anim_meta of `cur`
var _d: Array = []               # _m["d"] (frame durations), cached for update()
var _n := 0                      # _m["n"] (frame count)
# geometry of `cur` cached for DrawUtil.pmd: frame size, rows (directions), anchor
var _w := 0.0
var _h := 0.0
var _rows := 1
var _ax := 0.0
var _ay := 0.0
var _ver := 0                    # bumps on every meta change
## DrawUtil.pmd's cache: the READY sheet of `cur` while draw_ver == _ver (no per-frame lookup).
var draw_sheet: Sprites.Sheet = null
var draw_ver := -1

func _init(dex_: int, scale_: float = 1.0, shiny_: bool = false) -> void:
	dex = dex_
	shiny = shiny_ and Sprites.has_shiny(dex_)
	scale = scale_
	_set_meta(Sprites.anim_meta(dex, cur, shiny))

func _set_meta(m: Dictionary) -> void:
	_m = m
	_ver += 1
	if m.is_empty():
		_d = []
		_n = 0
		return
	_d = m["d"]
	_n = int(m["n"])
	_w = float(m["w"])
	_h = float(m["h"])
	_rows = int(m["r"])
	_ax = float(m["ax"])
	_ay = float(m["ay"])

func loop(anim: String, spd := 1.0) -> void:
	base = anim
	if not once and cur != anim:
		_start(anim, false)
	if not once:
		speed = spd

func play(anim: String, spd := 1.0, hold_ := false) -> void:
	_start(anim, true)
	speed = spd if spd != 0.0 else 1.0
	hold = hold_

## Is a one-shot still playing?
func busy() -> bool:
	return once and not done

## 0..1 progress of the current animation.
func progress() -> float:
	if _m.is_empty():
		return 1.0
	var d: Array = _m["d"]
	var total := 0.0
	var before := 0.0
	for i in d.size():
		if i < frame:
			before += d[i]
		total += d[i]
	return (before + t) / total if total > 0.0 else 1.0

## Total length in seconds of an animation (cast speed-up, player.cast).
func length_of(anim: String) -> float:
	var m := Sprites.anim_meta(dex, anim, shiny)
	if m.is_empty():
		return 0.4
	var s := 0.0
	for v in m["d"]:
		s += v
	return s / 60.0

func _start(anim: String, once_: bool) -> void:
	var nm := Sprites.anim_name(dex, anim, shiny)
	cur = nm if nm != "" else "Idle"
	frame = 0
	t = 0.0
	once = once_
	done = false
	_set_meta(Sprites.anim_meta(dex, cur, shiny))

func update(dt: float) -> void:
	if _m.is_empty() or done:
		return
	t += dt * 60.0 * speed
	var d := _d
	var n := _n
	var guard := 0
	while t >= float(d[frame]):
		t -= float(d[frame])
		frame += 1
		if frame >= n:
			if once:
				if hold:
					frame = n - 1
					done = true
					return
				# back to the background animation
				_start(base, false)
				speed = 1.0
				return
			frame = 0
		guard += 1
		if guard > 256:          # zero-length frames would loop forever
			break

func meta() -> Dictionary:
	return _m
