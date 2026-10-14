class_name Interact
extends RefCounted
## Altars, springs, locked chests and traps (js/systems/interact.js). The world places them
## (rare, on open floor; sim/world_map.gd place_props); this is what happens when your Pokémon
## is near one. Everything is proximity based (no keys, no costs):
##   altar     a 25 s power (Furia, Rayo, Imán or Prisa), then it goes dark
##   spring    heals while you stand on it; dries up and refills on its own
##   bigchest  stay next to it CHEST_TIME s (while they attack you) and it opens: coins,
##             tickets and XP for a whole level (loot in WorldMap.destroy_prop)
##   trap      goes off when stepped on (you or a walking enemy) and hits everything near:
##             poison, sticky (slow) or explosive

const CHEST_TIME := 3.5
const POWER_TIME := 25.0
const TRAP_R := 74.0
## Altar powers by prop kind (js POWERS; on/off below). Same data as world.json altar_powers.
const POWERS := [
	{"id": "dmg", "name": "Furia", "desc": "daño ×2", "color": "#ff5f6d"},
	{"id": "spd", "name": "Rayo", "desc": "+45% velocidad", "color": "#5fd4ff"},
	{"id": "mag", "name": "Imán", "desc": "atraes todo desde lejos", "color": "#ff8ad8"},
	{"id": "cd", "name": "Prisa", "desc": "-40% recarga", "color": "#ffd23f"},
]
const TRAP_COL := ["#c86bdc", "#8bd94a", "#ff7b3d"]
const TRAP_PAL := ["poison", "grass", "fire"]

var heal_shown := 0.0
var heal_acc := 0.0
## Candidates within SCAN + PAD of (_cx, _cy), refreshed when you move PAD/2, every 0.25 s (new
## chunks) or when the world forgets chunks; each frame still applies the exact JS 720 wu test
## (the scan walks ~16 chunks of props: 0.17 ms per frame on desktop without the cache).
const SCAN := 720.0
const PAD := 120.0
var _cache: Array[WorldProp] = []
var _cx := INF
var _cy := INF
var _ct := 0.0
var _ver := -1
## Debug / test counters: {altar, spring_hp, chest, trap}.
var stats := {"altar": 0, "spring_hp": 0.0, "chest": 0, "trap": 0}

## Interactables near a point, only in chunks that are already generated (the world's
## specials_near would generate the missing ones synchronously: ~5 ms per chunk, a 100+ ms hitch
## on entering a rift arena or when a new chunk column enters the scan). Not-yet-generated
## chunks can't hold a used altar or a drained spring, so the result is the same as JS.
static func cached_specials(W: WorldMap, x: float, y: float, r: float) -> Array[WorldProp]:
	var out: Array[WorldProp] = []
	for cy in range(int(floorf((y - r) / WorldMap.CW)), int(floorf((y + r) / WorldMap.CW)) + 1):
		for cx in range(int(floorf((x - r) / WorldMap.CW)), int(floorf((x + r) / WorldMap.CW)) + 1):
			if not W.has_chunk(cx, cy):
				continue
			for p in W.chunk_data(cx, cy).props:
				if WorldMap.SPECIAL.has(p.type) and U.dist2(x, y, p.x, p.y) <= (r + p.r) * (r + p.r):
					out.append(p)
	return out

static func power_on(pw: Dictionary, pl: Player) -> void:
	match pw["id"]:
		"dmg": pl.atk_mul *= 2.0
		"spd": pl.spd_mul *= 1.45
		"mag": pl.magnet *= 4.0
		"cd": pl.cd_mul *= 0.6

static func power_off(pw: Dictionary, pl: Player) -> void:
	match pw["id"]:
		"dmg": pl.atk_mul /= 2.0
		"spd": pl.spd_mul /= 1.45
		"mag": pl.magnet /= 4.0
		"cd": pl.cd_mul /= 0.6

func update(dt: float, pl: Player) -> void:
	if pl == null:
		return
	var S := Sim.cur
	var W := S.world
	_ct -= dt
	var ver: int = W.terrain_version * 1000003 + W.purge_serial
	if _ct <= 0.0 or ver != _ver or absf(pl.x - _cx) > PAD * 0.5 or absf(pl.y - _cy) > PAD * 0.5:
		_cache = cached_specials(W, pl.x, pl.y, SCAN + PAD)
		_cx = pl.x
		_cy = pl.y
		_ct = 0.25
		_ver = ver
	for p: WorldProp in _cache:
		# same set as specials_near(pl, 720) (minus props broken since the refresh)
		if U.dist2(pl.x, pl.y, p.x, p.y) > (SCAN + p.r) * (SCAN + p.r) or W.broken.has(Vector2i(p.tx, p.ty)):
			continue
		var d2 := U.dist2(pl.x, pl.y, p.x, p.y - 8.0 if p.type == "spring" or p.type == "trap" else p.y)
		match p.type:
			"spring":
				_spring(dt, pl, p, d2)
			"altar":
				# counting your Pokémon's size: a big one (Reshiram, Zekrom...) bumps into the
				# altar before getting within 30 and could never use it
				var reach := maxf(30.0, p.r + pl.r + 14.0)
				if not p.used and not pl.dead and d2 < reach * reach:
					use_power(pl, p)
			"bigchest":
				var reach := maxf(46.0, p.r + pl.r + 24.0)
				if not pl.dead and d2 < reach * reach:
					if p.open == 0.0:
						Sfx.play("select")
					p.open += dt
					if p.open >= CHEST_TIME:
						p.open = 0.0
						stats["chest"] += 1
						S.world.break_prop(p)
				elif p.open > 0.0:
					p.open = maxf(0.0, p.open - dt * 1.5)
			"trap":
				if not pl.dead and d2 < 13.0 * 13.0:
					S.world.break_prop(p)
				else:
					for e in S.enemies.query_circle(p.x, p.y - 8.0, 3.0):
						if not e.flying:
							S.world.break_prop(p)
							break

