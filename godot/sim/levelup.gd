class_name LevelUp
extends RefCounted
## The three level-up cards (js/systems/levelup.js). Card = Dictionary
## {w, type: new|evo|up|stat, key, icon, color, tag, title, desc, apply: Callable(Player)}.

## Stat card effects (LevelUp.STATS apply functions; data/max come from levelup_stats.json).
static func apply_stat(id: String, pl: Player) -> void:
	match id:
		"hp":
			pl.add_max_hp(20.0)
		"atk":
			pl.atk_mul *= 1.10
		"spd":
			pl.spd_mul *= 1.07
		"cd":
			pl.cd_mul *= 0.92
		"def":
			pl.dmg_reduce = minf(0.7, pl.dmg_reduce + 0.06)
		"rgn":
			pl.regen_flat += 0.9
		"mag":
			pl.magnet *= 1.30
		"xp":
			pl.xp_mul *= 1.12
		"heal":
			pl.heal(pl.max_hp * 0.45)

static func _apply_stat_card(p: Player, sid: String) -> void:
	apply_stat(sid, p)
	p.stats_taken[sid] = int(p.stats_taken.get(sid, 0)) + 1

static func _apply_evo(p: Player, m: Dictionary) -> void:
	Moves.evolve(m)
	Progress.event("evolve", {"move": m["id"]})      # JS levelup.js:68
	Sim.cur.fx.ring(p.x, p.y, 8.0, 120.0, Color.html("#ffd23f"), 0.8, 6.0)
	Sim.cur.fx.burst(p.x, p.y - p.body_h * 0.5, Color.html("#ffe14d"), 40, 240.0)
	Sfx.play("legend")

static func candidates(pl: Player) -> Array:
	var out: Array = []

	# --- new moves (only while a slot is free) ---
	if pl.slots.size() < pl.max_moves:
		# with 2 buff moves no more are offered (they deal no damage)
		var buffs := 0
		for m in pl.moves:
			if m["kind"] == "buff":
				buffs += 1
		var pool: Array = []
		for id in Moves.pool_for(pl.mon):
			var d := Moves.def(id)
			if pl.has_move(id) or pl.banned.has(id):
				continue
			if buffs >= 2 and d["kind"] == "buff":
				continue
			pool.append(id)
		for id in U.pick_n(pool, 6):
			var d := Moves.def(id)
			var mid: String = id
			out.append({"w": 10.0, "type": "new", "key": "new:" + mid, "icon": "move:" + mid,
				"color": Data.tcolor(d["type"]), "tag": Data.type_name.get(d["type"], d["type"]),
				"title": d["name"], "desc": d["desc"],
				"apply": func(p: Player): p.add_move(mid)})

	# --- evolutions: maxed move + its stat taken this run ---
	var waiting := {}
	for m in pl.moves:
		var ev := Moves.evo_info(m, pl.stats_taken)
		if ev.is_empty():
			continue
		if not ev["ready"]:
			waiting[ev["needs"]] = m
			continue
		var mm: Dictionary = m
		out.append({"w": 40.0, "type": "evo", "key": "evo:" + str(m["id"]), "icon": "move:" + str(m["id"]),
			"color": Color.html("#ffd23f"), "tag": "EVOLUCIÓN",
			"title": str(m["name"]) + " → " + str(ev["name"]), "desc": ev["text"],
			"apply": func(p: Player): _apply_evo(p, mm)})

	# --- upgrades of known moves ---
	for m in pl.moves:
		var txt := Moves.next_up_text(m)
		if txt == "":
			continue
		var mm: Dictionary = m
		out.append({"w": 8.0, "type": "up", "key": "up:" + str(m["id"]), "icon": "move:" + str(m["id"]),
			"color": Data.tcolor(m["type"]), "tag": "Nv.%d > %d" % [int(m["lvl"]), int(m["lvl"]) + 1],
			"title": m["name"], "desc": txt,
			"apply": func(_p: Player): Moves.level_up(mm)})

	# --- stats (capped by `max`; the ones an evolution waits for always appear) ---
	var free_stats: Array = []
	var wait_stats: Array = []
	for s in Data.levelup_stats:
		var sid: String = s["id"]
		if waiting.has(sid):
			wait_stats.append(s)
		elif not s.has("max") or int(pl.stats_taken.get(sid, 0)) < int(s["max"]):
			free_stats.append(s)
	for s in U.pick_n(free_stats, 5) + wait_stats:
		var sid: String = s["id"]
		var evo_for: Variant = waiting.get(sid)
		var w := 14.0 if evo_for != null else (4.0 if pl.slots.size() < pl.max_moves else 7.0)
		out.append({"w": w, "type": "stat", "key": "stat:" + sid, "icon": s["icon"],
			"color": Color.html("#ffd23f") if evo_for != null else Color.html("#8fa3c4"),
			"tag": ("Evoluciona " + str(evo_for["name"])) if evo_for != null else "Mejora",
			"title": s["title"], "desc": s["desc"],
			"apply": func(p: Player): _apply_stat_card(p, sid)})
	return out

## Up to n distinct cards picked by weight; a ready evolution card always comes first.
static func offer(pl: Player, n := 3) -> Array:
	var pool := candidates(pl)
	var picked: Array = []
	var used := {}
	for i in pool.size():
		if pool[i]["type"] == "evo":
			var c: Dictionary = pool.pop_at(i)
			used[c["key"]] = true
			picked.append(c)
			break
	while picked.size() < n and not pool.is_empty():
		var total := 0.0
		for c in pool:
			total += float(c["w"])
		var r := randf() * total
		var idx := 0
		for i in pool.size():
			r -= float(pool[i]["w"])
			if r <= 0.0:
				idx = i
				break
		var c: Dictionary = pool.pop_at(idx)
		if used.has(c["key"]):
			continue
		used[c["key"]] = true
		picked.append(c)
	return picked
