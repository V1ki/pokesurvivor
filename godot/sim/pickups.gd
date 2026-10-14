class_name Pickups
extends RefCounted
## XP gems and loot (js/entities/pickup.js). Gems sit still until you enter the magnet
## radius; then they are pulled forever ("sticky"). Above MAX the two oldest XP gems merge.
## Pickups never expire.

const MAX := 420
const BOSS_T10 := 1.0 / 3.0
const LEGEND_T10 := 1.0 / 2.0
const TICKET_RATE := 1.0 / 400.0

## kind -> {color, glow, r}
const KIND := {
	"xp": {"color": "#7fe0ff", "glow": "#2a8fd0", "r": 4.5},
	"xpBig": {"color": "#ffd95e", "glow": "#c08a10", "r": 7.0},
	"heal": {"color": "#5fe08a", "glow": "#1f8f4d", "r": 6.5},
	"magnet": {"color": "#ff9ed8", "glow": "#b03d84", "r": 6.5},
	"bomb": {"color": "#ff7b3d", "glow": "#b03d10", "r": 6.5},
	"coin": {"color": "#ffd23f", "glow": "#b8860b", "r": 5.5},
	"ticket": {"color": "#ffd23f", "glow": "#c08a10", "r": 7.0},
	"ticket10": {"color": "#c47bff", "glow": "#8a3fd0", "r": 8.0},
	"item": {"color": "#ffd23f", "glow": "#c08a10", "r": 9.0},
}

class Pickup:
	var id := 0
	var kind := "xp"
	var x := 0.0
	var y := 0.0
	var value: Variant = 0.0      # XP / coins, or item id
	var vx := 0.0
	var vy := 0.0
	var t := 0.0
	var pulled := false

var list: Array[Pickup] = []
var _next_id := 1

func clear() -> void:
	list.clear()

func count() -> int:
	return list.size()

static func is_xp(p: Pickup) -> bool:
	return p.kind == "xp" or p.kind == "xpBig"

func _push(o: Pickup) -> void:
	o.id = _next_id
	_next_id += 1
	list.append(o)
	if list.size() > MAX:
		# merge the oldest XP gem into the next oldest one
		var i := -1
		for k in list.size():
			if is_xp(list[k]):
				i = k
				break
		if i >= 0:
			var a: Pickup = list.pop_at(i)
			for k in list.size():
				if is_xp(list[k]):
					list[k].value = float(list[k].value) + float(a.value)
					list[k].kind = "xpBig"
					break
		else:
			list.pop_front()

static func make(kind: String, x: float, y: float, value: Variant) -> Pickup:
	var a := randf() * U.TAU_JS
	var s := U.rand(10.0, 46.0)
	var o := Pickup.new()
	o.kind = kind
	o.x = x
	o.y = y
	o.value = value
	o.vx = cos(a) * s
	# JS draws two independent speeds for vx and vy
	o.vy = sin(a) * U.rand(10.0, 46.0)
	o.t = randf() * 6.28
	return o

## Magnet pickup: everything flies to the player.
func pull_all() -> void:
	for o in list:
		o.pulled = true

func drop_xp(x: float, y: float, value: float, boss := false, legend := false) -> void:
	if boss:
		for i in 14:
			var a := randf() * U.TAU_JS
			var d := U.rand(10.0, 70.0)
			_push(make("xpBig", x + cos(a) * d, y + sin(a) * d, ceilf(value / 14.0)))
		_push(make("heal", x + 24.0, y, 0.0))
		_push(make("magnet", x - 24.0, y, 0.0))
		if randf() < (LEGEND_T10 if legend else BOSS_T10):
			_push(make("ticket10", x, y - 20.0, 1.0))
		return
	_push(make("xpBig" if value >= 20.0 else "xp", x, y, value))
	if randf() < TICKET_RATE:
		_push(make("ticket", x + U.rand(-6.0, 6.0), y, 1.0))
	# occasional drops
	var r := randf()
	if r < 0.012:
		_push(make("heal", x + U.rand(-8.0, 8.0), y, 0.0))
	elif r < 0.020:
		_push(make("magnet", x, y, 0.0))
	elif r < 0.026:
		_push(make("bomb", x, y, 0.0))

func drop(kind: String, x: float, y: float, value: Variant = 0.0) -> void:
	_push(make(kind, x, y, value))

## on_collect(pickup, player) is called for each collected pickup.
func update(dt: float, pl: Player, on_collect: Callable) -> void:
	var mag2 := pl.magnet * pl.magnet
	for i in range(list.size() - 1, -1, -1):
		if i >= list.size():
			continue
		var p := list[i]
		p.t += dt * 4.0
		var dx := pl.x - p.x
		var dy := pl.y - p.y
		var d2 := dx * dx + dy * dy
		if p.pulled or d2 < mag2:
			p.pulled = true
			var d := sqrt(d2)
			if d == 0.0:
				d = 1.0
			var pull := 240.0 + 1400.0 / d
			p.vx = U.damp(p.vx, (dx / d) * pull, 7.0, dt)
			p.vy = U.damp(p.vy, (dy / d) * pull, 7.0, dt)
		else:
			var f := pow(0.02, dt)
			p.vx *= f
			p.vy *= f
		p.x += p.vx * dt
		p.y += p.vy * dt
		if d2 < 15.0 * 15.0:
			list.remove_at(i)
			on_collect.call(p, pl)
