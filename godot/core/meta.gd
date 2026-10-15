class_name Meta
extends RefCounted
## Glue between a run and the save (game.js startRun / bankTickets / endRun, Phase 4):
## run options from the trainer upgrades and the partner's family (core/families.gd), ticket
## banking, coins formula, end-of-run stats and family XP.

## End-of-run coins (game.js endRun): round((floor(t/5) + floor(kills/4) + 80*bosses + picked) * mul).
static func run_coins(time: float, kills: int, bosses: int, picked: int, mul: float) -> Dictionary:
	var parts := {"tiempo": int(floor(time / 5.0)), "derrotados": int(floor(kills * 0.25)),
		"jefes": bosses * 80, "recogidas": picked}
	var coins := U.jroundi((parts["tiempo"] + parts["derrotados"] + parts["jefes"] + parts["recogidas"]) * mul)
	var bd: Array = []
	for k in parts:
		if parts[k]:
			bd.append("%s %d" % [k, parts[k]])
	var txt := " · ".join(bd) + (" · ×%.2f Fortuna" % mul if mul > 1.0 else "")
	return {"coins": coins, "parts": parts, "breakdown": txt}

## Partner + Sim.start_run options for the saved partner: {dex, opts}. Perks: the trainer's
## upgrades + its family's level and stars; moves: the ones its family knows (game.js startRun).
static func run_setup(fallback_dex := 4) -> Dictionary:
	if not Save.loaded or Save.data.get("partner") == null:
		return {"dex": fallback_dex, "opts": {}}
	var s := Save.data
	var dex := Save.partner()
	var bind: Array = s["pbind"].get(str(dex), []) if s.get("pbind") is Dictionary else []
	var known := Families.known(s, dex)
	return {"dex": dex, "opts": {"perks": Families.perks(s, dex), "bind": bind,
		"start_moves": Families.start_moves(s, dex, known), "pool": Families.pool_of(dex, known),
		"shiny": bool(s.get("partnerShiny", false)) and Save.owns_shiny(dex)}}

static var _banked := {"t1": 0, "t10": 0}

static func reset_bank() -> void:
	_banked = {"t1": 0, "t10": 0}

## Tickets picked up are saved at once (game.js bankTickets): nothing is lost if the app dies.
static func bank_tickets(pl: Player, commit := true) -> void:
	if not Save.loaded or pl == null:
		return
	var d1 := maxi(0, pl.t1 - int(_banked["t1"]))
	var d10 := maxi(0, pl.t10 - int(_banked["t10"]))
	if d1 == 0 and d10 == 0:
		return
	var t: Dictionary = Save.data["tickets"]
	t["t1"] = int(t["t1"]) + d1
	t["t10"] = int(t["t10"]) + d10
	_banked = {"t1": pl.t1, "t10": pl.t10}
	if commit:
		Save.commit()

## Applies a finished run to the save (game.js endRun after the coins formula). Adds `record`.
static func apply_run(r: Dictionary, pl: Player) -> void:
	if not Save.loaded:
		return
	var s := Save.data
	var st: Dictionary = s["stats"]
	r["record"] = float(r["time"]) > float(st.get("bestTime", 0))
	s["coins"] = int(s["coins"]) + int(r["coins"])
	# XP for the partner's family (Families.gain_xp: {f, lv, ups, xp, need, gained}, shown in the results)
	if pl != null:
		r["dex"] = pl.dex
		r["fam"] = Families.gain_xp(s, pl.dex, {"time": float(r["time"]), "kills": int(r["kills"]), "bosses": int(r["bosses"])})
	bank_tickets(pl, false)
	st["runs"] = Save.stat("runs") + 1
	st["totalKills"] = Save.stat("totalKills") + int(r["kills"])
	st["bestTime"] = maxi(Save.stat("bestTime"), int(floor(float(r["time"]))))
	st["bestLevel"] = maxi(Save.stat("bestLevel"), int(r["level"]))
	st["coinsEarned"] = Save.stat("coinsEarned") + int(r["coins"])
	Progress.event("runEnd", {"time": float(r["time"]), "level": int(r["level"]),
		"coins": pl.coins if pl != null else 0, "types": pl.mon["types"] if pl != null else [], "group": false})
	Progress.check_ach()
	Save.commit()

# ---------------- personality test (starters.js G.personalityResult) ----------------

## Starters whose score 2*scores[primary] + scores[secondary] is the best (the tie list).
static func personality_candidates(scores: Dictionary) -> Array:
	var best: Array = []
	var best_v := -1
	for s in Data._json("starters.json")["starters"]:
		var tr: Array = s["traits"]
		var v := int(scores.get(tr[0], 0)) * 2 + int(scores.get(tr[1], 0))
		if v > best_v:
			best_v = v
			best = [int(s["dex"])]
		elif v == best_v:
			best.append(int(s["dex"]))
	return best

## {trait, dex}: trait = highest score (ties: first inserted key); starter picked among the ties.
static func personality_result(scores: Dictionary, rnd := Callable()) -> Dictionary:
	if not rnd.is_valid():
		rnd = func() -> float: return randf()
	var best_trait := ""
	var top := -1
	for k in scores:
		if int(scores[k]) > top:
			top = int(scores[k])
			best_trait = k
	var c := personality_candidates(scores)
	return {"trait": best_trait, "dex": c[int(floor(rnd.call() * c.size()))]}
