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

## "level" (the game's since 2026-10-15, js/data/enemies.js MODE): every wild Pokémon has a level
## that grows with the run time, and its stats come from its base stats and that level with the
## main games' formulas; a form appears from the level it evolves at (Charmeleon from 16) and one
## that would have evolved leaves LV.linger levels later. See the "wild levels" section.
## "tier" (the previous model, kept for the parity tests and tests/sim_play.gd --enemies=tier):
## stats from the tier template of the run time × the time curves (scale, Spawner.hp_k).
static var mode := "level"

## Every number of the level mode (= js/data/enemies.js LV_DEFAULTS, exported to data/enemies.json
## "levels" and checked by tests/level_tests.gd); set_mode(mode, "k=v,k=v") overrides them. These are the ones
## the playtests picked (2026-10-15, variant "M11": new players last longer and die less all at
## once than with the tiers, fully upgraded ones about as long): Lv 3 at 0:00, 15 at 3:00, 27 at
## 6:00, then faster and faster (51 at 10:00, 104 at 15:00).
const LV_DEFAULTS := {
	"lv0": 3.0,          # wild level at 0:00
	"lv_min": 4.0,       # + levels per minute
	"lv_acc": 0.5,       # + levels per minute squared (the climb speeds up)...
	"acc_from": 6.0,     #   ...counting the minutes from this one (before it, only lv_min)
	"spread": 2.0,       # each one is ± up to this many levels off
	"hp_k": 2.8,         # in-game HP = hp_k × the games' HP stat
	"dmg_k": 5.4,        # contact damage = dmg_k × the games' level factor (dmg_lv·Lv + 2) × its attack
	                     #   (Attack or Sp. Atk) over an average one (dmg_of)
	"dmg_lv": 0.2,       # 2/5 in the games' damage formula; lower = damage climbs slower with level
	"grow": 0.03,        # extra HP per level above lv0, compounded (0.03 = ×1.03 each level)
	"xp0": 3.4,          # XP per kill: xp0 + xp_lv × level (then × Spawner.XP_K): about the tiers' XP
	"xp_lv": 0.17,
	"bands": [1.0, 12.0, 22.0, 32.0, 42.0, 52.0],   # cast groups by the level a form appears from
	"linger": 15.0,      # a form that evolves keeps appearing up to its evolution level + this
	"gate": 1.0,         # 1: each form waits for its own evolution level · 0: only its group's start
	"boss_lv": 8.0,      # bosses: wild level + this,
	"boss_hp": 5.0,      #   HP × this over a wild one of that species and level,
	"boss_dmg": 0.8,     #   damage ×
	"cap": 0.0,          # highest wild level (0 = none)
}
static var LV: Dictionary = LV_DEFAULTS.duplicate(true)
static var _lv_tiers: Array = []
static var _appear: Dictionary = {}       # dex -> [appears from, leaves after] (wild levels)

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
	if mode == "level":
		return _level_tiers()
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
	if tier.has("lv"):
		# level mode: what the stats come from; Spawner.make_enemy works them out at its level
		d["bhp"] = base_hp(p)
		d["batk"] = base_atk(p)
		d["spd_k"] = spd_k
		d["hp_m"] = (1.5 if tank else 1.0) * (0.8 if beh == "bomber" else 1.0)
		d["dmg_m"] = 1.2 if tank else 1.0
		d["spd_m"] = (0.7 if tank else 1.0) * (1.25 if beh == "bomber" else 1.0)
		d["xp_m"] = 1.3 if tank else 1.0
		d["shot_m"] = 0.7 if beh == "fan" else 0.8
		d["appear"] = appear_level(int(p["dex"]))
		d["leave"] = leave_level(int(p["dex"]))
		return at_level(d, float(tier["lv"][0]))
	return d

## All candidates of a tier (no legendaries/mythicals), unfiltered.
static func candidates_all(tier: Dictionary) -> Array:
	var out: Array = []
	if tier.has("lv"):
		for p in Data.dex:
			var a := appear_level(int(p["dex"]))
			if float(p["rarity"]) < 5.0 and a >= float(tier["lv"][0]) and a < float(tier["lv"][1]) and Data.meta_by.has(p["dex"]):
				out.append(p)
		return out
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
			if best.has("hp_m"):
				best["spd_m"] = float(best["spd_m"]) * 1.6
				best["hp_m"] = float(best["hp_m"]) * 0.7
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
	if mode == "level":
		var b := {"at": float(slot["at"]), "dex": int(bp["dex"]), "name": bp["name"],
			"bhp": base_hp(bp), "batk": base_atk(bp), "xp": float(slot["xp"]),
			"spd": U.jround(U.clampf_(40.0 + bs * 0.5, 40.0, 100.0)),
			"behavior": "ranged" if behavior_of(bp) == "ranged" else ("charger" if bs > 90.0 else "chase"),
			"shotCd": 1.1, "range": 260.0}
		return boss_at_level(b, wild_level(float(slot["at"])) + float(LV["boss_lv"]))
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

