extends SceneTree
## Playtest batch: human-like bots (debug/bot.gd: novice / casual / expert, or legacy) play whole
## runs headless, each one until the Pokémon faints, and this prints per profile the numbers a
## designer looks at: how long they last (and the best run), kills, Pokémonedas per run (and how
## many runs all the upgrades would take), level, the first boss, where the HP went, what landed
## the last hit, how the bot moved and used the map.
##   godot --headless --path godot --script res://tests/sim_play.gd -- [--bot=novice,casual,expert]
##       [--runs=20] [--jobs=N] [--seed=1] [--partner=4] [--upg=0] [--max=0] [--lang=en|zh]
##       [--csv=<file>] [--verbose] [--bot-set=k=v,...]
##   --runs=<n>     runs per profile (seeds seed, seed+1, ...: every profile plays the same worlds)
##   --jobs=<n>     runs in parallel, one headless Godot per job (default: CPU threads - 2, max 12);
##                  --jobs=1 plays everything in this process
##   --upg=<0..1>   permanent upgrades (Mejoras) bought, as a fraction of each one's max level
##                  (0 = a new account, 1 = everything maxed for this Pokémon)
##   --max=<s>      stop a run still alive at s (counted as alive); 0 (default) = until it faints
##                  (with a 4 h safety stop: after minute 60 the game gets harder and harder anyway)
##   --lang=zh      the report in Simplified Chinese
##   --csv=<file>   one row per run
##   --verbose      one line per run (seed order)
##   --bot-set=k=v,k=v   change a human profile's numbers for this batch (debug/bot.gd PROFILES),
##                  e.g. --bot-set=margin=20,buffs=false,chest=3/6
##   --trace=<s>    (forces --jobs=1; use one profile and --runs=1) a line every s seconds: HP, level,
##                  enemies near, closest one, active move, the bot's direction
##   --prof         (forces --jobs=1) time per frame: bot vs Sim.update and its sections
## Fixed dt = 1/60 like sim_smoke.gd; bot runs never touch the save. Internal: --child=<file> makes
## this process a worker that appends one JSON line per run to <file>.

const MARKS := [60.0, 180.0, 300.0, 600.0]
const SAFETY_T := 4.0 * 3600.0
const BUCKETS := [60.0, 120.0, 180.0, 300.0, 600.0]     # survival histogram edges (s)

