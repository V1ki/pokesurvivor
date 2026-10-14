class_name Bot
extends RefCounted
## Scripted input for headless runs (tests/sim_smoke.gd, tests/sim_play.gd) and main.gd --autoplay.
##
## Bot.profile (`--bot=<name>`, parsed by Autoshot2.debug_from_args):
##   legacy   the original test bot: big circles, push away from enemies that get close, gems when
##            nothing is near; always fires the first move. Cheap and stable: the unit tests, the
##            benchmark and the screenshot tools use it (it is the default).
##   novice / casual / expert   human-like players (PROFILES). They
##     - notice a NEW threat (telegraph, enemy shot, charger wind-up) only after a reaction time and
##       now and then overlook one (attention lapse), and only watch the N nearest enemies;
##     - re-plan a few times per second: every candidate direction (8 keys, or 16 for an analog
##       stick) is scored over the next 0.5-1 s against predicted enemy positions, telegraphs, shot
##       paths, walls / lava / traps, crowding, the active move's range, loot and goals;
##     - kite: drift sideways around the crowd instead of backing straight into the spawn ring;
##     - pick level-up cards, reroll and switch moves the way a player of that level would.
##   Their noise comes from their own RandomNumberGenerator (seeded from the world seed), never from
##   the game's randf() stream, so a run is reproducible for a given --seed and profile.

## Human-like profiles:
##   react      s before a new telegraph / shot / wind-up is noticed
##   think      s between two direction decisions (the key is held meanwhile)
##   dirs       8 = keyboard (WASD), 16 = analog stick
##   lapse      chance to overlook a given threat entirely
##   noise      execution error of the chosen direction (rad, normal sigma)
##   attention  nearest enemies tracked (bosses always)
##   see        how far threats and loot are noticed (wu; the view is ~768 wide)
##   margin     comfort gap kept from enemy bodies (wu)
##   horizon    how far ahead (s) a direction is judged
##   crowd      dislike of ending up among many enemies
##   tangent    taste for circling around the crowd (kiting) instead of running straight away
##   greed      pull of gems and drops (the best one in reach, unless enemies stand on it)
##   seek       goes for the rift, the lost Pokémon, thieves, and altars / springs / locked chests
##              within this distance (wu)
##   chest      [calm, abort]: walks to a locked chest with at most `calm` enemies near, then stays
##              by it until it opens (3.5 s) unless more than `abort` close in or HP drops below 35%
##   aim        cares about a clear line of fire: steps out from behind rocks / trees / walls that
##              would stop its shots (0 = never thinks about it)
##   switch     stay (keeps the selected move) · best (highest level move) · smart (+ boss / crowd)
##   cards      novice · casual · expert card taste (see _card_score)
##   buffs      stacks buff moves while it is calm
##   reroll     rerolls a bad hand of cards
##   shop       how it spends coins on permanent upgrades between runs (tests/sim_play.gd --campaign):
##              cheapest = always the cheapest one; casual / expert = best SHOP_W value per coin
const PROFILES := {
	"novice": {"react": 0.40, "think": 0.16, "dirs": 8, "lapse": 0.25, "noise": 0.25, "attention": 10,
		"see": 300.0, "margin": 18.0, "horizon": 0.5, "crowd": 0.5, "tangent": 0.0, "greed": 1.0,
		"seek": 350.0, "chest": [2, 4], "aim": 0.0, "switch": "stay", "cards": "novice", "buffs": false, "reroll": false,
		"shop": "cheapest"},
	"casual": {"react": 0.27, "think": 0.10, "dirs": 8, "lapse": 0.10, "noise": 0.12, "attention": 20,
		"see": 380.0, "margin": 28.0, "horizon": 0.8, "crowd": 1.0, "tangent": 0.35, "greed": 1.1,
		"seek": 900.0, "chest": [3, 6], "aim": 0.6, "switch": "best", "cards": "casual", "buffs": false, "reroll": true,
		"shop": "casual"},
	"expert": {"react": 0.18, "think": 0.05, "dirs": 16, "lapse": 0.02, "noise": 0.04, "attention": 40,
		"see": 460.0, "margin": 30.0, "horizon": 1.0, "crowd": 1.2, "tangent": 0.6, "greed": 1.3,
		"seek": 1200.0, "chest": [5, 8], "aim": 1.0, "switch": "smart", "cards": "expert", "buffs": true, "reroll": true,
		"shop": "expert"},
}

## Area moves (good in a crowd) and single-target ones (good on a boss), for "smart" switching.
const AOE := {"nova": true, "orbit": true, "aura": true, "melee": true, "cone": true, "meteor": true,
	"mine": true, "trail": true, "chain": true}
const SINGLE := {"projectile": true, "beam": true, "boomerang": true, "dash": true, "chain": true}

