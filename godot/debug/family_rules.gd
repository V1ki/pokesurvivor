class_name FamilyRules
extends RefCounted
## The proposed progression ("family" rules), so far only for the simulator
## (tests/sim_play.gd --campaign --rules=family):
##   - coins buy TRAINER upgrades, shared by every Pokémon (R.trainer: the survival / economy ones);
##   - a FAMILY (evolution line, js/data/evolutions.js) has a level earned by playing any of its
##     forms; the level gives what the per-Pokémon coin upgrades gave (damage, cooldown, crits, a 2nd
##     starting move) and unlocks the moves of its learnset (js/data/learnsets.js: by level, older
##     games, evolution moves, plus "fill" = TM moves completing up to 4);
##   - a form can be used once the family reaches its evolution level (the original one, or the one
##     estimated from base stats) AND the form is owned: pulled in the gacha, or unlocked with shards;
##   - a duplicate pull gives shards: to the partner's family if it is one of its forms, otherwise
##     universal shards (R.uni_rate of them make one shard of any family); a complete family turns
##     shards into stars (突破, small stat boost).
## The account (a Dictionary saved by sim_play.gd) holds: trainer {upgrade levels}, fams {fam id:
## {lv, xp, shards, stars}}, uni (universal shards), gacha (Gacha save: owned, tickets...).

## Every number of the rules; --rules-set=k=v,k=v overrides them (set_overrides).
const DEFAULTS := {
	"trainer": ["hp", "def", "regen", "spd", "magnet", "xp", "coins", "reroll"],
	"cap": 60,                  # family level cap
	"xp_base": 100.0,           # family XP from level L to L+1: xp_base + xp_step * L
	"xp_step": 20.0,
	"xp_per_s": 0.5,            # family XP per second survived,
	"xp_per_kill": 1.0,         #   per Pokémon defeated,
	"xp_per_boss": 60.0,        #   per boss defeated
	"atk_lv": 0.0068,           # per family level above 1: x damage (+40% at 60, like Fuerza 10/10)
	"cd_lv": 0.0041,            #   - cooldown (-24% at 60, like Reflejos 8/8)
	"crit_lv": 0.0051,          #   + crit chance (30% at 60, like Golpe Crítico 10/10)
	"moves2_lv": 20,            # from this family level a run starts with 2 moves (was Repertorio)
	"shard": [1, 3, 5, 10, 30], # shards a duplicate of rarity 1..5 is worth
	"uni_rate": 2.0,            # universal shards per shard of a family
	"unlock": [10, 20, 40, 60, 100],   # shards to unlock a missing form of rarity 1..5
	"stars": 5,                 # stars (突破) of a complete family
	"star_cost": 30,            # shards per star
	"star_atk": 0.05,           # per star: x damage, x max HP
	"star_hp": 0.05,
	"refund": false,            # duplicates still refund coins too (the current game's coins)
	"min_known": 0,             # the first N moves of the learnset are known from family level 1
	"pool": "learnset",         # learnset: cards offer only learned moves · hybrid: + its type pool
	"stab_start": true,         # start with the first learned attack of its own type, if any
	"min_attacks": 4,           # knowing fewer attacks, its type's basic moves fill the list
}

static var R: Dictionary = DEFAULTS.duplicate(true)
static var _evo: Dictionary = {}
static var _learn: Dictionary = {}
static var _members: Dictionary = {}      # fam id -> [dex] (in-game forms)

## "--rules-set" text -> R: "xp_per_s=1,unlock=5/10/20/40/80" (numbers, true/false, a/b lists).
## Returns the keys it did not know.
static func set_overrides(text: String) -> Array:
	R = DEFAULTS.duplicate(true)
	var bad: Array = []
	for kv in text.split(",", false):
		var p := kv.split("=", true, 1)
		if p.size() < 2 or not R.has(p[0]):
			bad.append(kv)
			continue
		var v: String = p[1]
		if v == "true" or v == "false":
			R[p[0]] = v == "true"
		elif "/" in v:
			R[p[0]] = Array(v.split("/")).map(func(x): return float(x) if x.is_valid_float() else x)
		elif v.is_valid_float():
			R[p[0]] = float(v)
		else:
			R[p[0]] = v
	return bad

