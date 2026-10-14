# PokéSurvivor — Godot 4.7 port

[中文说明](README.zh-CN.md) (quick start, controls, tests and the playtest simulator in Chinese)

Native port of the browser game (vanilla JS + Canvas 2D, `../js`) to **Godot 4.7.1 / GDScript**.
The porting spec is [`docs/PORTING.md`](docs/PORTING.md); the JS code is the source of truth.
Feature parity with the web game, item by item: [`docs/PARITY.md`](docs/PARITY.md).

**Status: Phase 0 (foundation) + Phase 1 (minimal playable core loop) + Phase 2 (combat
completeness: every move kind, held items, all enemy behaviors, telegraphs, bosses, flow-field
pathing, shinies, VFX sprites) + Phase 3a (world visuals & terrain: pixel-exact threaded ground
painter, 21 biome palettes with crossfade, props + destructibles + loot, liquids, weather) + Phase 3b (altars, springs, locked chests, traps, hordes, golden
hour, lost Pokémon, thieves, rifts + the 18 legendary arenas, bonds / move fusion) + Phase 4 (meta-progression: save, menus, collection, upgrades,
gacha, missions/achievements, settings, full sprite set) + Phase 5 (presentation & platforms:
Spanish / English / Simplified Chinese, pixel CJK font, PMD theme, phone layouts and UI scale,
gamepad / keyboard navigation, Android back button, launcher icons) of PORTING.md §11.7.**
Single player only (no accounts, cloud, co-op, ranking).

## Quick start

From the repository root (Node ≥ 18, Godot 4.7.1 at `/opt/homebrew/bin/godot` or on `PATH`):

```sh
node tools/export_godot.js                   # JS data -> godot/data/*.json (reads js/, writes nothing else)
node godot/tools/sync_sprites.js             # all 966 species as atlases -> godot/assets/pokemon/ (git-ignored, ~60 s)
godot --headless --path godot --import       # first import (and after adding class_name scripts)
godot --path godot                           # play (or open the project in the editor and press F5)
```

Controls (desktop): **WASD / arrows** move · **1–4 / Q / E (Tab)** switch active move (or click a
slot) · **Esc / P** pause · level-up: **1 / 2 / 3** pick, **R** reroll (or click a card). Menus:
**arrows / Tab** move the focus, **Enter / Space** press, **Esc** back.
Gamepad: left stick move, LB/RB cycle, Start pause; every menu and card list by **d-pad / stick +
A**, **B** back (closes settings, resumes the pause), **Y** reroll.
Touch (Android, landscape): floating joystick wherever the finger goes down (not on a HUD button,
size from *Ajustes › Controles*), tap a move slot to switch, pause button top-right; the Android
**back** button pauses a run, closes the open screen, or asks to quit on the main menu. On desktop you can test touch with the editor setting
*Input Devices → Pointing → Emulate Touch From Mouse*.

Debug flags (after `--`): `--partner=<dex>` (default 4 Charmander), `--seed=<n>`, `--touch`
(force the touch UI), `--fps`, `--autoshot=<dir>` (visual check: title → run driven by the
bot → screenshots `title/t03/levelup/t20/pause/t45/over.png` → quit), `--bot=novice|casual|expert`
(who plays `--autoplay` / `--autoshot` runs; default the legacy test bot, see "Playtest bots"). Phone-like aspect:
`godot --path godot --resolution 1320x608 -- --autoshot=/tmp/shots --touch --ui-scale=1.5`.
Phase 5: `--lang=es|en|zh` (language for this run, not saved), `--ui-scale=<physical px per canvas
px>` (phone UI scale; 1.5 in a 1320×608 window = the 2640×1216 target phone at half size, i.e. its
880×405 canvas), `--i18n-missing=<file>` (writes the texts shown untranslated at exit).
Phase 4: `--metashot=<dir>` walks every meta screen (menu, collection, upgrades, gacha + slot
machine + reveal, missions, achievements, profile, settings, personality test, results, popup, a
short real run → results → menu) and saves PNGs (`debug/meta_shots.gd`); `--import-ui=<file>`
first pastes a web save into *Settings › Cuenta › Importar* like a player; `--import=<file>`
imports at start without the UI. `--save=<path>` picks the save file.
Phase 2 (`debug/autoshot2.gd`, also accepted by `tests/sim_smoke.gd`): `--learn=id,id,...` (learn
these moves instead of the starting one), `--move-lvl=<1-5>`, `--evolve`, `--boss-at=<s>` /
`--boss-gap=<s>` (boss times), `--force-shiny=<n>` (next n spawns shiny), `--item=<id>`, `--cycle`
(the bot rotates the active slot every 6 s), `--start-t=<s>` (start the run clock later: enemy cap
and late tiers at once), `--god` (no damage at all, telegraphs included). `--autoshot=<dir> --p2
[--p2-end=60]` plays a run and saves event shots (`p2_boss`, `p2_boss_cast`, `p2_boss_fury`,
`p2_telegraph`, `p2_enemy_shots`, `p2_fields`, `p2_shiny`, `p2_shiny_arrow`, `p2_item`,
`p2_levelup`) plus one every 5 s.
Phase 3b (same parser, also in `sim_smoke.gd`): `--event=horde,gold,lost,thief` (start these events
from `--event-at=<s>` (default 5), one after another; `thief` spawns at once), `--rift-at=<s>`
(open a rift near you then), `--rift-type=<type>` (the next arena's type), `--bonds=<n>` (start
with n bonds: the fusion picker opens as soon as two moves are loose), `--seek` (the bot walks to
the open rift, the lost Pokémon and its mark, thieves and unused altars / springs / locked chests /
traps instead of circling). `--autoshot=<dir> --p3b` (`debug/autoshot3b.gd`, god mode, teleports)
saves `p3b_altar`, `p3b_altar_power`, `p3b_spring`, `p3b_chest_open`, `p3b_chest_loot`, `p3b_trap`,
`p3b_trap_boom`, `p3b_horde`, `p3b_gold`, `p3b_lost_arrow`, `p3b_lost`, `p3b_lost_follow`,
`p3b_lost_goal`, `p3b_lost_rescued`, `p3b_thief`, `p3b_rift_popup`, `p3b_rift_portal`, `p3b_arena`,
`p3b_legend`, `p3b_rift_won`, `p3b_bond`, `p3b_bond_step2`, `p3b_fused`, `p3b_rift_lost` and
`p3b_arenas.png` (6×3 montage of the 18 arena themes), then quits.
Phase 3a: `--autoshot=<dir> --p3a [--seed=n]` (`debug/autoshot3a.gd`, god mode, teleports) saves
`p3a_b00_forest`, `p3a_b00_props`, `p3a_b00_rain`, `p3a_b01_cave_fog`, `p3a_b02_volcano_sun`,
`p3a_b04_fire_sand`, `p3a_b05_water`, `p3a_b06_grass_swamp`, `p3a_b07_electric_spark`,
`p3a_b08_ice_snow`, `p3a_b10_poison`, `p3a_b16_ghost_fog`, `p3a_b17_dragon` and
`p3a_fade_0_to_1` (mid crossfade) next to liquids / props, then quits. Every autoshot paints the
visible ground synchronously (no placeholder chunks in screenshots). **Bot / screenshot runs
(`--autoshot`, `--autoplay`, `--metashot`) use a fresh in-memory save that is never written**,
and bot runs don't advance missions or achievements.

## Tests

```sh
godot --headless --path godot --script res://tests/run_tests.gd        # unit tests, exit code 0 = pass
godot --headless --path godot --script res://tests/sim_smoke.gd -- --seconds=120 --seed=7 [--god]
godot --headless --path godot --script res://tests/sim_play.gd -- --bot=novice,casual,expert --runs=100 --lang=zh   # playtest batch
godot --headless --path godot --script res://tests/sim_play.gd -- --campaign=100 --accounts=4 --save-dir=user://accounts --lang=zh   # accounts that grow
godot --headless --path godot --script res://tests/meta_ui_smoke.gd     # Phase 4 screens, headless
godot --headless --path godot --script res://tests/nav_smoke.gd         # Phase 5 keyboard / gamepad / back button
godot --headless --path godot --script res://tests/run_i18n_tests.gd    # Phase 5 i18n checks only
godot --headless --path godot --script res://tests/run_p3b_tests.gd     # Phase 3b checks only
godot --headless --path godot --script res://tests/run_parity_tests.gd  # parity-audit checks only
godot --headless --path godot --script res://tests/sim_smoke.gd -- --seconds=900 --god --seek \
      --event=horde,gold,lost,thief --event-at=20 --rift-at=60 --learn=ember,water-gun,thunder-shock --quiet
godot --headless --path godot --script res://tests/bench.gd -- --json      # hot-path benchmark (see "Hot paths")
```

