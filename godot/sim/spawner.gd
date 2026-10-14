class_name Spawner
extends RefCounted
## Waves, surges and the announcement banner (js/systems/spawner.js). Enemies appear on a
## ring just outside the view so they never pop in on screen.
## Bosses at their slot times, shiny rolls (1/4096); horde bag and golden spawns (sim/events.gd).

const CAP := 64
const ELITE_FROM := 0.85
const DENSITY := 0.24
const DMG_K := 2.4
const XP_K := 5.6
const SHINY_RATE := 1.0 / 4096.0

var acc := 0.0
var boss_idx := 0
var surge_t := 32.0
var announce := ""
var announce_t := 0.0
var preload_t := 0.0
var force_shiny := 0          # debug: the next N spawns are shiny (JS debugForceShiny)

## Extra toughness grows with the run: x3.3 at start up to x5 around minute 6.
static func hp_k(t: float) -> float:
	return 3.3 + minf(1.7, t / 210.0)

## Enemies per second at run time t.
static func rate(t: float) -> float:
	return (1.6 + t * 0.028 + pow(t / 60.0, 1.6) * 0.5) * DENSITY

## Stat multipliers applied to a def by spawn_one before elite/shiny (§5.3): {hp, dmg, spd, xp}.
static func spawn_mults(t: float) -> Dictionary:
	var s := EnemyDefs.scale(t)
	return {"hp": s["hp"] * hp_k(t), "dmg": s["dmg"] * DMG_K, "spd": s["spd"], "xp": XP_K}

func reset() -> void:
	acc = 0.0
	boss_idx = 0
	surge_t = 32.0
	announce = ""
	announce_t = 0.0
	preload_t = 0.0
	var S := Sim.cur
	S.defs.roll_run()
	if S.render:
		Sprites.preload_dex(S.defs.upcoming_dex(0.0, 80.0))

## [x, y] on the spawn ring around pl (always off-screen).
func ring_point(pl: Player, angle: float) -> Array:
	var d := Sim.cur.cam.outer_radius() + U.rand(10.0, 70.0)
	return [pl.x + cos(angle) * d, pl.y + sin(angle) * d * 0.9]

## Ring point where it fits (no wall / liquid); hovering species skip the check. [] if none.
func free_point(pl: Player, angle: float, flying: bool) -> Array:
	var world := Sim.cur.world
	for i in 8:
		var a := angle + (0.0 if i == 0 else U.rand(-0.9, 0.9))
		var pt := ring_point(pl, a)
		if flying or world.is_free(pt[0], pt[1], 14.0):
			return pt
	return []

## Shiny roll (1/4096) for a species with a shiny sheet (in this build's sprite subset).
func roll_shiny(dex: int) -> bool:
	if not Sprites.has_shiny(dex):
		return false
	if force_shiny > 0:
		force_shiny -= 1
		return true
	var hit := randf() < SHINY_RATE
	# Phase-1 sprite subset: only species whose shiny sheets are in this build
	return hit and (not EnemyDefs.restrict_to_available or Sprites.shiny_available(dex))

## Builds an enemy with the full spawn stat pipeline (§5.3) and adds it. null if no room.
func spawn_one(pl: Player, t: float, angle := NAN) -> Enemy:
	var S := Sim.cur
	# during a horde only that type comes out (sim/events.gd)
	var bag := S.events.bag()
	if bag.is_empty():
		bag = S.defs.bag_at(t)
	var def: Dictionary = bag[randi() % bag.size()]
	var pt := free_point(pl, randf() * U.TAU_JS if is_nan(angle) else angle, Sprites.hovers(int(def["dex"])))
	if pt.is_empty():
		return null
	var shiny := roll_shiny(int(def["dex"]))
	var e := make_enemy(def, pt[0], pt[1], t, S.enemies.count())
	if shiny:
		e.make_shiny()
	if S.events.golden():
		e.make_golden()
	S.enemies.add(e)
	if shiny:
		say("¡Un " + e.name + " shiny anda cerca!", 3.4)
		Sfx.play("shiny")
	return e

