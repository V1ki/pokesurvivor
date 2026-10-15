class_name Families
extends RefCounted
## Trainer, families, evolution and shards (port of js/systems/families.js, 2026-10-14), on the
## save Dictionary (Save.data, the same object as the web save):
##   - TRAINER: the coin upgrades (R.trainer: hp, def, regen, spd, magnet, xp, coins, reroll) work
##     for every Pokémon (save.trainer).
##   - FAMILY: each evolution line (data/evolutions.json) has a level (save.fams) earned by playing
##     any of its forms. It gives what Strength, Reflexes, Critical Hit and Repertoire gave and
##     unlocks the moves of its learnset (data/learnsets.json): the run starts with an attack of its
##     own type and the cards offer only the moves it knows (with fewer than R.minAttacks attacks,
##     its type's basic moves fill the list).
##   - EVOLUTION: a form can be used once its family reaches its evolution level and it is owned:
##     pulled in the gacha or unlocked with shards.
##   - SHARDS: a gacha duplicate gives shards of the partner's family if it belongs to it, else
##     universal shards (R.uniRate of them = 1 of any family); no coins. A complete family turns
##     shards into stars (+5% damage and HP each, up to 5).
## What was owned before save.stats.famAt stays usable. The simulator has the same rules on its
## own account format (debug/family_rules.gd).

const R := {
	"trainer": ["hp", "def", "regen", "spd", "magnet", "xp", "coins", "reroll"],
	"cap": 60,                 # family level cap
	"xpBase": 100, "xpStep": 20,   # XP from level L to L+1: xpBase + xpStep * L
	"xpPerS": 0.5,             # family XP per second survived,
	"xpPerKill": 1,            #   per Pokémon defeated
	"xpPerBoss": 60,           #   and per boss
	"atkLv": 0.0068,           # per level above 1: x damage (+40% at 60, like Strength 10/10)
	"cdLv": 0.0041,            #   - cooldown (-24% at 60, like Reflexes 8/8)
	"critLv": 0.0051,          #   + crits (30% at 60, like Critical Hit 10/10)
	"moves2Lv": 20,            # from this level a run starts with 2 moves
	"shard": [1, 3, 5, 10, 30],        # shards a duplicate of rarity 1..5 is worth
	"uniRate": 2,                      # universal shards per shard of a family
	"unlock": [10, 20, 40, 60, 100],   # shards to unlock a form of rarity 1..5
	"stars": 5, "starCost": 30,        # stars of a complete family and their price
	"starAtk": 0.05, "starHp": 0.05,   # per star: x damage and x HP
	"minKnown": 0,             # the first N moves of its list are known from level 1
	"pool": "learnset",        # 'learnset': cards offer only the moves it knows · 'hybrid': + its type's
	"stabStart": true,         # starts with the first attack of its own type it knows (if any)
	"minAttacks": 4,           # knowing fewer attacks, its type's basic moves fill the list
}

static var _evo: Dictionary = {}
static var _learn: Dictionary = {}
static var _members: Dictionary = {}      # family -> [dex] (the forms in the game)

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

static func evo(dex: int) -> Dictionary:
	_data()
	return _evo.get(str(dex), {})

# ---------------- families (data/evolutions.json) ----------------

static func fam_of(dex: int) -> int:
	_data()
	return int(_evo[str(dex)]["f"]) if _evo.has(str(dex)) else -dex

static func members(f: int) -> Array:
	_data()
	return _members.get(f, [-f] if f < 0 else [])

static func stage(dex: int) -> int:
	return int(evo(dex).get("s", 0))

static func _from(dex: int) -> int:
	var e := evo(dex)
	return int(e["from"]) if e.get("from") != null and _evo.has(str(int(e["from"]))) else 0

## Family level needed to use this form: 1 for the first one, else its evolution level.
static func req_level(dex: int) -> int:
	if _from(dex) == 0:
		return 1
	var h: Dictionary = evo(dex).get("how", {}) if evo(dex).get("how") is Dictionary else {}
	var l := int(h.get("lv", 0)) if int(h.get("lv", 0)) > 0 else int(h.get("est", 0))
	return mini(int(R["cap"]), l if l > 0 else 1)

## The form and the ones it evolves from (in the game), the first one last.
static func chain(dex: int) -> Array:
	var out := [dex]
	var d := dex
	while _from(d) != 0:
		d = _from(d)
		out.append(d)
	return out

static func is_final(dex: int) -> bool:
	for d in members(fam_of(dex)):
		if int(evo(d).get("from", 0)) == dex:
			return false
	return true

