class_name Presentation
extends RefCounted
## Screen presentation helpers (Phase 5): the UI scale on phones, the compact-layout query
## (css/style.css @media max-height 520px / 400px) and the display safe area.
##
## The web game lays out its HTML in CSS px = Android dp, so on a phone the menus and the HUD
## are physically ~3x bigger than at the 1280x720 base canvas of the port. On mobile the canvas
## is therefore scaled to about one canvas px per dp (rounded to a whole multiple when close,
## so pixel art and the 12 px CJK font stay crisp): the 2640x1216 target phone becomes an
## 880x405 canvas, the same size its web version has. Desktop keeps 1280x720 (canvas_items +
## expand). Debug: --ui-scale=<physical px per canvas px> (e.g. 1.5 for a 1320x608 window =
## the target phone at half resolution).

const BASE := Vector2(1280.0, 720.0)
const MIN_H := 360.0                 # never a canvas shorter than this
const MIN_W := 640.0

static var target := 0.0             # wanted physical px per canvas px (0 = desktop default)
static var scale := 1.0              # current physical px per canvas px

static func setup(win: Window, args: Dictionary) -> void:
	if args.has("ui-scale"):
		target = float(args["ui-scale"])
	elif OS.has_feature("mobile"):
		var d := DisplayServer.screen_get_dpi() / 160.0
		if d > 0.0:
			var r := roundf(d)
			target = r if r >= 1.0 and absf(d - r) / d <= 0.15 else d
	apply(win)
	win.size_changed.connect(func(): apply(win))

static func apply(win: Window) -> void:
	var ws := Vector2(win.size)
	if ws.x <= 0.0 or ws.y <= 0.0:
		return
	var base := minf(ws.x / BASE.x, ws.y / BASE.y)       # canvas_items + expand fit
	var want := base
	if target > 0.0:
		want = minf(target, minf(ws.y / MIN_H, ws.x / MIN_W))
		want = maxf(want, base * 0.5)
	scale = want
	var f := want / base
	if absf(win.content_scale_factor - f) > 0.001:
		win.content_scale_factor = f

## Canvas size (in canvas px) for the window at the current scale.
static func canvas_size(win: Window) -> Vector2:
	return Vector2(win.size) / maxf(0.01, scale)

## Short landscape canvas (phones): the compact layouts of the CSS (max-height: 520px).
static func compact(vp_size: Vector2) -> bool:
	return vp_size.y <= 520.0

## Very short canvas (CSS max-height: 400px).
static func tiny(vp_size: Vector2) -> bool:
	return vp_size.y <= 400.0

## Safe-area insets (notch / cut-outs / gesture bar) in canvas units.
static func safe_insets(vp: Viewport) -> Dictionary:
	var out := {"top": 0.0, "right": 0.0, "bottom": 0.0, "left": 0.0}
	if not OS.has_feature("mobile") or vp == null:
		return out
	var win := DisplayServer.window_get_size()
	var safe := DisplayServer.get_display_safe_area()
	var vs := vp.get_visible_rect().size
	if win.x <= 0 or vs.x <= 0.0 or safe.size.x <= 0:
		return out
	var k := vs.x / float(win.x)
	out["left"] = maxf(0.0, safe.position.x * k)
	out["top"] = maxf(0.0, safe.position.y * k)
	out["right"] = maxf(0.0, (win.x - safe.end.x) * k)
	out["bottom"] = maxf(0.0, (win.y - safe.end.y) * k)
	return out
