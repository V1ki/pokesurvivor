class_name Types
extends RefCounted
## Softened type chart (js/data/types.js): game x2 / x0.5 / x0 become x1.6 / x0.6 / x0.3,
## dual types multiply, clamped to [0.3, 2.4].

const MIN := 0.3
const MAX := 2.4

static func soft(v: float) -> float:
	if v == 2.0:
		return 1.6
	if v == 0.5:
		return 0.6
	if v == 0.0:
		return 0.3
	return 1.0

## Multiplier of an attack of type `atk` against a Pokémon of types `def`.
static func mult(atk: String, def: Array) -> float:
	var row: Dictionary = Data.type_chart.get(atk, {})
	if row.is_empty() or def.is_empty():
		return 1.0
	var m := 1.0
	for t in def:
		if row.has(t):
			m *= soft(float(row[t]))
	return U.clampf_(m, MIN, MAX)

## "super" | "weak" | "" (label for the damage number colour).
static func label(m: float) -> String:
	if m > 1.05:
		return "super"
	if m < 0.95:
		return "weak"
	return ""
