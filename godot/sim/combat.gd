class_name Combat
extends RefCounted
## Runs the active slot's moves and resolves every hit (js/systems/combat.js). Every
## `kind` is implemented here. Things that stay on the map for a while (mines, falling
## meteors, turrets, trail patches) live in `fields` and are updated here and drawn by
## render/world_view.gd. Everything happens on the ground plane: (x, y) are feet/shadows.
## Props take hits (World.damage_prop) and the weather scales damage by type (Weather.mult_of).

const TARGETED := ["melee", "beam", "projectile", "boomerang", "chain", "meteor", "dash", "cone"]
const CRIT_MUL := 1.5

## A persistent field: mine | meteor | turret | patch.
class Field:
	var kind := ""
	var owner: Player = null
	var m: Dictionary = {}
	var col := Color.WHITE
	var vis: Dictionary = {}
	var x := 0.0
	var y := 0.0
	var t := 0.0
	var life := 0.0          # 0 = no lifetime (meteors)
	var arm := 0.0
	var r := 0.0
	var dmg := 0.0
	var tick := 0.0
	var fall := 0.0
	var shot_t := 0.0
	var kick := 0.0
	var gone := false

var fields: Array[Field] = []

## Player shots this run: fired, stopped by a wall / indestructible prop, spent on a rock or
## chest (tests/sim_play.gd). Bookkeeping only.
var shot_stats := {"fired": 0, "wall": 0, "prop": 0}

func clear_fields(owner: Player = null) -> void:
	if owner == null:
		fields.clear()
	else:
		fields.assign(fields.filter(func(f: Field): return f.owner != owner))

func field_count() -> int:
	return fields.size()

# ---------------- casting ----------------

func tick(dt: float, pl: Player, now: float) -> void:
	if pl.dead:
		return
	# bonds: every move of the active slot ticks with its own cooldown
	for m in pl.active_group():
		_tick_move(dt, pl, m, now)

func _tick_move(dt: float, pl: Player, m: Dictionary, now: float) -> void:
	if m["kind"] == "orbit":
		_orbit(pl, m, dt, now)
		return
	m["t"] = float(m["t"]) - dt
	if m["t"] > 0.0:
		return
	# targeted moves wait for a target (don't waste the animation in the air)
	if TARGETED.has(m["kind"]) and not (pl.target != null and U.dist(pl.x, pl.y, pl.target.x, pl.target.y) <= reach(m)):
		m["t"] = 0.05
		return
	m["t"] = maxf(0.05, float(m["cd"]) * pl.cd_mul)
	pl.cast(m)
	m["cast_at"] = Time.get_ticks_msec()
	run(pl, m)

func run(pl: Player, m: Dictionary) -> void:
	match m["kind"]:
		"projectile":
			_fire_projectiles(pl, m)
		"melee":
			_melee(pl, m)
		"beam":
			_beam(pl, m)
		"nova":
			_nova(pl, m)
		"aura":
			_aura(pl, m)
		"buff":
			_buff(pl, m)
		"boomerang":
			_boomerang(pl, m)
		"chain":
			_chain(pl, m)
		"mine":
			_mines(pl, m)
		"meteor":
			_meteors(pl, m)
		"turret":
			_turret(pl, m)
		"dash":
			_dash(pl, m)
		"trail":
			_trail_patch(pl, m)
		"cone":
			_cone(pl, m)

static func reach(m: Dictionary) -> float:
	match m["kind"]:
		"melee":
			return float(m["radius"]) + 30.0
		"beam":
			return float(m["radius"]) + 20.0
		"boomerang":
			return float(m["radius"]) + 40.0
		"chain":
			return 280.0
		"meteor":
			return 340.0
		"dash":
			return float(m["radius"]) + 60.0
		"cone":
			return float(m["speed"]) * float(m["life"]) + 30.0
	return 520.0

static func pal_of(m: Dictionary) -> String:
	return VFX.for_move(m).get("pal", m.get("type", "normal"))

static func _f(m: Dictionary, k: String, def := 0.0) -> float:
	var v: Variant = m.get(k)
	return def if v == null else float(v)

