class_name Enemy
extends Body
## A wild Pokémon (port of the Enemy class in js/entities/enemy.js). (x, y) are the FEET.
## PMD animations: Walk moving · Idle standing · Charge aiming · Attack striking ·
## Shoot firing · Hurt when hit · Faint when down (stays on the ground and fades).
## Hovering species and bosses ignore terrain; the rest collide with walls, are slower in
## water and burn in lava. Behaviors (§5.5): chase, tank, runner, charger, the keep-distance
## group (ranged, fan, beamer, zoner, healer, summoner), shielder, jumper, bomber; bosses
## have their own AI (§5.6). The `thief` behavior (treasure thieves) belongs to sim/events.gd.

const KEEP_DISTANCE := ["ranged", "fan", "beamer", "zoner", "healer", "summoner"]
## Behavior codes cached by the `behavior` setter (int compares in the per-frame update).
enum { BK_CHASE, BK_THIEF, BK_RUNNER, BK_BOMBER, BK_SHIELDER, BK_JUMPER, BK_CHARGER, BK_OTHER }
const _BK := {"chase": BK_CHASE, "thief": BK_THIEF, "runner": BK_RUNNER, "bomber": BK_BOMBER,
	"shielder": BK_SHIELDER, "jumper": BK_JUMPER, "charger": BK_CHARGER}
const SHOT_COLOR := Color(1.0, 0.478, 0.62)       # #ff7a9e

static var next_id := 1

## Boss brain (bossInit): 2 melee + 2 ranged attacks, alternating close/far modes.
class BossAI:
	var melee: Array = []
	var ranged: Array = []
	var far_like := 0.35
	var mode := "close"
	var mode_t := 7.0
	var cd := 1.6
	var cast: Dictionary = {}     # {id, t, wind, after, ang, len?, dur?, go?, fired?}; empty = none
	var fury := false
	var side := 1.0

var id := 0
var def: Dictionary
var dex := 0
var name := ""
var boss := false
var scale := 1.0
var anim: PmdAnimator
var max_hp := 1.0
var hp := 1.0
var spd := 50.0
var dmg := 5.0
var xp := 3.0
var behavior := "chase":
	set(v):
		behavior = v
		_bk = _BK.get(v, BK_OTHER)
		_keep = KEEP_DISTANCE.has(v)
var _bk := BK_CHASE               # behavior code (see _BK)
var _keep := false                # keeps_distance()
var types: Array = ["normal"]
var atk_type := "normal"
var flying := false
var flash := 0.0
var slow := 0.0
var slow_t := 0.0
var burn := 0.0
var burn_t := 0.0
var burn_tick := 0.0
var poison := 0.0
var poison_t := 0.0
var poison_tick := 0.0
var lava_tick := 0.0
var kx := 0.0
var ky := 0.0
var touch_cd := 0.0
var fade := 0.0
var phase := "walk"
var pt := 0.0
var dash_x := 0.0
var dash_y := 0.0
var shot_cd := 0.0
var stuck_t := 0.0
var side_t := 0.0
var side := 1.0
var bob := 0.0
var shiny := false
var spark_t := 0.0
var golden := false
var legend := false
var sc: Dictionary = {}
var shield := 0.0
var shield_t := 0.0
var skill_cd := 0.0
var minions: Array = []          # summoned minions (Enemy)
var jump: Dictionary = {}         # {sx, sy, tx, ty, t, dur}; empty = not jumping
var jump_lift := 0.0
var lag_t := 0.0
var life := 0.0                   # treasure thief: seconds before it escapes (EnemyMgr)
var zig := 0.0                    # treasure thief: zigzag phase
var los := false                  # pathing line-of-sight cache
var los_at := -1.0
var ai: BossAI = null
var gi := -1                      # EnemyMgr grid entry index at the last rebuild (separation)
var shadow_rx := -1.0             # Sprites.shadow_rx(dex, scale), cached by render/world_view.gd

## Bosses grow to ~110 wu tall, in 0.5 steps so art pixels stay integral at x2 zoom.
static func boss_scale_of(d: int) -> float:
	var m := Sprites.anim_meta(d, "Idle")
	var h: float = (m["ay"] if not m.is_empty() else 30.0) * Sprites.PX
	return U.clampf_(U.jround(110.0 / h * 2.0) / 2.0, 1.0, 2.0)