## Level mode: only the forms that can already appear at this wild level.
static func wild_ok(p: Dictionary, t: float) -> bool:
	return mode != "level" or float(LV["gate"]) <= 0.0 or appear_level(int(p["dex"])) <= wild_level(t)

## Types with at least 3 non-support candidates in the current tier (JS order of TYPE_COLOR).
static func horde_types(t: float) -> Array:
	var all := candidates(tiers()[tier_at(t)]).filter(func(p): return not NO_HORDE.has(behavior_of(p)) and wild_ok(p, t))
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
	var pool := candidates(tier).filter(func(p): return (p["types"] as Array).has(type) and not NO_HORDE.has(behavior_of(p)) and wild_ok(p, t))
	var picked := rng.pick_n(pool, 4) if rng != null else U.pick_n(pool, 4)
	return picked.map(func(p): return def_for(p, tier, ti))

## Spawn bag at time t: each unlocked tier's cast, old tiers (> 260 s) weigh 3 instead of 10.
func bag_at(t: float) -> Array:
	if cast.is_empty():
		roll_run()
	var bag: Array = []
	var wl := wild_level(t)
	var last: Array = cast[0]["list"]
	for tier in cast:
		if t < float(tier["from"]):
			continue
		last = tier["list"]
		var w := 3 if t - float(tier["from"]) > 260.0 else 10
		for e in tier["list"]:
			# level mode: a form it hasn't evolved into yet, or one that would have evolved by now
			if e.has("appear") and ((float(LV["gate"]) > 0.0 and wl < float(e["appear"])) or wl > float(e["leave"])):
				continue
			for i in w:
				bag.append(e)
	return bag if not bag.is_empty() else last

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

# ---------------- wild levels (mode "level") ----------------

## Picks the model ("tier" / "level") and the level numbers ("lv0=2,lv_min=4,bands=1/10/20").
## Returns the keys it did not know.
static func set_mode(m: String, text := "") -> Array:
	mode = m
	LV = LV_DEFAULTS.duplicate(true)
	_lv_tiers = []
	var bad: Array = []
	for kv in text.split(",", false):
		var p := kv.split("=", true, 1)
		if p.size() < 2 or not LV.has(p[0]):
			bad.append(kv)
		elif "/" in p[1]:
			LV[p[0]] = Array(p[1].split("/")).map(func(x): return float(x))
		else:
			LV[p[0]] = float(p[1])
	return bad

## Wild level at run time t (not rounded): lv0 + lv_min·m + lv_acc·(m - acc_from)², m in minutes
## (the last part only after acc_from).
static func wild_level(t: float) -> float:
	var m := t / 60.0
	var u := maxf(0.0, m - float(LV["acc_from"]))
	var l := float(LV["lv0"]) + float(LV["lv_min"]) * m + float(LV["lv_acc"]) * u * u
	return minf(l, float(LV["cap"])) if float(LV["cap"]) > 0.0 else l

## When the wild level reaches l (s); 0 for levels it starts at or above.
static func time_of_level(l: float) -> float:
	var a := float(LV["lv_acc"])
	var b := float(LV["lv_min"])
	var f := float(LV["acc_from"])
	var c := float(LV["lv0"]) - l
	if c >= 0.0:
		return 0.0
	# before acc_from (or with no acceleration) it climbs lv_min a minute
	if a <= 0.0 or float(LV["lv0"]) + b * f >= l:
		return -c / maxf(b, 0.001) * 60.0
	# after: a·u² + b·u + (lv0 + b·f - l) = 0, u = minutes past acc_from
	var c2 := float(LV["lv0"]) + b * f - l
	return (f + (-b + sqrt(b * b - 4.0 * a * c2)) / (2.0 * a)) * 60.0

## Level of one that appears now: the wild level ± spread (whole levels, at least 1).
static func spawn_level(t: float) -> int:
	var s := int(LV["spread"])
	var l := int(floorf(wild_level(t)))
	if s > 0:
		l += randi() % (2 * s + 1) - s
	return maxi(1, l)

## The main games' stat formula (IV 31, no EVs, neutral nature).
static func hp_stat(b: float, l: float) -> float:
	return (2.0 * b + 31.0) * l / 100.0 + l + 10.0

static func stat(b: float, l: float) -> float:
	return (2.0 * b + 31.0) * l / 100.0 + 5.0

## Damage like the games' formula: the attacker's level factor (2·Lv/5 + 2, dmg_lv = 2/5) times
## its attack stat over an average one (base 75: (2·75+31) = 181), scaled so that level 3 hits
## about the same whatever dmg_lv is. Defense left out: it's the player's upgrades.
static func dmg_of(batk: float, l: float) -> float:
	var k := float(LV["dmg_lv"])
	return (k * l + 2.0) * (3.2 / (k * 3.0 + 2.0)) * (2.0 * batk + 31.0) / 181.0

## Approximate higher of base Attack / Sp. Atk (inverse of tools/fetch_pokedex.py).
static func base_atk(p: Dictionary) -> float:
	return (float(p["atk"]) - 0.70) / 0.55 * 100.0

