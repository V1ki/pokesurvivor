class_name AudioLogic
extends RefCounted
## The rules of js/core/audio.js sfx() without any audio: the per-key MIN_GAP limiter, the
## simultaneous-voice cap and the choice of the pre-rendered variant (assets/audio/manifest.json
## ids, written by tools/render_audio/render.js). Used by AudioMgr; unit-tested in
## tests/audio_tests.gd. Times are in milliseconds of one monotonic clock (JS mixes
## performance.now() for the gaps and ctx.currentTime for the xp combo: both are real time).
##
##   resolve("shot", {"kind": "chain", "type": "fire"}, now)  -> "shot_beam_fire"
##   resolve("xp", {}, now)                                    -> "xp_<combo 0..24>"
##   resolve("burst", {"rarity": 4}, now)                      -> "burst_4"
##   ""  = nothing to play (unknown name, MIN_GAP, voice cap, or a call JS would throw on)

## Minimum gap (ms) between two plays of the same key (audio.js MIN_GAP; shots: per kind).
const MIN_GAP := {"hit": 45, "faint": 60, "xp": 35, "coin": 50, "grass": 70, "shot": 70, "hover": 40, "break": 60}
## JS: `if (voices > 24) return;` before counting one more -> at most 25 voices per window.
const VOICE_CAP := 24
## Each play counts as a voice for 150 ms (setTimeout(() => voices--, 150)).
const VOICE_MS := 150.0
const XP_WINDOW := 0.45 * 1000.0
const XP_MAX := 24
## Every SFX of audio.js (its SFX table).
const NAMES := ["hover", "click", "back", "confirm", "select", "error", "shot", "hit", "faint", "bossDown", "xp",
	"coin", "heal", "levelup", "hurt", "boss", "surge", "shiny", "shinyGet", "break", "chest", "grass", "ball",
	"shake", "burst", "reveal", "rift", "legend", "gameover", "biome", "pause", "buy"]
## SHOT_PITCH types: an unknown type falls back to 600 Hz, which is exactly "normal".
const SHOT_TYPES := ["fire", "water", "electric", "psychic", "grass", "ice", "poison", "ghost", "dragon", "fairy",
	"normal", "fighting", "rock", "ground", "steel", "bug", "dark", "flying"]
## player.js SND: newer move families sound like an older one (trail is never sent by the player).
const SHOT_KIND := {"boomerang": "projectile", "chain": "beam", "mine": "nova", "meteor": "nova", "turret": "buff",
	"dash": "melee", "trail": "aura", "cone": "projectile"}
## Recipes that ignore the type / that use its pitch; any other kind is the projectile recipe.
const SHOT_FIXED := ["melee", "nova"]
const SHOT_TYPED := ["beam", "aura", "buff", "orbit"]

var last: Dictionary = {}              # key -> ms of the last accepted play
var voice_t := PackedFloat64Array()    # start ms of the voices still counted
var xp_combo := 0
var xp_t := -1.0e12
# stats (debug log / tests)
var played := 0
var gap_drops := 0
var cap_drops := 0
var unknown := 0
var max_voices := 0

## Sample id to play now, or "" (see the class doc). Mutates the limiter state like sfx() does:
## a call dropped by MIN_GAP / the cap changes nothing; an accepted one takes a voice even when
## JS would then throw (shot without opts, rarity out of 1..5) and stay silent.
func resolve(name: String, opts: Dictionary, now: float) -> String:
	if not name in NAMES:
		if name != "":
			unknown += 1
		return ""
	var kind := ""
	if name == "shot":
		kind = str(opts.get("kind", ""))
		kind = SHOT_KIND.get(kind, kind)
	var key := ("shot" + kind) if name == "shot" and not opts.is_empty() else name
	if now - float(last.get(key, -1.0e12)) < float(MIN_GAP.get(name, 0)):
		gap_drops += 1
		return ""
	if voices(now) > VOICE_CAP:
		cap_drops += 1
		return ""
	last[key] = now
	voice_t.append(now)
	max_voices = maxi(max_voices, voice_t.size())
	var id := variant(name, opts, kind, now)
	if id != "":
		played += 1
	return id

## Voices still counted at `now` (drops the expired ones).
func voices(now: float) -> int:
	var i := 0
	while i < voice_t.size() and voice_t[i] <= now - VOICE_MS:
		i += 1
	if i > 0:
		voice_t = voice_t.slice(i)
	return voice_t.size()

func variant(name: String, opts: Dictionary, kind: String, now: float) -> String:
	match name:
		"shot":
			if opts.is_empty():
				return ""               # JS: o.type of undefined -> TypeError -> silent
			var t := str(opts.get("type", "normal"))
			if not t in SHOT_TYPES:
				t = "normal"
			if kind in SHOT_FIXED:
				return "shot_" + kind
			if kind in SHOT_TYPED:
				return "shot_%s_%s" % [kind, t]
			return "shot_projectile_" + t
		"xp":
			xp_combo = mini(xp_combo + 1, XP_MAX) if now - xp_t < XP_WINDOW else 0
			xp_t = now
			return "xp_%d" % xp_combo
		"burst", "reveal":
			var r := int(opts.get("rarity", 0))
			if r == 0:
				r = 1                   # (o && o.rarity) || 1
			return "%s_%d" % [name, r] if r >= 1 and r <= 5 else ""
	return name

## Every id resolve() can return (the manifest must have exactly these).
static func all_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for n in NAMES:
		match n:
			"shot":
				for k in SHOT_FIXED:
					out.append("shot_" + k)
				for k in SHOT_TYPED + ["projectile"]:
					for t in SHOT_TYPES:
						out.append("shot_%s_%s" % [k, t])
			"xp":
				for c in XP_MAX + 1:
					out.append("xp_%d" % c)
			"burst", "reveal":
				for r in range(1, 6):
					out.append("%s_%d" % [n, r])
			_:
				out.append(n)
	return out

## Linear ramp of the music bus gains (linearRampToValueAtTime): value at `t` of a ramp from
## `a` at `t0` to `b` at `t0 + dur`.
static func ramp(t: float, t0: float, dur: float, a: float, b: float) -> float:
	if t <= t0:
		return a
	if t >= t0 + dur:
		return b
	return a + (b - a) * (t - t0) / dur

## setTargetAtTime smoothing of the volume buses (tau 0.05 s), one step of `dt`.
static func smooth(cur: float, target: float, dt: float, tau := 0.05) -> float:
	return target + (cur - target) * exp(-dt / tau)
