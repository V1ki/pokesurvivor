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
##   --learnset=<lv>  moves from the partner's learnset at that family level (debug/family_rules.gd:
##                  it starts with the first one, the cards offer only those) instead of its types
##
## Campaign (an account that grows): --campaign=<n> [--accounts=4] [--save-dir=<dir>]
##   every account starts like a new one (500 coins, no upgrades) and plays n runs in a row; after
##   each run its coins go to the partner's permanent upgrades, bought the way that profile's player
##   would (Bot.shop; Veto blocks the buff moves), and the next run starts with them. Accounts run in
##   parallel (one worker each); --save-dir keeps each one in <dir>/<profile>_<k>.json, and the next
##   --campaign with the same dir CONTINUES those accounts instead of starting over. The report is
##   the progression curve (survival, coins, upgrades, hours played at run 1, 5, 10, 20, 50, 100...),
##   when an account first lasts 3 / 5 / 10 min, when everything is maxed, and what it bought first.
##   Between runs the account also spends the gacha tickets it picked up (Bot.gacha, the partner's
##   generation banner, duplicates refund coins) and may switch to a Pokémon it pulled
##   (Bot.choose_partner). --rules picks the progression:
##     per_mon (default, the game's): coin upgrades per Pokémon (a new partner starts from zero)
##     shared (or --shared-upg): the same coin upgrades shared by the whole account
##     family: the proposed one (debug/family_rules.gd): coins buy trainer upgrades for every
##       Pokémon; each evolution family levels up by playing, which gives damage / cooldown / crits /
##       a 2nd move and unlocks its learnset; it evolves at the original level once the form is
##       owned (pulled, or unlocked with shards from duplicates); --rules-set=k=v,... changes its numbers
##   Each rule's accounts are saved apart (<profile>_<k>.json, _shared.json, _family.json).
##   --campaign=0 --save-dir=<dir> only prints the report of the saved accounts (even while another
##   campaign is still playing them: they are saved after every run).
##   Not simulated: missions and achievements (and their tickets), lost Pokémon joining you.
##
## Fixed dt = 1/60 like sim_smoke.gd; bot runs never touch the save. Internal: --child=<file> makes
## this process a worker that appends one JSON line per run to <file> (--account=<file>: campaign).