## What a level of each permanent upgrade is worth to a player (Bot.shop picks the best value per coin
## it can afford). "moves" (start with 2 moves) is one 1500-coin level; "ban" only matters while
## there are buff moves left to ban.
const SHOP_W := {
	"casual": {"hp": 1.0, "atk": 1.0, "spd": 0.5, "cd": 0.8, "def": 0.8, "regen": 0.6, "magnet": 0.4, "xp": 0.5,
		"coins": 0.4, "moves": 8.0, "crit": 0.7, "reroll": 0.4, "ban": 0.5},
	"expert": {"hp": 0.9, "atk": 1.3, "spd": 0.6, "cd": 1.2, "def": 0.9, "regen": 0.7, "magnet": 0.5, "xp": 0.8,
		"coins": 0.7, "moves": 14.0, "crit": 1.0, "reroll": 0.6, "ban": 1.0},
}

## legacy | novice | casual | expert
static var profile := "legacy"
## Overrides for the human profile's numbers (--bot-set=key=value,key=value; see set_overrides).
static var overrides: Dictionary = {}
## When true the legacy bot also rotates the active move slot every 6 s (exercises every learned kind).
static var cycle_slots := false:
	set(v):
		cycle_slots = v
		_last_cycle = -1
static var _last_cycle := -1
## Phase 3b (--seek): the legacy bot heads for the open rift, the lost Pokémon / its mark, thieves and
## unused interactables (altar, spring when hurt, locked chest, trap) instead of circling.
static var seek := false
static var _specials: Array[WorldProp] = []
static var _specials_t := -1.0

# human-like brain (reset when a new run starts)
static var _P: Dictionary = {}
static var _sim_id := 0
static var _last_t := 0.0
static var _rng := RandomNumberGenerator.new()
static var _salt := 0
static var _dir := Vector2.ZERO
static var _next_think := 0.0
static var _next_moves := 0.0
static var _buff_t := 0.0
static var _rerolled_lvl := -1
static var _wander_a := 0.0
static var _chest: WorldProp = null          # the locked chest it is waiting by
static var _id0 := 0                         # Enemy.next_id when the run started (run-local ids)

static func human() -> bool:
	return PROFILES.has(profile)

## "--bot-set" text -> overrides: "margin=20,buffs=false,chest=3/6" (numbers, true/false, a/b lists).
## Returns the keys it did not know (typos).
static func set_overrides(text: String) -> Array:
	overrides = {}
	var bad: Array = []
	for kv in text.split(",", false):
		var p := kv.split("=", true, 1)
		if p.size() < 2 or not (PROFILES["casual"] as Dictionary).has(p[0]):
			bad.append(kv)
			continue
		var v: String = p[1]
		if v == "true" or v == "false":
			overrides[p[0]] = v == "true"
		elif "/" in v:
			overrides[p[0]] = Array(v.split("/")).map(func(x): return float(x))
		elif v.is_valid_float():
			overrides[p[0]] = float(v)
		else:
			overrides[p[0]] = v
	_sim_id = 0
	return bad

## Where the legacy --seek bot wants to go (world point) or null.
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
	_refresh_specials(sim)
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

static func _refresh_specials(sim: Sim) -> void:
	if absf(sim.time - _specials_t) > 0.5:
		_specials_t = sim.time
		_specials = Interact.cached_specials(sim.world, sim.player.x, sim.player.y, 1400.0)

static func axis(sim: Sim) -> Vector2:
	if human():
		return _human_axis(sim)
	return _legacy_axis(sim)

## Card / item / bond choice for headless runs.
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
	if human():
		_sync(sim)
		_pick_human(sim)
		return
	_legacy_pick(sim)

# ================================ legacy bot ================================

static func _legacy_axis(sim: Sim) -> Vector2:
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

## Upgrade known moves first, then stats, then new moves; keeps the starting move (slot 0) active
## so the ranged bot keeps hitting.
static func _legacy_pick(sim: Sim) -> void:
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

# ================================ human-like bot ================================

## New run (or new Sim): reset the brain and seed its own RNG from the world seed.
static func _sync(sim: Sim) -> void:
	var id := sim.get_instance_id()
	if id == _sim_id and sim.time >= _last_t:
		_last_t = sim.time
		return
	_sim_id = id
	_last_t = sim.time
	_P = (PROFILES[profile] as Dictionary).duplicate()
	_P.merge(overrides, true)
	_salt = int(sim.world.seed) * 7919 + profile.hash()
	_rng.seed = _salt
	_dir = Vector2.ZERO
	_next_think = 0.0
	_next_moves = 0.0
	_buff_t = 0.0
	_rerolled_lvl = -1
	_wander_a = _rng.randf() * TAU
	_specials_t = -1.0
	_chest = null
	_id0 = Enemy.next_id