## Player shot record (fireProjectiles / nova / cone / boomerang / turret payload).
func _shot(pl: Player, m: Dictionary, x: float, y: float, a: float, speed: float, life: float, dmg: float) -> Projectiles.Proj:
	shot_stats["fired"] += 1
	var p := Projectiles.Proj.new()
	p.x = x
	p.y = y
	p.vx = cos(a) * speed
	p.vy = sin(a) * speed
	p.dmg = dmg
	p.r = _f(m, "size", 6.0)
	p.life = life
	p.pierce = int(_f(m, "pierce"))
	p.color = Data.tcolor(m["type"])
	p.homing = _f(m, "homing")
	p.owner = pl
	p.burn = _f(m, "burn")
	p.poison = _f(m, "poison")
	p.slow = _f(m, "slow")
	p.knock = _f(m, "knock")
	p.mtype = m["type"]
	p.vis = VFX.for_move(m)
	return p

func _fire_projectiles(pl: Player, m: Dictionary) -> void:
	var S := Sim.cur
	var n := maxi(1, int(_f(m, "count", 1)))
	var spread := _f(m, "spread")
	for i in n:
		var off := 0.0 if n == 1 else (float(i) / (n - 1) - 0.5) * spread * n
		var a := pl.aim + off + U.rand(-0.03, 0.03)
		S.projectiles.add(_shot(pl, m, pl.x + cos(a) * 3.0, pl.y + sin(a) * 3.0, a, float(m["speed"]), float(m["life"]), float(m["dmg"]) * pl.atk()))
	var col := Data.tcolor(m["type"])
	S.fx.spark(pl.x + cos(pl.aim) * pl.r, pl.y - U.LIFT + sin(pl.aim) * pl.r, col, cos(pl.aim), sin(pl.aim), 3)

func _nova(pl: Player, m: Dictionary) -> void:
	var S := Sim.cur
	var n := maxi(3, int(_f(m, "count", 1)))
	for i in n:
		var a := (float(i) / n) * U.TAU_JS + U.rand(-0.06, 0.06)
		S.projectiles.add(_shot(pl, m, pl.x + cos(a) * 3.0, pl.y + sin(a) * 3.0, a, float(m["speed"]), float(m["life"]), float(m["dmg"]) * pl.atk()))
	S.fx.ring(pl.x, pl.y, pl.r, pl.r * 4.0, Data.tcolor(m["type"]), 0.3, 3.0)

static func in_arc(px: float, py: float, x: float, y: float, aim: float, half: float) -> bool:
	var a := atan2(y - py, x - px)
	return absf(fmod(a - aim + PI * 3.0, 6.2832) - PI) <= half

func _melee(pl: Player, m: Dictionary) -> void:
	var S := Sim.cur
	var col := Data.tcolor(m["type"])
	var arc := float(m["arc"])
	var radius := float(m["radius"])
	var half := minf(arc, 6.2832) / 2.0
	S.fx.slash(pl.x, pl.y - U.LIFT * 0.5, pl.aim, radius, arc, VFX.for_move(m))
	for e in S.enemies.query_circle(pl.x, pl.y, radius):
		if not in_arc(pl.x, pl.y, e.x, e.y, pl.aim, half):
			continue
		_hit(pl, e, float(m["dmg"]) * pl.atk(), col, e.x - pl.x, e.y - pl.y, _f(m, "knock"), m)
	for p in S.world.props_in_circle(pl.x, pl.y, radius):
		if in_arc(pl.x, pl.y, p.x, p.y, pl.aim, half):
			S.world.damage_prop(p, float(m["dmg"]) * pl.atk(), col)

func _beam(pl: Player, m: Dictionary) -> void:
	var S := Sim.cur
	var col := Data.tcolor(m["type"])
	var w := float(m["width"])
	var ca := cos(pl.aim)
	var sa := sin(pl.aim)
	var radius := float(m["radius"])
	# the beam stops at the first wall
	var len := radius
	var d := 8.0
	while d < radius:
		if S.world.is_wall(pl.x + ca * d, pl.y + sa * d):
			len = d
			break
		d += 8.0
	S.fx.beam(pl.x, pl.y - U.LIFT, pl.aim, len, w, VFX.for_move(m))
	S.cam.kick(0.08)
	var mx := pl.x + ca * len / 2.0
	var my := pl.y + sa * len / 2.0
	for e in S.enemies.query_circle(mx, my, len / 2.0 + w):
		var px := e.x - pl.x
		var py := e.y - pl.y
		var along := px * ca + py * sa
		if along < -e.r or along > len + e.r:
			continue
		if absf(-px * sa + py * ca) <= w / 2.0 + e.r:
			_hit(pl, e, float(m["dmg"]) * pl.atk(), col, ca, sa, 0.0, m)
	for p in S.world.props_in_circle(mx, my, len / 2.0 + w):
		var px := p.x - pl.x
		var py := p.y - pl.y
		var along := px * ca + py * sa
		if along < -p.r or along > len + p.r:
			continue
		if absf(-px * sa + py * ca) <= w / 2.0 + p.r:
			S.world.damage_prop(p, float(m["dmg"]) * pl.atk(), col)

