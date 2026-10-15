class_name Sim
extends RefCounted
## The whole run simulation, renderer-agnostic (js/game.js update/run lifecycle).
## The Game node drives it with real input and draws it; the headless tests drive it
## with scripted input. `Sim.cur` plays the role of the JS global namespace `G`.
##
## States (§1.3): "ui" | "playing" | "levelup" | "choice" (held-item swap or bond picker) | "paused" | "over".

signal level_up_ready(level: int, cards: Array)
signal run_over(result: Dictionary)
signal item_choice_ready(cur: String, next: String)
signal bond_ready(opt: Dictionary)

static var cur: Sim = null

var cam := SimCamera.new()
var world := WorldMap.new()
var fx := FX.new()
var enemies := EnemyMgr.new()
var projectiles := Projectiles.new()
var pickups := Pickups.new()
var combat := Combat.new()
var spawner := Spawner.new()
var defs := EnemyDefs.new()
var hazards := Hazards.new()
var pathing := Pathing.new()
var interact := Interact.new()     # altars, springs, locked chests, traps (Phase 3b)
var rift := Rift.new()             # rifts + legendary arena (Phase 3b)
var events := Events.new()         # hordes, golden hour, lost Pokémon, thieves (Phase 3b)
var weather := Weather.new()       # rare weather event: damage by type, snow slow, sand/snow chip (Phase 3a)

var player: Player = null
var state := "ui"
var time := 0.0
var pending_levels := 0
var biome := 0
var death_t := 0.0
var input_axis := Vector2.ZERO     # movement vector from keyboard / joystick (length <= 1)
var render := true                 # false for headless sims (no sprite preloading)
var offer: Array = []              # current level-up cards
var result: Dictionary = {}        # last results screen data
var caught: Array = []             # wild shinies caught this run: {dex, isNew}
var item_choice: Array = []        # [current, new] while state == "choice"
var bond_opt: Dictionary = {}      # Player.bond_options() while the bond picker is open (state "choice")
var flash_col := Color.WHITE       # full-screen flash (rift travel, game.js flash)
var flash_t := 0.0
var flash_dur := 1.0
## Debug options applied by start_run (main.gd --learn/--boss-at/--force-shiny, smoke test):
##   moves: [ids] learned at start · move_lvl: int · boss_at: s of the 1st boss · boss_gap: s
##   between bosses · force_shiny: next N spawns shiny · item: held item at start · start_t: run clock
var debug: Dictionary = {}

func _init() -> void:
	Data.ensure()
	Sim.cur = self

# ---------------- run lifecycle ----------------

## opts (Phase 4 meta-progression, all optional): {shiny: bool, perks: Families.perks() (or
## Upgrades.perks()), bind: [moveId|null x4] (save.pbind[dex]), start_moves: [moveId] and pool:
## [moveId] (Families.start_moves / pool_of: what it starts with and what the cards may offer),
## ban: [moveId] (old saves' Veto, without start_moves)} — game.js startRun.
func start_run(partner_dex := 4, seed := -1, opts := {}) -> void:
	Sim.cur = self
	var perks: Dictionary = opts.get("perks", {})
	var shiny: bool = opts.get("shiny", false)
	if render:
		Sprites.load_now(partner_dex, shiny)     # before the spawner queues the cast's threaded loads
	fx.clear()
	projectiles.clear()
	combat.clear_fields()
	enemies.clear()
	pickups.clear()
	spawner.reset()
	pathing.clear()
	hazards.clear()
	rift.reset()
	events.reset()
	weather.reset()
	world.async_chunks = render      # game: field terrain on worker threads; headless: sync
	world.reset(seed if seed >= 0 else randi() % 1000000)
	world.set_biome(0, true)
	biome = 0
	time = 0.0
	pending_levels = 0
	offer = []
	result = {}
	caught = []
	item_choice = []
	bond_opt = {}
	flash_t = 0.0
	player = Player.new(Data.dex_by[partner_dex], perks, shiny)
	_apply_meta(opts, perks)
	_apply_debug()
	cam.x = player.x
	cam.y = player.y
	cam.shake = 0.0
	cam.calm = Settings.calm
	Sfx.music("forest")
	death_t = 0.0
	state = "playing"