## A family's name: its first form's.
static func fam_name(f: int) -> String:
	var m: Array = members(f).duplicate()
	m.sort_custom(func(a, b): return stage(a) < stage(b) or (stage(a) == stage(b) and a < b))
	return str(Data.dex_by[m[0]]["name"]) if not m.is_empty() and Data.dex_by.has(m[0]) else "?"

# ---------------- the save ----------------

## A family's data in the save (created when asked for).
static func fam(save: Dictionary, f: int) -> Dictionary:
	if not (save.get("fams") is Dictionary):
		save["fams"] = {}
	var fams: Dictionary = save["fams"]
	if not fams.has(str(f)):
		fams[str(f)] = {"lv": 1, "xp": 0, "shards": 0, "stars": 0}
	return fams[str(f)]

static func fam_of_dex(save: Dictionary, dex: int) -> Dictionary:
	return fam(save, fam_of(dex))

static func owns(save: Dictionary, dex: int) -> bool:
	return save.get("owned") is Dictionary and (save["owned"] as Dictionary).has(str(dex))

## Owned since before the families? (then it can always be used)
static func legacy(save: Dictionary, dex: int) -> bool:
	if not owns(save, dex):
		return false
	var o: Variant = save["owned"][str(dex)]
	var at := float(o.get("at", 0)) if o is Dictionary and (o.get("at") is int or o.get("at") is float) else 0.0
	var st: Dictionary = save.get("stats", {}) if save.get("stats") is Dictionary else {}
	var fa := float(st.get("famAt", 0)) if (st.get("famAt") is int or st.get("famAt") is float) else 0.0
	return at < fa

## Can it be the partner? It must be owned and its family must reach its level.
static func usable(save: Dictionary, dex: int) -> bool:
	return owns(save, dex) and (legacy(save, dex) or int(fam_of_dex(save, dex)["lv"]) >= req_level(dex))

# ---------------- moves (data/learnsets.json) ----------------

## Every move of this form with the family level that unlocks it, first to last: its list and
## those of the forms it evolves from; "evo" ones on reaching this form; "fill" (TMs completing a
## short list) from the start. [[id, level]]
static func moves_of(dex: int) -> Array:
	_data()
	var at := {}                 # id -> level (insertion order like the JS Map)
	var add := func(id: String, lv: int) -> void:
		if Data.move_by.has(id) and (not at.has(id) or lv < int(at[id])):
			at[id] = lv
	for d in chain(dex):
		var ls: Dictionary = _learn.get(str(d), {})
		for e in (ls.get("lv", []) as Array) + (ls.get("old", []) as Array):
			add.call(str(e[0]), maxi(1, int(e[1])))
		for id in ls.get("evo", []):
			add.call(str(id), req_level(d))
	for id in (_learn.get(str(dex), {}) as Dictionary).get("fill", []):
		add.call(str(id), 1)
	# no attack at level 1 (its first move is not in the game: Leer, Wrap...): its type's, as before
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
	var mk := int(R["minKnown"])
	for i in mini(mk, out.size()):
		out[i] = [out[i][0], 1]
	if mk > 0:
		var idx := {}
		for i in out.size():
			idx[out[i][0]] = i
		out.sort_custom(func(a, b): return a[1] < b[1] or (a[1] == b[1] and int(idx[a[0]]) < int(idx[b[0]])))
	return out

## Basic moves of its types to fill a short list: each of its types' start move (Ember, Vine
## Whip...), then the rest of its types' pools, then the normal ones.
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

## The ones it knows at its family's level; with fewer than R.minAttacks attacks, its type's basic
## moves fill the list (marked "basic": [id, 1, "basic"]) and make way for its own.
static func known(save: Dictionary, dex: int) -> Array:
	var lv := int(fam_of_dex(save, dex)["lv"])
	var list: Array = moves_of(dex).filter(func(e): return int(e[1]) <= lv)
	var atk := list.filter(func(e): return Moves.def(e[0]).get("kind", "") != "buff").size()
	var ids: Array = list.map(func(e): return e[0])
	for id in basics(dex):
		if atk >= int(R["minAttacks"]):
			break
		if ids.has(id):
			continue
		list.append([id, 1, "basic"])
		atk += 1
	return list

## To show them: the basic moves filling the list now, then its own list (without repeating them).
static func shown(save: Dictionary, dex: int) -> Array:
	var basic: Array = known(save, dex).filter(func(e): return e.size() > 2 and e[2] == "basic")
	var b_ids: Array = basic.map(func(e): return e[0])
	return basic + moves_of(dex).filter(func(e): return not b_ids.has(e[0]))

## What the cards may offer: the ones it knows (with R.pool "hybrid", also its type's).
static func pool_of(dex: int, list: Array) -> Array:
	var ids: Array = list.map(func(e): return e[0])
	if R["pool"] == "hybrid":
		for id in Moves.pool_for(Data.dex_by[dex]):
			if not ids.has(id):
				ids.append(id)
	return ids