static func _data() -> void:
	if not _evo.is_empty():
		return
	Data.ensure()
	_evo = Data._json("evolutions.json")
	_learn = Data._json("learnsets.json")
	for k in _evo:
		var f := int(_evo[k]["f"])
		if not _members.has(f):
			_members[f] = []
		_members[f].append(int(k))

# ---------------- families ----------------

static func fam_of(dex: int) -> int:
	_data()
	return int(_evo[str(dex)]["f"]) if _evo.has(str(dex)) else -dex

static func members(fam: int) -> Array:
	_data()
	return _members.get(fam, [-fam] if fam < 0 else [])

## Family level needed to use this form: 1 for a first form, else its evolution level.
static func req_level(dex: int) -> int:
	_data()
	var e: Dictionary = _evo.get(str(dex), {})
	if not e.has("from") or not _evo.has(str(int(e["from"]))):
		return 1
	var h: Dictionary = e.get("how", {})
	return mini(int(R["cap"]), int(h.get("lv", h.get("est", 1))))

## The form and the ones it evolved from (in this game), first form last.
static func chain(dex: int) -> Array:
	_data()
	var out := [dex]
	var d := dex
	while _evo.has(str(d)) and _evo[str(d)].has("from") and _evo.has(str(int(_evo[str(d)]["from"]))):
		d = int(_evo[str(d)]["from"])
		out.append(d)
	return out

static func is_final(dex: int) -> bool:
	_data()
	for d in members(fam_of(dex)):
		if _evo.has(str(d)) and int(_evo[str(d)].get("from", 0)) == dex:
			return false
	return true

static func stage(dex: int) -> int:
	_data()
	return int(_evo.get(str(dex), {}).get("s", 0))

static func fam(acc: Dictionary, f: int) -> Dictionary:
	var fams: Dictionary = acc["fams"]
	if not fams.has(str(f)):
		fams[str(f)] = {"lv": 1, "xp": 0.0, "shards": 0, "stars": 0}
	return fams[str(f)]

static func owns(acc: Dictionary, dex: int) -> bool:
	return (acc["gacha"]["owned"] as Dictionary).has(str(dex))

static func usable(acc: Dictionary, dex: int) -> bool:
	return owns(acc, dex) and int(fam(acc, fam_of(dex))["lv"]) >= req_level(dex)

static func usable_list(acc: Dictionary) -> Array:
	var out: Array = []
	for k in (acc["gacha"]["owned"] as Dictionary):
		var d := int(k)
		if Data.dex_by.has(d) and usable(acc, d):
			out.append(d)
	return out

# ---------------- a run with this account ----------------

## Moves this form can use: [id, family level that unlocks it], first learned first. Forms it
## evolved from count (an evolved Pokémon keeps its moves); "fill" (rule A) from level 1.
static func moves_of(acc: Dictionary, dex: int) -> Array:
	var lv := int(fam(acc, fam_of(dex))["lv"])
	var all := all_moves(dex)
	var out: Array = []
	for i in all.size():
		if int(all[i][1]) <= lv or i < int(R["min_known"]):
			# [id, level it is known from, position in the learnset] (the first min_known from level 1)
			out.append([all[i][0], 1 if i < int(R["min_known"]) else int(all[i][1]), i])
	out.sort_custom(func(a, b): return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2]))
	# fewer than min_attacks attacks: its type's basic moves fill the list (they make way for its own)
	var n := out.filter(func(e): return Moves.def(e[0]).get("kind", "") != "buff").size()
	var ids: Array = out.map(func(e): return e[0])
	for id in basics(dex):
		if n >= int(R["min_attacks"]):
			break
		if not ids.has(id):
			out.append([id, 1, 1000 + n, "basic"])
			n += 1
	return out

## Basic moves of its type to fill a short list (G.Families.basics): the start move of each of its
## types (Ember, Vine Whip...), then the rest of its types' pools, then the normal ones.
static func basics(dex: int) -> Array:
	var mon: Dictionary = Data.dex_by[dex]
	var out: Array = []
	var add := func(id: String) -> void:
		if Data.move_by.has(id) and Moves.def(id).get("kind", "") != "buff" and not out.has(id):
			out.append(id)
	for t in mon["types"]:
		add.call(str(Data.start_by_type.get(t, "")))
	for t in mon["types"]:
		for id in Data.pool_by_type.get(t, []):
			add.call(str(id))
	for id in Data.pool_by_type.get("normal", []):
		add.call(str(id))
	return out