const MARKS := [60.0, 180.0, 300.0, 600.0]
const CHECKPOINTS := [1, 5, 10, 20, 30, 50, 75, 100, 150, 200, 300, 400, 500, 750, 1000, 1500, 2000]
const MILESTONES := [180.0, 300.0, 600.0]
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
		"c_head": "campaign: starter %s (dex %d), %d accounts per profile, %d more runs each, %d parallel jobs%s",
		"c_keep": ", accounts kept in %s", "c_only": "campaign report of the accounts saved in %s", "c_resume": "  %s: continuing %d saved accounts (%d runs played so far in all)",
		"c_title": "== %s ==  %d accounts, %d runs each · upgrades %s",
		"c_rule": {"per_mon": "per Pokémon (the game's rule)", "shared": "shared by the whole account",
			"family": "trainer + family levels, evolutions and shards (proposed)"},
		"f_cols": "  %-6s  %9s  %8s  %8s  %11s  %8s  %9s  %10s  %6s  %8s",
		"f_cols_h": ["run", "played", "trainer", "fam. lv", "survived", "longest", "coins/run", "first boss", "owned", "stage"],
		"f_row": "  %-6s  %8.1fh  %7d%%  %8.1f  %11s  %8s  %9.0f  %9d%%  %6.1f  %8.1f",
		"f_evo": "  first evolution: run %s (≈ %s of play) · %d/%d accounts",
		"f_evo_no": "  first evolution: not yet (0/%d accounts)",
		"f_fin": "  final form (2nd evolution): run %s (≈ %s of play) · %d/%d accounts",
		"f_fin_no": "  final form (2nd evolution): not yet (0/%d accounts)",
		"f_tmax": "  trainer upgrades all bought: run %s (≈ %s of play) · %d/%d accounts",
		"f_tmax_no": "  trainer upgrades all bought: not yet (0/%d accounts)",
		"f_final": "  account %d: plays %s (%d*, stage %d), family level %d, %d stars, %d forms unlocked with shards, %d universal shards, owns %d, %d pulls, evolved %d times, switched family %d times, trainer %d%%, %d coins",
		"c_cols": "  %-6s  %9s  %9s  %11s  %8s  %9s  %10s  %6s  %9s",
		"c_cols_h": ["run", "played", "upgrades", "survived", "longest", "coins/run", "first boss", "owned", "switched"],
		"c_row": "  %-6s  %8.1fh  %8d%%  %11s  %8s  %9.0f  %9d%%  %6.1f  %8d%%",
		"c_final": "  account %d: plays %s (%d*), owns %d Pokémon, %d pulls, switched partner %d times",
		"c_ms": "  first time lasting %s: run %s (≈ %s of play) · %d/%d accounts got there",
		"c_ms_no": "  first time lasting %s: not yet (0/%d accounts)",
		"c_max": "  partner's upgrades all bought: run %s (≈ %s of play) · %d/%d accounts",
		"c_max_no": "  partner's upgrades all bought: not yet (0/%d accounts)",
		"c_left": "  partner's upgrades after %d runs: %d%% (median), coins in the wallet %d",
		"c_buy": "  account 1 bought first: ",
		"c_none": "-", "c_hours": "%.1f h",
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
		"c_head": "养成模式：初始伙伴 %s（图鉴 %d），每档 %d 个账号，每个账号再玩 %d 局，并行 %d 个进程%s",
		"c_keep": "，账号存档在 %s", "c_only": "养成模式报告（只读存档，不玩新局）：%s", "c_resume": "  %s：接着 %d 个已存档的账号继续（之前一共玩了 %d 局）",
		"c_title": "== %s ==  %d 个账号，每个玩了 %d 局 · 强化规则：%s",
		"c_rule": {"per_mon": "每只宝可梦单独（游戏现行规则）", "shared": "整个账号共享",
			"family": "训练家 + 家族等级、进化、碎片（新方案）"},
		"f_cols": "  %-6s  %9s  %8s  %8s  %11s  %8s  %9s  %10s  %6s  %8s",
		"f_cols_h": ["第几局", "累计游戏", "训练家", "家族等级", "平均坚持", "最长", "每局收入", "见到Boss", "拥有", "进化阶段"],
		"f_row": "  %-6s  %8.1fh  %7d%%  %8.1f  %11s  %8s  %9.0f  %9d%%  %6.1f  %8.1f",
		"f_evo": "  第一次进化：第 %s 局（约玩了 %s） · %d/%d 个账号做到",
		"f_evo_no": "  第一次进化：还没有账号做到（0/%d）",
		"f_fin": "  进化到最终形态（第二次进化）：第 %s 局（约玩了 %s） · %d/%d 个账号做到",
		"f_fin_no": "  进化到最终形态（第二次进化）：还没有账号做到（0/%d）",
		"f_tmax": "  训练家强化全部点满：第 %s 局（约玩了 %s） · %d/%d 个账号做到",
		"f_tmax_no": "  训练家强化全部点满：还没有账号做到（0/%d）",
		"f_final": "  账号 %d：现在用 %s（%d 星，第 %d 阶段），家族 %d 级，突破 %d 次，碎片解锁 %d 个形态，万能碎片 %d，拥有 %d 只，抽了 %d 次，进化 %d 次，换家族 %d 次，训练家 %d%%，钱包 %d 币",
		"c_cols": "  %-6s  %9s  %9s  %11s  %8s  %9s  %10s  %6s  %9s",
		"c_cols_h": ["第几局", "累计游戏", "强化进度", "平均坚持", "最长", "每局收入", "见到Boss", "拥有", "已换伙伴"],
		"c_row": "  %-6s  %8.1fh  %8d%%  %11s  %8s  %9.0f  %9d%%  %6.1f  %8d%%",
		"c_final": "  账号 %d：现在用 %s（%d 星），拥有 %d 只宝可梦，抽了 %d 次，换过 %d 次伙伴",
		"c_ms": "  第一次坚持到 %s：第 %s 局（约玩了 %s） · %d/%d 个账号做到",
		"c_ms_no": "  第一次坚持到 %s：还没有账号做到（0/%d）",
		"c_max": "  当前伙伴强化全部点满：第 %s 局（约玩了 %s） · %d/%d 个账号做到",
		"c_max_no": "  当前伙伴强化全部点满：还没有账号做到（0/%d）",
		"c_left": "  玩了 %d 局后当前伙伴的强化进度 %d%%（中位数），钱包里还有 %d 币",
		"c_buy": "  账号 1 最先买的强化：",
		"c_none": "-", "c_hours": "%.1f 小时",
	},
}
## Damage sources in Chinese (the part before ":" and the enemy behaviors).
const ZH_SRC := {"touch": "撞击", "shot": "子弹", "hazard": "预警攻击", "boss": "Boss", "trap": "陷阱", "lava": "岩浆",
	"weather": "天气", "other": "其他", "chase": "追击怪", "runner": "快跑怪", "charger": "冲锋怪", "jumper": "跳跃怪",
	"bomber": "自爆怪", "beamer": "射线怪", "zoner": "地面圈怪", "fan": "扇形弹怪", "ranged": "远程怪", "tank": "坦克怪",
	"healer": "治疗怪", "shielder": "护盾怪", "summoner": "召唤怪", "zone": "圆圈", "beam": "射线"}

