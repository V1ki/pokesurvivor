class_name WorldProp
extends Body
## A scenery object placed by WorldMap.place_props (js/world/world.js makeProp): tree, rock,
## chest, grass and the interactables altar, spring, bigchest, trap (logic in Phase 3b's
## sim/interact.gd). (x, y) are the FEET: x = tx*32 + 16, y = ty*32 + 28.

var id := 0
var type := ""
var tx := 0
var ty := 0
var kind := 0                 # altar power 0-3 / trap kind 0-2
var hp := INF
var max_hp := INF
var solid := false
var flat := false             # spring / trap: drawn flat on the ground, under everything
var destructible := false
var flash := 0.0
var wiggle := 0.0             # H(tx, ty, 9) * 6.28 (grass sway / halo phase)
var used := false             # altar
var charge := 1.0             # spring
var open := 0.0               # bigchest unlock progress (s)
