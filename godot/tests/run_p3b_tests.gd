extends SceneTree
## Phase 3b (interactables, events, rifts, bonds) tests only — the same checks run_tests.gd runs:
##   godot --headless --path godot --script res://tests/run_p3b_tests.gd

var passes := 0
var fails := 0

func _initialize() -> void:
	seed(20261013)
	Data.ensure()
	EnemyDefs.set_mode("tier")      # the JS vectors are computed with the tier model (tools/export_godot.js)
	Phase3bTests.run(self)
	print("== %d passed, %d failed ==" % [passes, fails])
	quit(1 if fails > 0 else 0)

func check(name: String, ok: bool, detail := "") -> void:
	if ok:
		passes += 1
	else:
		fails += 1
	print("  %s  %s%s" % ["PASS" if ok else "FAIL", name, ("  (" + detail + ")") if detail != "" else ""])
