class_name FX
extends RefCounted
## Purely visual effects (port of js/entities/fx.js): square particles, VFX sprites,
## shiny twinkles, projectile trails, dotted rings, pixel slashes, beams and damage numbers.
## Nothing here affects gameplay. Drawn by render/world_view.gd (world space) and
## render/overlay.gd (damage texts, screen space).

const PX := 2.0
const CAP_PARTS := [350, 800, 1400]
const CAP_SPRITES := [110, 210, 320]
const CAP_TEXTS := [25, 45, 70]
const DENS := [0.35, 0.65, 1.0]

## A loose VFX sprite (or a shiny twinkle when `twinkle`).
class Spr:
	var shape := ""
	var pal := "normal"
	var x := 0.0
	var y := 0.0
	var vx := 0.0
	var vy := 0.0
	var t := 0.0
	var life := 0.4
	var scale := 1.0
	var angle := 0.0
	var spin := 0.0
	var grav := 0.0
	var fr := 10.0
	var fade := true
	var twinkle := false

class Ring:
	var x := 0.0
	var y := 0.0
	var r0 := 0.0
	var r1 := 0.0
	var color := Color.WHITE
	var life := 0.3
	var t := 0.0
	var width := 3.0

class Slash:
	var x := 0.0
	var y := 0.0
	var angle := 0.0
	var radius := 0.0
	var arc := 0.0
	var pal := "normal"
	var t := 0.0
	var life := 0.22

class Beam:
	var x := 0.0
	var y := 0.0
	var angle := 0.0
	var len := 0.0
	var width := 0.0
	var pal := "normal"
	var shape := ""           # sprite travelling along it, "lightning" = zigzag, "" = none
	var t := 0.0
	var life := 0.2
	var seed := 0.0

class Text:
	var x := 0.0
	var y := 0.0
	var vy := -46.0
	var t := 0.0
	var life := 0.62
	var s := ""
	var color := Color.WHITE
	var big := false
	# render/overlay.gd cache: translated string, its width at font size `tsize`, screen position
	var ts := ""
	var tw := 0.0
	var tsize := -1
	var tpos := Vector2.ZERO

## Square particles as a struct of arrays (hundreds alive: packed arrays are far cheaper than
## objects to update and draw). Particle i < n_parts: position, velocity, age / life, size in wu,
## gravity, drag (per 1/60 s) and colour.
var n_parts := 0
var p_x := PackedFloat64Array()
var p_y := PackedFloat64Array()
var p_vx := PackedFloat64Array()
var p_vy := PackedFloat64Array()
var p_t := PackedFloat64Array()
var p_life := PackedFloat64Array()
var p_s := PackedFloat64Array()
var p_grav := PackedFloat64Array()
var p_drag := PackedFloat64Array()
var p_col := PackedColorArray()
var sprites: Array[Spr] = []
var rings: Array[Ring] = []
var slashes: Array[Slash] = []
var beams: Array[Beam] = []
var texts: Array[Text] = []

func clear() -> void:
	n_parts = 0
	sprites.clear()
	rings.clear()
	slashes.clear()
	beams.clear()
	texts.clear()

func q() -> int:
	return clampi(Settings.fx, 0, 2)

# ---------------- particles ----------------

## Square particle. size is in art pixels.
func px(x: float, y: float, color: Color, vx := 0.0, vy := 0.0, life := 0.4, size := 1.0, grav := 0.0, drag := 0.9) -> void:
	var i := n_parts
	if i >= CAP_PARTS[q()]:
		return
	if i >= p_x.size():
		_grow(maxi(64, i * 2))
	p_x[i] = x
	p_y[i] = y
	p_vx[i] = vx
	p_vy[i] = vy
	p_t[i] = 0.0
	p_life[i] = life
	p_s[i] = size * PX
	p_grav[i] = grav
	p_drag[i] = drag
	p_col[i] = color
	n_parts = i + 1

func _grow(n: int) -> void:
	p_x.resize(n)
	p_y.resize(n)
	p_vx.resize(n)
	p_vy.resize(n)
	p_t.resize(n)
	p_life.resize(n)
	p_s.resize(n)
	p_grav.resize(n)
	p_drag.resize(n)
	p_col.resize(n)

## Live particles.
func part_count() -> int:
	return n_parts

func burst(x: float, y: float, color: Color, n := 8, power := 110.0) -> void:
	n = maxi(1, U.jroundi(n * DENS[q()]))
	for i in n:
		var a := randf() * U.TAU_JS
		var s := U.rand(power * 0.35, power)
		px(x, y, color, cos(a) * s, sin(a) * s, U.rand(0.22, 0.5), 2.0 if randf() < 0.35 else 1.0)

