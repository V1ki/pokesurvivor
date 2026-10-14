class_name Player
extends Body
## The controlled Pokémon (port of js/entities/player.js). (x, y) are the FEET.
## Only the moves of the ACTIVE slot fire (automatically); 1-4 / Q / E switch slots.
## Held items: equip() + has_item() checks (Choice Band, Life Orb, Focus Sash, Shell Bell, Rocky Helmet).

var mon: Dictionary
var dex := 0
var shiny := false
var anim: PmdAnimator

var atk_mul := 1.0
var spd_mul := 1.0
var cd_mul := 1.0
var dmg_reduce := 0.0
var regen_flat := 0.0
var magnet := 78.0
var xp_mul := 1.0
var coin_mul := 1.0

var max_hp := 100.0
var hp := 100.0
var base_spd := 100.0
var base_atk := 1.0

var moves: Array = []            # learned move instances (Dictionary)
var slots: Array = []            # each slot = Array of move instances fired together
var active := 0
var max_moves := 4
var bonds := 0

var buffs := {
	"atk": {"n": 0, "t": 0.0, "amount": 0.0},
	"spd": {"n": 0, "t": 0.0, "amount": 0.0},
	"def": {"n": 0, "t": 0.0, "amount": 0.0},
	"regen": {"n": 0, "t": 0.0, "amount": 0.0},
}

var level := 1
var xp := 0.0
var xp_next := 62
var kills := 0
var bosses := 0
var rerolls := 0
var reroll_bonus := 0
var crit_chance := 0.0
var banned: Dictionary = {}      # move id -> true (Veto upgrade)
var bind: Dictionary = {}        # move id -> fixed slot (Atajos upgrade)
var coins := 0
var t1 := 0
var t10 := 0
var dmg_dealt := 0.0

var invuln := 0.0
var flash := 0.0
var aim := PI / 2.0
var move_angle := PI / 2.0
var walking := false
var in_liquid := false
var lava_tick := 0.0
var attack_face := 0.0
var slow_t := 0.0
var power: Dictionary = {}       # active altar power (Phase 3b): {def: Interact.POWERS[k], t, dur}
var god := false                 # debug (--god): takes no damage at all, telegraphs included
var item := ""                   # held item id (sim/items.gd), one per run
var item_regen := 0.0            # Leftovers regen snapshot at equip time
var sash_t := -999999            # last time (ms, wall clock like JS) the Focus Sash saved you
var last_patch: WeakRef = null  # last trail patch (Combat.Field; weak: the field refers back to us)
var bell_heal := 0.0
var stats_taken: Dictionary = {}
## Moves the level-up cards may offer as new moves; empty = Moves.pool_for (its types, like JS).
## Set by tests/sim_play.gd --rules=family (moves of the family's learnset at its level).
var move_pool: Array = []
## HP lost this run by source (`src` of hurt(): "touch:<behavior>", "boss", "shot", "hazard:<who>",
## "trap", "lava", "weather") and the source of the last hit. Bookkeeping only (tests/sim_play.gd).
var dmg_log: Dictionary = {}
var last_hit := ""
var target: Body = null
var svx := 0.0
var svy := 0.0
var orb_cast_t := 0.0
# smoothed velocity, maintained by EnemyMgr (runner lead, laggards)
var vsx := 0.0
var vsy := 0.0
var _px := 0.0
var _py := 0.0
var _has_prev := false

func _init(mon_: Dictionary, perks: Dictionary = {}, shiny_ := false) -> void:
	mon = mon_
	dex = int(mon["dex"])
	shiny = shiny_ and Sprites.has_shiny(dex)
	anim = PmdAnimator.new(dex, 1.0, shiny)
	r = Sprites.body_radius(dex)
	body_h = Sprites.body_height(dex)
	atk_mul = perks.get("atkMul", 1.0)
	spd_mul = perks.get("spdMul", 1.0)
	cd_mul = perks.get("cdMul", 1.0)
	dmg_reduce = perks.get("dmgReduce", 0.0)
	regen_flat = perks.get("regen", 0.0)
	magnet = 78.0 * perks.get("magnetMul", 1.0)
	xp_mul = perks.get("xpMul", 1.0)
	coin_mul = perks.get("coinMul", 1.0)
	max_hp = float(mon["hp"]) + perks.get("hp", 0.0)
	hp = max_hp
	base_spd = float(mon["spd"])
	base_atk = float(mon["atk"])
	reroll_bonus = int(perks.get("rerolls", 0))
	crit_chance = perks.get("crit", 0.0)
	xp_next = xp_for(1)