func _init(def_: Dictionary, x_: float, y_: float, sc_: Dictionary, boss_ := false) -> void:
	is_enemy = true
	id = next_id
	next_id += 1
	def = def_
	dex = int(def["dex"])
	var mon: Dictionary = Data.dex_by.get(dex, {})
	name = mon.get("name", def.get("name", ""))
	x = x_
	y = y_
	boss = boss_
	scale = boss_scale_of(dex) if boss else 1.0
	anim = PmdAnimator.new(dex, scale)
	r = Sprites.body_radius(dex, scale)
	body_h = Sprites.body_height(dex, scale)
	max_hp = U.jround(float(def["hp"]) * float(sc_["hp"]))
	hp = max_hp
	spd = float(def["spd"]) * float(sc_["spd"])
	dmg = float(def["dmg"]) * float(sc_["dmg"])
	xp = float(def["xp"])
	behavior = def["behavior"]
	var ts: Array = mon.get("types", [])
	types = ts if not ts.is_empty() else ["normal"]
	atk_type = types[0]
	flying = boss or Sprites.hovers(dex)
	shot_cd = U.rand(0.3, float(def["shotCd"])) if def.get("shotCd", 0.0) else 0.0
	bob = randf() * 6.28
	sc = sc_
	skill_cd = U.rand(1.0, 4.0)

## Unit vector from (ax, ay) to (bx, by) in 64-bit floats ([0, 0] if too close), like G.U.norm.
## (U.norm returns a float32 Vector2: fine for movement, not for shot / beam angles.)
static func dir_to(ax: float, ay: float, bx: float, by: float) -> Array:
	var x := bx - ax
	var y := by - ay
	var m := sqrt(x * x + y * y)
	return [x / m, y / m] if m > 1e-6 else [0.0, 0.0]

func keeps_distance() -> bool:
	return _keep

## Turns it shiny: other sprite, double HP and much more XP.
func make_shiny() -> void:
	shiny = true
	anim = PmdAnimator.new(dex, scale, true)
	max_hp *= 2.0
	hp = max_hp
	xp *= 5.0
	if Sim.cur != null and Sim.cur.render:
		Sprites.preload_dex([dex], true)

## Golden hour (sim/events.gd): double XP and sometimes coins.
func make_golden() -> void:
	if golden or boss or behavior == "thief":
		return
	golden = true
	xp *= 2.0

## eff: "super" | "weak" | "crit" | "" (only for the number colour).
func hurt(amount: float, color: Color, dir_x := 0.0, dir_y := 0.0, knock := 0.0, eff := "") -> void:
	if dead:
		return
	var d := maxf(1.0, U.jround(amount))
	# shield absorbs first
	if shield > 0.0:
		var a := minf(shield, d)
		shield -= a
		if a >= d:
			Sim.cur.fx.dmg_text(x, y - body_h - 4.0, int(d), Color.html("#9fd8ff"))
			flash = 0.05
			return
		amount = d - a
	hp -= maxf(1.0, U.jround(amount))
	show_hurt(d, color, dir_x, dir_y, eff)
	if knock > 0.0 and not boss:
		var n := U.norm(dir_x, dir_y)
		kx += n.x * knock
		ky += n.y * knock
	if hp <= 0.0:
		die()

func show_hurt(d: float, color: Color, dir_x: float, dir_y: float, eff: String) -> void:
	flash = 0.09
	var c := color
	if eff == "crit":
		c = Color.html("#ff9a3c")
	elif eff == "super":
		c = Color.html("#ffe14d")
	elif eff == "weak":
		c = Color.html("#a3abb8")
	var S := Sim.cur
	S.fx.dmg_text(x, y - body_h - 4.0, int(d), c, boss or eff == "super" or eff == "crit")
	S.fx.spark(x, y - body_h * 0.5, color, dir_x, dir_y, 3)
	if not anim.busy() and phase != "dash":
		anim.play("Hurt")
	Sfx.play("hit")

func apply_slow(factor: float, dur := 1.2) -> void:
	slow = maxf(slow, factor)
	slow_t = maxf(slow_t, dur)

func apply_burn(stacks := 1.0) -> void:
	burn = minf(8.0, burn + stacks)
	burn_t = 3.0

func apply_poison(stacks := 1.0) -> void:
	poison = minf(8.0, poison + stacks)
	poison_t = 4.0

