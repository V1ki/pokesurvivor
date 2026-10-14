class_name StreamRng
extends RefCounted
## Math.random() stand-in for the Phase 3b systems (events, rifts). It draws from randf() in the
## game; the JS-reference tests load the exact stream of Math.random() values the JS code
## consumed (`seq`), so the same decisions come out in the same order (JS U.rand / pick / pickN).

var seq := PackedFloat64Array()
var i := 0

func next() -> float:
	if i < seq.size():
		i += 1
		return seq[i - 1]
	return randf()

## Remaining values of a test stream (0 in the game).
func left() -> int:
	return seq.size() - i

func feed(values: PackedFloat64Array) -> void:
	seq = values
	i = 0

func rand(a: float, b: float) -> float:
	return a + next() * (b - a)

func rand_int(a: int, b: int) -> int:
	return int(floorf(a + next() * (b - a + 1)))

func pick(arr: Array) -> Variant:
	if arr.is_empty():
		return null
	return arr[mini(int(floorf(next() * arr.size())), arr.size() - 1)]

## n distinct elements (G.U.pickN).
func pick_n(arr: Array, n: int) -> Array:
	var c := arr.duplicate()
	var out: Array = []
	while out.size() < n and not c.is_empty():
		out.append(c.pop_at(mini(int(floorf(next() * c.size())), c.size() - 1)))
	return out