## Deterministic per threat: this player simply does not see that one. The id must be the same
## whatever ran before in this process (run-local ids, positions), so a seed + profile replays.
static func _lapsed(id: int) -> bool:
	return float(hash(id ^ _salt) & 1023) / 1024.0 < float(_P["lapse"])

static func _human_axis(sim: Sim) -> Vector2:
	var pl := sim.player
	if pl == null or pl.dead:
		return Vector2.ZERO
	_sync(sim)
	_manage_moves(sim)
	if sim.time >= _next_think:
		_next_think = sim.time + float(_P["think"]) * _rng.randf_range(0.8, 1.25)
		_dir = _plan(sim)
	return _dir

## Comfortable distance band [near, far] to the closest enemy for the active move.
static func _band(pl: Player) -> Vector2:
	var m := _main_of(pl.active_group())
	if m.is_empty():
		return Vector2(200.0, 420.0)          # a buff deals no damage: keep away
	var reach := Combat.reach(m)
	var close := pl.r + 24.0
	match m["kind"]:
		"melee", "aura":
			return Vector2(close, maxf(close + 10.0, reach * 0.8))
		"orbit":
			var rr := float(m.get("radius", 62.0))
			return Vector2(maxf(close, rr * 0.55), maxf(close + 10.0, rr * 1.1))
		"dash", "cone":
			return Vector2(60.0, reach * 0.85)
		"beam", "boomerang":
			return Vector2(90.0, reach * 0.8)
		"nova":
			return Vector2(70.0, 210.0)
		"chain", "trail", "mine", "turret":
			return Vector2(100.0, 250.0)
		"meteor":
			return Vector2(120.0, 300.0)
	return Vector2(130.0, 300.0)              # projectile

