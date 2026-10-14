class_name Items
extends RefCounted
## Held items, one per run (js/data/items.js). on/off are exact inverses; the reactive ones
## (focussash, shellbell, rockyhelmet, lifeorb, choiceband) are checked with pl.has_item().
## Names/descriptions come from data/items.json.

static var _list: Array = []

static func list() -> Array:
	if _list.is_empty():
		Data.ensure()
		_list = Data._json("items.json")
	return _list

static func by_id(id: String) -> Dictionary:
	for it in list():
		if it["id"] == id:
			return it
	return {}

static func name_of(id: String) -> String:
	return by_id(id).get("name", id)

static func on(id: String, p: Player) -> void:
	match id:
		"leftovers":
			p.item_regen = p.max_hp * 0.015
			p.regen_flat += p.item_regen
		"choiceband":
			p.atk_mul *= 1.4
		"quickclaw":
			p.cd_mul *= 0.8
		"amuletcoin":
			p.coin_mul *= 1.5
		"luckyegg":
			p.xp_mul *= 1.3
		"lifeorb":
			p.atk_mul *= 1.3
		"choicescarf":
			p.spd_mul *= 1.35
		"assaultvest":
			p.dmg_reduce += 0.2

static func off(id: String, p: Player) -> void:
	match id:
		"leftovers":
			p.regen_flat -= p.item_regen
		"choiceband":
			p.atk_mul /= 1.4
		"quickclaw":
			p.cd_mul /= 0.8
		"amuletcoin":
			p.coin_mul /= 1.5
		"luckyegg":
			p.xp_mul /= 1.3
		"lifeorb":
			p.atk_mul /= 1.3
		"choicescarf":
			p.spd_mul /= 1.35
		"assaultvest":
			p.dmg_reduce -= 0.2

## A random item different from `except`.
static func roll(except := "") -> String:
	var pool: Array = list().filter(func(i): return i["id"] != except)
	return U.pick(pool)["id"]