## XP needed to go from level L to L+1 (x2 then x4 on 2026-10-10 in JS).
static func xp_for(lvl: int) -> int:
	return int(floor((8.0 + lvl * 6.0 + pow(float(lvl), 1.75) * 1.6) * 4.0))

# ---------------- effective stats ----------------

func atk() -> float:
	return base_atk * atk_mul * (1.0 + buffs["atk"]["n"] * buffs["atk"]["amount"])

func spd() -> float:
	var s: float = base_spd * spd_mul * (1.0 + buffs["spd"]["n"] * buffs["spd"]["amount"]) * (0.5 if slow_t > 0.0 else 1.0)
	var slow := 1.0
	if in_liquid:
		slow = Sim.cur.world.liquid_effect(mon["types"]).get("slow", 1.0)
	return s * slow * Weather.speed_of(mon["types"])

func reduction() -> float:
	return minf(0.8, dmg_reduce + buffs["def"]["n"] * buffs["def"]["amount"])

func regen() -> float:
	return regen_flat + buffs["regen"]["n"] * buffs["regen"]["amount"]

# ---------------- moves ----------------

func has_move(id: String) -> bool:
	for m in moves:
		if m["id"] == id:
			return true
	return false

func _slot_index(g: Array) -> int:
	for i in slots.size():
		if is_same(slots[i], g):
			return i
	return -1

func add_move(id: String) -> bool:
	if slots.size() >= max_moves or has_move(id):
		return false
	var m := Moves.instance(id, 1)
	moves.append(m)
	var group: Array = [m]
	slots.append(group)
	arrange()
	# switch to the new move unless a bond group is active
	if not (active < slots.size() and (slots[active] as Array).size() > 1):
		set_active(_slot_index(group))
	return true

## Fixed slots (Atajos upgrade): bound moves go to their slot; the rest fill in learn order.
func arrange() -> void:
	var n := slots.size()
	if n < 2 or bind.is_empty():
		return
	var want := func(g: Array) -> int:
		var k := 1 << 30
		for m in g:
			if bind.has(m["id"]):
				k = mini(k, int(bind[m["id"]]))
		return k
	var cur_g: Variant = slots[active] if active < n else null
	var out: Array = []
	out.resize(n)
	var bound: Array = slots.filter(func(g): return want.call(g) < (1 << 30))
	bound.sort_custom(func(a, b): return want.call(a) < want.call(b))
	for g in bound:
		var p := mini(want.call(g), n - 1)
		while p >= 0 and out[p] != null:
			p -= 1
		if p < 0:
			p = 0
			while out[p] != null:
				p += 1
		out[p] = g
	for g in slots:
		var placed := false
		for o in out:
			if is_same(o, g):
				placed = true
		if not placed:
			out[out.find(null)] = g
	slots = out
	if cur_g != null:
		active = _slot_index(cur_g)

func set_active(i: int) -> void:
	if i < 0 or i >= slots.size() or i == active:
		return
	# Choice Band: the active move can't be changed
	if has_item("choiceband") and active < slots.size():
		Sim.cur.fx.dmg_text(x, y - body_h - 8.0, "Cinta Elección", Color.html("#ff8ad8"))
		return
	active = i
	Sim.cur.projectiles.clear_orbs(self)
	Sfx.play("select")
	for m in slots[i]:
		m["t"] = minf(m["t"], m["cd"] * 0.35)
	var m0: Dictionary = slots[i][0]
	Sim.cur.fx.ring(x, y - U.LIFT * 0.5, 6.0, r * 3.4, Data.tcolor(m0["type"]), 0.3, 3.0)