## Picks the direction for the next `think` seconds.
static func _plan(sim: Sim) -> Vector2:
	var P := _P
	var pl := sim.player
	var W := sim.world
	var s := maxf(pl.spd(), 1.0)
	var H: float = P["horizon"]
	var ts: Array[float] = [0.12, 0.3]
	if H > 0.5:
		ts.append(0.55)
	ts.append(H)
	var nt := ts.size()
	var wts: Array[float] = []                 # sooner = more urgent
	for t in ts:
		wts.append(1.6 - t)
	var react: float = P["react"]
	var see: float = P["see"]
	var margin: float = P["margin"]
	var fear := 7.0 / maxf(pl.hp, 12.0)       # a hit weighs more as HP drops
	var hurt_k := 1.0 - pl.hp / maxf(pl.max_hp, 1.0)
	var red := 1.0 - pl.reduction()

	# --- enemies in view: the N nearest (bosses always), their position over the next second ---
	var all: Array[Enemy] = []
	for e in sim.enemies.query_circle(pl.x, pl.y, see):
		if not e.dead:
			all.append(e)
	var px0 := pl.x
	var py0 := pl.y
	all.sort_custom(func(a: Enemy, b: Enemy) -> bool:
		return U.dist2(a.x, a.y, px0, py0) < U.dist2(b.x, b.y, px0, py0))
	var att: int = P["attention"]
	var foes: Array[Enemy] = []
	for i in all.size():
		if i < att or all[i].boss:
			foes.append(all[i])
	var nf := foes.size()
	var ex := PackedFloat32Array()
	var ey := PackedFloat32Array()
	ex.resize(nf * nt)
	ey.resize(nf * nt)
	var thr := PackedFloat32Array()
	var rad := PackedFloat32Array()
	thr.resize(nf)
	rad.resize(nf)
	var chargers: Array[Enemy] = []            # wind-up noticed: it will dash where you are
	var cx := 0.0
	var cy := 0.0
	var cw := 0.0
	var near_n := 0
	for i in nf:
		var e := foes[i]
		var dx := pl.x - e.x
		var dy := pl.y - e.y
		var d := maxf(0.01, sqrt(dx * dx + dy * dy))
		var still: bool = e.keeps_distance() or e.phase == "aim" or e.phase == "fuse" or not e.jump.is_empty() \
			or e.behavior == "thief"
		# where it heads: you (along its path), or for a runner where you will be (it leads your
		# smoothed velocity, like Enemy.update)
		var hx := dx
		var hy := dy
		var hd := d
		if e.behavior == "runner":
			var lead := clampf(d / maxf(60.0, e.spd), 0.0, 1.4)
			hx = pl.x + pl.vsx * lead - e.x
			hy = pl.y + pl.vsy * lead - e.y
			hd = maxf(0.01, sqrt(hx * hx + hy * hy))
		for k in nt:
			var t := ts[k]
			var qx := e.x
			var qy := e.y
			if e.phase == "dash" and not e.boss:
				var tt := minf(t, maxf(0.0, e.pt))
				qx += e.dash_x * e.spd * 3.4 * tt
				qy += e.dash_y * e.spd * 3.4 * tt
			elif not still:
				var step := minf(e.spd * t, maxf(0.0, hd - e.r - pl.r))
				qx += hx / hd * step
				qy += hy / hd * step
			ex[i * nt + k] = qx
			ey[i * nt + k] = qy
		thr[i] = 0.0 if e.behavior == "thief" else e.dmg * fear * red
		rad[i] = e.r + pl.r
		if e.behavior == "charger" and not e.boss and e.phase == "aim" and 0.55 - e.pt >= react and not _lapsed((e.id - _id0) * 31 + 7):
			chargers.append(e)
		if d < 260.0 and e.behavior != "thief":
			var w := 1.0 / (1.0 + d / 120.0)
			cx += e.x * w
			cy += e.y * w
			cw += w
			if d < 200.0:
				near_n += 1

	# --- telegraphs and shots that have been noticed ---
	var hz: Array = []
	for h in sim.hazards.list:
		if not h.hit and h.t >= react and not _lapsed(hash(Vector3i(int(h.x * 4.0), int(h.y * 4.0), int(h.delay * 1000.0)))):
			hz.append(h)
	var shots: Array = []
	for p in sim.projectiles.list:
		if p.friendly or p.t < react or _lapsed(p.id):
			continue
		if absf(p.x - pl.x) < see and absf(p.y - pl.y) < see:
			shots.append(p)

	# --- loot, traps and goals ---
	var loot: Array = []                       # [x, y, weight]
	for p in sim.pickups.list:
		if p.pulled or absf(p.x - pl.x) > 420.0 or absf(p.y - pl.y) > 420.0:
			continue
		var w := 0.0
		match p.kind:
			"xp":
				w = 1.0
			"xpBig":
				w = 1.6
			"coin":
				w = 0.5
			"heal":
				w = 0.3 + 4.5 * hurt_k
			"magnet":
				w = 2.0
			"bomb":
				w = 1.5 if near_n >= 6 else 0.6
			"ticket", "ticket10":
				w = 2.5
			"item":
				w = 3.0
		if w > 0.0:
			loot.append([p.x, p.y, w])
	var tgt := Vector2.INF                     # the pickup worth walking to
	var tgt_v := 0.0
	for l in loot:
		var lx: float = l[0]
		var ly: float = l[1]
		var crowd_at := 0.0
		for e in foes:
			if e.behavior != "thief" and U.dist2(lx, ly, e.x, e.y) < 90.0 * 90.0:
				crowd_at += 1.0
		var v: float = float(l[2]) / (1.0 + sqrt(U.dist2(pl.x, pl.y, lx, ly)) / 150.0) / (1.0 + crowd_at * float(P["crowd"]))
		if v > tgt_v:
			tgt_v = v
			tgt = Vector2(lx, ly)
	_refresh_specials(sim)
	var traps: Array = []
	for p: WorldProp in _specials:
		if p.type == "trap" and absf(p.x - pl.x) < 300.0 and absf(p.y - pl.y) < 300.0 \
				and not W.broken.has(Vector2i(p.tx, p.ty)):
			traps.append(Vector2(p.x, p.y - 8.0))
	var want: Array = _human_goal(sim, near_n, hurt_k)
	# waiting by a locked chest: keep within its reach until it opens (or it gets too hot)
	var hold := Vector2.INF
	var hold_r := 0.0
	if _chest != null:
		var ch := _chest
		var lim: Array = P["chest"]
		if W.broken.has(Vector2i(ch.tx, ch.ty)) or near_n > int(lim[1]) or hurt_k > 0.65:
			_chest = null
		else:
			hold = Vector2(ch.x, ch.y)
			hold_r = maxf(46.0, ch.r + pl.r + 24.0) - 8.0
	var cen := Vector2(cx / cw - pl.x, cy / cw - pl.y).normalized() if cw > 0.0 else Vector2.ZERO
	var press := minf(1.0, near_n / 5.0)
	var band := _band(pl)
	# shots that walls / rocks / trees stop: projectiles, boomerangs, cones (beams go through)
	var am := _main_of(pl.active_group())
	var aim_k: float = P["aim"] if not am.is_empty() and ["projectile", "boomerang", "cone", "chain"].has(am["kind"]) else 0.0
	var ranged: bool = not am.is_empty() and am["kind"] == "projectile"
	var reach: float = minf(Combat.reach(am), 420.0) if not am.is_empty() else 0.0
	var offense := 1.0 - 0.6 * hurt_k
	_wander_a += _rng.randf_range(-0.25, 0.35)
	var wander := Vector2.from_angle(_wander_a)
	var idle := nf == 0 and loot.is_empty() and want.is_empty()
	var types: Array = pl.mon["types"]

	# --- score every direction (and standing still) ---
	var dirs: int = P["dirs"]
	var best := Vector2.ZERO
	var best_c := INF
	var qxs := PackedFloat32Array()
	var qys := PackedFloat32Array()
	qxs.resize(nt)
	qys.resize(nt)
	for di in dirs + 1:
		var d := Vector2.ZERO if di == dirs else Vector2.from_angle(TAU * di / dirs)
		var c := 0.0
		# path: where you will be at each sample (it stops where a wall / solid prop is)
		var free_t := INF
		var lx := pl.x
		var ly := pl.y
		for k in nt:
			var nx := pl.x + d.x * s * ts[k]
			var ny := pl.y + d.y * s * ts[k]
			if free_t == INF and di != dirs and not W.is_free(nx, ny, pl.r * 0.75, true):
				free_t = ts[k - 1] if k > 0 else 0.0
				c += 2.0 if k == 0 else 1.2
			if free_t == INF:
				lx = nx
				ly = ny
			qxs[k] = lx
			qys[k] = ly
			if W.is_liquid(lx, ly):
				var le := W.liquid_effect(types)
				if le.has("dmg"):
					c += 6.0 * wts[k]
				elif not le.is_empty():
					c += 0.25 * wts[k]
			for tp: Vector2 in traps:
				if U.dist2(lx, ly, tp.x, tp.y) < 26.0 * 26.0:
					c += 3.0 * wts[k]
			# enemy bodies (predicted)
			for j in nf:
				var gx := lx - ex[j * nt + k]
				var gy := ly - ey[j * nt + k]
				var gap := sqrt(gx * gx + gy * gy) - rad[j]
				if gap < margin:
					var q := (margin - gap) / margin
					c += wts[k] * q * q * thr[j]
		# chargers: the dash goes where you are when the wind-up ends, then runs ~0.42 s
		for e in chargers:
			var a := _pos_at(pl, d, s, e.pt, free_t)
			var u := Vector2(a.x - e.x, a.y - e.y).normalized()
			for k in nt:
				if ts[k] < e.pt or ts[k] > e.pt + 0.5:
					continue
				var run := (ts[k] - e.pt) * e.spd * 3.4
				if U.dist2(qxs[k], qys[k], e.x + u.x * run, e.y + u.y * run) < pow(e.r + pl.r + 8.0, 2.0):
					c += wts[k] * (1.0 + e.dmg * fear * red * 1.5)
		# telegraphs: where you will be when it goes off
		for h in hz:
			var tt: float = h.delay - h.t
			var a := _pos_at(pl, d, s, minf(tt, H), free_t)
			if Hazards.inside(h, a.x, a.y, pl.r + 5.0):
				c += (1.0 if tt <= H else 0.45) * (2.0 + h.dmg * fear * red * 1.5)
		# shots: closest approach between consecutive samples
		var hit_r := pl.r + 5.0
		for p in shots:
			var life: float = p.life - p.t
			var t0 := 0.0
			var ax := pl.x
			var ay := pl.y
			for k in nt:
				var t1 := minf(ts[k], life)
				if t1 <= t0:
					break
				var span := t1 - t0
				var rx: float = ax - (p.x + p.vx * t0)
				var ry: float = ay - (p.y + p.vy * t0)
				var wx: float = (qxs[k] - ax) / (ts[k] - t0) - p.vx
				var wy: float = (qys[k] - ay) / (ts[k] - t0) - p.vy
				var ww := wx * wx + wy * wy
				var u := clampf(-(rx * wx + ry * wy) / ww, 0.0, span) if ww > 1e-6 else 0.0
				var mx := rx + wx * u
				var my := ry + wy * u
				if mx * mx + my * my < pow(p.r + hit_r, 2.0):
					c += wts[k] * (1.0 + p.dmg * fear * red * 1.2)
					break
				t0 = t1
				ax = qxs[k]
				ay = qys[k]
		# where you end up: crowding, corners, range, loot, goal
		var endx := qxs[nt - 1]
		var endy := qys[nt - 1]
		var dens := 0.0
		var nearest := INF
		for j in nf:
			var e := foes[j]
			if e.behavior == "thief":
				continue
			var dd := sqrt(U.dist2(endx, endy, e.x, e.y))
			dens += (2.5 if e.boss else 1.0) / (1.0 + (dd / 110.0) * (dd / 110.0))
			nearest = minf(nearest, dd - e.r)
		c += float(P["crowd"]) * dens * 0.3
		if near_n > 0:
			var walls := 0
			for a in 8:
				if not W.is_free(endx + cos(a * PI / 4.0) * 72.0, endy + sin(a * PI / 4.0) * 72.0, 10.0, true):
					walls += 1
			c += walls * 0.12 * minf(1.0, near_n / 4.0)
		if cen != Vector2.ZERO and di != dirs:
			c += maxf(0.0, d.dot(cen)) * 0.9 * press
			c -= float(P["tangent"]) * absf(d.cross(cen)) * press * 0.6
		if aim_k > 0.0 and nf > 0:
			var tg := _aim_target(foes, endx, endy, ranged)
			if tg != null and U.dist2(endx, endy, tg.x, tg.y) < reach * reach \
					and _fire_blocked(W, endx, endy, tg.x, tg.y, tg.r):
				c += 0.9 * aim_k * offense
		if nearest < INF:
			if nearest < band.x:
				c += (band.x - nearest) / band.x * 0.7 * offense
			elif nearest > band.y:
				c += minf(1.0, (nearest - band.y) / 220.0) * 0.35 * offense
		var gain := 0.0
		for l in loot:
			gain += float(l[2]) / (1.0 + sqrt(U.dist2(endx, endy, l[0], l[1])) / 90.0)
		c -= float(P["greed"]) * 0.25 * minf(gain, 4.0)
		if tgt != Vector2.INF:
			c += float(P["greed"]) * sqrt(U.dist2(endx, endy, tgt.x, tgt.y)) / 250.0
		if hold != Vector2.INF:
			var hd := sqrt(U.dist2(endx, endy, hold.x, hold.y))
			if hd > hold_r:
				c += 2.5 + (hd - hold_r) / 40.0
		elif not want.is_empty():
			var g: Vector2 = want[0]
			c += float(want[1]) * sqrt(U.dist2(endx, endy, g.x, g.y)) / 400.0
		if idle:
			c += 0.3 * (1.0 - d.dot(wander))
		# holding a direction is easier than flicking to another one
		c += 0.12 * (1.0 - d.dot(_dir)) if _dir != Vector2.ZERO else (0.05 if di != dirs else 0.0)
		if c < best_c:
			best_c = c
			best = d
	# execution error (with keys the result is still one of the 8 directions)
	if best != Vector2.ZERO:
		var a := best.angle() + _rng.randfn(0.0, float(P["noise"]))
		if dirs <= 8:
			a = roundf(a / (PI / 4.0)) * (PI / 4.0)
		best = Vector2.from_angle(a)
	return best

