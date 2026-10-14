class_name AndroidDisplay
extends Node
## Android 15+ picks each app's frame rate from per-view votes. Godot's GL render view never
## votes, so the system treats it as "normal" content and runs it at 60 Hz even on a 120 Hz
## panel. This asks for the panel's highest refresh rate on the render view and its Surface,
## through the AndroidRuntime singleton (Godot 4.4+: Java APIs from GDScript). No-op elsewhere.

const ANDROID_R_ID_CONTENT := 16908290        # android.R.id.content
const FRAME_RATE_COMPATIBILITY_FIXED_SOURCE := 1

var _rt: Object = null
var _activity: Object = null
var last_report := ""

func _ready() -> void:
	if OS.get_name() != "Android" or not Engine.has_singleton("AndroidRuntime"):
		return
	_rt = Engine.get_singleton("AndroidRuntime")
	_activity = _rt.getActivity()
	request()

func _notification(what: int) -> void:
	# the Surface is recreated when the app comes back from the background
	if what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		request()

func request() -> void:
	if _activity == null:
		return
	_activity.runOnUiThread(_rt.createRunnableFromGodotCallable(_apply))

func _apply() -> void:
	var hz := _max_refresh()
	var voted := 0
	var root: Object = _activity.findViewById(ANDROID_R_ID_CONTENT)
	if root != null:
		voted = _vote(root, hz, 0)
	last_report = "%.0f Hz requested on %d view(s)" % [hz, voted]
	if OS.is_debug_build():
		print("[display] ", last_report)

func _max_refresh() -> float:
	var best := 60.0
	var display: Object = _activity.getWindowManager().getDefaultDisplay()
	if display == null:
		return best
	for m in display.getSupportedModes():
		best = maxf(best, float(m.getRefreshRate()))
	return best

## Votes on every view of the tree; SurfaceViews (Godot's GL view) also get a Surface vote.
func _vote(view: Object, hz: float, depth: int) -> int:
	var n := 0
	if view.has_java_method("setRequestedFrameRate"):          # API 35+
		view.setRequestedFrameRate(hz)
		n += 1
	if view.has_java_method("getHolder"):
		var surface: Object = view.getHolder().getSurface()
		if surface != null and surface.isValid():
			surface.setFrameRate(hz, FRAME_RATE_COMPATIBILITY_FIXED_SOURCE)
	if depth < 6 and view.has_java_method("getChildCount"):
		for i in view.getChildCount():
			n += _vote(view.getChildAt(i), hz, depth + 1)
	return n
