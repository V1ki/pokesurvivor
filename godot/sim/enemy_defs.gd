class_name EnemyDefs
extends RefCounted
## Wild Pokémon definitions (js/data/enemies.js): BST tiers unlocked by run time, the
## deterministic behavior per species, per-species defs, the per-run cast, bosses and the
## time-scaling curves. Pure functions are static; the rolled cast lives on the instance.

const PLAIN := ["chase", "charger", "ranged", "tank"]
const SUPPORT := ["healer", "shielder", "summoner"]
const LATE_FROM := 60.0
const LATE_K := 0.000374

## Phase 1: only species whose sprite sheets are in this build (tools/sync_sprites.js).
static var restrict_to_available := true

static var _heal: Dictionary = {}
static var _shield: Dictionary = {}
static var _bomb: Dictionary = {}
static var _summon: Dictionary = {}

var cast: Array = []         # [{from, list: [def]}]
var bosses: Array = []       # the 5 boss defs of this run (spawned by the Spawner at `at` s)

static func _sets() -> void:
	if not _summon.is_empty():
		return
	for d in Data.enemies["heal"]:
		_heal[int(d)] = true
	for d in Data.enemies["shield"]:
		_shield[int(d)] = true
	for d in Data.enemies["bomb"]:
		_bomb[int(d)] = true
	for k in Data.enemies["summon"]:
		_summon[int(k)] = int(Data.enemies["summon"][k])

static func tiers() -> Array:
	return Data.enemies["tiers"]

## Approximate base stats from the game stats (inverse of tools/fetch_pokedex.py).
static func base_hp(p: Dictionary) -> float:
	return (float(p["hp"]) - 70.0) / 0.45

static func base_spd(p: Dictionary) -> float:
	return (float(p["spd"]) - 78.0) / 0.42

static func _has_any(types: Array, xs: Array) -> bool:
	for t in xs:
		if types.has(t):
			return true
	return false

## Deterministic personality: h = hash(dex, 7, 11); first matching rule wins.
static func behavior_of(p: Dictionary) -> String:
	_sets()
	var d: int = p["dex"]
	var t: Array = p["types"]
	var h := U.hash01(d, 7, 11)
	if _heal.has(d):
		return "healer"
	if _shield.has(d):
		return "shielder"
	if _bomb.has(d):
		return "bomber"
	if _summon.has(d) and Data.meta_by.has(_summon[d]):
		return "summoner"
	if _has_any(t, ["bug"]) and h >= 0.6 and h < 0.78:
		return "summoner"
	if _has_any(t, ["electric", "psychic", "dragon", "ice"]) and h < 0.18:
		return "beamer"
	if _has_any(t, ["fire", "ground", "poison"]) and h < 0.18:
		return "zoner"
	if _has_any(t, ["water", "grass", "bug", "fairy"]) and h >= 0.18 and h < 0.32:
		return "fan"
	if _has_any(t, ["fighting", "ground", "normal", "rock"]) and h >= 0.42 and h < 0.56:
		return "jumper"
	if _has_any(t, ["psychic", "electric", "ghost", "fairy"]) and h < 0.4:
		return "ranged"
	if _has_any(t, ["fire", "water", "poison", "ice"]) and h < 0.22:
		return "ranged"
	if _has_any(t, ["fighting", "normal", "ground", "rock", "dragon", "steel", "dark"]) and h < 0.4:
		return "charger"
	if base_hp(p) > 95.0 and base_spd(p) < 50.0:
		return "tank"
	return "chase"

## Enemy definition of a Pokémon for a tier (index ti).
static func def_for(p: Dictionary, tier: Dictionary, ti: int) -> Dictionary:
	_sets()
	var hp_k := U.clampf_(base_hp(p) / 65.0, 0.7, 1.6)
	var spd_k := U.clampf_(0.75 + base_spd(p) / 260.0, 0.75, 1.3)
	var beh := behavior_of(p)
	var tank := beh == "tank"
	var d := {
		"dex": int(p["dex"]), "name": p["name"], "behavior": beh,
		"hp": U.jround(float(tier["hp"]) * hp_k * (1.5 if tank else 1.0)),
		"spd": U.jround(float(tier["spd"]) * spd_k * (0.7 if tank else 1.0)),
		"dmg": U.jround(float(tier["dmg"]) * (1.2 if tank else 1.0)),
		"xp": maxf(3.0, U.jround(float(tier["xp"]) * (1.3 if tank else 1.0))),
	}
	var cd := {"ranged": 2.2 - ti * 0.15, "fan": 3.2 - ti * 0.15, "beamer": 4.4 - ti * 0.2,
		"zoner": 4.6 - ti * 0.2, "healer": 3.5, "summoner": 7.0}
	if cd.has(beh):
		d["shotDmg"] = U.jround(float(tier["dmg"]) * (0.7 if beh == "fan" else 0.8))
		d["shotCd"] = U.round2(cd[beh])
		var rng := 260.0 if beh == "beamer" else (230.0 if beh == "healer" or beh == "summoner" else 190.0)
		d["range"] = rng + ti * 6
	if beh == "summoner" and _summon.has(int(p["dex"])):
		d["minion"] = _summon[int(p["dex"])]
	if beh == "fan":
		d["fanN"] = 3 if ti < 2 else 5
	if beh == "zoner":
		d["zones"] = 1 if ti < 2 else (2 if ti < 4 else 3)
	if beh == "bomber":
		d["spd"] = U.jround(d["spd"] * 1.25)
		d["hp"] = U.jround(d["hp"] * 0.8)
	return d

