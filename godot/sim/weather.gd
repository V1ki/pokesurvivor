class_name Weather
extends RefCounted
## Rare weather event (port of js/systems/weather.js, §7.10): from minute 2, one check every
## 60 s with an 18% chance, kind weighted by biome % 3, lasting round(rand(55, 75)) s. It scales
## move damage by type (both directions, Combat/Player), slows non-Ice Pokémon in snow and chips
## HP in sand/snow. Visuals: render/weather_layer.gd (tint + particles) and the fog vignette.

const FROM := 120.0
const CHECK := 60.0
const CHANCE := 0.18

var kinds: Dictionary = {}       # key -> {name, icon, color, tint [r,g,b,a], mult {type: k}, safe?, slow?, hint}
var biome_w: Array = []          # BIOME_W: weights per biome % 3
var cur: Dictionary = {}         # {kind, t, dur} or {} when clear
var check_t := CHECK
var chip_t := 0.0
## Random source (Math.random): tests replay the JS draws through it.
var rng: Callable = func() -> float: return randf()
## Tests: biome index and enemy list to use instead of Sim.cur's (-1 / null = Sim.cur).
var biome_override := -1
var enemies_override: Variant = null

func _init() -> void:
	var w := WorldMap.world_json()
	kinds = w.get("weather", {})
	biome_w = w.get("weather_biome_w", [])

func reset() -> void:
	cur = {}
	check_t = CHECK
	chip_t = 0.0

func def() -> Dictionary:
	return kinds[cur["kind"]] if not cur.is_empty() else {}

## Intensity 0..1 (fades in and out over 3 s).
func level() -> float:
	if cur.is_empty():
		return 0.0
	var t: float = cur["t"]
	return minf(1.0, minf(t / 3.0, (float(cur["dur"]) - t) / 3.0))

## Damage multiplier of an attack of this type with the current weather.
func mult(type: String) -> float:
	if cur.is_empty():
		return 1.0
	var m: Dictionary = def()["mult"]
	if not m.has(type) or float(m[type]) == 0.0:
		return 1.0
	return 1.0 + (float(m[type]) - 1.0) * level()

## Does the sand / snow chip hurt a Pokémon of these types?
func hurts(types: Array) -> bool:
	if cur.is_empty():
		return false
	var d := def()
	if not d.has("safe"):
		return false
	for t in types:
		if (d["safe"] as Array).has(t):
			return false
	return true

## Speed factor (snow) for a Pokémon of these types.
func speed_for(types: Array) -> float:
	if cur.is_empty() or not def().get("slow", false) or types.has("ice"):
		return 1.0
	return 1.0 - 0.1 * level()

func start(kind: String, dur: float) -> void:
	cur = {"kind": kind, "t": 0.0, "dur": dur}
	var d: Dictionary = kinds[kind]
	if Sim.cur != null:
		Sim.cur.spawner.say(str(d["name"]) + ": " + str(d["hint"]), 3.4)
	Sfx.play("biome")

## Let it fade out (3 s).
func stop() -> void:
	if not cur.is_empty():
		cur["dur"] = minf(float(cur["dur"]), float(cur["t"]) + 3.0)

## Weather right now (the arena of a rift; not random).
func force(kind: String, dur: float) -> void:
	start(kind, dur)

## Remove at once (leaving the arena).
func clear() -> void:
	cur = {}

func pick(biome: int) -> String:
	var w: Dictionary = biome_w[biome % biome_w.size()]
	var total := 0.0
	for k in w:
		total += float(w[k])
	var r: float = rng.call() * total
	for k in w:
		r -= float(w[k])
		if r <= 0.0:
			return k
	return "rain"

func _in_arena() -> bool:
	if Sim.cur == null:
		return false
	var rift: Variant = Sim.cur.get("rift")       # Phase 3b (sim/rift.gd)
	return rift != null and bool(rift.get("in_arena"))

## pl: the player (duck-typed: dead, hp, max_hp, mon.types, x, y, body_h) or null.
func update(dt: float, time: float, pl) -> void:
	if not cur.is_empty():
		cur["t"] = float(cur["t"]) + dt
		if float(cur["t"]) >= float(cur["dur"]):
			cur = {}
	elif time > FROM and not _in_arena():
		check_t -= dt
		if check_t <= 0.0:
			check_t = CHECK
			if rng.call() < CHANCE:
				var biome := biome_override if biome_override >= 0 else (Sim.cur.world.biome if Sim.cur != null else 0)
				var kind := pick(biome)
				var dur := U.jround(55.0 + rng.call() * 20.0)
				start(kind, dur)
	# sand and snow chip a little HP (never a KO for the player)
	chip_t -= dt
	if chip_t <= 0.0:
		chip_t = 2.0
		if pl != null and not pl.dead and hurts(pl.mon["types"]) and level() > 0.5:
			var d := maxf(1.0, pl.max_hp * 0.012)
			if pl.hp > d + 1.0:
				pl.hp -= d
				if pl is Player:
					pl.dmg_log["weather"] = float(pl.dmg_log.get("weather", 0.0)) + d
				if Sim.cur != null:
					Sim.cur.fx.dmg_text(pl.x, pl.y - pl.body_h - 4.0, "-%d" % U.jroundi(d), Color.html(def()["color"]))
		if not cur.is_empty() and def().has("safe") and level() > 0.5:
			var list: Array = enemies_override if enemies_override != null else (Sim.cur.enemies.list if Sim.cur != null else [])
			for e in list.duplicate():
				if e.dead or e.boss:
					continue
				if not hurts(e.types):
					continue
				e.hp -= e.max_hp * 0.02 + 1.0
				e.flash = 0.05
				if e.hp <= 0.0:
					e.die()

## HUD chip data: {kind, t, dur, left, name, icon, color, ...} or {} (none / faded out).
func current() -> Dictionary:
	if cur.is_empty() or level() <= 0.0:
		return {}
	var o: Dictionary = kinds[cur["kind"]].duplicate()
	o.merge(cur, true)
	o["left"] = maxf(0.0, float(cur["dur"]) - float(cur["t"]))
	return o

## Fog closes the vignette: 0..1.
func vignette() -> float:
	return level() if (not cur.is_empty() and cur["kind"] == "fog") else 0.0

## Weather.mult(type) of the running simulation (1 without one) — Combat, Player.hurt.
static func mult_of(type: String) -> float:
	return Sim.cur.weather.mult(type) if Sim.cur != null else 1.0

## Weather.speedFor(types) of the running simulation (snow) — Player.spd, Enemy movement.
static func speed_of(types: Array) -> float:
	return Sim.cur.weather.speed_for(types) if Sim.cur != null else 1.0
