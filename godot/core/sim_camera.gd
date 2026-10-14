class_name SimCamera
extends RefCounted
## World view model (port of js/core/camera.js). The simulation uses it (sees(), outer_radius())
## even when nothing is rendered; the Camera2D node just mirrors it.
## VIEW_W world units are always visible horizontally; at least MIN_VIEW_H vertically.

const VIEW_W := 768.0
const MIN_VIEW_H := 420.0

var x := 0.0
var y := 0.0
var scale := 1.0
var w := 768.0
var h := 432.0
var shake := 0.0
var sx := 0.0             # current shake offset
var sy := 0.0
var calm := false         # "less shaking" setting

func _init() -> void:
	resize(1280.0, 720.0)

## Recompute the zoom for a viewport of css_w x css_h (canvas units).
func resize(css_w: float, css_h: float) -> void:
	scale = minf(css_w / VIEW_W, css_h / MIN_VIEW_H)
	w = css_w / scale
	h = css_h / scale

func follow(tx: float, ty: float, dt: float) -> void:
	x = U.damp(x, tx, 9.0, dt)
	y = U.damp(y, ty, 9.0, dt)
	if shake > 0.0:
		shake = maxf(0.0, shake - dt * 2.4)
		var a := shake * 7.0
		sx = U.rand(-a, a)
		sy = U.rand(-a, a)
	else:
		sx = 0.0
		sy = 0.0

func kick(amount: float) -> void:
	if calm or Settings.calm:          # Settings.calm: also when toggled mid-run (pause > Ajustes)
		amount *= 0.25
	shake = minf(1.2, shake + amount)

func left() -> float:
	return x - w / 2.0

func top() -> float:
	return y - h / 2.0

## Is the point inside the view (with a margin)?
func sees(px: float, py: float, pad := 60.0) -> bool:
	var l := x - w / 2.0          # left() / top() inlined (hot: every entity, every frame)
	var t := y - h / 2.0
	return px > l - pad and px < l + w + pad and py > t - pad and py < t + h + pad

## Radius of the circle enclosing the view: spawn ring, bomb radius, biome ring.
func outer_radius() -> float:
	return sqrt(w * w + h * h) / 2.0 + 40.0

func world_to_screen(px: float, py: float) -> Vector2:
	return Vector2((px - left() + sx) * scale, (py - top() + sy) * scale)

## Without the shake offset: the HUD edge arrows (hud.js / events.js project with
## (x - cam.left()) * scale, so they don't jitter with the camera shake).
func world_to_screen_steady(px: float, py: float) -> Vector2:
	return Vector2((px - left()) * scale, (py - top()) * scale)