## The enemy Player.update would aim at from (x, y): for a projectile the boss within 330, else the
## one touching you, else the closest (approximation of its targeting).
static func _aim_target(foes: Array[Enemy], x: float, y: float, ranged: bool) -> Enemy:
	var best: Enemy = null
	var bd := INF
	for e in foes:
		if e.behavior == "thief":
			continue
		var d := U.dist2(x, y, e.x, e.y)
		if ranged and e.boss and d < 330.0 * 330.0:
			return e
		if d < bd:
			bd = d
			best = e
	return best

## Would a shot from (x0, y0) to an enemy at (x1, y1) be stopped by a wall or a solid prop?
static func _fire_blocked(W: WorldMap, x0: float, y0: float, x1: float, y1: float, er: float) -> bool:
	var dx := x1 - x0
	var dy := y1 - y0
	var d := sqrt(dx * dx + dy * dy)
	if d < 1.0:
		return false
	var n := int((d - er) / 14.0)
	for i in range(1, n + 1):
		var t := i * 14.0 / d
		if W.projectile_block(x0 + dx * t, y0 + dy * t, 5.0) != "":
			return true
	return false

## Where you are after `t` s walking along d (you stop at free_t, where the path is blocked).
static func _pos_at(pl: Player, d: Vector2, s: float, t: float, free_t: float) -> Vector2:
	var k := clampf(minf(t, free_t), 0.0, 10.0) * s
	return Vector2(pl.x + d.x * k, pl.y + d.y * k)