## Report labels. %-formats keep the same arguments in both languages.
const TXT := {
	"en": {
		"head": "play: partner %s (dex %d), %d runs per profile from seed %d, upgrades %d%%, %s, %d parallel jobs",
		"until": "until it faints", "max": "max %d s",
		"prog": "  ... %s  (%d s)",
		"title": "== %s ==  %d runs, %d fainted",
		"missing": "  !! %d runs missing (a worker failed)",
		"surv": "  survived     median %s · mean %s · shortest %s · longest %s",
		"dist": "  how long     ", "bucket": "%s %d", "lt": "<%d min", "rng": "%d-%d min", "ge": "%d+ min",
		"best": "  best run     seed %d: %s, level %d, %d kills, %d coins",
		"kills": "  kills        mean %.0f · most %d",
		"coins": "  coins        mean %.0f · most %d · all runs %d",
		"upg": "  upgrades     all of this Pokémon's upgrades cost %d more coins: ≈ %d runs like these ≈ %.1f h of play",
		"upg_done": "  upgrades     all bought already",
		"run": "  per run      level %.1f · bosses beaten %.2f",
		"move": "  movement     %.1f direction changes/s · standing still %d%% · closest enemy %.0f wu on average",
		"map": "  map          per run: %.1f locked chests opened · %.1f altars · %.0f HP from springs · %.1f traps set off · rifts %.1f opened, %.1f entered, %.1f won",
		"shots": "  shots        %.0f per run · line of fire to the target blocked %d%% of the time · %d%% of shots end in a wall / tree (misses included) · %d%% on rocks / chests",
		"boss": "  first boss   reached in %d%% of runs, beaten in %d%%",
		"lvat": "  level at     ", "lvat1": "%s lv %.1f (%d/%d alive)",
		"hp": "  HP lost to   ", "hpd": "    detail     ", "last": "  last hit     ",
		"line": "  %-7s seed %3d  %7s %s  lv %2d  kills %4d  bosses %d  coins %4d  last hit %-16s %s",
		"dead": "fainted", "alive": "alive  ",
		"csv": "play: %d rows -> %s", "done": "play: done in %.1f s",
	},
	"zh": {
		"head": "试玩：伙伴 %s（图鉴 %d），每档 %d 局，种子从 %d 开始，永久强化 %d%%，%s，并行 %d 个进程",
		"until": "每局打到倒下为止", "max": "每局最多 %d 秒",
		"prog": "  …… %s（%d 秒）",
		"title": "== %s ==  %d 局，倒下 %d 局",
		"missing": "  !! 少了 %d 局（有子进程出错）",
		"surv": "  坚持时间     中位数 %s · 平均 %s · 最短 %s · 最长 %s",
		"dist": "  时长分布     ", "bucket": "%s %d 局", "lt": "不到 %d 分钟", "rng": "%d-%d 分钟", "ge": "%d 分钟以上",
		"best": "  最好的一局   种子 %d：坚持 %s，%d 级，击杀 %d，宝可梦币 %d",
		"kills": "  击杀         平均 %.0f · 最多 %d",
		"coins": "  宝可梦币     平均 %.0f · 最多 %d · 所有局合计 %d",
		"upg": "  永久强化     这只宝可梦的强化全部点满还要 %d 币：按这个收入 ≈ %d 局 ≈ 玩 %.1f 小时",
		"upg_done": "  永久强化     已经全部点满",
		"run": "  每局         等级 %.1f · 打赢 Boss %.2f 个",
		"move": "  走位         每秒换方向 %.1f 次 · 站着不动 %d%% · 离最近的敌人平均 %.0f",
		"map": "  地图         每局：开带锁宝箱 %.1f 个 · 祭坛 %.1f 个 · 泉水回血 %.0f · 触发陷阱 %.1f 个 · 裂缝 出现 %.1f / 进入 %.1f / 打赢 %.1f",
		"shots": "  射击         每局 %.0f 发 · 有目标时火线被挡住 %d%% 的时间 · %d%% 的子弹最后撞到墙/树（含没打中的） · %d%% 打在石头/宝箱上",
		"boss": "  第一个 Boss  见到的局 %d%% · 打赢的局 %d%%",
		"lvat": "  各时间点等级 ", "lvat1": "%s 时 %.1f 级（%d/%d 局还活着）",
		"hp": "  掉血来源     ", "hpd": "    明细       ", "last": "  致命一击     ",
		"line": "  %-7s 种子 %3d  %7s %s  %2d 级  击杀 %4d  Boss %d  宝可梦币 %4d  致命一击 %-16s %s",
		"dead": "倒下", "alive": "存活",
		"csv": "试玩：%d 行 -> %s", "done": "试玩：用时 %.1f 秒",
	},
}
## Damage sources in Chinese (the part before ":" and the enemy behaviors).
const ZH_SRC := {"touch": "撞击", "shot": "子弹", "hazard": "预警攻击", "boss": "Boss", "trap": "陷阱", "lava": "岩浆",
	"weather": "天气", "other": "其他", "chase": "追击怪", "runner": "快跑怪", "charger": "冲锋怪", "jumper": "跳跃怪",
	"bomber": "自爆怪", "beamer": "射线怪", "zoner": "地面圈怪", "fan": "扇形弹怪", "ranged": "远程怪", "tank": "坦克怪",
	"healer": "治疗怪", "shielder": "护盾怪", "summoner": "召唤怪", "zone": "圆圈", "beam": "射线"}

var _lang := "en"
var _trace := 0.0
var _prof := false
var _bot_us := 0
var _sim_us := 0
var _frames := 0

