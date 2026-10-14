class_name Body
extends RefCounted
## Anything with feet on the ground plane that collides with terrain: (x, y) are the FEET.
## Positions are GDScript floats (64-bit), like JS numbers.

var x := 0.0
var y := 0.0
var r := 8.0            # collision radius (wu)
var body_h := 24.0      # visual height (HP bar / damage number anchor)
var dead := false
var is_enemy := false
