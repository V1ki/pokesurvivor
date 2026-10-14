class_name Rift
extends RefCounted
## Rifts and the legendary arena (js/systems/rift.js).
## Now and then (a few times per run) a RIFT opens near you. It lasts TTL s; walking into it
## takes you to a closed round arena far away in the world, against a LEGENDARY Pokémon:
##   win   the legendary drops tickets (the ×10 half of the time) and coins, and you get a
##         BOND (move fusion, Player.fuse); after a few seconds you are back where you were
##         and choose the fusion
##   lose  (you fall or the time runs out) back with no prize and some HP; the run goes on
## While the arena lasts the map's enemies are stashed (EnemyMgr.stash) and nothing spawns.
## All randomness goes through `rng` (Math.random order of the JS code, for the reference tests).

const CHECK := 30.0
## Less luck involved (JS 12-10-2026): every miss makes the next roll likelier (20, 40, 60,
## 80, 100 %): at most 2.5 min without a rift.
const CHANCE := 0.2
const TTL := 45.0
const ARENA_R := 11
const ARENA_TIME := 120.0
const FROM := 75.0
const TS := 32.0
## Legendaries of these types keep their distance and shoot; the rest charge.
const RANGED_TYPES := ["psychic", "electric", "ghost", "fairy", "fire", "water", "ice", "dragon"]

var rng := StreamRng.new()
var portal: Dictionary = {}      # the rift on the map (JS `rift`): {x, y, ttl, t}
## The arena (JS `arena`): {tx, ty, r, dex, shiny, type, x, y, back_x, back_y, biome, t,
## phase: fight|won|lost, end_t, boss_id}; empty = not in a rift.
var arena: Dictionary = {}
var check_t := CHECK
var asked := false
var down_t := 0.0
var misses := 0
var next_type := ""              # debug: type of the next arena
## Debug triggers (Sim._apply_debug): open a rift at this run time (--rift-at).
var debug_open_at := INF
## Test / smoke log: [time, what, detail].
var history: Array = []

var in_arena: bool:
	get:
		return not arena.is_empty()

func reset() -> void:
	portal = {}
	arena = {}
	check_t = CHECK
	asked = false
	down_t = 0.0
	misses = 0
	history = []
	debug_open_at = INF
	Progress.in_arena = false

func time_left() -> float:
	return maxf(0.0, ARENA_TIME - float(arena["t"])) if not arena.is_empty() else 0.0

# ---------------- the rift on the map ----------------

func update(dt: float, pl: Player, time: float) -> void:
	if not portal.is_empty():
		portal["t"] = float(portal["t"]) + dt
		portal["ttl"] = float(portal["ttl"]) - dt
		if float(portal["ttl"]) <= 0.0:
			portal = {}
			history.append([time, "expired"])
			return
		# lilac motes rising from the rift (JS: 30 % per drawn frame)
		if Sim.cur.render and randf() < dt * 18.0:
			Sim.cur.fx.px(float(portal["x"]) + U.rand(-14.0, 14.0), float(portal["y"]) - U.rand(10.0, 80.0), Color.html("#d9c2ff"), 0.0, -40.0, 0.6)
		if arena.is_empty() and not pl.dead and U.dist2(pl.x, pl.y, portal["x"], float(portal["y"]) - 10.0) < 30.0 * 30.0:
			enter()
	elif arena.is_empty() and time >= debug_open_at:
		debug_open_at = INF
		open()
	elif arena.is_empty() and time > FROM:
		check_t -= dt
		if check_t <= 0.0:
			check_t = CHECK
			if Sim.cur.enemies.boss_alive():
				return                   # with a boss alive it doesn't count as a try
			if rng.next() < CHANCE * (1 + misses):
				misses = 0
				open()
			else:
				misses += 1
	if not arena.is_empty():
		_arena_tick(dt, pl)

func open() -> void:
	var S := Sim.cur
	var near: Player = rng.pick([S.player])
	for i in 24:
		var a := rng.next() * U.TAU_JS
		var d := rng.rand(380.0, 560.0)
		var x := near.x + cos(a) * d
		var y := near.y + sin(a) * d * 0.85
		if not S.world.is_free(x, y, 22.0):
			continue
		show(x, y, TTL)
		return

## The rift appears (the big popup is drawn by the HUD while t < 4.5 s).
func show(x: float, y: float, ttl: float) -> void:
	portal = {"x": x, "y": y, "ttl": ttl, "t": 0.0}
	asked = false
	history.append([Sim.cur.time, "open", x, y])
	Sfx.play("rift")
	Sim.cur.fx.ring(x, y, 6.0, 80.0, Color.html("#b48aff"), 0.7, 5.0)