func die() -> void:
	if dead:
		return
	dead = true
	fade = 0.9
	anim.play("Faint", 1.0, true)
	var S := Sim.cur
	var col := Color.html("#ffd95e") if boss else Color.WHITE
	var cy := y - body_h * 0.5
	S.fx.burst(x, cy, col, 34 if boss else 9, 260.0 if boss else 120.0)
	S.fx.ring(x, y, r, r * (6.0 if boss else 2.6), col, 0.6 if boss else 0.3, 6.0 if boss else 3.0)
	if boss:
		S.cam.kick(0.9)
		for i in 10:
			S.pickups.drop("coin", x + U.rand(-40, 40), y + U.rand(-30, 30), 5)
		# bosses always drop a held item
		S.pickups.drop("item", x - 26.0, y - 10.0, Items.roll())
	S.pickups.drop_xp(x, y, xp, boss, legend)
	if golden and randf() < 0.35:
		S.pickups.drop("coin", x + 6, y - 4, 3)
	# treasure thief: Meowth drops coins; Gholdengo, a x10 ticket
	if behavior == "thief":
		var tk10: bool = def.get("loot", "") == "ticket10"
		for i in (6 if tk10 else 20):
			S.pickups.drop("coin", x + U.rand(-36, 36), y + U.rand(-26, 26), 5)
		if tk10:
			S.pickups.drop("ticket10", x, y - 12.0, 1)
		S.fx.ring(x, y, r, r * 5.0, Color.html("#ffd23f"), 0.6, 4.0)
	# the rift legendary: loose tickets and coins (the x10 about half of the time, drop_xp)
	if legend:
		for i in 3:
			S.pickups.drop("ticket", x + U.rand(-30, 30), y + U.rand(-20, 20), 1)
		for i in 10:
			S.pickups.drop("coin", x + U.rand(-50, 50), y + U.rand(-35, 35), 8)
	Sfx.play("bossDown" if boss else "faint")
	if shiny:
		S.fx.burst(x, cy, Color.html("#ffe9a0"), 30, 220.0)
		S.fx.ring(x, y, r, r * 7.0, Color.html("#9ae6ff"), 0.7, 5.0)
		S.on_shiny_caught(self)