## All candidates of a tier (no legendaries/mythicals), unfiltered.
static func candidates_all(tier: Dictionary) -> Array:
	var out: Array = []
	var lo: float = tier["bst"][0]
	var hi: float = tier["bst"][1]
	for p in Data.dex:
		if float(p["rarity"]) < 5.0 and float(p["bst"]) >= lo and float(p["bst"]) <= hi and Data.meta_by.has(p["dex"]):
			out.append(p)
	return out

## Candidates restricted to species with sprites present (Phase 1 subset).
static func candidates(tier: Dictionary) -> Array:
	var all := candidates_all(tier)
	if not restrict_to_available:
		return all
	var out := all.filter(func(p): return Sprites.available(p["dex"]))
	return out if not out.is_empty() else all

# ---------------- run cast ----------------

## One support (healer/shielder/summoner) per tier and, from the 2nd tier, one telegraphed
## attacker; tier 0 is otherwise only PLAIN behaviors.
static func cast_for(tier: Dictionary) -> Array:
	var all := candidates(tier)
	var kind := {}
	for p in all:
		kind[p["dex"]] = behavior_of(p)
	var kinds: Array = []
	for k in SUPPORT:
		for p in all:
			if kind[p["dex"]] == k:
				kinds.append(k)
				break
	var pick: Array = []
	if not kinds.is_empty():
		var sk: String = kinds[randi() % kinds.size()]
		pick = U.pick_n(all.filter(func(p): return kind[p["dex"]] == sk), 1)
	var n: int = int(tier["cast"])
	if float(tier["from"]) > 0.0:
		pick.append_array(U.pick_n(all.filter(func(p): return not PLAIN.has(kind[p["dex"]]) and not SUPPORT.has(kind[p["dex"]])), 1))
	var rest: Array
	if float(tier["from"]) == 0.0:
		rest = all.filter(func(p): return not pick.has(p) and PLAIN.has(kind[p["dex"]]))
	else:
		rest = all.filter(func(p): return not pick.has(p))
	return pick + U.pick_n(rest, n - pick.size())

## Rolls the cast of a new run (and the 5 boss slots).
func roll_run() -> void:
	cast = []
	var ts := tiers()
	for ti in ts.size():
		var tier: Dictionary = ts[ti]
		var lst: Array = []
		for p in cast_for(tier):
			lst.append(def_for(p, tier, ti))
		cast.append({"from": float(tier["from"]), "list": lst})
	# the fastest chase/charger/tank of each tier becomes the runner
	for tier in cast:
		var best: Dictionary = {}
		for d in tier["list"]:
			if d["behavior"] == "chase" or d["behavior"] == "charger" or d["behavior"] == "tank":
				if best.is_empty() or float(d["spd"]) > float(best["spd"]):
					best = d
		if not best.is_empty():
			best["behavior"] = "runner"
			best["spd"] = U.jround(float(best["spd"]) * 1.6)
			best["hp"] = U.jround(float(best["hp"]) * 0.7)
	# the 5 boss slots: non-legendary, not repeated, BST in the slot's range
	bosses = []
	var used := {}
	for slot in Data.enemies["boss_slots"]:
		var pool := boss_pool(slot, used)
		var bp: Dictionary = U.pick(pool)
		used[bp["dex"]] = true
		bosses.append(boss_def(slot, bp))