func _aura(pl: Player, m: Dictionary) -> void:
	var S := Sim.cur
	var col := Data.tcolor(m["type"])
	var radius := float(m["radius"])
	S.fx.ring(pl.x, pl.y, radius * 0.5, radius, col, 0.28, 2.0)
	var vis := VFX.for_move(m)
	var aura: String = vis.get("aura", "")
	if aura != "":
		for i in 5:
			var a := randf() * U.TAU_JS
			var r := radius * U.rand(0.45, 1.0)
			var x := pl.x + cos(a) * r
			var y := pl.y + sin(a) * r * 0.8 - U.LIFT * 0.5
			var vx: float
			var vy: float
			# Giga Drain pulls toward you; poison and shadows rise; the rest swirls
			if vis.get("inward", false):
				vx = -cos(a) * r * 2.2
				vy = -sin(a) * r * 1.8
			elif vis.get("rise", false):
				vx = U.rand(-10, 10)
				vy = -55.0
			else:
				vx = -sin(a) * 70.0
				vy = cos(a) * 55.0
			S.fx.sp(aura, vis["pal"], x, y, {"vx": vx, "vy": vy, "life": 0.42, "spin": U.rand(-6, 6) if VFX.spins(aura) else 0.0})
	var healed := 0.0
	for e in S.enemies.query_circle(pl.x, pl.y, radius):
		_hit(pl, e, float(m["dmg"]) * pl.atk(), col, e.x - pl.x, e.y - pl.y, 0.0, m)
		healed += float(m.get("drain", 0.0))        # combat.js: drain per enemy hit (no move has it yet)
	for p in S.world.props_in_circle(pl.x, pl.y, radius):
		S.world.damage_prop(p, float(m["dmg"]) * pl.atk(), col)
	if healed > 0.0:
		pl.heal(minf(healed, 6.0))

func _buff(pl: Player, m: Dictionary) -> void:
	var S := Sim.cur
	pl.add_buff(m["stat"], float(m["amount"]), float(m["dur"]), int(_f(m, "stacks")))
	S.fx.ring(pl.x, pl.y, pl.r * 2.4, pl.r * 1.1, Data.tcolor(m["type"]), 0.35, 2.5)
	var vis := VFX.for_move(m)
	for i in 3:
		S.fx.sp(vis.get("buff", "arrow"), vis["pal"], pl.x + U.rand(-pl.r * 1.4, pl.r * 1.4),
			pl.y - U.rand(0.0, pl.body_h * 0.8), {"vy": -70.0, "life": 0.6})

## Boomerang: flies out, stops and comes back, hitting on the way out and back.
func _boomerang(pl: Player, m: Dictionary) -> void:
	var S := Sim.cur
	var n := maxi(1, int(_f(m, "count", 1)))
	var spread := _f(m, "spread")
	if spread == 0.0:
		spread = 0.5
	var speed := float(m["speed"])
	var out := float(m["radius"]) / speed               # seconds out
	for i in n:
		var a := pl.aim + (0.0 if n == 1 else (float(i) / (n - 1) - 0.5) * spread * mini(n, 3))
		var p := _shot(pl, m, pl.x, pl.y, a, speed, out * 4.0 + 1.5, float(m["dmg"]) * pl.atk())
		p.pierce = 999
		p.boom = out
		p.bsp = speed * 1.1
		S.projectiles.add(p)