func update(dt: float, pl: Player) -> void:
	var S := Sim.cur
	# off-screen enemies don't animate (they still move and think)
	var seen := S.cam.sees(x, y, 120.0)
	if seen or dead:
		anim.update(dt)
	if flash > 0.0:
		flash -= dt
	if dead:
		fade -= dt
		return
	if shiny and seen:
		spark_t -= dt
		if spark_t <= 0.0:
			spark_t = 0.22
			S.fx.twinkle(x + U.rand(-r, r) * 1.2, y - U.rand(4.0, body_h * 1.1))
	if touch_cd > 0.0:
		touch_cd -= dt
	bob += dt * 6.0

	# --- statuses ---
	if slow_t > 0.0:
		slow_t -= dt
		if slow_t <= 0.0:
			slow = 0.0
	if burn > 0.0:
		burn_t -= dt
		burn_tick -= dt
		if burn_tick <= 0.0:
			burn_tick = 0.5
			hurt(1.6 * burn * (1.0 + pl.level * 0.06), Color.html("#ff9a4d"))
		if burn_t <= 0.0:
			burn = 0.0
	if poison > 0.0:
		poison_t -= dt
		poison_tick -= dt
		if poison_tick <= 0.0:
			poison_tick = 0.6
			hurt(max_hp * 0.012 * poison + 1.0, Color.html("#d47cf0"))
		if poison_t <= 0.0:
			poison = 0.0
	if dead:
		return

	# --- terrain ---
	var terrain_mul := 1.0
	if not flying and not legend and S.world.is_liquid(x, y):
		var le := S.world.liquid_effect(types)
		if le.has("dmg"):
			lava_tick -= dt
			if lava_tick <= 0.0:
				lava_tick = le["every"]
				hurt(6.0 + max_hp * 0.04, Color.html(le["color"]))
			if dead:
				return
		elif le.has("slow"):
			terrain_mul = 0.45 if le["slow"] < 0.5 else 0.55

	var sp := spd * (1.0 - slow) * terrain_mul * S.weather.speed_for(types)
	# U.norm / U.dist inlined (same expressions; the direction keeps U.norm's float32 Vector2 rounding)
	var tpx := pl.x - x
	var tpy := pl.y - y
	var dist := sqrt(tpx * tpx + tpy * tpy)
	var n := Vector2(tpx / dist, tpy / dist) if dist > 1e-6 else Vector2.ZERO
	var dx: float = n.x
	var dy: float = n.y
	var bk := _bk

	# treasure thief: runs away from you (zigzagging) as soon as you get close
	if bk == BK_THIEF:
		zig += dt
		var near := dist < 300.0
		var a := atan2(-dy, -dx) + sin(zig * 2.2) * 0.7
		var k := 1.0 if near else 0.35
		var ox := x
		var oy := y
		x += (cos(a) * sp * k + kx) * dt
		y += (sin(a) * sp * k + ky) * dt
		var kd := pow(0.0015, dt)
		kx *= kd
		ky *= kd
		if S.world.collide(self) and U.dist(ox, oy, x, y) < sp * k * dt * 0.3:
			zig += 1.4
		if randf() < dt * 6.0 and S.cam.sees(x, y, 0.0):
			S.fx.twinkle(x + U.rand(-r, r), y - U.rand(4.0, body_h))
		anim.dir = Sprites.dir_from_angle(a)
		anim.loop("Walk", 1.4)
		return
	# runner: heads to where you WILL be
	if bk == BK_RUNNER:
		var lead := U.clampf_(dist / maxf(60.0, sp), 0.0, 1.4)
		var n2 := U.norm(pl.x + pl.vsx * lead - x, pl.y + pl.vsy * lead - y)
		dx = n2.x
		dy = n2.y
		if S.cam.sees(x, y, 0.0) and randf() < dt * 10.0:
			S.fx.px(x - dx * 8.0 + U.rand(-4, 4), y, Color.html("#e8dcc0"), 0.0, -12.0, 0.35)

	# --- personality (shields, jumps, fuse) ---
	if shield_t > 0.0:
		shield_t -= dt
		if shield_t <= 0.0:
			shield = 0.0
	if not jump.is_empty():
		_update_jump(dt)
		return
	if bk == BK_BOMBER and phase == "fuse":
		pt -= dt
		flash = 0.05 if int(floorf(pt * 10.0)) % 2 != 0 else 0.0
		if pt <= 0.0:
			hp = 0.0
			die()
		anim.loop("Idle")
		return
	if bk == BK_BOMBER and dist < r + pl.r + 26.0:
		start_fuse()
		return
	if bk == BK_SHIELDER or bk == BK_JUMPER:
		skill_cd -= dt
		if skill_cd <= 0.0:
			if bk == BK_SHIELDER:
				skill_cd = 6.0
				cast_shields()
			elif dist < 250.0:
				skill_cd = U.rand(5.0, 7.0)
				start_jump(pl)
				return
			else:
				skill_cd = 0.5

	# stuck against something for a while: go around one side
	if side_t > 0.0:
		side_t -= dt
		var a := atan2(dy, dx) + side * 1.25
		dx = cos(a)
		dy = sin(a)

	# path around obstacles (walkers only)
	if not flying and phase != "dash" and side_t <= 0.0:
		var pd: Variant = S.pathing.dir_for(self, pl, S.time * 1000.0)
		if pd != null and not (_keep and dist < float(def.get("range", 200.0)) * 0.82):
			dx = (pd as Vector2).x
			dy = (pd as Vector2).y

	var vx := dx * sp
	var vy := dy * sp
	var anim_base := "Walk"

	if boss:
		var mv := _boss_move(dt, pl, dist, dx, dy, sp)
		vx = mv[0]
		vy = mv[1]
		anim_base = mv[2]
	elif bk == BK_CHARGER:
		pt -= dt
		if phase == "walk":
			if dist < 200.0 and pt <= 0.0:
				phase = "aim"
				pt = 0.55
				anim.play("Charge", 1.6)
		elif phase == "aim":
			vx = 0.0
			vy = 0.0
			anim_base = "Idle"
			if pt <= 0.0:
				phase = "dash"
				pt = 0.42
				dash_x = dx
				dash_y = dy
				anim.play("Attack", 1.4)
				S.fx.ring(x, y, r, r * 2.4, Color.html("#ff6b6b"), 0.25, 2.0)
		elif phase == "dash":
			vx = dash_x * sp * 3.4
			vy = dash_y * sp * 3.4
			if pt <= 0.0:
				phase = "walk"
				pt = 1.1
	elif _keep:
		var range := float(def.get("range", 200.0))
		var keep := range * 0.82
		# straight toward you (not the path) to back off
		var nd := dir_to(x, y, pl.x, pl.y)
		if dist < keep * 0.75:
			vx = -nd[0] * sp * 0.8
			vy = -nd[1] * sp * 0.8
		elif dist < keep:
			vx *= 0.1
			vy *= 0.1
			anim_base = "Idle"
		shot_cd -= dt
		if shot_cd <= 0.0 and dist < range:
			shot_cd = float(def.get("shotCd", 2.0)) if def.get("shotCd", 0.0) else 2.0
			special(pl, nd[0], nd[1])

	# --- integration ---
	var ox := x
	var oy := y
	x += kx * dt
	y += ky * dt
	var kd := pow(0.0015, dt)
	kx *= kd
	ky *= kd
	x += vx * dt
	y += vy * dt
	if not flying and S.world.collide(self):
		var want := sqrt(vx * vx + vy * vy) * dt
		var got := U.dist(ox, oy, x, y)
		if want > 0.5 and got < want * 0.35:
			stuck_t += dt
			if stuck_t > 0.35 and side_t <= 0.0:
				side_t = 0.7
				stuck_t = 0.0
				side = -1.0 if randf() < 0.5 else 1.0
		else:
			stuck_t = 0.0

	# --- animation ---
	var moving := absf(vx) + absf(vy) > 2.0
	var face_a: float
	if phase == "dash":
		face_a = atan2(dash_y, dash_x)
	elif moving:
		face_a = atan2(vy, vx)
	else:
		face_a = atan2(pl.y - y, pl.x - x)
	anim.dir = posmod(int(floor((PI / 2.0 - face_a) / (PI / 4.0) + 0.5)), 8)     # Sprites.dir_from_angle
	anim.loop(anim_base if moving else "Idle", maxf(0.6, sp / 70.0) if moving else 1.0)