func spark(x: float, y: float, color: Color, dir_x: float, dir_y: float, n := 4) -> void:
	n = maxi(1, U.jroundi(n * DENS[q()]))
	var base := atan2(dir_y, dir_x)
	for i in n:
		var a := base + U.rand(-0.9, 0.9)
		var s := U.rand(60.0, 170.0)
		px(x, y, color, cos(a) * s, sin(a) * s, U.rand(0.14, 0.32))

## Loose effect sprite. o: {vx, vy, life, scale, angle, spin, grav, frame_rate, fade}
func sp(shape: String, pal: String, x: float, y: float, o: Dictionary = {}) -> void:
	if sprites.size() >= CAP_SPRITES[q()]:
		return
	var s := Spr.new()
	s.shape = shape
	s.pal = pal
	s.x = x
	s.y = y
	s.vx = o.get("vx", 0.0)
	s.vy = o.get("vy", 0.0)
	s.life = o.get("life", 0.4)
	s.scale = o.get("scale", 1.0)
	s.angle = o.get("angle", 0.0)
	s.spin = o.get("spin", 0.0)
	s.grav = o.get("grav", 0.0)
	s.fr = o.get("frame_rate", 10.0)
	s.fade = o.get("fade", true)
	sprites.append(s)

## Shiny sparkle (pixel cross that grows and fades).
func twinkle(x: float, y: float) -> void:
	if sprites.size() >= CAP_SPRITES[q()]:
		return
	var s := Spr.new()
	s.twinkle = true
	s.x = x
	s.y = y
	s.vy = -8.0
	s.life = U.rand(0.45, 0.7)
	sprites.append(s)

## Projectile trail particles by material (ember, drip, spark, bubbles, dirt, wisp).
func trail(kind: String, pal: String, x: float, y: float, vx: float, vy: float) -> void:
	if randf() > DENS[q()]:
		return
	var P := Data.pal(pal)
	var back := atan2(-vy, -vx)
	match kind:
		"ember":
			px(x + U.rand(-3, 3), y + U.rand(-3, 3), P[3 if randf() < 0.5 else 2], cos(back) * 30.0, -40.0, 0.35)
		"drip":
			px(x + U.rand(-3, 3), y + U.rand(-3, 3), P[3], cos(back) * 20.0, 10.0, 0.35, 1.0, 260.0)
		"spark":
			px(x + U.rand(-3, 3) * 2.0, y + U.rand(-3, 3) * 2.0, P[4] if randf() < 0.5 else P[3], U.rand(-60, 60), U.rand(-60, 60), 0.16)
		"bubbles":
			px(x + U.rand(-3, 3), y + U.rand(-3, 3), P[3], 0.0, -35.0, 0.45, 2.0 if randf() < 0.3 else 1.0)
		"dirt":
			px(x + U.rand(-3, 3), y + U.rand(-3, 3), P[2 if randf() < 0.5 else 1], cos(back) * 25.0, -20.0, 0.35, 1.0, 300.0)
		"wisp":
			px(x + U.rand(-3, 3) * 2.0, y + U.rand(-3, 3) * 2.0, P[1 if randf() < 0.5 else 2], 0.0, -30.0, 0.5, 2.0)

## Floating text. Numbers (or "-123") are hidden when the damage-numbers setting is off.
func dmg_text(x: float, y: float, value: Variant, color: Color, big := false) -> void:
	var s := str(value)
	var numeric := value is int or value is float or (s.length() > 1 and s[0] == "-" and s[1] >= "0" and s[1] <= "9")
	if numeric and not Settings.dmg_numbers:
		return
	if texts.size() >= CAP_TEXTS[q()]:
		if not big:
			return
		texts.pop_front()
	var t := Text.new()
	t.x = x + U.rand(-6.0, 6.0)
	t.y = y
	t.life = 0.95 if big else 0.62
	t.s = s
	t.color = color
	t.big = big
	texts.append(t)

## Expanding ring made of pixel dots.
func ring(x: float, y: float, r0: float, r1: float, color: Color, life := 0.3, width := 3.0) -> void:
	var r := Ring.new()
	r.x = x
	r.y = y
	r.r0 = r0
	r.r1 = r1
	r.color = color
	r.life = life
	r.width = width
	rings.append(r)

