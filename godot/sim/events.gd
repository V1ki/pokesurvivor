class_name Events
extends RefCounted
## Mid-run events and treasure thieves (js/systems/events.js).
## Every 4-5 min (never with a boss alive, never in a rift arena) one of these happens:
##   horde  30 s in which every spawn is of one type
##   gold   golden hour: 30 s of golden enemies (double XP, sometimes coins)
##   lost   a lost Pokémon: touch it, it follows you, lead it to the green mark. Enemies hurt
##          it; if it falls (or you take over 2 min) it leaves. Reward: half your HP, coins, a
##          ticket and, 1 time in 5, it joins your collection (Sim.on_rescue).
## Treasure thieves (max 2 per run, Enemy behavior "thief"): a Meowth full of coins (or, 1 in 4,
## a Gholdengo with a ×10 ticket) that runs away and escapes after 15 s.
## All randomness goes through `rng` (Math.random order of the JS code, for the reference tests).

const EVERY := [240.0, 300.0]
const DUR := 30.0
const LOST_TIME := 120.0
const THIEF_FIRST := [120.0, 240.0]
const THIEF_NEXT := [240.0, 360.0]
const THIEF_LIFE := 15.0

## The lost Pokémon (a Body: it collides with the terrain while following you).
class Lost extends Body:
	var dex := 0
	var name := ""
	var hp := 100.0
	var max_hp := 100.0
	var state := "wait"          # wait | follow
	var follow: Player = null
	var tx := 0.0                # the green mark (goal)
	var ty := 0.0
	var t := 0.0
	var anim: PmdAnimator
	var hit_cd := 0.0
	var grant := false           # joins your collection when rescued
	var moving := false
	var flash := 0.0

var rng := StreamRng.new()
var next_t := 0.0
var cur: Dictionary = {}         # {id, t, dur, type?, defs?}; empty = no event
var last := ""
var thief_t := 0.0
var thieves := 0
var lost: Lost = null
## Debug triggers (Sim._apply_debug, --event=...): [[at_s, id], ...] started in order.
var debug_queue: Array = []
## Log of what happened (tests, smoke stats): [time, what, detail].
var history: Array = []
var _time := 0.0

func reset() -> void:
	next_t = rng.rand(EVERY[0], EVERY[1])
	cur = {}
	last = ""
	lost = null
	thief_t = rng.rand(THIEF_FIRST[0], THIEF_FIRST[1])
	thieves = 0
	history = []
	debug_queue = []

func golden() -> bool:
	return not cur.is_empty() and cur["id"] == "gold"

func current() -> String:
	return "" if cur.is_empty() else str(cur["id"])

## Spawn bag during a horde (Spawner.spawn_one), else [].
func bag() -> Array:
	if not cur.is_empty() and cur["id"] == "horde" and not (cur["defs"] as Array).is_empty():
		return cur["defs"]
	return []

# ---------------- cycle ----------------

func update(dt: float, pl: Player, time: float) -> void:
	_time = time
	if not cur.is_empty():
		cur["t"] = float(cur["t"]) + dt
		if cur["id"] != "lost" and float(cur["t"]) >= float(cur["dur"]):
			end()
	if lost != null:
		_lost_tick(dt, pl)
	var S := Sim.cur
	if S.rift.in_arena:
		return
	_debug_tick(pl, time)

	if thieves < 2:
		thief_t -= dt
		if thief_t <= 0.0:
			if S.enemies.boss_alive():
				thief_t = 8.0
			else:
				spawn_thief(pl, time)
				thieves += 1
				thief_t = rng.rand(THIEF_NEXT[0], THIEF_NEXT[1])

	if not cur.is_empty():
		return
	next_t -= dt
	if next_t > 0.0:
		return
	if S.enemies.boss_alive():
		next_t = 10.0
		return
	next_t = rng.rand(EVERY[0], EVERY[1])
	var ids := ["horde", "gold", "lost"].filter(func(id): return id != last)
	start(rng.pick(ids), time, pl)

func _debug_tick(pl: Player, time: float) -> void:
	if debug_queue.is_empty() or time < float(debug_queue[0][0]):
		return
	var id: String = debug_queue[0][1]
	if id == "thief":
		debug_queue.pop_front()
		spawn_thief(pl, time)
		return
	if not cur.is_empty():
		return                       # wait for the running event to end
	debug_queue.pop_front()
	start(id, time, pl)