func enter() -> void:
	if asked:
		return
	asked = true
	start()

# ---------------- arena ----------------

## Legendaries with sprites, only of `force` type if any has it.
static func legend_pool(force := "") -> Array:
	var pool := Data.dex.filter(func(p): return p.get("leg", false) and Sprites.has_sprite_meta(int(p["dex"])))
	if force != "" and pool.any(func(p): return (p["types"] as Array).has(force)):
		pool = pool.filter(func(p): return (p["types"] as Array).has(force))
	return pool

## Weighted choice: legendaries you haven't beaten yet come out 4 times as often.
func pick_legend(pool: Array, beaten: Dictionary) -> Dictionary:
	var ws: Array = []
	var total := 0
	for p in pool:
		var w := 1 if beaten.has(str(p["dex"])) else 4
		ws.append(w)
		total += w
	var r := rng.next() * total
	var mi := 0
	while mi < pool.size() - 1:
		r -= ws[mi]
		if r > 0.0:
			mi += 1
		else:
			break
	return pool[mi]

## Picks the legendary and the place, then travels there (JS start). `beaten_` (tests): the
## save's legends dictionary to use instead of Save.data.legends.
func start(force := "", beaten_: Variant = null) -> void:
	if not arena.is_empty():
		return
	if force == "":
		force = next_type
	next_type = ""
	var beaten: Dictionary = beaten_ if beaten_ is Dictionary else (Save.data.get("legends", {}) if Save.loaded else {})
	var mon := pick_legend(legend_pool(force), beaten)
	var dex := int(mon["dex"])
	# same draw order as the JS object literal: tx, ty, shiny, type
	var tx := 5000 + int(floorf(rng.next() * 3000.0))
	var ty := 5000 + int(floorf(rng.next() * 3000.0))
	var shiny := Sprites.has_shiny(dex) and rng.next() < 1.0 / 512.0
	# the arena is one of its types, at random
	var type := force if force != "" else str(rng.pick(mon["types"]))
	var cfg := {"tx": tx, "ty": ty, "r": ARENA_R, "dex": dex, "shiny": shiny, "type": type}
	begin(cfg)
	spawn_legend()

## Travel to the arena: stash the map, build the arena, move you in.
func begin(cfg: Dictionary) -> void:
	var S := Sim.cur
	var pl := S.player
	arena = cfg.duplicate()
	arena["x"] = int(cfg["tx"]) * TS + TS / 2.0
	arena["y"] = int(cfg["ty"]) * TS + TS / 2.0
	arena["back_x"] = pl.x
	arena["back_y"] = pl.y
	arena["biome"] = S.world.biome
	arena["t"] = 0.0
	arena["phase"] = "fight"
	arena["end_t"] = 0.0
	arena["boss_id"] = 0
	portal = {}
	asked = false
	down_t = 0.0
	Progress.in_arena = true
	S.enemies.stash()
	S.projectiles.clear()
	S.combat.clear_fields()
	S.hazards.clear()
	S.world.set_arena({"tx": int(cfg["tx"]), "ty": int(cfg["ty"]), "r": int(cfg["r"]), "type": cfg["type"]})
	S.world.set_biome(WorldMap.arena_biome(cfg["type"]), true)
	# every arena brings its weather (volcano: sun, glacier: snow...)
	var th: Dictionary = theme(cfg["type"])
	var wx: Variant = S.get("weather")
	if th.get("weather") is String and th["weather"] != "" and wx != null:
		wx.force(th["weather"], ARENA_TIME + 15.0)
	# you on the south side of the arena; the legendary appears in the north
	pl.x = float(arena["x"])
	pl.y = float(arena["y"]) + TS * 3.0
	S.cam.x = pl.x
	S.cam.y = pl.y
	S.flash("#c9a6ff", 0.9)
	Sfx.play("rift")
	S.spawner.say("Has entrado en la grieta…", 2.4)
	history.append([S.time, "arena", cfg["type"], int(cfg["dex"]), int(cfg["tx"]), int(cfg["ty"])])

## Arena theme of a type (tiles.js ARENA_THEMES via data/world.json).
static func theme(type: String) -> Dictionary:
	var th: Dictionary = WorldMap.world_json().get("arena_themes", {})
	return th.get(type, th.get("normal", {}))

