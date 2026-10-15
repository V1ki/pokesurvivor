class_name FamiliesTests
extends RefCounted
## Trainer, families, evolution and shards (core/families.gd) against js/systems/families.js:
## data/test_vectors_p4.json "families", computed in tools/export_godot.js. Called from run_tests.gd.

static func run(t: Object) -> void:
	print("-- families (js/systems/families.js) --")
	var V: Dictionary = Data._json("test_vectors_p4.json").get("families", {}) if FileAccess.file_exists("res://data/test_vectors_p4.json") else {}
	if V.is_empty():
		t.check("test_vectors_p4.json has families", false, "run: node tools/export_godot.js")
		return
	var deq := Callable(Phase4Tests, "deq")
	var e: String = deq.call(Families.R, V["r"])
	t.check("Families.R == G.Families.R (every number)", e == "", e)
	var bad: Array = []
	for r in V["req"]:
		var d := int(r[0])
		var mine := [d, Families.fam_of(d), Families.req_level(d), Families.stage(d), 1 if Families.is_final(d) else 0]
		if deq.call(mine, r) != "":
			bad.append("%s vs %s" % [mine, r])
	t.check("family, evolution level, stage and last form of all %d species" % V["req"].size(), bad.is_empty(), str(bad.slice(0, 3)))
	bad = []
	for r in V["names"]:
		if Families.fam_name(Families.fam_of(int(r[0]))) != r[1]:
			bad.append(r)
	t.check("family names", bad.is_empty(), str(bad))
	bad = []
	for r in V["moves"]:
		var mine := Families.moves_of(int(r[0]))
		if deq.call(mine, r[1]) != "":
			bad.append("%d: %s vs %s" % [int(r[0]), mine, r[1]])
	t.check("moves_of (learnset, evolution, fill) of all %d species" % V["moves"].size(), bad.is_empty(), str(bad.slice(0, 2)))
	for g in V["known"]:
		bad = []
		for r in g["rows"]:
			var d := int(r[0])
			var s := Save.new_save("F")
			s["fams"] = {}
			Families.fam(s, Families.fam_of(d))["lv"] = int(g["lv"])
			var k := Families.known(s, d)
			var mine := [d, k, Families.start_moves(s, d, k), Families.shown(s, d).size(), Families.pool_of(d, k)]
			if deq.call(mine, r) != "":
				bad.append("%d: %s vs %s" % [d, mine, r])
		t.check("family level %d: known (with basic moves), start moves, shown, card pool of all %d species" % [int(g["lv"]), g["rows"].size()],
			bad.is_empty(), str(bad.slice(0, 2)))
	bad = []
	for c in V["perks"]:
		var s := Save.new_save("F")
		s["fams"] = {}
		s["trainer"] = (c["trainer"] as Dictionary).duplicate()
		var fm := Families.fam(s, Families.fam_of(int(c["dex"])))
		fm["lv"] = int(c["lv"])
		fm["stars"] = int(c["stars"])
		var mine := Families.perks(s, int(c["dex"]))
		# Godot's JSON reader can be 1-2 ulp off on decimals (tools/export_godot.js): compare with a tolerance
		for k in c["perks"]:
			if not mine.has(k) or absf(float(mine[k]) - float(c["perks"][k])) > 1e-9:
				bad.append("dex %d lv %d .%s: %s vs %s" % [int(c["dex"]), int(c["lv"]), k, mine.get(k), c["perks"][k]])
		if mine.size() != (c["perks"] as Dictionary).size():
			bad.append("dex %d: keys %s vs %s" % [int(c["dex"]), mine.keys(), c["perks"].keys()])
	t.check("perks: trainer upgrades + family level + stars (%d cases)" % V["perks"].size(), bad.is_empty(), str(bad))
	bad = []
	for r in V["bonus"]:
		if deq.call(Families.level_bonus(int(r[0])), r[1]) != "":
			bad.append(r)
	t.check("level_bonus", bad.is_empty(), str(bad))
	var s2 := Save.new_save("F")
	s2["fams"] = {}
	bad = []
	for c in V["xp"]:
		var r: Dictionary = Families.gain_xp(s2, 4, c["run"])
		var e3: String = deq.call(r, c["r"])
		if e3 == "":
			e3 = deq.call(Families.fam(s2, Families.fam_of(4)), c["fam"])
		if e3 != "":
			bad.append(e3)
	t.check("gain_xp: levels, leftover XP and the cap over %d runs" % V["xp"].size(), bad.is_empty(), str(bad))
	_pulls(t, V, deq)
	_unlock(t, V, deq)
	_sim_rules(t)