## Hotkeys, start move, bans and the Repertoire 2nd move (game.js startRun, Phase 4).
func _apply_meta(opts: Dictionary, perks: Dictionary) -> void:
	var bind: Array = opts.get("bind", [])
	for i in mini(4, bind.size()):
		if bind[i] is String:
			player.bind[bind[i]] = i
	if opts.has("start_moves"):
		# its family's moves (core/families.gd): the cards offer only those
		player.move_pool = (opts.get("pool", []) as Array).duplicate()
		for id in opts["start_moves"]:
			if Data.move_by.has(id):
				player.add_move(id)
		player.set_active(0)
		return
	player.add_move(Moves.start_move_of(player.dex))
	var ban: Array = opts.get("ban", [])
	for id in ban.slice(0, int(perks.get("bans", 0))):
		player.banned[id] = true
	if int(perks.get("startMoves", 1)) >= 2:
		var pool: Array = Moves.pool_for(player.mon).filter(func(id): return not player.has_move(id) \
			and not player.banned.has(id) and Moves.def(id).get("kind", "") != "buff")
		if not pool.is_empty():
			player.add_move(U.pick(pool))
		player.set_active(0)

## Coins formula and summary (endRun). The save is updated by Meta.apply_run (main.gd).
func end_run(dead := true) -> void:
	if state == "over" or player == null:
		return
	state = "over"
	Sfx.music("")
	Sfx.play("gameover" if dead else "back")
	var rw := Meta.run_coins(time, player.kills, player.bosses, player.coins, player.coin_mul)
	var coins: int = rw["coins"]
	var mv: Array = []
	for m in player.moves:
		mv.append({"id": m["id"], "name": m["name"], "lvl": m["lvl"], "type": m["type"]})
	result = {"dead": dead, "time": time, "level": player.level, "kills": player.kills, "bosses": player.bosses,
		"coins": coins, "t1": player.t1, "t10": player.t10, "moves": mv, "breakdown": rw["breakdown"],
		"caught": caught.duplicate()}
	run_over.emit(result)

## quiet: game.js autoPause (the app went to the background) pauses without the sound.
func toggle_pause(quiet := false) -> void:
	if state == "playing":
		state = "paused"
		if not quiet:
			Sfx.play("pause")
	elif state == "paused":
		state = "playing"

## Debug options (see `debug`): learn moves, early bosses, forced shinies, start item.
func _apply_debug() -> void:
	if debug.is_empty():
		return
	if not (debug.get("moves", []) as Array).is_empty():
		# forced moves replace the starting one
		player.moves.clear()
		player.slots.clear()
		player.active = 0
		for id in debug["moves"]:
			if Data.move_by.has(id):
				player.add_move(id)
		player.set_active(0)
	var lv := int(debug.get("move_lvl", 1))
	for m in player.moves:
		while int(m["lvl"]) < mini(lv, Moves.max_lvl(m)):
			Moves.level_up(m)
		if debug.get("evolve", false) and int(m["lvl"]) >= Moves.max_lvl(m):
			Moves.evolve(m)
	if debug.has("boss_at"):
		var gap := float(debug.get("boss_gap", 90.0))
		for i in defs.bosses.size():
			defs.bosses[i]["at"] = float(debug["boss_at"]) + i * gap
	spawner.force_shiny = int(debug.get("force_shiny", 0))
	if debug.has("start_t"):
		# start the run clock later (perf tests at the enemy cap); earlier bosses are skipped
		time = float(debug["start_t"])
		while spawner.boss_idx < defs.bosses.size() and float(defs.bosses[spawner.boss_idx]["at"]) < time:
			spawner.boss_idx += 1
		biome = int(floor(time / 240.0))
		world.set_biome(biome, true)
	if str(debug.get("item", "")) != "":
		player.equip(debug["item"])
	_apply_debug_3b()

## Phase 3b debug options: events / rifts / bonds on demand (debug/autoshot2.gd parses them).
##   events: [[at_s, "horde"|"gold"|"lost"|"thief"], ...] · rift_at: s · rift_type: type · bonds: n
func _apply_debug_3b() -> void:
	events.debug_queue = (debug.get("events", []) as Array).duplicate(true)
	if debug.has("rift_at"):
		rift.debug_open_at = float(debug["rift_at"])
	rift.next_type = str(debug.get("rift_type", ""))
	player.bonds = int(debug.get("bonds", 0))

# ---------------- level-up ----------------

func maybe_level_up() -> void:
	if pending_levels <= 0 or state != "playing":
		return
	# never open cards with the Pokémon down (died and collected XP in the same frame)
	if player.dead:
		return
	pending_levels -= 1
	state = "levelup"
	Sfx.play("levelup")
	offer = LevelUp.offer(player)
	level_up_ready.emit(player.level, offer)

func rerolls_left() -> int:
	return maxi(0, 1 + player.reroll_bonus - player.rerolls) if player != null else 0

func reroll() -> bool:
	if state != "levelup" or rerolls_left() <= 0:
		return false
	player.rerolls += 1
	Sfx.play("select")
	offer = LevelUp.offer(player)
	level_up_ready.emit(player.level, offer)
	return true

func pick_card(i: int) -> bool:
	if state != "levelup" or i < 0 or i >= offer.size():
		return false
	var c: Dictionary = offer[i]
	offer = []
	Sfx.play("confirm")
	(c["apply"] as Callable).call(player)
	state = "playing"
	return true

