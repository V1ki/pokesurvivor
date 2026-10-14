class_name Gacha
extends RefCounted
## One banner per generation (port of js/systems/gacha.js). Pure logic on a save Dictionary.
## Rates 1* 45 / 2* 30 / 3* 17 / 4* 6.5 / 5* 1.5 %; a x10 pull brings at least one 4*; after 70 pulls
## without a 5* on a banner the next one is 5*; 1/100 shiny (an owned shiny is swapped for a missing
## one of the same pool, or the pull turns normal); duplicates refund coins (15/30/60/120/300).
## Every random draw goes through `rnd` (Math.random order of the JS code), so a seeded RNG
## reproduces the JS results exactly (tests/run_tests.gd).

static var _cfg: Dictionary = {}
static var _pools: Dictionary = {}     # "gen/rarity" -> [entries]

static func cfg() -> Dictionary:
	if _cfg.is_empty():
		Data.ensure()
		_cfg = Data._json("gacha.json")
		_cfg["pity"] = int(_cfg["pity"])
	return _cfg

static func banners() -> Array:
	return cfg()["banners"]

static func rarity_name(r: int) -> String:
	return cfg()["rarity_name"].get(str(r), "")

static func rarity_color(r: int) -> Color:
	return Color.html(cfg()["rarity_color"].get(str(r), "#ffffff"))

static func refund(r: int) -> int:
	return int(cfg()["refund"].get(str(r), 0))

## What a pull of n costs: {t1, t10} or {} if you can't afford it. use = "t1" | "t10" (x10 only).
static func cost_of(save: Dictionary, n: int, use := "t1") -> Dictionary:
	var t: Dictionary = save.get("tickets", {"t1": 0, "t10": 0})
	if n == 10 and use == "t10":
		return {"t1": 0, "t10": 1} if int(t.get("t10", 0)) >= 1 else {}
	return {"t1": n, "t10": 0} if int(t.get("t1", 0)) >= n else {}

static func _in_banner(p: Dictionary, gen: int) -> bool:
	return int(p["gen"]) == gen and Data.meta_by.has(int(p["dex"]))

## Pokémon of a rarity in a banner (G.DEX order).
static func pool(rarity: int, gen: int) -> Array:
	var k := "%d/%d" % [gen, rarity]
	if not _pools.has(k):
		Data.ensure()
		_pools[k] = Data.dex.filter(func(p): return _in_banner(p, gen) and int(p["rarity"]) == rarity)
	return _pools[k]

## Closest non-empty pool (offsets 0,-1,+1,-2,+2,...).
static func pool_near(rarity: int, gen: int) -> Dictionary:
	for d in [0, -1, 1, -2, 2, -3, 3, -4, 4]:
		var r: int = rarity + d
		if r < 1 or r > 5:
			continue
		var p := pool(r, gen)
		if not p.is_empty():
			return {"rarity": r, "list": p}
	return {"rarity": rarity, "list": Data.dex.filter(func(p): return _in_banner(p, gen))}

static func roll_rarity(rnd: Callable, min_r := 1) -> int:
	var rates: Array = cfg()["rates"].filter(func(rw): return int(rw[0]) >= min_r)
	var total := 0.0
	for rw in rates:
		total += float(rw[1])
	var x: float = rnd.call() * total
	for rw in rates:
		x -= float(rw[1])
		if x <= 0.0:
			return int(rw[0])
	return int(rates[rates.size() - 1][0])

## The 3 strongest 5* of a generation (banner art).
static func featured(gen: int) -> Array:
	var l: Array = Data.dex.filter(func(p): return _in_banner(p, gen) and int(p["rarity"]) == 5)
	# JS Array.sort is stable: equal BST keep the G.DEX order (Godot's sort_custom is not)
	var idx := {}
	for i in l.size():
		idx[l[i]["dex"]] = i
	l.sort_custom(func(a, b): return float(a["bst"]) > float(b["bst"]) or \
		(float(a["bst"]) == float(b["bst"]) and idx[a["dex"]] < idx[b["dex"]]))
	return l.slice(0, 3).map(func(p): return int(p["dex"]))

static func _pick(list: Array, rnd: Callable) -> Variant:
	return list[int(floor(rnd.call() * list.size()))]

static var force_shiny := 0            # debug: the next N pulls are shiny (G.Gacha.debugForceShiny)

## n pulls on banner `gen` over `save` (modified). Returns [] if unaffordable, else
## [{dex, rarity, shiny, isNew, refund}]. rnd: Callable -> float in [0, 1) (default randf).
static func pull(save: Dictionary, n: int, gen := 1, use := "t1", rnd := Callable()) -> Array:
	if not rnd.is_valid():
		rnd = func() -> float: return randf()
	var cost := cost_of(save, n, use)
	if cost.is_empty():
		return []
	save["tickets"]["t1"] = int(save["tickets"]["t1"]) - int(cost["t1"])
	save["tickets"]["t10"] = int(save["tickets"]["t10"]) - int(cost["t10"])
	if not (save.get("pity") is Dictionary):
		save["pity"] = {}
	if not (save.get("shiny") is Dictionary):
		save["shiny"] = {}
	var pity: Dictionary = save["pity"]
	var g := str(gen)
	pity[g] = int(pity.get(g, 0))
	var shinies: Dictionary = save["shiny"]
	var owned: Dictionary = save["owned"]
	var out: Array = []
	var t := Save.now_ms()
	for i in n:
		pity[g] = int(pity[g]) + 1
		var want: int
		if int(pity[g]) >= int(cfg()["pity"]):
			want = 5
		elif n == 10 and i == n - 1 and not out.any(func(r): return int(r["rarity"]) >= 4):
			want = roll_rarity(rnd, 4)
		else:
			want = roll_rarity(rnd)
		var pn := pool_near(want, gen)
		var rarity: int = pn["rarity"]
		var list: Array = pn["list"]
		if rarity == 5:
			pity[g] = 0
		var mon: Dictionary = _pick(list, rnd)
		var shiny := false
		if Sprites.has_shiny(int(mon["dex"])):
			if force_shiny > 0:
				force_shiny -= 1
				shiny = true
			else:
				shiny = rnd.call() < float(cfg()["shiny_rate"])
		# shinies never repeat: swap for a same-pool one you lack, else the pull is normal
		if shiny and shinies.has(str(mon["dex"])):
			var missing: Array = list.filter(func(p): return Sprites.has_shiny(int(p["dex"])) and not shinies.has(str(p["dex"])))
			if not missing.is_empty():
				mon = _pick(missing, rnd)
			else:
				shiny = false
		var dex := int(mon["dex"])
		var is_new := false
		var rf := 0
		if shiny:
			is_new = not shinies.has(str(dex))
			if is_new:
				shinies[str(dex)] = {"at": t, "from": "gacha"}
			else:
				rf = refund(rarity) * 3
			if not owned.has(str(dex)):
				owned[str(dex)] = {"at": t, "from": "gacha"}
		else:
			is_new = not owned.has(str(dex))
			if is_new:
				owned[str(dex)] = {"at": t, "from": "gacha"}
			else:
				rf = refund(rarity)
		save["coins"] = int(save["coins"]) + rf
		out.append({"dex": dex, "rarity": rarity, "shiny": shiny, "isNew": is_new, "refund": rf})
	save["stats"]["pulls"] = int(save["stats"].get("pulls", 0)) + n
	return out