## [point, weight] the player is drawn to, or []: the open rift, the lost Pokémon (or its mark), a
## thief, an unused altar, a spring when hurt, a locked chest when it is quiet. Never a trap.
static func _human_goal(sim: Sim, near_n: int, hurt_k: float) -> Array:
	var pl := sim.player
	var seek_r: float = _P["seek"]
	var calm: int = (_P["chest"] as Array)[0]
	var rf := sim.rift
	if rf.in_arena:
		return []
	if not rf.portal.is_empty():
		# the big pulsing arrow: everybody heads there, in more of a hurry as it is about to close
		return [Vector2(rf.portal["x"], float(rf.portal["y"]) - 10.0), 2.6 if float(rf.portal["ttl"]) > 20.0 else 4.0]
	var L := sim.events.lost
	if L != null:
		return [Vector2(L.x, L.y) if L.state == "wait" else Vector2(L.tx, L.ty), 1.2]
	for e in sim.enemies.list:
		if e.behavior == "thief" and not e.dead and U.dist2(pl.x, pl.y, e.x, e.y) < 600.0 * 600.0:
			return [Vector2(e.x, e.y), 1.0]
	var best: Array = []
	var bd := INF
	for p: WorldProp in _specials:
		if sim.world.broken.has(Vector2i(p.tx, p.ty)):
			continue
		var w := 0.0
		var at := Vector2(p.x, p.y + 6.0)
		match p.type:
			"altar":
				w = 0.0 if p.used else 0.8
			"spring":
				w = 0.6 + 1.5 * hurt_k if hurt_k > 0.3 and p.charge > 0.2 else 0.0
				at = Vector2(p.x, p.y - 8.0)
			"bigchest":
				w = 0.9 if near_n <= calm and hurt_k < 0.6 else 0.0
				# arrived: wait by it until it opens
				if w > 0.0 and U.dist2(pl.x, pl.y, p.x, p.y) < pow(maxf(46.0, p.r + pl.r + 24.0) - 4.0, 2.0):
					_chest = p
		if w <= 0.0:
			continue
		var d := sqrt(U.dist2(pl.x, pl.y, at.x, at.y))
		if d < seek_r and d / w < bd:
			bd = d / w
			best = [at, w]
	return best