# ---------------- pickups ----------------

func on_collect(p: Pickups.Pickup, who: Player) -> void:
	Sfx.play({"xp": "xp", "xpBig": "xp", "coin": "coin", "heal": "heal", "bomb": "break", "magnet": "confirm",
		"ticket": "shiny", "ticket10": "legend", "item": "legend"}.get(p.kind, ""))
	match p.kind:
		"xp", "xpBig":
			pending_levels += player.gain_xp(float(p.value))
		"coin":
			player.coins += int(p.value)
			fx.dmg_text(who.x, who.y - who.body_h - 6.0, "+" + str(int(p.value)), Color.html("#ffd23f"))
		"ticket", "ticket10":
			if p.kind == "ticket":
				player.t1 += 1
			else:
				player.t10 += 1
			fx.dmg_text(who.x, who.y - who.body_h - 8.0, "+1 ticket" if p.kind == "ticket" else "¡Ticket ×10!",
				Color.html("#ffd23f" if p.kind == "ticket" else "#d9a6ff"), true)
			fx.ring(who.x, who.y, 6.0, 50.0, Color.html("#ffd23f" if p.kind == "ticket" else "#c47bff"), 0.4, 3.0)
		"heal":
			player.heal(player.max_hp * 0.3)
			fx.ring(who.x, who.y, 6.0, 60.0, Color.html("#5fe08a"), 0.4, 3.0)
		"magnet":
			pickups.pull_all()
			fx.ring(who.x, who.y, 10.0, 420.0, Color.html("#ff9ed8"), 0.6, 4.0)
		"bomb":
			cam.kick(0.8)
			fx.ring(who.x, who.y, 20.0, cam.outer_radius(), Color.html("#ff7b3d"), 0.5, 6.0)
			# every enemy ON SCREEN takes 60 + level*14
			for e in enemies.list.duplicate():
				if not cam.sees(e.x, e.y, 0.0):
					continue
				e.hurt(60.0 + player.level * 14.0, Color.html("#ff7b3d"), e.x - who.x, e.y - who.y, 160.0)
		"item":
			offer_item(str(p.value))

# ---------------- held items ----------------

## Picked up an item: wear it if empty-handed, else choose (the game pauses meanwhile).
func offer_item(id: String) -> void:
	if player == null or Items.by_id(id).is_empty():
		return
	if player.item == "":
		take_item(id)
		return
	if player.item == id:
		spawner.say("Ya llevas " + Items.name_of(id), 2.0)
		return
	if state == "playing":
		state = "choice"
	item_choice = [player.item, id]
	item_choice_ready.emit(player.item, id)

## Keeps / switches to `got` and closes the choice.
func take_item(got: String) -> void:
	if got != player.item:
		player.equip(got)
		spawner.say("¡Llevas " + Items.name_of(got) + "!", 2.6)
		Progress.event("item", {"id": got})
	item_choice = []
	if state == "choice":
		state = "playing"

## Choice screen: 0 = keep the current item, 1 = switch to the new one.
func choose_item(i: int) -> bool:
	if state != "choice" or item_choice.size() != 2 or i < 0 or i > 1:
		return false
	Sfx.play("click")             # run-ui.js: the card's UI click (keys 1/2 click the card too)
	take_item(item_choice[i])
	return true

# ---------------- shinies ----------------

# ---------------- bonds (move fusion, Phase 3b) ----------------

## Bond of a legendary: opens the fusion picker (state "choice") if two moves can join;
## otherwise the bond is kept until you learn another move (game.js offerBond). quiet: no message.
func offer_bond(quiet := false) -> void:
	if player == null or player.bonds <= 0 or player.dead or state != "playing" or rift.in_arena:
		return
	var opt := player.bond_options()
	if opt.is_empty():
		if not quiet:
			spawner.say("Guardas el vínculo: aprende otro movimiento para usarlo", 3.0)
		return
	state = "choice"
	bond_opt = opt
	Sfx.play("levelup")
	bond_ready.emit(opt)

## The picker's answer: the loose moves that join (1 in "add" mode, 2 in "pair" mode).
func choose_bond(picked: Array) -> bool:
	if state != "choice" or bond_opt.is_empty() or picked.is_empty():
		return false
	var group := player.fuse(picked, bond_opt["group"])
	bond_opt = {}
	Sfx.play("legend")
	fx.ring(player.x, player.y, 8.0, 130.0, Color.html("#ff8ad8"), 0.8, 6.0)
	fx.burst(player.x, player.y - player.body_h * 0.5, Color.html("#ffb3e6"), 40, 240.0)
	spawner.say("¡Vínculo! " + str(group.size()) + " movimientos a la vez", 2.6)
	state = "playing"
	return true