Phase 3b checks (`tests/phase3b_tests.gd`, 96 checks) against `data/test_vectors_p3b.json`
(`exportPhase3b()` in `tools/export_godot.js`: the unchanged `world.js`, `rift.js`, `events.js` and
`player.js` with stubs; `Math.random` replaced by a recorded mulberry32 stream whose uint32 values
Godot feeds back as exact `k / 2^32` through `sim/stream_rng.gd`): every interactable placed in
12×12 chunks for 3 seeds (type, kind, radius, flags), the **18 arena themes** (41×41 tiles + props,
half of them after the area was generated and purged), rift chance escalation over 2,000 s (open
frames, positions, draws), 13 legendary picks (weighted by beaten legends, forced types, arena
cfg, the legendary's def at 12 run times, a shiny one), 3,000 s of event / thief / lost-Pokémon
schedule for two streams (frames, horde casts, lost spots, thief stats and positions, exact draw
counts), horde types, 11 bond option/fusion cases (Atajos binds, Choice Band); plus live-sim checks
of the §7.8–7.11 numbers (altar powers + revert after 25 s, spring 14 %/s and refill, locked chest
3.5 s with decay and loot, each trap kind on you and on enemies, walking vs flying triggers, horde
bag and 30 s, golden XP/coins, thieves (stats, flight, 15 s escape, loot), lost Pokémon (follow,
damage, rescue reward, 120 s timeout), boss-alive retries, rift entry/stash/legendary/keepInside/
no spawns, win → bond picker, loss by falling and by time, rift expiry, fused slot casting).

`run_tests.gd` checks (86 checks): the §10.4 hash and mission-RNG vectors **bit-exactly**
(IEEE bits vs values computed by the JS itself), `terrainRaw` against three JS `world.js` terrain
dumps (seeds 12345 / 777 / 1, 9,728 tiles), the XP curve (cumulative 510 to level 5, 768 to
level 6, `xpFor(1..60)` identical to `Player.xpFor`), spawn rate (`rate(60) = 0.9072/s`,
bit-exact at 6 times), enemy HP/dmg/speed multipliers at t = 0/60/180/300 s (§5.3) plus the
full spawn pipeline (rounding, DMG_K, XP_K, elites), `behaviorOf` for all 966 species, tier
candidates, `defFor`, move ladders/evolutions vs JS `Moves.instance`, type chart, swept
projectile collision (a shot that crosses an enemy hugging the player in one frame still hits),
level-up offers (distinct cards, caps, forced gold evolution card) and a 60 s headless run.
`sim_smoke.gd` runs the whole loop without rendering at a fixed dt of 1/60 with a scripted bot
(`debug/bot.gd`: big circles + avoidance + gem pickup) and prints stats every 10 s, then the
kinds cast, behaviors / bosses / shinies / items seen and the `Sim.update` time (avg / max, and at
the 64-enemy cap). It takes the Phase 2 debug flags above, e.g.
`-- --seconds=600 --god --learn=rock-slide,discharge,quick-attack,flame-wheel --move-lvl=5 --boss-at=45 --cycle`.

### Playtest bots (`tests/sim_play.gd`)

`debug/bot.gd` has, next to the `legacy` test bot (the default everywhere: tests, benchmark,
screenshots), three **human-like** profiles picked with `--bot=novice|casual|expert` (sim_play,
sim_smoke, `--autoplay`, `--autoshot`). They notice a new telegraph / enemy shot / charger wind-up only
after a reaction time (0.40 / 0.27 / 0.18 s) and sometimes overlook one; re-plan a few times per
second by scoring 8 key directions (16 for the expert's stick) over the next 0.5–1 s against
predicted enemy positions (runners lead you like the game does), telegraphs, shot paths, walls /
lava / traps, crowding and corners; kite sideways around the crowd; keep the active move's range and
a clear line of fire (rocks, trees and walls stop shots); collect the best gem that no enemy stands
on; head for the rift, altars, springs when hurt and locked chests, and wait by a chest until it
opens (unless it gets crowded); pick cards, reroll and switch moves like a player of that level.
Their noise has its own RNG seeded from the world seed: a seed + profile replays exactly.
All the numbers are in `Bot.PROFILES`; `--bot-set=margin=20,chest=3/6` overrides them for one batch.

`sim_play.gd` plays `--runs` runs per profile (default 20, same seeds for every profile), each one
**until the Pokémon faints** (`--max=<s>` to cap them; a 4 h safety stop otherwise), on `--jobs`
headless Godot workers in parallel (default CPU threads − 2, max 12: about 7× faster than one
process; a worker that finishes takes the next block of seeds, and the results are identical to a
`--jobs=1` run). It prints the progress every 5 s, then per profile (`--lang=zh` for Chinese):
survival time (median / mean / shortest / longest and a histogram), the best run (seed, time,
level, kills, coins), kills and coins (mean / most / all runs), how many runs like these all of the
partner's remaining upgrades would take (and hours of play), level, how many reach and beat the
first boss, level at 1 / 3 / 5 / 10 min, movement (direction changes per second, time standing still,
distance kept from enemies), map use (locked chests opened, altars, spring healing, traps, rifts
opened / entered / won), shots (how often the line of fire to the target is blocked), **where the HP
went** and **what landed the last hit** (`Player.dmg_log` / `last_hit`, filled by `hurt(.., src)`:
`touch:<behavior>`, `boss`, `shot`, `hazard:<who>`, `trap`, `lava`, `weather`). Options:
`--upg=<0..1>` (permanent upgrades bought, fraction of each max), `--partner=<dex>`, `--max=<s>`,
`--csv=<file>` (one row per run), `--verbose` (one line per run), `--trace=<s>` (a state line every s
seconds; use with one profile and `--runs=1`), `--prof` (bot vs `Sim.update` time per frame). To watch
one play, run after run, fast-forwarded and with each result printed:
`godot --path godot -- --autoplay --bot=expert --speed=4` (`--speed=<n>`: n simulation steps per frame).

**Campaign** (`--campaign=<n>`): instead of every run starting from zero, each of `--accounts`
accounts per profile (default 4, one worker each) starts like a new account (500 coins, no
upgrades) and plays n runs in a row; after every run its coins buy the partner's permanent upgrades
the way that player would (`Bot.shop`: the novice always buys the cheapest, casual / expert the best
`Bot.SHOP_W` value per coin; Veto blocks the buff moves) and the next run starts with them.
`--save-dir=<dir>` keeps each account in `<dir>/<profile>_<k>.json` (coins, levels, runs, play time,
next seed, every run's summary); running `--campaign` again with the same dir continues them. The
report is the progression curve per profile (at run 1, 5, 10, 20, 30, 50, 75, 100, ...: hours
played, share of the 40,000 upgrade coins spent, survival mean and longest, coins per run, first
boss reached), when the accounts first last 3 / 5 / 10 min and buy every upgrade (median run and
hours) and the first purchases. Gacha (other partners), missions and achievements are not simulated.
`--campaign=0` with the same `--save-dir` only prints that report (accounts are saved after every run,
so this works while a campaign is still playing them).

Phase 2 checks (`tests/phase2_tests.gd`, 96 checks) against `data/test_vectors_p2.json` (written by
`exportPhase2()` in `tools/export_godot.js`, which runs the unchanged `enemy.js`, `combat.js`,
`hazards.js`, `pathing.js` with stubs for the browser-only parts): ladders L1–5 + evolution of all
64 moves (one check per kind), `reach()`, `evoInfo` (320 cases), gold card + stat weight 14,
`defFor` of all 966 species at two tiers (shotDmg/shotCd/range/minion/fanN/zones), boss defs
(60 rolled) and on-time stats, every boss cast (7 × fury on/off: telegraph shapes/delays/damage,
wind-ups, volley/nova angles and damage) for 5 bosses, ranged/fan/beamer/zoner/jumper/bomber
specials, healer/shielder/summoner on a known group, hazard `inside()` on 26,904 points, the BFS
flow field (57×57) and `dirFor` for 220 enemies on a known map, all 11 items' on/off. Plus live-sim
checks: every kind's runtime (nova ring, cone arc, boomerang out/back, chain falloff + hex, beam
strip, aura, melee arc, buff stacks, dash, mines arm/trigger/cap, meteors stagger/landing,
turrets, trail cap, orbit), item pickup/swap, Life Orb, Focus Sash, Choice Band, Rocky Helmet,
crits, telegraph detonation through i-frames, enemy shots, bomber, jumper, boss spawn/enrage/AI
casts/drops, shiny spawn/catch/no relocation, the windowed spatial grid vs a reference Map grid,
VFX textures, and three 50 s runs with 12 forced kinds, a boss and a shiny.
Reference values come from `data/test_vectors.json`, written by `tools/export_godot.js` with the
unchanged JS functions.

Phase 4 checks (`tests/phase4_tests.gd`, 43 checks; also `res://tests/run_meta_tests.gd` alone, ~1 s),
against `data/test_vectors_p4.json` (written by `exportPhase4()` in `tools/export_godot.js`, which
runs the unchanged `db.js`, `gacha.js`, `progress.js` + `ranking.js`, `upgrades.js`,
`achievements.js`, `starters.js` with a seeded `Math.random`): `newSave` keys/order; `migrate` +
`sanitize` of the **real web guest save** (`tests/fixtures/web_guest_save.json`) and of a legacy
v1 save (pity number, account-wide upgrades, bad dex keys / moves / levels / ticket strings)
deep-equal to JS; JSON round trip lossless (ints stay ints); end-of-run coins + breakdown text (7
cases); all 90 upgrade prices and `perks()`; gacha pool sizes, featured, **5 seeded pull sequences
bit-identical to JS** (results, pity, coins, tickets, owned), 1,000 seeded pulls with owned
shinies (swap / no repeats), pity 70 and the x10 guarantee with an unlucky RNG, rarity odds over
200k rolls, guarantee split 81.25/18.75 %, shiny 1 % and the effective 5★ rate over 50k pulls;
Madrid period ids for 16 instants (DST switches, ISO week/year edges) and the generated mission
sets for 32 date/account pairs; mission texts; advance/claim/reroll/pending semantics; all 127
achievement values on the real save and a rich synthetic one, `checkAch` grants + rewards;
personality result for 7 answer sets; import (localStorage string form) / export / garbage
rejection through `Save.import_json`. Tests redirect the save to `user://tests/` and delete it.
`tests/meta_ui_smoke.gd` drives the screens headless on an in-memory save (test → starter,
upgrades + Veto + hotkeys → `Meta.run_setup` → a run with those perks → `Meta.apply_run`, partner
change, gacha pull, mission claim/reroll, profile, settings, import, delete) and fails on any
script error or wrong state.
Phase 3a checks (`tests/phase3_tests.gd`, 59 checks; also `res://tests/run_p3_tests.gd` alone, ~10 s)
against `data/test_vectors_p3.json` (written by `exportPhase3()` in `tools/export_godot.js`, which
runs the unchanged `tiles.js` painters on real pixel buffers, `world.js` and `weather.js`; set
`P3_DUMP=<dir>` to also dump the raw RGBA of every JS chunk): **30 painted chunks (15 chunks x 2
biomes, 4 seeds, floor/dirt/walls/water/lava/arena palettes) identical byte for byte** (SHA-256 of
the RGBA + one hash per tile row to locate a difference; a failing chunk is saved to
`user://p3_chunk_*.png`), **424 prop sprites** (21 biomes x every type/variant + the 4 rift
frames) identical byte for byte, prop placement for 4 seeds (3,565 props incl. 71 interactables,
same order), chunks generated on worker threads == synchronous, 330 `collide` / `isFree` /
`projectileBlock` / `walkable` cases next to solid props and walls bit-exact, `fill_walkable` ==
`walkable` with props, `nearestBreakable` / `specialsNear` / `propsInCircle`, `liquidEffect` for 21
biomes x 10 type sets, a **60-minute weather run replayed with the JS random draws** (12 events,
level / `mult` / `speedFor` / `hurts` / sand-snow chip on the player and 5 enemies at 180 samples,
bit-exact), and live-sim checks: lava ticks through i-frames, water 0.6x, poison/spark immunities,
ice sliding, a rock cracking (variant 1) then breaking with loot and staying broken after its chunk
is regenerated, grass, trees stopping shots, auto-aim at the nearest rock/chest, the 4:00 biome
change with its 2.6 s crossfade, palette wrap (22 -> 1), weather wiring into `Player.spd` /
`Combat` and the painter on `WorkerThreadPool` == main thread.
Audio (`tests/audio_tests.gd`, 29 checks): the manifest has the 6 tracks with loops of exactly
`bars·16·60/bpm/4` s in whole samples (OGG length = loop), exactly the 155 SFX ids `AudioLogic` can
ask for (no missing, no orphan), every file loads with the manifest length, headroom gains match the
peaks; MIN_GAP per key (hit 45 ms, coin, shots per mapped kind), the 25-voice cap and its 150 ms
expiry, xp combo (+1 < 0.45 s, max 24, gap drops don't count), shot kind/type mapping, rarity
variants, fade ramps and the τ = 0.05 s volume smoothing.

## Project layout

```
project.godot        Compatibility renderer, 1280x720 canvas_items/expand, Nearest, pixel snap,
                     sensor-landscape, input map (§11.2, physical keycodes + gamepad)
main.tscn / main.gd  Game root: builds the layers, input -> Sim, camera, screens, autoshot
core/                u.gd (U: imul32/hash01/damp/JS rounding), data.gd (Data: static JSON tables),
                     sprites.gd (Sprites: meta, derived geometry, atlas pages + preview strips,
                     threaded LRU cache, white silhouettes), pmd_animator.gd (PmdAnimator),
                     sim_camera.gd, settings.gd (Settings: user://settings.cfg, auto quality),
                     sfx.gd (Sfx: audio facade) + audio.gd (AudioMgr, autoload "Audio") +
                     audio_logic.gd (sfx() rules), save.gd (Save: db.js format, user://save.json,
                     import/export), progress.gd (Progress: missions, achievements, run events,
                     Madrid period ids, seeded RNG), gacha.gd (Gacha), upgrades.gd (Upgrades),
                     meta.gd (Meta: run setup from upgrades, ticket banking, coins, endRun stats,
                     personality result)
sim/                 renderer-agnostic simulation (RefCounted, no nodes, no physics):
                     sim.gd (Sim: state machine, update order §1.4, onCollect, endRun),
                     player, enemy (behaviors + boss AI), enemy_mgr (windowed grid 52 wu,
                     separation, laggards), enemy_defs (tiers, behaviorOf, defFor, rollRun, boss
                     defs, scaling), spawner (bosses, shinies), combat (15 kinds + fields),
                     projectiles, hazards (telegraphs), pathing (flow field + LOS), items,
                     pickups, levelup, moves, types, world_map (terrain, props, arena, collision,
                     loot, biome + crossfade state, async chunk jobs), world_prop (WorldProp),
                     world_paint (WorldPaint: pixel-exact ground painter -> palette slots,
                     worker-safe), weather (Weather), fx, body
                     Phase 3b: interact.gd (Interact: altars, springs, locked chests, traps),
                     events.gd (Events: horde, golden hour, lost Pokémon, thieves), rift.gd (Rift:
                     portal, arena travel, legendary, win/loss), stream_rng.gd (StreamRng:
                     Math.random stand-in that can replay a JS stream)
render/              world_view.gd (one custom-drawn Node2D: telegraphs, ground fields,
                     pickups, y-sorted Pokémon, projectiles, air fields, FX + Camera2D),
                     vfx.gd (VFX: 23 attack shapes x 19 palettes from vfx.json), overlay.gd
                     (damage numbers), draw_util.gd, icons.gd (move emblems / UI icons),
                     event_draw.gd (EventDraw: rift portal, lost Pokémon + goal mark, y-sorted)
                     Phase 3a: ground_layer.gd (GroundLayer: threaded chunk painting, R8 palette
                     textures + palette shader + crossfade, LRU 48) and liquid_layer.gd
                     (shimmer), both children of WorldView drawn behind it; prop_art.gd (PropArt:
                     prop painters, cached textures, drawProp); weather_layer.gd (WeatherLayer:
                     tint + particles, feeds the fog uniform of main.gd's vignette shader)
ui/                  hud.gd, touch.gd (TouchInput: joystick + tappable HUD buttons), screens.gd
                     (level-up cards, pause — built in code with a Theme), item_choice.gd
                     (held-item swap screen), bond_ui.gd (BondUI: move-fusion picker),
                     event_hud.gd (EventHud: rift arrows/popup/arena timer, event timers, edge
                     arrows, altar power chip, screen flash)
                     Phase 4 (meta UI, CanvasLayer 6): meta_ui.gd (MetaUI: screen switching, top
                     bar, Esc/back), ui_kit.gd (UIKit: theme + widgets), poke_view.gd (PokeView:
                     animated Pokémon box), menu_screen, dex_screen, upgrades_screen, gacha_screen
                     + slot_machine (slots.js port), goals_screen (missions/achievements/profile),
                     settings_screen, test_screen (test/result/starters), results_screen,
                     popups.gd (toasts + achievement popups), backdrop.gd (menu world + wanderers)
                     Phase 5: presentation.gd (Presentation: phone UI scale, compact query, safe
                     area), input_router.gd (InputRouter: back button, quit dialog, keyboard /
                     gamepad focus navigation)
debug/bot.gd         scripted input used by the smoke test and --autoshot; meta_shots.gd (--metashot);
                     autoshot2.gd (Phase 2 + 3b debug flags + --p2 visual check);
                     autoshot3b.gd (--p3b visual check); autoshot3a.gd (--p3a visual check)
tests/               run_tests.gd, sim_smoke.gd, phase2_tests.gd, phase4_tests.gd (+ run_meta_tests.gd),
                     phase3_tests.gd (+ run_p3_tests.gd), phase3b_tests.gd (+ run_p3b_tests.gd),
                     fixtures/
data/                generated JSON (keep committed; regenerate with tools/export_godot.js)
assets/fonts/        Pixelify PS 400/700 + Fusion Pixel 12 px zh_hans (woff2, CJK fallback; OFL)
assets/icons/        launcher icons (192 px + adaptive 432 px foreground / background / monochrome)
core/ (Phase 5)      i18n.gd (I18n: central translation, port of js/core/i18n.js), i18n_translation.gd
                     (TranslationServer bridge), i18n_extra.gd (I18nExtra: Godot-only en / zh texts)
tools/sync_sprites.js  sprite pipeline (full set as atlases; --files = legacy per-file subset)
tools/pack_sprites.gd  atlas packer run headless by sync_sprites.js
```

Design notes: the simulation mirrors the JS module structure (managers + arrays + explicit update
order) and is driven by `Sim.update(dt)` with `dt = min(delta, 1/30)` like JS; `Sim.cur` plays the
role of the global `G`. `Data`/`Sprites`/`U` are static classes rather than autoload nodes so the
same code runs in `--script` test runs. Positions are 64-bit floats (`x`, `y` fields), never
`Vector2` (float32), so the numbers match JS.

## Sprites: the full set as per-Pokémon atlases (Phase 4)

All **966 species** (normal + shiny, 13,468 SpriteCollab PNGs / 95 MB) are usable: collection,
gacha, partner choice and the enemy cast. `node godot/tools/sync_sprites.js` runs
`tools/pack_sprites.gd` headless, which shelf-packs each species' 7 sheets into one page
(`<dex>.png`) and its 7 shiny sheets into another (`<dex>s.png`); species that don't fit in
2048×2048 (the GLES3 minimum) get extra pages `<dex>[s]_<k>.png` (59 of 1,924 species/variants). Several widths are
tried per species and the smallest area wins (Charmander: 928×832, 92 % used). It also writes
per-generation **preview strips** `idle<gen>[s].png` (row 0 of every Idle sheet) for grids and gacha
cards, and `assets/pokemon/atlas.json` (`[page, x, y]` of every sheet; sizes come from the meta).
Only species whose source PNGs are newer than their atlas are repacked (`--force` repacks all;
`--files [--from --to --shiny --partner]` restores the old per-file subset). The JSON is shipped
via the export preset's `include_filter`.

Measured on this Mac (M4 Max, Godot 4.7.1, same project, debug APK arm64, `--import` from a clean
`.godot`):

| Full set | files | import | `.godot/imported` | APK | export |
|---|---|---|---|---|---|
| (a) 13,468 PNGs as-is | 13,468 | 53 s | 139 MB | **108.3 MB** | 22 s |
| (b) atlases (chosen) | 1,985 + 18 previews | **22 s** (18 s in the real project) | 67 MB | **88.7 MB** | 8 s |

(The Gen-1 subset APK of Phase 1 was 34.8 MB, i.e. the runtime is ~30 MB.) Packing takes ~62 s
once. **(b) wins on every axis**, so it is the default; (a) remains available with `--files`.

Runtime (`core/sprites.gd`, same API as before — `Sprites.sheet()` returns a `Sheet` whose `tex`
is now an `AtlasTexture`, so `DrawUtil.pmd` is unchanged): one threaded load per page, LRU of 48
pages (evict after 20 s idle down to 75 %, a dropped page takes its sheets and white
silhouettes), `load_now()` loads the partner's pages synchronously at run start, white hit-flash
sheets are cut from one CPU read-back per page. UI grids use `Sprites.preview()` (≈10 KB of VRAM
per species instead of a ~4 MB page), full atlases only for single "hero" views. With every species
available, `EnemyDefs.restrict_to_available` is a no-op, so runs meet all generations (tier
candidates 276 / 261 / 182 / 270 / 192 / 75). The whole set fits in the APK (Play limit 150 MB for
a base APK, 200 MB AAB base module), so the `.pck`-per-generation split is not needed now.

## Phase 1 — what is implemented

- World: exact `terrainRaw` (bit-identical to JS), chunk data cache, `collide`/`isFree`/
  `isLiquid`/`projectileBlock`, liquid effects (water slow; lava etc. for later biomes), biome
  index changes every 240 s (palette + banner). (Phase 1) Ground = placeholder palette tiles baked per chunk
  (4 px per tile, JS floor bands approximated, ≤ 1 bake per frame with 300 wu prefetch).
- Player: movement (no acceleration, ice slide), targeting priorities, casting animations with
  speed-up, hurt / i-frames / blink / soft flash, melee damage reduction, regen, XP curve,
  death → 1.3 s Faint → results.
- Enemies: 6 tiers, `behaviorOf`, `defFor`, `rollRun` cast (+ runner), spawner (rate, CAP 64,
  elites at ≥ 55, ring placement with `isFree`, surges), time scaling, contact damage + pushback,
  knockback, burn/poison/slow, separation, spatial grid, corpses, laggard relocation, unstick.
  Behaviors chase / tank / runner / charger are exact; the others fall back to chase.
- Moves: projectile, melee, aura, orbit with the exact casting loop, reach, damage formula, type
  chart, crits, ladders and evolutions (gold card); swept projectile collision.
- Pickups: xp / xpBig with sticky magnet physics, merge cap 420, heal / magnet / bomb / ticket.
- Level-up: new / up / evo / stat cards with weights, caps and reroll; keys 1–3 and R.
- HUD: XP bar, name, level, HP bar, buff chips, timer, sub-line, banner, move slots (cooldown,
  level pips, tap/click), item slot, touch pause button, control hint, FPS; damage numbers;
  vignette; title, pause, results (coins formula) and restart.
- Touch: floating joystick (left half), HUD buttons, auto-pause on app switch, safe-area insets.

## Known gaps vs Phase 1 / deferred

- (Phase 2 filled the combat gaps listed here before: all kinds, bosses, shinies, enemy shots,
  telegraphs, pathing, held items, VFX sprites — see below.)
- (Phase 3a/3b filled props, weather, interactables, events, rifts and bonds — see below.)
- (Audio: done, pre-rendered from the JS synth — see *Audio* below. Save/meta-progression: Phase 4, below.)
- (UI strings stay Spanish in code; Phase 5 translates them centrally.)
- The headless bot dies around 60–90 s with only Ember (ranged enemies, telegraphs and pathing
  make Phase 2 runs harder); `--god` exercises longer runs.
- Not yet tested on a physical Android device (no export preset committed). Check 120 Hz frame
  pacing and touch on the target phone (2640×1216) in the first export.

## Phase 2 — combat completeness (what is implemented)

- **Moves**: all 15 kinds (`sim/combat.gd`): projectile, melee, beam (cut by walls), nova, aura
  (+ inward/rising/swirling sprites), buff (stacks), boomerang (out/back, re-hits), chain (x0.85 per
  hop, hex x1.7 on statused targets), mine (arm 0.35 s, trigger radius 14, cap 4+2n, half damage on
  timeout), meteor (0.09 s stagger, lands at 0.5 s, shadow + dashed target), turret (behind you,
  first shot 0.3 s, `count` live), dash (teleport, stops before walls, i-frames 0.3), trail
  (patches, no stacking while standing, cap 18), cone, orbit; ground/air field layers; the
  Phase 1 kind filter is gone (every pool move can be offered). Evolutions + forced gold card,
  stat weight 14 while waiting, crits (x1.5 after the type chart, orange number).
- **Held items** (`sim/items.gd`): 11 items with exact on/off; Choice Band (no slot change), Life
  Orb (1 % HP per cast, never KO), Focus Sash (1 HP once per 60 s real time), Shell Bell, Rocky
  Helmet (15 + 4·level to toucher). Bosses drop one; picking one up while holding another pauses
  the game (Sim state `choice`) on the two-card swap screen (`ui/item_choice.gd`, keys 1/2, click,
  tap). HUD item slot with icon and name.
- **Enemies** (`sim/enemy.gd`): ranged / fan / beamer / zoner / healer / shielder / summoner /
  jumper / bomber with the exact timers, ranges and damage (`shotDmg` inherits time, DMG_K, elite
  and enrage multipliers), enemy shots (190 wu/s, r 7, 2.4 s, type VFX + red ground ring, blocked
  by walls), support icons, shield bubbles. **Telegraphs** (`sim/hazards.gd`): zone/beam warnings
  that fill up, blink and detonate once ignoring i-frames.
- **Bosses**: 5 slots per run (x1.35 HP / x1.2 dmg defs, bossScale, sprite scale up to x2), the
  close/far AI with circle-strafe, slam / dash / leap / rain / beam / volley / nova casts, enrage
  under 50 % (x1.15 speed, faster casts, chains), boss bar, waves at 25 % and no surges during the
  fight, drops (item, coins, 14 big gems, heal, magnet, ticket x10 1/3), "boss" music request.
- **Pathing** (`sim/pathing.gd`): BFS flow field (R 28) around the player every 0.35 s, 8
  neighbours without corner cutting, line-of-sight shortcut (re-checked every 0.2 s), centre-of-tile
  fallback; keep-distance enemies back off in a straight line; unstick kept.
- **Shinies**: 1/4096 per spawn and boss (forced with `--force-shiny`), x2 HP x5 XP, banner,
  cyan aura + twinkles, never relocated, HUD edge arrows, catch = defeat (`Progress.shiny_caught`,
  run summary `sim.caught`, +300 coins if already owned).
- **VFX / FX** (`render/vfx.gd`, `sim/fx.gd`): the 23 procedural shapes x 19 palettes as tiny
  textures (16-direction rotation, spin, frames, scale 1.5 for big shots); projectile trails
  (ember, drip, spark, bubbles, dirt, wisp), beams (block body with wobble, lightning zigzag,
  travelling sprites), melee extras (impact, jaws, claw, vine/feather leaves), impact sprites,
  twinkles, sprite caps by quality.

### Phase 2 — known gaps

- (Phase 3a added props: attacks break rocks/chests/grass, enemy shots stop on solid props,
  `walkable` / `fill_walkable` include solid props; weather multipliers are wired.) The `thief`
  behavior and golden enemies come with events (Phase 3b).
- (Audio is implemented: see *Audio* below.)
- The flow field and the ground placeholder generate terrain chunks the camera prefetch doesn't
  cover; in game they are built on `WorkerThreadPool`, headless runs stay synchronous.

## Phase 4 — meta-progression (what is implemented)

- **Save** (`core/save.gd`): `user://save.json` holds exactly the JS save object (`db.js`
  `newSave` / `migrate` / `sanitize`, VERSION 3, string keys like `"4"`, ints kept as ints), so a
  web save imports verbatim and an export can go back into `localStorage`. Commits immediately
  (purchases, pulls, partner/hotkey/ban/profile edits, mission claims, tickets as soon as they are
  picked up, end of run). Single local profile ("Entrenador"); no accounts/cloud/merge.
  *Ajustes › Cuenta* (the web app's tab name): paste/clipboard/`save_import.json` import (validated with migrate+sanitize,
  previous save kept as `save.backup.json`), export to clipboard + `save_export.json`, delete.
- **Flow** (`main.gd` + `ui/meta_ui.gd`): no partner → personality test (8 questions → trait →
  suggested starter, "Elegir otro" → 29 starters) → menu → Play (saved partner, shiny skin,
  per-Pokémon perks, hotkeys `pbind`, bans `pban`, Repertoire 2nd move via
  `Sim.start_run(dex, seed, opts)`) → run → results (coins formula, stats, `runEnd`, achievements)
  → menu. Esc / gamepad B goes back from sub-screens. `--autoplay` starts runs from the menu.
- **Menu** with the live backdrop (§1.7: world seed 4242, 20 wanderers, drifting camera, biome
  every 30 s; ground drawn by `WorldView` in state `ui`), partner card (lively, type border or
  shiny), Normal/Shiny toggle, list Play / Pokémon / Mejoras / Gacha / Misiones / Ajustes (no
  Friends/Ranking), stats box, top bar (coins, tickets, settings), pending-rewards badge.
- **Collection**: 9 generation tabs (have/total), filters all/owned/missing/shiny/rarity, grid
  (silhouettes, crown, shiny star), detail (stats bars, start move, learnable moves, Normal/Shiny
  view, choose partner). **Upgrades**: Pokémon selector, 13 cards with pips and prices, Veto picker,
  4 hotkey selects. **Gacha**: 9 banners, rates panel, x1 / x10 / x10-ticket, pity line, slot machine
  (port of `slots.js`: lever, reels, suspense on 4★+/shiny, LED, bulbs, tray, sparks, click =
  faster) and reveal cards 150 ms apart (NEW / SHINY NEW / duplicate +coins, glow on 5★/shiny).
- **Missions / achievements / profile** (`core/progress.gd`): daily 3 + weekly 2 from the Madrid
  period ids (EU DST rule + ISO week computed in code, no tz database) and the FNV-1a/mulberry32
  seed, advance/claim/reroll, reset countdown; 127 achievements (values hand-ported, goals from
  data), auto-granted rewards, 21 titles, popups (medal or legend sprite, queue 2.8 s + 0.25 s);
  profile favourites (3) and title.
- **Settings**: quality auto/high/mid/low (auto sampler of `settings.js`), damage numbers, calm,
  FPS, joystick size, music/sfx/mute (drive the Music/SFX buses live), language (Spanish only, others
  shown disabled), save import/export/delete. `user://settings.cfg`.
- **Progress hooks in the run**: `Progress.kill(e)` (enemy_mgr.gd, every death: kills, kills by
  type, bosses, legends), `Progress.event("evolve")` (levelup.gd), `"item"` and
  `Progress.shiny_caught()` (sim.gd, Phase 2), `"runEnd"` (Meta.apply_run: survive minutes, level,
  picked-up coins, partner types). Phase 3 wired the rest: `Progress.event("chest")` when a locked
  chest opens (`WorldMap.destroy_prop`), `Progress.event("rift", {"type": arena_type})` on a rift
  win (`Rift._won`), `Progress.in_arena` while inside a rift arena (`Rift.begin` / `_finish` /
  `reset`) and the rescue's `Save.grant(dex, "rescue")` + commit (`Sim.on_rescue`).
  Co-op `group` runs don't exist, so `group1`/`group10` stay unreachable.

### Phase 4 — known gaps

- (Phase 5 added the languages, the PMD theme and the pause screen's "Ajustes" button.)
  (Audio: see *Audio* below.)
- The menu backdrop uses the Phase 1 placeholder ground.
- No public profile / friends / ranking (offline port). Achievement popups also show during runs,
  as in JS.
- Not yet checked on a phone: the collection builds up to 156 animated preview cells per tab.

## Phase 5 — presentation & platforms (what is implemented)

- **Languages** (`core/i18n.gd`, port of `js/core/i18n.js`): Spanish source strings are the keys and
  every visible text is translated **centrally**, never at the call sites: Controls (Label, Button,
  tooltips, OptionButton / PopupMenu items, placeholders) through `TranslationServer` (one script
  `Translation`, `core/i18n_translation.gd`, whose `_get_message()` is `I18n.t()` — the equivalent
  of the web's MutationObserver), drawn text through `DrawUtil.text()` / `text_width()` (the
  patched `fillText`). Same three levels as JS: exact phrase (ALL-CAPS text case-insensitive),
  `{x}` patterns (filled in order, captured groups translated recursively), whole-word fragments
  (keys ≥ 4 chars or with a space, longest first) plus case keeping; Chinese loads the English
  dictionary first as its fallback, like the web. Dictionaries: `data/lang_en.json` /
  `data/lang_zh.json` = every `G.I18n.add()` call of `js/data/lang-*.js` in order (lang-zh also
  adds the 966 Pokémon names by dex), written by `exportI18n()` in `tools/export_godot.js`.
  Godot-only texts (save import/export, the quit dialog, touch/gamepad help, Lv. / SPD chips, region
  names in Chinese...) are in `core/i18n_extra.gd` (its patterns are tried before the web ones).
  Other agents keep writing Spanish: anything in the web dictionaries is translated automatically;
  add the rest to `I18nExtra`. A text with line breaks is translated line by line (Godot-only).
  Player-facing language names in Settings are not translated (`auto_translate_mode` disabled),
  nor the JSON sample of the import box. Language: *Ajustes › Gráficos › Idioma* (applies at once,
  no reload), default from `OS.get_locale()` (zh* → zh, es* → es, else en) until one is picked.
- **Fonts**: Pixelify PS (Latin) with **Fusion Pixel 12 px zh_hans** (`.woff2`, imported as is) as
  the fallback for CJK, both without antialiasing / hinting / subpixel positioning; the CJK font
  uses `fixed_size = 12` + `FIXED_SIZE_SCALE_INTEGER_ONLY`, so Chinese is drawn at whole multiples
  of its 12 px grid (12 px up to 17 px text, 24 px from 18 px) and stays crisp at small HUD sizes.
- **Theme** (`UIKit.theme()`, merged into the engine default theme by `main.gd`, so every Control on
  any CanvasLayer gets it): the PMD `.box` (vertical gradient `#2c519f → #1a3170`, 3 px white
  border r 12, 3 px dark outer ring, 2 px blue inner ring) and the `.btn` family (blue / gold /
  danger with a 2 px dark ring and a 4 px bottom ledge, pressed = 2 px lower, hover ×1.15
  brightness, disabled grey) are 9-patch `StyleBoxTexture`s painted pixel by pixel at startup
  (geometry cached, ~50 ms on desktop); ghost buttons, chips, tabs, `.card`s (level-up / item /
  evolution), cells, fields, sliders, popups and tooltips are `StyleBoxFlat`s with the CSS values;
  keyboard / gamepad focus shows a gold ring (not on mouse / touch clicks).
- **Phone layout** (`ui/presentation.gd`): the web lays out its HTML in CSS px = Android dp, so on
  mobile the canvas is scaled to ~1 px per dp, rounded to a whole factor when close: the
  2640×1216 target phone gets an **880×405 canvas at exactly 3×** (pixel art and the 12 px CJK font
  stay crisp; desktop keeps 1280×720). Canvases ≤ 520 px tall use the CSS compact layouts: small top
  bar, two-column menu list without the stats box, smaller logo / partner stage, page margins under
  the top bar, wrapping collection filters and a narrower detail pane, compact gacha banner, slot
  machine at ×1 and 100 px reveal cards, two-column results, 8-column starter grid, achievement
  popups at the bottom, compact level-up / item cards. Safe-area insets (cut-outs) move the top bar,
  pages and HUD buttons.
- **Input** (`ui/input_router.gd`): Android back = pause a run / close the open screen / quit dialog
  on the menu (`application/config/quit_on_go_back=false`); keyboard and gamepad focus navigation of
  every menu and modal (the first arrow / d-pad / stick press focuses the screen's first control or
  the one marked `focus_first`; clickable cards become focusable and get a synthetic click on A /
  Enter; scroll containers follow the focus; text fields only by click). `ui_accept` / `ui_cancel`
  include gamepad A / B; A/B/X no longer pick cards directly (d-pad + A does). Touch: the joystick
  appears wherever the finger goes down, like JS. The pause screen has *Ajustes* (sound tab) like JS.
- **Settings**: quality auto-scaling (§8.8, sampled while playing), FPS counter, damage numbers and
  calm mode are wired (calm also applies mid-run to the camera shake and screen flash); `lang`.
  Debug runs never write `settings.cfg` (`Settings.read_only`).
- **Android export**: launcher icons from the game's icons (`assets/icons`, adaptive foreground /
  background / monochrome), label "PokéSurvivor", sensor-landscape, immersive + edge-to-edge; the
  debug keystore comes from the editor settings (never committed). `config/name` stays
  "PokeSurvivor" (it names the `user://` folder of existing desktop saves).
- **Tests**: `tests/i18n_tests.gd` (in `run_tests.gd`) compares `I18n.t()` with the real
  `js/core/i18n.js` + dictionaries run in Node on 6,020 strings (all dictionary keys, upper / lower
  case, every pattern filled with numbers, Pokémon / move names and nested patterns, 1,700 fragment
  sentences, whitespace cases, mission / achievement / move / item / upgrade / biome texts and the
  Godot UI literals) in es / en / zh — all identical — plus the supplement, multi-line texts and the
  cached lookup cost (≈0.2 µs). `tests/nav_smoke.gd` drives the real game in Chinese with scripted
  keyboard / gamepad / back-button events only: personality test → partner → menu → run → level-up
  pick of card 2 → pause → settings → resume → results → menu → quit dialog.

### Phase 5 — known gaps

- Not yet tried on the physical phone: check the 3× canvas, the safe area with the camera cut-out
  and 120 Hz pacing with the `[perf]` line.
- Some web texts are untranslated in the web too and stay so here (e.g. an altar power's
  description inside its banner); add them to `I18nExtra` when seen (`--i18n-missing=<file>`).
- Quitting a scripted run while threaded sprite loads are in flight can crash the engine at exit
  (seen in headless `--script` tests; `nav_smoke.gd` waits for the loads first).

## Audio (pre-rendered from the JS synth)

The web game synthesizes everything live with Web Audio (`js/core/audio.js`, scores in
`js/data/music.js`). The port plays files rendered offline **by that unchanged code**:

```sh
node godot/tools/render_audio/render.js           # ~1 min: 6 tracks + 155 SFX + manifest.json -> godot/assets/audio/
godot --headless --path godot --import            # then import them
node godot/tools/render_audio/render.js --check-loops --out=/tmp/x   # loop periodicity check only
```

Needs Node ≥ 18 (no npm packages), Google Chrome (`CHROME=` to override the macOS path) and sox with
Vorbis (`SOX=`, default `/opt/homebrew/bin/sox`; Homebrew's ffmpeg has no libvorbis). A local HTTP
server (127.0.0.1, ephemeral port) serves `tools/render_audio/page.html|js` plus the two game files to
headless Chrome, driven over the DevTools protocol through `--remote-debugging-pipe`. `page.js`
re-evaluates `audio.js` for every job with `AudioContext` → a Proxy of an `OfflineAudioContext`
(fake `currentTime`, state always `running`), the 25 ms sequencer `setInterval` captured and run in
1 s render slices (`suspend()`), `setTimeout` synchronous (the reverb IR fill), `performance.now`
on the fake clock (MIN_GAP), a seeded `Math.random` (dry SFX are byte-identical on every run; what goes
through Chrome's convolution reverb differs by ~−60 dB between runs), volumes through
its own `localStorage` key, and the master compressor swapped for a gain (it acts on the live
music + SFX sum, so the port does the master stage itself). Same instruments, reverb (1.8 s
noise IR) and buses as the game.

- **Music** (`assets/audio/music/*.ogg`, Vorbis q4, 44.1 kHz stereo): 3 loops rendered, the 2nd
  kept (`[0.1 + L, 0.1 + 2L)`, L = steps·60/bpm/4 rounded to whole samples), so the file start
  already holds the reverb/release tails of the previous loop and loops seamlessly at its end.
  village 38.400 s, forest 31.475, cave 41.739, volcano 14.545, boss 12.800, rift 23.415 (2.2 MB).
  Loop check: the 3rd loop's first second vs the file start differs by 0.03 dB (median 10 ms RMS
  envelope) for village/boss, 0.3–0.5 dB for the others (noise bursts and sub-sample note shifts
  when L·44100 is not whole); the seam step is below the median sample step. Files peaking above
  0.97 are scaled down and `gain_db` (boss +2.3, rift +1.4, forest +0.1 dB) restores the level.
- **SFX** (`assets/audio/sfx/`, 155 files): every id of the JS `SFX` table rendered 1.5 s into the
  context (bus ramps settled), trimmed below −72 dBFS with a 5 ms fade, mono when L = R, 16-bit
  WAV (imported as QOA by Godot 4.7) or OGG when longer than 1 s (reverb tails: shiny, legend,
  rift, biome...). The ×2.4 SFX bus gain is baked in; bell/pad reverb sends are mixed at the
  default music/sfx balance. Parametric SFX are rendered per variant instead of pitch-shifted (a
  shift would change their length): `shot` per kind × type (melee and nova ignore the type: 92
  files), `xp` per combo step 0..24 (25), `burst`/`reveal` per rarity 1..5.
- `manifest.json`: per file duration, channels, peak/RMS, `gain_db`; per track bpm, bars, loop
  length and the loop checks; the Chrome compressor curve; sha1 of the two JS sources.
- Size: 5.3 MB of sources in the repo, **3.2 MB in the APK** (Vorbis 2.5 MB + QOA SFX 0.66 MB);
  `export_presets.cfg` includes `assets/audio/manifest.json` (the sounds are imported resources).

Runtime (`core/audio.gd`, autoload **Audio** = `AudioMgr`; game code calls the static facade
`Sfx.play(name, opts)` / `Sfx.music(name)` of `core/sfx.gd` at the JS call sites):

- Buses Music (`music·0.7`, 0 when muted) and SFX (`sfx`) → Master, volumes from `Settings`
  (Ajustes › Sonido), smoothed like `setTargetAtTime` (τ 0.05 s). Master = ×0.9 output gain
  + 0.59 dB: measured in Chrome, the JS `DynamicsCompressor(−14 dB, ratio 4, knee 30)` only adds
  that makeup below −14 dB and takes 0.4 dB off a 0 dBFS sine, so a hard limiter at −0.3 dB
  replaces it (Godot's compressor has no soft knee). Measured in a windowed run: the village theme
  comes out at −21.79 dB RMS vs −21.80 dB for the full JS chain rendered in Chrome.
- Music: `music(name)` is idempotent; the old track fades out linearly in 0.7 s, the new one fades
  in 0 → 1 over 0.8 s and starts 0.1 s after the call (as `startSong`). Selection as in JS: village
  in every menu (`main.gd`), forest at run start, `rift` in an arena, else `boss` while a boss is
  alive, else forest/cave/volcano by biome (`sim.gd`), silence on the results screen.
- SFX: `AudioLogic` = `sfx()` (MIN_GAP per key — shots per kind —, at most 25 voices counted
  150 ms each, xp combo, variant ids), then a pool of 32 players (oldest stolen). Nothing plays when
  muted or at sfx 0. Hover/click/error sounds on `UIKit.button` and the run screens' buttons, click
  when a volume slider is released.
- Like JS, nothing ducks or pauses the music while the game is paused; on a phone the Master bus is
  muted while the app is in the background. Headless runs (tests, `--script`) keep the logic and
  load/play nothing.
- Debug (after `--`): `--audiolog` (implied by `--autoplay`) prints `[audio] music=… played=…
  gap_drop=… cap_drop=… voices_max=…/25 players_max=…/32` every 5 s; `--sfx-stress` fires 40 SFX in
  one frame every 10 s; `--audio-rec=<file.wav>` records the Master bus (pre-fader) until quit.

Known gaps: no Pokémon cries (none in JS either); SFX reverb tails follow the SFX volume instead of
the music volume (JS routes them through the music bus); music loops restart from the top on every
switch, like JS.

## Phase 3a — world visuals & terrain (what is implemented)

- **Ground painter** (`sim/world_paint.gd`): literal port of `tiles.js` `paintChunk` / `dirtMask`
  / `paintFloor` / `paintWall` / `paintLiquid` (inlined 32-bit hash with incremental x terms, the
  4-px dirt lattice stored as float32 like the JS `Float32Array`, every float op in JS order),
  **pixel-exact** (30 chunk hashes). It writes one of 24 *palette slots* per art pixel instead of
  RGBA: the slot map depends only on (seed, terrain), never on the biome. `render/ground_layer.gd`
  runs it on `WorkerThreadPool` (≤ 3 tasks, visible chunks first, then 300 wu of prefetch), uploads
  the result as a 256×256 **R8** `ImageTexture` (≤ 2 per frame, ~0.2 ms) and draws it at CW + 1 wu
  with a palette shader. A biome change or the 2.6 s **crossfade** only changes two palette
  uniforms (`mix(old, new, smoothstep k)` == JS "old image, then new at alpha k"): nothing is
  repainted. Until a chunk is painted a 16×16 per-tile placeholder (same shader) is shown. Cache:
  48 textures, LRU (never a chunk drawn this frame). The menu backdrop uses it too (async chunks).
- **21 biome palettes** cycling every 4 min (`floor(time/240) mod 21`, crossfade, banner, ring;
  biome name in the HUD sub-line) — the palette table comes from `world.json` (`tiles.js`
  `BIOMES` incl. the 18 derived arena palettes).
- **Props** (`WorldMap._place_props`, `sim/world_prop.gd`): `placeProps` incl. interactables (step 1)
  and the arena branch, pure so it runs inside the worker chunk jobs (broken props are filtered when
  a chunk is stored); solid-prop index per chunk (`ChunkData.solid`) used by `collide`, `is_free`,
  `walkable`, `fill_walkable`, `projectile_block`. Painters (`render/prop_art.gd`: tree / crystal /
  dead tree, rock + cracked, grass + sway frame, chest, altar ×8, spring + dry, bigchest, trap ×3,
  rift ×4) are **pixel-exact** (424 hashes), cached by biome/type/variant (a worker pre-paints the
  current and next biome), white silhouettes for the hit flash. Drawn as in `drawProp`: shadow,
  y-sorted with entities (flat ones first), old/new biome sprite crossfade, altar halo, bigchest
  ring, spring twinkles.
- **Destructibles + loot** (`damage_prop` / `destroy_prop`): every `damageProp` call site of
  `combat.js` (melee arc, beam, aura, dash, field blasts, player shots: walls and indestructible
  solid props stop them, rocks/chests take a hit and use pierce, grass never stops a shot, orbs
  rehit) and the exact loot tables (grass, rock, chest, bigchest with `level_xp()` +
  `Progress.event("chest")`, trap → `Sim.interact.trap_effect`). Enemy shots stop on any solid prop.
  The player auto-aims at `nearest_breakable(200)` when no enemy is around.
- **Liquids**: water/swamp slow, lava/poison/spark damage through i-frames, ice sliding, immunities
  (Phase 1/2 code, now with every biome's liquid), the liquid shimmer (`render/liquid_layer.gd`,
  hashes cached per chunk) and damaging liquids excluded from pathing.
- **Weather** (`sim/weather.gd`): schedule, intensity, `mult` (wired into `Combat._hit`, player
  shots and `Player.hurt`), snow `speed_for` (player and enemies), sand/snow chip, `force` /
  `stop` / `clear` for the arena; `render/weather_layer.gd` draws the tint + particles under the
  vignette and feeds the fog vignette (main.gd's shader now composites vignette + fog); HUD chip
  `NAME · Ns` top right.

### Phase 3a — performance

Painter (one 256×256 chunk, GDScript, M4 Max): **33 ms avg / 36 ms max on a lightly loaded machine**
(main thread, 15 chunks; `run_p3_tests.gd` prints it), 64 ms avg / 82 ms max on worker threads
during a 5-minute `--autoplay --god` run while the machine was at load average 100-280 (other
jobs). The main thread only polls tasks, uploads ≤ 2 textures/frame and draws: ground layer avg
**0.05 ms/frame, max 1.2 ms** in a run (chunk data store + placeholder), liquid shimmer 0.06 ms avg;
texture upload ≤ 0.21 ms; no chunk is ever baked on the main thread in game (only the screenshot
harness sets `sync_paint`). GDScript was fast enough, so no shader / GDExtension: on a phone the
paint takes maybe 2-4x longer on a background thread, which only delays when a far chunk switches
from its placeholder (prefetch covers 300 wu ≈ 2-3 s of walking). Prop sprites are pre-painted
per biome on a worker; the first frame of a biome may paint the few missing ones (~1 ms each).

### Phase 3a — extension points and known gaps

- Arena: `WorldMap.set_arena({tx, ty, r, type})` / `set_arena({})`, `arena_dist`, `arena_safe`,
  `purges(cx, cy)` (chunk data and ground textures are dropped like `setArena`), `arena_biome(type)`;
  interactables: `specials_near`, `break_prop`, `WorldProp.used/charge/open/kind`,
  `PropArt.texture(0, "rift", frame)`; weather: `Sim.weather.force/stop/clear`.
- `PropArt.CHEST_TIME` duplicates `Interact.CHEST_TIME` (3.5) to avoid a class dependency.
- Flat props are drawn before the y-sorted list, so a flat event decal (goal mark, y - 4000) is
  drawn after them instead of interleaved by y (they rarely overlap).
- Not measured on the phone yet: check `[perf] ground` there (paint_avg on workers, main_max).

## Phase 3b — interactables, events, rifts, bonds (what is implemented)

- **Interactables** (`sim/interact.gd`, placed by Phase 3a's `WorldMap.place_props`): altar
  (touch within `max(30, r + r + 14)`: one of 4 powers for 25 s — Furia atk ×2, Rayo spd ×1.45,
  Imán magnet ×4, Prisa cd ×0.6 — a new power replaces the old, exact revert, chip in the buff row
  and a pulsing ring under the feet), spring (+14 % max HP/s while within 26 wu, charge −0.09/s,
  refills in 45 s within 720 wu, "+N" every 0.6 s, dry banner), locked chest (stay within
  `max(46, r + r + 24)` for 3.5 s while they attack you; progress decays ×1.5 when you leave; loot +
  `Progress.event("chest")` in `WorldMap.destroy_prop`), traps (you within 13 wu or any walking
  enemy touching a 3-wu circle; poison / sticky / explosive on enemies within 74 + r and on you
  within 51.8 wu ignoring i-frames). No keys or costs exist in JS (§7.8).
- **Events** (`sim/events.gd`): every 240–300 s (never with a boss alive → retry in 10 s, never
  in an arena) a horde (30 s, spawns only from ≤ 4 defs of one type with ≥ 3 non-support
  candidates, burst of 6), golden hour (30 s, current and new enemies golden: XP ×2, 35 % coin) or a
  lost Pokémon (≤ 4★, walking, 220–300 wu away, mark 700–850 wu further; touch → follows you,
  enemies hurt it, rescue within 56 wu: heal 50 %, 12 coins ×5 + a ticket, 1 in 5 joins your
  collection via `Sim.on_rescue` → `Save.grant(dex, "rescue")`, else +150 coins if owned; leaves
  after 120 s), never the previous one. Thieves: 2 per run (first at 120–240 s, then 240–360 s,
  boss alive → 8 s): Meowth (coins ×20) or 1 in 4 Gholdengo (hp ×1.5, 6 coins + ×10 ticket), flee
  zigzagging, escape after 15 s, gold ring. HUD: event countdown, edge arrows to the lost Pokémon /
  "Marca" (with metres) and to thieves; world: green mark with heart, "!" while it waits, HP bar.
- **Rifts** (`sim/rift.gd`): from 75 s, a check every 30 s (skipped with a boss alive) with chance
  20 % × (1 + misses); portal 380–560 wu away for 45 s (4-frame `PropArt` sprite, glow, motes,
  popup 4.5 s, pulsing edge arrow / bouncing arrow with "GRIETA · N m · N s"); walking within 30 wu
  enters: legendary weighted 4:1 for not-yet-beaten ones (`save.legends`), arena at tile
  5000–7999 of one of its types (`WorldMap.set_arena`, palette `arena_biome`, theme weather), map
  enemies/projectiles/fields/hazards cleared or stashed (`EnemyMgr.stash/restore`), lavender
  flash, you south / the legendary (boss + legend, walking, `legend_def`, shiny 1/512) north.
  Inside: no spawns, events, thieves, rift checks, laggards or biome changes; `keep_inside`;
  `Progress.in_arena`; "GRIETA · m:ss"; music "rift". Win: `Progress.event("rift")`, pull all
  pickups, +1 bond, back after 5 s; loss (down 1.4 s or 120 s): back after 1.2 s, revived at 30 %
  (dying in the arena never ends the run). Back: old biome, `Weather.clear()`, restored enemies,
  bond picker.
- **Bonds** (`Player.bond_options/fuse`, `Sim.offer_bond/choose_bond`, `ui/bond_ui.gd`): "pair"
  (two loose moves, two steps with "Atrás") or "add" (one loose move joins the growing group, up to
  4); kept with a banner when impossible and offered every frame; Atajos arrangement and Choice
  Band respected; every move of the active group ticks and casts on its own cooldown (Phase 2
  combat). HUD: pink fused slot with a 2×2 grid of the moves (own cooldowns, flash on cast),
  "Name +N", stored-bond icon (×N). Keys 1–4, click or tap.
- New strings are the JS Spanish strings, built exactly like JS (translated centrally by Phase 5).

## Parity audit (docs/PARITY.md)

A module-by-module comparison with the web game (424 rows: 292 present, 93 fixed by the audit,
13 left as intended / cosmetic, the rest online-only). What it added or changed:

- **Credits / licensing**: *Ajustes › Acerca de* shows the web's version line, "Créditos
  completos" (the 114 SpriteCollab artists of `CREDITS.md`, CC BY-NC 4.0, PokeAPI, Pixelify Sans /
  Fusion Pixel Font under the SIL OFL 1.1 with their full licence texts, trademark), "Aviso legal
  y privacidad" (the offline parts of the web's legal page: fan project, not affiliated with
  Nintendo / Creatures / GAME FREAK / The Pokémon Company, crypto, third-party content, contact,
  source code, privacy), "Contacto" and "Código (GitHub)"; the menu has the web's credits line.
  `exportCredits()` in `tools/export_godot.js` copies `CREDITS.md` and the font licences
  (`assets/fonts/OFL.txt`, `assets/fonts/fusion-pixel/`) into `godot/`; the Android preset packs them.
- **Menus**: top-bar sound button + panel and the same controls in the pause screen
  (`ui/sound_controls.gd`), user pill → *Misiones › Perfil*, "Ver mi perfil público" (profile
  preview built from the save, like the web's app mode), gold generation tabs, cyan Normal/Shiny
  toggle, red banned chips, Spanish move order, gacha lines with icons, slot glow, card pulses,
  hover sounds on every clickable (`UIKit.button(..., hover)`), the web's click/back ids.
- **Run**: Esc closing Ajustes over the pause no longer resumes; one tap = one bond / item card;
  held items on the ground show their icon; deleting / importing the save mid-run ends the run
  first (`MetaUI.quit_run_requested` / `save_replaced` → main.gd); silent auto-pause only when the
  app goes to the background (or the window is minimised); Android vibration on a hit
  (`mobile/shell.js`, VIBRATE permission); damage numbers under weather / vignette (Overlay
  layer 1, Vignette layer 2); screen flash drawn by `TouchInput` over the joystick.
- **Tests**: `tests/parity_tests.gd` (17 checks; reference values in
  `tests/fixtures/parity_vectors.json` from `exportParity()`), the Esc step in `nav_smoke.gd`.
  `Sfx.test_log` (an Array) records requested SFX names for tests.

## Spec corrections and porting notes

- **Godot's JSON / `String.to_float` is not correctly rounded** (values can be 1–2 ulp off the
  JS double). Game data is unaffected in practice, but bit-exact comparisons must not go through
  JSON numbers: `test_vectors.json` carries the IEEE-754 bits of each reference double.
- §5.10: pickups don't spawn with a uniform 10–46 wu/s speed; JS draws two independent speeds,
  `vx = cos(a)·rand(10,46)`, `vy = sin(a)·rand(10,46)` (ported as in JS).
- §5.12: the JS grid key `cx*73856093 ^ cy*19349663` collides for symmetric cells around the
  origin ((a,b) and (-a,-b) with |a|,|b| ≤ 4 and the same parity), and `queryCircle` then returns
  the enemies of that bucket **twice** (double heal / double aura hit near the spawn point; away
  from the origin only 0.06 % of 5×5 windows collide). The port's grid has no collisions (dense
  window around the camera with per-cell linked lists + an overflow list; same order as JS
  otherwise), and the JS reference vectors place their groups away from the origin.
- §2.7 / §11.8: damage-number `vy *= 0.94` per frame is ported as `pow(0.94, dt*60)` (identical
  at 60 FPS, frame-rate independent at 120 Hz).
- §11.3 lists `Data` as an autoload; it is a static class here (works in `--script` tests).
- Appendix A ran unchanged on the current tree; `tools/export_godot.js` adds `test_vectors.json`
  (JS-computed reference values, including terrain dumps produced by the unmodified `world.js`).
- Godot gotchas hit while porting: `Control.set_anchors_preset()` keeps the current rect — use
  `set_anchors_and_offsets_preset()` for code-built full-screen controls; a static `has_meta()`
  clashes with `Object.has_meta` (renamed `has_sprite_meta`); blocking on one threaded load
  (`load_threaded_get`) right after queueing ~100 others printed *"Bug in ResourceLoader logic"*
  in 4.7.1, so the partner's sheets are loaded synchronously (`Sprites.load_now`) before the
  spawner queues the cast's threaded preloads.

### Phase 2 notes

- §5.6: the initial boss mode is not random: JS starts in `far` mode iff the boss behavior is
  `ranged` (then alternates); `farLike` only picks which mode lasts 7–9 s instead of 4–5 s.
- §4.6 mines trigger on `queryCircle(x, y, 14)`, i.e. an enemy's *circle* within 14 wu (feet
  distance ≤ 14 + e.r), not its feet.
- §5.13: the LOS throttle (200 ms) uses run time instead of `performance.now()` (identical while
  playing, deterministic in headless runs). The BFS is spread over ≤ 3 frames (1,100 cells per
  frame, double buffered) and waits for its terrain chunks (worker threads in game): the field is
  at most ~50 ms older than in JS; `Pathing.build()` gives the JS result in one call (tested).
- Shot and telegraph angles use 64-bit directions (`Enemy.dir_to`): `U.norm` returns a float32
  `Vector2`, which moved angles by ~5e-9 rad against the JS vectors.
- Focus Sash keeps the JS wall-clock 60 s (`Time.get_ticks_msec`), so pausing counts.
- `Player.last_patch` is a `WeakRef` (the patch refers back to its owner: a strong reference
  leaked both objects at exit).
- Debug runs: `Player.god` makes `hurt()` a no-op (telegraphs reset i-frames, so `invuln` alone
  is not enough for `--god`); `--autoplay` no longer pauses when the window loses focus.

### Phase 4 notes

- `toLocaleString('es')` only groups thousands from 5 digits (4331, 12.345): the port matches it
  (`UIKit.num_es`, mission texts).
- JS `Array.sort` is stable, Godot's `sort_custom` is not: `Gacha.featured` breaks BST ties by
  G.DEX order explicitly (the JS-vector test failed without it).
- Godot's JSON parser returns every number as a float: `Save.parse` turns integral values back into
  ints (keys stay strings), so exports print `716`, not `716.0`, and `created` (the mission seed)
  stays exact. `JSON.new().parse()` is used so invalid input doesn't log engine errors.
- Hand-edited saves: where JS would misbehave on a wrong container type (e.g. `owned` as an array)
  `migrate` resets that field to its default; an imported partner that is not a valid dex becomes
  `null` (→ personality test). Everything else follows `sanitize` exactly (verified on a legacy save).
- The missions reset countdown uses Madrid time (JS approximates it with the browser's local time).
- §11.6 suggested one atlas per Pokémon with normal + shiny together; they are packed separately
  (enemies never need shiny pages) plus per-generation Idle preview strips for the UI grids.
- GDScript 4.7: `trait` is a reserved word; `round()` returns a Variant (use `roundf` with `:=`).

### Phase 3a notes

- §7.7 / §11.4: the dirt lattice is a `Float32Array` in JS: its values are rounded to float32
  before the per-pixel bilinear step; the port must do the same (`PackedFloat32Array`) to be
  pixel-exact. §11.4 estimated 100–400 ms per chunk in GDScript; measured 33 ms (inlined hash,
  lazy hashes for pixels that are overwritten, per-cell noise tables).
- §7.1 / §11.4: chunk images are FIFO(48) in JS because they are baked synchronously; with async
  painting the port keeps 48 textures LRU (a still-visible chunk is never evicted and repainted).
  Palette slots + shader instead of one RGBA image per biome (identical pixels, no repaint on a
  biome change or during the crossfade).
- §7.5 `projectileBlock` returns `'wall'`, the prop or null; `projectile_block()` keeps its String
  API (`"wall"`, `"prop"`, `""`) and `projectile_block_any()` returns the JS value.
- `destroyProp` uses `splice(indexOf(p), 1)`: for a stale prop object (its chunk evicted and
  regenerated) `indexOf` is -1 and JS removes the chunk's *last* prop; the port removes the prop on
  that tile.
- §7.4: flat props (spring, trap) don't crossfade (JS returns before the fade code). JS
  `drawLiquid` / `visibleProps` generate missing chunks while drawing; the port only draws cached
  chunks (generation happens on workers).
- `Math.hypot` → `sqrt(x² + y²)` everywhere (terrain, arena, discs, liquid inner corners): equal at
  every threshold used (tested through the chunk, sprite and placement hashes).

### Phase 3b notes

- §7.8 says altars/springs/chests/traps work by proximity only; the task brief mentioned
  "keys/costs": JS has none, so none were added.
- JS `Events.say(text, secs)` ignores the colour argument its callers pass: event banners use the
  normal gold banner (as in JS); only the HUD countdown is drawn in the type colour.
- Thieves and lost Pokémon spawn on an ellipse (`y × 0.8`, mark `y × 0.85`), so "230–300 wu"
  (§7.9) is the horizontal range; the rift is `y × 0.85` too.
- The rift legendary and its arena are chosen with the JS draw order (pick, tx, ty, shiny only for
  species with a shiny sheet, type only when not forced), so a recorded `Math.random` stream gives
  the same legendary, arena and position (tested).
- Rift portal motes: JS spawns one with 30 % per drawn frame; the port uses `dt × 18` (same at
  60 FPS, frame-rate independent).
- `Interact` keeps the JS 720 wu scan exactly but reads candidates from a small cache (refreshed
  every 0.25 s, on 60 wu of movement or when the world forgets chunks) and **only from chunks that
  are already generated**: `specials_near` generates missing chunks synchronously (~5 ms each in
  GDScript), which made entering a rift arena a 100–160 ms frame. Ungenerated chunks can't hold
  a used altar or a drained spring, so behaviour is unchanged.
- Arena coordinates are ~160k–256k wu: GDScript positions are 64-bit, terrain noise comes from
  integer tiles (Phase 3a), but `draw_colored_polygon` at those coordinates failed to triangulate
  (float32): the XP gem diamond is now drawn with a local transform (`world_view._draw_pickups`).
- `World.setArena(null)` is never called in JS after a rift; the port keeps the arena set too.
- After a rift, the bond picker opens while the lavender flash is still full (JS: the flash only
  fades while playing, under the DOM picker) — same in the port.

## Performance (desktop, Apple M4 Max)

At the 64-enemy cap (64–80 alive with summons) with 4 L5 kinds, enemy shots, telegraphs and
fields active (`--start-t=300`): headless `Sim.update` avg **1.66 ms**, max 6.2 ms (the max
includes synchronous chunk generation, ~2.5 ms per chunk, which runs on worker threads in game);
in the windowed game (1280×720, 120 Hz vsync) sim avg 1.1–2.0 ms and the world layer's draw
recording (`world_view._draw`, now in the `[perf]` line as `draw_avg/draw_max`) avg 0.7–1.9 ms,
spikes 6–14 ms from the Phase 1 ground chunk bake. Breakdown at ~77 enemies: per-enemy AI 0.45 ms,
separation 0.6 ms, flow-field `dirFor` 0.05 ms, BFS slice 0.8 ms on rebuild frames, one
`query_circle(r 60)` ≈ 13 µs. The windowed frame held 120 FPS until the machine got busy (load
6.5); CPU sim + draw ≈ 3–4 ms on desktop is likely ~10 ms on a high-end phone, i.e. **over the
8.3 ms budget at 120 Hz** at the cap: profile on the device; candidates are the enemy loop
(fewer Dictionary/Variant accesses, cached `def` fields), separation, ground baking on a worker
(Phase 3) and batching the FX rects.

Phase 3b (measured while the machine was heavily loaded, load average 90–200, so absolute numbers
are inflated ~2×): windowed `--autoplay --god --start-t=300 --event=horde` — during the horde at the
64-enemy cap `[perf]` sim_avg 2.4–3.2 ms, draw_avg 2.3–2.6 ms (same as without the event: the horde
only changes the spawn bag); in a rift arena fight (legendary alone, enemy shots, telegraphs)
sim_avg 0.4–0.5 ms, draw_avg 0.4–0.5 ms. Per-system headless cost at the cap: `Interact.update`
0.05 ms (cached candidates; 0.17 ms scanning chunks every frame), `Rift.update` / `Events.update`
< 0.01 ms. Entering an arena: one frame of ~57 ms windowed (was 150 ms before the interactable scan
stopped generating chunks synchronously); headless the first arena frame is 2–3 ms and the BFS then
generates the arena chunks over the next frames (workers in game).

## Hot paths (120 FPS pass)

Target: the vivo X200 Pro mini (Dimensity 9400, 2640×1216 at 120 Hz), i.e. well under 8.3 ms per
frame for sim + draw recording + rendering in the worst normal case. Everything below keeps the
simulation **bit-exact**: the test suite passes and `tests/bench.gd --trace` checksums (every
60 frames, 6 scenarios: the cap + horde + boss, the cave with chain/cone/boomerang/orbit, an early
forest run, a rift arena, thief + lost Pokémon + golden hour, and one with the draw pass running)
are identical to the build before this pass.

**Benchmarks**
- `tests/bench.gd` (headless, deterministic): `-- [--frames=1800] [--warm=600] [--seed=7] [--no-draw]
  [--trace] [--json] [scenario flags]`. Default scenario: `--start-t=600` (cap, late tiers), four L5
  evolved moves fused by 3 bonds (projectiles + nova + meteors + mines all casting), a horde at 605 s,
  a boss at 625 s, god mode, bot input, dt = 1/60. Prints mean / median / p95 / max per system and
  the state checksum; the world view and the damage numbers record their draw commands every frame
  (headless = GDScript recording cost only). To compare two builds, run both copies alternately
  with `--json` (the machine load cancels out) and compare the checksums.
- `--bench=<frames>` (main.gd, debug builds, `debug/bench_draw.gd`), windowed:
  `godot --path godot --fixed-fps 60 --disable-vsync --resolution 1320x608 -- --autoplay --god --bench=900
  --bench-warm=600 --bench-sync --start-t=600 --learn=ember,heat-wave,rock-slide,spikes --move-lvl=5
  --evolve --bonds=3 --boss-at=625 --event=horde --event-at=605 --seed=7` prints sim, world-view draw
  recording per pass, damage numbers, the RenderingServer's CPU render time, draw calls and primitives,
  then quits. `--bench-sync` seeds the run and generates terrain / paints the ground synchronously, so
  two builds render the same frames; `--bench-shot=<png>` saves the last frame, `--bench-hide=HUD,...`
  hides nodes (draw calls per layer).
- `SimProf` (`core/sim_prof.gd`): per-system laps in `Sim.update`, `EnemyMgr.update`,
  `world_view._draw` and the damage numbers; on in debug builds, which add `[perf] sim ...` and
  `[perf] draw ...` (ms/frame per system) to the 5 s `[perf]` lines (logcat on the phone).

**Before → after** (M4 Max; headless: median of 5 interleaved runs of the default scenario, mean
ms/frame over 1,800 frames; windowed: 2 + 2 `--bench-sync` runs at 1320×608, 900 frames)

| headless system | before | after | | windowed | before | after |
|---|---|---|---|---|---|---|
| enemy AI (`e_ai`) | 0.594 | 0.472 (−20%) | | sim | 2.50 | 1.71 (−32%) |
| separation (`e_sep`) | 0.587 | 0.405 (−31%) | | world draw recording | 2.39 | 1.05 (−56%), max 6.4 → 1.4 |
| FX update | 0.387 | 0.169 (−56%) | | damage numbers | 0.19 | 0.19 |
| projectile hits (`resolve`) | 0.141 | 0.113 (−20%) | | RenderingServer CPU | 2.53 | 1.06 (−58%) |
| fields | 0.128 | 0.102 (−20%) | | draw calls | 581 | 345 (−41%) |
| pathing (p95: BFS frames) | 0.073 (0.64) | 0.061 (0.56) | | primitives | 19.8k | 7.7k |
| cull / laggards | 0.054 | 0.031 (−43%) | | **CPU per frame** | **7.6** | **4.0 (−47%)** |
| **Sim.update total** | **2.225** | **1.626 (−27%)** | | | | |
| draw: entities (list + draw) | 0.751 | 0.513 (−32%) | | | | |
| draw: FX | 0.441 | 0.206 (−53%) | | | | |
| draw: ground fields | 0.152 | 0.037 (−76%) | | | | |
| **draw recording total** | **1.633** | **1.028 (−37%)** | | | | |

What changed:
- **Enemies** (`sim/enemy_mgr.gd`, `sim/enemy.gd`): separation reads packed copies of the grid
  entries' positions / radii / alive flags and writes each moved enemy back (same visiting order and
  float expressions as the JS loop); the grid stores each enemy's entry index; laggard-loop
  invariants hoisted; behavior codes cached by a `behavior` setter; `U.norm` / `U.dist` /
  `Sprites.dir_from_angle` inlined with the same expressions (the direction keeps its float32 Vector2).
- **Pathing** (`sim/pathing.gd`): one int array holds walkability and distance (`BLOCK` / `UNSEEN` /
  steps, filled by `WorldMap.fill_walk_codes`), so each BFS neighbour is one read; `dir_for` and
  `clear_line` unrolled.
- **World queries** (`sim/world_map.gd`): `collide` and `projectile_block_any` read the chunk arrays
  directly when the box is inside one chunk; `props_in_circle` scans a packed per-chunk list of
  destructible props.
- **FX** (`sim/fx.gd`): particles are packed arrays (no object per particle); the default drag's
  `pow` once per frame.
- **Draw** (`render/world_view.gd`, `render/draw_util.gd`, `core/pmd_animator.gd`): the animator
  caches its READY sheet and frame geometry (no key strings / dictionary lookups per sprite); y-sort
  by int64 keys (no lambda sort; equal y keep insertion order); colours as constants (no
  `Color.html` per frame); cached shadow radius, VFX textures (no key strings), outline / dash point
  caches; dashes as one `draw_multiline`; damage numbers (`render/overlay.gd`) with cached strings /
  widths, outlines and fills batched with flushes that keep the exact stroke-then-fill result.
- **Draw calls**: ellipses / gems / boxes moved from polygons to one shared shapes texture, and the
  world view draws with a small canvas shader (`DrawUtil.flash_material`): a Pokémon's or prop's
  shadow, status rings and HP bar are shader shapes on the sprite's own atlas page (one batch per
  Pokémon instead of 2–4), and the hit flash is the sprite texture with a marker modulate — the white
  silhouette textures are gone, and with them a GPU read-back + image build on the first hit of every
  sheet (1–4 ms hitches on desktop, far more on a phone). Screenshots of identical `--bench-sync`
  frames differ only by sub-pixel ellipse edges (and the real-time grass sway).

Phone estimate: CPU per frame at the cap went from ~7.6 to ~4.0 ms on the M4 Max (sim 1.7 + draw
recording 1.2 + RenderingServer 1.1). With the Dimensity 9400 at ~1.5–2× the M4 Max per core that is
~6–8 ms after (11–15 ms before): inside 8.3 ms, but without much margin — read `[perf] sim` /
`[perf] draw` on the device. Remaining hotspots: per-enemy AI (~0.45 ms: flow-field steps and
line-of-sight sampling, wall collision), separation (~0.35 ms, dominated by `collide` after pushes),
RenderingServer time (~345 draw calls: ~1 per Pokémon / prop and, in dense fights, ~2 per group of
overlapping damage numbers — drawing every outline before every fill would save ~60–100 calls but
change how overlapping numbers look), BFS rebuild frames (p95 ~0.5 ms). Further options:
`rendering/driver/threads/thread_model` = separate (render thread; to try on the device), damage
numbers from a pre-outlined bitmap atlas, a struct-of-arrays enemy store.

## Next step: Phase 3 (world completeness)

(Phase 3a did (1), (2), weather and the liquids of later biomes; Phase 3b the events, rifts and
bonds: see their sections. What remains is the device check below.)

Recommended order: (1) props + destructibles + `World.walkable` with solid props (pathing,
projectile cover, attacks damaging props — the `damageProp` call sites are marked in combat.js);
(2) the threaded ground painter (the chunk job machinery in `world_map.gd` can host it);
(3) events (hordes, golden hour, thieves — the `thief` branch of `enemy.js update` — lost
Pokémon), weather (damage/speed multipliers in `Combat._hit`, `Player.hurt`, enemy speed),
liquids of later biomes; (4) rifts + bonds UI (multi-move slots already tick independently).
Device check first: export to the phone and read the `[perf]` line at the cap.
