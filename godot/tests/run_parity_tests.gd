extends SceneTree
var passes := 0
var fails := 0
func _initialize() -> void:
	Data.ensure()
	ParityTests.run(self)
	print("== %d passed, %d failed ==" % [passes, fails])
	quit(1 if fails > 0 else 0)
func check(name: String, ok: bool, detail := "") -> void:
	if ok:
		passes += 1
		print("  PASS  ", name, ("  (" + detail + ")") if detail != "" else "")
	else:
		fails += 1
		print("  FAIL  ", name, ("  (" + detail + ")") if detail != "" else "")
