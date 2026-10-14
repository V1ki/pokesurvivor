class_name Hazards
extends RefCounted
## Telegraphed enemy attacks (js/systems/hazards.js). A hazard is first drawn on the
## ground as a warning that fills up; at `delay` it detonates once and hurts the player if
## inside (ignoring i-frames). Enemies are never hurt by hazards.
##   zone  circle (ground/fire/poison zones, explosions, jump landings)
##   beam  straight strip from the caster (electric, psychic, dragon, ice)

class Hazard:
	var kind := "zone"
	var x := 0.0
	var y := 0.0
	var r := 0.0
	var angle := 0.0
	var len := 0.0
	var w := 0.0
	var delay := 1.0
	var dmg := 0.0
	var type := "normal"
	var color := Color.WHITE
	var t := 0.0
	var hit := false
	var end := 0.3

var list: Array[Hazard] = []

func clear() -> void:
	list.clear()

func count() -> int:
	return list.size()

## Circle zone centred on (x, y).
func zone(x: float, y: float, r: float, delay: float, dmg: float, type: String, color: Color) -> Hazard:
	var h := Hazard.new()
	h.kind = "zone"
	h.x = x
	h.y = y
	h.r = r
	h.delay = delay
	h.dmg = dmg
	h.type = type
	h.color = color
	list.append(h)
	return h

## Strip from (x, y) along `angle`, `len` long and `w` wide.
func beam(x: float, y: float, angle: float, len: float, w: float, delay: float, dmg: float, type: String, color: Color) -> Hazard:
	var h := Hazard.new()
	h.kind = "beam"
	h.x = x
	h.y = y
	h.angle = angle
	h.len = len
	h.w = w
	h.delay = delay
	h.dmg = dmg
	h.type = type
	h.color = color
	list.append(h)
	return h

## Is a body of radius r at (x, y) inside? (only 60% of the radius counts)
static func inside(h: Hazard, x: float, y: float, r: float) -> bool:
	if h.kind == "zone":
		var rr := h.r + r * 0.6
		return U.dist2(x, y, h.x, h.y) < rr * rr
	var ca := cos(h.angle)
	var sa := sin(h.angle)
	var px := x - h.x
	var py := y - h.y
	var along := px * ca + py * sa
	if along < -r or along > h.len + r:
		return false
	return absf(-px * sa + py * ca) <= h.w / 2.0 + r * 0.6

func update(dt: float, pl: Player) -> void:
	for i in range(list.size() - 1, -1, -1):
		var h := list[i]
		h.t += dt
		if not h.hit and h.t >= h.delay:
			h.hit = true
			_detonate(h)
			if pl != null and not pl.dead and inside(h, pl.x, pl.y, pl.r):
				pl.invuln = 0.0
				pl.hurt(h.dmg, h.type)
		if h.hit and h.t >= h.delay + h.end:
			list.remove_at(i)

func _detonate(h: Hazard) -> void:
	var S := Sim.cur
	var near := S.cam.sees(h.x, h.y, 120.0)
	if h.kind == "zone":
		S.fx.ring(h.x, h.y, 4.0, h.r, h.color, 0.35, 5.0)
		S.fx.burst(h.x, h.y - 6.0, h.color, U.jroundi(h.r / 3.0), 160.0)
		if near:
			Sfx.play("break")
			if h.r > 60.0:
				S.cam.kick(0.35)
	else:
		S.fx.beam(h.x, h.y - U.LIFT, h.angle, h.len, h.w, VFX.for_type(h.type))
		if near:
			Sfx.play("shot", {"kind": "beam", "type": h.type})
