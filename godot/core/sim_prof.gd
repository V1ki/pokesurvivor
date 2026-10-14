class_name SimProf
extends RefCounted
## Optional per-system timer for Sim.update and world_view._draw (tests/bench.gd and the
## "[perf] sim" / "[perf] draw" lines of debug builds). Each call site is guarded by
## `if SimProf.on:` so the cost when off is one static bool read.
## Sections are laps: begin() at the start of a pass, lap(i) after each system adds the time
## since the previous lap to us[i]. Sections that don't run in a frame just stay 0.

enum {
	PLAYER, WORLD, PATHING, SPAWNER, E_GRID, E_AI, E_SEP, E_CULL, GRID, CAST, PROJ, RESOLVE,
	FIELDS, PICKUPS, HAZARDS, EVENTS, FX, MISC,
	D_HAZARDS, D_GFIELDS, D_PICKUPS, D_ENT_LIST, D_ENT_DRAW, D_PROJ, D_AFIELDS, D_FX, D_TEXT,
	COUNT,
}
const NAMES := ["player", "world", "pathing", "spawner", "e_grid", "e_ai", "e_sep", "e_cull", "grid",
	"cast", "proj", "resolve", "fields", "pickups", "hazards", "events", "fx", "misc",
	"d_hazards", "d_gfields", "d_pickups", "d_ent_list", "d_ent_draw", "d_proj", "d_afields", "d_fx", "d_text"]
const FIRST_DRAW := D_HAZARDS

static var on := false
static var us := PackedInt64Array()    # accumulated microseconds per section
static var _t := 0

static func enable(v := true) -> void:
	on = v
	if us.size() != COUNT:
		us.resize(COUNT)
	us.fill(0)

static func begin() -> void:
	_t = Time.get_ticks_usec()

static func lap(i: int) -> void:
	var now := Time.get_ticks_usec()
	us[i] += now - _t
	_t = now

static func reset() -> void:
	us.fill(0)

## "name=ms ..." of the sections in [from, to) averaged over `frames`, and resets them.
static func take(from: int, to: int, frames: int) -> String:
	var parts: PackedStringArray = []
	for i in range(from, to):
		parts.append("%s=%.3f" % [NAMES[i], us[i] / 1000.0 / maxf(1.0, frames)])
		us[i] = 0
	return " ".join(parts)
