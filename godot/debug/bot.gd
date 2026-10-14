class_name Bot
extends RefCounted
## Scripted input for headless runs: walk in big circles, steer away from enemies that get
## close and pick up gems when nothing is near. Deterministic given the simulation state.

## When true the bot also rotates the active move slot every 6 s (exercises every learned kind).
static var cycle_slots := false:
	set(v):
		cycle_slots = v
		_last_cycle = -1
static var _last_cycle := -1
## Phase 3b (--seek): head for the open rift, the lost Pokémon / its mark, thieves and unused
## interactables (altar, spring when hurt, locked chest, trap) instead of circling.
static var seek := false
static var _specials: Array[WorldProp] = []
static var _specials_t := -1.0

## Where the bot wants to go (world point) or null.
static func goal(sim: Sim) -> Variant:
	var pl := sim.player
	var rf := sim.rift
	if not rf.portal.is_empty() and not rf.in_arena:
		return Vector2(rf.portal["x"], float(rf.portal["y"]) - 10.0)
	if rf.in_arena:
		return null
	var L := sim.events.lost
	if L != null:
		return Vector2(L.x, L.y) if L.state == "wait" else Vector2(L.tx, L.ty)
	for e in sim.enemies.list:
		if e.behavior == "thief" and not e.dead:
			return Vector2(e.x, e.y)
	var best: Variant = null
	var bd := 1e18
	if absf(sim.time - _specials_t) > 0.5:
		_specials_t = sim.time
		_specials = Interact.cached_specials(sim.world, pl.x, pl.y, 1400.0)
	for p: WorldProp in _specials:
		if sim.world.broken.has(Vector2i(p.tx, p.ty)):
			continue
		if (p.type == "altar" and p.used) or (p.type == "spring" and (pl.hp >= pl.max_hp or p.charge < 0.2)):
			continue
		var d := U.dist2(pl.x, pl.y, p.x, p.y)
		if d < bd:
			bd = d
			best = Vector2(p.x, p.y - 8.0 if p.type == "spring" or p.type == "trap" else p.y + 6.0)
	return best

static func axis(sim: Sim) -> Vector2:
	var pl := sim.player
	if pl == null:
		return Vector2.ZERO
	if cycle_slots and pl.slots.size() > 1:
		var k := int(sim.time / 6.0)
		if k != _last_cycle:
			_last_cycle = k
			pl.set_active(k % pl.slots.size())
	if seek:
		var g: Variant = goal(sim)
		if g != null:
			var to := Vector2((g as Vector2).x - pl.x, (g as Vector2).y - pl.y)
			if to.length() > 4.0:
				return to.normalized()
	var a := sim.time * 0.25
	var v := Vector2(cos(a), sin(a)) * 0.6
	var flee := Vector2.ZERO
	var near := 0
	for e in sim.enemies.list:
		var d := U.dist(pl.x, pl.y, e.x, e.y)
		if d < 190.0 and d > 0.01:
			flee += Vector2(pl.x - e.x, pl.y - e.y) / d * (190.0 - d) / 190.0
			near += 1
	v += flee * 2.0
	# nothing close: go collect the nearest gem
	if near == 0:
		var best := 1e9
		var to := Vector2.ZERO
		for p in sim.pickups.list:
			var d := U.dist(pl.x, pl.y, p.x, p.y)
			if d < best and d < 400.0:
				best = d
				to = Vector2(p.x - pl.x, p.y - pl.y) / maxf(d, 0.01)
		v += to * 1.5
	return v.normalized() if v.length() > 0.01 else Vector2.ZERO

## Card choice for headless runs: upgrade known moves first, then stats, then new moves;
## keeps the starting move (slot 0) active so the ranged bot keeps hitting.
static func pick(sim: Sim) -> void:
	if sim.state == "choice" and not sim.bond_opt.is_empty():
		# bond picker: the first loose move(s)
		var o := sim.bond_opt
		var loose: Array = o["loose"]
		sim.choose_bond([loose[0]] if o["mode"] == "add" else [loose[0], loose[1]])
		return
	if sim.state == "choice":
		# held-item swap: take the new item, except never drop a Focus Sash
		sim.choose_item(0 if sim.item_choice[0] == "focussash" else 1)
		return
	var best := 0
	var best_score := -1
	for i in sim.offer.size():
		var c: Dictionary = sim.offer[i]
		var score: int = {"evo": 5, "up": 3, "stat": 2, "new": 1}.get(c["type"], 0)
		if c["type"] == "stat" and (c["key"] == "stat:hp" or c["key"] == "stat:rgn" or (c["key"] == "stat:heal" and sim.player.hp < sim.player.max_hp * 0.5)):
			score = 4
		if score > best_score:
			best_score = score
			best = i
	sim.pick_card(best)
	if not cycle_slots:
		sim.player.set_active(0)