func cycle(dir: int) -> void:
	if slots.is_empty():
		return
	set_active(posmod(active + dir, slots.size()))

# ---------------- bonds (move fusion, Phase 3b) ----------------
# Each legendary beaten in a rift gives a bond. With it moves join one slot and are cast
# together (each with its own cooldown). Only one group grows (up to BOND_MAX); with no group
# half-built, the bond joins two loose moves.

const BOND_MAX := 4

## What a bond can do now: {mode: "add", group, loose} (one loose move joins the growing group)
## or {mode: "pair", group: [], loose} (two loose moves); {} if nothing (bond kept for later).
func bond_options() -> Dictionary:
	var loose: Array = []
	var grow: Array = []
	var has_grow := false
	for s in slots:
		if (s as Array).size() == 1:
			loose.append(s[0])
		elif not has_grow and (s as Array).size() > 1 and (s as Array).size() < BOND_MAX:
			grow = s
			has_grow = true
	if has_grow:
		return {"mode": "add", "group": grow, "loose": loose} if not loose.is_empty() else {}
	return {"mode": "pair", "group": [], "loose": loose} if loose.size() >= 2 else {}

## Joins the loose `picked` moves into `group` (or a new one) and spends a bond. Returns the group.
func fuse(picked: Array, group: Array = []) -> Array:
	var target: Array = group
	if group.is_empty():
		for s in slots:
			if is_same(s[0], picked[0]):
				target = s
				break
	var cur_g: Variant = slots[active] if active < slots.size() else null
	for m in picked:
		var inside := false
		for o in target:
			if is_same(o, m):
				inside = true
		if inside:
			continue
		var idx := -1
		for i in slots.size():
			if (slots[i] as Array).size() == 1 and is_same(slots[i][0], m):
				idx = i
				break
		if idx < 0:
			continue
		slots.remove_at(idx)
		target.append(m)
	arrange()
	# switch to the group, except with the Choice Band (you stay in your slot, if it's left)
	var a := _slot_index(cur_g) if cur_g != null else -1
	active = a if has_item("choiceband") and a >= 0 else _slot_index(target)
	bonds = maxi(0, bonds - 1)
	Sim.cur.projectiles.clear_orbs(self)
	return target

## Altar power (replaces the active one).
func add_power(pw: Dictionary, dur: float) -> void:
	if not power.is_empty():
		Interact.power_off(power["def"], self)
	Interact.power_on(pw, self)
	power = {"def": pw, "t": dur, "dur": dur}

## Stands up again (back from a lost rift fight).
func revive(frac := 0.5) -> void:
	dead = false
	hp = maxf(1.0, max_hp * frac)
	invuln = 2.0
	anim.hold = false
	anim._start("Idle", false)
	var S := Sim.cur
	S.fx.ring(x, y, 6.0, 70.0, Color.html("#5fe08a"), 0.5, 4.0)
	S.fx.burst(x, y - body_h * 0.5, Color.html("#9dffb8"), 18, 150.0)
	Sfx.play("heal")

func active_group() -> Array:
	return slots[active] if active < slots.size() else []

func active_move() -> Dictionary:
	var g := active_group()
	return g[0] if not g.is_empty() else {}

const CAST_ANIM := {"melee": "Attack", "beam": "Shoot", "projectile": "Shoot", "nova": "Attack",
	"aura": "Charge", "buff": "Charge", "orbit": "Charge", "boomerang": "Shoot", "chain": "Shoot",
	"mine": "Charge", "meteor": "Charge", "turret": "Charge", "dash": "Attack", "trail": "Walk", "cone": "Shoot"}