# ---------------- bosses ----------------
# Each boss has 4 attacks: 2 close (slam always + dash or leap) and 2 ranged by type.
# It alternates between rushing you and fighting from afar; everything is telegraphed
# on the ground. Below half HP it gets furious: faster, shorter waits, chained attacks.

func boss_init() -> void:
	var has := func(xs: Array) -> bool:
		for t in xs:
			if types.has(t):
				return true
		return false
	ai = BossAI.new()
	ai.melee = ["slam", "dash" if U.hash01(dex, 3, 7) < 0.5 else "leap"]
	var pref := "volley"
	if has.call(["fire", "ground", "poison", "rock", "grass"]):
		pref = "rain"
	elif has.call(["electric", "psychic", "dragon", "ice", "steel"]):
		pref = "beam"
	elif has.call(["fairy", "ghost", "water", "flying"]):
		pref = "nova"
	var others := ["rain", "beam", "nova", "volley"].filter(func(k): return k != pref)
	ai.ranged = [pref, others[int(floorf(U.hash01(dex, 5, 9) * 3.0)) % 3]]
	var far := behavior == "ranged"
	ai.far_like = 0.65 if far else 0.35
	ai.mode = "far" if far else "close"
	ai.mode_t = U.rand(6.0, 8.0)
	ai.cd = 1.6
	ai.side = -1.0 if randf() < 0.5 else 1.0