func start(id: String, time: float, pl: Player) -> void:
	var S := Sim.cur
	last = id
	if id == "horde":
		var types := EnemyDefs.horde_types(time)
		if types.is_empty():
			start("gold", time, pl)
			return
		var type: String = rng.pick(types)
		var defs := EnemyDefs.horde_defs(type, time, rng)
		if S.render:
			Sprites.preload_dex(defs.map(func(d): return d["dex"]))
		cur = {"id": id, "t": 0.0, "dur": DUR, "type": type, "defs": defs}
		S.spawner.burst(6)
	elif id == "gold":
		cur = {"id": id, "t": 0.0, "dur": DUR}
		for e in S.enemies.list:
			e.make_golden()
	else:
		if not spawn_lost(pl):
			return
		cur = {"id": id, "t": 0.0, "dur": INF}
	history.append([time, id, cur.get("type", lost.dex if lost != null and id == "lost" else "")])
	announce()

func announce() -> void:
	if cur.is_empty():
		return
	var S := Sim.cur
	if cur["id"] == "horde":
		S.spawner.say("¡Horda de tipo " + str(Data.type_name.get(cur["type"], cur["type"])) + "!", 3.0)
	elif cur["id"] == "gold":
		S.spawner.say("¡Hora dorada! Doble de experiencia", 3.0)
	elif lost != null:
		S.spawner.say("¡Un " + lost.name + " se ha perdido! Búscalo y llévalo a la marca", 3.4)
	Sfx.play("shiny" if cur["id"] == "gold" else "surge")

func end() -> void:
	cur = {}

# ---------------- treasure thief ----------------

func spawn_thief(pl: Player, time: float) -> void:
	var S := Sim.cur
	var gold := rng.next() < 0.25
	var dex := 1000 if gold else 52
	var mon: Dictionary = Data.dex_by.get(dex, {})
	if mon.is_empty() or not Sprites.has_sprite_meta(dex):
		return
	rng.pick([pl])                   # JS picks a living player (one draw)
	if S.render:
		Sprites.preload_dex([dex])
	var def := {"dex": dex, "name": mon["name"], "behavior": "thief",
		"hp": U.jround(60.0 * (1.0 + time / 95.0) * (1.5 if gold else 1.0)),
		"spd": 92.0, "dmg": 0.0, "xp": 10.0, "loot": "ticket10" if gold else "coins"}
	for i in 12:
		var a := rng.next() * U.TAU_JS
		var d := rng.rand(230.0, 300.0)
		var x := pl.x + cos(a) * d
		var y := pl.y + sin(a) * d * 0.8
		if not S.world.is_free(x, y, 14.0):
			continue
		var e := Enemy.new(def, x, y, {"hp": 1.0, "spd": 1.0, "dmg": 1.0})
		e.life = THIEF_LIFE
		S.enemies.add(e)
		S.fx.ring(x, y, 4.0, 40.0, Color.html("#ffd23f"), 0.5, 3.0)
		S.spawner.say(("¡Un " + e.name + " con un ticket ×10! ¡Atrápalo antes de que huya!") if gold
			else ("¡Un " + e.name + " cargado de monedas! ¡Atrápalo antes de que huya!"), 3.2)
		Sfx.play("shiny")
		history.append([time, "thief", dex, int(def["hp"]), x, y])
		return

# ---------------- lost Pokémon ----------------

## Species that can get lost: up to 4★, not legendary, with sprites, walking (not hovering).
static func lost_pool() -> Array:
	return Data.dex.filter(func(p): return float(p["rarity"]) <= 3.0 and not p.get("leg", false) \
		and Sprites.has_sprite_meta(int(p["dex"])) and not Sprites.hovers(int(p["dex"])))

func spawn_lost(pl: Player) -> bool:
	var S := Sim.cur
	rng.pick([pl])                   # JS picks a living player (one draw)
	var mon: Dictionary = rng.pick(lost_pool())
	var at: Array = []
	var to: Array = []
	var i := 0
	while i < 20 and at.is_empty():
		var a := rng.next() * U.TAU_JS
		var d := rng.rand(220.0, 300.0)
		var x := pl.x + cos(a) * d
		var y := pl.y + sin(a) * d * 0.8
		if S.world.is_free(x, y, 16.0):
			at = [x, y]
		i += 1
	i = 0
	while i < 30 and not at.is_empty() and to.is_empty():
		var a := rng.next() * U.TAU_JS
		var d := rng.rand(700.0, 850.0)
		var x: float = at[0] + cos(a) * d
		var y: float = at[1] + sin(a) * d * 0.85
		if S.world.is_free(x, y, 30.0):
			to = [x, y]
		i += 1
	if at.is_empty() or to.is_empty():
		return false
	var L := Lost.new()
	L.dex = int(mon["dex"])
	L.name = mon["name"]
	L.x = at[0]
	L.y = at[1]
	L.tx = to[0]
	L.ty = to[1]
	L.grant = rng.next() < 0.2
	L.anim = PmdAnimator.new(L.dex, 1.0)
	L.r = Sprites.body_radius(L.dex)
	L.body_h = Sprites.body_height(L.dex)
	lost = L
	if S.render:
		Sprites.preload_dex([L.dex])
	return true