## Chain: hits one enemy and jumps to the next nearest ones (a bit weaker each hop).
func _chain(pl: Player, m: Dictionary) -> void:
	var S := Sim.cur
	var col := Data.tcolor(m["type"])
	var vis := VFX.for_move(m)
	var cur: Enemy = null
	if pl.target is Enemy and not (pl.target as Enemy).dead:
		cur = pl.target
	else:
		cur = S.projectiles.nearest(S.enemies.list, pl.x, pl.y, reach(m))
	if cur == null:
		return
	var fx := pl.x
	var fy := pl.y - U.LIFT
	var k := 1.0
	var done := {}
	var n := maxi(1, int(_f(m, "count", 1)))
	var radius := float(m["radius"])
	var i := 0
	while i < n and cur != null:
		done[cur.id] = true
		var tx := cur.x
		var ty := cur.y - cur.body_h * 0.5
		S.fx.beam(fx, fy, atan2(ty - fy, tx - fx), sqrt((tx - fx) * (tx - fx) + (ty - fy) * (ty - fy)), 10.0, vis)
		# Hex: more damage to whoever already suffers a status
		var hx := 1.0
		if _f(m, "hex") != 0.0 and (cur.burn > 0.0 or cur.poison > 0.0 or cur.slow > 0.0):
			hx = float(m["hex"])
		_hit(pl, cur, float(m["dmg"]) * pl.atk() * k * hx, col, tx - fx, ty - fy, 0.0, m)
		k *= 0.85
		fx = tx
		fy = ty
		var best: Enemy = null
		var bd := radius * radius
		for e in S.enemies.query_circle(cur.x, cur.y, radius):
			if done.has(e.id):
				continue
			var d := U.dist2(cur.x, cur.y, e.x, e.y)
			if d < bd:
				bd = d
				best = e
		cur = best
		i += 1
	S.cam.kick(0.05)

## Mines stay on the ground and blow up when an enemy steps on them.
func _mines(pl: Player, m: Dictionary) -> void:
	var n := maxi(1, int(_f(m, "count", 1)))
	for i in n:
		var a := randf() * U.TAU_JS
		var d := 0.0 if n == 1 else U.rand(18.0, 46.0)
		var f := _field("mine", pl, m, pl.x + cos(a) * d, pl.y + sin(a) * d * 0.8)
		f.arm = 0.35
		f.life = _f(m, "dur", 7.0) if _f(m, "dur") != 0.0 else 7.0
		f.r = float(m["radius"])
	# a few per player at most: the oldest ones go
	var mine: Array = fields.filter(func(o: Field): return o.kind == "mine" and o.owner == pl)
	for j in maxi(0, mine.size() - (4 + n * 2)):
		mine[j].gone = true

## Meteors fall on nearby enemies (the shadow shows where).
func _meteors(pl: Player, m: Dictionary) -> void:
	var S := Sim.cur
	var n := maxi(1, int(_f(m, "count", 1)))
	var near: Array = S.enemies.query_circle(pl.x, pl.y, reach(m)).filter(func(e: Enemy): return not e.dead)
	near.shuffle()
	for i in n:
		var e: Enemy = near[i] if i < near.size() else null
		var x := e.x + U.rand(-8, 8) if e != null else pl.x + U.rand(-140, 140)
		var y := e.y + U.rand(-6, 6) if e != null else pl.y + U.rand(-110, 110)
		var f := _field("meteor", pl, m, x, y)
		f.t = -i * 0.09
		f.fall = 0.5
		f.r = float(m["radius"])

## Turret: something on the ground that shoots by itself for a while.
func _turret(pl: Player, m: Dictionary) -> void:
	var a := pl.aim + PI + U.rand(-0.6, 0.6)
	var f := _field("turret", pl, m, pl.x + cos(a) * 26.0, pl.y + sin(a) * 20.0)
	f.life = _f(m, "dur", 6.0) if _f(m, "dur") != 0.0 else 6.0
	f.shot_t = 0.3
	var mine: Array = fields.filter(func(o: Field): return o.kind == "turret" and o.owner == pl and not o.gone)
	for j in maxi(0, mine.size() - maxi(1, int(_f(m, "count", 1)))):
		mine[j].gone = true
	Sim.cur.fx.ring(pl.x, pl.y, 4.0, 30.0, f.col, 0.3, 2.0)