func _boss_move(dt: float, pl: Player, dist: float, dx: float, dy: float, sp: float) -> Array:
	if ai == null:
		boss_init()
	if not ai.fury and hp < max_hp * 0.5:
		enrage()
	var k := 1.25 if ai.fury else 1.0
	if not ai.cast.is_empty():
		return _boss_cast(dt, pl)
	ai.mode_t -= dt
	ai.cd -= dt * k
	# always alternates: longer (7-9 s) in its favourite distance than in the other (4-5 s)
	if ai.mode_t <= 0.0:
		ai.mode = "close" if ai.mode == "far" else "far"
		ai.mode_t = U.rand(7.0, 9.0) if (ai.mode == "far") == (ai.far_like > 0.5) else U.rand(4.0, 5.0)
		ai.side = -ai.side
	var vx := dx * sp * k * 1.1
	var vy := dy * sp * k * 1.1
	var nd := dir_to(x, y, pl.x, pl.y)
	if ai.mode == "far":
		if dist < 170.0:
			vx = -nd[0] * sp
			vy = -nd[1] * sp
		elif dist < 300.0:
			# circles around you
			vx = -nd[1] * sp * 0.55 * ai.side
			vy = nd[0] * sp * 0.55 * ai.side
	if ai.cd <= 0.0:
		var cid := ""
		if ai.mode == "close":
			var ok: Array = ai.melee.filter(func(m): return dist < 125.0 if m == "slam" else dist < 320.0)
			# now and then it also shoots when close
			if not ok.is_empty() and randf() < 0.8:
				cid = U.pick(ok)
			elif dist < 480.0:
				cid = U.pick(ai.ranged)
		else:
			if dist < 115.0:
				cid = "slam"
			elif dist < 430.0:
				cid = U.pick(ai.ranged)
		if cid != "":
			boss_start(cid, pl)
	return [vx, vy, "Walk"]

func enrage() -> void:
	ai.fury = true
	spd *= 1.15
	var S := Sim.cur
	S.spawner.say("¡" + name + " se ha enfurecido!", 2.4)
	S.fx.ring(x, y, r, r * 5.0, Color.html("#ff4a4a"), 0.6, 5.0)
	S.cam.kick(0.5)
	Sfx.play("boss")

func _col() -> Color:
	return Data.type_color.get(atk_type, SHOT_COLOR)

func boss_start(cid: String, pl: Body) -> void:
	var S := Sim.cur
	var f := 0.8 if ai.fury else 1.0
	var type := atk_type
	var col := _col()
	var ang := atan2(pl.y - y, pl.x - x)
	var c := {"id": cid, "t": 0.0, "wind": 0.6 * f, "after": 0.35, "ang": ang}
	ai.cast = c
	match cid:
		"slam":            # stomp: shockwave around it
			c["wind"] = 0.85 * f
			S.hazards.zone(x, y, 96.0 + r, c["wind"], dmg * 1.3, type, col, "boss")
			anim.play("Charge", 1.2)
		"dash":            # straight charge
			c["wind"] = 0.75 * f
			c["len"] = 330.0
			c["dur"] = 0.32
			S.hazards.beam(x, y, ang, 330.0 + r, r * 2.0 + 16.0, c["wind"] + c["dur"], dmg * 1.2, type, col, "boss")
			anim.play("Charge", 1.3)
		"leap":            # jumps and lands on you
			jump = {"sx": x, "sy": y, "tx": pl.x, "ty": pl.y, "t": -0.5 * f, "dur": 0.65}
			S.hazards.zone(pl.x, pl.y, 82.0, 0.5 * f + 0.65, dmg * 1.25, type, col, "boss")
			anim.play("Charge", 1.4)
			ai.cast = {}
			ai.cd = U.rand(1.4, 2.0) + 0.6
		"rain":            # zones falling around you
			var n := 6 if ai.fury else 4
			for i in n:
				var a := randf() * U.TAU_JS if i > 0 else 0.0
				var d := U.rand(40.0, 120.0) if i > 0 else 0.0
				S.hazards.zone(pl.x + cos(a) * d, pl.y + sin(a) * d * 0.8, 50.0, 1.05 + i * 0.12, shot_dmg() * 1.15, type, col, "boss")
			c["wind"] = 0.5
			anim.play("Shoot")
		"beam":            # fan of beams
			var n := 5 if ai.fury else 3
			var spr := 0.42 if ai.fury else 0.5
			for i in n:
				S.hazards.beam(x, y, ang + (i - (n - 1) / 2.0) * spr, 400.0, 26.0, 1.0, shot_dmg() * 1.2, type, col, "boss")
			c["wind"] = 1.0
			c["after"] = 0.25
			anim.play("Charge", 1.1)
		"volley", "nova":  # fan / ring of shots
			c["wind"] = (0.7 if cid == "nova" else 0.5) * f
			anim.play("Charge", 1.4)
			S.fx.ring(x, y, r, r * 2.4, col, c["wind"], 2.0)