## What a run starts with: the first attack it knows (2 from R.moves2Lv); with R.stabStart, one
## of its own type first (with "hybrid", its type's usual one if it knows none yet).
static func start_moves(save: Dictionary, dex: int, list = null) -> Array:
	if list == null:
		list = known(save, dex)
	var n := 2 if int(fam_of_dex(save, dex)["lv"]) >= int(R["moves2Lv"]) else 1
	var atk: Array = (list as Array).filter(func(e): return Moves.def(e[0]).get("kind", "") != "buff").map(func(e): return e[0])
	if R["stabStart"]:
		var types: Array = Data.dex_by[dex]["types"]
		var own := ""
		for id in atk:
			if types.has(Moves.def(id).get("type", "")):
				own = id
				break
		if own == "" and R["pool"] == "hybrid":
			own = Moves.start_move_of(dex)
		if own != "":
			atk.erase(own)
			atk.push_front(own)
	var out: Array = atk.slice(0, n)
	return out if not out.is_empty() else [Moves.start_move_of(dex)]

# ---------------- in the run ----------------

## Player perks: the trainer's upgrades plus what the family level and stars give.
static func perks(save: Dictionary, dex: int) -> Dictionary:
	var p := Upgrades.perks(save.get("trainer", {}) if save.get("trainer") is Dictionary else {})
	var f := fam_of_dex(save, dex)
	var l := int(f["lv"]) - 1
	var st := int(f["stars"])
	p["atkMul"] = float(p["atkMul"]) * (1.0 + float(R["atkLv"]) * l) * (1.0 + float(R["starAtk"]) * st)
	p["cdMul"] = float(p["cdMul"]) * maxf(0.4, 1.0 - float(R["cdLv"]) * l)
	p["crit"] = float(p["crit"]) + float(R["critLv"]) * l
	p["hp"] = float(p["hp"]) + U.jround(float(Data.dex_by[dex]["hp"]) * float(R["starHp"]) * st)
	p["startMoves"] = 1
	p["bans"] = 0
	return p

## What each level gives, to show it: {atk, cd, crit} in % and whether it starts with 2 moves.
static func level_bonus(lv: int) -> Dictionary:
	var l := lv - 1
	return {"atk": U.jroundi(float(R["atkLv"]) * l * 100.0), "cd": U.jroundi(minf(0.6, float(R["cdLv"]) * l) * 100.0),
		"crit": U.jroundi(float(R["critLv"]) * l * 100.0), "two": lv >= int(R["moves2Lv"])}

# ---------------- between runs ----------------

static func xp_need(lv: int) -> int:
	return int(R["xpBase"]) + int(R["xpStep"]) * lv

## A run's XP for the partner's family. run {time, kills, bosses} -> {f, lv, ups, xp, need, gained}
static func gain_xp(save: Dictionary, dex: int, run: Dictionary) -> Dictionary:
	var fm := fam_of_dex(save, dex)
	var gained := U.jroundi(float(run["time"]) * float(R["xpPerS"]) + float(run["kills"]) * float(R["xpPerKill"])
		+ float(run["bosses"]) * float(R["xpPerBoss"]))
	fm["xp"] = float(fm["xp"]) + gained
	var ups := 0
	while int(fm["lv"]) < int(R["cap"]) and float(fm["xp"]) >= xp_need(int(fm["lv"])):
		fm["xp"] = float(fm["xp"]) - xp_need(int(fm["lv"]))
		fm["lv"] = int(fm["lv"]) + 1
		ups += 1
	if int(fm["lv"]) >= int(R["cap"]):
		fm["xp"] = 0
	fm["xp"] = Save.ints(fm["xp"])
	return {"f": fam_of(dex), "lv": int(fm["lv"]), "ups": ups, "xp": fm["xp"], "need": xp_need(int(fm["lv"])), "gained": gained}

## After a pull (Gacha.pull): each duplicate gives shards instead of coins, of the partner's family
## if it belongs to it, else universal ones. Sets {shards, uni} on every result and takes back the
## coins it refunded.
static func after_pull(save: Dictionary, results: Array) -> void:
	var f := fam_of(int(save["partner"])) if save.get("partner") != null else 0
	for r in results:
		r["shards"] = 0
		r["uni"] = 0
		if r["isNew"]:
			continue
		var v := int(R["shard"][clampi(int(r["rarity"]) - 1, 0, 4)])
		if fam_of(int(r["dex"])) == f:
			var fm := fam(save, f)
			fm["shards"] = int(fm["shards"]) + v
			r["shards"] = v
		else:
			save["uni"] = int(save.get("uni", 0)) + v
			r["uni"] = v
		save["coins"] = maxi(0, int(save["coins"]) - int(r.get("refund", 0)))
		r["refund"] = 0