## Called by Combat when a move fires: PMD attack animation, sped up to chain at short cooldowns.
func cast(m: Dictionary) -> void:
	var kind: String = m["kind"]
	# Life Orb: every attack costs a little HP (never KOs)
	if has_item("lifeorb") and kind != "orbit" and kind != "trail":
		hp = maxf(1.0, hp - maxf(1.0, max_hp * 0.01))
	if kind != "trail":
		Sfx.play("shot", {"kind": kind, "type": m.get("type", "normal")})
	if kind == "trail":
		return
	# don't restart a one-shot that is past its first third
	if anim.busy() and anim.progress() < 0.65:
		return
	var an: String = CAST_ANIM.get(kind, "Attack")
	var meta := Sprites.anim_meta(dex, an)
	var alen := 0.4
	if not meta.is_empty():
		alen = 0.0
		for v in meta["d"]:
			alen += v
		alen /= 60.0
	var cd := maxf(0.12, float(m["cd"]) * cd_mul)
	anim.play(an, maxf(1.0, alen / (cd * 0.9)))
	attack_face = 0.35

# ---------------- damage and healing ----------------

## type = attack type (type chart); "" = untyped damage. src: where it came from (dmg_log only).
func hurt(amount: float, type := "", src := "other") -> void:
	if invuln > 0.0 or dead or god:
		return
	var before := hp
	var eff := ""
	if type != "":
		var k := Types.mult(type, mon["types"])
		eff = Types.label(k)
		amount *= k * Weather.mult_of(type)
	# melee users take 25% less (they have to stand in the crowd)
	var close := 1.0
	for m in active_group():
		if m["kind"] == "melee":
			close = 0.75
	var d := maxf(1.0, amount * (1.0 - reduction()) * close)
	hp -= d
	dmg_log[src] = float(dmg_log.get(src, 0.0)) + minf(d, before)
	last_hit = src
	invuln = 0.45
	flash = 0.14
	Sfx.play("hurt")
	var S := Sim.cur
	S.cam.kick(0.28)
	var c := "#ff3048" if eff == "super" else ("#c9a0a8" if eff == "weak" else "#ff6b7a")
	S.fx.dmg_text(x, y - body_h - 4.0, "-" + str(U.jroundi(d)), Color.html(c), eff == "super")
	S.fx.burst(x, y - body_h * 0.5, Color.html("#ff5f6d"), 6, 90.0)
	# Focus Sash: survive the hit with 1 HP (once every 60 s of real time)
	if hp <= 0.0 and has_item("focussash") and Time.get_ticks_msec() - sash_t > 60000:
		sash_t = Time.get_ticks_msec()
		hp = 1.0
		invuln = 1.2
		S.fx.dmg_text(x, y - body_h - 16.0, "¡Banda Focus!", Color.html("#ff9a3d"), true)
		S.fx.ring(x, y, 6.0, 70.0, Color.html("#ff9a3d"), 0.5, 4.0)
	if hp <= 0.0:
		hp = 0.0
		dead = true
		anim.play("Faint", 1.0, true)
		S.projectiles.clear_orbs(self)
	# mobile/shell.js (Android app): short vibration when a hit takes HP (Haptics.impact LIGHT =
	# Capacitor's 50 ms at amplitude 110/255)
	if hp < before and OS.has_feature("android"):
		Input.vibrate_handheld(50, 110.0 / 255.0)

func heal(amount: float) -> void:
	var before := hp
	hp = minf(max_hp, hp + amount)
	var got := U.jroundi(hp - before)
	if got >= 1:
		Sim.cur.fx.dmg_text(x, y - body_h - 6.0, "+" + str(got), Color.html("#5fe08a"))

func add_max_hp(amount: float) -> void:
	max_hp += amount
	hp += amount

## Returns how many levels were gained (several at once is possible).
func gain_xp(amount: float) -> int:
	xp += amount * xp_mul
	var leveled := 0
	while xp >= xp_next:
		xp -= xp_next
		level += 1
		xp_next = xp_for(level)
		leveled += 1
	return leveled

func has_item(id: String) -> bool:
	return item == id

## Puts on a held item (taking off the current one first).
func equip(id: String) -> void:
	if item != "":
		Items.off(item, self)
	item = id
	if id != "":
		Items.on(id, self)

## Shell Bell: a little HP from the damage you deal (max 4/s).
func on_dealt(dmg: float) -> void:
	if item == "shellbell":
		bell_heal = minf(4.0, bell_heal + dmg * 0.04)