var _lang := "en"
var _learnset_lv := 0
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
	_learnset_lv = int(args.get("learnset", "0"))
	if args.has("rules-set"):
		var bad_r := FamilyRules.set_overrides(str(args["rules-set"]))
		if not bad_r.is_empty():
			push_error("--rules-set: unknown " + str(bad_r))
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
	if args.has("child") and args.has("campaign"):
		Bot.profile = str(args.get("bot", "casual"))
		_campaign_child(args, partner, max_t)
		quit(0)
		return
	if args.has("child"):
		Bot.profile = str(args.get("bot", "casual"))
		var f := FileAccess.open(str(args["child"]), FileAccess.WRITE)
		for i in runs:
			f.store_line(JSON.stringify(_play(seed0 + i, partner, max_t, {"perks": perks} if not perks.is_empty() else {})))
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
	if args.has("campaign"):
		_campaign(args, profiles, partner, seed0, jobs)
		quit(0)
		return
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
				R.append(_play(seed0 + i, partner, max_t, {"perks": perks} if not perks.is_empty() else {}))
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
	var dir := _tmp_dir()
	var block := clampi(int(ceil(runs * profiles.size() / float(jobs * 3))), 1, 8)
	var tasks: Array = []                     # [profile, jsonl file, worker args]
	var totals := {}
	for prof in profiles:
		totals[prof] = runs
		var s := 0
		while s < runs:
			var k := mini(block, runs - s)
			tasks.append([prof, dir.path_join("w%04d.jsonl" % tasks.size()),
				["--bot=" + str(prof), "--seed=%d" % (seed0 + s), "--runs=%d" % k] + _pass_on(args)])
			s += k
	_pool(tasks, jobs, totals, t0, dir)
	var out := {}
	for task in tasks:
		for r in _read_lines(task[1]):
			if not out.has(task[0]):
				out[task[0]] = []
			out[task[0]].append(r)
	_rm_dir(dir)
	return out

## The options every worker gets as they were given here.
static func _pass_on(args: Dictionary) -> Array:
	var out: Array = []
	for key in ["partner", "upg", "max", "bot-set", "shared-upg", "rules", "rules-set", "learnset"]:
		if args.has(key):
			out.append(("--%s=%s" % [key, args[key]]) if str(args[key]) != "" else "--" + key)
	return out

static func _tmp_dir() -> String:
	var dir := OS.get_cache_dir().path_join("pokesurvivor_sim_play_%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(dir)
	return dir

static func _rm_dir(dir: String) -> void:
	for name in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(name))
	DirAccess.remove_absolute(dir)

static func _read_lines(path: String) -> Array:
	var out: Array = []
	var fa := FileAccess.open(path, FileAccess.READ)
	if fa == null:
		return out
	while not fa.eof_reached():
		var line := fa.get_line()
		if line.strip_edges() != "":
			var r: Variant = JSON.parse_string(line)
			if r is Dictionary:
				out.append(r)
	fa.close()
	return out

## Runs the tasks ([label, jsonl file, worker args]) on `jobs` headless Godots (one task each, the
## next one starts as soon as a worker ends) and prints every 5 s how many lines each label's files
## hold out of totals[label].
func _pool(tasks: Array, jobs: int, totals: Dictionary, t0: int, dir: String) -> void:
	var queue := tasks.duplicate()
	var exe := OS.get_executable_path()
	var proj := ProjectSettings.globalize_path("res://")
	var running: Array = []                   # pids
	var next_print := 0
	var n := 0
	while not queue.is_empty() or not running.is_empty():
		while running.size() < jobs and not queue.is_empty():
			var task: Array = queue.pop_front()
			n += 1
			var cargs: Array = ["--headless", "--quiet", "--log-file", dir.path_join("w%04d.log" % n), "--path", proj,
				"--script", "res://tests/sim_play.gd", "--", "--child=" + str(task[1])] + task[2]
			var pid := OS.create_process(exe, PackedStringArray(cargs))
			if pid <= 0:
				push_error("could not start a worker")
				continue
			running.append(pid)
		OS.delay_msec(200)
		running = running.filter(func(pid): return OS.is_process_running(pid))
		var now := Time.get_ticks_msec()
		if now >= next_print:
			next_print = now + 5000
			var done := {}
			for task in tasks:
				done[task[0]] = int(done.get(task[0], 0)) + _count_lines(task[1])
			var parts: Array = []
			for label in totals:
				parts.append("%s %d/%d" % [label, int(done.get(label, 0)), int(totals[label])])
			print(_t("prog") % [" · ".join(parts), (now - t0) / 1000])