## Dash: you cross like lightning toward the enemy and hit everything on the way.
func _dash(pl: Player, m: Dictionary) -> void:
	var S := Sim.cur
	var col := Data.tcolor(m["type"])
	var vis := VFX.for_move(m)
	var ca := cos(pl.aim)
	var sa := sin(pl.aim)
	var sx := pl.x
	var sy := pl.y
	var len := 0.0
	var radius := float(m["radius"])
	var d := 8.0
	while d <= radius:
		if not S.world.is_free(sx + ca * d, sy + sa * d, pl.r * 0.8, true):
			break
		len = d
		d += 8.0
	# trail: copies of the strike along the way
	var dd := 0.0
	while dd <= len:
		S.fx.sp(vis.get("proj", "streak"), vis["pal"], sx + ca * dd, sy + sa * dd - U.LIFT * 0.6, {"life": 0.22, "angle": pl.aim})
		dd += 22.0
	S.fx.slash(sx + ca * len, sy + sa * len - U.LIFT * 0.5, pl.aim, 34.0, 2.2, vis)
	pl.x = sx + ca * len
	pl.y = sy + sa * len
	S.world.collide(pl)
	pl.invuln = maxf(pl.invuln, 0.3)
	var w := _f(m, "width", 34.0) if _f(m, "width") != 0.0 else 34.0
	var mx := sx + ca * len / 2.0
	var my := sy + sa * len / 2.0
	for e in S.enemies.query_circle(mx, my, len / 2.0 + w):
		var rr := w / 2.0 + e.r
		if seg_dist2(sx, sy, pl.x, pl.y, e.x, e.y) <= rr * rr:
			_hit(pl, e, float(m["dmg"]) * pl.atk(), col, ca, sa, _f(m, "knock"), m)
	for p in S.world.props_in_circle(mx, my, len / 2.0 + w):
		if seg_dist2(sx, sy, pl.x, pl.y, p.x, p.y) <= (w / 2.0 + p.r) * (w / 2.0 + p.r):
			S.world.damage_prop(p, float(m["dmg"]) * pl.atk(), col)
	S.cam.kick(0.12)

## Trail: you leave patches behind that hurt whatever walks over them.
func _trail_patch(pl: Player, m: Dictionary) -> void:
	var radius := float(m["radius"])
	# standing still: no new patch on top of the last one (only now and then)
	var last: Field = pl.last_patch.get_ref() if pl.last_patch != null else null
	if last != null and U.dist2(last.x, last.y, pl.x, pl.y) < (radius * 0.9) * (radius * 0.9) and last.t < 1.0:
		return
	var f := _field("patch", pl, m, pl.x, pl.y)
	f.life = _f(m, "dur", 3.0) if _f(m, "dur") != 0.0 else 3.0
	f.r = radius
	f.tick = 0.0
	pl.last_patch = weakref(f)
	var mine: Array = fields.filter(func(o: Field): return o.kind == "patch" and o.owner == pl and not o.gone)
	for j in maxi(0, mine.size() - 18):
		mine[j].gone = true

## Short cone: many quick shots that don't go far (breath, spray...).
func _cone(pl: Player, m: Dictionary) -> void:
	var S := Sim.cur
	var n := maxi(2, int(_f(m, "count", 1)))
	var arc := _f(m, "arc")
	if arc == 0.0:
		arc = 0.9
	for i in n:
		var a := pl.aim + (float(i) / (n - 1) - 0.5) * arc + U.rand(-0.05, 0.05)
		var sp := float(m["speed"]) * U.rand(0.85, 1.1)
		S.projectiles.add(_shot(pl, m, pl.x + cos(a) * 4.0, pl.y + sin(a) * 4.0, a, sp, float(m["life"]) * U.rand(0.85, 1.05), float(m["dmg"]) * pl.atk()))
	var col := Data.tcolor(m["type"])
	S.fx.spark(pl.x + cos(pl.aim) * pl.r, pl.y - U.LIFT + sin(pl.aim) * pl.r, col, cos(pl.aim), sin(pl.aim), 5)

func _field(kind: String, pl: Player, m: Dictionary, x: float, y: float) -> Field:
	var f := Field.new()
	f.kind = kind
	f.owner = pl
	f.m = m
	f.col = Data.tcolor(m["type"])
	f.vis = VFX.for_move(m)
	f.x = x
	f.y = y
	f.dmg = float(m["dmg"]) * pl.atk()
	fields.append(f)
	return f