## Boss of slot b on the spawn ring (no hpK / DMG_K / XP_K / elite).
func spawn_boss(pl: Player, t: float, b: Dictionary) -> Enemy:
	var S := Sim.cur
	var pt := ring_point(pl, randf() * U.TAU_JS)
	var e := Enemy.new(b, pt[0], pt[1], EnemyDefs.boss_scale(t), true)
	if roll_shiny(int(b["dex"])):
		e.make_shiny()
	S.enemies.add(e)
	say("¡" + e.name + (" shiny" if e.shiny else "") + " salvaje apareció!", 3.2)
	S.cam.kick(1.1)
	Sfx.play("boss")
	return e

## Spawn stat pipeline, separated so the tests can check it: scale*hpK, DMG_K, XP_K, elite.
static func make_enemy(def: Dictionary, x: float, y: float, t: float, alive: int) -> Enemy:
	var s := EnemyDefs.scale(t)
	var sc := {"hp": s["hp"] * hp_k(t), "dmg": s["dmg"], "spd": s["spd"]}
	var e := Enemy.new(def, x, y, sc)
	e.dmg *= DMG_K
	e.xp = U.jround(e.xp * XP_K)
	if alive >= CAP * ELITE_FROM:
		# elite: no visual marker
		e.max_hp = U.jround(e.max_hp * 1.6)
		e.hp = e.max_hp
		e.dmg *= 1.25
		e.xp = U.jround(e.xp * 1.6)
	return e

func update(dt: float, pl: Player, t: float) -> void:
	var S := Sim.cur
	if announce_t > 0.0:
		announce_t -= dt
	# nothing else comes out in the rift arena (and the boss clock waits)
	if S.rift.in_arena:
		return
	# preload what will appear in the next minute
	preload_t -= dt
	if preload_t <= 0.0:
		preload_t = 10.0
		if S.render:
			Sprites.preload_dex(S.defs.upcoming_dex(t, 60.0))
	var lf := EnemyDefs.LATE_FROM * 60.0
	if t >= lf and t - dt < lf:
		say("¡Los Pokémon salvajes se vuelven cada vez más fuertes!", 3.6)
		Sfx.play("boss")
	# --- bosses ---
	if boss_idx < S.defs.bosses.size():
		var b: Dictionary = S.defs.bosses[boss_idx]
		if t >= float(b["at"]):
			spawn_boss(pl, t, b)
			boss_idx += 1
	# boss fight: waves drop to 25% and no surges, so the boss is a moment of its own
	var boss_fight := S.enemies.boss_alive()
	# --- trickle ---
	if S.enemies.count() < CAP:
		acc += rate(t) * (0.25 if boss_fight else 1.0) * dt
		var n := int(floorf(acc))
		acc -= n
		while n > 0 and S.enemies.count() < CAP:
			n -= 1
			spawn_one(pl, t)
	# --- surge ---
	if not boss_fight:
		surge_t -= dt
	if surge_t <= 0.0:
		surge_t = U.rand(38.0, 56.0)
		var base := randf() * U.TAU_JS
		var n := mini(CAP - S.enemies.count(), U.jroundi((14 + int(floorf(t / 22.0))) * 0.4))
		for i in n:
			spawn_one(pl, t, base + U.rand(-0.55, 0.55))
		say("¡Marea de Pokémon!", 2.2)
		Sfx.play("surge")

## A few at once from one side (a horde starts, sim/events.gd).
func burst(n: int) -> void:
	var S := Sim.cur
	var base := randf() * U.TAU_JS
	for i in n:
		if S.enemies.count() >= CAP + 10:
			break
		spawn_one(S.player, S.time, base + U.rand(-0.6, 0.6))

## A laggard reappears ahead of the player (where it runs), off-screen. false = no room.
func ahead(e: Enemy, pl: Player) -> bool:
	var sp := sqrt(pl.vsx * pl.vsx + pl.vsy * pl.vsy)
	var a0 := atan2(pl.vsy, pl.vsx) if sp > 20.0 else randf() * U.TAU_JS
	var pt := free_point(pl, a0 + U.rand(-0.9, 0.9), e.flying)
	if pt.is_empty():
		return false
	e.x = pt[0]
	e.y = pt[1]
	e.kx = 0.0
	e.ky = 0.0
	e.phase = "walk"
	e.pt = 0.0
	e.jump = {}
	e.jump_lift = 0.0
	return true

## Big announcement (one global message; a new one replaces the old).
func say(text: String, secs := 2.6) -> void:
	announce = text
	announce_t = secs