func _boss_cast(dt: float, pl: Player) -> Array:
	var c := ai.cast
	c["t"] = float(c["t"]) + dt
	var t: float = c["t"]
	if c["id"] == "dash" and t >= float(c["wind"]):
		if not c.get("go", false):
			c["go"] = true
			anim.play("Attack", 1.6)
		if t >= float(c["wind"]) + float(c["dur"]):
			return _boss_end()
		var s := float(c["len"]) / float(c["dur"])
		return [cos(c["ang"]) * s, sin(c["ang"]) * s, "Walk"]
	if t >= float(c["wind"]) and not c.get("fired", false):
		c["fired"] = true
		var nd := dir_to(x, y, pl.x, pl.y)
		if c["id"] == "volley":
			shoot(nd[0], nd[1], 1.1, 9 if ai.fury else 7, 0.8)
		elif c["id"] == "nova":
			var n := 18 if ai.fury else 14
			shoot(nd[0], nd[1], 6.2832 * (n - 1) / n, n, 0.7)
		elif c["id"] == "slam":
			anim.play("Attack", 1.4)
	if t >= float(c["wind"]) + float(c["after"]):
		return _boss_end()
	return [0.0, 0.0, "Idle"]

func _boss_end() -> Array:
	ai.cast = {}
	ai.cd = U.rand(1.3, 2.0)
	if ai.fury and randf() < 0.35:
		ai.cd = 0.3          # chains another one
	return [0.0, 0.0, "Idle"]

# ---------------- shots and specials ----------------

## Shot damage: def.shotDmg scaled like its contact damage (time, DMG_K, elite, enrage).
func shot_dmg() -> float:
	return float(def.get("shotDmg", 10.0) if def.get("shotDmg", 0.0) else 10.0) * (dmg / float(def["dmg"]))

## Normal enemy shot (one, or several in a fan).
func shoot(ax: float, ay: float, spread := 0.0, n := 1, k := 1.0) -> void:
	var S := Sim.cur
	var base := atan2(ay, ax)
	for i in n:
		var a := base + (0.0 if n == 1 else (float(i) / (n - 1) - 0.5) * spread)
		var p := Projectiles.Proj.new()
		p.x = x
		p.y = y
		p.vx = cos(a) * 190.0
		p.vy = sin(a) * 190.0
		p.dmg = shot_dmg() * k
		p.r = 7.0
		p.life = 2.4
		p.friendly = false
		p.color = SHOT_COLOR
		p.mtype = atk_type
		p.vis = VFX.for_type(atk_type)
		S.projectiles.add(p)
	anim.play("Shoot")
	S.fx.ring(x, y - U.LIFT, 4.0, 14.0, SHOT_COLOR, 0.2, 2.0)

## What each keep-distance personality does when its timer fires.
func special(pl: Body, dx: float, dy: float) -> void:
	var S := Sim.cur
	var col := _col()
	match behavior:
		"fan":
			var n := int(def.get("fanN", 5)) if def.get("fanN", 0) else 5
			shoot(dx, dy, 0.6 if n == 3 else 0.9, n, 0.65)
		"beamer":
			# telegraphed beam: the strip shows on the ground first
			S.hazards.beam(x, y, atan2(dy, dx), 360.0, 22.0, 1.0, shot_dmg() * 1.05, atk_type, col, behavior)
			anim.play("Charge", 1.2)
		"zoner":
			var n := U.rand_int(1, int(def.get("zones", 3)) if def.get("zones", 0) else 3)
			for i in n:
				S.hazards.zone(pl.x + (U.rand(-70, 70) if i > 0 else 0.0), pl.y + (U.rand(-55, 55) if i > 0 else 0.0), 44.0,
					1.2, shot_dmg() * 0.95, atk_type, col, behavior)
			anim.play("Shoot")
		"healer":
			heal_around()
		"summoner":
			summon()
		_:
			shoot(dx, dy)

## Heals 7% of max HP (more the harder the player hits, capped x2.5) to hurt allies nearby.
func heal_around() -> void:
	var S := Sim.cur
	var pw := 1.0
	var p := S.player
	if p != null and p.atk() > 0.0 and p.base_atk > 0.0:
		pw = maxf(1.0, p.atk() / p.base_atk)
	var k := 0.07 * minf(2.5, pow(pw, 0.35))
	var n := 0
	for e in S.enemies.query_circle(x, y, 150.0):
		if e.dead or e.hp >= e.max_hp:
			continue
		e.hp = minf(e.max_hp, e.hp + e.max_hp * k)
		S.fx.burst(e.x, e.y - e.body_h * 0.6, Color.html("#7dffb0"), 5, 60.0)
		n += 1
	anim.play("Charge")
	S.fx.ring(x, y, 8.0, 150.0, Color.html("#5fe08a"), 0.5, 3.0)
	if n > 0 and S.cam.sees(x, y, 0.0):
		Sfx.play("heal")