## Every move of this form's learnset with its unlock level (see moves_of), first learned first.
static func all_moves(dex: int) -> Array:
	_data()
	var at := {}
	var add := func(id: String, l: int) -> void:
		if Data.move_by.has(id) and (not at.has(id) or l < int(at[id])):
			at[id] = l
	var ch := chain(dex)
	for i in ch.size():
		var ls: Dictionary = _learn.get(str(ch[i]), {})
		for e in ls.get("lv", []) + ls.get("old", []):
			add.call(str(e[0]), maxi(1, int(e[1])))
		for id in ls.get("evo", []):
			add.call(str(id), req_level(ch[i]))          # learned when it evolved into this form
	for id in _learn.get(str(dex), {}).get("fill", []):
		add.call(str(id), 1)
	# no attack at level 1 (its first move isn't in the game: Leer, Wrap...): its type's one, as before
	var first := false
	for id in at:
		if int(at[id]) <= 1 and Moves.def(id).get("kind", "") != "buff":
			first = true
	if not first:
		add.call(Moves.start_move_of(dex), 1)
	var out: Array = []
	for id in at:
		out.append([id, int(at[id])])
	out.sort_custom(func(a, b): return a[1] < b[1] or (a[1] == b[1] and str(a[0]) < str(b[0])))
	return out

## The moves the level-up cards may offer: the learned ones (+ its type pool with R.pool "hybrid").
static func pool_of(dex: int, moves: Array) -> Array:
	var ids: Array = moves.map(func(e): return e[0])
	if R["pool"] == "hybrid":
		for id in Moves.pool_for(Data.dex_by[dex]):
			if not ids.has(id):
				ids.append(id)
	return ids

## Moves a run starts with: the first damaging one learned (2 from moves2_lv); with R.stab_start
## the first one of its own type comes first (its type's move if it learned none yet, hybrid).
static func start_moves(acc: Dictionary, dex: int, moves: Array) -> Array:
	var n := 2 if int(fam(acc, fam_of(dex))["lv"]) >= int(R["moves2_lv"]) else 1
	var atk: Array = moves.filter(func(e): return Moves.def(e[0]).get("kind", "") != "buff").map(func(e): return e[0])
	if R["stab_start"]:
		var types: Array = Data.dex_by[dex]["types"]
		var own: Array = atk.filter(func(id): return types.has(Moves.def(id).get("type", "")))
		if own.is_empty() and R["pool"] == "hybrid":
			own = [Moves.start_move_of(dex)]
		if not own.is_empty():
			atk.erase(own[0])
			atk.push_front(own[0])
	var out: Array = atk.slice(0, n)
	if out.is_empty():
		out.append(Moves.start_move_of(dex))
	return out

## Sim.start_run perks: trainer upgrades + what the family level and stars give.
static func perks(acc: Dictionary, dex: int) -> Dictionary:
	var pk := Upgrades.perks(acc["trainer"])
	var fm := fam(acc, fam_of(dex))
	var l := int(fm["lv"]) - 1
	var st := int(fm["stars"])
	pk["atkMul"] = float(pk["atkMul"]) * (1.0 + float(R["atk_lv"]) * l) * (1.0 + float(R["star_atk"]) * st)
	pk["cdMul"] = float(pk["cdMul"]) * maxf(0.4, 1.0 - float(R["cd_lv"]) * l)
	pk["crit"] = float(pk["crit"]) + float(R["crit_lv"]) * l
	pk["hp"] = float(pk["hp"]) + float(Data.dex_by[dex]["hp"]) * float(R["star_hp"]) * st
	pk["startMoves"] = 1
	pk["bans"] = 0
	return pk

## Roughly how strong a Pokémon of this account is (Bot.power with the family-rule perks).
static func power(acc: Dictionary, dex: int) -> float:
	var mon: Dictionary = Data.dex_by[dex]
	var pk := perks(acc, dex)
	var atk := float(mon["atk"]) * float(pk["atkMul"]) / float(pk["cdMul"]) * (1.0 + float(pk["crit"]) * 0.5)
	var hp := (float(mon["hp"]) + float(pk["hp"])) / (1.0 - float(pk["dmgReduce"])) + float(pk["regen"]) * 30.0
	var spd := float(mon["spd"]) * float(pk["spdMul"])
	var two := int(fam(acc, fam_of(dex))["lv"]) >= int(R["moves2_lv"])
	return atk * pow(hp, 0.6) * pow(spd, 0.3) * (1.3 if two else 1.0)

