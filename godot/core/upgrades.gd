class_name Upgrades
extends RefCounted
## Per-Pokémon permanent upgrades bought with coins (port of js/data/upgrades.js).
## Definitions (id, icon, name, unit, max, base, grow) come from data/upgrades.json.

static var _list: Array = []
static var _by: Dictionary = {}

static func list() -> Array:
	if _list.is_empty():
		Data.ensure()
		_list = Data._json("upgrades.json")
		for u in _list:
			u["max"] = int(u["max"])
			_by[u["id"]] = u
	return _list

static func by_id(id: String) -> Dictionary:
	list()
	return _by.get(id, {})

## Price of the next level: round(base * grow^lvl / 10) * 10 (lvl = current level from 0).
static func cost(id: String, lvl: int) -> int:
	var u := by_id(id)
	return U.jroundi(float(u["base"]) * pow(float(u["grow"]), lvl) / 10.0) * 10

## Bought levels -> Player modifiers (upgrades.js perks); levels are clamped to [0, max].
static func perks(levels: Dictionary = {}) -> Dictionary:
	var L := func(id: String) -> int:
		var v: Variant = levels.get(id, 0)
		var n := int(floor(float(v))) if (v is int or v is float) else 0
		return clampi(n, 0, int(by_id(id)["max"]))
	return {
		"hp": L.call("hp") * 8.0,
		"atkMul": 1.0 + L.call("atk") * 0.04,
		"spdMul": 1.0 + L.call("spd") * 0.03,
		"cdMul": 1.0 - L.call("cd") * 0.03,
		"dmgReduce": L.call("def") * 0.02,
		"regen": L.call("regen") * 0.2,
		"magnetMul": 1.0 + L.call("magnet") * 0.12,
		"xpMul": 1.0 + L.call("xp") * 0.05,
		"coinMul": 1.0 + L.call("coins") * 0.08,
		"startMoves": 1 + L.call("moves"),
		"crit": L.call("crit") * 0.03,
		"rerolls": L.call("reroll"),
		"bans": L.call("ban"),
	}