## A family's shards counting the universal ones.
static func shards_for(save: Dictionary, f: int) -> int:
	return int(fam(save, f)["shards"]) + int(floor(float(save.get("uni", 0)) / float(R["uniRate"])))

## Pays with the family's shards and, if short, with universal ones.
static func pay(save: Dictionary, f: int, cost: int) -> bool:
	var fm := fam(save, f)
	if shards_for(save, f) < cost:
		return false
	var own := mini(int(fm["shards"]), cost)
	fm["shards"] = int(fm["shards"]) - own
	save["uni"] = int(save.get("uni", 0)) - (cost - own) * int(R["uniRate"])
	return true

static func unlock_cost(dex: int) -> int:
	return int(R["unlock"][clampi(int(Data.dex_by[dex]["rarity"]) - 1, 0, 4)])

## Can this missing form be unlocked with shards? (its family has the level)
static func can_unlock(save: Dictionary, dex: int) -> bool:
	return not owns(save, dex) and int(fam_of_dex(save, dex)["lv"]) >= req_level(dex) \
		and shards_for(save, fam_of(dex)) >= unlock_cost(dex)

static func unlock(save: Dictionary, dex: int) -> bool:
	if not can_unlock(save, dex) or not pay(save, fam_of(dex), unlock_cost(dex)):
		return false
	save["owned"][str(dex)] = {"at": Save.now_ms(), "from": "shards"}
	return true

static func complete(save: Dictionary, f: int) -> bool:
	for d in members(f):
		if Data.dex_by.has(d) and not owns(save, d):
			return false
	return true

static func can_star(save: Dictionary, f: int) -> bool:
	return complete(save, f) and int(fam(save, f)["stars"]) < int(R["stars"]) and shards_for(save, f) >= int(R["starCost"])

static func star(save: Dictionary, f: int) -> bool:
	if not can_star(save, f) or not pay(save, f, int(R["starCost"])):
		return false
	var fm := fam(save, f)
	fm["stars"] = int(fm["stars"]) + 1
	return true

# ---------------- saves from before the change ----------------

## JS unary plus for an upgrade level: numbers as they are, "4" -> 4, anything else 0.
static func _num(v: Variant) -> float:
	if v is int or v is float:
		return 0.0 if is_nan(float(v)) else float(v)
	if v is bool:
		return 1.0 if v else 0.0
	if v is String and (v as String).strip_edges().is_valid_float():
		return float(v)
	return 0.0

## The old upgrades (of the account, then of each Pokémon: save.upgrades / save.pupg, which no
## longer change) move to the new system losing nothing. Runs on every load (idempotent):
##   - trainer: of each upgrade, the highest level any Pokémon had;
##   - family: the level giving at least what its Strength, Reflexes, Critical Hit and Repertoire
##     gave (the best form of the family).
## Only the first time (`first`): Ban is gone and the coins it cost come back.
static func migrate(s: Dictionary, first: bool) -> void:
	if not (s.get("trainer") is Dictionary):
		s["trainer"] = {}
	if not (s.get("fams") is Dictionary):
		s["fams"] = {}
	var all := {"_acc": s["upgrades"] if s.get("upgrades") is Dictionary else {}}
	if s.get("pupg") is Dictionary:
		for d in s["pupg"]:
			all[str(d)] = s["pupg"][d]
	for d in all:
		var u: Dictionary = all[d] if all[d] is Dictionary else {}
		for id in R["trainer"]:
			var cur: float = _num(s["trainer"].get(id, 0))
			s["trainer"][id] = Save.ints(maxf(cur, _num(u.get(id, 0))))
		if d == "_acc" or not Save.valid_dex_key(d):
			continue
		var lv := maxi(1, maxi(1 + int(ceil(_num(u.get("atk", 0)) * 0.04 / float(R["atkLv"]))),
			maxi(1 + int(ceil(_num(u.get("cd", 0)) * 0.03 / float(R["cdLv"]))),
			maxi(1 + int(ceil(_num(u.get("crit", 0)) * 0.03 / float(R["critLv"]))),
			int(R["moves2Lv"]) if Save._truthy(u.get("moves")) else 1))))
		if lv > 1:
			var fm := fam(s, fam_of(int(d)))
			fm["lv"] = mini(int(R["cap"]), maxi(int(fm["lv"]), lv))
		if first:
			# JS: for (l = 0; l < min(3, +u.ban); l++)
			for l in int(ceil(minf(3.0, _num(u.get("ban", 0))))):
				s["coins"] = int(_num(s["coins"])) + Upgrades.cost("ban", l)