func _lost_tick(dt: float, pl: Player) -> void:
	var S := Sim.cur
	var L := lost
	L.t += dt
	L.anim.update(dt)
	if L.state == "wait":
		if not pl.dead and U.dist2(pl.x, pl.y, L.x, L.y) < pow(pl.r + L.r + 18.0, 2.0):
			L.state = "follow"
			L.follow = pl
			S.spawner.say("¡" + L.name + " te sigue! Llévalo a la marca verde", 3.0)
			Sfx.play("confirm")
			history.append([_time, "follow", L.dex])
		L.moving = false
	else:
		var p: Player = L.follow if L.follow != null else pl
		var d := U.dist(L.x, L.y, p.x, p.y)
		var keep := p.r + L.r + 14.0
		L.moving = d > keep
		if L.moving:
			var sp := minf(d - keep, maxf(120.0, p.spd() * 1.15) * dt)
			var n := Enemy.dir_to(L.x, L.y, p.x, p.y)
			L.x += n[0] * sp
			L.y += n[1] * sp
			S.world.collide(L)
			L.anim.dir = Sprites.dir_from_angle(atan2(n[1], n[0]))
		if U.dist2(L.x, L.y, L.tx, L.ty) < 56.0 * 56.0:
			_rescued(pl)
			return
	L.anim.loop("Walk" if L.moving else "Idle")

	# enemies touching it hurt it
	L.hit_cd -= dt
	if L.hit_cd <= 0.0:
		var dmg := 0.0
		var n_hits := 0
		for e in S.enemies.query_circle(L.x, L.y, L.r):
			if not e.dead and e.behavior != "thief":
				dmg += 4.0 + e.dmg * 0.12
				n_hits += 1
		if n_hits > 0:
			L.hit_cd = 0.5
			L.hp -= minf(30.0, dmg)
			L.flash = 0.1
			S.fx.burst(L.x, L.y - 10.0, Color.html("#ff5f6d"), 4, 60.0)
			if L.hp <= 0.0:
				_gone("¡" + L.name + " se ha asustado y ha huido…!")
				return
	if L.flash > 0.0:
		L.flash -= dt
	if L.t > LOST_TIME:
		_gone(L.name + " se ha cansado de esperar y se ha ido…")

func _rescued(pl: Player) -> void:
	var S := Sim.cur
	var L := lost
	for i in 12:
		S.pickups.drop("coin", L.tx + U.rand(-40.0, 40.0), L.ty + U.rand(-30.0, 30.0), 5)
	S.pickups.drop("ticket", L.tx, L.ty - 12.0, 1)
	history.append([_time, "rescued", L.dex, L.grant])
	_reward(pl, L.dex, L.grant)
	lost = null
	end()

## Heals you and, 1 time in 5, the Pokémon joins your collection.
func _reward(pl: Player, dex: int, grant: bool) -> void:
	var S := Sim.cur
	if pl != null and not pl.dead:
		pl.heal(pl.max_hp * 0.5)
		S.fx.ring(pl.x, pl.y, 6.0, 70.0, Color.html("#5fe08a"), 0.5, 3.0)
	var nm: String = Data.dex_by.get(dex, {}).get("name", "")
	S.fx.burst(lost.tx if lost != null else pl.x, lost.ty - 10.0 if lost != null else pl.y, Color.html("#7dffb0"), 24, 180.0)
	Sfx.play("legend")
	if grant:
		S.on_rescue(dex, nm)
	else:
		S.spawner.say("¡Has llevado a " + nm + " a casa! Te lo agradece", 3.2)

func _gone(msg: String) -> void:
	history.append([_time, "gone", lost.dex if lost != null else 0])
	Sim.cur.spawner.say(msg, 3.0)
	lost = null
	end()

# ---------------- debug ----------------

func debug_start(id: String) -> void:
	var S := Sim.cur
	if id == "thief":
		spawn_thief(S.player, S.time)
	else:
		start(id, S.time, S.player)