## A level-mode def with its stats at level l (hp, dmg, spd, xp, shotDmg).
static func at_level(d: Dictionary, l: float) -> Dictionary:
	var o := d.duplicate()
	var lv := maxf(1.0, l)
	var grow := pow(1.0 + float(LV["grow"]), maxf(0.0, lv - float(LV["lv0"])))
	o["level"] = int(lv)
	o["hp"] = maxf(1.0, U.jround(float(LV["hp_k"]) * hp_stat(float(d["bhp"]), lv) * float(d["hp_m"]) * grow))
	o["dmg"] = U.round2(float(LV["dmg_k"]) * dmg_of(float(d["batk"]), lv) * float(d["dmg_m"]))
	o["spd"] = U.jround((56.0 + minf(16.0, lv * 0.3)) * float(d["spd_k"]) * float(d["spd_m"]))
	o["xp"] = maxf(3.0, U.jround((float(LV["xp0"]) + float(LV["xp_lv"]) * lv) * float(d["xp_m"])))
	if d.has("shotDmg"):
		o["shotDmg"] = U.round2(float(o["dmg"]) * float(d["shot_m"]) / float(d["dmg_m"]))
	return o

## A level-mode boss at level l: boss_hp × the HP of a wild one of that species and level.
static func boss_at_level(b: Dictionary, l: float) -> Dictionary:
	var o := b.duplicate()
	var lv := maxf(1.0, l)
	var grow := pow(1.0 + float(LV["grow"]), maxf(0.0, lv - float(LV["lv0"])))
	o["level"] = int(lv)
	o["hp"] = U.jround(float(LV["hp_k"]) * hp_stat(float(b["bhp"]), lv) * float(LV["boss_hp"]) * grow)
	o["dmg"] = U.round2(float(LV["dmg_k"]) * dmg_of(float(b["batk"]), lv) * float(LV["boss_dmg"]))
	o["shotDmg"] = U.round2(float(o["dmg"]) * 0.46)
	return o

## The level a species appears from in the wild: an evolved form from its evolution level
## (Families.req_level: the games' one, or estimated from its base stats); a first form that
## evolves from 1; one that doesn't evolve at all, the level of evolved forms with similar base
## stats. Leaves after its next form's level + linger (never, for a last form).
static func appear_level(dex: int) -> float:
	_appear_data()
	return float(_appear.get(dex, [1.0, 999.0])[0])

static func leave_level(dex: int) -> float:
	_appear_data()
	return float(_appear.get(dex, [1.0, 999.0])[1]) + (float(LV["linger"]) if float(_appear.get(dex, [1.0, 999.0])[1]) < 999.0 else 0.0)

static func _appear_data() -> void:
	if not _appear.is_empty():
		return
	Families._data()
	var evo: Dictionary = Families._evo
	# base stat total -> level, fitted on the level evolutions (like tools/fetch_evolutions.py)
	var n := 0.0
	var sx := 0.0
	var sy := 0.0
	var sxx := 0.0
	var sxy := 0.0
	for k in evo:
		var lv := int((evo[k].get("how", {}) as Dictionary).get("lv", 0))
		if lv > 0 and Data.dex_by.has(int(k)):
			var x := float(Data.dex_by[int(k)]["bst"])
			n += 1.0
			sx += x
			sy += lv
			sxx += x * x
			sxy += x * lv
	var b1 := (n * sxy - sx * sy) / (n * sxx - sx * sx)
	var b0 := (sy - b1 * sx) / n
	for p in Data.dex:
		var d := int(p["dex"])
		var e: Dictionary = evo.get(str(d), {})
		var h: Dictionary = e.get("how", {})
		var from := 1.0
		if int(h.get("lv", 0)) > 0 or int(h.get("est", 0)) > 0:
			from = minf(60.0, float(h.get("lv", 0) if int(h.get("lv", 0)) > 0 else h.get("est", 0)))
		elif Families.members(Families.fam_of(d)).size() <= 1:
			from = clampf(roundf(b0 + b1 * float(p["bst"])), 1.0, 60.0)
		var nxt := 999.0
		for c in Families.members(Families.fam_of(d)):
			var ce: Dictionary = evo.get(str(c), {})
			if int(ce.get("from", 0)) == d:
				nxt = minf(nxt, float(Families.req_level(c)))
		_appear[d] = [from, nxt]

## The cast groups of the level mode: one per band, from when the wild level reaches it.
static func _level_tiers() -> Array:
	if not _lv_tiers.is_empty():
		return _lv_tiers
	var bands: Array = LV["bands"]
	var base: Array = Data.enemies["tiers"]
	for i in bands.size():
		var t: Dictionary = (base[mini(i, base.size() - 1)] as Dictionary).duplicate()
		t["from"] = 0.0 if i == 0 else roundf(time_of_level(float(bands[i])))
		t["lv"] = [float(bands[i]) if i > 0 else -999.0, float(bands[i + 1]) if i + 1 < bands.size() else 9999.0]
		_lv_tiers.append(t)
	return _lv_tiers