## The legendary's def at run time t (rift.js spawnLegend, single player).
static func legend_def(mon: Dictionary, t: float) -> Dictionary:
	var lk := EnemyDefs.late(t)
	var ranged := false
	for ty in mon["types"]:
		if RANGED_TYPES.has(ty):
			ranged = true
	return {
		"dex": int(mon["dex"]), "name": mon["name"],
		"hp": U.jround((3200.0 + t * 9.0) * lk),
		"spd": U.jround(U.clampf_(48.0 + (float(mon["spd"]) - 78.0) * 0.6, 48.0, 105.0)),
		"dmg": U.jround((36.0 + t / 20.0) * pow(lk, 0.7)), "xp": U.jround(500.0 + t * 1.2),
		"behavior": "ranged" if ranged else "charger",
		"shotDmg": U.jround((18.0 + t / 40.0) * pow(lk, 0.7)), "shotCd": 0.9, "range": 300.0,
	}

func spawn_legend() -> void:
	var S := Sim.cur
	var mon: Dictionary = Data.dex_by[int(arena["dex"])]
	var e := Enemy.new(legend_def(mon, S.time), arena["x"], float(arena["y"]) - TS * 3.5, {"hp": 1.0, "spd": 1.0, "dmg": 1.0}, true)
	e.legend = true
	# it collides with walls and pillars like you: flying over the rocks, your shots
	# couldn't reach it (the Celebi bug)
	e.flying = false
	if arena["shiny"]:
		e.make_shiny()
	S.enemies.add(e)
	arena["boss_id"] = e.id
	S.spawner.say("¡" + e.name + (" shiny" if e.shiny else "") + " te esperaba en la grieta!", 3.2)
	S.cam.kick(1.1)
	Sfx.play("boss")

## Nobody leaves the arena circle (in case something pushes too hard).
func keep_inside() -> void:
	var mx := (float(arena["r"]) - 1.4) * TS
	var ax: float = arena["x"]
	var ay: float = arena["y"]
	for e in Sim.cur.enemies.list:
		var dx := e.x - ax
		var dy := e.y - ay
		var d := sqrt(dx * dx + dy * dy)
		if d > mx:
			e.x = ax + dx / d * mx
			e.y = ay + dy / d * mx

func _arena_tick(dt: float, pl: Player) -> void:
	var S := Sim.cur
	arena["t"] = float(arena["t"]) + dt
	if arena["phase"] == "fight":
		keep_inside()
		var boss := S.enemies.get_enemy(int(arena["boss_id"]))
		if boss == null or boss.dead:
			_won()
			return
		down_t = down_t + dt if pl.dead else 0.0
		if down_t > 1.4 or float(arena["t"]) > ARENA_TIME:
			_lost()
		return
	arena["end_t"] = float(arena["end_t"]) - dt
	if float(arena["end_t"]) <= 0.0:
		_finish()

func _won() -> void:
	if arena.is_empty() or arena["phase"] != "fight":
		return
	var S := Sim.cur
	arena["phase"] = "won"
	arena["end_t"] = 5.0
	Progress.event("rift", {"type": arena["type"]})
	S.pickups.pull_all()
	S.spawner.say("¡Has vencido a " + str(Data.dex_by[int(arena["dex"])]["name"]) + "! Recoge el premio…", 3.4)
	Sfx.play("legend")
	history.append([S.time, "won", arena["type"]])
	var pl := S.player
	if pl != null:
		pl.bonds += 1
		S.fx.dmg_text(pl.x, pl.y - pl.body_h - 10.0, "¡Vínculo!", Color.html("#ff8ad8"), true)
		S.fx.ring(pl.x, pl.y, 8.0, 90.0, Color.html("#ff8ad8"), 0.7, 5.0)

func _lost() -> void:
	if arena.is_empty() or arena["phase"] != "fight":
		return
	arena["phase"] = "lost"
	arena["end_t"] = 1.2
	Sim.cur.spawner.say("La grieta os ha expulsado…", 2.6)
	Sfx.play("back")
	history.append([Sim.cur.time, "lost", arena["type"]])

## Back to the map: the old biome, the stashed enemies, where you were.
func _finish() -> void:
	var S := Sim.cur
	var pl := S.player
	var a := arena
	arena = {}
	Progress.in_arena = false
	S.world.set_biome(int(a["biome"]), true)
	var wx: Variant = S.get("weather")
	if wx != null:
		wx.clear()
	S.enemies.restore()
	S.projectiles.clear()
	S.combat.clear_fields()
	S.hazards.clear()
	pl.x = a["back_x"]
	pl.y = a["back_y"]
	if pl.dead:
		pl.revive(0.3)
	S.cam.x = pl.x
	S.cam.y = pl.y
	S.flash("#c9a6ff", 0.8)
	history.append([S.time, "back", a["phase"]])
	if pl.bonds > 0:
		S.offer_bond()

# ---------------- debug ----------------

func debug_open() -> void:
	open()

## A rift arena of this type right now (JS debugArena).
func debug_arena(type := "") -> void:
	start(type)