static func _count_lines(path: String) -> int:
	if not FileAccess.file_exists(path):
		return 0
	return FileAccess.get_file_as_string(path).count("\n")

# ---------------- one run ----------------

## One run until it faints (or max_t). opts: Sim.start_run options (perks, ban), plus
## start_moves: [ids] it starts with · pool: [ids] the level-up cards may offer (family rules).
func _play(seed_: int, partner: int, max_t: float, opts: Dictionary) -> Dictionary:
	seed(seed_)
	var sim := Sim.new()
	sim.render = false
	if _learnset_lv > 0 and not opts.has("pool"):
		var acc := {"fams": {str(FamilyRules.fam_of(partner)): {"lv": _learnset_lv, "xp": 0.0, "shards": 0, "stars": 0}}}
		var mv := FamilyRules.moves_of(acc, partner)
		opts = opts.duplicate()
		opts["start_moves"] = FamilyRules.start_moves(acc, partner, mv)
		opts["pool"] = mv.map(func(e): return e[0])
	if opts.has("start_moves"):
		sim.debug = {"moves": opts["start_moves"]}
	sim.start_run(partner, seed_, opts)
	if opts.has("pool"):
		sim.player.move_pool = opts["pool"]
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
		"t1": pl.t1, "t10": pl.t10,
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

# ---------------- campaign: accounts that grow run after run ----------------

## The saved account at `path` (same profile, starter and upgrade rule) or a new one: 500 coins, no
## upgrades, the starter as its only Pokémon. rule: "per_mon" (the game) or "shared".
##   {profile, start, partner, rule, coins, levels_by: {dex or "all": levels}, gacha: Gacha save,
##    runs, play_s, spent, switches, next_seed, hist: [one summary per run]}
static func _load_account(path: String, profile: String, start: int, seed_: int, rule: String) -> Dictionary:
	if FileAccess.file_exists(path):
		var a: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if a is Dictionary and a.get("profile") == profile:
			if not a.has("levels_by"):           # saved before gacha / rules: one partner, per Pokémon
				a["start"] = int(a["partner"])
				a["rule"] = "per_mon"
				a["levels_by"] = {str(int(a["partner"])): a.get("levels", {})}
				a.erase("levels")
				a["gacha"] = _new_gacha(int(a["partner"]))
				a["switches"] = 0
			if int(a["start"]) == start and a["rule"] == rule:
				return a
	if rule == "family":
		return {"profile": profile, "start": start, "partner": start, "rule": rule, "coins": Save.START_COINS,
			"trainer": {}, "fams": {}, "uni": 0, "gacha": _new_gacha(start), "runs": 0, "play_s": 0.0, "spent": 0,
			"switches": 0, "evos": 0, "next_seed": seed_, "hist": []}
	return {"profile": profile, "start": start, "partner": start, "rule": rule, "coins": Save.START_COINS,
		"levels_by": {}, "gacha": _new_gacha(start), "runs": 0, "play_s": 0.0, "spent": 0, "switches": 0,
		"next_seed": seed_, "hist": []}

## --rules (or the older --shared-upg): per_mon | shared | family.
static func _rule_of(args: Dictionary) -> String:
	var r := str(args.get("rules", "shared" if args.has("shared-upg") else "per_mon"))
	return r if ["per_mon", "shared", "family"].has(r) else "per_mon"

static func _new_gacha(start: int) -> Dictionary:
	return {"tickets": {"t1": 0, "t10": 0}, "pity": {}, "shiny": {}, "owned": {str(start): {"at": 0, "from": "start"}},
		"coins": 0, "stats": {"pulls": 0}}

## The upgrade levels a Pokémon of this account runs with (created on demand; "all" when shared).
static func _levels_of(acc: Dictionary, dex: int) -> Dictionary:
	var key := "all" if acc["rule"] == "shared" else str(dex)
	var by: Dictionary = acc["levels_by"]
	if not by.has(key):
		by[key] = {}
	return by[key]

static func _save_account(path: String, acc: Dictionary) -> void:
	var f := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	f.store_string(JSON.stringify(acc))
	f.close()
	DirAccess.rename_absolute(path + ".tmp", path)