## Boss candidates of a slot (fallback BST >= 580). Phase-1 sprite subset: species with sheets.
static func boss_pool(slot: Dictionary, used: Dictionary) -> Array:
	var ok := func(p: Dictionary) -> bool:
		return not p.get("leg", false) and Data.meta_by.has(p["dex"]) and not used.has(p["dex"]) \
			and (not restrict_to_available or Sprites.available(p["dex"]))
	var pool: Array = Data.dex.filter(func(p): return ok.call(p) and float(p["bst"]) >= float(slot["bst"][0]) and float(p["bst"]) <= float(slot["bst"][1]))
	if pool.is_empty():
		pool = Data.dex.filter(func(p): return ok.call(p) and float(p["bst"]) >= 580.0)
	if pool.is_empty():
		# tiny sprite subsets: any non-legendary with sheets
		pool = Data.dex.filter(func(p): return ok.call(p))
	return pool

## Boss def of species p in a slot (x1.35 HP and x1.2 damage over the slot values).
static func boss_def(slot: Dictionary, bp: Dictionary) -> Dictionary:
	var bs := base_spd(bp)
	return {
		"at": float(slot["at"]), "dex": int(bp["dex"]), "name": bp["name"],
		"hp": U.jround(float(slot["hp"]) * 1.35), "spd": U.jround(U.clampf_(40.0 + bs * 0.5, 40.0, 100.0)),
		"dmg": U.jround(float(slot["dmg"]) * 1.2), "xp": float(slot["xp"]),
		"behavior": "ranged" if behavior_of(bp) == "ranged" else ("charger" if bs > 90.0 else "chase"),
		"shotDmg": U.jround(float(slot["dmg"]) * 0.55), "shotCd": 1.1, "range": 260.0,
	}

# ---------------- time scaling ----------------

## Overtime after minute 60: HP (and less so damage) grows faster and faster.
static func late(t: float) -> float:
	var m := maxf(0.0, t / 60.0 - LATE_FROM)
	return exp(minf(30.0, LATE_K * m * m))

static func scale(t: float) -> Dictionary:
	var k := late(t)
	return {"hp": (1.0 + t / 95.0) * k, "dmg": (1.0 + t / 420.0) * pow(k, 0.7), "spd": 1.0 + minf(0.35, t / 1400.0)}

static func boss_scale(t: float) -> Dictionary:
	var k := late(t)
	return {"hp": (1.0 + t / 600.0) * k, "dmg": (1.0 + t / 600.0) * pow(k, 0.7), "spd": 1.0}

## Tier index for run time t.
static func tier_at(t: float) -> int:
	var ti := 0
	var ts := tiers()
	for i in ts.size():
		if t >= float(ts[i]["from"]):
			ti = i
	return ti

# ---------------- hordes (sim/events.gd) ----------------

const NO_HORDE := ["bomber", "healer", "shielder", "summoner"]

## Types with at least 3 non-support candidates in the current tier (JS order of TYPE_COLOR).
static func horde_types(t: float) -> Array:
	var all := candidates(tiers()[tier_at(t)]).filter(func(p): return not NO_HORDE.has(behavior_of(p)))
	var out: Array = []
	for ty in Data.type_order:
		var n := 0
		for p in all:
			if (p["types"] as Array).has(ty):
				n += 1
		if n >= 3:
			out.append(ty)
	return out

## Up to 4 Pokémon of one type with the current tier's stats (rng: a StreamRng or null).
static func horde_defs(type: String, t: float, rng: StreamRng = null) -> Array:
	var ti := tier_at(t)
	var tier: Dictionary = tiers()[ti]
	var pool := candidates(tier).filter(func(p): return (p["types"] as Array).has(type) and not NO_HORDE.has(behavior_of(p)))
	var picked := rng.pick_n(pool, 4) if rng != null else U.pick_n(pool, 4)
	return picked.map(func(p): return def_for(p, tier, ti))

## Spawn bag at time t: each unlocked tier's cast, old tiers (> 260 s) weigh 3 instead of 10.
func bag_at(t: float) -> Array:
	if cast.is_empty():
		roll_run()
	var bag: Array = []
	for tier in cast:
		if t < float(tier["from"]):
			continue
		var w := 3 if t - float(tier["from"]) > 260.0 else 10
		for e in tier["list"]:
			for i in w:
				bag.append(e)
	return bag if not bag.is_empty() else cast[0]["list"]

## Dexes of the cast (and bosses) due within `ahead` s (sprite preloading).
func upcoming_dex(t: float, ahead := 60.0) -> Array:
	if cast.is_empty():
		roll_run()
	var out: Array = []
	for tier in cast:
		if float(tier["from"]) <= t + ahead:
			for e in tier["list"]:
				out.append(e["dex"])
	for b in bosses:
		if float(b["at"]) <= t + ahead:
			out.append(b["dex"])
	return out