## Damage of a field (mine, meteor, patch) to everything in its circle.
func _blast(f: Field, r: float, k := 1.0) -> void:
	var S := Sim.cur
	for e in S.enemies.query_circle(f.x, f.y, r):
		_hit(f.owner, e, f.dmg * k, f.col, e.x - f.x, e.y - f.y, _f(f.m, "knock"), f.m)
	for p in S.world.props_in_circle(f.x, f.y, r):
		S.world.damage_prop(p, f.dmg * k, f.col)

func update_fields(dt: float) -> void:
	var S := Sim.cur
	for i in range(fields.size() - 1, -1, -1):
		if i >= fields.size():
			continue
		var f := fields[i]
		f.t += dt
		if f.gone or f.owner == null or (f.life > 0.0 and f.t >= f.life and f.kind != "mine"):
			fields.remove_at(i)
			continue
		match f.kind:
			"mine":
				var armed := f.t >= f.arm
				var trig := armed and not S.enemies.query_circle(f.x, f.y, 14.0).is_empty()
				if trig or f.t >= f.life:
					S.fx.ring(f.x, f.y, 4.0, f.r, f.col, 0.3, 4.0)
					S.fx.burst(f.x, f.y - 6.0, f.col, 10, 150.0)
					if S.cam.sees(f.x, f.y, 40.0):
						Sfx.play("break")
					fields.remove_at(i)
					_blast(f, f.r, 1.0 if trig else 0.5)
			"meteor":
				if f.t >= f.fall:
					S.fx.ring(f.x, f.y, 4.0, f.r, f.col, 0.35, 4.0)
					S.fx.burst(f.x, f.y - 6.0, f.col, 12, 170.0)
					if S.cam.sees(f.x, f.y, 40.0):
						Sfx.play("break")
						S.cam.kick(0.12)
					fields.remove_at(i)
					_blast(f, f.r)
			"turret":
				f.shot_t -= dt
				if f.shot_t <= 0.0:
					var m := f.m
					var rng := _f(m, "range", 300.0) if _f(m, "range") != 0.0 else 300.0
					var tg := S.projectiles.nearest(S.enemies.list, f.x, f.y, rng)
					var rate := _f(m, "rate", 0.6) if _f(m, "rate") != 0.0 else 0.6
					f.shot_t = rate if tg != null else 0.15
					if tg != null:
						var a := atan2(tg.y - f.y, tg.x - f.x)
						var spd := _f(m, "speed", 300.0) if _f(m, "speed") != 0.0 else 300.0
						var p := _shot(f.owner, m, f.x, f.y, a, spd, 1.4, f.dmg)
						p.r = _f(m, "size", 6.0) if _f(m, "size") != 0.0 else 6.0
						p.color = f.col
						S.projectiles.add(p)
						f.kick = 0.12
				if f.kick > 0.0:
					f.kick -= dt
			"patch":
				f.tick -= dt
				if f.tick <= 0.0:
					f.tick = 0.5
					_blast(f, f.r)
				var aura: String = f.vis.get("aura", "")
				if aura != "" and randf() < dt * 3.0 and S.cam.sees(f.x, f.y, 20.0):
					S.fx.sp(aura, f.vis["pal"], f.x + U.rand(-f.r, f.r) * 0.6, f.y - 4.0, {"vy": -40.0, "life": 0.4})