# ---------------- between runs: the upgrade shop ----------------

## Spends `coins` on permanent upgrades the way this profile's player would (Upgrades.cost, max
## levels); `levels` is updated in place. bans_left = buff moves that a Veto level could still
## block. Returns {coins: left, bought: [ids in order]}.
static func shop(levels: Dictionary, coins: int, bans_left: int) -> Dictionary:
	var P: Dictionary = (PROFILES.get(profile, PROFILES["casual"]) as Dictionary).duplicate()
	P.merge(overrides, true)
	var style: String = P.get("shop", "casual")
	var bought: Array = []
	while true:
		var best := ""
		var best_v := -INF
		for u in Upgrades.list():
			var id: String = u["id"]
			var lvl := int(levels.get(id, 0))
			if lvl >= int(u["max"]) or (id == "ban" and lvl >= bans_left):
				continue
			var cost := Upgrades.cost(id, lvl)
			if cost > coins:
				continue
			var v: float = -float(cost) if style == "cheapest" else float(SHOP_W[style].get(id, 0.5)) / cost
			if v > best_v:
				best_v = v
				best = id
		if best == "":
			break
		coins -= Upgrades.cost(best, int(levels.get(best, 0)))
		levels[best] = int(levels.get(best, 0)) + 1
		bought.append(best)
	return {"coins": coins, "bought": bought}

## The moves a player blocks with Veto: the buff moves of the partner's pool (they deal no damage).
static func bans_for(mon: Dictionary) -> Array:
	return Moves.pool_for(mon).filter(func(id): return Moves.def(id).get("kind", "") == "buff")

# ---------------- moves ----------------

## The first damaging move of a slot group, or {} for a buff-only slot.
static func _main_of(g: Array) -> Dictionary:
	for m in g:
		if m["kind"] != "buff":
			return m
	return {}

## How much a player trusts a move: the one they upgraded most (evolved even more).
static func _move_rank(m: Dictionary) -> float:
	return int(m["lvl"]) * 10.0 + (25.0 if m.get("evolved", false) else 0.0)

static func _manage_moves(sim: Sim) -> void:
	var pl := sim.player
	if pl.slots.size() < 2 or sim.time < _next_moves:
		return
	_next_moves = sim.time + 0.25
	var mode: String = _P["switch"]
	var cur := _main_of(pl.active_group())
	if mode == "stay":
		# keeps whatever is selected (a new move selects itself); only after a few seconds notices
		# that a buff deals no damage
		if cur.is_empty():
			_buff_t += 0.25
			if _buff_t > 4.0:
				_buff_t = 0.0
				pl.set_active(_best_slot(sim, "best"))
		else:
			_buff_t = 0.0
		return
	if _P["buffs"] and _stack_buff(sim):
		return
	var bi := _best_slot(sim, mode)
	if bi != pl.active:
		pl.set_active(bi)

## Expert: switch to a buff move while nothing is close, until its stacks are full.
static func _stack_buff(sim: Sim) -> bool:
	var pl := sim.player
	var calm := sim.enemies.query_circle(pl.x, pl.y, 230.0).filter(func(e: Enemy) -> bool:
		return not e.dead and e.behavior != "thief").is_empty()
	for i in pl.slots.size():
		var g: Array = pl.slots[i]
		if not _main_of(g).is_empty():
			continue
		var bm: Dictionary = g[0]
		var b: Dictionary = pl.buffs.get(bm.get("stat", ""), {})
		var full := int(b.get("n", 0)) >= int(bm.get("stacks", 5)) and float(b.get("t", 0.0)) > 3.0
		if calm and not full:
			if pl.active != i:
				pl.set_active(i)
			return true
	return false

