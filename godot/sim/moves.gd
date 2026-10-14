class_name Moves
extends RefCounted
## Move instances, ladders and evolutions (js/data/moves.js). Base defs come from
## moves.json (melee load-time buff already applied by the exporter). An instance is a
## Dictionary copy of the def plus {id, lvl, t, evolved, base_name}.

## Every move kind (all implemented in sim/combat.gd since Phase 2).
const IMPLEMENTED_KINDS := ["projectile", "melee", "beam", "orbit", "nova", "aura", "boomerang", "chain", "mine",
	"meteor", "turret", "dash", "trail", "cone", "buff"]

static func def(id: String) -> Dictionary:
	return Data.move_by.get(id, {})

static func max_lvl(m: Dictionary) -> int:
	return (Data.ladders[m["kind"]] as Array).size() + 1

## Instance of a move at `lvl` with all ladder steps up to that level applied.
static func instance(id: String, lvl := 1) -> Dictionary:
	var d := def(id)
	var s: Dictionary = d.duplicate(true)
	s["id"] = id
	s["lvl"] = lvl
	s["t"] = 0.0
	s["evolved"] = false
	var ups: Array = Data.ladders[d["kind"]]
	for i in lvl - 1:
		apply_mods(s, ups[i]["m"])
	return s

## MULT keys multiply if the base value exists; ADD keys add; anything else is assigned.
static func apply_mods(s: Dictionary, m: Dictionary) -> void:
	for k in m:
		if Data.mult_keys.has(k) and s.has(k) and s[k] != null:
			s[k] = float(s[k]) * float(m[k])
		elif Data.add_keys.has(k):
			s[k] = float(s.get(k, 0.0)) + float(m[k])
		else:
			s[k] = m[k]

static func level_up(s: Dictionary) -> bool:
	if int(s["lvl"]) >= max_lvl(s):
		return false
	apply_mods(s, Data.ladders[s["kind"]][int(s["lvl"]) - 1]["m"])
	s["lvl"] = int(s["lvl"]) + 1
	return true

## Text of the next upgrade (level-up card), or "" at max level.
static func next_up_text(s: Dictionary) -> String:
	if int(s["lvl"]) >= max_lvl(s):
		return ""
	return Data.ladders[s["kind"]][int(s["lvl"]) - 1]["t"]

## Moves this Pokémon can learn (its types + normal).
static func pool_for(mon: Dictionary) -> Array:
	var ids: Array = (Data.pool_by_type.get("normal", []) as Array).duplicate()
	for t in mon["types"]:
		for id in Data.pool_by_type.get(t, []):
			if not ids.has(id):
				ids.append(id)
	return ids

static func start_for(mon: Dictionary) -> String:
	if mon.has("start") and Data.move_by.has(mon["start"]):
		return mon["start"]
	for t in mon["types"]:
		if Data.start_by_type.has(t):
			return Data.start_by_type[t]
	return "tackle"

## G.startMoveOf: starter table first, else by type.
static func start_move_of(dex: int) -> String:
	if Data.starter_by.has(dex):
		return Data.starter_by[dex]["start"]
	return start_for(Data.dex_by[dex])

# ---------------- evolution ----------------

## {name, needs, need_name, text, ready} or {} if it cannot evolve.
static func evo_info(m: Dictionary, stats_taken: Dictionary) -> Dictionary:
	if not Data.evo.has(m["id"]) or m.get("evolved", false) or int(m["lvl"]) < max_lvl(m) \
			or not Data.evo_mods.has(m["kind"]):
		return {}
	var e: Array = Data.evo[m["id"]]
	return {"name": e[0], "needs": e[1], "need_name": Data.need_name.get(e[1], ""),
		"text": Data.evo_mods[m["kind"]]["t"], "ready": int(stats_taken.get(e[1], 0)) > 0}

static func evolve(m: Dictionary) -> bool:
	if not Data.evo.has(m["id"]) or m.get("evolved", false):
		return false
	apply_mods(m, Data.evo_mods[m["kind"]]["m"])
	m["base_name"] = m["name"]
	m["name"] = Data.evo[m["id"]][0]
	m["evolved"] = true
	return true