## Worker: one account plays --campaign runs; after each one it banks the coins and tickets, pulls,
## maybe switches partner, buys upgrades for the partner of the next run, saves.
func _campaign_child(args: Dictionary, start: int, max_t: float) -> void:
	var path := str(args["account"])
	var rule := _rule_of(args)
	var acc := _load_account(path, Bot.profile, start, int(args.get("seed", "1")), rule)
	var out := FileAccess.open(str(args["child"]), FileAccess.WRITE)
	var gen := int(Data.dex_by[start]["gen"])          # the starter's banner (its pity builds up)
	var rng := RandomNumberGenerator.new()
	if rule == "family":
		_family_child(args, acc, path, out, gen, rng, max_t)
		return
	var lv_of := func(d: int) -> Dictionary: return _levels_of(acc, d)
	for i in int(args["campaign"]):
		var dex := int(acc["partner"])
		var r := _play(int(acc["next_seed"]), dex, max_t,
			{"perks": Upgrades.perks(_levels_of(acc, dex)), "ban": Bot.bans_for(Data.dex_by[dex])})
		rng.seed = hash("gacha %d %s" % [int(acc["next_seed"]), Bot.profile])
		acc["next_seed"] = int(acc["next_seed"]) + 1
		acc["runs"] = int(acc["runs"]) + 1
		acc["play_s"] = float(acc["play_s"]) + float(r["time"])
		# gacha: the tickets picked up this run, duplicates refund coins into the wallet
		var g: Dictionary = acc["gacha"]
		g["tickets"]["t1"] = int(g["tickets"]["t1"]) + int(r["t1"])
		g["tickets"]["t10"] = int(g["tickets"]["t10"]) + int(r["t10"])
		g["coins"] = int(acc["coins"]) + int(r["coins"])
		var got := Bot.gacha(g, gen, rng)
		var wallet := int(g["coins"])
		g["coins"] = 0
		var owned: Array = (g["owned"] as Dictionary).keys().map(func(k): return int(k)).filter(func(d): return Data.dex_by.has(d))
		var next := Bot.choose_partner(owned, dex, got, func(d: int) -> float: return Bot.power(Data.dex_by[d], lv_of.call(d)))
		if next != dex:
			acc["switches"] = int(acc["switches"]) + 1
		acc["partner"] = next
		# upgrades for the Pokémon of the next run
		var lv := _levels_of(acc, next)
		var sh := Bot.shop(lv, wallet, Bot.bans_for(Data.dex_by[next]).size())
		acc["spent"] = int(acc["spent"]) + wallet - int(sh["coins"])
		acc["coins"] = int(sh["coins"])
		var h := {"run": acc["runs"], "t": r["time"], "kills": r["kills"], "coins": r["coins"], "level": r["level"],
			"bosses": r["bosses"], "saw_boss": r["saw_boss"], "play_s": acc["play_s"], "spent": acc["spent"],
			"bought": sh["bought"], "last_hit": r["last_hit"], "partner": dex, "next": next,
			"upg": _upgrades_left({}) - _upgrades_left(lv), "owned": owned.size(),
			"pulls": int(g["stats"]["pulls"]), "t1": r["t1"], "t10": r["t10"],
			"got": got.filter(func(x): return x["isNew"] and int(x["rarity"]) >= 4).map(func(x): return int(x["dex"]))}
		(acc["hist"] as Array).append(h)
		out.store_line(JSON.stringify(h))
		out.flush()
		_save_account(path, acc)
	out.close()