# ---------------- rift / events helpers (Phase 3b) ----------------

## Full-screen flash (game.js flash): alpha min(1, t/dur*1.4), drawn by the HUD.
func flash(col: String, dur: float) -> void:
	flash_col = Color.html(col)
	flash_dur = dur
	flash_t = dur

## A rescued lost Pokémon joins you (game.js G.onRescue): new -> collection, else +150 coins.
func on_rescue(dex: int, name: String) -> void:
	if player == null or not Save.loaded:
		return
	var is_new := not Save.owns(dex)
	if is_new:
		Save.grant(dex, "rescue")
		Save.commit()
	else:
		player.coins += 150
	spawner.say(("¡" + name + " se une a tu equipo!") if is_new else ("¡" + name + " te da las gracias! (+150 monedas, ya lo tenías)"), 4.0)
	Sfx.play("shinyGet")

## A wild shiny goes down: you keep it (catching = defeating it).
func on_shiny_caught(e: Enemy) -> void:
	if player == null:
		return
	var is_new := Progress.shiny_caught(e.dex)      # grants shiny + normal form, stats, commit
	caught.append({"dex": e.dex, "isNew": is_new})
	spawner.say(("¡Has conseguido a " + e.name + " shiny!") if is_new else ("¡Otro " + e.name + " shiny! (+300 monedas)"), 4.0)
	if not is_new:
		player.coins += 300
	Sfx.play("shinyGet")

# ---------------- frame ----------------

## Full simulation step while playing (update order of §1.4 — keep it).
func update(dt: float) -> void:
	if state != "playing" or player == null:
		return
	var pl := player
	# per-system timings (tests/bench.gd, [perf] lines): one static bool read when off
	var P := SimProf.on
	if P: SimProf.begin()
	if flash_t > 0.0:
		flash_t -= dt
	# after fainting, let the Faint animation play for 1.3 s before the results
	# (not in the rift arena: there falling only throws you back out)
	if pl.dead and not rift.in_arena:
		death_t += dt
		pl.update(dt)
		enemies.update(dt * 0.3, pl)
		fx.update(dt)
		cam.follow(pl.x, pl.y, dt)
		if death_t > 1.3:
			death_t = 0.0
			end_run(true)
		return
	time += dt

	var b := int(floor(time / 240.0))
	if b != biome and not rift.in_arena:
		biome = b
		world.set_biome(b)
		Sfx.play("biome")
		spawner.say("— " + world.biome_name() + " —", 3.0)
		fx.ring(pl.x, pl.y, 10.0, cam.outer_radius(), Color.WHITE, 0.7, 6.0)

	if P: SimProf.lap(SimProf.MISC)
	pl.update(dt)
	cam.follow(pl.x, pl.y, dt)
	if P: SimProf.lap(SimProf.PLAYER)
	world.update(dt)
	if P: SimProf.lap(SimProf.WORLD)
	pathing.update(dt, pl)
	if P: SimProf.lap(SimProf.PATHING)
	spawner.update(dt, pl, time)
	if P: SimProf.lap(SimProf.SPAWNER)
	enemies.update(dt, pl)                  # laps E_GRID, E_AI, E_SEP, E_CULL inside
	enemies.rebuild_grid()
	if P: SimProf.lap(SimProf.GRID)
	combat.tick(dt, pl, time)
	if P: SimProf.lap(SimProf.CAST)
	projectiles.update(dt, pl, enemies.list)
	if P: SimProf.lap(SimProf.PROJ)
	combat.resolve(dt, pl, time)
	if P: SimProf.lap(SimProf.RESOLVE)
	combat.update_fields(dt)
	if P: SimProf.lap(SimProf.FIELDS)
	pickups.update(dt, pl, on_collect)
	if P: SimProf.lap(SimProf.PICKUPS)
	hazards.update(dt, pl)
	if P: SimProf.lap(SimProf.HAZARDS)
	interact.update(dt, pl)
	rift.update(dt, pl, time)
	events.update(dt, pl, time)
	weather.update(dt, time, pl)
	if P: SimProf.lap(SimProf.EVENTS)
	fx.update(dt)
	if P: SimProf.lap(SimProf.FX)
	Sfx.music("rift" if rift.in_arena else ("boss" if enemies.boss_alive() else ["forest", "cave", "volcano"][biome % 3]))
	maybe_level_up()
	if pl.bonds > 0:
		offer_bond(true)
	if P: SimProf.lap(SimProf.MISC)

## Frozen states keep FX and the partner animation running at quarter speed.
func idle_tick(dt: float) -> void:
	if player != null and state != "ui" and state != "playing":
		fx.update(dt * 0.25)
		player.anim.update(dt * 0.25)