## The simulator's copy (debug/family_rules.gd, its own account format) gives the same moves.
static func _sim_rules(t: Object) -> void:
	var bad: Array = []
	for lv in [1, 20, 45]:
		for p in Data.dex:
			var d := int(p["dex"])
			var acc := {"fams": {str(FamilyRules.fam_of(d)): {"lv": lv, "xp": 0, "shards": 0, "stars": 0}}}
			var mv := FamilyRules.moves_of(acc, d)
			var s := Save.new_save("F")
			s["fams"] = {}
			Families.fam(s, Families.fam_of(d))["lv"] = lv
			var k := Families.known(s, d)
			if mv.map(func(e): return e[0]) != k.map(func(e): return e[0]) or FamilyRules.start_moves(acc, d, mv) != Families.start_moves(s, d, k):
				bad.append("%d at %d" % [d, lv])
	t.check("simulator rules (FamilyRules) == game rules (Families): moves and start moves", bad.is_empty(), str(bad.slice(0, 5)))

static func _pulls(t: Object, V: Dictionary, deq: Callable) -> void:
	var bad: Array = []
	for c in V["pulls"]:
		var s := Save.new_save("Shards")
		s["created"] = 1
		s["partner"] = 4
		s["coins"] = 1000
		s["tickets"] = {"t1": 400, "t10": 0}
		for d in [1, 4, 5, 7, 10, 13, 16, 19, 25]:
			s["owned"][str(d)] = {"at": 1, "from": "gacha"}
		var rng := Progress.Rng.new(str(c["seed"]))
		var rnd := func() -> float: return rng.next()
		var steps: Array = []
		for k in 30:
			var res := Gacha.pull(s, 10, 1, "t1", rnd)
			Families.after_pull(s, res)
			steps.append(res)
		var e: String = deq.call(steps, c["steps"])
		if e == "" and (int(s["coins"]) != int(c["coins"]) or int(s["uni"]) != int(c["uni"])):
			e = "coins %s/%s uni %s/%s" % [s["coins"], c["coins"], s["uni"], c["uni"]]
		if e == "":
			e = deq.call(s["fams"], c["fams"])
		if e != "":
			bad.append("%s: %s" % [c["seed"], e])
	t.check("after_pull: duplicates give family / universal shards, no coins (%d x 300 seeded pulls)" % V["pulls"].size(), bad.is_empty(), str(bad))

static func _unlock(t: Object, V: Dictionary, deq: Callable) -> void:
	var s := Save.new_save("Unlock")
	s["created"] = 1
	s["partner"] = 4
	s["owned"] = {"4": {"at": 5, "from": "starter"}}
	s["stats"]["famAt"] = 10
	var f := Families.fam_of(4)
	var log: Array = []
	var snap := func(what: String) -> void:
		var owned: Array = (s["owned"] as Dictionary).keys().map(func(k): return int(k))
		owned.sort()
		log.append([what, Families.usable(s, 4), Families.usable(s, 5), Families.usable(s, 6), Families.can_unlock(s, 5),
			Families.can_unlock(s, 6), Families.can_star(s, f), Families.shards_for(s, f), Families.fam(s, f).duplicate(), s["uni"], owned])
	snap.call("start")
	Families.fam(s, f)["shards"] = 15
	s["uni"] = 13
	snap.call("shards")
	log.append(["unlock5 lv1", Families.unlock(s, 5)])
	snap.call("after")
	Save.now_override = 1792000000000
	Families.fam(s, f)["lv"] = 16
	log.append(["unlock5 lv16", Families.unlock(s, 5)])
	snap.call("after")
	Families.fam(s, f)["lv"] = 36
	Families.fam(s, f)["shards"] = 100
	log.append(["unlock6", Families.unlock(s, 6)])
	Save.now_override = -1
	snap.call("after")
	for i in 4:
		log.append(["star", Families.star(s, f)])
	snap.call("stars")
	s["owned"]["150"] = {"at": 3, "from": "gacha"}
	s["owned"]["149"] = {"at": 30, "from": "gacha"}
	log.append(["legacy", Families.legacy(s, 150), Families.legacy(s, 149), Families.usable(s, 149), Families.req_level(149)])
	var e: String = deq.call(log, V["unlock"]["log"])
	if e == "":
		e = deq.call(s["owned"], V["unlock"]["owned"])
	t.check("unlock with shards (needs the family level), stars once complete, owned-before-famAt forms", e == "", e)