func _spring(dt: float, pl: Player, p: WorldProp, d2: float) -> void:
	if p.charge < 1.0:
		p.charge = minf(1.0, p.charge + dt / 45.0)
	if pl.dead or d2 > 26.0 * 26.0 or p.charge <= 0.02 or pl.hp >= pl.max_hp:
		return
	var S := Sim.cur
	var before := pl.hp
	pl.hp = minf(pl.max_hp, pl.hp + pl.max_hp * 0.14 * dt)
	heal_acc += pl.hp - before
	stats["spring_hp"] += pl.hp - before
	p.charge = maxf(0.0, p.charge - dt * 0.09)
	if randf() < dt * 14.0:
		S.fx.px(pl.x + U.rand(-pl.r, pl.r), pl.y - U.rand(0.0, pl.body_h), Color.html("#7dffb0"), 0.0, -50.0, 0.5)
	heal_shown -= dt
	if heal_shown <= 0.0 and heal_acc >= 1.0:
		heal_shown = 0.6
		S.fx.dmg_text(pl.x, pl.y - pl.body_h - 6.0, "+" + str(U.jroundi(heal_acc)), Color.html("#5fe08a"))
		heal_acc = 0.0
		Sfx.play("xp")
	if p.charge <= 0.02:
		S.spawner.say("El manantial se ha secado (se recarga solo)", 2.2)

func use_power(pl: Player, p: WorldProp) -> void:
	p.used = true
	stats["altar"] += 1
	var pw: Dictionary = POWERS[clampi(p.kind, 0, 3)]
	var col := Color.html(pw["color"])
	pl.add_power(pw, POWER_TIME)
	var S := Sim.cur
	S.fx.ring(p.x, p.y - 20.0, 8.0, 90.0, col, 0.6, 5.0)
	S.fx.burst(pl.x, pl.y - pl.body_h * 0.5, col, 24, 200.0)
	Sfx.play("legend")
	S.spawner.say("¡Poder " + str(pw["name"]) + "! " + str(pw["desc"]) + " durante " + str(int(POWER_TIME)) + " s", 3.0)

## A trap goes off (called by WorldMap.destroy_prop): hits enemies around it and you if inside.
func trap_effect(p: WorldProp) -> void:
	var S := Sim.cur
	var x := p.x
	var y := p.y - 8.0
	var k := clampi(p.kind, 0, 2)
	stats["trap"] += 1
	var col := Color.html(TRAP_COL[k])
	var pal: String = TRAP_PAL[k]
	S.fx.ring(x, y, 6.0, TRAP_R, col, 0.5, 7.0 if k == 2 else 4.0)
	S.fx.burst(x, y - 6.0, col, 40 if k == 2 else 22, 260.0 if k == 2 else 140.0)
	for i in (10 if k == 2 else 7):
		var a := randf() * U.TAU_JS
		var r := U.rand(8.0, TRAP_R * 0.8)
		S.fx.sp("impact" if k == 2 else "blob", pal, x + cos(a) * r, y + sin(a) * r * 0.7 - 6.0,
			{"vy": -30.0 if k == 2 else -45.0, "life": U.rand(0.4, 0.8)})
	Sfx.play("boss" if k == 2 else "surge")
	if k == 2 and U.dist2(x, y, S.cam.x, S.cam.y) < 500.0 * 500.0:
		S.cam.kick(0.7)
	var pl := S.player
	var lvl := pl.level if pl != null else 1
	for e in S.enemies.query_circle(x, y, TRAP_R):
		if k == 0:
			e.apply_poison(5.0)
			e.hurt(14.0 + lvl * 3.0, Color.html("#d47cf0"))
		elif k == 1:
			e.apply_slow(0.65, 4.5)
			e.hurt(4.0, Color.html("#8bd94a"))
		else:
			e.hurt(90.0 + lvl * 18.0, Color.html("#ff7b3d"), e.x - x, e.y - y, 220.0)
	if pl != null and not pl.dead and U.dist2(x, y, pl.x, pl.y) < pow(TRAP_R * 0.7, 2.0):
		pl.invuln = 0.0
		if k == 0:
			pl.hurt(pl.max_hp * 0.1, "", "trap")
		elif k == 1:
			pl.slow_t = 3.5
			S.fx.dmg_text(pl.x, pl.y - pl.body_h - 6.0, "¡Pegajoso!", Color.html("#8bd94a"))
		else:
			pl.hurt(pl.max_hp * 0.2, "", "trap")