## Worker, --rules=family (debug/family_rules.gd): the run uses the family's moves and perks; after
## it the family gains XP, the tickets are pulled, duplicates become shards, shards unlock forms /
## stars, the partner evolves (any player does) or switches, and the coins buy trainer upgrades.
func _family_child(args: Dictionary, acc: Dictionary, path: String, out: FileAccess, gen: int,
		rng: RandomNumberGenerator, max_t: float) -> void:
	var F := FamilyRules
	var t_total := F.trainer_total()
	for i in int(args["campaign"]):
		var dex := int(acc["partner"])
		var mv := F.moves_of(acc, dex)
		var r := _play(int(acc["next_seed"]), dex, max_t, {"perks": F.perks(acc, dex),
			"start_moves": F.start_moves(acc, dex, mv), "pool": mv.map(func(e): return e[0])})
		rng.seed = hash("gacha %d %s" % [int(acc["next_seed"]), Bot.profile])
		acc["next_seed"] = int(acc["next_seed"]) + 1
		acc["runs"] = int(acc["runs"]) + 1
		acc["play_s"] = float(acc["play_s"]) + float(r["time"])
		var ups := F.gain_xp(acc, dex, r)
		# gacha: duplicates become shards (their coin refund is taken back unless R.refund)
		var g: Dictionary = acc["gacha"]
		g["tickets"]["t1"] = int(g["tickets"]["t1"]) + int(r["t1"])
		g["tickets"]["t10"] = int(g["tickets"]["t10"]) + int(r["t10"])
		g["coins"] = int(acc["coins"]) + int(r["coins"])
		var got := Bot.gacha(g, gen, rng)
		var wallet := int(g["coins"]) - F.shards_from(acc, dex, got)
		g["coins"] = 0
		var unlocked := F.spend_shards(acc, dex)
		# evolve when a later form of the partner can be used (the strongest), else maybe switch
		var next := dex
		for d in F.members(F.fam_of(dex)):
			if d != dex and Data.dex_by.has(d) and F.chain(d).has(dex) and F.usable(acc, d) \
					and (next == dex or F.stage(d) > F.stage(next) or (F.stage(d) == F.stage(next)
					and int(Data.dex_by[d]["bst"]) > int(Data.dex_by[next]["bst"]))):
				next = d
		if next != dex:
			acc["evos"] = int(acc["evos"]) + 1
		else:
			var fresh: Array = got.filter(func(x): return x["isNew"] and F.usable(acc, int(x["dex"])))
			for d in unlocked:
				fresh.append({"dex": d, "rarity": int(Data.dex_by[d]["rarity"]), "isNew": true})
			next = Bot.choose_partner(F.usable_list(acc), dex, fresh, func(d: int) -> float: return F.power(acc, d))
			if next != dex:
				acc["switches"] = int(acc["switches"]) + 1
		acc["partner"] = next
		# coins: trainer upgrades only
		var sh := Bot.shop(acc["trainer"], wallet, 0, F.R["trainer"])
		acc["spent"] = int(acc["spent"]) + wallet - int(sh["coins"])
		acc["coins"] = int(sh["coins"])
		var fm := F.fam(acc, F.fam_of(next))
		var h := {"run": acc["runs"], "t": r["time"], "kills": r["kills"], "coins": r["coins"], "level": r["level"],
			"bosses": r["bosses"], "saw_boss": r["saw_boss"], "play_s": acc["play_s"], "spent": acc["spent"],
			"bought": sh["bought"], "last_hit": r["last_hit"], "partner": dex, "next": next,
			"owned": (g["owned"] as Dictionary).size(), "pulls": int(g["stats"]["pulls"]), "t1": r["t1"], "t10": r["t10"],
			"flv": int(fm["lv"]), "ups": ups, "stage": F.stage(next), "final": F.is_final(next),
			"rar": int(Data.dex_by[next]["rarity"]), "tp": float(F.trainer_spent(acc["trainer"])) / t_total,
			"uni": int(acc.get("uni", 0)), "fsh": int(fm["shards"]), "stars": int(fm["stars"]),
			"unlocked": unlocked, "moves": mv.size()}
		(acc["hist"] as Array).append(h)
		out.store_line(JSON.stringify(h))
		out.flush()
		_save_account(path, acc)
	out.close()

## Parent: one worker per account (all profiles), then the progression report per profile.
func _campaign(args: Dictionary, profiles: Array, partner: int, seed0: int, jobs: int) -> void:
	var t0 := Time.get_ticks_msec()
	var n := maxi(0, int(args.get("campaign", "100")))
	var accounts := maxi(1, int(args.get("accounts", "4")))
	var keep := str(args.get("save-dir", ""))
	var tmp := _tmp_dir()
	var dir := ProjectSettings.globalize_path(keep) if keep != "" else tmp
	DirAccess.make_dir_recursive_absolute(dir)
	jobs = maxi(1, mini(jobs, accounts * profiles.size()))
	if n == 0:
		print(_t("c_only") % dir)
	else:
		print(_t("c_head") % [Data.dex_by[partner]["name"], partner, accounts, n, jobs, (_t("c_keep") % dir) if keep != "" else ""])
	if not Bot.overrides.is_empty():
		print("play: profile overrides " + str(Bot.overrides))
	var rule := _rule_of(args)
	var suffix := "" if rule == "per_mon" else "_" + rule
	var tasks: Array = []
	var totals := {}
	for prof in profiles:
		totals[prof] = n * accounts
		var old := 0
		var had := 0
		for k in accounts:
			var path := dir.path_join("%s_%d%s.json" % [prof, k + 1, suffix])
			var a := _load_account(path, prof, partner, 0, rule)
			if int(a["runs"]) > 0:
				had += 1
				old += int(a["runs"])
			# every profile's account k plays the same worlds (seed0 + k * 100003 + run)
			tasks.append([prof, tmp.path_join("c_%s_%d.jsonl" % [prof, k + 1]),
				["--bot=" + str(prof), "--campaign=%d" % n, "--account=" + path, "--seed=%d" % (seed0 + k * 100003)] + _pass_on(args)])
		if had > 0 and n > 0:
			print(_t("c_resume") % [prof, had, old])
	if n > 0:
		_pool(tasks, jobs, totals, t0, tmp)
	for prof in profiles:
		var accs: Array = []
		for k in accounts:
			var path := dir.path_join("%s_%d%s.json" % [prof, k + 1, suffix])
			if FileAccess.file_exists(path):
				accs.append(JSON.parse_string(FileAccess.get_file_as_string(path)))
		if not accs.is_empty():
			_campaign_report(prof, accs)
	_rm_dir(tmp)
	print(_t("done") % ((Time.get_ticks_msec() - t0) / 1000.0))