# ---------------- between runs ----------------

## Family XP of a run (sim_play result) for the partner's family. Returns levels gained.
static func gain_xp(acc: Dictionary, dex: int, r: Dictionary) -> int:
	var fm := fam(acc, fam_of(dex))
	fm["xp"] = float(fm["xp"]) + float(r["time"]) * float(R["xp_per_s"]) + float(r["kills"]) * float(R["xp_per_kill"]) \
		+ float(r["bosses"]) * float(R["xp_per_boss"])
	var up := 0
	while int(fm["lv"]) < int(R["cap"]):
		var need := float(R["xp_base"]) + float(R["xp_step"]) * int(fm["lv"])
		if float(fm["xp"]) < need:
			break
		fm["xp"] = float(fm["xp"]) - need
		fm["lv"] = int(fm["lv"]) + 1
		up += 1
	if int(fm["lv"]) >= int(R["cap"]):
		fm["xp"] = 0.0
	return up

## Gacha results -> shards. Duplicates of the partner's family give its shards, any other
## duplicate gives universal shards (both by rarity). Without R.refund the coins a duplicate
## refunded are taken back. Returns the coins to take back.
static func shards_from(acc: Dictionary, partner: int, got: Array) -> int:
	var f := fam_of(partner)
	var back := 0
	var sv: Array = R["shard"]
	for g in got:
		if g["isNew"]:
			continue
		var v := int(sv[clampi(int(g["rarity"]) - 1, 0, 4)])
		if fam_of(int(g["dex"])) == f:
			fam(acc, f)["shards"] = int(fam(acc, f)["shards"]) + v
		else:
			acc["uni"] = int(acc.get("uni", 0)) + v
		if not R["refund"]:
			back += int(g["refund"])
	return back

## Pays `cost` family shards with the family's own, then universal ones. False if it can't.
static func _pay(acc: Dictionary, fm: Dictionary, cost: int) -> bool:
	var own := int(fm["shards"])
	var uni := int(acc.get("uni", 0))
	var rate := float(R["uni_rate"])
	if own + int(floor(uni / rate)) < cost:
		return false
	var from_own := mini(own, cost)
	fm["shards"] = own - from_own
	acc["uni"] = uni - int(ceil((cost - from_own) * rate))
	return true

## Spends shards on the partner's family the way a player would: unlock the next missing form it
## has the level for (the one with the most base stats first), then stars once nothing is
## missing. Returns the dex numbers unlocked.
static func spend_shards(acc: Dictionary, partner: int) -> Array:
	var f := fam_of(partner)
	var fm := fam(acc, f)
	var unl: Array = R["unlock"]
	var out: Array = []
	var missing: Array = members(f).filter(func(d): return Data.dex_by.has(d) and not owns(acc, d))
	missing.sort_custom(func(a, b): return req_level(a) < req_level(b) or (req_level(a) == req_level(b)
		and int(Data.dex_by[a]["bst"]) > int(Data.dex_by[b]["bst"])))
	for d in missing:
		if req_level(d) > int(fm["lv"]):
			break
		var cost := int(unl[clampi(int(Data.dex_by[d]["rarity"]) - 1, 0, 4)])
		if not _pay(acc, fm, cost):
			break
		acc["gacha"]["owned"][str(d)] = {"at": 0, "from": "shards"}
		out.append(d)
	if members(f).all(func(d): return not Data.dex_by.has(d) or owns(acc, d)):
		while int(fm["stars"]) < int(R["stars"]) and _pay(acc, fm, int(R["star_cost"])):
			fm["stars"] = int(fm["stars"]) + 1
	return out

## Cost of every trainer upgrade (to report progress).
static func trainer_total() -> int:
	var t := 0
	for u in Upgrades.list():
		if (R["trainer"] as Array).has(u["id"]):
			for l in int(u["max"]):
				t += Upgrades.cost(u["id"], l)
	return t

static func trainer_spent(levels: Dictionary) -> int:
	var t := 0
	for u in Upgrades.list():
		if (R["trainer"] as Array).has(u["id"]):
			for l in mini(int(levels.get(u["id"], 0)), int(u["max"])):
				t += Upgrades.cost(u["id"], l)
	return t