## Shields (35% of max HP, 8 s) for the 6 nearest allies (itself included).
func cast_shields() -> void:
	var S := Sim.cur
	var near: Array = S.enemies.query_circle(x, y, 160.0).filter(func(e: Enemy): return not e.dead)
	near.sort_custom(func(a: Enemy, b: Enemy): return U.dist2(a.x, a.y, x, y) < U.dist2(b.x, b.y, x, y))
	for e: Enemy in near.slice(0, 6):
		e.shield = maxf(e.shield, e.max_hp * 0.35)
		e.shield_t = 8.0
	anim.play("Charge")
	S.fx.ring(x, y, 8.0, 160.0, Color.html("#7fc8ff"), 0.5, 3.0)

## Two minions (at most 4 alive, and never above the cap + 15).
func summon() -> void:
	var S := Sim.cur
	minions = minions.filter(func(m: Enemy): return not m.dead and S.enemies.get_enemy(m.id) != null)
	if minions.size() >= 4 or S.enemies.count() > Spawner.CAP + 15:
		return
	var d := int(def.get("minion", dex)) if def.get("minion", 0) else dex
	var mon: Dictionary = Data.dex_by.get(d, {})
	var mdef := {"dex": d, "name": mon.get("name", ""), "hp": U.jround(float(def["hp"]) * 0.35),
		"spd": U.jround(float(def["spd"]) * 1.1), "dmg": U.jround(float(def["dmg"]) * 0.6),
		"xp": maxf(1.0, U.jround(float(def["xp"]) * 0.25)), "behavior": "chase"}
	for i in 2:
		var a := randf() * U.TAU_JS
		var m := Enemy.new(mdef, x + cos(a) * 30.0, y + sin(a) * 22.0, sc if not sc.is_empty() else {"hp": 1.0, "spd": 1.0, "dmg": 1.0})
		S.enemies.add(m)
		minions.append(m)
		S.fx.burst(m.x, m.y - 8.0, Color.html("#c47bff"), 8, 90.0)
	anim.play("Charge")
	S.fx.ring(x, y, 8.0, 50.0, Color.html("#c47bff"), 0.4, 3.0)

## Bomber: stands still blinking for 1 s, then explodes (the zone fires even if it dies).
func start_fuse() -> void:
	phase = "fuse"
	pt = 1.0
	Sim.cur.hazards.zone(x, y, 62.0, 1.0, dmg * 1.4, atk_type, Color.html("#ff7b3d"), "bomber")

func start_jump(pl: Body) -> void:
	jump = {"sx": x, "sy": y, "tx": pl.x, "ty": pl.y, "t": -0.45, "dur": 0.6}
	anim.play("Charge", 1.4)
	Sim.cur.hazards.zone(pl.x, pl.y, 50.0, 1.05, dmg * 1.2, atk_type, _col(), "jumper")

## Jump: crouches, flies in an arc (over walls) and lands where you were.
func _update_jump(dt: float) -> void:
	var j := jump
	j["t"] = float(j["t"]) + dt
	if j["t"] < 0.0:
		anim.loop("Idle")
		return
	var k := minf(1.0, float(j["t"]) / float(j["dur"]))
	x = j["sx"] + (j["tx"] - j["sx"]) * k
	y = j["sy"] + (j["ty"] - j["sy"]) * k
	jump_lift = sin(k * PI) * 46.0
	anim.dir = Sprites.dir_from_angle(atan2(j["ty"] - j["sy"], j["tx"] - j["sx"]))
	if k >= 1.0:
		jump = {}
		jump_lift = 0.0
		if not flying:
			Sim.cur.world.collide(self)
		anim.play("Attack", 1.4)

## Contact hit animation (called by Combat when it touches you).
func strike(pl: Player) -> void:
	if not anim.busy():
		anim.dir = Sprites.dir_from_angle(atan2(pl.y - y, pl.x - x))
		anim.play("Attack", 1.5)