## Orbit: keeps `count` orbs alive around the player; re-hit interval max(0.12, cd).
func _orbit(pl: Player, m: Dictionary, dt: float, now: float) -> void:
	var S := Sim.cur
	var want := maxi(1, int(_f(m, "count", 1)))
	var orbs: Array = []
	for p in S.projectiles.list:
		if p.orb and p.owner == pl and p.mid == m["id"]:
			orbs.append(p)
	var relayout := orbs.size() != want
	var base: float = orbs[0].oa if not orbs.is_empty() else now * float(m["speed"])
	if orbs.size() > want:
		for k in range(want, orbs.size()):
			S.projectiles.remove(orbs[k])
	for i in range(orbs.size(), want):
		var p := Projectiles.Proj.new()
		p.orb = true
		p.owner = pl
		p.mid = m["id"]
		p.x = pl.x
		p.y = pl.y
		p.r = float(m["size"])
		p.color = Data.tcolor(m["type"])
		p.vis = VFX.for_move(m)
		p.dmg = float(m["dmg"]) * pl.atk()
		p.oa = (float(i) / want) * 6.2832
		p.orad = float(m["radius"])
		p.ospeed = float(m["speed"])
		p.rehit = maxf(0.12, float(m["cd"]))
		p.life = INF
		p.pierce = 1 << 30
		p.knock = _f(m, "knock")
		p.burn = _f(m, "burn")
		p.poison = _f(m, "poison")
		p.slow = _f(m, "slow")
		p.mtype = m["type"]
		S.projectiles.add(p)
	var live: Array = []
	for p in S.projectiles.list:
		if p.orb and p.owner == pl and p.mid == m["id"]:
			live.append(p)
	for i in live.size():
		var p: Projectiles.Proj = live[i]
		p.dmg = float(m["dmg"]) * pl.atk()
		p.orad = float(m["radius"])
		p.ospeed = float(m["speed"])
		p.r = float(m["size"])
		if relayout:
			p.oa = base + (float(i) / live.size()) * 6.2832
	# a Charge animation now and then so it looks alive
	pl.orb_cast_t -= dt
	if pl.orb_cast_t <= 0.0:
		pl.orb_cast_t = 1.6
		pl.cast({"kind": "orbit", "cd": 1.6})

# ---------------- hits ----------------

## Crit (Mejoras -> Golpe Crítico): x1.5 damage, big orange number.
func _is_crit(pl: Player) -> bool:
	return pl.crit_chance > 0.0 and randf() < pl.crit_chance

## Player -> enemy damage: dmg * type chart * crit (§4.5) and the move's statuses.
func _hit(pl: Player, e: Enemy, dmg: float, col: Color, dx: float, dy: float, knock: float, m: Dictionary) -> void:
	var tk := Types.mult(m["type"], e.types)
	var crit := _is_crit(pl)
	dmg *= tk * Weather.mult_of(m["type"]) * (CRIT_MUL if crit else 1.0)
	e.hurt(dmg, col, dx, dy, knock, "crit" if crit else Types.label(tk))
	pl.on_dealt(dmg)
	pl.dmg_dealt += dmg
	if _f(m, "burn") != 0.0:
		e.apply_burn(float(m["burn"]))
	if _f(m, "poison") != 0.0:
		e.apply_poison(float(m["poison"]))
	if _f(m, "slow") != 0.0:
		e.apply_slow(float(m["slow"]))

## Distance² from point (cx, cy) to segment (ax, ay)-(bx, by).
static func seg_dist2(ax: float, ay: float, bx: float, by: float, cx: float, cy: float) -> float:
	var dx := bx - ax
	var dy := by - ay
	var l2 := dx * dx + dy * dy
	var t := ((cx - ax) * dx + (cy - ay) * dy) / l2 if l2 > 0.0 else 0.0
	t = clampf(t, 0.0, 1.0)
	var qx := ax + dx * t - cx
	var qy := ay + dy * t - cy
	return qx * qx + qy * qy