## Melee crescent. vis = VFX.for_move(m): {pal, melee?} (impact, jaws, claw, vine, feather).
func slash(x: float, y: float, angle: float, radius: float, arc: float, vis: Dictionary) -> void:
	var pal: String = vis.get("pal", "normal")
	var s := Slash.new()
	s.x = x
	s.y = y
	s.angle = angle
	s.radius = radius
	s.arc = arc
	s.pal = pal
	slashes.append(s)
	var mx := x + cos(angle) * radius * 0.7
	var my := y + sin(angle) * radius * 0.7
	match vis.get("melee", ""):
		"impact":
			sp("impact", pal, mx, my, {"life": 0.2, "scale": 1.5, "frame_rate": 12.0, "fade": false})
		"jaws":
			sp("jaws", pal, mx, my, {"life": 0.24, "scale": 1.5, "frame_rate": 9.0, "fade": false})
		"claw":
			sp("claw", pal, mx, my, {"life": 0.2, "scale": 1.5, "angle": angle - PI / 4.0})
		"vine", "feather":
			var leaf_pal := "flying" if vis.get("melee") == "feather" else pal
			for i in 4:
				var a := angle + U.rand(-arc / 2.0, arc / 2.0)
				var r := radius * U.rand(0.5, 1.0)
				sp("leaf", leaf_pal, x + cos(a) * r, y + sin(a) * r,
					{"vx": cos(a) * 40.0, "vy": sin(a) * 40.0 + 20.0, "life": 0.45, "spin": U.rand(-8, 8), "grav": 60.0})

## Straight beam. vis: {pal, beam?} — beam = sprite travelling along it or "lightning".
func beam(x: float, y: float, angle: float, len: float, width: float, vis: Dictionary) -> void:
	var pal: String = vis.get("pal", "normal")
	var b := Beam.new()
	b.x = x
	b.y = y
	b.angle = angle
	b.len = len
	b.width = width
	b.pal = pal
	b.shape = vis.get("beam", "")
	b.seed = randf() * 100.0
	beams.append(b)
	sp("impact", pal, x + cos(angle) * 10.0, y + sin(angle) * 10.0, {"life": 0.12, "scale": 1.0})
	sp("impact", pal, x + cos(angle) * len, y + sin(angle) * len, {"life": 0.18, "scale": 1.5})

# ---------------- update ----------------

func update(dt: float) -> void:
	# particles: same arithmetic as the old per-object loop, compacted in place
	var j := 0
	var k_def := pow(0.9, dt * 60.0)        # the default drag, computed once
	for i in n_parts:
		var t := p_t[i] + dt
		var life := p_life[i]
		if t >= life:
			continue
		var vy := p_vy[i] + p_grav[i] * dt
		var vx := p_vx[i]
		var dr := p_drag[i]
		var k := k_def if dr == 0.9 else pow(dr, dt * 60.0)
		p_x[j] = p_x[i] + vx * dt
		p_y[j] = p_y[i] + vy * dt
		p_vx[j] = vx * k
		p_vy[j] = vy * k
		p_t[j] = t
		if j != i:
			p_life[j] = life
			p_s[j] = p_s[i]
			p_grav[j] = p_grav[i]
			p_drag[j] = dr
			p_col[j] = p_col[i]
		j += 1
	n_parts = j
	j = 0
	for i in sprites.size():
		var s := sprites[i]
		s.t += dt
		if s.t >= s.life:
			continue
		s.vy += s.grav * dt
		s.x += s.vx * dt
		s.y += s.vy * dt
		if s.spin != 0.0:
			s.angle += s.spin * dt
		sprites[j] = s
		j += 1
	sprites.resize(j)
	for i in range(texts.size() - 1, -1, -1):
		var t := texts[i]
		t.t += dt
		if t.t >= t.life:
			texts.remove_at(i)
			continue
		t.y += t.vy * dt
		t.vy *= pow(0.94, dt * 60.0)      # JS: *= 0.94 per frame
	for i in range(rings.size() - 1, -1, -1):
		rings[i].t += dt
		if rings[i].t >= rings[i].life:
			rings.remove_at(i)
	for i in range(slashes.size() - 1, -1, -1):
		slashes[i].t += dt
		if slashes[i].t >= slashes[i].life:
			slashes.remove_at(i)
	for i in range(beams.size() - 1, -1, -1):
		beams[i].t += dt
		if beams[i].t >= beams[i].life:
			beams.remove_at(i)

func count() -> int:
	return n_parts + sprites.size() + texts.size()

## Alpha is quantized to 1 / .66 / .33 so effects look pixel-art.
static func step(k: float) -> float:
	return 1.0 if k > 0.66 else (0.66 if k > 0.33 else 0.33)