static func _best_slot(sim: Sim, mode: String) -> int:
	var pl := sim.player
	var boss := false
	var crowd := 0
	if mode == "smart":
		for e in sim.enemies.query_circle(pl.x, pl.y, 420.0):
			if e.dead:
				continue
			if e.boss:
				boss = true
			elif U.dist2(pl.x, pl.y, e.x, e.y) < 200.0 * 200.0:
				crowd += 1
	var best_i := pl.active
	var best_s := -INF
	for i in pl.slots.size():
		var g: Array = pl.slots[i]
		var m := _main_of(g)
		if m.is_empty():
			continue
		var sc := _move_rank(m) + (g.size() - 1) * 15.0          # a fused slot fires several moves
		if boss and SINGLE.has(m["kind"]):
			sc += 12.0
		if crowd >= 7 and AOE.has(m["kind"]):
			sc += 12.0
		if i == pl.active:
			sc += 4.0                                            # no flicking back and forth
		if sc > best_s:
			best_s = sc
			best_i = i
	return best_i

# ---------------- level-up cards ----------------

static func _pick_human(sim: Sim) -> void:
	var pl := sim.player
	if sim.offer.is_empty():
		return
	var sc: Array[float] = []
	for c in sim.offer:
		sc.append(_card_score(c, pl))
	var best := 0
	for i in sc.size():
		if sc[i] > sc[best]:
			best = i
	if _P["reroll"] and sc[best] < 2.6 and sim.rerolls_left() > 0 and _rerolled_lvl != pl.level:
		_rerolled_lvl = pl.level
		if sim.reroll():
			_pick_human(sim)
			return
	if _P["cards"] == "novice":
		# goes for what looks exciting rather than what is best
		var tot := 0.0
		for v in sc:
			tot += v * v
		var r := _rng.randf() * tot
		for i in sc.size():
			r -= sc[i] * sc[i]
			if r <= 0.0:
				best = i
				break
	sim.pick_card(best)

static func _card_score(c: Dictionary, pl: Player) -> float:
	var style: String = _P["cards"]
	var key: String = c["key"]
	var hurt := 1.0 - pl.hp / maxf(pl.max_hp, 1.0)
	var dmg_moves := 0
	var main := {}
	for m in pl.moves:
		if m["kind"] == "buff":
			continue
		dmg_moves += 1
		if main.is_empty() or _move_rank(m) > _move_rank(main):
			main = m
	match str(c["type"]):
		"evo":
			return 100.0
		"up":
			var id := key.substr(3)
			var m := {}
			for mm in pl.moves:
				if mm["id"] == id:
					m = mm
			if m.is_empty() or m["kind"] == "buff":
				return 2.0 if style == "novice" else 1.0
			if style == "novice":
				return 3.0
			if not main.is_empty() and main["id"] == id:
				return 6.0 if style == "casual" else 7.0
			return 3.5 if style == "casual" else 3.0
		"new":
			var d := Moves.def(key.substr(4))
			var buff: bool = d.get("kind", "") == "buff"
			if style == "novice":
				return 2.5 if buff else 4.0
			if buff:
				return 0.8 if style == "casual" else (1.6 if dmg_moves >= 2 else 0.6)
			if dmg_moves < 2:
				return 5.0 if style == "casual" or AOE.has(d.get("kind", "")) else 4.0
			if dmg_moves < 3:
				return 3.5 if style == "casual" else 2.2
			return 1.5 if style == "casual" else 0.8
		"stat":
			var sid := key.substr(5)
			for m in pl.moves:
				var ev := Moves.evo_info(m, pl.stats_taken)
				if not ev.is_empty() and not ev["ready"] and ev["needs"] == sid:
					return {"novice": 3.0, "casual": 5.0}.get(style, 8.0)
			if style == "novice":
				return 0.5 + 6.0 * hurt if sid == "heal" else (2.5 if sid == "hp" else 2.0)
			var ex := style == "expert"
			var v := 0.0
			match sid:
				"heal":
					v = 7.0 * hurt if hurt > 0.45 else 0.3
				"hp":
					v = 2.0 + 3.0 * hurt
				"def":
					v = 3.2 if ex else 2.5
				"rgn":
					v = 2.6 if ex else 2.0
				"atk":
					v = 4.5 if ex else 3.0
				"cd":
					v = 4.5 if ex else 3.0
				"spd":
					v = 3.0 if ex else 2.2
				"mag":
					v = 2.0 if ex else 1.4
				"xp":
					v = (2.6 if pl.level < 12 else 1.2) if ex else 1.4
			# an expert takes the stat its main move will need to evolve before it is maxed
			if ex and not main.is_empty() and int(main["lvl"]) >= 3 and Data.evo.has(main["id"]) \
					and str(Data.evo[main["id"]][1]) == sid and int(pl.stats_taken.get(sid, 0)) == 0:
				v += 2.5
			return v
	return 1.0