func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var runs := maxi(1, int(args.get("runs", "20")))
	var seed0 := int(args.get("seed", "1"))
	var partner := int(args.get("partner", "4"))
	var max_t := float(args.get("max", "0"))
	if max_t <= 0.0:
		max_t = SAFETY_T
	var upg := clampf(float(args.get("upg", "0")), 0.0, 1.0)
	_lang = "zh" if str(args.get("lang", "")) == "zh" else "en"
	_trace = float(args.get("trace", "0")) if str(args.get("trace", "")) != "" else 0.0
	_prof = args.has("prof")
	if args.has("bot-set"):
		var bad := Bot.set_overrides(str(args["bot-set"]))
		if not bad.is_empty():
			push_error("--bot-set: unknown " + str(bad))
	var levels := {}
	for u in Upgrades.list():
		levels[u["id"]] = int(floor(int(u["max"]) * upg))
	var perks := Upgrades.perks(levels) if upg > 0.0 else {}
	Data.ensure()

	# worker: play the given seeds of one profile, one JSON line per run
	if args.has("child"):
		Bot.profile = str(args.get("bot", "casual"))
		var f := FileAccess.open(str(args["child"]), FileAccess.WRITE)
		for i in runs:
			f.store_line(JSON.stringify(_play(seed0 + i, partner, max_t, perks)))
			f.flush()
		f.close()
		quit(0)
		return

	var profiles: Array = []
	for p in str(args.get("bot", "novice,casual,expert")).split(",", false):
		if p == "legacy" or Bot.PROFILES.has(p):
			profiles.append(p)
		else:
			push_error("unknown --bot profile: " + p)
	var jobs := clampi(int(args.get("jobs", str(clampi(OS.get_processor_count() - 2, 1, 12)))), 1, 64)
	if _trace > 0.0 or _prof:
		jobs = 1
	jobs = mini(jobs, runs * profiles.size())
	print(_t("head") % [Data.dex_by[partner]["name"], partner, runs, seed0, int(upg * 100.0),
		_t("until") if max_t >= SAFETY_T else _t("max") % int(max_t), jobs])
	if not Bot.overrides.is_empty():
		print("play: profile overrides " + str(Bot.overrides))
	var t0 := Time.get_ticks_msec()
	var results := {}
	if jobs == 1:
		if _prof:
			SimProf.enable()
		for prof in profiles:
			Bot.profile = prof
			var R: Array = []
			for i in runs:
				R.append(_play(seed0 + i, partner, max_t, perks))
			results[prof] = R
	else:
		results = _parallel(args, profiles, runs, seed0, jobs, t0)

	var rows: Array[String] = ["profile,seed,time,fainted,level,kills,bosses,coins,last_hit,lv60,lv180,lv300,lv600,hp_touch,hp_shot,hp_hazard,hp_other,chests,altars,rifts,shots,shots_blocked,moves"]
	for prof in profiles:
		var R: Array = results.get(prof, [])
		R.sort_custom(func(a, b): return int(a["seed"]) < int(b["seed"]))
		if args.has("verbose"):
			print("")
			for r in R:
				print(_t("line") % [prof, int(r["seed"]), _mmss(r["time"]), _t("dead") if r["dead"] else _t("alive"), int(r["level"]),
					int(r["kills"]), int(r["bosses"]), int(r["coins"]), _src(r["last_hit"]), r["moves"]])
		for r in R:
			var g := _groups(r["dmg"])
			var lv: Dictionary = r["lv"]
			rows.append("%s,%d,%.1f,%d,%d,%d,%d,%d,%s,%s,%s,%s,%s,%.0f,%.0f,%.0f,%.0f,%d,%d,%d,%d,%d,%s" % [prof, int(r["seed"]), r["time"],
				int(r["dead"]), int(r["level"]), int(r["kills"]), int(r["bosses"]), int(r["coins"]), r["last_hit"],
				str(lv.get("60", "")), str(lv.get("180", "")), str(lv.get("300", "")), str(lv.get("600", "")),
				g.get("touch", 0.0), g.get("shot", 0.0), g.get("hazard", 0.0), float(g.get("boss", 0.0)) + float(g.get("other", 0.0)),
				int(r["chests"]), int(r["altars"]), int(r["rifts"]), int(r["shots"]["fired"]),
				int(r["shots"]["wall"]) + int(r["shots"]["prop"]), str(r["moves"]).replace(",", " ")])
		if not R.is_empty():
			_report(prof, R, runs, levels)
	var csv_path := str(args.get("csv", ""))
	if csv_path != "":
		var f := FileAccess.open(csv_path, FileAccess.WRITE)
		if f != null:
			f.store_string("\n".join(rows) + "\n")
			f.close()
			print(_t("csv") % [rows.size() - 1, csv_path])
	if _prof:
		print("play: per frame: bot %.3f ms, Sim.update %.3f ms (%d frames)" % [_bot_us / 1000.0 / maxf(_frames, 1), _sim_us / 1000.0 / maxf(_frames, 1), _frames])
		print("play: Sim.update sections (ms/frame): " + SimProf.take(0, SimProf.FIRST_DRAW, _frames))
	print(_t("done") % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit(0)

# ---------------- parallel workers ----------------

## Splits every profile's seeds into small blocks, keeps `jobs` headless Godots busy with them (a
## worker that finishes gets the next block) and gathers their JSON lines: {profile: [result]}.
func _parallel(args: Dictionary, profiles: Array, runs: int, seed0: int, jobs: int, t0: int) -> Dictionary:
	var dir := OS.get_cache_dir().path_join("pokesurvivor_sim_play_%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(dir)
	var block := clampi(int(ceil(runs * profiles.size() / float(jobs * 3))), 1, 8)
	var queue: Array = []                     # [profile, first seed, runs]
	for prof in profiles:
		var s := 0
		while s < runs:
			var k := mini(block, runs - s)
			queue.append([prof, seed0 + s, k])
			s += k
	var pass_on: Array = []
	for key in ["partner", "upg", "max", "bot-set"]:
		if args.has(key):
			pass_on.append("--%s=%s" % [key, args[key]])
	var exe := OS.get_executable_path()
	var proj := ProjectSettings.globalize_path("res://")
	var running: Array = []                   # [pid, file, task]
	var files: Array = []                     # [file, profile]
	var next_print := 0
	var n := 0
	while not queue.is_empty() or not running.is_empty():
		while running.size() < jobs and not queue.is_empty():
			var task: Array = queue.pop_front()
			n += 1
			var file := dir.path_join("w%04d.jsonl" % n)
			var cargs := ["--headless", "--quiet", "--log-file", dir.path_join("w%04d.log" % n), "--path", proj,
				"--script", "res://tests/sim_play.gd", "--", "--child=" + file, "--bot=" + str(task[0]),
				"--seed=%d" % task[1], "--runs=%d" % task[2]] + pass_on
			var pid := OS.create_process(exe, PackedStringArray(cargs))
			if pid <= 0:
				push_error("could not start a worker")
				continue
			running.append([pid, file, task])
			files.append([file, task[0]])
		OS.delay_msec(200)
		for i in range(running.size() - 1, -1, -1):
			if not OS.is_process_running(running[i][0]):
				running.remove_at(i)
		var now := Time.get_ticks_msec()
		if now >= next_print:
			next_print = now + 5000
			var done := {}
			for f in files:
				done[f[1]] = int(done.get(f[1], 0)) + _count_lines(f[0])
			var parts: Array = []
			for prof in profiles:
				parts.append("%s %d/%d" % [prof, int(done.get(prof, 0)), runs])
			print(_t("prog") % [" · ".join(parts), (now - t0) / 1000])
	var out := {}
	for f in files:
		var fa := FileAccess.open(f[0], FileAccess.READ)
		if fa == null:
			continue
		while not fa.eof_reached():
			var line := fa.get_line()
			if line.strip_edges() == "":
				continue
			var r: Variant = JSON.parse_string(line)
			if r is Dictionary:
				if not out.has(f[1]):
					out[f[1]] = []
				out[f[1]].append(r)
		fa.close()
	for name in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(name))
	DirAccess.remove_absolute(dir)
	return out

static func _count_lines(path: String) -> int:
	if not FileAccess.file_exists(path):
		return 0
	return FileAccess.get_file_as_string(path).count("\n")

# ---------------- one run ----------------

func _play(seed_: int, partner: int, max_t: float, perks: Dictionary) -> Dictionary:
	seed(seed_)
	var sim := Sim.new()
	sim.render = false
	sim.start_run(partner, seed_, {"perks": perks} if not perks.is_empty() else {})
	var boss1 := float(sim.defs.bosses[0]["at"]) if not sim.defs.bosses.is_empty() else 180.0
	var dt := 1.0 / 60.0
	var lv := {}
	var mi := 0
	var frozen := 0
	var prev := Vector2.ZERO
	var turns := 0               # input changes (a new key / stick direction, or stopping)
	var still := 0
	var frames := 0
	var gap_sum := 0.0
	var gap_n := 0
	var los_n := 0               # samples with a projectile move and its target in reach
	var los_bad := 0             # ... where a wall / rock / tree stands in the way
	while sim.state != "over" and sim.time < max_t:
		if sim.state == "levelup" or sim.state == "choice":
			Bot.pick(sim)
			frozen += 1
			if frozen > 50:
				push_error("seed %d: the bot could not leave state %s" % [seed_, sim.state])
				break
			continue
		frozen = 0
		var b0 := Time.get_ticks_usec()
		sim.input_axis = Bot.axis(sim)
		_bot_us += Time.get_ticks_usec() - b0
		var ax := sim.input_axis
		if (ax == Vector2.ZERO) != (prev == Vector2.ZERO) or (ax != Vector2.ZERO and ax.dot(prev) < 0.94):
			turns += 1
		prev = ax
		frames += 1
		if ax == Vector2.ZERO:
			still += 1
		if frames % 15 == 0:
			var g := _closest_gap(sim)
			if g < 400.0:
				gap_sum += g
				gap_n += 1
			var am := sim.player.active_move()
			var tg := sim.player.target
			if not am.is_empty() and ["projectile", "boomerang", "cone", "chain"].has(am["kind"]) and tg is Enemy \
					and U.dist2(sim.player.x, sim.player.y, tg.x, tg.y) < pow(minf(Combat.reach(am), 420.0), 2.0):
				los_n += 1
				if Bot._fire_blocked(sim.world, sim.player.x, sim.player.y, tg.x, tg.y, tg.r):
					los_bad += 1
		if _trace > 0.0 and fmod(sim.time, _trace) < dt:
			_trace_line(sim)
		var s0 := Time.get_ticks_usec()
		sim.update(dt)
		_sim_us += Time.get_ticks_usec() - s0
		_frames += 1
		while mi < MARKS.size() and sim.time >= MARKS[mi]:
			lv[str(int(MARKS[mi]))] = sim.player.level
			mi += 1
	var pl := sim.player
	var dead := sim.state == "over"
	var mv: Array = []
	for m in pl.moves:
		mv.append("%s%d%s" % [m["id"], int(m["lvl"]), "*" if m.get("evolved", false) else ""])
	return {"seed": seed_, "time": sim.time, "dead": dead, "level": pl.level, "kills": pl.kills,
		"bosses": pl.bosses, "saw_boss": sim.time >= boss1,
		"coins": int(Meta.run_coins(sim.time, pl.kills, pl.bosses, pl.coins, pl.coin_mul)["coins"]),
		"last_hit": pl.last_hit if dead else "", "dmg": pl.dmg_log.duplicate(), "lv": lv, "moves": " ".join(mv),
		"turns": turns / maxf(sim.time, 1.0), "still": float(still) / maxf(frames, 1), "gap": gap_sum / maxf(gap_n, 1),
		"chests": int(sim.interact.stats["chest"]), "altars": int(sim.interact.stats["altar"]),
		"spring": float(sim.interact.stats["spring_hp"]), "traps": int(sim.interact.stats["trap"]),
		"rift_open": sim.rift.history.filter(func(h): return h[1] == "open").size(),
		"rifts": sim.rift.history.filter(func(h): return h[1] == "arena").size(),
		"rift_won": sim.rift.history.filter(func(h): return h[1] == "won").size(),
		"shots": sim.combat.shot_stats.duplicate(), "los_n": los_n, "los_bad": los_bad}

## Gap (wu, body to body) to the closest enemy, INF if none.
static func _closest_gap(sim: Sim) -> float:
	var pl := sim.player
	var best := INF
	for e in sim.enemies.list:
		if not e.dead and e.behavior != "thief":
			best = minf(best, sqrt(U.dist2(pl.x, pl.y, e.x, e.y)) - e.r - pl.r)
	return best

func _trace_line(sim: Sim) -> void:
	var pl := sim.player
	var n200 := 0
	var n100 := 0
	var close := INF
	for e in sim.enemies.list:
		if e.dead:
			continue
		var d := sqrt(U.dist2(pl.x, pl.y, e.x, e.y)) - e.r - pl.r
		close = minf(close, d)
		if d < 200.0:
			n200 += 1
		if d < 100.0:
			n100 += 1
	var am := pl.active_move()
	print("  t %6.1f  hp %3d/%-3d  lv %2d  kills %4d  alive %2d  <100 %2d  <200 %2d  closest %5.0f  move %-14s dir (%5.2f,%5.2f)  gems %d" % [
		sim.time, int(pl.hp), int(pl.max_hp), pl.level, pl.kills, sim.enemies.count(), n100, n200, close,
		str(am.get("id", "-")), sim.input_axis.x, sim.input_axis.y, sim.pickups.count()])

# ---------------- report ----------------

func _t(key: String) -> String:
	return TXT[_lang][key]

## A damage source as the report shows it ("touch:runner" -> "撞击·快跑怪" in Chinese).
func _src(k: String) -> String:
	if _lang != "zh" or k == "":
		return k
	var p := k.split(":")
	return "·".join(Array(p).map(func(x): return ZH_SRC.get(x, x)))

## HP lost grouped as touch / boss / shot / hazard / other.
static func _groups(dmg: Dictionary) -> Dictionary:
	var g := {}
	for k: String in dmg:
		var grp := k.get_slice(":", 0)
		if not ["touch", "boss", "shot", "hazard"].has(grp):
			grp = "other"
		g[grp] = float(g.get(grp, 0.0)) + float(dmg[k])
	return g

func _top(counts: Dictionary, total: float, n: int) -> String:
	var keys := counts.keys()
	keys.sort_custom(func(a, b): return float(counts[a]) > float(counts[b]))
	var out: Array = []
	for k in keys.slice(0, n):
		out.append("%s %d%%" % [_src(k), int(roundf(float(counts[k]) / maxf(total, 1e-6) * 100.0))])
	return ", ".join(out)

## Coins still needed to max every upgrade of the partner from these levels.
static func _upgrades_left(levels: Dictionary) -> int:
	var left := 0
	for u in Upgrades.list():
		for l in range(int(levels.get(u["id"], 0)), int(u["max"])):
			left += Upgrades.cost(u["id"], l)
	return left

func _report(prof: String, R: Array, asked: int, levels: Dictionary) -> void:
	var n := R.size()
	var times: Array[float] = []
	var dead := 0
	var lv_sum := 0.0
	var kills := 0.0
	var coins := 0.0
	var saw := 0
	var beat := 0
	var bosses := 0.0
	var dmg := {}
	var killers := {}
	var lv_at := {}
	var turns := 0.0
	var still := 0.0
	var gap := 0.0
	var best: Dictionary = R[0]
	var most_kills := 0
	var most_coins := 0
	var it := {"chests": 0.0, "altars": 0.0, "spring": 0.0, "traps": 0.0, "rift_open": 0.0, "rifts": 0.0, "rift_won": 0.0,
		"los_n": 0.0, "los_bad": 0.0}
	var sh := {"fired": 0.0, "wall": 0.0, "prop": 0.0}
	for r in R:
		for k in it:
			it[k] += float(r[k])
		for k in sh:
			sh[k] += float(r["shots"][k])
		turns += r["turns"]
		still += r["still"]
		gap += r["gap"]
		times.append(r["time"])
		dead += int(r["dead"])
		lv_sum += r["level"]
		kills += r["kills"]
		coins += r["coins"]
		most_kills = maxi(most_kills, int(r["kills"]))
		most_coins = maxi(most_coins, int(r["coins"]))
		if float(r["time"]) > float(best["time"]):
			best = r
		saw += int(r["saw_boss"])
		beat += int(int(r["bosses"]) > 0)
		bosses += r["bosses"]
		for k in r["dmg"]:
			dmg[k] = float(dmg.get(k, 0.0)) + float(r["dmg"][k])
		if r["dead"]:
			killers[r["last_hit"]] = int(killers.get(r["last_hit"], 0)) + 1
		for m in r["lv"]:
			if not lv_at.has(m):
				lv_at[m] = []
			lv_at[m].append(r["lv"][m])
	times.sort()
	var mean := 0.0
	for t in times:
		mean += t
	mean /= n
	var med := times[n / 2] if n % 2 == 1 else (times[n / 2 - 1] + times[n / 2]) / 2.0
	var hp_total := 0.0
	for k in dmg:
		hp_total += float(dmg[k])
	print("")
	print(_t("title") % [prof, n, dead])
	if n < asked:
		print(_t("missing") % (asked - n))
	print(_t("surv") % [_mmss(med), _mmss(mean), _mmss(times[0]), _mmss(times[n - 1])])
	var hist: Array = []
	for i in BUCKETS.size() + 1:
		var lo: float = 0.0 if i == 0 else BUCKETS[i - 1]
		var hi: float = INF if i == BUCKETS.size() else BUCKETS[i]
		var c := times.filter(func(t): return t >= lo and t < hi).size()
		var label: String = _t("lt") % int(hi / 60.0) if i == 0 else (_t("ge") % int(lo / 60.0) if hi == INF else _t("rng") % [int(lo / 60.0), int(hi / 60.0)])
		hist.append(_t("bucket") % [label, c])
	print(_t("dist") + " · ".join(hist))
	print(_t("best") % [int(best["seed"]), _mmss(best["time"]), int(best["level"]), int(best["kills"]), int(best["coins"])])
	print(_t("kills") % [kills / n, most_kills])
	print(_t("coins") % [coins / n, most_coins, int(coins)])
	var left := _upgrades_left(levels)
	if left <= 0:
		print(_t("upg_done"))
	elif coins > 0.0:
		var per := coins / n
		var need := int(ceil(left / per))
		print(_t("upg") % [left, need, need * mean / 3600.0])
	print(_t("run") % [lv_sum / n, bosses / n])
	print(_t("boss") % [int(100.0 * saw / n), int(100.0 * beat / n)])
	var lvs: Array = []
	for m in MARKS:
		var key := str(int(m))
		if lv_at.has(key):
			var a: Array = lv_at[key]
			var sm := 0.0
			for v in a:
				sm += v
			lvs.append(_t("lvat1") % [_mmss(m), sm / a.size(), a.size(), n])
	print(_t("lvat") + (" · ".join(lvs) if not lvs.is_empty() else "-"))
	print(_t("hp") + _top(_groups(dmg), hp_total, 5))
	print(_t("hpd") + _top(dmg, hp_total, 7))
	if dead > 0:
		print(_t("last") + _top(killers, dead, 5))
	print(_t("move") % [turns / n, int(100.0 * still / n), gap / n])
	print(_t("map") % [it["chests"] / n, it["altars"] / n, it["spring"] / n, it["traps"] / n, it["rift_open"] / n, it["rifts"] / n, it["rift_won"] / n])
	print(_t("shots") % [sh["fired"] / n, int(100.0 * it["los_bad"] / maxf(it["los_n"], 1.0)), int(100.0 * sh["wall"] / maxf(sh["fired"], 1.0)),
		int(100.0 * sh["prop"] / maxf(sh["fired"], 1.0))])

static func _mmss(t: float) -> String:
	return "%d:%02d" % [int(t) / 60, int(t) % 60]