## Projectile hits (swept), enemy shots and contact damage.
func resolve(_dt: float, pl: Player, now: float) -> void:
	var S := Sim.cur
	var list := S.projectiles.list
	var i := list.size() - 1
	while i >= 0:
		if i >= list.size():
			i = list.size() - 1
			continue
		var p := list[i]
		i -= 1
		# --- enemy shots: walls and solid props give cover ---
		if not p.friendly:
			if S.world.projectile_block(p.x, p.y, p.r) != "":
				S.fx.burst(p.x, p.y - U.LIFT, p.color, 5, 70.0)
				list.erase(p)
				continue
			if U.dist2(p.x, p.y, pl.x, pl.y) < (p.r + pl.r) * (p.r + pl.r):
				pl.hurt(p.dmg, p.mtype, "shot")
				S.fx.burst(p.x, p.y - U.LIFT, p.color, 7, 110.0)
				list.erase(p)
			continue
		# --- player shots ---
		if not p.orb:
			var block: Variant = S.world.projectile_block_any(p.x, p.y, p.r)
			if block is String or (block != null and not (block as WorldProp).destructible):
				shot_stats["wall"] += 1
				S.fx.burst(p.x, p.y - U.LIFT, p.color, 5, 80.0)
				list.erase(p)
				continue
		# scenery (rocks, chests, grass): grass never stops a shot, solid ones use up pierce
		var consumed := false
		for prop in S.world.props_in_circle(p.x, p.y, p.r):
			if p.orb:
				var pk := "p%d" % prop.id
				var plast: float = p.hit_log.get(pk, -99.0)
				if now - plast < p.rehit:
					continue
				p.hit_log[pk] = now
				S.world.damage_prop(prop, p.dmg, p.color)
				continue
			if p.phits.has(prop.id):
				continue
			p.phits[prop.id] = true
			S.world.damage_prop(prop, p.dmg, p.color)
			if prop.solid:
				if p.pierce > 0:
					p.pierce -= 1
				else:
					consumed = true
					break
		if consumed:
			shot_stats["prop"] += 1
			S.fx.burst(p.x, p.y - U.LIFT, p.color, 5, 80.0)
			list.erase(p)
			continue
		# Enemies. SWEPT collision over the whole segment moved this frame: a fast shot
		# moves ~8 wu/frame and used to tunnel through enemies hugging the player.
		var sx := p.x if (p.orb or not p.has_prev) else p.px
		var sy := p.y if (p.orb or not p.has_prev) else p.py
		var half := U.dist(sx, sy, p.x, p.y) / 2.0
		for e in S.enemies.query_circle((sx + p.x) / 2.0, (sy + p.y) / 2.0, half + p.r):
			if seg_dist2(sx, sy, p.x, p.y, e.x, e.y) > (p.r + e.r) * (p.r + e.r):
				continue
			if p.orb:
				var last: float = p.hit_log.get(e.id, -99.0)
				if now - last < p.rehit:
					continue
				p.hit_log[e.id] = now
				# orbs live all run: forget old hits
				if p.hit_log.size() > 300:
					for k in p.hit_log.keys():
						if now - float(p.hit_log[k]) > p.rehit:
							p.hit_log.erase(k)
			else:
				if p.hits.has(e.id):
					continue
				p.hits[e.id] = true
			var crit := _is_crit(pl)
			var tm := Types.mult(p.mtype, e.types) if p.mtype != "" else 1.0
			var k := tm * (Weather.mult_of(p.mtype) if p.mtype != "" else 1.0) * (CRIT_MUL if crit else 1.0)
			var lbl := "crit" if crit else (Types.label(tm) if p.mtype != "" else "")
			var ddx := p.vx if p.vx != 0.0 else e.x - pl.x
			var ddy := p.vy if p.vy != 0.0 else e.y - pl.y
			e.hurt(p.dmg * k, p.color, ddx, ddy, p.knock, lbl)
			if randf() < 0.5:
				S.fx.sp("impact", p.pal, e.x, e.y - e.body_h * 0.5, {"life": 0.12, "scale": 1.0})
			pl.dmg_dealt += p.dmg * k
			pl.on_dealt(p.dmg * k)
			if p.burn > 0.0:
				e.apply_burn(p.burn)
			if p.poison > 0.0:
				e.apply_poison(p.poison)
			if p.slow > 0.0:
				e.apply_slow(p.slow)
			if not p.orb:
				if p.pierce > 0:
					p.pierce -= 1
				else:
					S.fx.burst(p.x, p.y - U.LIFT, p.color, 5, 80.0)
					list.erase(p)
					break

	# --- enemy <-> player contact ---
	if pl.dead:
		return
	for e in S.enemies.query_circle(pl.x, pl.y, pl.r + 40.0):
		if U.dist2(e.x, e.y, pl.x, pl.y) > (e.r + pl.r) * (e.r + pl.r):
			continue
		if e.touch_cd > 0.0 or e.behavior == "thief":
			continue
		e.touch_cd = 0.55
		e.strike(pl)
		pl.hurt(e.dmg, e.atk_type, "boss" if e.boss else "touch:" + e.behavior)
		if pl.has_item("rockyhelmet"):
			e.hurt(15.0 + pl.level * 4.0, Color.html("#9aa6b5"), e.x - pl.x, e.y - pl.y, 80.0)
		var n := U.norm(e.x - pl.x, e.y - pl.y)
		e.kx += n.x * 150.0
		e.ky += n.y * 150.0