func _campaign_report(prof: String, accs: Array) -> void:
	var total := _upgrades_left({})
	var K := accs.size()
	var runs := 0
	for a in accs:
		runs = maxi(runs, (a["hist"] as Array).size())
	print("")
	print(_t("c_title") % [prof, K, runs, TXT[_lang]["c_rule"][str(accs[0].get("rule", "per_mon"))]])
	if accs[0].get("rule", "") == "family":
		_family_report(accs, runs)
		return
	var hdr: Array = _t_arr("c_cols_h")
	print(_t("c_cols") % hdr)
	var rows_at: Array = CHECKPOINTS.filter(func(c): return c < runs)
	rows_at.append(runs)
	for c: int in rows_at:
		# the runs that end at c, averaged over the last 20% (at least 1)
		var w := maxi(1, int(c * 0.2))
		var ts: Array[float] = []
		var coins := 0.0
		var saw := 0
		var hours := 0.0
		var spent := 0.0
		var best := 0.0
		var na := 0
		var owned := 0.0
		var moved := 0
		for a in accs:
			var h: Array = a["hist"]
			if h.size() < c:
				continue
			na += 1
			hours += float(h[c - 1]["play_s"]) / 3600.0
			# upgrades of the partner the next run uses (older saves: everything spent)
			spent += float(h[c - 1].get("upg", h[c - 1]["spent"]))
			owned += float(h[c - 1].get("owned", 1))
			if int(h[c - 1].get("next", a.get("start", 0))) != int(a.get("start", 0)):
				moved += 1
			for j in range(c - w, c):
				ts.append(float(h[j]["t"]))
				coins += float(h[j]["coins"])
				saw += int(h[j]["saw_boss"])
				best = maxf(best, float(h[j]["t"]))
		if ts.is_empty():
			continue
		var mean := 0.0
		for t in ts:
			mean += t
		mean /= ts.size()
		print(_t("c_row") % [str(c), hours / na, int(100.0 * spent / na / total), _mmss(mean), _mmss(best),
			coins / ts.size(), int(100.0 * saw / ts.size()), owned / na, int(100.0 * moved / na)])
	for m in MILESTONES:
		var at: Array = []
		var hrs: Array = []
		for a in accs:
			for h in a["hist"]:
				if float(h["t"]) >= m:
					at.append(int(h["run"]))
					hrs.append(float(h["play_s"]) / 3600.0)
					break
		if at.is_empty():
			print(_t("c_ms_no") % [_mmss(m), K])
		else:
			print(_t("c_ms") % [_mmss(m), _num(_median(at)), _t("c_hours") % _median(hrs), at.size(), K])
	var at_max: Array = []
	var hrs_max: Array = []
	var pct: Array = []
	var wallet: Array = []
	for a in accs:
		var last: Dictionary = (a["hist"] as Array).back() if not (a["hist"] as Array).is_empty() else {}
		pct.append(100.0 * float(last.get("upg", a["spent"])) / total)
		wallet.append(float(a["coins"]))
		for h in a["hist"]:
			if float(h.get("upg", h["spent"])) >= total:
				at_max.append(int(h["run"]))
				hrs_max.append(float(h["play_s"]) / 3600.0)
				break
	if at_max.is_empty():
		print(_t("c_max_no") % K)
	else:
		print(_t("c_max") % [_num(_median(at_max)), _t("c_hours") % _median(hrs_max), at_max.size(), K])
	print(_t("c_left") % [runs, int(_median(pct)), int(_median(wallet))])
	var first: Array = []
	for h in accs[0]["hist"]:
		for id in h["bought"]:
			if first.size() < 14:
				first.append("%s(%d)" % [_upg_name(id), int(h["run"])])
	print(_t("c_buy") + (", ".join(first) if not first.is_empty() else _t("c_none")))
	for k in K:
		var a: Dictionary = accs[k]
		var d := int(a.get("partner", a.get("start", 0)))
		var g: Dictionary = a.get("gacha", {})
		print(_t("c_final") % [k + 1, Data.dex_by[d]["name"], int(Data.dex_by[d]["rarity"]),
			(g.get("owned", {}) as Dictionary).size(), int(g.get("stats", {}).get("pulls", 0)), int(a.get("switches", 0))])