func add_buff(stat: String, amount: float, dur: float, max_stacks: int) -> void:
	if not buffs.has(stat):
		return
	var b: Dictionary = buffs[stat]
	b["amount"] = amount
	b["n"] = mini(max_stacks, int(b["n"]) + 1)
	b["t"] = dur

# ---------------- update ----------------

func update(dt: float) -> void:
	anim.update(dt)
	if dead:
		return
	var S := Sim.cur
	if invuln > 0.0:
		invuln -= dt
	if flash > 0.0:
		flash -= dt
	if attack_face > 0.0:
		attack_face -= dt
	for k in buffs:
		var b: Dictionary = buffs[k]
		if b["n"] > 0:
			b["t"] -= dt
			if b["t"] <= 0.0:
				b["n"] = 0
	if slow_t > 0.0:
		slow_t -= dt
	if bell_heal > 0.0:
		var hh := minf(bell_heal, 4.0 * dt)
		hp = minf(max_hp, hp + hh)
		bell_heal -= hh
	if not power.is_empty():
		power["t"] = float(power["t"]) - dt
		if float(power["t"]) <= 0.0:
			Interact.power_off(power["def"], self)
			power = {}
	var rg := regen()
	if rg > 0.0:
		hp = minf(max_hp, hp + rg * dt)

	# --- movement with collisions (no acceleration; ice slides) ---
	var ax: float = S.input_axis.x
	var ay: float = S.input_axis.y
	walking = ax != 0.0 or ay != 0.0
	var s := spd()
	var slide: bool = in_liquid and S.world.liquid_effect(mon["types"]).get("slide", false)
	svx = U.damp(svx, ax * s * 1.15, 1.6, dt) if slide else ax * s
	svy = U.damp(svy, ay * s * 1.15, 1.6, dt) if slide else ay * s
	x += svx * dt
	y += svy * dt
	S.world.collide(self)
	if walking:
		move_angle = atan2(ay, ax)

	# --- liquid ---
	in_liquid = S.world.is_liquid(x, y)
	if in_liquid:
		var le := S.world.liquid_effect(mon["types"])
		if le.has("dmg"):
			lava_tick -= dt
			if lava_tick <= 0.0:
				lava_tick = le["every"]
				invuln = 0.0
				hurt(maxf(le["flat"], max_hp * le["dmg"] * 0.5), "", "lava")
				S.fx.burst(x, y - 4.0, Color.html(le["color"]), 5, 70.0)
		elif walking and randf() < dt * 8.0:
			S.fx.burst(x, y, Color.WHITE if le.get("slide", false) else Color.html("#b3defa"), 2, 40.0)

	# --- targeting (priority depends on the active move) ---
	#   ranged (projectile, beam): boss in range > touching > nearest
	#   others: touching > boss > nearest; with no enemies: nearest breakable prop (rock, chest)
	var all: Array = S.enemies.list
	var m := active_move()
	var ranged: bool = not m.is_empty() and (m["kind"] == "projectile" or m["kind"] == "beam")
	var threat: Enemy = S.projectiles.nearest(all, x, y, r + 24.0)
	var boss: Enemy = null
	for e: Enemy in all:
		if e.boss and not e.dead and U.dist(x, y, e.x, e.y) < 330.0:
			boss = e
			break
	var tg: Enemy = (boss if boss != null else threat) if ranged else (threat if threat != null else boss)
	if tg == null:
		tg = S.projectiles.nearest(all, x, y, 520.0)
	var tb: Body = tg
	if tb == null:
		tb = S.world.nearest_breakable(x, y, 200.0)
	target = tb
	if tb != null:
		aim = atan2(tb.y - y, tb.x - x)
	elif walking:
		aim = move_angle

	# --- animation: face the target while attacking, else where it walks ---
	var face := aim if (attack_face > 0.0 or not walking) else move_angle
	anim.dir = Sprites.dir_from_angle(face)
	anim.loop("Walk" if walking else "Idle", s / 110.0 if walking else 1.0)