## Progression curve of family-rule accounts: trainer upgrades bought, the partner's family level
## and stage, survival and coins at run 1, 5, 10..., then the milestones and each account.
func _family_report(accs: Array, runs: int) -> void:
	var K := accs.size()
	print(_t("f_cols") % _t_arr("f_cols_h"))
	var rows_at: Array = CHECKPOINTS.filter(func(c): return c < runs)
	rows_at.append(runs)
	for c: int in rows_at:
		var w := maxi(1, int(c * 0.2))
		var ts: Array[float] = []
		var coins := 0.0
		var saw := 0
		var best := 0.0
		var na := 0
		var sums := {"hours": 0.0, "tp": 0.0, "flv": 0.0, "owned": 0.0, "stage": 0.0}
		for a in accs:
			var h: Array = a["hist"]
			if h.size() < c:
				continue
			na += 1
			var e: Dictionary = h[c - 1]
			sums["hours"] += float(e["play_s"]) / 3600.0
			sums["tp"] += float(e["tp"])
			sums["flv"] += float(e["flv"])
			sums["owned"] += float(e["owned"])
			sums["stage"] += float(e["stage"])
			for j in range(c - w, c):
				ts.append(float(h[j]["t"]))
				coins += float(h[j]["coins"])
				saw += int(h[j]["saw_boss"])
				best = maxf(best, float(h[j]["t"]))
		if ts.is_empty():
			continue
		var mean := 0.0
		for t in ts:
			mean += t
		mean /= ts.size()
		print(_t("f_row") % [str(c), sums["hours"] / na, int(100.0 * sums["tp"] / na), sums["flv"] / na, _mmss(mean),
			_mmss(best), coins / ts.size(), int(100.0 * saw / ts.size()), sums["owned"] / na, sums["stage"] / na])
	# milestones: lasting 3 / 5 / 10 min, first evolution, final form, trainer maxed
	var first := func(test: Callable) -> Array:
		var at: Array = []
		var hrs: Array = []
		for a in accs:
			for h in a["hist"]:
				if test.call(h):
					at.append(int(h["run"]))
					hrs.append(float(h["play_s"]) / 3600.0)
					break
		return [at, hrs]
	var line := func(key: String, res: Array, extra: Variant = null) -> void:
		var at: Array = res[0]
		if at.is_empty():
			print(_t(key + "_no") % ([extra, K] if extra != null else K))
		else:
			var args: Array = [_num(_median(at)), _t("c_hours") % _median(res[1]), at.size(), K]
			print(_t(key) % (([extra] + args) if extra != null else args))
	for m in MILESTONES:
		line.call("c_ms", first.call(func(h): return float(h["t"]) >= m), _mmss(m))
	line.call("f_evo", first.call(func(h): return int(h["stage"]) >= 1))
	line.call("f_fin", first.call(func(h): return int(h["stage"]) >= 2))
	line.call("f_tmax", first.call(func(h): return float(h["tp"]) >= 0.999))
	for k in K:
		var a: Dictionary = accs[k]
		var d := int(a["partner"])
		var fm: Dictionary = FamilyRules.fam(a, FamilyRules.fam_of(d))
		var n_unl := 0
		for h in a["hist"]:
			n_unl += (h.get("unlocked", []) as Array).size()
		var last: Dictionary = (a["hist"] as Array).back() if not (a["hist"] as Array).is_empty() else {}
		print(_t("f_final") % [k + 1, Data.dex_by[d]["name"], int(Data.dex_by[d]["rarity"]), FamilyRules.stage(d),
			int(fm["lv"]), int(fm["stars"]), n_unl, int(a.get("uni", 0)), (a["gacha"]["owned"] as Dictionary).size(),
			int(a["gacha"]["stats"]["pulls"]), int(a.get("evos", 0)), int(a.get("switches", 0)),
			int(100.0 * float(last.get("tp", 0.0))), int(a["coins"])])

func _t_arr(key: String) -> Array:
	return TXT[_lang][key]

## 12 or 12.5 (a median of run numbers).
static func _num(v: float) -> String:
	return str(int(v)) if v == floorf(v) else "%.1f" % v

static func _median(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var b := a.duplicate()
	b.sort()
	return float(b[b.size() / 2]) if b.size() % 2 == 1 else (float(b[b.size() / 2 - 1]) + float(b[b.size() / 2])) / 2.0

## Upgrade name for the report (the game's Spanish name, with the Chinese one in --lang=zh).
func _upg_name(id: String) -> String:
	if _lang == "zh":
		return {"hp": "生命", "atk": "力量", "spd": "移速", "cd": "冷却", "def": "防御", "regen": "回血", "magnet": "吸取",
			"xp": "经验", "coins": "幸运", "moves": "开局2技能", "crit": "暴击", "reroll": "换卡", "ban": "禁用"}.get(id, id)
	return id

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
