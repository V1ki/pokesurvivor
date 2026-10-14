# PokéSurvivor → Godot 4.7 (GDScript) — Porting Specification

> Source of truth: the JS code in this repo (vanilla JS + Canvas 2D, comments in Spanish).
> `GDD.md` describes intent and is partly outdated; where code and GDD disagree, **code wins** and the
> discrepancy is flagged here. All `file:line` references are relative to the repo root
> (the repository root) and were taken from the working tree on 2026-10-13.
> Online features (Firebase accounts/cloud save, friends, ranking, co-op over WebRTC) are **out of scope**;
> they are only noted where they touch gameplay code paths you must strip.

Conventions used in this document:

- **wu** = world unit (the JS world coordinate unit). **art px** = one pixel of sprite/tile art. `PX = 2` wu per art px.
- `dt` is in seconds. Angles are radians, measured with `atan2(dy, dx)` in **y-down** screen space (same as Godot 2D).
- "Spanish UI strings" are the keys of the English dictionary (`js/data/lang-en.js`); see §9.6.
- `G.X` = the global namespace object the JS modules attach to (`window.G`, `js/core/util.js:2`).

## Table of contents

1. [Architecture of the JS game](#1-architecture-of-the-js-game)
2. [Sprites, tiles, VFX and icons](#2-sprites-tiles-vfx-and-icons)
3. [Player](#3-player)
4. [Moves / weapons](#4-moves--weapons)
5. [Enemies, spawning, drops, shinies](#5-enemies-spawning-drops-shinies)
6. [Level-up cards](#6-level-up-cards)
7. [World: biomes, terrain, interactables, events, weather, rifts, hazards](#7-world)
8. [Meta-progression (outside runs)](#8-meta-progression-outside-runs)
9. [UI screens, HUD, input, audio, fonts, i18n](#9-ui-hud-input-audio)
10. [Data export plan](#10-data-export-plan)
11. [Godot 4.7 architecture & phased port plan](#11-godot-47-architecture--phased-port-plan)
12. [Appendix: top gotchas](#12-appendix-top-gotchas)
13. [Appendix A: data exporter sketch](#appendix-a--toolsexport_godotjs-sketch-tested-against-the-current-tree)

---

## 1. Architecture of the JS game

### 1.1 Module system and boot

- No bundler, no ES modules. `dev.html:543-617` loads ~70 `<script defer>` files **in order**; each attaches an object to the
  global `G` (`window.G = window.G || {}` in `js/core/util.js:2`). Most modules are IIFEs returning a public API
  (`G.Combat = (() => { ... return {...}; })()`); `G.Player` is an ES class; enemies are a class private to `G.EnemyMgr`.
- `index.html` + `js/app.min.js` are **generated** by `tools/build.js` from `dev.html` (terser bundle). Never port from `app.min.js`.
- Boot: `js/main.js:43` `boot()` → checks every required namespace exists (`main.js:5-8`) → waits for the pixel font →
  `G.Flow.boot()` (`js/game.js:799`): init all UIs, start menu music, `G.Game.init()` (canvas, resize, touch, backdrop,
  `requestAnimationFrame(loop)`), then `G.DB.ready()` → "tap to start" screen (audio unlock) → login (or restored session)
  → personality test if `save.partner` is empty (`game.js:838`) → main menu.

Load order (relevant subset, `dev.html:543-617`): `util, i18n, lang-en, settings, music, pokedex, lang-zh, sprites-meta,
firebase-config, db, audio, input, touch, sprites, camera, moves, types, starters, enemies, upgrades, items, missions,
achievements, funding, changelog, tiles, world, vfx, fx, projectile, enemy, pickup, player, combat, spawner, levelup,
gacha, interact, rift, events, weather, pathing, progress, hazards, net/*, icons, ui, hud, login, test, menu, slots,
gacha-ui, run-ui, social-ui, ranking-ui, goals-ui, settings-ui, support-ui, news-ui, updater, game, main`.

### 1.2 Module map

| Namespace | File | Responsibility |
|---|---|---|
| `G.U`, `G.LIFT` | `js/core/util.js` | math helpers, deterministic 2D hash, type colors/names (Spanish) |
| `G.Settings` | `js/core/settings.js` | per-device settings + auto quality (FPS-driven) |
| `G.DB` | `js/core/db.js` | save data (`newSave()`), accounts, localStorage + Firebase sync |
| `G.Audio` | `js/core/audio.js` + `js/data/music.js` | Web Audio synth: music sequencer + SFX |
| `G.Input` / `G.Touch` | `js/core/input.js` / `js/core/touch.js` | keyboard / floating joystick |
| `G.Sprites` | `js/core/sprites.js` | PMD sprite-sheet loader + `Animator` |
| `G.Camera` | `js/core/camera.js` | constant world width view, follow, shake |
| `G.Moves`, `G.Types`, `G.STARTERS`, `G.Enemies`, `G.Upgrades`, `G.Items`, `G.DEX`, `G.SPRITE_META` | `js/data/*` | static data |
| `G.Tiles`, `G.World` | `js/world/tiles.js`, `js/world/world.js` | procedural tile art, chunked infinite terrain, props, collisions |
| `G.VFX`, `G.FX` | `js/entities/vfx.js`, `js/entities/fx.js` | procedural pixel-art attack sprites; particles/rings/slashes/beams/damage numbers |
| `G.Projectiles` | `js/entities/projectile.js` | single list for player shots, enemy shots and orbit orbs |
| `G.EnemyMgr` | `js/entities/enemy.js` | enemy class, AI, bosses, spatial grid |
| `G.Pickups` | `js/entities/pickup.js` | XP gems, coins, heal, magnet, bomb, tickets, items |
| `G.Player` | `js/entities/player.js` | the controlled Pokémon |
| `G.Combat` | `js/systems/combat.js` | runs the active move(s), all hit tests, persistent "fields" (mines, meteors, turrets, trail patches) |
| `G.Spawner` | `js/systems/spawner.js` | waves, bosses, banner messages (`G.Spawner.say`) |
| `G.LevelUp` | `js/systems/levelup.js` | level-up card generation |
| `G.Interact`, `G.Rift`, `G.Events`, `G.Weather`, `G.Hazards`, `G.Path` | `js/systems/*` | altars/springs/locked chests, legendary rifts, mid-run events, weather, traps, BFS flow field |
| `G.Progress`, `G.Gacha` | `js/systems/progress.js`, `gacha.js` | missions/achievements, gacha rolls |
| `G.HUD`, `G.UI`, `G.Icons`, `G.*UI` | `js/ui/*` | canvas HUD, DOM screens, procedural icons |
| `G.Game`, `G.Flow` | `js/game.js` | run lifecycle, main loop, render, menu backdrop, screen flow |
| `G.Social`, `G.Net`, `G.Coop`, `G.Ranking` | `js/net/*` | **online — exclude** |

### 1.3 Game states (`G.Game.state`, `js/game.js:19`)

| State | Meaning | Simulation | Entered by | Left by |
|---|---|---|---|---|
| `'ui'` | menus; live world backdrop | `Backdrop.render` only | boot, `toUI()` (`game.js:792`) | `startRun()` |
| `'playing'` | run in progress | full `update(dt)` | `startRun`, closing a card/pause/choice | level-up, pause, choice, death→`'over'` |
| `'levelup'` | 3 cards shown (DOM `scr-levelup`) | frozen; FX + player anim at `dt*0.25` | `maybeLevelUp()` (`game.js:319`) | card picked (`game.js:333-337`) |
| `'paused'` | pause menu (`scr-pause`) | frozen (same slow-mo FX) | Esc/P (`togglePause`, `game.js:73`), tab hidden, portrait rotation | Esc/P again, "continue" |
| `'choice'` | bond (fusion) picker or held-item swap | frozen | `offerBond()` (`game.js:349`), `offerItem()` (`game.js:377`) | choice made |
| `'held'` | co-op only (someone else choosing) | frozen | co-op | — (ignore) |
| `'over'` | results screen | nothing | `endRun()` (`game.js:270`) | results closed → `G.Flow.afterRun()` → `'ui'` |

Pending level-ups are counted in `pendingLevels`; only one card screen opens per frame and only while `state==='playing'`
and the player is alive (`game.js:319-338`). Multiple level-ups from one gem queue up and open back-to-back.

### 1.4 Main loop and timestep (`js/game.js:504-597`)

- `requestAnimationFrame` **variable timestep**. `real = (ts - last)/1000`; `dt = min(1/30, real) * speedK`
  (`game.js:521-522`). So the sim slows down below 30 FPS (no catch-up, no fixed step). `speedK` is a debug slow-mo (1).
- `G.Settings.sample(real)` (auto quality) only while playing (`game.js:524`).
- Non-playing, non-UI states still tick `G.FX.update(dt*0.25)` and `pl.anim.update(dt*0.25)` (visual slow-mo, `game.js:532`).
- The next frame is requested **before** running the frame; exceptions are caught; after 180 consecutive failing frames
  the run is ended and saved (`game.js:504-518`). (Port: optional; Godot doesn't kill the loop on script errors.)
- Death: when `pl.dead` (solo, not in rift arena) the game keeps updating the player, enemies at `dt*0.3` and FX, and the
  camera, for **1.3 s** (so the Faint anim plays), then `endRun(true)` (`game.js:547-555`).

**Update order while playing** (`game.js:556-597`) — keep this order, several systems read data produced earlier in the frame:

1. `time += dt` (run clock, seconds).
2. Biome rotation: `b = floor(time/240)`; if changed and not in a rift arena → `World.setBiome(b)`, sfx `biome`,
   banner `'— <biome name> —'` for 3 s, white ring of radius `Camera.outerRadius()` (`game.js:558-565`).
3. `pl.update(dt)` (movement, collisions, liquids, buffs, **target selection**).
4. `Camera.follow(pl.x, pl.y, dt)`; `World.update(dt, Camera)` (chunk streaming/baking).
5. `G.Path.update(dt, players)` (BFS flow field) and `G.Spawner.update(dt, players, time)`.
6. `G.EnemyMgr.update(dt, players)`; `G.EnemyMgr.rebuildGrid()` (spatial hash, cell 52 wu, `enemy.js:740`).
7. `G.Combat.tick(dt, pl, time)` (cooldowns → cast active move group).
8. `G.Projectiles.update(dt, pl, enemies)` (move, homing, boomerang return, off-screen cull).
9. `G.Combat.resolve(dt, pl, time)` (projectile hits, enemy-shot hits, contact damage).
10. `G.Combat.updateFields(dt)` (mines, meteors, turrets, trail patches).
11. `G.Pickups.update(dt, players, onCollect)`.
12. `G.Hazards.update`, `G.Interact.update`, `G.Rift.update`, `G.Events.update`, `G.Weather.update`, `G.FX.update`.
13. Music selection: `'rift'` in arena, else `'boss'` if a boss is alive, else `G.BIOME_MUSIC[biome % 3]`
    (`['forest','cave','volcano']`, `js/data/music.js:128`) (`game.js:593`).
14. `maybeLevelUp()`; `offerBond(true)` if the player holds unused bonds (`game.js:594-595`).

### 1.5 Coordinates, units, camera

- **(x, y) of every entity is its FEET** (ground contact point). All collisions happen on the ground plane. Projectiles and
  effects live on the ground plane too but are **drawn `G.LIFT = 18` wu higher** with a shadow ellipse at the true position
  (`util.js:5`, `projectile.js:110-135`).
- `G.Sprites.PX = 2` wu per art pixel (`sprites.js:14`). Tiles are `G.Tiles.T = 16` art px = **`TS = 32` wu**
  (`tiles.js:10`, `world.js:32`). Chunks are 16×16 tiles (= 512 wu, README).
- World is **infinite** and procedurally generated from a seed (`World.reset(seed)`, run seed = `floor(random()*1e6)`,
  menu backdrop seed `4242`) — see §7.
- Camera (`js/core/camera.js`):
  - `VIEW_W = 768` wu of world are always visible horizontally; `MIN_VIEW_H = 420` wu guaranteed vertically on very wide
    screens: `scale = min(cssW/768, cssH/420)`; visible world `w = cssW/scale`, `h = cssH/scale` (`camera.js:19-24`).
  - Follow: exponential damping `x = damp(x, tx, 9, dt)` where `damp(a,b,rate,dt) = b + (a-b)*exp(-rate*dt)` (`util.js:29`).
  - Shake: `kick(a)`: `shake = min(1.2, shake + a)` (×0.25 if setting `calm`); decays `2.4/s`; offset is uniform random in
    `±shake*7` wu on both axes each frame (`camera.js:26-40`).
  - Pixel snapping: the world translation is rounded to whole *physical* pixels (`camera.js:43-49`) to avoid seams between
    chunk images and sprite jitter.
  - `sees(x, y, pad=60)` = inside view rect expanded by `pad`. `outerRadius() = hypot(w,h)/2 + 40` — used for spawn ring,
    bomb radius, biome-change ring.
- Canvas: backing store = CSS size × `dpr`, with **`dpr = min(1.5, devicePixelRatio)`** (`game.js:46`).
  `imageSmoothingEnabled = false` everywhere. Render transform = `setTransform(dpr)` then `scale(Camera.scale)` then
  camera translate (`game.js:644-650`). HUD is drawn in CSS-pixel screen space after restoring the transform.

**Godot mapping**: Camera2D with `zoom = Vector2(scale, scale)` where `scale = min(viewport_w/768, viewport_h/420)`
(recompute on `size_changed`); set `rendering/2d/snap/snap_2d_transforms_to_pixel = true` and
`snap_2d_vertices_to_pixel = true`; default canvas texture filter **Nearest**. Keep world units identical (1 Godot px = 1 wu)
so every number in this spec ports verbatim.

### 1.6 Draw order (`js/game.js:619-686`)

World space (camera transform applied):

1. `World.drawGround` (baked chunk images) → `World.drawLiquid` (animated water/lava overlay).
2. `Hazards.draw` (traps) → `Combat.drawGroundFields` (trail patches, mines, meteor shadows, turret shadows) → `Pickups.draw`.
3. **Y-sorted pass** (`game.js:627-640`): visible props (flat props such as springs/traps get `y-4000` so they are always
   below), enemies (`EnemyMgr.drawables(cam)`), player(s), the rift portal, event drawables (lost Pokémon, goal marker…);
   stable sort by feet `y` ascending; each draws its own shadow + sprite + overlays.
4. `Projectiles.draw` (all shadows, then red ground rings under enemy shots, then sprites at `y-18`).
5. `Combat.drawAirFields` (falling meteors, floating turrets).
6. `FX.draw` (beams, slashes, rings, square particles, VFX sprites, damage numbers).

Screen space: 7. `Weather.draw` (tint + pixel particles) → 8. `World.drawVignette` → 9. fog vignette
(radial gradient `rgba(200,205,220, 0.45*fog)` from `0.32*min(w,h)` to `0.62*max(w,h)`, `game.js:660-667`) →
10. `HUD.draw` → 11. `Touch.draw` (joystick) → 12. FPS text (bottom-right, 11px, green ≥50 / yellow ≥30 / red) →
13. full-screen flash (`G.Game.flash(col, dur)`, alpha `min(1, t/dur*1.4)`, ×0.3 if `calm`).

### 1.7 Menu backdrop (`js/game.js:694-779`)

While in `'ui'`, the real world (seed 4242, biome cycles every 30 s through 0..2) is rendered with 20 wandering Pokémon
(`CAST = [1,4,7,25,133,52,39,35,16,43,60,69,74,92,129,147,113,143,54,79]`). Each wanderer every 1–3.5 s: 55% walk in a
random direction at 25–55 wu/s, otherwise stand; 15% chance of playing Attack/Shoot/Charge. Camera drifts
`(cos(t*0.05)*14, sin(t*0.037)*10)` wu/s. Wanderers leaving the view (pad 120) respawn inside. Port as an optional
`MenuBackdrop` scene reusing the world renderer.

### 1.8 Run lifecycle (`js/game.js:88-139`, `270-315`)

`startRun()`:

1. `mon = G.DEX_BY[save.partner]`; `perks = G.Upgrades.perks(G.DB.upgradesOf(mon.dex))` (per-Pokémon permanent upgrades, §8).
2. Clear FX, projectiles, fields, enemies, pickups, spawner, rift, events, weather, path, hazards.
3. `World.reset(seed)`; `World.setBiome(0, true)`; `time = 0`.
4. `pl = new G.Player(mon, perks, save.partnerShiny && ownsShiny(dex))`.
5. Slot bindings ("Atajos"): `save.pbind[dex] = [moveIdForSlot1, ...]` → `pl.bind[id] = slotIndex`.
6. `pl.addMove(G.startMoveOf(dex))` — starter-specific move (`js/data/starters.js:43`) or by first type (`moves.js:469-480`).
7. "Veto": `pl.banned = new Set(save.pban[dex].slice(0, perks.bans))`.
8. "Repertorio" (`perks.startMoves >= 2`): add one random non-buff move from the pool that isn't banned; `setActive(0)`.
9. Camera snaps to player; preload partner sheets; music `forest`.

`endRun(dead)` coin formula (`game.js:281-288`):
`coins = round((floor(time/5) + floor(kills*0.25) + bosses*80 + coinsPickedUp) * pl.coinMul)`.
Then: `save.coins += coins`; tickets banked; `stats.runs++`, `totalKills`, `bestTime`, `bestLevel`, `coinsEarned`;
`Progress.event('runEnd', {time, level, coins, types, group})`; `Progress.checkAch()`; commit; show results.
Tickets (`pl.t1`, `pl.t10`) and caught shinies are **written to the save immediately when collected** (`bankTickets`,
`game.js:172-181`; `onShinyCaught`, `game.js:258-268`) so a crash doesn't lose them.

---

## 2. Sprites, tiles, VFX and icons

### 2.1 Pokémon sprite sheets (SpriteCollab / PMD format)

- Directory: `assets/pokemon/{dex}/{Anim}.png` (normal) and `assets/pokemon/{dex}/s/{Anim}.png` (shiny). 966 dex folders,
  95 MB total. PNGs are **8-bit indexed (palette)**, e.g. `25/Walk.png` = 128×320.
- Exactly 7 animations per Pokémon: `Idle, Walk, Attack, Shoot, Charge, Hurt, Faint` (`sprites.js:106`). All 966 entries
  have all 7 in the metadata.
- Sheet layout: **columns = frames, rows = 8 directions**. Row index → direction:
  `0 Down · 1 DownRight · 2 Right · 3 UpRight · 4 Up · 5 UpLeft · 6 Left · 7 DownLeft` (`sprites.js:5-6`).
  One animation in the whole set has `r = 1` (single row); the code clamps `row = min(dir, r-1)` (`sprites.js:244`).
  **No horizontal flipping is ever used** — all 8 directions are drawn art.
- Metadata: `G.SPRITE_META[dex]` in `js/data/sprites-meta.js` (generated by `tools/fetch_sprites.py` from SpriteCollab
  `AnimData.xml`). Per Pokémon:

  | Field | Meaning |
  |---|---|
  | `s` | PMD ShadowSize 0/1/2 (counts: 84/693/189) → shadow ellipse radius |
  | `a` | `{ AnimName: animMeta }` |
  | `sh` | `1` if a shiny folder exists (958 of 966) |
  | `sa` | shiny-only geometry overrides `{ AnimName: animMeta }` (30 Pokémon) |
  | `sm` | animations missing for the shiny (currently unused: 0 entries) |
  | `hv` | `1` if the Pokémon visually hovers (140 Pokémon; `tools/hover_flags.py`) → enemies with `hv` fly over terrain |

  Per animation (`animMeta`): `w, h` frame size in art px (max seen 176×160), `n` frame count, `r` rows (8),
  `d` array of per-frame durations in **1/60 s ticks**, `ax, ay` **ground anchor** inside the frame (art px, usually `.5`
  values, e.g. `15.5, 23.5`), derived from the `-Shadow.png` so that changing animation never makes the sprite jump.

- Lookup rules (`sprites.js:47-66`): `animName(dex, anim, shiny)` falls back to `Idle`, then `Walk`, if an animation is
  missing. Shiny geometry: `sa[name]` if present else `a[name]`.

### 2.2 How a Pokémon is drawn (`Animator`, `sprites.js:158-259`)

- Scale `k = PX * animator.scale` (= 2 for normal Pokémon; bosses use larger `scale` — §5).
- Source rect: `sx = min(frame, n-1) * w`, `sy = min(dir, r-1) * h`, size `w×h`.
- Destination: `dx = round(x - ax*k)`, `dy = round(y - ay*k)`, size `w*k × h*k` → the anchor pixel lands exactly on the feet.
  Godot: `draw_texture_rect_region(tex, Rect2(round(x - ax*k), round(y - ay*k), w*k, h*k), Rect2(sx, sy, w, h), modulate)`.
- Frame timing: `t += dt*60*speed`; advance while `t >= d[frame]`. `loop(anim, speed)` sets the background anim (Idle/Walk)
  without restarting it if already playing; `play(anim, {speed, hold})` plays once over the background, then returns to it
  (`hold:true` freezes on the last frame — used for `Faint`). `busy()` = one-shot still playing. `progress()` = 0..1.
- Direction from angle: `dir = ((round((π/2 - a)/(π/4)) % 8) + 8) % 8` with `a = atan2(dy, dx)` (`sprites.js:122-124`).
  Works unchanged with Godot's `Vector2.angle()`.
- Hit flash: a **white silhouette** of the whole sheet is generated once per image (`source-in` fill, `sprites.js:28-41`).
  Enemies draw *only* the white sheet while `flash > 0` (full white); the player draws the normal frame and then the white
  frame at 55% alpha (`softFlash`). Godot: either pre-generate a white copy per sheet (`Image` → set RGB=1 where A>0) or use
  a `canvas_item` shader with a `flash` uniform (requires one CanvasItem per entity).
- Alpha: `opts.alpha` multiplies `globalAlpha` (player i-frames blink: alpha `0.45` when `floor(invuln*18)` is odd).
- Fallback while loading/missing: a grey circle radius `8k` at `(x, y-12k)` (`sprites.js:238-243`); also shows `Idle` while
  the requested anim sheet is still loading.
- Derived geometry (used for gameplay!):
  - `bodyRadius(dex, scale=1) = clamp(IdleW * 0.22, 5, 26) * PX * scale` (collision radius, `sprites.js:127-131`).
  - `bodyHeight(dex, scale=1) = Idle.ay * PX * scale` (HP-bar / damage-number height, `sprites.js:134-137`).
- Shadow (`sprites.js:140-148`): filled ellipse at feet, `rx = [5, 8, 12][clamp(s,0,2)] * PX * scale`, `ry = rx*0.42`,
  color `rgba(0,0,0,0.34)`.

### 2.3 Lazy loading and eviction (`sprites.js:68-119`)

- A sheet is requested the first time it's drawn: key `"dex/Anim[/s]"`, `new Image()` with `src` as above. Failed loads
  retry with exponential backoff `min(8, 2^tries)` s.
- Cache cap: `MAX_SHEETS = 200`; when full, evict sheets unused for > 20 s (oldest first) down to 75% of the cap.
- `preload(dexes, timeout=8000, shiny)` loads all 7 anims; called at run start for the partner (`game.js:134`) and by the
  spawner for upcoming species (see §5).
- Godot: use `ResourceLoader.load_threaded_request(path)` + `load_threaded_get_status`; keep a `Dictionary` cache keyed
  like JS with last-used time; drop references to evict. Import settings for `assets/pokemon/**`: Texture2D, **Lossless**,
  no mipmaps, filter Nearest. ~13,500 PNGs will take a while to import the first time — consider the per-Pokémon atlas
  option in §11.6.

### 2.4 Which animation is used when

| Situation | Animation | Source |
|---|---|---|
| Player/enemy moving | `Walk` (player speed factor `spd/110`) | `player.js:380`, enemy.js |
| Standing | `Idle` | same |
| Player casts `melee`, `nova`, `dash` | `Attack` | `player.js:206-208` |
| Player casts `projectile`, `beam`, `boomerang`, `chain`, `cone` | `Shoot` | same |
| Player casts `aura`, `buff`, `orbit` (every 1.6 s), `mine`, `meteor`, `turret` | `Charge` | same |
| `trail` | no cast animation | `player.js:213` |
| Enemy hit (if not busy and not dashing) | `Hurt` | `enemy.js:136` |
| Death / KO | `Faint` (hold last frame) | `player.js:253`, enemy die |
| Enemy charge telegraph → strike | `Charge` → `Attack` | enemy.js (§5) |

Cast animation speed: `speed = max(1, animLen / (cd*0.9))` with `animLen = sum(d)/60` and `cd = max(0.12, m.cd*cdMul)`,
so attacks chain at short cooldowns. A one-shot already past 35% isn't restarted (`busy() && progress() < 0.65` → skip)
(`player.js:215-220`). After casting the sprite faces the aim direction for 0.35 s (`attackFace`).

### 2.5 Tiles / world art (summary — full detail in §7)

All terrain and props are **procedural pixel art painted in code** (no tile images): `js/world/tiles.js` paints 16×16 art-px
tiles per biome palette with the deterministic hash `G.U.hash(x, y, seed)` (`util.js:32-39`), and `world.js` bakes each
visible 16×16-tile chunk into an image at art resolution (`ImageData`, ~4 ms/chunk in Chrome), drawn ×2.
See §7 for biomes, terrain classes and the port strategy (bake to `Image`/`ImageTexture` on a worker thread, or a shader).

### 2.6 Attack VFX sprites (`js/entities/vfx.js`) — procedural

- 23 shapes are generated on demand into tiny canvases at art resolution and cached by `shape|palette|frame`
  (`vfx.js:258-287`). Each shape is a function writing palette letters into a grid: `o` outline, `d` dark, `m` mid, `l` light,
  `w` white/highlight, `L` light at 50% alpha; `outline()` adds a 1-px `o` border around opaque pixels (PMD style).
- Shapes (w×h art px, frames, flags): `fire 15×11 f3 dir`, `drop 13×9 dir`, `bubble 11×11 f2`, `leaf 12×7 spin`,
  `bolt 15×10 f2 dir`, `shard 13×7 dir`, `rock 12×11 f3 spin`, `blob 12×11 f2`, `needle 13×5 dir`, `star 11×11 f2 spin`,
  `streak 15×5 dir`, `wind 13×11 f2 spin`, `web 11×11 spin`, `ring 13×13 f2`, `crescent 12×11 dir`, `note 11×11 dir`,
  `impact 15×15 f2`, `claw 13×13`, `jaws 13×11 f2`, `arrow 7×9`, `ball 11×11 f2`, `shadow 13×13 f3`, `heart 9×8`.
  `dir` shapes point right and are rotated to the velocity, snapped to 16 directions (π/8); `spin` shapes rotate `t*9` rad.
- 19 palettes of 5 colors `[outline, dark, mid, light, highlight]`, one per type plus `aura` (`vfx.js:15-35`).
- `G.VFX.forMove(m)` → `{ pal, proj, beam?, melee?, aura?, buff?, trail?, inward?, rise? }` from the per-move table
  `MOVE` (`vfx.js:318-383`), default projectile shape by type `TYPE_SHAPE` (`vfx.js:385-389`).
  Enemy shots use `forType(enemyType)`.
- Draw: centered, scale `PX * (scale||1)` (projectiles use scale 1.5 if `r >= 8`), frame = `floor(t*12)`.
- **Port recommendation**: run the same generator once at startup in GDScript into `Image`s (they're ≤15×15 px, 23 shapes ×
  19 palettes × ≤3 frames ≈ 1,000 tiny images — trivial) and build an atlas `ImageTexture`; or pre-render them offline with
  Node into a PNG atlas + JSON (simplest; see §10).

### 2.7 FX layer (`js/entities/fx.js`) — all procedural, world space

| Primitive | Data | Draw |
|---|---|---|
| particle `px()` | square `size*PX` wu, `vx,vy`, `grav`, `drag` (default 0.9 per 1/60 s: `v *= drag^(dt*60)`), life | `fillRect` snapped to the 2-wu grid; alpha stepped |
| `burst(x,y,col,n=8,power=110)` | n particles, random dir, speed `rand(0.35p, p)`, life 0.22–0.5, 35% size 2 | — |
| `spark(x,y,col,dirX,dirY,n=4)` | cone ±0.9 rad around dir, speed 60–170, life 0.14–0.32 | — |
| `sp(shape,pal,x,y,o)` | a VFX sprite with velocity/spin/grav/life/scale/frameRate(10)/fade | `G.VFX.draw` |
| `trail(kind, pal, …)` | `ember, drip, spark, bubbles, dirt, wisp` particle recipes (`fx.js:61-74`) | — |
| `ring(x,y,r0,r1,col,life=0.3,width=3)` | expanding ellipse (`ry = 0.9 r`) made of 2-wu dots (4-wu dots if width ≥ 4) | dots |
| `slash(x,y,angle,radius,arc,col,fx)` | crescent of pixel blocks, life 0.22, thickness `sin(πu)*3*k` art px, + extra sprite (`impact`, `jaws`, `claw`, `vine`/`feather` leaves) | blocks |
| `beam(x,y,angle,len,width,col,fx)` | life 0.2; body of 4-wu segments with wobble, or `lightning` zigzag; sprites travel along it at 420 wu/s every 26 wu; impact sprites at both ends | blocks |
| `dmgText(x,y,value,color,big)` | rises `vy=-46`, `vy *= 0.94`/frame, life 0.62 (big 0.95), font 13px/20px bold, 3-px black outline | text |
| `twinkle(x,y)` | shiny sparkle cross (drawn by `G.Icons.twinkle`) | — |

- Alpha is **quantized** to `1 / 0.66 / 0.33` (`fx.js:154`) so effects look pixel-art.
- Caps by quality level (`G.Settings.fx` 0/1/2): particles `350/800/1400`, sprites `110/210/320`, texts `25/45/70`, density
  multiplier `0.35/0.65/1` (`fx.js:12`). When the text cap is hit, non-big texts are dropped; big ones evict the oldest.
- Numeric damage texts are hidden when setting `dmgNumbers` is off (text messages still show) (`fx.js:80`).

### 2.8 Icons (`js/ui/icons.js`)

Procedural pixel-art icons from character maps rendered to canvas/data-URLs, always drawn at integer multiples (no emojis
anywhere). Each move icon = type emblem (18) + family badge. Details and list in §9.3.

---

## 3. Player

### 3.1 Base stats (from `js/data/pokedex.js`)

Each `G.DEX` entry: `{ dex, name (Spanish), types[1-2], hp, spd, atk, rarity 1-5, bst, starter, gen 1-9, leg? }`
(966 entries, `pokedex.js:9-976`; `G.DEX_BY[dex]` index at `pokedex.js:978`). Derived offline by
`tools/fetch_pokedex.py:91-93` from base stats:

| Game stat | Formula | Range seen | Meaning in game |
|---|---|---|---|
| `hp` | `round(70 + baseHP * 0.45)` | ~72–184 | max HP |
| `spd` | `round(78 + baseSpeed * 0.42)` | ~80–150 | move speed in **wu/s** |
| `atk` | `round(0.70 + max(baseAtk, baseSpAtk)/100 * 0.55, 2)` | ~0.8–1.6 | global damage multiplier |
| `rarity` | legendary/mythical → 5; else BST ≥580 → 5, ≥495 → 4, ≥410 → 3, ≥320 → 2, else 1 (`fetch_pokedex.py:59-71`) | | gacha tier |

### 3.2 Constructor (`js/entities/player.js:11-76`)

| Field | Initial value |
|---|---|
| `r` (collision radius) | `G.Sprites.bodyRadius(dex)` |
| `bodyH` | `G.Sprites.bodyHeight(dex)` |
| `maxHp = hp` | `mon.hp + perks.hp` |
| `baseSpd`, `baseAtk` | `mon.spd`, `mon.atk` |
| `atkMul, spdMul, cdMul` | `perks.atkMul ‖ 1`, `perks.spdMul ‖ 1`, `perks.cdMul ‖ 1` |
| `dmgReduce` | `perks.dmgReduce ‖ 0` |
| `regenFlat` | `perks.regen ‖ 0` (HP/s) |
| `magnet` (pickup radius, wu) | `78 * (perks.magnetMul ‖ 1)` |
| `xpMul`, `coinMul`, `critChance` | from perks (§8.3) |
| `rerollBonus` | `perks.rerolls` (level-up rerolls = 1 free + this) |
| `maxMoves` | 4 slots |
| `buffs` | `{atk, spd, def, regen}` each `{n: stacks, t: time left, amount}` |
| `level=1, xp=0, xpNext=xpFor(1)` | |
| `kills, bosses, coins, t1, t10, dmgDealt` | 0 |
| `item` | `null` (one held item per run, §4.9) |
| `statsTaken` | `{}` — count of each level-up stat card taken (evolution condition, caps) |
| `bonds` | 0 (fusion tokens from legendaries, §4.8) |

### 3.3 Effective stats (getters, `player.js:89-97`)

```
atk       = baseAtk * atkMul * (1 + buffs.atk.n * buffs.atk.amount)
spd       = baseSpd * spdMul * (1 + buffs.spd.n * buffs.spd.amount) * (slowT > 0 ? 0.5 : 1)
            * (inLiquid ? World.liquidEffect(types).slow || 1 : 1) * Weather.speedFor(types)
reduction = min(0.8, dmgReduce + buffs.def.n * buffs.def.amount)
regen     = regenFlat + buffs.regen.n * buffs.regen.amount          (HP per second)
```

### 3.4 Movement (`player.js:328-340`)

- Input vector from `G.Input.axis()` (normalized keyboard vector, or touch joystick vector which may be < 1 in length).
- **No acceleration**: velocity = `axis * spd` instantly. Exception — ice (`liquidEffect.slide`): velocity damps toward
  `axis * spd * 1.15` at rate 1.6 (`damp`).
- Integrate `x += vx*dt`, then `G.World.collide(this)` (circle vs. terrain push-out, §7). Facing: while walking
  `moveAngle = atan2(ay, ax)`.
- Liquid: `inLiquid = World.isLiquid(x, y)`; if the liquid deals damage (lava/poison/etc.): every `le.every` s,
  `invuln = 0` then `hurt(max(le.flat, maxHp * le.dmg * 0.5))`; else 8 small splash particles/s while walking.
- Walk animation speed = `spd/110`.

### 3.5 Targeting (`player.js:358-375`) — computed every frame, consumed by combat

```
ranged = activeMove.kind in {projectile, beam}
threat = nearest enemy within (r + 24) of the player          (something touching you)
boss   = first boss alive within 330 wu
target = (ranged ? boss || threat : threat || boss)
         || nearest enemy within 520
         || World.nearestBreakable(x, y, 200)                 (rock / chest / tall grass prop)
aim    = angle to target, else moveAngle when walking, else unchanged (initial π/2 = down)
```
"Nearest" uses `G.Projectiles.nearest` = squared distance to `(e.x, e.cy())` where `cy()` = feet y (`enemy.js:81`).

### 3.6 Taking damage (`player.js:225-257`)

```
if invuln > 0 or dead: ignore
if type given: k = Types.mult(type, mon.types); amount *= k * Weather.mult(type)
close = activeGroup has any 'melee' move ? 0.75 : 1        (melee users take 25% less)
d = max(1, amount * (1 - reduction) * close)
hp -= d; invuln = 0.45 s; flash = 0.14 s; sfx 'hurt'; Camera.kick(0.28)
damage text '-d' colored: super-effective #ff3048 (big), weak #c9a0a8, else #ff6b7a
```
- **Focus Sash** item: if `hp <= 0` and ≥ 60 s (wall-clock `performance.now()`) since last proc → `hp = 1`, `invuln = 1.2`.
- Death: `hp = 0; dead = true; anim.play('Faint', {hold:true})`; orbit orbs removed.
- Enemy contact damage arrives through `Combat.resolve` (§5); the attacker gets `touchCd = 0.55` s and is knocked back 150.

### 3.7 Healing, regen and per-frame upkeep (`player.js:312-326`)

- `invuln`, `flash`, `attackFace`, buff timers (`t -= dt`; at 0 → `n = 0`, all stacks drop at once), `slowT` count down.
- Shell Bell: pending `bellHeal` (≤ 4) is applied at max 4 HP/s.
- Altar power timer (`power.t`), calls `def.off(pl)` on expiry.
- Regen: `hp = min(maxHp, hp + regen*dt)`.
- `heal(amount)` clamps to `maxHp` and shows `+N` green (`#5fe08a`) if ≥ 1. `addMaxHp(a)` raises both max and current.

### 3.8 XP and levels (`player.js:82-84`, `269-279`)

`xpFor(L) = floor((8 + 6L + 1.6 * L^1.75) * 4)` = XP needed to go from level L to L+1.
`gainXp(a)`: `xp += a * xpMul`; while `xp >= xpNext`: `xp -= xpNext; level++; xpNext = xpFor(level)`; returns number of
levels gained (added to `pendingLevels`).

| L | xpFor(L) | cumulative to reach L+1 |
|---|---|---|
| 1 | 62 | 62 |
| 2 | 101 | 163 |
| 3 | 147 | 310 |
| 5 | 258 | 768 |
| 10 | 631 | 3,128 |
| 15 | 1,123 | 7,716 |
| 20 | 1,722 | 15,087 |
| 30 | 3,213 | 40,195 |
| 40 | 5,063 | 82,215 |
| 60 | 9,750 | 230,586 |

`G.Game.levelXp()` = XP needed (pre-`xpMul`) to level once: `ceil((xpNext - xp + 1) / xpMul)` — used by locked chests.

### 3.9 Pickups / magnet

`magnet` (wu) is the attraction radius for gems/coins (base 78; perk +12%/lvl; level-up card "Imán" ×1.30, max 6).
Collection rules, attraction speed and the "magnet" pickup are in §5.7. Effects of collecting (`game.js:403-451`):

| Pickup kind | Effect |
|---|---|
| `xp`, `xpBig` | `pendingLevels += pl.gainXp(value)` |
| `coin` | `pl.coins += value`, yellow `+N` text |
| `ticket` / `ticket10` | `pl.t1++` / `pl.t10++`, banked to save immediately |
| `heal` | `pl.heal(maxHp * 0.3)` |
| `magnet` | `G.Pickups.pullAll()` (all gems fly to you) |
| `bomb` | `Camera.kick(0.8)`; every enemy **on screen** takes `60 + level*14` (color `#ff7b3d`, knock 160) |
| `item` | equip, or open the 2-card swap choice if you already hold one (§4.9) |

### 3.10 Death and revive

Solo: `dead` → 1.3 s of slowed simulation → `endRun(true)`. Inside a rift arena, dying ejects you instead (§7.11).
Co-op revive (`REVIVE_TIME = 3` s within 56 wu, revive at 50% HP, `invuln 2`) — **out of scope**.

### 3.11 Player drawing (`player.js:432-499`)

1. Ground halo: ellipse stroke `rx = 1.5r, ry = 0.6r`, width 2, alpha 0.22, color = active move type color.
2. Shadow (§2.2). 3. Altar power ring: ellipse `2.1r × 0.85r`, width 3, alpha `0.35 + 0.15 sin(now/120ms)`.
4. Sprite (soft flash, i-frame blink). 5. Buff arcs: one ellipse arc per active buff, radius `1.8r + i*5`, `ry = 0.42 rx`,
   sweep `2π * n/5`, colors atk `#ff6b4d`, spd `#7fe0ff`, def `#b0b8c8`, regen `#5fe08a`, alpha 0.6.

---

## 4. Moves / weapons

### 4.1 Data model (`js/data/moves.js`)

64 moves in `RAW` (`moves.js:124-402`). Fields (all optional except the first 6):

| Field | Meaning |
|---|---|
| `id` | stable string id (also used in saves: `pbind`, `pban`) |
| `name`, `desc` | Spanish display strings (English via i18n dictionary) |
| `type` | one of 18 types — determines type-chart multiplier, color (`G.U.TYPE_COLOR`), VFX palette, learn pool |
| `kind` | behavior family (14 kinds, below) |
| `cd` | cooldown in seconds (for `orbit`: re-hit interval per enemy; for `aura`: tick interval) |
| `dmg` | base damage per hit (multiplied by `pl.atk`) |
| `speed` | projectile speed wu/s (orbit: angular speed rad/s) |
| `count` | projectiles / orbs / chain hops / mines / meteors / simultaneous turrets |
| `spread` | angular spread factor between multiple projectiles |
| `pierce` | extra enemies a projectile can pass through |
| `life` | projectile lifetime s |
| `size` | projectile collision radius wu (draw scale 1.5 if ≥ 8) |
| `radius` | melee/aura/explosion radius, beam length, orbit radius, boomerang out-distance, dash distance, chain hop range |
| `arc` | melee arc in radians (≥ 2π = full circle); cone total arc |
| `width` | beam / dash width wu |
| `knock` | knockback impulse added to enemy `kx/ky` |
| `burn`, `poison` | status stacks applied on hit |
| `slow` | slow factor applied on hit (enemy-side, 1.2 s) |
| `homing` | homing damping rate |
| `stat, amount, dur, stacks` | buff moves |
| `rate`, `range` | turret fire interval s, target range wu |
| `hex` | damage multiplier vs. statused enemies (chain) |

**Load-time transform (do this in the exporter, not at runtime twice!)**: every `melee` move gets
`dmg = round(dmg*1.2)`, `radius = round(radius*1.25)`, `arc = min(3, round2(arc*1.25))` (`moves.js:407-412`).
The tables below already include it.

Learn pool (`moves.js:415-430`): `poolFor(mon)` = all `normal` moves ∪ moves of each of the Pokémon's types. Pool sizes:
normal 8, fire 6, water 5, grass 4, psychic 4, poison 4, ground 4, electric 3, flying 3, bug 3, ice 3, ghost 3, steel 3,
dark 3, rock 2, fighting 2, dragon 2, fairy 2. Starting move: `G.startMoveOf(dex)` = starter table move, else
`START[firstMatchingType]` (`moves.js:469-480`).

### 4.2 Level-up ladders (all moves: max level 5)

`instance(id, lvl)` copies the def and applies ladder steps `0..lvl-2` (`moves.js:436-442`). Mod rules (`moves.js:444-453`):
keys in `MULT = [dmg, cd, speed, radius, dur, amount, arc, width, spread, life, size, rate]` multiply **if the base value
exists**; keys in `ADD = [count, pierce, stacks]` add; any other key — or a MULT key whose base is `null` — is **assigned**.

| Kind | Lv2 | Lv3 | Lv4 | Lv5 |
|---|---|---|---|---|
| projectile | count+1, spread×1.4 | dmg×1.45 | cd×0.75 | count+1, pierce+1, spread×1.2 |
| melee | dmg×1.40 | radius×1.25 | cd×0.75 | arc×9 (⇒ 360°), dmg×1.50 |
| beam | dmg×1.45 | radius×1.30, width×1.30 | cd×0.75 | dmg×1.50 |
| orbit | count+1 | dmg×1.55 | radius×1.25, speed×1.35 | count+1, dmg×1.55 |
| nova | count+4 | dmg×1.40 | cd×0.75 | count+4, pierce+1 |
| aura | radius×1.30 | dmg×1.45 | cd×0.70 | radius×1.30, dmg×1.50 |
| boomerang | count+1 | dmg×1.45 | radius×1.30 | count+1, dmg×1.40 |
| chain | count+2 | dmg×1.45 | cd×0.75 | count+2, dmg×1.40 |
| mine | count+1 | dmg×1.50 | radius×1.30 | count+1, cd×0.75 |
| meteor | count+1 | dmg×1.45 | radius×1.30 | count+2, cd×0.80 |
| turret | dmg×1.50 | rate×0.74 | count+1 | dur×1.50, dmg×1.40 |
| dash | dmg×1.40 | radius×1.30 | cd×0.75 | dmg×1.60, width×1.40 |
| trail | dmg×1.40 | dur×1.40 | radius×1.30 | dmg×1.50, radius×1.30 |
| cone | count+3 | dmg×1.40 | life×1.30 | count+3, pierce+1 |
| buff | stacks+1 | amount×1.40 | dur×1.50 | stacks+1, amount×1.40 |

Card texts are in `LADDERS[kind][i].t` (Spanish). `nextUpText(m)` returns the text of the next step or `null` at max.

### 4.3 Base move table (level 1, after the melee transform)

**melee** (9)

| id / name | type | cd | dmg | radius | arc | knock | slow | evolves → (needs) |
|---|---|---|---|---|---|---|---|---|
| `tackle` Placaje | normal | 0.5 | 16 | 60 | 2.13 | 90 |  | Derribo (hp) |
| `vine-whip` Látigo Cepa | grass | 0.62 | 19 | 85 | 1.63 | 60 |  | Latigazo (atk) |
| `wing-attack` Ataque Ala | flying | 0.55 | 17 | 73 | 2.38 | 70 |  | Pájaro Osado (atk) |
| `body-slam` Golpe Cuerpo | normal | 0.95 | 36 | 58 | 2.75 | 140 |  | Gigaimpacto (atk) |
| `bug-bite` Picadura | bug | 0.42 | 13 | 55 | 2 | 40 |  | Tijera X (atk) |
| `karate-chop` Golpe Kárate | fighting | 0.5 | 22 | 63 | 1.5 | 110 |  | A Bocajarro (atk) |
| `lick` Lengüetazo | ghost | 0.48 | 14 | 60 | 2.25 |  | 0.4 | Puño Sombra (atk) |
| `metal-claw` Garra Metal | steel | 0.5 | 18 | 63 | 2 | 60 |  | Cabeza de Hierro (atk) |
| `bite` Mordisco | dark | 0.45 | 17 | 58 | 1.88 | 70 |  | Triturar (atk) |

**dash** (2)

| id / name | type | cd | dmg | radius | width | knock | evolves → (needs) |
|---|---|---|---|---|---|---|---|
| `quick-attack` Ataque Rápido | normal | 0.75 | 20 | 110 | 34 | 40 | Velocidad Extrema (spd) |
| `aerial-ace` Golpe Aéreo | flying | 0.75 | 18 | 120 | 40 | 60 | Acróbata (spd) |

**buff** (5) — never evolve

| id / name | type | cd | stat | amount | dur | stacks |
|---|---|---|---|---|---|---|
| `swords-dance` Danza Espada | normal | 0.85 | atk | 0.13 | 7 | 5 |
| `agility` Agilidad | normal | 0.85 | spd | 0.1 | 7 | 5 |
| `harden` Fortaleza | normal | 0.85 | def | 0.07 | 7 | 5 |
| `aqua-ring` Acua Aro | water | 0.9 | regen | 1.6 | 8 | 4 |
| `dragon-dance` Danza Dragón | dragon | 0.7 | atk | 0.11 | 7 | 5 |

**projectile** (9)

| id / name | type | cd | dmg | speed | count | spread | pierce | life | size | extras | evolves → (needs) |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `ember` Ascuas | fire | 0.52 | 18 | 310 | 1 | 0.12 | 0 | 1.6 | 7 | burn 1 | Llamarada (atk) |
| `water-gun` Pistola Agua | water | 0.44 | 14 | 350 | 1 | 0.1 | 1 | 1.5 | 6 |  | Escaldar (atk) |
| `thunder-shock` Impactrueno | electric | 0.4 | 13 | 480 | 1 | 0.08 | 2 | 1.1 | 5 |  | Trueno (atk) |
| `confusion` Confusión | psychic | 0.58 | 13 | 280 | 1 | 0.1 | 0 | 2.2 | 8 | homing 2 | Psicocarga (cd) |
| `sludge` Residuos | poison | 0.6 | 17 | 290 | 1 | 0.12 | 0 | 1.5 | 8 | poison 1 | Bomba Lodo (atk) |
| `poison-sting` Picotazo Veneno | poison | 0.34 | 8 | 420 | 1 | 0.08 | 0 | 1 | 4 | poison 1 | Puya Nociva (spd) |
| `rock-throw` Lanzarrocas | rock | 0.7 | 24 | 260 | 1 | 0.12 | 0 | 1.4 | 9 | knock 90 | Roca Afilada (atk) |
| `aura-sphere` Esfera Aural | fighting | 0.62 | 17 | 300 | 1 | 0.1 | 0 | 2 | 8 | homing 4 | Onda Certera (cd) |
| `shadow-ball` Bola Sombra | ghost | 0.66 | 19 | 280 | 1 | 0.1 | 2 | 1.6 | 9 |  | Golpe Fantasma (cd) |

**cone** (2)

| id / name | type | cd | dmg | count | arc | speed | life | size | pierce | extras | evolves → (needs) |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `flamethrower` Lanzallamas | fire | 0.7 | 7 | 7 | 0.9 | 380 | 0.42 | 6 | 1 | burn 1 | Sofoco (cd) |
| `bubble-beam` Rayo Burbuja | water | 0.65 | 6 | 7 | 1 | 340 | 0.45 | 6 |  | slow 0.3 | Acua Cola (atk) |

**orbit** (3)

| id / name | type | cd (rehit) | dmg | count | radius | speed (rad/s) | size | extras | evolves → (needs) |
|---|---|---|---|---|---|---|---|---|---|
| `fire-spin` Giro Fuego | fire | 0.3 | 14 | 3 | 62 | 2.4 | 9 | burn 1 | Fuego Sagrado (rgn) |
| `leaf-storm` Tormenta Floral | grass | 0.26 | 14 | 4 | 74 | 2.6 | 8 |  | Danza Pétalo (rgn) |
| `gust` Tornado | flying | 0.26 | 13 | 3 | 72 | 2.8 | 8 | knock 40 | Vendaval (spd) |

**nova** (7)

| id / name | type | cd | dmg | speed | count | pierce | life | size | extras | evolves → (needs) |
|---|---|---|---|---|---|---|---|---|---|---|
| `heat-wave` Onda Ígnea | fire | 1.25 | 13 | 250 | 10 | 1 | 1.1 | 7 | burn 1 | Erupción (hp) |
| `bubble` Burbuja | water | 1 | 9 | 210 | 8 | 0 | 1.3 | 8 | slow 0.45 | Surf (spd) |
| `psychic` Psíquico | psychic | 1.35 | 10 | 230 | 12 | 1 | 1.6 | 7 | homing 1 | Vasta Fuerza (mag) |
| `mud-shot` Disparo Lodo | ground | 1.1 | 11 | 200 | 7 | 0 | 1 | 9 | slow 0.4 | Tierra Viva (atk) |
| `hyper-voice` Vozarrón | normal | 1.15 | 12 | 260 | 9 | 1 | 0.9 | 7 |  | Alboroto (cd) |
| `fairy-wind` Viento Feérico | fairy | 1 | 11 | 230 | 10 | 0 | 1.2 | 7 |  | Fuerza Lunar (atk) |
| `dark-pulse` Pulso Umbrío | dark | 1.15 | 14 | 240 | 10 | 1 | 1.1 | 8 |  | Alarido (spd) |

**beam** (5)

| id / name | type | cd | dmg | radius (length) | width | extras | evolves → (needs) |
|---|---|---|---|---|---|---|---|
| `hydro-pump` Hidrobomba | water | 1.5 | 29 | 250 | 30 |  | Hidrocañón (atk) |
| `psybeam` Psicorrayo | psychic | 1.15 | 17 | 215 | 40 |  | Premonición (atk) |
| `ice-beam` Rayo Hielo | ice | 1.1 | 20 | 220 | 30 | slow 0.7 | Ventisca (atk) |
| `dragon-rage` Furia Dragón | dragon | 1 | 24 | 230 | 34 |  | Cometa Draco (atk) |
| `flash-cannon` Foco Resplandor | steel | 1.05 | 23 | 220 | 30 |  | Rayo Metálico (def) |

**boomerang** (3)

| id / name | type | cd | dmg | speed | count | spread | radius (out) | size | extras | evolves → (needs) |
|---|---|---|---|---|---|---|---|---|---|---|
| `razor-leaf` Hoja Afilada | grass | 0.9 | 10 | 330 | 2 | 0.5 | 210 | 6 |  | Lluevehojas (cd) |
| `bonemerang` Huesomerang | ground | 0.95 | 16 | 300 | 1 | (0.5) | 230 | 8 | knock 40 | Ataque Óseo (atk) |
| `psycho-cut` Psicocorte | psychic | 0.8 | 9 | 360 | 2 | 0.6 | 200 | 7 |  | Psicocolmillo (cd) |

**aura** (7)

| id / name | type | cd (tick) | dmg | radius | extras | evolves → (needs) |
|---|---|---|---|---|---|---|
| `giga-drain` Hierba Lazo | grass | 0.55 | 9 | 76 |  | Planta Feroz (hp) |
| `discharge` Chispazo | electric | 0.45 | 8 | 70 |  | Campo Eléctrico (def) |
| `bulldoze` Terratemblor | ground | 0.7 | 11 | 80 | slow 0.35 | Terremoto (atk) |
| `bug-buzz` Zumbido | bug | 0.45 | 8 | 66 |  | Enjambre (rgn) |
| `powder-snow` Nieve Polvo | ice | 0.55 | 8 | 76 | slow 0.45 | Viento Hielo (spd) |
| `dazzling-gleam` Brillo Mágico | fairy | 0.5 | 9 | 72 |  | Campo de Niebla (rgn) |
| `night-shade` Tinieblas | dark | 0.5 | 9 | 72 |  | Pesadilla (rgn) |

**chain** (2)

| id / name | type | cd | dmg | count (hits) | radius (hop) | extras | evolves → (needs) |
|---|---|---|---|---|---|---|---|
| `thunderbolt` Rayo | electric | 0.95 | 21 | 4 | 140 |  | Electrocañón (cd) |
| `hex` Infortunio | ghost | 0.9 | 17 | 4 | 150 | hex 1.7 | Poltergeist (mag) |

**trail** (2)

| id / name | type | cd | dmg | radius | dur | extras | evolves → (needs) |
|---|---|---|---|---|---|---|---|
| `toxic` Tóxico | poison | 0.3 | 6 | 26 | 3 | poison 1 | Gas Venenoso (rgn) |
| `flame-wheel` Rueda Fuego | fire | 0.28 | 10 | 28 | 2.6 | burn 1 | Envite Ígneo (spd) |

**mine** (3)

| id / name | type | cd | dmg | count | radius (blast) | dur | extras | evolves → (needs) |
|---|---|---|---|---|---|---|---|---|
| `string-shot` Disparo Demora | bug | 1.1 | 14 | 2 | 56 | 7 | slow 0.6 | Red Viscosa (cd) |
| `spikes` Púas | ground | 1.2 | 18 | 2 | 60 | 8 |  | Fisura (atk) |
| `toxic-spikes` Púas Tóxicas | poison | 1.1 | 11 | 2 | 56 | 8 | poison 2 | Lanza Mugre (rgn) |

**meteor** (3)

| id / name | type | cd | dmg | count | radius (blast) | extras | evolves → (needs) |
|---|---|---|---|---|---|---|---|
| `rock-slide` Avalancha | rock | 1.3 | 21 | 3 | 46 | knock 50 | Trampa Rocas (cd) |
| `hail` Granizo | ice | 1.2 | 18 | 4 | 40 | slow 0.4 | Alud (cd) |
| `meteor-mash` Puño Meteoro | steel | 1.4 | 34 | 2 | 54 | knock 80 | Bomba Imán (atk) |

**turret** (2)

| id / name | type | cd | dmg | rate (s/shot) | dur | count | range | speed | size | extras | evolves → (needs) |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `will-o-wisp` Fuego Fatuo | fire | 3.5 | 15 | 0.55 | 6 | 1 | 300 | 300 | 7 | burn 1 | Infierno (cd) |
| `substitute` Sustituto | normal | 4 | 14 | 0.4 | 6 | 1 | 280 | 320 | 6 |  | Doble Equipo (def) |

### 4.4 Casting loop (`js/systems/combat.js:21-77`)

Only the moves of the **active slot** run (a slot is a group of 1–4 moves when bonds are used, §4.8). Per move per frame:

```
if kind == 'orbit': orbit(...) ; continue           # orbs are persistent, no cooldown loop
m.t -= dt
if m.t > 0: continue
if kind in TARGETED and not (pl.target and dist(pl, pl.target) <= reach(m)):
    m.t = 0.05; continue                            # wait for a target, don't waste the animation
m.t = max(0.05, m.cd * pl.cdMul)
pl.cast(m)                                          # animation + sfx 'shot' {kind, type}; Life Orb self-damage
run(pl, m)                                          # kind dispatch
```

`TARGETED = melee, beam, projectile, boomerang, chain, meteor, dash, cone`. `reach(m)`: melee `radius+30`, beam
`radius+20`, boomerang `radius+40`, chain `280`, meteor `340`, dash `radius+60`, cone `speed*life+30`, otherwise `520`.
Untargeted kinds (`nova, aura, buff, mine, turret, trail`) fire whenever off cooldown.
Switching the active slot (`setActive`, `player.js:138-151`) clears the player's orbit orbs, plays `select`, and sets each
move's timer to `min(t, cd*0.35)` (fast first cast). Choice Band blocks switching.

**Life Orb** (`player.js:203-205`): each cast (not orbit/trail) costs `max(1, maxHp*0.01)` HP, never below 1.

### 4.5 Damage formula (player → enemy)

```
base      = m.dmg_at_level(_and_evolution) * pl.atk                       # pl.atk includes perks, items, card stacks, buffs
typeK     = clamp(Π over enemy types of SOFT[CHART[m.type][t]], 0.3, 2.4) * Weather.mult(m.type)
            where SOFT = {2: 1.6, 0.5: 0.6, 0: 0.3}                         (js/data/types.js:14-44)
crit      = random() < pl.critChance  →  ×1.5                              (combat.js:526-527)
dmg       = base * typeK * (crit ? 1.5 : 1) [* chain falloff * hex]        (combat.js:529-539, 638-641)
enemy.hurt(dmg): d = max(1, round(dmg)); shield absorbs first; hp -= max(1, round(remaining))   (enemy.js:100-127)
```

- **No STAB**, no defense stat on enemies. Type label for the number color: `super` if mult > 1.05, `weak` if < 0.95
  (`types.js:47`); crit text orange `#ff9a3c`, super yellow `#ffe14d` (big), weak grey `#a3abb8`.
- The type multiplier uses the **move's type**; enemy attacks against the player use the enemy's primary type or its shot
  type (§5), with the same table.
- On hit: `pl.onDealt(dmg)` (Shell Bell: `bellHeal = min(4, bellHeal + dmg*0.04)`), `pl.dmgDealt += dmg`, then statuses:
  `burn` → `applyBurn(stacks)`: `burn = min(8, burn+stacks)`, `burnT = 3` s, ticks every 0.5 s for
  `1.6 * burn * (1 + pl.level*0.06)`; `poison` → `poison = min(8, poison+stacks)`, `poisonT = 4` s, ticks every 0.6 s for
  `maxHp*0.012*poison + 1`; `slow` → `slow = max(slow, factor)`, `slowT = max(slowT, 1.2)` (`enemy.js:140-152`, `253-261`).
- Knockback: `kx += nx*knock; ky += ny*knock` (normalized hit direction); bosses ignore knockback (`enemy.js:120-124`).
- All attacks also damage destructible props (rocks, chests, tall grass) with `World.damageProp(p, dmg, color)` (no type mult).

### 4.6 Per-kind runtime behavior (`js/systems/combat.js`)

**projectile** (`fireProjectiles`, `combat.js:86-104`): `n = max(1, count)`; for each `i`:
`off = n==1 ? 0 : (i/(n-1) - 0.5) * spread * n`; angle `a = aim + off + rand(±0.03)`; spawn at `(x,y) + 3*(cos a, sin a)`
with `v = speed`, `dmg = m.dmg*pl.atk`, `r = size`, `life`, `pierce`, `homing`, status payload, `hits = Set()`.
Muzzle `spark` (3 particles).

**nova** (`combat.js:106-121`): `n = max(3, count)`, evenly spaced around 2π with ±0.06 jitter; same projectile record; ring FX.

**cone** (`combat.js:338-351`): `n = max(2, count)`, `a = aim + (i/(n-1) - 0.5)*arc + rand(±0.05)`,
speed `× rand(0.85, 1.1)`, life `× rand(0.85, 1.05)`, spawn 4 wu out.

**Projectile physics** (`projectile.js:42-93`): `t += dt`; die at `t >= life`; **boomerang** (`boom` = out time
`radius/speed`): at `t >= boom` set `back = true` and **reset `hits`** (can hit the same enemies again), then velocity damps
(rate 7) toward the owner at `bsp = speed*1.1`; removed when within `owner.r + 8`; life `out*4 + 1.5`, `pierce 999`.
**Homing** (`homing > 0`): retarget each frame to the nearest enemy within 340 wu, `v = damp(v, dir*|v|, homing, dt)`
(constant speed, turning rate = `homing`). Store `px,py` (previous pos) for swept collision; emit trail particles every
0.04 s if on screen; **despawn when outside the camera view + 260 wu**.

**Projectile collision** (`combat.js:552-658`), in reverse list order:
1. Enemy shots (`friendly:false`): removed if `World.projectileBlock(x,y,r)` (walls and solid props give cover); hit the
   player if `dist < p.r + pl.r` → `pl.hurt(p.dmg, p.mtype)`, removed.
2. Player shots (not orbs): removed by walls and non-destructible solid props. For each prop in radius (once per
   projectile via `phits`): damage it; solid props consume 1 pierce or stop the projectile; tall grass doesn't.
3. Enemies: **swept** test along the segment `(px,py)→(x,y)`: `segDist2 <= (p.r + e.r)^2`, enemies fetched with
   `queryCircle(mid, half_len + r)`. Each enemy at most once per projectile (`hits` set). Damage as §4.5; 50% chance of
   an impact sprite. Then `pierce > 0 ? pierce-- : remove`.
4. Orbs: never removed; per-target re-hit timer `rehit` (= move `cd`, min 0.12 s) tracked in `hitLog: Map(id → time)`
   using run time; the map is pruned above 300 entries.

**melee** (`combat.js:128-141`): slash FX at `(x, y - 9)`; hits every enemy with `dist <= radius` (enemy feet,
`queryCircle`) whose angle is within `half = min(arc, 2π)/2` of `aim`; knock along the player→enemy direction; props in the
same arc are damaged. Melee active ⇒ player takes 25% less damage (§3.6).

**beam** (`combat.js:143-170`): length = `radius`, cut at the first wall sampled every 8 wu along the aim. Hits every enemy
whose feet are within the rectangle `[−r, len+r]` along the axis and `|perp| <= width/2 + e.r`; no knockback; camera kick
0.08. Visual: `FX.beam` from `(x, y-18)`.

**aura** (`combat.js:172-196`): every `cd` s, hit everything within `radius` of the player (no arc), ring FX
`radius*0.5 → radius`, 5 type particles (inward for `giga-drain`, rising for toxic/bulldoze/night-shade, else swirling).
(`m.drain` healing is dead code — no move defines `drain`.)

**buff** (`combat.js:198-207`): `pl.addBuff(stat, amount, dur, stacks)`: `b.amount = amount; b.n = min(maxStacks, n+1);
b.t = dur` (refreshes the whole stack's timer). Effects: atk → `atk × (1 + n*amount)`; spd → `spd × (1 + n*amount)`;
def → `reduction += n*amount` (cap 0.8 total); regen → `+n*amount` HP/s. All stacks expire together when `t` hits 0.
Buffs don't deal damage; the level-up generator never offers a 3rd buff move (§6).

**boomerang** (`combat.js:212-224`): `n = max(1,count)`, `spread = m.spread || 0.5`;
angle `aim + (n==1 ? 0 : (i/(n-1) - 0.5) * spread * min(n, 3))`; see physics above.

**chain** (`combat.js:227-254`): first target = `pl.target` if it's a live enemy, else nearest within 280. Up to
`count` hits; each hit damage `m.dmg*pl.atk*k*hex` where `k` starts at 1 and `*= 0.85` per hop; `hex` (move `hex`) applies
only if the current target has `burn>0 || poison>0 || slow>0`. Next target = nearest not-yet-hit enemy within `radius` of the
current one. Each hop draws a 10-wide beam from the previous point (start `(pl.x, pl.y-18)`, then each target's mid-body).
Camera kick 0.05.

**mine** (`combat.js:257-268`, update `366-375`): drop `count` mines at random angle, distance 0 (single) or 18–46
(`y` offset ×0.8); arm after 0.35 s; trigger when any enemy is within **14 wu** of the mine; explode for full `dmg` in
`radius` (or for **50% damage** when the mine times out at `dur`, default 7). Cap per player `4 + count*2` mines (oldest
removed).

**meteor** (`combat.js:271-282`, update `376-383`): pick `count` random enemies within 340 (shuffled), target position
`enemy ± (8, 6)` jitter (or a random point within ±140×±110 of the player if fewer enemies); meteor `i` starts at
`t = -i*0.09` and lands at `t >= 0.5` (`fall`) dealing `dmg` in `radius`; kick 0.12. Ground shadow ellipse grows
`0.3 → 1.0` and a dashed target ring is drawn; the rock falls from `(+40, -170)` offset.

**turret** (`combat.js:285-293`, update `384-400`): placed 26 wu behind the player (`aim + π ± 0.6`, y offset ×20/26);
lives `dur` (6 s); first shot after 0.3 s; each shot targets the nearest enemy within `range` (default 300), projectile
speed `speed`, life 1.4, `size`, interval `rate` (0.15 s re-check when no target). At most `count` turrets per player
(oldest removed). Drawn floating 16 wu up with a bob `sin(now*4)*2`.

**dash** (`combat.js:296-321`): sample along aim every 8 wu up to `radius`; stop before the first point where
`World.isFree(x, y, pl.r*0.8, true)` fails; **teleport** the player to the end point, `World.collide(pl)`,
`invuln = max(invuln, 0.3)`; hit every enemy within `width/2 + e.r` of the traversed segment (knock along aim); props
too; kick 0.12. Streak sprites every 22 wu; slash at the end.

**trail** (`combat.js:324-335`, update `401-407`): drop a patch at the feet unless the previous patch is within
`0.9*radius` and younger than 1 s; patch lives `dur`, ticks every 0.5 s dealing `dmg` in `radius` (first tick immediately);
max 18 patches per player. No cast animation, no sound per patch.

**orbit** (`combat.js:468-502`): wants `count` orbs owned by the player with this move id. If the count changed, remove extra
and spawn missing; relayout so all orbs are evenly spaced starting from the first orb's angle (`base = orbs[0].oa` or
`now*speed`). Every frame refresh `dmg = m.dmg*pl.atk`, `orad = radius`, `ospeed = speed`, `r = size`. Orb position:
`oa += ospeed*dt; x = owner.x + cos(oa)*orad; y = owner.y + sin(oa)*orad*0.7` (elliptical). Re-hit interval
`max(0.12, cd)`. A `Charge` cast animation plays every 1.6 s. Orbs also damage props on the same re-hit timer.

**Swapped slots / fields cleanup**: orbs are removed on slot change, bond fusion and death; persistent fields (mines,
meteors, turrets, patches) stay until they expire.

### 4.7 Evolution (`moves.js:482-558`, `levelup.js:53-71`)

- Every non-buff move has an evolution `EVO[id] = [newName, needs]` where `needs` ∈ `hp, atk, spd, cd, def, rgn, mag, xp`
  (ids of level-up stat cards, §6). Display names of needs: `NEED_NAME` (Vigor, Potencia, Carrera, Reflejos, Coraza,
  Síntesis, Imán, Aprendizaje).
- Condition (`evoInfo`): move at **level 5**, not already evolved, and `pl.statsTaken[needs] >= 1` (the matching stat card
  was taken **at least once during this run**, at any time).
- When ready, a gold "evo" card is **always** included in the next level-up offer (first slot) (`levelup.js:112-114`).
  While a maxed move is waiting for its stat, that stat card is always added to the candidate pool with weight 14 and a gold
  "Evoluciona X" tag (`levelup.js:87-101`).
- `evolve(m)`: apply `EVO_MODS[kind].m` with the same mod rules, `baseName = name`, `name = newName`, `evolved = true`.
  The move keeps its id/type/kind.

| Kind | Evolution mods |
|---|---|
| projectile | dmg×1.8, count+2, pierce+2, size×1.3, spread×1.1 |
| melee | dmg×1.9, radius×1.3, arc×9 |
| beam | dmg×1.8, width×1.5, radius×1.2, cd×0.85 |
| orbit | count+2, dmg×1.7, radius×1.15 |
| nova | count+6, dmg×1.6, pierce+1 |
| aura | dmg×1.8, radius×1.35 |
| boomerang | dmg×1.8, count+1, radius×1.2, size×1.2 |
| chain | dmg×1.7, count+3, radius×1.2 |
| mine | dmg×1.8, count+2, radius×1.25 |
| meteor | dmg×1.7, count+2, radius×1.2 |
| turret | dmg×1.8, count+1, rate×0.8 |
| dash | dmg×1.9, radius×1.25, cd×0.8 |
| trail | dmg×1.8, radius×1.25, dur×1.3 |
| cone | dmg×1.7, count+4, pierce+1 |

### 4.8 Bonds ("vínculos", move fusion) (`player.js:158-195`, `game.js:342-370`, `rift.js:199`)

- Each legendary defeated in a rift grants `pl.bonds++`. While `bonds > 0`, every frame `offerBond(quiet=true)` tries to
  open the bond picker (only in `playing`, not in an arena, and not while level-up/pause/item screens are open).
- `bondOptions()`: if a group with 2–3 moves exists (`BOND_MAX = 4`) and there are loose (single) slots → mode `'add'`
  (pick one loose move to add to that group); else if ≥ 2 loose slots → mode `'pair'` (pick two, in 2 steps); else
  `null` (bond stays stored; message "learn another move to use it").
- `fuse(moves, group)`: move the picked moves into one slot (removing their slots, which frees slot count for new moves),
  rearrange bound slots, make the fused slot active (unless Choice Band), `bonds--`, clear orbs.
- Effect: **all moves in the active slot tick and cast independently, each with its own cooldown** (`combat.js:24`).
  The HUD flashes each fused move's icon when it casts (`m.castAt`). Only one group can grow at a time.
- Slot arrangement ("Atajos" upgrade): `arrange()` (`player.js:118-134`) places moves that have a bound slot index at that
  index (or the nearest free lower one), others fill remaining slots in learn order.

### 4.9 Held items (`js/data/items.js`) — one per run

| id | Name (es) | Effect (on/off are exact inverses) |
|---|---|---|
| `leftovers` | Restos | `regenFlat += maxHp*0.015` (snapshot at equip time) |
| `choiceband` | Cinta Elección | `atkMul *= 1.4`; cannot change active slot |
| `quickclaw` | Garra Rápida | `cdMul *= 0.8` |
| `focussash` | Banda Focus | survive a lethal hit at 1 HP once per 60 s (real time) |
| `shellbell` | Cascabel Concha | heal 4% of damage dealt, max 4 HP/s |
| `amuletcoin` | Moneda Amuleto | `coinMul *= 1.5` |
| `luckyegg` | Huevo Suerte | `xpMul *= 1.3` |
| `lifeorb` | Vidasfera | `atkMul *= 1.3`; each cast costs 1% max HP (min 1, never KO) |
| `choicescarf` | Pañuelo Elección | `spdMul *= 1.35` |
| `rockyhelmet` | Casco Dentado | an enemy that touches you takes `15 + level*4` (knock 80) |
| `assaultvest` | Chaleco Asalto | `dmgReduce += 0.2` |

`G.Items.roll(except)` = uniform random item ≠ `except`. Picking up an item when holding one opens a 2-card choice
("keep X" / "switch to Y"), pausing the game (`game.js:377-400`). Drop sources: all bosses, locked chests (50%), normal
chests (8%) (§5, §7).

---

## 5. Enemies, spawning, drops, shinies

Sources: `js/data/enemies.js` (data + run cast), `js/systems/spawner.js` (spawning), `js/entities/enemy.js` (runtime, AI,
bosses, manager/grid), `js/systems/pathing.js` (flow field), `js/entities/pickup.js` (drops), `js/systems/hazards.js`
(telegraphed attacks). **Enemy pools do not depend on biome** — only on run time (tiers) and hordes.

### 5.1 Data model (`js/data/enemies.js`)

Enemies are generated from `G.DEX` at run start. Inverse of the stat derivation (`enemies.js:53-54`):
`baseHp(p) = (p.hp - 70)/0.45`, `baseSpd(p) = (p.spd - 78)/0.42`.

**Tiers** (`TIERS`, `enemies.js:34-41`) — BST brackets unlocked by run time; `tierAt(t)` = highest tier with `from <= t`.
Candidates of a tier = `G.DEX` with `rarity < 5`, BST in range, sprite meta present (`enemies.js:115-117`).

| ti | from (s) | BST | hp | spd | dmg | xp | cast | #candidates |
|---|---|---|---|---|---|---|---|---|
| 0 | 0 | 180–330 | 17 | 56 | 6 | 3.5 | 7 | 276 |
| 1 | 70 | 300–405 | 32 | 62 | 8.5 | 5 | 7 | 261 |
| 2 | 160 | 385–465 | 52 | 60 | 11 | 8 | 7 | 182 |
| 3 | 260 | 445–515 | 88 | 70 | 14 | 13 | 7 | 270 |
| 4 | 380 | 495–560 | 150 | 66 | 22 | 24 | 7 | 192 |
| 5 | 500 | 530–620 | 250 | 72 | 28 | 38 | 7 | 75 |

**Behavior per species** (`behaviorOf(p)`, `enemies.js:67-85`), deterministic: `h = G.U.hash(p.dex, 7, 11)`. First match wins:

1. dex ∈ `HEAL {35,36,113,173,183,184,242,301,440,531,594,700,764,858}` → `healer`
2. dex ∈ `SHIELD {95,122,208,213,227,306,375,410,411,436,437,439,476,703}` → `shielder`
3. dex ∈ `BOMB {74,75,76,100,101,102,109,110,337,338,343,344}` → `bomber`
4. `SUMMON[dex]` exists and the minion has sprite meta → `summoner`. `SUMMON = {15:13, 18:16, 24:23, 28:27, 31:29,
   34:32, 42:41, 51:50, 53:52, 57:56, 59:58, 62:60, 68:66, 73:72, 78:77, 82:81, 85:84, 91:90, 117:116, 130:129, 168:167,
   169:41, 199:79, 230:116, 262:261, 334:333, 405:403, 416:415, 462:81, 466:239, 553:551, 637:636}`
5. bug type and `0.6 ≤ h < 0.78` → `summoner` (swarm; minion = itself)
6. electric/psychic/dragon/ice and `h < 0.18` → `beamer`
7. fire/ground/poison and `h < 0.18` → `zoner`
8. water/grass/bug/fairy and `0.18 ≤ h < 0.32` → `fan`
9. fighting/ground/normal/rock and `0.42 ≤ h < 0.56` → `jumper`
10. psychic/electric/ghost/fairy and `h < 0.4` → `ranged`
11. fire/water/poison/ice and `h < 0.22` → `ranged`
12. fighting/normal/ground/rock/dragon/steel/dark and `h < 0.4` → `charger`
13. `baseHp > 95 && baseSpd < 50` → `tank`
14. else `chase`

Later-assigned behaviors: `runner` (per-tier, in `rollRun`) and `thief` (events only).

**Per-species def** (`defFor(p, tier, ti)`, `enemies.js:88-112`):
```
hpK  = clamp(baseHp/65, 0.7, 1.6);  spdK = clamp(0.75 + baseSpd/260, 0.75, 1.3)
hp   = round(tier.hp * hpK * (tank ? 1.5 : 1));   spd = round(tier.spd * spdK * (tank ? 0.7 : 1))
dmg  = round(tier.dmg * (tank ? 1.2 : 1));        xp  = max(3, round(tier.xp * (tank ? 1.3 : 1)))
ranged-like (ranged, fan, beamer, zoner, healer, summoner):
  shotDmg = round(tier.dmg * (fan ? 0.7 : 0.8))
  shotCd  = {ranged: 2.2-0.15ti, fan: 3.2-0.15ti, beamer: 4.4-0.2ti, zoner: 4.6-0.2ti, healer: 3.5, summoner: 7} (2 dp)
  range   = (beamer 260 | healer/summoner 230 | else 190) + 6*ti
summoner: minion = SUMMON[dex] (undefined for swarms → own dex);  fan: fanN = ti<2 ? 3 : 5
zoner: zones = ti<2 ? 1 : ti<4 ? 2 : 3;  bomber: spd = round(spd*1.25), hp = round(hp*0.8)
```
Def shape: `{dex, name, behavior, hp, spd, dmg, xp, [shotDmg, shotCd, range], [minion], [fanN], [zones]}`.

**Run cast** (`rollRun()`, `enemies.js:145-172`, called by `Spawner.reset()`): for each tier pick **7 species**
(`castFor`, `enemies.js:129-139`), `PLAIN = [chase, charger, ranged, tank]`, `SUPPORT = [healer, shielder, summoner]`:
1. pick a support kind uniformly among those present, then 1 species of it;
2. if `tier.from > 0`: 1 species whose behavior is neither PLAIN nor SUPPORT (bomber/beamer/zoner/fan/jumper);
3. fill the rest: tier 0 only PLAIN; other tiers any remaining candidate.
Then in each tier the **fastest** chase/charger/tank def becomes `runner`: `spd = round(spd*1.6)`, `hp = round(hp*0.7)`.

**Bosses** (`BOSS_SLOTS`, `enemies.js:44-50`, built at `155-170`) — 5 per run, non-legendary, not repeated:

| at (s) | slot hp | slot dmg | xp | BST | final hp = round(hp·1.35) | final dmg = round(dmg·1.2) | shotDmg = round(dmg·0.55) |
|---|---|---|---|---|---|---|---|
| 180 | 1400 | 34 | 220 | 490–545 | 1890 | 41 | 19 |
| 360 | 3200 | 42 | 420 | 520–580 | 4320 | 50 | 23 |
| 540 | 5600 | 48 | 680 | 540–600 | 7560 | 58 | 26 |
| 720 | 9000 | 56 | 1000 | 580–700 | 12150 | 67 | 31 |
| 900 | 16000 | 68 | 1800 | 600–700 | 21600 | 82 | 37 |

Boss pool: `!leg`, sprite meta, unused this run, BST in range (fallback BST ≥ 580). `spd = round(clamp(40 + baseSpd*0.5,
40, 100))`; behavior `ranged` if `behaviorOf` says ranged, else `charger` if baseSpd > 90, else `chase` (only affects
`farLike`, see 5.6). No bosses after minute 15. No minibosses; "elites" are a spawn-time boost (5.3).

**Time scaling** (`enemies.js:174-194`):
```
late(t)      = exp(min(30, 0.000374 * m^2)),  m = max(0, t/60 - 60)        # overtime after minute 60
scale(t)     = { hp: (1 + t/95)*late, dmg: (1 + t/420)*late^0.7, spd: 1 + min(0.35, t/1400) }
bossScale(t) = { hp: (1 + t/600)*late, dmg: (1 + t/600)*late^0.7, spd: 1 }
```
`late`: min 60 ×1, 75 ×1.088, 90 ×1.40, 105 ×2.13, 120 ×3.84, 150 ×20.7. At `t = 3600` the banner "¡Los Pokémon salvajes
se vuelven cada vez más fuertes!" (3.6 s, sfx `boss`) is shown once (`spawner.js:121-122`).

**Spawn bag** (`bagAt(t)`, `enemies.js:213-225`): if a horde event is active → horde defs only; else for every unlocked
tier push each cast def `w` times, `w = (t - from > 260) ? 3 : 10` (old tiers fade); empty → `cast[0].list`. Species are
picked uniformly from the bag. `hordeTypes(t)` = types with ≥ 3 candidates in the current tier, excluding
`NO_HORDE = {bomber, healer, shielder, summoner}`; `hordeDefs(type, t)` = up to 4 random candidates of that type (`defFor`,
no runner). `upcomingDex(t, ahead=60)` = cast + boss dexes due within `ahead` s (sprite preloading).

### 5.2 Spawner (`js/systems/spawner.js`)

Constants (`spawner.js:17-25`): `CAP = 64` alive, `ELITE_FROM = 0.85`, `DENSITY = 0.24`, `DMG_K = 2.4`, `XP_K = 5.6`,
`hpK(t) = 3.3 + min(1.7, t/210)`, `SHINY_RATE = 1/4096`; `surgeT` starts at 32.

- **Rate** (enemies/s): `rate(t) = (1.6 + 0.028 t + 0.5 (t/60)^1.6) * 0.24` (`spawner.js:35-37`).
- `update(dt, players, t)` (`spawner.js:109-151`):
  1. tick banner; **if in rift arena: return** (no spawns, no boss check — overdue bosses spawn on return);
  2. every 10 s preload `upcomingDex(t, 60)`;
  3. boss: if `t >= BOSSES[bossIdx].at` → `spawnBoss(anchor(), t, b)`, `bossIdx++`;
  4. `bossFight = EnemyMgr.bossAlive()` (legendaries count);
  5. trickle: if `count < CAP`: `acc += rate(t) * (bossFight ? 0.25 : 1) * dt`; spawn `floor(acc)` (consuming acc) while
     `count < CAP`;
  6. surge ("¡Marea de Pokémon!"): `surgeT -= dt` only while no boss is alive; at ≤ 0: `surgeT = rand(38, 56)`,
     `n = min(CAP - count, round((14 + floor(t/22)) * 0.4))`, spawned at `base ± rand(0.55)` rad around one anchor; banner
     2.2 s (shown even if `n ≤ 0`), sfx `surge`. Solo sizes ≈ 6 (0–1 min), 9 (3), 16 (10), 22 (15), 38 (30), 71 (60).
  - `burst(n)` (horde start): `n = 6` from one side ±0.6 rad, allowed up to `CAP + 10`.
- **Spawn position**: `ringPoint(pl, a)`: `d = Camera.outerRadius() + rand(10, 70)`, point `(x + cos a·d, y + sin a·d·0.9)`
  (≈ 490–550 wu at 16:9, always off-screen). `freePoint`: up to 8 tries (try 0 exact angle, others `±0.9` rad); walkers need
  `World.isFree(x, y, 14)` (no wall, **no liquid**, no prop overlap); hovering species (`meta.hv`) skip the check.
  Bosses use `ringPoint` without checks. If no point → nothing spawns (the accumulator was consumed).

### 5.3 Spawn stat pipeline (`spawnOne`, `spawner.js:79-95`)

```
def   = pick(bagAt(t))
e     = new Enemy(def, x, y, sc = { hp: scale.hp * hpK(t), dmg: scale.dmg, spd: scale.spd })
e.maxHp = e.hp = round(def.hp * sc.hp);  e.spd = def.spd * sc.spd;  e.dmg = def.dmg * sc.dmg * 2.4
e.xp  = round(def.xp * 5.6)
elite if EnemyMgr.count >= 64*0.85 (≥ 55 alive): maxHp = hp = round(maxHp*1.6); dmg *= 1.25; xp = round(xp*1.6)   # no visual marker
shiny (1/4096, only if a shiny sheet exists): makeShiny()  → shiny sprite, maxHp *= 2, hp = maxHp, xp *= 5
golden hour active: makeGolden() → golden = true, xp *= 2 (not bosses/thieves)
```
Solo multipliers vs. `def` (from the formulas): t=0: HP ×3.30, dmg ×2.40, spd ×1.00 · 1 min: ×5.85/×2.74/×1.04 ·
3 min: ×12.0/×3.43/×1.13 · 5 min: ×19.7/×4.11/×1.21 · 10 min: ×36.6/×5.83/×1.35 · 15 min: ×52.4/×7.54 · 30 min:
×99.7/×12.7 · 60 min: ×194/×23.0 · 90 min: ×405/×42.1 · 120 min: ×1476/×112. From ~minute 3 the cap is saturated, so most
new spawns are elites.

**Bosses** (`spawnBoss`, `spawner.js:97-106`): `new Enemy(b, x, y, bossScale(t), boss=true)`; no hpK/DMG_K/XP_K/elite;
shiny roll 1/4096; banner "¡X salvaje apareció!" / "¡X shiny salvaje apareció!" 3.2 s, `Camera.kick(1.1)`, sfx `boss`.
On-time boss stats: #1 2457 HP / 53 dmg, #2 6912/80, #3 14364/110, #4 26730/147, #5 54000/205. Boss speed `def.spd`
unscaled; xp = slot xp.

### 5.4 Enemy runtime (`js/entities/enemy.js`)

Constructor (`enemy.js:25-79`): `id` (global counter), `def`, `dex`, `name`, `x, y`, `boss`;
`scale = boss ? clamp(round(110/h*2)/2, 1, 2) : 1` with `h = Idle.ay*2` (`enemy.js:16-22`); `anim = Animator(dex, scale)`;
`r = bodyRadius(dex, scale)`; `bodyH = bodyHeight(dex, scale)`; `maxHp = hp = round(def.hp*sc.hp)`;
`spd = def.spd*sc.spd`; `dmg = def.dmg*sc.dmg`; `xp = def.xp`; `behavior`; `types` (from dex, default `['normal']`);
`atkType = types[0]`; `flying = boss || hovers(dex)`; status fields (`slow, slowT, burn, burnT, burnTick, poison, poisonT,
poisonTick, lavaTick`); knockback velocity `kx, ky`; `touchCd`; `dead, fade`; charger `phase='walk', pt, dx, dy`;
`shotCd = def.shotCd ? rand(0.3, def.shotCd) : 0`; unstick `stuckT, sideT, side`; `bob = rand(0, 2π)`; `shiny`;
`shield, shieldT`; `skillCd = rand(1, 4)`; `minions[]`; `jump`; `lagT`. Set elsewhere: `golden, legend, life, ai, zig,
jumpLift, los, losAt`.

**Damage intake** — see §4.5 (`hurt`: shield first, `d` displayed is **pre-shield**; bosses ignore hit knockback).
**Statuses**: burn (max 8 stacks, 3 s, tick 0.5 s `1.6*burn*(1 + pl.level*0.06)`), poison (max 8, 4 s, tick 0.6 s
`maxHp*0.012*poison + 1`), slow (`max(slow, f)`, 1.2 s default, speed × `(1 - slow)`). No stun/freeze. DoTs go through
`hurt` (shields absorb them).

**Terrain/weather** (`enemy.js:266-277`): only if `!flying && !legend` and standing in liquid (immune same types, §7):
water → ×0.55, swamp → ×0.45 (`terrainMul = le.slow < 0.5 ? 0.45 : 0.55`); lava/poison/spark → every `le.every` s
`hurt(6 + maxHp*0.04, le.color)`; ice → nothing. Snow: speed × `(1 - 0.1*level)` for non-ice. Sand/snow chip: §7.4.

Final speed: `spd * (1 - slow) * terrainMul * Weather.speedFor(types)`.

**`update(dt, pl)` order** (`enemy.js:235-398`; `pl` = nearest living player):
1. `seen = Camera.sees(x, y, 120)`; animate only if seen or dead; `flash -= dt`; dead → `fade -= dt`, return.
2. shiny twinkle every 0.22 s if seen. 3. `touchCd -= dt`, `bob += 6dt`. 4. statuses (may kill → return). 5. terrain.
6. `spd`, normalized `(dx, dy)` to player, `dist`. 7. thief branch (returns). 8. runner lead. 9. shield expiry.
10. jump in progress → `updateJump`, return. 11. bomber fuse. 12. shielder/jumper skill cooldown.
13. unstick: if `sideT > 0`, rotate dir by `side*1.25` rad. 14. pathing (non-flying, not dashing, not unsticking):
    `pd = Path.dirFor(this, pl)`; used unless the enemy keeps distance and `dist < range*0.82`.
15. velocity `dir*spd`, base anim `Walk`; boss / charger / keep-distance branches may override.
16. integrate: `x += kx*dt; kx *= 0.0015^dt` (same for y); `x += vx*dt`; if not flying `World.collide(this)`.
    Stuck: if collided, intended move `want > 0.5` and actual `got < want*0.35` → `stuckT += dt`; at `> 0.35` (and
    `sideT <= 0`) → `sideT = 0.7`, `side = ±1`, `stuckT = 0`.
17. anim: `moving = |vx|+|vy| > 2`; facing = dash dir / velocity / toward player;
    `anim.loop(moving ? base : 'Idle', moving ? max(0.6, spd/70) : 1)`.

### 5.5 Behaviors (exact)

`keepsDistance()` = ranged, fan, beamer, zoner, healer, summoner (`enemy.js:542`).

| Behavior | AI |
|---|---|
| `chase` / `tank` | walk to player using the flow field (tank only differs in stats) |
| `runner` | chase a predicted point: `lead = clamp(dist/max(60, spd), 0, 1.4)` s ahead along the player's smoothed velocity; dust FX `#e8dcc0` |
| `charger` | `walk` → when `dist < 200 && pt <= 0`: `aim` (`pt = 0.55`, `Charge` anim ×1.6, stands still) → `dash` (`pt = 0.42`, direction locked, velocity `dir*spd*3.4`, `Attack` ×1.4, ring `#ff6b6b`) → `walk` with `pt = 1.1` cooldown. No hazard telegraph. |
| keep-distance group | `range = def.range ‖ 200`, `keep = range*0.82`: `dist < keep*0.75` → retreat straight at `spd*0.8`; `dist < keep` → velocity ×0.1, `Idle`; else approach (pathing). Fire: `shotCd -= dt`; when `shotCd <= 0 && dist < range` → `shotCd = def.shotCd ‖ 2`, `special()` |
| `ranged` | `shoot(dx, dy)` — 1 bullet, k = 1 |
| `fan` | `shoot(dx, dy, spread = (n==3 ? 0.6 : 0.9), n = fanN, k = 0.65)` |
| `beamer` | hazard beam from its feet toward the player: `len 360, w 22, delay 1.0, dmg shotDmg()*1.05`; `Charge` ×1.2 |
| `zoner` | `randInt(1, zones)` hazard zones: first on the player, others offset `rand(±70), rand(±55)`; `r 44, delay 1.2, dmg shotDmg()*0.95`; `Shoot` |
| `healer` | `healAround()`: `pow = max(1, max over players of atk/baseAtk)`, `k = 0.07*min(2.5, pow^0.35)`; every live enemy within 150 (incl. itself) with `hp < maxHp` heals `maxHp*k`; green ring 150, sfx `heal` if on screen (every `shotCd` = 3.5 s, only within `range` of the player) |
| `shielder` | chases; every 6 s (`skillCd`) `castShields()`: 6 nearest live enemies within 160 (incl. itself) get `shield = max(shield, maxHp*0.35)`, `shieldT = 8`; blue ring 160 |
| `summoner` | `summon()` every 7 s within range: prune dead minions; abort if ≥ 4 alive or manager count > `CAP + 15` (79); spawn 2 minions at `(x + cos·30, y + sin·22)` with def `{dex: minion ‖ own, hp: round(def.hp*0.35), spd: round(def.spd*1.1), dmg: round(def.dmg*0.6), xp: max(1, round(def.xp*0.25)), behavior: 'chase'}` and the summoner's `sc` (no DMG_K/XP_K/elite/shiny/golden) |
| `jumper` | chases; when `skillCd <= 0`: if `dist < 250` → `skillCd = rand(5, 7)`, `startJump`: crouch 0.45 s (`Idle`), then lerp to the player's position over 0.6 s with `jumpLift = sin(kπ)*46` (ignores walls), land → collide, `Attack` ×1.4; hazard zone at target `r 50, delay 1.05, dmg*1.2`; else `skillCd = 0.5` |
| `bomber` | chases; when `dist < r + pl.r + 26`: `startFuse()` — stands still blinking for 1.0 s, hazard zone at itself `r 62, delay 1.0, dmg*1.4`, color `#ff7b3d`; then `hp = 0; die()` (**gives XP and counts as a kill**; the hazard still fires if it is killed earlier) |
| `thief` | flees zig-zag: `zig += dt`, angle `atan2(-dy, -dx) + sin(zig*2.2)*0.7`; speed ×1 if player within 300 else ×0.35; stuck → `zig += 1.4`; never deals contact damage; escapes after `life = 15` s |

**Enemy shots** (`shoot(ax, ay, spread=0, n=1, k=1)`, `enemy.js:547-561`): speed 190, `r 7`, life 2.4 s,
`dmg = shotDmg()*k` where `shotDmg() = (def.shotDmg ‖ 10) * (this.dmg/def.dmg)` (inherits time, DMG_K, elite and enrage
multipliers), `friendly: false`, `mtype = atkType`, visual `VFX.forType(type)` with a red ground ring; angles
`base + (i/(n-1) - 0.5)*spread`. Blocked by walls and any solid prop; hit the player at `dist < p.r + pl.r` (respects
i-frames). No cap on enemy projectiles.

### 5.6 Bosses (`enemy.js:408-540`)

- `flying = true` (no pathing/terrain) — except rift legendaries (`flying = false`, they path and collide).
- `bossInit`: `melee = ['slam', hash(dex,3,7) < 0.5 ? 'dash' : 'leap']`; preferred ranged by type: fire/ground/poison/
  rock/grass → `rain`; electric/psychic/dragon/ice/steel → `beam`; fairy/ghost/water/flying → `nova`; else `volley`;
  `ranged = [pref, others[floor(hash(dex,5,9)*3) % 3]]`; `farLike = behavior==='ranged' ? 0.65 : 0.35`; initial mode
  `far`/`close` by that probability; `modeT = rand(6, 8)`, `cd = 1.6`, `fury = false`, `side = ±1`.
- Enrage once at `hp < 50%`: `fury = true`, `spd *= 1.15` (permanent), banner "¡X se ha enfurecido!", red ring, kick 0.5.
  `k = fury ? 1.25 : 1`.
- Movement: `modeT -= dt; cd -= dt*k`; at `modeT <= 0` toggle mode, flip side, `modeT = rand(7, 9)` (favorite) or
  `rand(4, 5)`. Default velocity `dir*spd*k*1.1`; far mode: `dist < 170` flee at `spd`; `dist < 300` circle-strafe at
  `spd*0.55*side`.
- Attack choice at `cd <= 0`: close mode → melee allowed (`slam` if `dist < 125`, `dash`/`leap` if `dist < 320`) picked 80%
  of the time, else ranged if `dist < 480`; far mode → `slam` if `dist < 115`, ranged if `dist < 430`. Retries each frame.
- Casts (`bossStart`, `f = fury ? 0.8 : 1`; cast = `{id, t, wind: 0.6f, after: 0.35, ang}`; boss stands still (`Idle`)
  except dashing; ends at `wind + after`; `bossEnd`: `cd = rand(1.3, 2.0)`, with fury 35% chance `cd = 0.3`):

| id | wind | effect | damage |
|---|---|---|---|
| `slam` | 0.85f | hazard zone at boss `r = 96 + boss.r`, delay = wind; `Charge` then `Attack` | dmg×1.3 |
| `dash` | 0.75f | hazard beam `len 330 + r`, `w 2r + 16`, delay `wind + 0.32`; then moves 330 wu in 0.32 s | dmg×1.2 |
| `leap` | — | jump `{t: -0.5f, dur: 0.65}` (lift 46) to the player; zone `r 82`, delay `0.5f + 0.65`; `cd = rand(1.4, 2) + 0.6` | dmg×1.25 |
| `rain` | 0.5 | `fury ? 6 : 4` zones (first on player, others 40–120 away, y×0.8), `r 50`, delay `1.05 + 0.12i` | shotDmg×1.15 |
| `beam` | 1.0 | `fury ? 5 : 3` beams spaced `fury ? 0.42 : 0.5` rad, `len 400, w 26`, delay 1.0 | shotDmg×1.2 |
| `volley` | 0.5f | `shoot(spread 1.1, n = fury ? 9 : 7, k 0.8)` | shotDmg×0.8 |
| `nova` | 0.7f | `shoot(spread 2π(n-1)/n, n = fury ? 18 : 14, k 0.7)` (full ring) | shotDmg×0.7 |

Bosses get contact pushback (150) but not hit knockback; exempt from laggard relocation.

### 5.7 Hazards (telegraphed attacks, `js/systems/hazards.js`)

Shape `{kind: 'zone'|'beam', x, y, r | (angle, len, w), delay, dmg, type, color}`; `t` counts up; at `t >= delay` it
detonates once: if the player is inside → `pl.invuln = 0; pl.hurt(dmg, type)` (**ignores i-frames**, type chart and
weather apply); removed `0.3` s later. Hit tests: zone = **circle** `dist < r + 0.6*pl.r` (drawn as an ellipse
`r × 0.75r`); beam = along ∈ `[-pl.r, len + pl.r]` and `|perp| <= w/2 + 0.6*pl.r`. Fixed at creation position. Enemies are
never hurt by hazards. Telegraph drawing (world space, under entities): `k = min(1, t/delay)`; zone: full ellipse α .16,
inner ellipse scaled by k α .32, dashed `[4,4]` stroke width 2, α .95 if `k > .75` and blinking (`sin(now_ms/60) > 0`)
else .6; beam: rect α .14, inner rect height `w*k` α .34, dashed `[6,4]`. Color = type color. Detonation FX: zone →
ring + burst `round(r/3)`, sfx `break` (+ kick .35 if `r > 60`) if near view; beam → `FX.beam`.

### 5.8 Contact damage (`js/systems/combat.js:660-671`)

For each enemy in `queryCircle(pl.x, pl.y, pl.r + 40)` with `dist < e.r + pl.r`, `touchCd <= 0`, not a thief:
`touchCd = 0.55`; `e.strike(pl)` (`Attack` ×1.5 facing the player if not busy); `pl.hurt(e.dmg, e.atkType)`; Rocky Helmet
→ `e.hurt(15 + 4*level, '#9aa6b5', dir, 80)`; pushback `e.kx += nx*150, e.ky += ny*150` (bosses too).
Player and enemies overlap freely (no blocking).

### 5.9 Death and drops (`die()`, `enemy.js:154-197`; `pickup.js:72-94`)

`dead = true`, `fade = 0.9`, `Faint` held; burst 9 particles (34 boss); ring `r → 2.6r` (`6r` boss). Drops (authority only):

| Source | Drops |
|---|---|
| normal enemy | 1 gem of value `e.xp` (`xpBig` if `value >= 20`, else `xp`); `ticket` with p = 1/400; then one roll `r`: `< 0.012` heal, `< 0.020` magnet, `< 0.026` bomb |
| golden enemy | + 35% `coin` (3) |
| boss | `Camera.kick(0.9)`; 10 `coin` (5) within ±40/±30; 1 `item` (`Items.roll()`) at (−26, −10); 14 `xpBig` of `ceil(xp/14)` at random angle, distance 10–70; heal at +24x, magnet at −24x; `ticket10` with p = 1/3 |
| rift legendary | boss drops with `ticket10` p = 1/2, + 3 `ticket` + 10 `coin` (8) |
| thief | Meowth 20 `coin` (5); Gholdengo 6 `coin` (5) + `ticket10`; gold ring |
| minion | small `xp` gem (1–12) |

Then sfx `bossDown`/`faint`; shiny → extra burst + cyan ring + `G.onShinyCaught(e)`. Manager bookkeeping
(`enemy.js:906-915`): `pl.kills++`, `pl.bosses++` if boss, `G.Progress.kill(e)`, move to `corpses` (max 120; draw alpha
`clamp(fade/0.5, 0, 1)`; removed at `fade <= 0`).

### 5.10 Pickups (`js/entities/pickup.js`)

| kind | color / glow | r | value |
|---|---|---|---|
| `xp` | `#7fe0ff` / `#2a8fd0` | 4.5 | XP |
| `xpBig` | `#ffd95e` / `#c08a10` | 7 | XP |
| `heal` | `#5fe08a` / `#1f8f4d` | 6.5 | — |
| `magnet` | `#ff9ed8` / `#b03d84` | 6.5 | — |
| `bomb` | `#ff7b3d` / `#b03d10` | 6.5 | — |
| `coin` | `#ffd23f` / `#b8860b` | 5.5 | coins |
| `ticket` | `#ffd23f` / `#c08a10` | 7 | 1 |
| `ticket10` | `#c47bff` / `#8a3fd0` | 8 | 1 |
| `item` | `#ffd23f` / `#c08a10` | 9 | item id |

Effects on collect: §3.9. Physics (`pickup.js:101-150`): spawn with random velocity 10–46 wu/s; each frame `t += 4dt`;
nearest living player; if `pulled || d < pl.magnet` → `pulled = true` **forever** (sticky), speed
`pull = 240 + 1400/d` wu/s, `v = damp(v, dir*pull, 7, dt)`; else friction `v *= 0.02^dt`; integrate; **collect when
`d < 15`**. `pullAll()` sets `pulled` on every pickup in the map (items included). Cap `MAX = 420`: on overflow the oldest
XP gem is merged into the next-oldest XP gem (which becomes `xpBig`); if no XP gem exists the oldest pickup is dropped.
**Pickups never expire.** Draw (culled `sees(x, y, 30)`): shadow `0.9r × 0.35r` α .28; glow circle `2r` α .3; bounce
`|sin(0.8t)|*3` at `y - 6 - bounce`; XP = diamond (half-width `0.78r`) + white highlight; coin = spinning ellipse
(x-scale `max(0.25, |cos(0.9t)|)`); others = pixel icon 18 px (24 for `ticket10`/`item`; item adds a pulsing gold circle r 18).

### 5.11 Shiny encounters and "catching"

- Chance 1/4096 per normal/surge/burst spawn and per boss (only if the species has a shiny sheet); rift legendary 1/512;
  minions, thieves and lost Pokémon are never shiny.
- On spawn: `makeShiny()` (HP ×2 after elite, XP ×5), banner `'¡Un ' + name + ' shiny anda cerca!'` (EN "A shiny {x} is
  nearby!") 3.4 s, sfx `shiny`.
- While alive: cyan aura `#9ae6ff`, twinkles every 0.22 s, **never relocated/culled**, kept through the rift stash; HUD
  off-screen arrow (§9.2).
- **Catching = defeating it.** `G.onShinyCaught(e)` (`game.js:258-268`): `DB.grantShiny(dex, 'wild')` (also grants the
  normal form), `stats.shinies++`, commit immediately, add to the run summary; banner "¡Has conseguido a X shiny!" or
  "¡Otro X shiny! (+300 monedas)" (`pl.coins += 300`); sfx `shinyGet`. The shiny can then be chosen as partner skin.
- "Joins your team" messages also come from the **lost Pokémon rescue** event (20% chance, §7.3): "¡X se une a tu equipo!".

### 5.12 Enemy manager, spatial grid, laggards (`enemy.js:737-961`)

- Lists: `list` (alive), `corpses`, `byId`. Spatial hash: `CELL = 52` wu, `Map` keyed `cx*73856093 ^ cy*19349663`
  (collisions harmless), rebuilt every frame (twice). `queryCircle(x, y, r)` scans cells covering `[x-r, x+r]` ±1 cell and
  returns live enemies with `dist <= r + e.r`.
- `update(dt, players)` (`enemy.js:885-946`): (1) smoothed player velocity `p._vx += ((x - _px)/dt - _vx) * min(1, 5dt)`
  (reset if moved > 200 in a frame); (2) rebuild grid; update every enemy with its nearest living player (enemies appended
  mid-loop — minions — are updated the same frame); (3) `separate(dt)`: for each enemy check 3×3 cells,
  `min = (e.r + o.r)*0.82`, accumulate `n̂ * (min - d)/min`, apply `x += px*42*dt` then collide if walking (soft; bosses
  too); (4) reverse loop: dead → corpses; thief `life -= dt` → escape (no drop); **laggard logic** (skip bosses, shinies,
  arena): `R = outerRadius + 40`, `unseen = d > R && !sees(x, y, 60)`, `behind = |v| > 40 && (e - pl)·v < -0.2*dist*|v|`;
  `unseen && behind` → `lagT += dt`, `!unseen` → `lagT = 0`; if `(unseen && lagT > 2.5) || d > 1400` →
  `Spawner.ahead(e, pl)`: relocate to a free ring point at `atan2(_vy, _vx) ± rand(0.9)` (random if speed ≤ 20), reset
  `kx, ky, phase, pt, jump, jumpLift`; if no point → removed silently.
- `drawables(cam)` = corpses + alive within `sees(x, y, 80)`. `stash()/restore()` for the rift.

### 5.13 Pathing (`js/systems/pathing.js`)

Per-player **BFS distance field** (flow field): `R = 28` tiles → `N = 57`×57 cells centered on the player's tile
(±896 wu). `open[i] = World.walkable(tx, ty)` (not wall, not damaging liquid lava/poison/spark, no solid prop; water,
swamp, ice walkable; player's cell forced open). Rebuilt every 0.35 s per living player with a ring-buffer queue; 8-neighbor,
diagonal only if both orthogonal neighbors are open. `dirFor(e, pl)` → normalized direction or `null` ("go straight") when
no field, enemy tile outside, `dist <= 1` or unreachable; line of sight cached per enemy (re-evaluated at most every 200 ms
of **wall-clock** time): clear LOS → null. Else step to the lowest-distance neighbor (same corner rule), aiming at that
tile's center; if `clearLine(enemy → goal)` fails, aim at the center of the enemy's own tile first. `clearLine` samples
every `0.4*TS = 12.8` wu with 3 lateral offsets `{-w, 0, +w}`, `w = min(0.9r, 14.4)`.

### 5.14 Enemy drawing (`enemy.js:675-730`)

1. Aura (boss/shiny/golden, alive): ellipse `1.6r × 0.6r`, α `(golden && !boss ? 0.32 : 0.22) + sin(bob*0.5)*0.06`,
   color fury `#ff4a4a` > shiny `#9ae6ff` > golden `#ffd23f` > boss `#ffd95e`.
2. Shadow (§2.2, scaled). 3. Sprite at `y - lift`, `lift = (flying && !boss ? 1 + sin(bob)*1.5 : 0) + jumpLift`;
   white silhouette while `flash > 0`; alpha from corpse fade.
4. (alive only) shield bubble ellipse at `y - 0.45 bodyH`, `rx 1.5r, ry 0.65 bodyH`, fill `rgba(127,200,255,.14)`, stroke
   `#9fd8ff` 2 px, α `0.35 + sin(bob)*0.08`. 5. burn/poison ground ellipse `1.2r × 0.5r` α .45 (`#ff8a3d` / `#c86bdc`).
6. support icon (`heart`/`shield`/`friends`, 12 px) at `(x-6, y - bodyH - (damaged ? 26 : 18))`.
7. HP bar if boss or damaged: width `boss ? 90 : max(22, 2r)`, height 3.4 at `y - bodyH - 10`, bg `rgba(0,0,0,.6)`, fill
   `#ffcb3d` (boss) / `#ff5f6d`.

### 5.15 GDD vs code (code wins)

Cap 64 (GDD 280); elites trigger at ≥ 55 alive; healer heals 7%×min(2.5, pow^0.35) (GDD 15%); boss `ticket10` 1/3
(GDD "always"); legend 50% `ticket10` + 3 tickets (GDD "2"); ticket rate 1/400; boss stats ×1.35 HP ×1.2 dmg over slots;
overtime `late()` after minute 60.

---

## 6. Level-up cards

Source: `js/systems/levelup.js` (generation), `js/ui/run-ui.js:1-90` (screen, reroll), `js/game.js:319-338` (trigger).

### 6.1 Trigger

- XP gems → `pendingLevels += pl.gainXp(value)`; each frame, if `pendingLevels > 0 && state==='playing' && !pl.dead`:
  `pendingLevels--`, `state='levelup'`, sfx `levelup`, `G.RunUI.showLevelUp(pl.level, G.LevelUp.offer(pl), cb)`.
  The callback plays `confirm`, applies the card and returns to `'playing'`. One screen per frame; queued level-ups chain.
- Keys while the screen is open: `1`/`2`/`3` (and numpad) pick a card, `R` rerolls (`game.js:457-463`). Clicking/tapping a
  card also picks it.

### 6.2 Candidate pool (`levelup.js:31-105`) — weights `w`

| Card type | When offered | Count added to pool | Weight | Tag / color | Effect |
|---|---|---|---|---|---|
| `new` (learn move) | `pl.slots.length < 4` | up to **6** random ids (`pickN`) from `poolFor(mon)` minus known, minus banned (Veto), minus buff moves if the player already has ≥ 2 buff moves | **10** each | "Nuevo · <Type>" chip in type color | `pl.addMove(id)` (becomes the active slot unless a bond group is active) |
| `evo` (evolution) | a move at level 5 whose `needs` stat was taken ≥ 1 time (§4.7) | 1 per ready move | 40 (but forced, see 6.3) | gold `#ffd23f`, "EVOLUCIÓN", title "Old → New" | `G.Moves.evolve(m)`, gold ring/burst, sfx `legend`, `Progress.event('evolve')` |
| `up` (upgrade move) | every known move below level 5 | 1 per move | **8** | type color, "Nv.L > L+1" | `G.Moves.levelUp(m)` |
| `stat` | see below | up to 5 random stats + all "evolution-waiting" stats | **4** if a slot is free, **7** if all 4 slots are full; **14** if it unlocks an evolution | grey `#8fa3c4` "Mejora", or gold "Evoluciona <move>" | `s.apply(pl)`; `pl.statsTaken[id]++` |

Stat selection: `pickN(STATS.filter(s => !waiting[s.id] && room(s)), 5)` + every stat that some maxed move is waiting for
(those ignore the cap). `room(s) = !s.max || statsTaken[s.id] < s.max`.

### 6.3 Drawing 3 cards (`offer(pl, n=3)`, `levelup.js:108-126`)

1. If any `evo` card exists, the **first one** is taken unconditionally (gold card always shows).
2. Then weighted random without replacement until 3 cards or the pool is empty (`r = random()*total; walk until r <= 0`).
   Duplicate `key`s are skipped. Fewer than 3 cards is possible late in a run (everything maxed and stats capped).

### 6.4 Stat cards (`LevelUp.STATS`, `levelup.js:9-28`)

| id | Icon | Title (es) | Effect | Max times |
|---|---|---|---|---|
| `hp` | heart | Vigor | `addMaxHp(20)` (+20 max and current) | ∞ |
| `atk` | fist | Potencia | `atkMul *= 1.10` | 40 |
| `spd` | boot | Carrera | `spdMul *= 1.07` | 8 |
| `cd` | clock | Reflejos | `cdMul *= 0.92` | 10 |
| `def` | shield | Coraza | `dmgReduce = min(0.7, dmgReduce + 0.06)` | 12 |
| `rgn` | sprout | Síntesis | `regenFlat += 0.9` HP/s | ∞ |
| `mag` | magnet | Imán | `magnet *= 1.30` | 6 |
| `xp` | book | Aprendizaje | `xpMul *= 1.12` | 8 |
| `heal` | berry | Baya Zidra | `heal(maxHp * 0.45)` | ∞ (never an evolution need) |

Evolution needs reference these ids: `hp, atk, spd, cd, def, rgn, mag, xp` (§4.7).

### 6.5 Rerolls and bans

- Rerolls per run = `1 (free) + perks.rerolls` (permanent upgrade "Cambio de cartas", max 5) − `pl.rerolls` used
  (`run-ui.js:22-34`). Reroll regenerates a fresh `offer(pl)` (evo card again forced). Button hidden when 0 left.
- Ban ("Veto", permanent upgrade, max 3): banned move ids per Pokémon (`save.pban[dex]`, first `perks.bans` entries) are
  excluded from `new` cards (and from the "Repertorio" second starting move). There is no in-run ban/skip button.
- No "skip" card and no rarity tiers for cards besides the gold evolution card.

### 6.6 Card UI (DOM `#scr-levelup`)

Title "¡Nivel N!", 3 horizontal cards each with: icon (32 px, tinted background `color + '33'`), title + tag chip,
description, and the key hint `1/2/3`. Evo cards have class `evo` (gold border). Reroll button shows remaining count
(`#lvl-rr-n`). The game is fully paused (FX at quarter speed in the background).

---

## 7. World

Sources: `js/world/world.js`, `js/world/tiles.js`, `js/systems/{interact,events,weather,rift,hazards}.js`.
Units: `T = 16` art px per tile, `TS = 32` wu per tile, chunk `N = 16` tiles = `CW = 512` wu (`world.js:29-33`).

### 7.1 Shape, chunks, caches (`world.js:29-114`)

- **Infinite, unbounded** map, deterministic from `seed` (`reset(s)`: `seed = (s|0) || 1`, clears all caches,
  `world.js:550-554`). Run seed `floor(random()*1e6)`; menu seed 4242.
- Chunk **data** (`Map "cx,cy" → {cx, cy, terr: Uint8Array(256), props: [], propAt: Map "tx,ty" → solid prop,
  liquids: [tx,ty,…]}`) is generated on demand by any query; `MAX_DATA = 400`, FIFO eviction.
- Chunk **images** (256×256 art px canvases) only for visible chunks; `MAX_IMAGES = 48`, FIFO.
- `broken: Set "tx,ty"` = destroyed props (skipped when a chunk is regenerated). **Quirk**: other prop state (`used`,
  `charge`, `open`) is lost if chunk data is evicted (a used altar comes back fresh).
- Terrain enum: `FLOOR = 0, WALL = 1, LIQUID = 2`.

### 7.2 Noise and terrain (`util.js:32-39`, `world.js:50-87`) — port bit-exact

```
hash(x, y, seed) → [0,1)      (see §10.4 for the GDScript version + test vectors)
vnoise(x, y, s):  xi = floor(x), yi = floor(y), xf = x - xi, yf = y - yi
                  u = xf*xf*(3 - 2xf), v = yf*yf*(3 - 2yf)
                  a = H(xi, yi, s), b = H(xi+1, yi, s), c = H(xi, yi+1, s), d = H(xi+1, yi+1, s)
                  return (a + (b - a)u)(1 - v) + (c + (d - c)u)v
fbm(x, y, s)    = vnoise(x, y, s)*0.65 + vnoise(x*2.13 + 17, y*2.13 - 9, s + 1)*0.35
```
(`tx >> 1` in the arena rules is an arithmetic shift on int32 — GDScript `>>` matches for negative tile coords.)
`terrainRaw(tx, ty)` (tile coords):
1. If an arena is set and `arenaDist < arena.r + 7` → arena rules (§7.7).
2. `d = hypot(tx, ty)`; `d < 9` → FLOOR (start clearing); else `ramp = clamp((d - 9)/8, 0, 1)`.
3. `fbm(tx/13, ty/13, seed+101) < 0.04 + 0.23*ramp` → LIQUID (tested first).
4. else `fbm(tx/8, ty/8, seed+202) > 1 - 0.27*ramp` → WALL (rock formation).
5. else FLOOR.
The layout is identical in every biome; biomes only change palette and liquid kind.

### 7.3 Props (`placeProps`, `world.js:118-187`)

For each FLOOR tile (skip if `hypot(tx,ty) < 7` or broken); `open` = whole 3×3 neighborhood FLOOR. First match wins:

| Step | Condition | Prop |
|---|---|---|
| 1 | `open && hypot > 12 && hs < 0.0032`, `hs = H(tx,ty,seed+909)` | `hs < 0.0004` altar · `< 0.0008` spring · `< 0.0011` bigchest · else trap; `kind = floor(H(tx,ty,seed+910) * (altar ? 4 : 3))` |
| 2 | `open && h < (grove ? 0.07 : 0.006)`, `h = H(tx,ty,seed+404)`, `grove = fbm(tx/10, ty/10, seed+505) > 0.6` | tree |
| 3 | `open && h > 0.992` | rock |
| 4 | `open && 0.985 < h <= 0.992 && H(tx,ty,seed+606) < 0.07` | chest |
| 5 | `fbm(tx/5, ty/5, seed+707) > 0.66 && H(tx,ty,seed+808) < 0.75` (no `open` needed) | tall grass |

`PROP` table (`world.js:165-174`):

| type | solid | hp | r (wu) | flat | art size (×2 in world) |
|---|---|---|---|---|---|
| tree | yes | ∞ | 13 | no | tree 30×40 / crystal 26×40 / deadtree 28×40 (by biome `prop`) |
| rock | yes | 34 | 12 | no | 22×17 |
| chest | yes | 22 | 12 | no | 16×14 |
| grass | no | 1 | 14 | no | 20×17 |
| altar | yes | ∞ | 9 | no | 18×27 |
| spring | no | ∞ | 22 | yes | 34×16 |
| bigchest | yes | ∞ | 14 | no | 24×20 |
| trap | no | ∞ | 9 | yes | 14×14 |

`makeProp`: position `x = tx*32 + 16`, `y = ty*32 + 28`; fields `destructible = hp != ∞`, `flash`, `wiggle =
H(tx,ty,9)*2π`, `used = false`, `charge = 1`, `open = 0`, `id`, `kind`. Only solid props are indexed in `propAt`.

**Prop damage & loot** (`damageProp`/`destroyProp`, `world.js:340-411`): `hp -= amt`, `flash = 0.08`, spark FX; at 0 →
`broken.add`, sfx `grass`/`chest`/`break`:

| prop | loot |
|---|---|
| grass | 5% heal; else 6% coin(1) |
| rock | 40% `dropXp(6)`; same roll `r > 0.75` coin(2), `r > 0.94` heal |
| chest | 4–7 coins(3), 50/50 heal or magnet, `dropXp(20)`, 8% item; gold burst, kick .25 |
| bigchest | 9 coins(4), 1–3 tickets, 15% ticket10, 50% item, `dropXp(G.Game.levelXp())` (exactly one level), `Progress.event('chest')`; kick .4 |
| trap | `Interact.trapEffect(p)` |

Enemies never damage props. Player auto-aims at `nearestBreakable(x, y, 200)` (solid destructible: rock, chest) when no
enemies are near.

### 7.4 Biomes (`tiles.js:12-131`, `game.js:558-565`, `world.js:562-571`)

`G.Tiles.BIOMES` = 3 overworld palettes + 18 arena palettes (one per type, `arenaBiome(theme)`) = **21 entries**.

| idx | name | liquid | tree sprite | floor[0] / wallTop[0] / liq / foam |
|---|---|---|---|---|
| 0 | Bosque Umbrío | water | tree | `#3e7a39` / `#5d6e49` / `#3b7fc6` / `#b3defa` |
| 1 | Cueva Cristal | water | crystal | `#4d5778` / `#5f5089` / `#2a9cab` / `#aaf4f7` |
| 2 | Volcán Ceniza | lava | dead | `#5b4537` / `#3c3634` / `#e45a1f` / `#ffd46a` |
| 3–20 | `'Grieta · ' + theme.name` (normal, fire, water, grass, electric, ice, fighting, poison, ground, flying, psychic, bug, rock, ghost, dragon, dark, steel, fairy) | theme.liquid | theme.prop | derived |

Full palette fields: `floor[3], dirt[3], speck, light, flowers[3], wallTop[3], wallLight, wallEdge, wallFace[2],
wallFaceDark, liq, liqDeep, foam, shore, prop, leaf[4], trunk[2], rock[3], grass[3]` (exact hex in `tiles.js:12-37`).
`arenaBiome(th)` derivation (`tiles.js:116-130`) with `shade(hex,k)` = `k ≥ 0 ? v + (255-v)k : v(1+k)` per channel:
`floor = [f, shade(f,.05), shade(f,-.06)]`, `dirt = [shade(f,-.16), shade(f,-.12), shade(f,-.2)]`, `speck = shade(f,-.25)`,
`light = shade(f,.22)`, `wallTop = [w, shade(w,.07), shade(w,-.07)]`, `wallLight = shade(w,.32)`, `wallEdge = shade(w,-.7)`,
`wallFace = [shade(w,-.3), shade(w,-.38)]`, `wallFaceDark = shade(w,-.55)`, `liqDeep = shade(L,-.22)`,
`foam = th.foam ‖ shade(L,.55)`, `shore = shade(f,-.32)`, `leaf = [shade(l,-.35), shade(l,-.15), l, shade(l,.3)]`,
`trunk = [shade(t,-.2), t]`, `rock = [shade(r,-.2), r, shade(r,.22)]`, `grass = [shade(g,-.28), g, shade(g,.28)]`.

**Biome per run**: starts at 0 (no fade); `b = floor(time/240)` → `setBiome(b)` uses `b mod 21`, so a run **cycles through
all 21 palettes every 4 minutes** (from minute 12 the overworld uses arena palettes and their liquids — e.g. minute 16 is
the fire palette with lava). Music still follows `BIOME_MUSIC[b % 3]`. **GDD says "3 biomes rotate" — code differs.**
On change: sfx `biome`, banner `'— name —'` 3 s, white ring. No enemy-type affinity per biome; biome affects palette,
liquid kind, weather weights (`b % 3`), music.

**Crossfade** (`FADE = 2.6` s): keep the old chunk image cache; draw old then new at `alpha = smoothstep(t/2.6)`; props
old at `1-k`, new at `k`. Menu backdrop cycles 0→1→2 every 30 s.

### 7.5 Collision and queries (`world.js:224-336`) — custom math, no physics engine

- `collide(e)` (player, walking enemies, lost Pokémon, wanderers): **2 passes**; for each tile in the AABB `[x±r, y±r]`:
  WALL tile → closest point `q` on the tile box; if `d < r` push out along `(e - q)` by `r - d`; if the center is inside,
  eject through the nearest side. Solid prop on the tile → circle–circle push to `p + n*(r + p.r)` (zero distance → 0.01).
  Returns `hit`. **Liquids never block movement.**
- `isFree(x, y, r=12, allowLiquid=false)`: false if any tile in the AABB is WALL, LIQUID (unless allowed), or holds a solid
  prop overlapping `r + p.r`.
- `walkable(tx, ty)` (pathing): not WALL, not damaging liquid, no solid prop.
- `projectileBlock(x, y, r)`: `'wall'` if the tile is WALL, else any solid prop in the 3×3 tiles with `dist < r + p.r`,
  else null. Enemy shots: destroyed by walls and **any** solid prop (cover). Player shots: destroyed by walls and
  indestructible solid props (tree, altar, bigchest); rocks/chests take damage and consume pierce; grass is cut but never
  stops a shot; each projectile hits a prop once.
- `propsInCircle(x, y, r)`: destructible props with `hp > 0` overlapping. `isLiquid(x, y)`: tile under the feet point.

### 7.6 Liquids (`world.js:196-215`)

| kind | effect | immune types | where |
|---|---|---|---|
| water | slow 0.6 | water | biomes 0, 1; arenas normal/water/fighting/flying/psychic/rock/ghost/dark/steel/fairy |
| swamp | slow 0.45 | water | arenas grass, ground, bug |
| lava | dmg 0.06, flat 5, every 0.5 s, `#ff8a3d` | fire | biome 2; arenas fire, dragon |
| poison | dmg 0.035, flat 3, every 0.5 s, `#c86bdc` | poison, steel | poison arena |
| spark | dmg 0.045, flat 4, every 0.7 s, `#ffe14d` | electric, ground | electric arena |
| ice | slide | ice | ice arena |

Player: speed × `slow`; damaging: every `every` s `invuln = 0; hurt(max(flat, maxHp*dmg*0.5))` (untyped); ice: slippery
velocity (§3.4). Enemies: water ×0.55 / swamp ×0.45; damaging → `6 + 4% maxHp` (ignores `dmg`); ice none; flying and
legendaries unaffected. Immunity if any of the Pokémon's types is listed.

### 7.7 Ground & prop rendering (procedural; `tiles.js:180-619`, `world.js:415-539`)

**Ground**: each chunk is painted into a 256×256 art-px RGBA buffer and drawn at `CW + 1 = 513` wu (1-wu overlap hides
seams). **Every pixel depends only on its tile, the 8 neighbor terrain kinds and a continuous dirt field** — so it is
shader-portable. Hash seeds below are constants unless noted (`gx, gy` = global art-px coords).

- Dirt mask: `F(gx,gy) = fbm(gx/96, gy/96, seed+303)` sampled on a 4-px lattice and bilinearly interpolated, plus
  `(H(gx>>1, gy>>1, seed+9) - 0.5)*0.05`; dirt if `> 0.64`.
- `paintFloor`: `band = H(gx>>3, gy>>3, 11)*0.7 + H(gx, gy, 12)*0.5`; `col = pal[min(2, floor(band*3/1.2))]` (pal = dirt or
  floor); `r = H(gx,gy,13)`: `< 0.035` speck, `> 0.985` light; dirt top edge → speck; grass just below dirt with
  `r < 0.5` → light; wall directly north → row 0 `wallFaceDark`, row 1 speck where `(x+ty)%2`. Per-tile detail
  `d = H(tx,ty,14)`, anchor `dx = 3 + floor(H(tx,ty,15)*10)`, `dy = 4 + floor(H(tx,ty,16)*9)`: dirt tile (> 128 dirt px):
  `d < 0.22` 2×2 pebble; else `d < 0.18` tuft (5 light + 1 speck), `d < 0.26` "+" flower in
  `flowers[floor(H(tx,ty,17)*3)]` with light center, `d < 0.32` pebble.
- `paintWall` (2.5D): neighbors n/s/w/e; `FACE = s ? 0 : 6` front-face rows at the bottom; rounded outer corners (NW/NE when
  corner sum < 3, SW/SE when < 2, only if both adjacent sides open); face streaks
  `wallFace[((x + (H(gx,0,21) < .5 ? 0 : 1)) % 3 == 0) ? 1 : 0]`, first face row `wallEdge`, last `wallFaceDark`, 8% random
  `wallFaceDark`; top `wallTop[floor(H(gx>>1,gy>>1,23)*2.2 + H(gx,gy,24)*0.8) % 3]` with 5% `wallLight`; no wall north →
  row 0 `wallEdge`, row 1 `wallLight`; no wall west/east → column 0/15 `wallEdge`.
- `paintLiquid`: outer corners skipped when corner sum < 3; `d` = distance to shore (min over open sides, inner-corner arcs
  `hypot(...) - 0.5`); bands: `d < 1` shore, `< 2` foam, `< 4` liqLight = mix(liq, foam, 0.28), `< 6` (`r < .5` ? liq :
  liqLight), else (`d < 8 && r < .5` ? liq : liqDeep), + 8% liq speckle where `d ≥ 6` (`r = H(gx,gy,31)`); waves where
  `d ≥ 3 && H(gx>>2, gy, 33) < 0.045 && (gx & 3) != 3` → liqLight; glints `H(gx,gy,34) < 0.004` → foam.
- **Liquid shimmer** (every frame, real time `t`): per visible liquid tile `ph = H(tx,ty,77)*2π`,
  `k = (sin(t*(hot ? 2.2 : 1.6) + ph) + 1)/2` (hot = lava/poison/spark); α `hot ? 0.35 + 0.5k : 0.7k`, color foam; rect at
  `(x + (floor(H(tx,ty,78)*12 + 2) + round(2k))*P, y + floor(H(tx,ty,79)*12 + 2)*P)`, size `(hot ? 2 : 3)P × P`; hot &&
  `k > 0.8` → extra 1×1 bubble 2P higher.

**Props** are painted in code into small canvases cached by `"biome/type/variant"` (1-px dark outline, top-left light):
tree (6 leaf blobs, 4 shades, 12% dither, trunk), crystal (3 spires), dead tree (trunk + 4 branches), rock (variant 1 =
cracked when `hp < 50%`), grass (11 blades; variant toggles when `sin(t*2.4 + wiggle) > 0.55` — sway), altar
(variant `kind*2 + used`, orb in `['#ff5f6d','#5fd4ff','#ff8ad8','#ffd23f'][kind]`, grey when used), spring (variant 1 dry
when `charge < 0.15`), bigchest (gold padlock), trap (variant = kind: purple skull / green drops / orange mine), chest,
rift (4 animated frames, 30×46). Placement: non-flat → shadow ellipse `1.1r × 0.38r` α .3 (not grass), sprite at
`(round(x - w/2), round(y - h + (grass ? 4 : 2)))`; flat → centered at `(x, y - 8)`. Altar halo (unused): circle r 13 at
`(x, y - h + 22)`, α `0.22 + 0.1 sin(3t + wiggle)`. Bigchest progress ring: arc r 26, `#ffd23f` width 3, sweep
`360° * open/3.5`. Spring sparkle twinkles. Hit flash: white silhouette α 0.6 while `flash > 0`.

**Vignette** (every frame incl. menu, `world.js:576-582`): radial gradient centered, transparent at `0.34*min(w,h)` →
`rgba(0,0,0,.5)` at `0.78*max(w,h)`. No day/night cycle, no lighting. No minimap; off-screen indicators are HUD arrows.

### 7.8 Interactables (`js/systems/interact.js`) — proximity only, no keys, no costs

`Interact.update(dt, pl)` scans `World.specialsNear(pl.x, pl.y, 720)`; distance to `(x, y)` (spring/trap: `(x, y-8)`).

| Interactable | Trigger | Behavior |
|---|---|---|
| Altar (kind 0–3) | `dist < max(30, p.r + pl.r + 14)`, unused | `used = true`; `pl.addPower(POWERS[kind], 25)` (replaces any active power); banner `'¡Poder ' + name + '! ' + desc + ' durante 25 s'`; sfx `legend` |
| Spring | `dist <= 26` | `charge += dt/45` (recharges 0→1 in 45 s whenever within the 720 scan); heals if `charge > 0.02 && hp < maxHp`: `+14% maxHp/s`, `charge -= 0.09*dt`; `+N` text every ≥ 0.6 s (sfx `xp`); at ≤ 0.02 banner "El manantial se ha secado (se recarga solo)" |
| Locked chest (bigchest) | `dist < max(46, p.r + pl.r + 24)` | sfx `select` on start; `open += dt`; at `open >= 3.5` breaks → loot (§7.3); out of range `open` decays at `1.5*dt`; enemies keep attacking |
| Trap (0 poison, 1 sticky, 2 explosive) | player `dist < 13`, or any walking enemy touching a 3-px circle at `(x, y-8)` | `World.breakProp(p)` → `trapEffect` |

Altar powers: `dmg` Furia `atkMul ×2` `#ff5f6d`; `spd` Rayo `spdMul ×1.45` `#5fd4ff`; `mag` Imán `magnet ×4` `#ff8ad8`;
`cd` Prisa `cdMul ×0.6` `#ffd23f` (25 s, reverted by `off`).
`trapEffect(p)`: center `(x, y-8)`, `TRAP_R = 74`, colors `['#c86bdc','#8bd94a','#ff7b3d']`; enemies within `74 + e.r`:
poison → `applyPoison(5)` + `hurt(14 + 3*lvl)`; sticky → `applySlow(0.65, 4.5)` + `hurt(4)`; explosive →
`hurt(90 + 18*lvl)` knock 220. Player within 51.8 (= 74*0.7): `invuln = 0`, then poison `hurt(10% maxHp)`, sticky
`slowT = 3.5` (speed ×0.5, text "¡Pegajoso!"), explosive `hurt(20% maxHp)`. One-shot (recorded in `broken`).

### 7.9 Events (`js/systems/events.js`)

Constants: `EVERY = [240, 300]`, `DUR = 30`, `LOST_TIME = 120`, `THIEF_FIRST = [120, 240]`, `THIEF_NEXT = [240, 360]`,
`THIEF_LIFE = 15`. Never while in the arena.

- Scheduling: on reset `nextT = rand(240, 300)`, `thiefT = rand(120, 240)`. The event countdown runs only while no event is
  active; at ≤ 0 (boss alive → retry in 10 s) `nextT = rand(240, 300)` and start a random event from
  `['horde', 'gold', 'lost']` **excluding the previous one**. Thieves (max **2 per run**): at `thiefT <= 0` (boss alive →
  retry 8 s) spawn, `thiefT = rand(240, 360)`.
- **Horde** (30 s): `types = Enemies.hordeTypes(time)` (empty → falls back to gold); random type; `defs = hordeDefs(type)`;
  `Spawner.burst(6)` from one side; all spawns come from `defs` for 30 s. Banner `'¡Horda de tipo ' + TYPE + '!'`, sfx
  `surge`. HUD countdown `'HORDA <TYPE> · Ns'` (type color) at `(w/2, 112)`.
- **Golden hour** (30 s): all current enemies `makeGolden()`, and new spawns too (xp ×2, 35% coin(3) on death, gold
  ground ellipse). Banner "¡Hora dorada! Doble de experiencia", sfx `shiny`. HUD `'HORA DORADA · Ns'` `#ffd23f`.
- **Lost Pokémon** (no fixed duration): pool `rarity <= 3`, not legendary, has sprite, not hovering; spawns 220–300 wu from a
  random living player (y×0.8, `isFree(16)`, 20 tries); goal 700–850 wu from the spawn (y×0.85, `isFree(30)`, 30 tries);
  either fails → no event. `hp = 100`, `grant = random() < 0.2`. Banner "¡Un X se ha perdido! Búscalo y llévalo a la marca".
  States: `wait` → a player within `o.r + L.r + 18` → `follow` ("¡X te sigue! Llévalo a la marca verde", sfx `confirm`):
  keeps a gap `p.r + L.r + 14`, steps `min(d - keep, max(120, p.spd*1.15)*dt)`, collides with terrain. Rescued within 56 wu
  of the goal. Damage every 0.5 s while touched by non-thief enemies: `hp -= min(30, Σ(4 + 0.12*e.dmg))`; 0 HP → "¡X se ha
  asustado y ha huido…!". Timeout 120 s from spawn → "X se ha cansado de esperar y se ha ido…". Reward: 12 coins(5) around
  the goal + 1 ticket; player heals 50% maxHp; sfx `legend`; if `grant` → `G.onRescue` (joins collection if new, else +150
  coins), else "¡Has llevado a X a casa! Te lo agradece". Drawing: goal ellipse 56×40 fill `#5fe08a` α `.25 + .15k`, dashed
  `[6,5]` `#7dffb0` stroke, bobbing heart icon, sorted at `y - 4000`; the Pokémon has a green ellipse, shadow, Walk/Idle
  sprite, bouncing "!" while waiting, HP bar 30×3.4 `#5fe08a`.
- **Treasure thief**: 25% Gholdengo (dex 1000, loot ticket10) else Meowth (dex 52, loot coins);
  `hp = round(60*(1 + t/95)*(gold ? 1.5 : 1))`, `spd 92`, `dmg 0`, `xp 10`, behavior `thief`, `sc = {1,1,1}`; spawns
  230–300 wu away (12 tries, `isFree(14)`); banner "¡Un X cargado de monedas! ¡Atrápalo antes de que huya!" (or "… con un
  ticket ×10! …"); escapes after 15 s ("¡X se ha escapado!"); gold HUD edge arrow.

### 7.10 Weather (`js/systems/weather.js`)

| key | name | icon | color | tint rgba | damage mult | extra |
|---|---|---|---|---|---|---|
| sun | Sol abrasador | wsun | `#ffcb3d` | 255,190,90 @ .07 | fire 1.5, water 0.5 | — |
| rain | Lluvia | wrain | `#7fb8ff` | 50,90,170 @ .09 | water 1.5, electric 1.2, fire 0.5 | — |
| sand | Tormenta de arena | wsand | `#e0bf73` | 200,160,90 @ .09 | rock/ground/steel 1.3 | `safe: rock, ground, steel` → chip |
| snow | Nevada | wsnow | `#d8f1ff` | 210,230,255 @ .08 | ice 1.5 | `safe: ice` → chip; slow |
| fog | Niebla | wfog | `#c9cfdc` | 190,195,210 @ .12 | ghost/fairy/psychic 1.3 | closes vignette |

- Trigger: not in arena, `time > 120`, none active; `checkT` counts down from 60 (frozen while active); each check rolls
  `0.18`. Kind weighted by `BIOME_W[biome % 3]`: 0 `{rain 3, fog 2, sun 1.5, snow .5, sand .5}`, 1 `{fog 3, snow 2.5,
  rain 1, sand 1}`, 2 `{sun 3, sand 3, fog 1}`. Duration `round(rand(55, 75))` s. Start: banner `name + ': ' + hint`
  3.4 s, sfx `biome`. `force(kind, dur)` (arena), `stop()` (fade 3 s), `clear()`.
- Intensity `level = min(1, t/3, (dur - t)/3)`. `mult(type) = 1 + (m - 1)*level` for listed types (both directions of
  combat). `speedFor(types)`: snow & not ice → `1 - 0.1*level` (player and enemies).
- Chip every 2 s while `level > 0.5` (sand/snow): player not of a safe type: `d = max(1, 1.2% maxHp)` applied directly
  (bypasses i-frames/reduction) only if `hp > d + 1` (never KOs), text in the weather color; enemies (non-boss, not safe):
  `hp -= 2% maxHp + 1`, `flash .05` (**can kill**).
- Visuals (screen space, before the vignette): tint rect `rgba(r,g,b, a*level)`; particles `want = {rain 70, snow 45,
  sand 40, sun 14, fog 0} * level * (w/1280)`, pixel size `s = max(2, round(w/640))`, advanced by `frameDt` (frozen when
  paused): rain spawn x∈[0, w+200], y=-10, v (−120, 720), α .5 `#cfe2ff`, 4 stacked `0.5s × 1.5s` rects (stair streak),
  life 9; snow x∈[0,w], v (±20, 40–80), α .7 white `s×s`, life 20; sand x = w+20, y∈[0,h], v (−520…−380, 20–60), α .4
  `#e8cf8f` `3s × 0.5s`, life 9; sun from bottom, v (±8, −15…−30), α .45 `#fff1b0` `s×s`, life 12. Fog vignette: §1.6.
  HUD chip top-right `NAME · Ns`.

### 7.11 Rifts and legendary arenas (`js/systems/rift.js`)

Constants: `CHECK = 30`, `CHANCE = 0.2`, `TTL = 45`, `ARENA_R = 11` tiles, `ARENA_TIME = 120`, `FROM = 75`.

- **Opening**: when no rift/arena and `time > 75`; every 30 s (skipped, not counted, while a boss is alive) roll
  `random() < 0.2*(1 + misses)` (20/40/60/80/100%); success resets `misses`. Placement 380–560 wu from a random living
  player (y×0.85, `isFree(22)`, 24 tries). `rift = {x, y, ttl: 45, t}`; sfx `rift`, purple ring. GDD says 14% — code wins.
- **Entering**: player within **30 wu of `(x, y-10)`** — no key. Rift vanishes at `ttl <= 0`.
- **Drawing**: purple ellipse `#7b3cff` 34×12 α `.25*fade`; 4-frame sprite at 8 fps at `(x - w/2, y - h + 4)`;
  `fade = min(1, 2t)*min(1, ttl/1.5)`; 30%/frame rising lilac particle `#d9c2ff`. HUD: big pulsing off-screen arrow
  `'GRIETA · N m · N s'` (m = dist/32), on-screen bouncing arrow, 4.5 s popup "¡SE HA ABIERTO UNA GRIETA!" (§9.2).
- **Legendary choice**: `DEX` with `leg` and sprites; weight 4 if not yet beaten (`save.legends`), 1 if beaten;
  `cfg = {tx: 5000 + rand(0..2999), ty: same, r: 11, dex, shiny: hasShiny && random() < 1/512, type: random one of the
  legendary's types}`.
- **begin()**: center `(tx*32 + 16, ty*32 + 16)`; save return position and biome; `EnemyMgr.stash()`; clear projectiles,
  fields, hazards; `World.setArena({tx, ty, r, type})` (purges cached chunks within `r + 9 + 16` tiles);
  `setBiome(arenaBiome(type), instant)`; `Weather.force(theme.weather, 135)` if the theme has one (otherwise overworld
  weather continues — quirk); teleport player to `(cx, cy + 96)`; flash `#c9a6ff` 0.9 s, sfx `rift`, banner "Has entrado en
  la grieta…".
- **Legendary** (`spawnLegend`, `rift.js:137-162`), `t` = run time, `lk = late(t)`:
  `hp = round((3200 + 9t)*lk)`, `spd = round(clamp(48 + (mon.spd - 78)*0.6, 48, 105))`, `dmg = round((36 + t/20)*lk^0.7)`,
  `xp = round(500 + 1.2t)`, behavior `ranged` if any type ∈ {psychic, electric, ghost, fairy, fire, water, ice, dragon}
  else `charger`, `shotDmg = round((18 + t/40)*lk^0.7)`, `shotCd 0.9`, `range 300`; spawned as a **boss** at
  `(cx, cy - 112)` with `legend = true`, `flying = false`; banner "¡X te esperaba en la grieta!", kick 1.1, sfx `boss`.
- **Arena terrain** (`world.js:62-87, 130-141`), `ad` = tile distance from center, `(lx, ly)` offset: wall ring
  `r <= ad < r + 7`; safe corridor `|lx| <= 2 && -6 <= ly <= 5` or `hypot < 2.5` (always floor, no props); pillars:
  `th.pillars && ad < r - 2 && H(tx>>1, ty>>1, seed+31+arena.tx) < th.pillars` (2×2 blocks); pools:
  `th.pools && ad < r - 1.5 && fbm(tx/3.2, ty/3.2, seed+37+arena.tx) < th.pools` → liquid; props for `ad < r - 1.2`
  (outside corridor, `hh = H(tx,ty,seed+777)`): tree if `open && hh < pr.tree`, rock if `open && hh < tree + rock`, grass if
  `hh > 1 - pr.grass`; no interactables.

| type | arena name | liquid | pools | pillars | props | weather |
|---|---|---|---|---|---|---|
| normal | Pradera Eterna | water | 0 | .035 | tree .025, grass .05 | — |
| fire | Volcán Ígneo | lava | .31 | .03 | tree .01 | sun |
| water | Gruta Marina | water | .33 | .02 | tree .015 | rain |
| grass | Selva Esmeralda | swamp | .22 | 0 | tree .05, grass .12 | — |
| electric | Central Voltio | spark | .28 | .04 | tree .01 | rain |
| ice | Glaciar Eterno | ice | .36 | .02 | tree .02 | snow |
| fighting | Dojo Ancestral | water | 0 | .075 | tree .008 | — |
| poison | Ciénaga Tóxica | poison | .31 | .015 | tree .02 | — |
| ground | Desierto Rojo | swamp | .25 | .04 | tree .01, rock .015 | sand |
| flying | Pico Celeste | water | 0 | .02 | tree .025 | — |
| psychic | Templo Mental | water | 0 | .045 | tree .02 | — |
| bug | Bosque Colmena | swamp | .2 | 0 | tree .04, grass .12 | — |
| rock | Cantera Antigua | water | 0 | .08 | rock .03 | sand |
| ghost | Cementerio Sombrío | water | 0 | .03 | tree .03 | fog |
| dragon | Santuario Dragón | lava | .22 | .04 | tree .015 | — |
| dark | Callejón Oscuro | water | 0 | .05 | tree .02 | — |
| steel | Fortaleza de Acero | water | 0 | .08 | tree .01 | — |
| fairy | Bosque Encantado | water | .16 | 0 | tree .05, grass .1 | — |

(Theme colors `floor, wall, liq, foam?, prop, leaf, trunk, flowers[3], grass, rock` at `tiles.js:52-105`.)

- **Rules inside**: no spawns, events, thieves, weather rolls or rift checks; no laggard relocation; bond offers postponed;
  run clock keeps running; solo death does **not** end the run. `keepInside()` clamps every enemy to `(r - 1.4)*32 = 307.2`
  wu from the center (players are held by the walls). HUD `'GRIETA · m:ss'` (time left of 120 s).
- **Win** (legendary dead): `phase = 'won'`, `endT = 5`; `Progress.event('rift', {type})`; `Pickups.pullAll()`; banner
  "¡Has vencido a X! Recoge el premio…", sfx `legend`; `pl.bonds++` (text "¡Vínculo!" `#ff8ad8`); legendary drops (§5.9);
  `save.legends[dex]` recorded. **The legendary is not added to the collection.**
- **Loss**: player dead for > 1.4 s or `arena.t > 120` → `phase = 'lost'`, `endT = 1.2`, banner "La grieta os ha
  expulsado…", sfx `back`.
- **finish()**: restore previous biome instantly, `Weather.clear()`, `EnemyMgr.restore()`, clear projectiles/fields/hazards,
  teleport back; if dead `revive(0.3)` (30% HP, invuln 2 s); flash `#c9a6ff` 0.8 s; `offerBond()` if bonds > 0. A 4-minute
  biome boundary crossed while inside applies next frame. (`World.setArena(null)` is never called — harmless quirk.)
- Float precision: arena coordinates are 160k–256k wu; fine for float32 positions but compute noise from integer tile/pixel
  coordinates (or relocate the arena closer, e.g. tile offset 2000).

---

## 8. Meta-progression (outside runs)

### 8.1 Save data (`js/core/db.js`)

Storage is **localStorage JSON only** (no IndexedDB): `read/write` at `db.js:52-60`, try/catch-wrapped; on failure the game
keeps playing from memory. Constants (`db.js:34-40`): `VERSION = 3`, `START_COINS = 500`, keys `ps.accounts`,
`ps.session`, `ps.save.<lowercaseName>`, `ps.guest`, `ps.guest.session`, `ps.cloud.<uid>` (cloud cache — drop),
`ps.migrated.*`.

**`newSave(name)`** (`db.js:64-91`):

| Field | Type | Default | Meaning |
|---|---|---|---|
| `v` | int | 3 | save version |
| `name` | str | arg | display name |
| `created` | ms | now | creation time — **also the per-account mission seed** (§8.6); keep stable |
| `updated` | ms | now | bumped on each `commit()` |
| `coins` | int | 500 | Pokémonedas |
| `owned` | `{dex: {at, from}}` | `{}` | collection; `from` ∈ `starter, gacha, wild, rescue` |
| `shiny` | `{dex: {at, from}}` | `{}` | shiny variants (granting a shiny also grants the normal form) |
| `partner` | int\|null | null | dex you play; `null` ⇒ personality test on login |
| `partnerShiny` | bool | false | use shiny skin (only if owned) |
| `starter` | int\|null | null | dex picked in the test |
| `personality` | `{trait, scores}`\|null | null | test result |
| `upgrades` | `{id: lvl}` | `{}` | legacy account-wide upgrades (migration only) |
| `pupg` | `{dex: {upgradeId: lvl}}` | `{}` | **per-Pokémon permanent upgrades** |
| `tickets` | `{t1, t10}` | `{0,0}` | gacha tickets (single, ×10) |
| `pity` | `{gen: int}` | `{}` | pulls since last 5★ per banner |
| `legends` | `{dex: ms}` | `{}` | legendaries defeated in rifts |
| `arenas` | `{type: ms}` | `{}` | rift arenas won (one per type) |
| `itemsFound` | `{itemId: ms}` | `{}` | held items ever equipped |
| `evoMoves` | `{moveId: ms}` | `{}` | moves ever evolved |
| `ach` | `{achId: ms}` | `{}` | unlocked achievements |
| `missions` | obj | `{}` | `{day:'dYYYYMMDD', rerolled, daily:[M×3], week:'wYYYY-WW', weekly:[M×2]}`, `M = {id, goal, param, prog, claimed, told}` |
| `profile` | `{favs:[{dex,shiny}]≤3, title}` | `{[], ''}` | public profile (keep locally; titles are cosmetic) |
| `stats` | obj | all 0 | `runs, bestTime (s), bestLevel, totalKills, pulls, coinsEarned, shinies (wild only), bossesTotal, riftWins, evolutions, missionsDone, groupRuns, bestGroupTime` |

Also present at runtime (created by `sanitize`/UI): `pupgDone: bool`, `pbind: {dex: [moveId|null ×4]}` (fixed hotkey slot
per move), `pban: {dex: [moveId ≤3]}` (banned moves).

Migration on every load (`migrate` `db.js:94-111`, `sanitize` `db.js:119-154`): fill missing keys from `newSave`;
v1→v2 `pity: number` → `{1: pity}`; v2→v3 copy legacy `upgrades` into `pupg[partner]` once; clamp coins/tickets to
non-negative ints; drop `owned/shiny` entries not in the dex; `pbind[d]` exactly 4 unique valid ids or null; `pban[d]`
≤ 3 unique valid ids; `pupg[d][id]` unknown ids removed and levels clamped to `[0, max]`.

Commit policy: `commit()` writes immediately (`db.js:664-675`). Commits happen after every gacha pull, upgrade purchase,
partner change, test choice, each ticket picked up during a run, a wild shiny caught / rescue, mission claim/reroll,
profile/hotkey/ban edits, and at end of run. Helpers: `owns(dex)`, `grant(dex, from)` (no-op if owned), `ownsShiny`,
`grantShiny(dex, from)` (returns true if new; grants normal too), `upgradesOf(dex)` (creates `pupg[dex]`).

Accounts: local accounts (`name` 3–16 chars `[A-Za-z0-9_ñÑáéíóúÁÉÍÓÚ]`, salted SHA-256, not real security) and a guest
save. **There are no save slots in the UI** (`js/ui/slots.js` is the gacha *slot machine*, not save slots).
**Godot**: `user://save.json` (or `user://saves/<profile>.json`) holding the same JSON object; keep field names so a JS
save can be imported verbatim (a nice-to-have: "import save from browser" by pasting the localStorage JSON).

### 8.2 Coins (Pokémonedas)

Sources:

| Source | Amount |
|---|---|
| New save | 500 |
| End of run (`game.js:281-288`) | `round((floor(t/5) + floor(kills/4) + 80*bosses + pickedUpCoins) * coinMul)`; `coinMul = (1 + 0.08*Fortuna) × 1.5 if Amulet Coin` |
| Gacha duplicates | 15/30/60/120/300 by rarity (shiny dup ×3 is unreachable: shiny dups are rerolled) |
| Missions / achievements | §8.6, §8.7 |
| Duplicate wild shiny / duplicate rescue | +300 / +150 in-run coins |

In-run coin pickups (multiplied at the end): grass 6% → 1; rock 25% → 2; breakable chest 4–7 orbs of 3; locked chest 9×4;
boss 10×5; golden enemy 35% → 3; thief Meowth 20×5, thief Gholdengo 6×5; rift legendary extra 10×8; rescued Pokémon 12×5
(`world.js:370-408`, `enemy.js:172-190`, `events.js:205-210`).

Sinks: **only** the per-Pokémon upgrade shop. Gacha costs tickets, never coins.

### 8.3 Upgrade shop (`js/data/upgrades.js`, UI `js/ui/menu.js:233-362`)

Per-Pokémon (`save.pupg[dex][id]`); the shop has a Pokémon selector (partner first, then by total levels desc, then dex).
Next-level cost: `cost(id, lvl) = round(base * grow^lvl / 10) * 10` (lvl = current level from 0). Purchase: if
`lvl < max && coins >= price` → `coins -= price; lvl++; commit`.

| id | Name (es / en) | Per level | max | base | grow | Costs lvl 0→max-1 | Total |
|---|---|---|---|---|---|---|---|
| `hp` | Vitalidad / Vitality | +8 max HP | 10 | 60 | 1.35 | 60,80,110,150,200,270,360,490,660,890 | 3270 |
| `atk` | Fuerza / Strength | +4% damage | 10 | 80 | 1.38 | 80,110,150,210,290,400,550,760,1050,1450 | 5050 |
| `spd` | Zancada / Stride | +3% speed | 8 | 70 | 1.4 | 70,100,140,190,270,380,530,740 | 2420 |
| `cd` | Reflejos / Reflexes | −3% cooldown | 8 | 90 | 1.42 | 90,130,180,260,370,520,740,1050 | 3340 |
| `def` | Coraza / Armor | +2% damage reduction | 8 | 80 | 1.4 | 80,110,160,220,310,430,600,840 | 2750 |
| `regen` | Síntesis / Synthesis | +0.2 HP/s | 5 | 120 | 1.5 | 120,180,270,410,610 | 1590 |
| `magnet` | Imán / Magnet | +12% pickup radius | 6 | 50 | 1.4 | 50,70,100,140,190,270 | 820 |
| `xp` | Sabiduría / Wisdom | +5% XP | 8 | 100 | 1.42 | 100,140,200,290,410,580,820,1160 | 3700 |
| `coins` | Fortuna / Fortune | +8% end-of-run coins | 8 | 120 | 1.45 | 120,170,250,370,530,770,1120,1620 | 4950 |
| `moves` | Repertorio / Repertoire | start with 2 moves | 1 | 1500 | 1 | 1500 | 1500 |
| `crit` | Golpe Crítico / Critical Hit | +3% crit (×1.5) | 10 | 90 | 1.4 | 90,130,180,250,350,480,680,950,1330,1860 | 6300 |
| `reroll` | Cambio de cartas / Card reroll | +1 reroll per run | 5 | 150 | 1.6 | 150,240,380,610,980 | 2360 |
| `ban` | Veto / Ban | ban 1 move from cards | 3 | 300 | 1.9 | 300,570,1080 | 1950 |

`perks(levels)` (`upgrades.js:29-47`), with `L(id) = clamp(floor(levels[id]), 0, max)`:
`hp: 8L, atkMul: 1+0.04L, spdMul: 1+0.03L, cdMul: 1-0.03L, dmgReduce: 0.02L, regen: 0.2L, magnetMul: 1+0.12L,
xpMul: 1+0.05L, coinMul: 1+0.08L, startMoves: 1+L(moves), crit: 0.03L, rerolls: L, bans: L`. Applied in
`new G.Player(...)` (§3.2) and `startRun` (§1.8). Same screen also hosts the **ban picker** (toggle up to `L(ban)` moves
from `poolFor(mon)` minus the start move) and the **hotkey panel** (4 selects over `poolFor(mon) ∪ {start move}`, each
move in one slot only) (`menu.js:300-362`).

### 8.4 Gacha (`js/systems/gacha.js`, UI `js/ui/gacha-ui.js`, slot machine `js/ui/slots.js`)

- **9 banners, one per generation** (`gacha.js:33-43`: Kanto, Johto, Hoenn, Sinnoh, Teselia/Unova, Kalos, Alola, Galar,
  Paldea, each with 3 gradient colors). Pool = all `G.DEX` with `gen === banner.gen` and sprite metadata (legendaries
  included as 5★). `featured(gen)` = top-3 5★ by BST (banner art).
- Cost (`costOf`, `gacha.js:19-23`): ×1 = 1 `t1`; ×10 = 10 `t1` **or** 1 `t10` (two buttons). No coins.
- Rarity weights `RATES = [[1,45],[2,30],[3,17],[4,6.5],[5,1.5]]` (Common, Uncommon, Rare, Epic, Legendary).
- Per pull `i` of `n` (`gacha.js:80-125`):
  1. `pity[gen]++`; if `pity[gen] >= 70` → want 5★.
  2. else if `n==10 && i==9` and no earlier result in this batch was ≥ 4★ → `rollRarity(min=4)` (4★ 81.25% / 5★ 18.75%).
  3. else `rollRarity()`.
  4. `poolNear(want, gen)` tries offsets `0,-1,+1,-2,+2,-3,+3,-4,+4` for a non-empty pool (all current pools non-empty).
  5. If resulting rarity is 5 → `pity[gen] = 0` (pity is per banner). `mon = uniform pick` from the pool.
  6. Shiny if the dex has a shiny sprite and `random() < 1/100`. If that shiny is already owned → pick a random same-pool
     Pokémon whose shiny you lack; if none, the pull becomes non-shiny.
  7. Grant: shiny → `shiny[dex]` (+ normal form if missing), new or refund ×3; normal → `owned[dex]` if new, else refund
     `REFUND[r] = {1:15, 2:30, 3:60, 4:120, 5:300}` coins.
  8. `stats.pulls += n`. Returns `[{dex, rarity, shiny, isNew, refund}]`; the UI then runs `Progress.checkAch()` and commits.
- Generation pool sizes (R1/R2/R3/R4/R5): Kanto 35/41/38/31/6, Johto 25/21/29/18/7, Hoenn 41/25/44/12/13,
  Sinnoh 20/20/20/32/15, Unova 36/27/38/26/14, Kalos 15/17/14/17/7, Alola 14/9/23/20/17, Galar 23/4/23/25/12,
  Paldea 24/7/19/30/12. 87 legendaries/mythicals (`leg: true`), all 5★.
- Rarity colors: 1 `#9fb1c9`, 2 `#5fe08a`, 3 `#4fb4ff`, 4 `#c47bff`, 5 `#ffcb3d`, shiny `#9ae6ff`.
- Presentation (pull already resolved; animation cosmetic): pixel-art slot machine 176×170 art px, 3 reels with the strip
  `ball, ball2, ball, ball3, ball, ball2, ballLux, ball, ball4, ball2, ball3, shiny, ball, ball2`; symbol per rarity:
  1 Poké Ball `ball`, 2 Great `ball2`, 3 Ultra `ball3`, 4 Luxury `ballLux`, 5 Master `ball4`, shiny = red star. For ≥ 4★ or
  shiny the 3rd reel slows (LED text "¡¿ÉPICO?!", "¡¿LEGENDARIO?!", "¡¿SHINY?!"). ×1 timings: lever 0.22 + 0.2 s, spin
  0.6 s, reels stop 0.32 s apart, prize shown 1.0 s; ×10 is faster; click = ×0.25 durations. Then result cards revealed
  150 ms apart ("¡NUEVO!" / "¡SHINY NUEVO!" / "Repetido · +N").

**Ticket sources**: normal enemy kill 1/400 → `ticket`; boss kill 1/3 → `ticket10`; rift legendary 1/2 → `ticket10` + 3
`ticket` always; locked chest 1–3 `ticket` + 15% `ticket10`; rescued Pokémon 1 `ticket`; Gholdengo thief 1 `ticket10`;
missions/achievements. **Shiny odds**: wild 1/4096 (bosses included), rift legendary 1/512, gacha 1/100.

### 8.5 Collection, partner, starters, personality test

How a Pokémon becomes owned: starter (test/manual pick), gacha, **killing a wild shiny** (`G.onShinyCaught`: shiny +
normal; duplicate → +300 run coins), rescue event (20% chance the escorted Pokémon joins; duplicate → +150).
Rift legendaries are **not** granted on victory (only `legends[dex]`, a bond, loot) — they come from the 5★ gacha pool
or by killing their 1/512 shiny.

Collection screen (`menu.js:106-231`): generation tabs 1–9 (have/total), filters all/owned/missing/shiny/rarity 5..1,
grid (unowned = silhouette "???"; crown on partner; star on owned shiny), detail pane with HP/ATK/SPD bars (scale max hp
183, atk 1.55, spd 137), starting move, learnable move icons, "Choose as partner" (sets `partner`,
`partnerShiny = hasShiny && viewingShiny`). Main menu has a Normal/Shiny toggle when the partner's shiny is owned.
Any owned Pokémon is playable; no other unlock gates.

**Starters** (`js/data/starters.js:7-37`, `{dex, start, traits:[primary, secondary]}`; all 29 selectable in the first-time
flow): 1 vine-whip leal/paciente · 4 ember valiente/impulsivo · 7 water-gun prudente/leal · 152 vine-whip dulce/paciente ·
155 ember tímido/impulsivo · 158 water-gun travieso/valiente · 252 razor-leaf sereno/astuto · 255 ember alegre/valiente ·
258 water-gun tenaz/leal · 387 vine-whip paciente/tenaz · 390 ember travieso/alegre · 393 bubble orgulloso/prudente ·
495 razor-leaf orgulloso/astuto · 498 ember tenaz/alegre · 501 water-gun valiente/travieso · 650 vine-whip travieso/tenaz ·
653 ember astuto/sereno · 656 water-gun sereno/astuto · 722 razor-leaf sereno/dulce · 725 ember solitario/orgulloso ·
728 bubble alegre/dulce · 810 vine-whip alegre/travieso · 813 ember impulsivo/alegre · 816 water-gun tímido/astuto ·
906 razor-leaf solitario/astuto · 909 ember tranquilo/tenaz · 912 water-gun orgulloso/prudente · 54 confusion
caótico/tímido · 79 confusion tranquilo/paciente.

**Personality test** (`G.PERSONALITY_TEST`, `starters.js:69-110`; UI `js/ui/test.js`): runs after login when
`save.partner == null`, can't be retaken. 8 questions × 4 answers; each answer adds trait points
(`scores[k] += p[k]`). Result (`G.personalityResult`, `starters.js:112-122`): `trait` = highest score (ties → first
inserted key, stable sort); starter = argmax over the 29 of `2*scores[traits[0]] + scores[traits[1]]`, ties broken uniformly
at random. Screen shows the trait (`G.TRAIT_TEXT`), the suggested starter, "¡Vamos juntos!" (accept) or "Elegir otro"
(29-starter grid). `choose(dex)`: `starter = partner = dex`, `personality = {trait, scores}`, `grant(dex,'starter')`, commit,
go to menu.

Questions → answers → points (Spanish keys; English in `lang-en.js:230-262`):

| # | Question (EN) | A | B | C | D |
|---|---|---|---|---|---|
| 1 | Fight in the middle of town! | valiente 2, impulsivo 1 | prudente 2, leal 1 | sereno 1, tímido 1, solitario 1 | travieso 2, caótico 1 |
| 2 | You find a wallet | leal 2, dulce 1 | tenaz 2, paciente 1 | astuto 2, travieso 1 | prudente 1, tímido 2 |
| 3 | Ideal day off | impulsivo 2, alegre 1 | sereno 2, tranquilo 1 | alegre 2, leal 1 | tenaz 2, orgulloso 1 |
| 4 | Important exam tomorrow | tenaz 2, prudente 1 | orgulloso 2, sereno 1 | tímido 2, dulce 1 | caótico 2, tranquilo 1 |
| 5 | What friends say about you | alegre 2, travieso 1 | leal 2, dulce 1 | solitario 2, astuto 1 | valiente 1, tenaz 2 |
| 6 | Dark short path or long sunny one | valiente 2, impulsivo 1 | paciente 2, prudente 1 | tranquilo 2, sereno 1 | astuto 2, caótico 1 |
| 7 | Someone mocks you | orgulloso 2, impulsivo 1 | sereno 2, solitario 1 | tímido 2, dulce 1 | travieso 2, astuto 1 |
| 8 | What matters most | leal 2, alegre 1 | solitario 2, impulsivo 1 | tranquilo 2, paciente 1 | orgulloso 2, tenaz 1 |

16 traits: valiente (Brave), impulsivo (Impulsive), prudente (Cautious), leal (Loyal), paciente (Patient), dulce (Kind),
tímido (Shy), travieso (Mischievous), sereno (Serene), astuto (Clever), alegre (Cheerful), tenaz (Tenacious), orgulloso
(Proud), solitario (Loner), tranquilo (Relaxed), caótico (Chaotic).

### 8.6 Missions (`js/data/missions.js`, `js/systems/progress.js`, UI `js/ui/goals-ui.js:43-86`)

- `ensure(save)` (on every progress event, screen open, `pending()`): period ids in **Europe/Madrid** time
  (`G.Ranking.periodIds`, `ranking.js:47-68` — the only ranking code to keep): `d = 'd'+YYYYMMDD`, `w = 'w'+ISOyear+'-'+WW`
  (ISO week). New day → `daily = pickSet(DAILY, 3, rng(d + String(save.created)))`, `rerolled = false`. New week →
  `weekly = pickSet(WEEKLY, 2, rng(w + String(save.created)))`.
- `rng(seedString)`: FNV-1a 32-bit (`h = 2166136261; for each char: h ^= code; h = imul(h, 16777619)`) feeding
  mulberry32: `h += 0x6D2B79F5; t = h; t = imul(t ^ (t>>>15), t|1); t ^= t + imul(t ^ (t>>>7), t|61);
  return ((t ^ (t>>>14))>>>0) / 2^32`. **GDScript ints are signed 64-bit**: keep every intermediate masked to 32 bits
  (`& 0xFFFFFFFF`) and use the shared `imul32(a, b)` helper from §10.4 (16-bit split, never overflows int64);
  `x >>> n` = `(x & 0xFFFFFFFF) >> n`; `t | 1` / `t | 61` on the masked value.
- `pickSet(defs, n, r)`: until n unique ids: `idx = floor(r()*pool.length)` (pool shrinks), `make(def)`: `goal =
  def.goals[floor(r()*len)]`, then if `def.param == 'type'`: `param = TYPES[floor(r()*18)]` (type order of
  `G.U.TYPE_NAME`: normal, fire, water, grass, electric, ice, fighting, poison, ground, flying, psychic, bug, rock, ghost,
  dragon, dark, steel, fairy). Instance `{id, goal, param, prog:0, claimed:false, told:false}`.
- Reroll: once per day, one unclaimed daily, non-deterministic seed (`M.day + 'cambio' + Date.now()`), excludes the 3
  current ids.
- Progress (`advance`, `progress.js:66-79`): skip if claimed/done or event/match mismatch; `v = def.value ? def.value(d) : 1`;
  mode `max` → `prog = max(prog, v)`, else `prog += v`. On completion toast "Misión completada". **Claim is manual**:
  `claimed = true`, grant reward, `stats.missionsDone++`, `event('missionDone', {daily})`, commit.

Daily (3/day): `kill` (kill, +1; 300/500/800; 2 t1 + 150) · `killType` (kill where enemy types include param;
30/50/80; 2 t1 + 200) · `survive` (runEnd, max of `floor(time/60)`; 5/7/9; 3 t1 + 200) · `level` (runEnd, max level;
8/12/15; 2 t1 + 200) · `boss` (kill with `d.boss`; 1/2; 3 t1 + 250) · `chest` (locked chest opened; 1/2; 2 t1 + 200) ·
`coins` (runEnd, + raw picked-up coins; 100/200/300; 2 t1 + 150) · `playType` (runEnd with partner of type param, max
minutes; 3; 3 t1 + 200) · `item` (item equipped; 1; 2 t1 + 150) · `evolve` (1; 3 t1 + 250).
Weekly (2/week): `wkill` 4000/6000 (1 t10 + 800) · `wrift` rift wins 1/2 (1 t10 + 1000) · `wboss` 4/6 (1 t10 + 900) ·
`wsurvive` max minutes 12/15 (1 t10 + 1000) · `wevolve` 3/5 (1 t10 + 900) · `wdaily` daily missions done 8/12 (1 t10 + 800).

Event hooks `G.Progress.event(kind, d)` (`progress.js:129-159`):

| kind | payload | fired at | save side effects |
|---|---|---|---|
| `kill` | `{types, boss, legend}` | `G.Progress.kill(e)` from enemy death (`enemy.js:909`) | boss → `stats.bossesTotal++`; legend → `legends[dex] = now` |
| `chest` | — | locked chest opened (`world.js:407`) | — |
| `item` | `{id}` | item equipped (`game.js:384`) | `itemsFound[id]` |
| `evolve` | `{move}` | evolution card (`levelup.js:68`) | `stats.evolutions++`, `evoMoves[id]` |
| `rift` | `{type}` | rift won (`rift.js:193`) | `stats.riftWins++`, `arenas[type]` |
| `runEnd` | `{time, level, coins, types, group}` | `endRun` (`game.js:299`) | group → `groupRuns++` |
| `missionDone` | `{daily}` | claim | — |

`legend = (e.legend || (Rift.inArena && e.boss)) ? e.dex : 0`. The rift legendary has `boss = legend = true`, so it also
counts for bosses (+80 coins, boss missions, boss loot). `checkAch()` runs after each event (throttled to 1/s for kills).

### 8.7 Achievements and titles (`js/data/achievements.js`, checked in `progress.js:169-181`)

Shape `{id, cat, tier (1 bronze, 2 silver, 3 gold), name, desc, value(save) → number, goal, reward {coins|t1|t10}, title?, dex?}`.
`checkAch()` grants every not-yet-unlocked achievement with `value >= goal`: `ach[id] = now`, reward granted
automatically, popup "¡Logro: X!" (+ "Nuevo título: …"); the caller commits. Categories: coleccion, supervivencia,
combate, grietas, legendarios, otros. 127 total = 40 fixed + 87 generated (`leg_<dex>`: "Vence a X", tier 2, goal 1,
reward 1 t1, one per legendary with sprite metadata, `achievements.js:74-77`).

| id | tier | condition | reward | title |
|---|---|---|---|---|
| own1 / own10 / own50 / own100 / own250 / own500 / ownAll | 1/1/2/2/3/3/3 | owned ≥ 1/10/50/100/250/500/966 | 100c / 2t1 / 5t1 / 1t10 / 2t10 / 3t10 / 10t10 | — / — / Coleccionista / — / Maestro Pokémon / — / Profesor Pokémon |
| shiny1 / shiny5 / shiny20 | 1/2/3 | shinies owned ≥ 1/5/20 | 3t1 / 1t10 / 2t10 | Brillante / — / Cazashinies |
| pulls100 | 2 | pulls ≥ 100 | 1t10 | Afortunado |
| time5 / time10 / time15 / time20 | 1/2/2/3 | best minutes ≥ 5/10/15/20 | 200c / 4t1 / 1t10 / 2t10 | — / — / — / Superviviente |
| lvl20 / lvl40 | 1/3 | bestLevel ≥ **15 / 30** (ids are historical) | 2t1 / 1t10 | — / Imparable |
| runs50 | 2 | runs ≥ 50 | 1t10 | Explorador |
| kills1k / kills10k / kills100k | 1/2/3 | totalKills ≥ 1e3/1e4/1e5 | 2t1 / 1t10 / 3t10 | — / Veterano / Leyenda viva |
| boss1 / boss25 / boss100 | 1/2/3 | bossesTotal ≥ 1/25/100 | 2t1 / 1t10 / 2t10 | — / Cazajefes / — |
| evo1 / evo25 / evoAll | 1/2/3 | evolutions ≥ 1/25; distinct evoMoves ≥ 59 | 3t1 / 1t10 / 3t10 | — / Evolucionista / Maestro de movimientos |
| items5 / itemsAll | 1/2 | distinct itemsFound ≥ 5 / 11 | 3t1 / 1t10 | — / Anticuario |
| rift1 / rift10 / arenas | 1/2/3 | riftWins ≥ 1/10; distinct arenas ≥ 18 | 3t1 / 1t10 / 2t10 | Valiente / — / Viajero de grietas |
| leg10 / leg30 / legAll | 2/3/3 | legends ≥ 10/30/87 | 1t10 / 2t10 / 5t10 | Cazalegendarios / — / Leyenda |
| mis10 / mis50 / mis200 | 1/2/3 | missionsDone ≥ 10/50/200 | 3t1 / 1t10 / 3t10 | — / Constante / — |
| group1 / group10 | 1/2 | groupRuns (co-op only — drop or leave unreachable) | 2t1 / 1t10 | — / Compañero fiel |

Titles: `G.Progress.titles()` = titles of unlocked achievements (21 possible); chosen in the Profile tab (`profile.title`),
plus 3 favorite Pokémon (`profile.favs`). Goals screen (`goals-ui.js`) has 3 tabs: Missions, Achievements (category chips,
medal cards with progress bars, legendary silhouette grid), Profile.

### 8.8 Settings and other per-device keys

`ps.settings` = `{quality:'auto'|'high'|'mid'|'low', dmgNumbers:true, calm:false, fps:false, stick:1}` (§2.7, §9);
`ps.audio = {music:0.55, sfx:0.7, muted:false}`; `ps.lang = 'es'|'en'|'zh'`; `ps.news.seen`; `ps.ask` (Ko-fi prompt date).
Auto quality: starts at 2 (desktop) / 1 (touch); sampled each second while playing; < 45 FPS for 3 consecutive samples →
−1; > 57 FPS for 8 → +1 (`settings.js:31-41`). Godot: `user://settings.cfg` via `ConfigFile`.

### 8.9 Online features (excluded)

Firebase Auth + Firestore cloud save with merge (`db.js:308-613`), social/friends/presence/invites/public profiles
(`js/net/social.js`, `js/ui/social-ui.js`), leaderboards (`js/net/ranking.js`, `js/ui/ranking-ui.js`), 4-player co-op over
WebRTC with TURN/RTDB relay (`js/net/net.js`, `js/net/coop.js`), auto-updater (`js/core/updater.js`), Ko-fi support prompt.
In gameplay code, strip every `G.Coop.*` branch (treat `G.Coop.active` as false, `isHost` as true) and `G.Ranking.submit*`.

---

## 9. UI, HUD, input, audio

**Split**: the main `#game` canvas draws the world, the in-run HUD, the touch joystick, damage numbers, FPS and flashes.
**Every menu and every in-run modal** (level-up, bond, item, pause, results), toasts and popups are **DOM** overlays
(`<section class="scr">` in `dev.html`, styled by `css/style.css`). Small DOM canvases show animated Pokémon previews
(`G.UI.sprite`, `ui.js:203-284`) and the gacha slot machine (`G.Slots`). While in menus, the main canvas keeps rendering
the live world backdrop (§1.7).

### 9.1 Screens

`G.UI.SCREENS` (`ui.js:10-12`) are mutually exclusive: `scr-login, scr-test, scr-result, scr-starters, scr-menu, scr-dex,
scr-upgrades, scr-gacha, scr-levelup, scr-pause, scr-over, scr-nick, scr-friends, scr-lobby, scr-rank, scr-item, scr-goals,
scr-bond`. `G.UI.show(id, keepMenu)` hides the others (with `keepMenu`, the menu stays visible underneath a `.dim`
backdrop). Independent overlays: `scr-settings, scr-legal, scr-news, scr-support, scr-profile, #pull-fx, #invite-pop,
#sound-panel, #topbar, #credits-line, #rotate, #boot, #tap-start, .toast, #ach-pop`.

Flow (`G.Flow`, `game.js:798-862`): boot "Cargando…" → `DB.ready` → tap-to-start (only if audio is locked — not needed
natively) → restored session ? `afterLogin` : login → no partner ? personality test : menu → Play → run → results → menu.

| Screen | Content | Actions / exits | Source |
|---|---|---|---|
| Login `scr-login` | logo, account tabs, guest | **drop** (offline port = auto guest/local profile) | login.js |
| Test `scr-test` | progress bar, "Pregunta N de M", question, 4 answer buttons | answer → next → result | test.js:13-43 |
| Result `scr-result` | "Tu personalidad es…", trait + text, 200×150 sprite stage (scale 4), suggested partner | "¡Vamos juntos!" → choose; "Elegir otro" → starters | test.js:45-54 |
| Starters `scr-starters` | grid of 29 starters (92×80 cells, scale 2), info line (types, start move, traits) | Back / Choose → grant, set partner, menu | test.js:57-92 |
| Main menu `scr-menu` | left: logo + partner card (260×200 stage, scale 4, "lively" anims, border = type color or `#9ae6ff` if shiny), name, type chips, rarity ball, Normal/Shiny toggle if owned; right: menu list + stats box (Runs, best time, best level, kills) | items `play, dex, upgrades, gacha, goals, (friends, rank), settings` with icons `ball, book, up, ball4, medal3, friends, trophy, gear` (`menu.js:8`); goals subtitle "N premios por recoger" | menu.js:7-102 |
| Top bar `#topbar` (menus) | coins pill, tickets (t1, t10), user pill; buttons news, support, sound panel, fullscreen, settings, exit | keep coins/tickets/sound/settings | ui.js:23-44 |
| Collection `scr-dex` | §8.5 | Esc/back → menu | menu.js:106-231 |
| Upgrades `scr-upgrades` | Pokémon selector + 13 upgrade cards (icon, name, unit, pips, buy button "cost" / "Máx."), ban picker, 4 hotkey selects | buy → sfx `buy` | menu.js:237-362 |
| Gacha `scr-gacha` | 9 banner tabs, banner (3-color gradient, "<Region> Misterioso", owned count, featured sprites 170×190), buttons ×1 / ×10 (10 t1) / ×10 (1 t10), tickets line, pity "N / 70", rates panel | pull → `#pull-fx` slot machine + result cards → Continue | gacha-ui.js, slots.js |
| Goals `scr-goals` | tabs Missions (3 daily + 2 weekly, progress bars, reset countdown, claim / reroll) · Achievements (category chips, medal cards, legendary grid) · Profile (3 favorites, title select) | claim sfx `buy` | goals-ui.js |
| Settings `scr-settings` | tabs Sound (music/sfx sliders 0–100, mute), Graphics (language es/en/zh, quality auto/high/mid/low, damage numbers, calm, FPS, fullscreen), Controls (stick size 0.8/1/1.25, key reference), Account, About | Esc / Close returns to caller (menu or pause) | settings-ui.js |
| Level-up `scr-levelup` | "¡Nivel N!", "Elige una recompensa · 1 2 3", up to 3 cards (vertical list, `min(560px, 100%)` wide, gap 10), reroll button "Cambiar opciones (N) · R" | §6 | run-ui.js:7-90 |
| Bond `scr-bond` | "¡Vínculo!" (pink `#ff8ad8`), subtitle by mode, move cards with "Nv.N" chips | keys 1–4 / click; "Atrás" in step 2 of pair mode | run-ui.js:141-221 |
| Item `scr-item` | "¡Un objeto!", "Sólo puedes llevar uno · 1 2", cards "Quedarme con X" / "Cambiar a Y" (2nd gold) | keys 1–2 / click | run-ui.js:120-139 |
| Pause `scr-pause` | "Pausa", key hints, inline sound controls | Continue (gold), Settings (sound tab), "Abandonar run" → `endRun(false)` (still pays coins) | run-ui.js:223-233 |
| Results `scr-over` | "Has caído…" / "Run terminada"; Time, Level, Kills, Bosses; coins + breakdown string (`tiempo N · derrotados N · jefes N · recogidas N · ×M Fortuna`); tickets; moves with levels; shinies caught (90×72 sprites, "¡nuevo!"); "¡Nuevo récord de tiempo!" | "Volver al menú" | run-ui.js:104-140 |
| Toast `.toast` | bottom-center (30 px), default 2.2 s | — | ui.js:46-53 |
| Achievement popup `#ach-pop` | top-center (64 px), medal or legend sprite + text; queue, 2.8 s each, 0.25 s gap; sfx `legend` (achievement) / `confirm` (mission) | — | progress.js:199-220 |
| Rotate `#rotate` | "Gira el móvil" (touch portrait → auto-pause) | — | game.js:54-62 |
| Drop | `scr-nick, scr-friends, scr-lobby, scr-rank, scr-profile (public), #invite-pop, scr-news, scr-support, scr-legal`, updater | online/web only; the existing `window.PS_APP` mode already hides friends/rank/support/logout | — |

Esc priority (`game.js:455-489`): settings open → close; level-up → 1–3 / R; bond → 1–4; item → 1–2; in `'ui'` → back to
menu from dex/upgrades/gacha/goals (not during the pull animation); else Esc/P toggles pause.

Theme (for a Godot `Theme`): `.box` panel gradient `#2c519f → #1a3170`, border 3 `#f4f8ff`, radius 12, outer ring 3
`#0b1838`, inner ring 2 `#5b83d6`, padding 22×24; `.btn` gradient `#3d67c0 → #26468f`, border 3 `#f4f8ff`, radius 9, ring
2 `#0b1838` + 4-px bottom ledge, 17 px/700 (small 14 px), hover brightness ×1.15, pressed +2 px down, disabled grey;
variants gold (`#ffe37a → #f0a31e`, text `#3a2300`), ghost, danger (`#8a1f2e`). Palette: ink `#fff`, muted `#b9cbf0`,
gold `#ffd23f`, red `#ff5f6d`, green `#5fe08a`, text shadow `2px 2px 0 #0a1430`, body bg `#050914`. `.dim` backdrop
radial `rgba(10,20,50,.55) → rgba(3,6,16,.88)`. Animations: `pop` (scale .94→1 + fade, .22 s), card hover
`translateX(4px)`, legendary glow pulse. Responsive breakpoints: `max-height: 520px` (compact, 2-column menu), 660/780 px
heights, `max-width: 760px`. UI click sounds by delegation (`ui.js:64-81`): `hover` on enter; `back` for back buttons,
`error` if disabled, `data-sfx` override (`none`), else `click`.

### 9.2 In-run HUD (canvas, `js/ui/hud.js`) — screen CSS px, not affected by world zoom

Font helper `F(w, s) = "<w> <s>px Pixelify"`. `bar(x,y,w,h,frac,col,bg='rgba(0,0,0,.55)')` = pill (radius h/2) with the
fill clipped. Margins `px = 16, py = 20`.

| # | Element | Position / size | Style |
|---|---|---|---|
| 1 | XP bar | `(0, 0, w, 7)` | bg `rgba(0,0,0,.5)`; fill `w*xp/xpNext`, horizontal gradient over full width `#4fd1ff → #a98bff` |
| 2 | Pokémon name | left at (16, 30) | 800 13px `#eaf2ff` |
| 3 | `'Nv. ' + level` | (16, 46) | 700 11px `#ffcb3d` |
| 4 | HP bar | `bar(64, 37, 168, 11, hp/maxHp, '#ff5f6d')`; text `ceil(hp) + ' / ' + round(maxHp)` centered at (148, 46) | 700 10px white .95 |
| 5 | Buff chips | row from (16, 54), h 15, radius 7, width textW+12, gap 5 | bg `rgba(0,0,0,.5)`, text 800 9px `LBL ×n`: ATK `#ff6b4d`, VEL `#7fe0ff`, DEF `#b0b8c8`, REG `#5fe08a` |
| 6 | Timer `m:ss` | centered (w/2, 42) | 800 26px white .95 |
| 7 | Sub-line `BIOME · N DERROTADOS · N MONEDAS` | (w/2, 58) | 600 10px `#8fa3c4` (only kill/coin counter) |
| 8 | Weather chip | top-right, x0 = `w - tw - 16 - (touch ? 56 : 0)`, y0 = 14, h 26, radius 9 | bg `rgba(0,0,0,.55)`, icon 20 px, text `NAME · Ns` (800 11) in weather color |
| 9 | Boss bar | `bw = min(420, w - 80)`, `bar((w-bw)/2, 70, bw, 12, hp/maxHp, '#ffcb3d')`; name upper-case at (w/2, 80) | 800 10px `#20160a` |
| 10 | Off-screen shiny arrows | clamp x∈[34, w-34], y∈[94, h-104] | triangle (tip 24, base 12 at ±2.5 rad) `#9ae6ff`, α `0.6 + 0.4 sin(now_ms/160)`, shiny icon 24 px |
| 11 | Altar power chip | after the buff chips | `NAME Ns`, bg `rgba(0,0,0,.6)`, power color |
| 12 | Rift arrow (off-screen) | margin 52, y∈[122, h-132] | halo r `30 + 8 beat` α `.18 + .22 beat` `#b48aff`; triangle tip 40 / base 20 at ±2.45 rad, dark copy ×1.12 `#1a0b33`; fill `beat > .5 ? #e2d0ff : #a06bff`; label `GRIETA · N m · N s` 800 12 stroke 4; `beat = .5 + .5 sin(now_s*7)` |
| 12b | Rift arrow (on-screen) | bouncing down arrow at world `y - 40` (−46 − \|sin(now*4)\|*10 px) | label `GRIETA · N s` |
| 13 | Rift arena timer | `GRIETA · m:ss` at (w/2, boss ? 98 : 76) | 800 12px `#d9c2ff` |
| 14 | Event countdown + arrows | (w/2, 112); arrows margin 44, y∈[114, h-124], tip 30 / base 15 | gold hour `#ffd23f`, horde type color; lost Pokémon / goal `#7dffb0`; thieves `#ffd23f` |
| 15 | "Rift opened" popup | first 4.5 s; box at (w/2, 0.2h), h 52, radius 10, fill `rgba(26,11,51,.88)`, stroke 2 `#b48aff`; α `min(1, 4t, (4.5-t)*2)`, scale `1 + max(0, .25 - t)*1.6` | line 1 "¡SE HA ABIERTO UNA GRIETA!" 800 20 `#e2d0ff`; line 2 700 11 `#c9b0ff` |
| 16 | Announcement banner (`G.Spawner.say(text, secs=2.6)`) | (w/2, 0.3h) | 800 22px `#ffcb3d`, stroke `rgba(0,0,0,.7)` w 4, α `min(1, remaining*1.6)`; one global message (new replaces old) |
| 17 | Move slots | `S = 54`, `GAP = 9`, `n = max(1, slots)`, centered; y = `h - 54 - 18 - (touch ? min(28, safeBottom) : 0)`; active raised 6 px | see below |
| 18 | Stored bonds | `bond` icon 24 right of the slots; `×N` pink if > 1 | |
| 19 | Held item slot | left of the slots (`slotsLeft - 54 - 18`), 54×54, radius 12 | item: fill `rgba(40,30,10,.9)`, stroke 2 `#ffd23f`, icon 36, name above 700 9 `#ffd23f`; empty: `rgba(10,16,28,.55)`, stroke 1 `rgba(140,170,210,.18)` |
| 20 | Pause button (touch) | 40×40 at top-right (safe area), radius 10 | fill `rgba(10,16,28,.7)`, stroke 2 white .8, two bars 5×18 |
| 21 | Control hint (first 14 s) | (w/2, h - 4) | 600 10px `rgba(180,200,230,.55)`; desktop "WASD moverse · 1-4 / Q / E o clic en un ataque para cambiarlo · Esc pausa" |

Move slot (`hud.js:250-322`): rounded rect radius 12; fill active `rgba(20,30,50,.95)` else `rgba(10,16,28,.8)`; stroke
width active 2.5, fused/evolved 2, else 1.2; stroke color fused `#ff8ad8` > evolved `#ffd23f` > active = type color > else
`rgba(140,170,210,.22)`. Single move: cooldown overlay `rgba(0,0,0,.6)` from the top with height `S*clamp(m.t/(m.cd*cdMul))`
(orbit always 0), icon `move:<id>` 32 px at (x+11, y+9), level pips (`maxLvl` dots 4×3, gap 2, at y+S-9, filled with type
color if `i < lvl`). Fused group: 2×2 grid of 22-px icons, per-icon cooldown overlay, white cast flash α
`0.55*(1 - (now - castAt)/180ms)`. Key number `i+1` at (x+3, y+10) 800 9px; active move name above (700 10px), fused
"Name +N". Slots are clickable/tappable (`G.Touch.addButton`, pad 7.5) → `setActive`, sfx `click`.

Damage numbers: §2.7 (world space). Note `vy *= 0.94` **per frame** in JS — use `vy *= pow(0.94, dt*60)` in Godot.

### 9.3 Icons (`js/ui/icons.js`) — procedural, no image files

- UI icons are 12×12 character maps (`{pal: {char: '#hex'}, rows: [12 strings]}`, `'.'`/`' '` transparent, `k` outline
  `#1b1528`), rendered 1 px per char. Canvas: `G.Icons.draw(ctx, name, x, y, size)`; DOM: `G.Icons.html(name, size)` → SVG
  data-URL `<img>`. **Size snapping** (`icons.js:363-367`): drawn size = `nativeW * max(1, round(size/nativeW))`, centered
  in the requested box (20 → 24, 16 → 12, 32 → 36). Unknown names fall back to `star`.
- List: chrome `gear, full, phone, user, crown, cursor (8×12), sound, mute, book, up, trophy, friends, heart, ban`;
  stats `heart, fist, boot, clock, shield, sprout, magnet, book, berry, coin, cards, star, starDim`; pickups `berry,
  magnet, bomb, ticket, ticket10`; currency `coin, ticket, ticket10`; special `shiny, bond`; weather `wsun, wrain, wsand,
  wsnow, wfog`; rarity balls `ball, ball2, ball3, ballLux, ball4`; 11 held items (ids as in §4.9); medals `medal1, medal2,
  medal3, medalOff`.
- Type/move emblems (16×16, `emblem(type, kind)`, `icons.js:254-285`): disk centered (7.5, 7.5): skip `d > 7.6`, outline
  `d > 6.6`, dark `shade(col, .55)` if `dx+dy > 6`, light `shade(col, 1.3)` if `dx+dy < -6.5`, else type color; 8×8 white
  type glyph (`TYPE_GLYPH`, 18) at (4,4) with dark shadow at (5,5); `move:<id>` adds a kind badge: 7×7 outline square at
  (9,9), 5×5 `#2b3454`, 5×5 gold `#ffd23f` glyph from `KIND_GLYPH` (15 kinds).
- `twinkle(ctx, x, y, phase, px)` shiny sparkle (`icons.js:389-401`): stage by phase (<.15 → 0, <.32 → 1, <.62 → 2,
  <.82 → 1, else 0); white center; stage ≥ 1 adds a 4-arm cross `#fff3a8` at distance 1; stage 2 adds arms at distance 2
  `#fff3a8`, tips at 3 `#9ae6ff` and diagonals at 1 `#9ae6ff`.
- Port: a one-off tool (Node or GDScript `@tool`) that renders every icon to PNG (+ an atlas JSON), or build
  `ImageTexture`s at startup with `Image.set_pixel`. Keep integer scaling and Nearest filtering.

### 9.4 Input

**Keyboard** (`js/core/input.js`, `game.js:455-489`): physical key codes; `tap()` true only on the press frame; window blur
clears held keys. Movement vector is normalized (diagonal = 1/√2 each).

| Key | Context | Action |
|---|---|---|
| W/↑ A/← S/↓ D/→ | playing | move |
| 1–4 (row or numpad) | playing | `pl.setActive(i)` |
| Q | playing | `pl.cycle(-1)` |
| E or Tab | playing | `pl.cycle(+1)` |
| Esc or P | playing/paused | toggle pause |
| 1–3, R | level-up | pick card, reroll |
| 1–4 | bond | pick |
| 1–2 | item | pick |
| Esc | settings / menu sub-screen | close / back |

"Move select" = which slot is **active**: only the active slot's moves tick cooldowns and fire (§4.4); aim is automatic
(§3.5). Mouse: only DOM clicks and clicking HUD slots. **No gamepad support** (Godot gets it nearly free via InputMap —
recommended addition: left stick = move, LB/RB = cycle, Start = pause, A/B/X = card picks).

**Touch** (`js/core/touch.js`): floating dynamic joystick — appears where a non-mouse pointer goes down on the canvas
(not on a HUD button), only while playing; first pointer owns it. Radius `R = 56 * stick` (0.8/1/1.25 → 44.8/56/70 px).
Dead zone 7 px; magnitude `k = min(1, (d - 7)/(R*0.5 - 7))` (full speed at half radius); output `(dx/d*k, dy/d*k)`. The
base follows the finger when `d > R` (origin dragged so the finger stays at R). Visual: base circle radius R fill
`rgba(10,20,48,.55)` at α .5, stroke 3 `#f4f8ff`; knob radius `0.42R` fill `#ffd23f` α .85, stroke 3 `#a55f00`. HUD buttons
are rebuilt every frame; press de-dupe within 350 ms. Touch mode adds a pause button and moves the weather chip / slots for
safe areas. Godot: handle `InputEventScreenTouch/Drag` by `index` in `_unhandled_input` (HUD buttons as real
`TextureButton`s stop the event), `DisplayServer.get_display_safe_area()` for insets.

### 9.5 Audio (`js/core/audio.js`, `js/data/music.js`) — 100% procedural Web Audio, zero files

**Graph**: per-song bus (fades) → `musicBus (muted ? 0 : music*0.7)`; convolution reverb (1.8 s stereo noise IR,
`g²√g` decay) → wet 0.3 → musicBus; `sfxBus (muted ? 0 : sfx*2.4)`; both → `DynamicsCompressor(threshold −14 dB, ratio 4)`
→ out 0.9. Volumes in `ps.audio = {music: 0.55, sfx: 0.7, muted: false}`, ramps τ = 0.05.

**Instruments** (`INST`, `audio.js:123-218`): flute (triangle f + sine 2f ×.18, LP 3600, vibrato 5.3 Hz, breath noise),
bell (sine f + 4f), pluck (saw → LP sweep 3200 → max(300, 1.8f) in 220 ms), bass (triangle + square ×.25, LP 900), pad
(2 detuned saws ±0.4%, LP 1100), lead (2 squares +0.6%, LP 2600, vibrato 6 Hz), kick (sine 150→42 Hz in 130 ms),
snare (HP noise + triangle 190 Hz), hat (HP 7500 noise 45 ms), shaker (BP 5200 noise 70 ms). Envelope helper `gainEnv`.

**Sequencer**: 16th-note steps (`sd = 60/bpm/4`), 16 steps/bar, `setInterval` 25 ms with 150 ms look-ahead, swing delays
steps where `i%4 == 2` by `swing*sd`. Score format (`music.js`): `melody` per bar `"A4:4 C5:2 -:2"` (note:16ths, `-` rest);
`parts` 16-char patterns over `chords` (`R` root, `F` fifth, `O` octave, `T` third, `0–5` chord tones
`[0, third, 7, 12, 12+third, 19]`, `C` triad, `-` hold, `.` rest); `drums` 16-char (`X` 1, `x` .75, `o` .45).
`music(name)`: idempotent; old song fades out linearly 0.7 s, new fades in 0→1 over 0.8 s starting 0.1 s later.

| Track | BPM / swing | Bars | Loop | Lead | Plays |
|---|---|---|---|---|---|
| `village` | 100 / .18 | 16 | 38.4 s | flute | all menus |
| `forest` | 122 | 16 | 31.5 s | flute | biome b%3 = 0 |
| `cave` | 92 / .1 | 16 | 41.7 s | flute | b%3 = 1 |
| `volcano` | 132 | 8 | 14.5 s | lead | b%3 = 2 |
| `boss` | 150 | 8 | 12.8 s | lead | any boss alive |
| `rift` | 164 | 16 | 23.4 s | lead | in arena |
| `null` | — | — | — | — | results screen |

**SFX** (`audio.js:354-449`; `tone(type, f0, f1, dur, vol)`, `hiss(dur, vol, filter, f0, f1)`, `arp(type, freqs, gap,
dur, vol)`): `hover` square 1400 .025 · `click` square 660→990 .05 · `back` square 880→520 .07 · `confirm` triangle arp
784/988/1319 · `select` square 990→1180 .04 · `error` square arp 330/262 · `shot{kind,type}` with pitch
`SHOT_PITCH[type]` (fire 520, water 700, electric 1100, psychic 800, grass 640, ice 900, poison 400, ghost 350, dragon 300,
fairy 1200, normal 600, fighting 450, rock 260, ground 240, steel 750, bug 980, dark 330, flying 820) and recipe per kind
(melee BP hiss 600→2800; beam saw .6f→.35f + BP hiss; nova LP hiss 2400→300 + sine 140→60; aura two sines; buff sine arp;
orbit triangle f→1.5f; projectile triangle 1.5f→.5f + HP hiss for fire/electric); kind mapping `boomerang/cone →
projectile, chain → beam, mine/meteor → nova, turret → buff, dash → melee, trail → silent` · `hit` triangle 230→90 .045 ·
`faint` sine 720→240 · `bossDown` · `xp` sine `880*2^(combo/12)` .06 (combo +1 if previous xp < 0.45 s ago, max 24) ·
`coin` square 1320 + 1760 · `heal` triangle arp 523/659/784/1047 · `levelup` · `hurt` square 150→70 + LP hiss · `boss`
(3 saws 82/123/165 + kick, 1.3 s) · `surge` LP hiss 500→120 .7 · `shiny` 6 bells 2093…4186 every .07 s · `shinyGet` ·
`break` · `chest` · `grass` HP hiss 2600 .06 · `ball`, `shake`, `burst{rarity}`, `reveal{rarity}` (gacha) · `rift`
(4 pads + hiss) · `legend` (square arp + shiny) · `gameover` triangle arp 523/440/349/262 · `biome` (4 pads) · `pause` ·
`buy`. Pickup → sfx: xp/xpBig `xp`, coin `coin`, heal `heal`, bomb `break`, magnet `confirm`, ticket `shiny`, ticket10
`legend`, item `legend` (`game.js:374`). Rate limits (`MIN_GAP` ms): hit 45, faint 60, xp 35, coin 50, grass 70, shot 70
(per kind), hover 40, break 60; voice cap 24 (each counted 150 ms). No Pokémon cries.

**Port recommendation**: **pre-render** (don't synthesize live in GDScript): run the unchanged `audio.js` + `music.js` in an
`OfflineAudioContext` (headless Chromium via Puppeteer/Playwright, or `node-web-audio-api`) and export WAV/OGG. Music:
render 2 loops + 2 s tail and keep `[L, 2L]` so reverb tails wrap seamlessly → `AudioStreamOggVorbis` with loop. SFX:
render each fixed SFX once; parametric ones: `xp` = one 880 Hz sample + `pitch_scale = 2^(combo/12)`; `shot` = render per
(kind) at f = 600 and use `pitch_scale = f/600` (or pre-render 18 types × kinds ≈ 92 files); `burst`/`reveal` 5 rarity
variants. Buses: Master (Compressor −14 dB, ratio 4), Music (`music*0.7`), SFX (bake the ×2.4 into the samples, avoid >0 dB
bus gain). Crossfade with two `AudioStreamPlayer`s + Tween (0.7 s out, 0.8 s in). Keep `MIN_GAP` and the voice cap (pool of
`AudioStreamPlayer`s or `AudioStreamPolyphonic`).

### 9.6 Fonts, scaling, i18n

- Fonts (`assets/fonts`): `PixelifyPS-400.ttf`, `PixelifyPS-700.ttf` (Pixelify Sans OFL with redrawn digits,
  `tools/make_font.py`); CSS weights ≥ 551 (incl. canvas 600/700/800) use the 700 file. CJK fallback
  `fusion-pixel/fusion-pixel-12px-proportional-zh_hans.otf.woff2` (Godot can't load woff2 — convert to TTF/OTF). Godot:
  `FontFile` with `antialiasing = NONE` (or grayscale — sizes 9/10/11/13 aren't multiples of the pixel grid), hinting off,
  subpixel positioning off; outline via `outline_size` + `font_outline_color` (canvas used `strokeText` width 3–4).
- i18n (`js/core/i18n.js`): **source language is Spanish and the Spanish string is the key**; `en` (`lang-en.js`, ~1,117
  entries incl. patterns) and `zh` (`lang-zh.js`, falls back to English). Lookup: exact → ALL-CAPS case-insensitive → `{x}`
  patterns (captured groups translated recursively) → whole-word fragment replacement. Translation is automatic: DOM via
  MutationObserver, canvas by **monkey-patching `fillText/strokeText/measureText`**. Language: `ps.lang` → `/en/` path →
  browser language; changing it reloads. Godot: export to CSV/PO with Spanish msgids; every concatenation site must become
  `tr("…{0}…").format([...])` (multi-`{x}` patterns need positional `{0} {1}`); fragment matching has no equivalent — add
  explicit keys. Pokémon names exist **only in Spanish** in `pokedex.js` (no English names in the repo; most match English,
  but e.g. Paradox Pokémon don't — fetch English names from PokeAPI if needed). HUD labels `VEL`/`REG` have no English key.

---

## 10. Data export plan

### 10.1 What `tools/export_data.js` produces today

`node tools/export_data.js` → `tools/cache/gamedata.json` (227 KB; `tools/cache/` is git-ignored). It loads `util, i18n,
lang-en, settings, pokedex, sprites-meta, moves, types, items, achievements, tiles, funding` in a `vm` sandbox with a fake
DOM. It exists to generate the SEO web pages, so it exports **display data only**:

| Key | Size | Content | Enough for Godot? |
|---|---|---|---|
| `dex` | 966 entries, 123 KB | full `G.DEX` entries | **yes** |
| `legends` | 87 | dex numbers with `leg` | yes (derivable) |
| `moves` | 64, 14 KB | `id, name, type, kind, desc, maxLvl, evo {name, needs(display name), text}` | **no** — no numbers, ladders or evo mods |
| `items` | 11 | `id, name, desc` | names only (effects are code) |
| `achievements` | 127, 18 KB | `id, cat, name, desc, tier, title, reward` | **no `goal`**, no value source |
| `achCats` | 6 | categories | yes |
| `types` / `matrix` | 18 / 18×18 | raw chart / precomputed single-type multipliers | chart yes |
| `typeColor`, `typeName`, `typeOrder` | 18 | colors, Spanish names, order | yes |
| `arenas` | 18 | arena names only | **no** (themes, palettes missing) |
| `funding` | — | Ko-fi data | drop |
| `en` | 1,117 | Spanish → English dictionary (incl. `{x}` patterns) | yes |

Missing entirely: sprite metadata, move stats/ladders/evolution mods, starters + personality test, enemy tiers/boss slots/
behavior tables, upgrades, missions, level-up stats, gacha config, biome palettes and arena themes, weather kinds, altar
powers, VFX shapes/palettes, icon maps, music scores.

### 10.2 Proposed `tools/export_godot.js` (new script; sketch in Appendix A, tested)

A new exporter loads the same files in a sandbox and **patches the source text in memory** to expose module-private tables
(`LADDERS, EVO_MODS, START, MULT, ADD` in moves.js; `behaviorOf, defFor, HEAL, SHIELD, BOMB, SUMMON` in enemies.js;
`grid, MOVE, TYPE_SHAPE` in vfx.js; `KIND_GLYPH` in icons.js; `BIOME_W` in weather.js). Output (tested against the current
tree, total ≈ 840 KB):

| File | Size | Content |
|---|---|---|
| `pokedex.json` | 120 KB | `G.DEX` (966) |
| `sprite_meta.json` | 539 KB | `G.SPRITE_META` keyed by dex string |
| `moves.json` | 23 KB | `moves` (**post melee transform**), `ladders`, `evo`, `evo_mods`, `need_name`, `start_by_type`, `mult_keys`, `add_keys`, `pool_by_type`, `vfx` (per-move `forMove` result) |
| `types.json` | 2 KB | chart, soft map `{2:1.6, 0.5:0.6, 0:0.3}`, clamp `[0.3, 2.4]`, order, colors, Spanish names |
| `starters.json` | 5 KB | 29 starters, 8 test questions, trait texts |
| `enemies.json` | 20 KB | tiers, boss slots, `late_from`, HEAL/SHIELD/BOMB sets, SUMMON map, `behavior_by_dex` (all 966 — a verification table for your GDScript `behaviorOf`), `candidates_by_tier` |
| `upgrades.json` | 1 KB | 13 upgrades `{id, icon, name, unit, max, base, grow}` |
| `items.json` | 1 KB | `{id, name, desc}` (effects hand-ported, §4.9) |
| `levelup_stats.json` | 1 KB | `{id, icon, title, desc, max}` (effects hand-ported, §6.4) |
| `missions.json` | 1 KB | `{id, ev, param, mode, goals, reward}` (`match/value/text` hand-ported, §8.6) |
| `achievements.json` | 18 KB | 127 `{id, cat, tier, name, desc, goal, reward, title, dex}` (`value` hand-ported, §8.7) |
| `gacha.json` | 1 KB | banners, rates, pity 70, shiny 1/100, refunds, rarity names/colors |
| `world.json` | 19 KB | `tile_px`, 21 biome palettes, `arena_first` (3), arena types, 18 arena themes, weather kinds, weather biome weights, altar powers |
| `vfx.json` | 9 KB | 19 palettes, type → shape, 23 shapes as **letter grids per frame** (`o d m l w L .`) |
| `icons.json` | 16 KB | 55 UI char-map icons, 18 type glyphs, 15 kind glyphs, rarity → ball |
| `music.json` | 4 KB | song scores (only if you resynthesize; see §9.5) |
| `i18n_en.json` | 61 KB | Spanish → English (convert to CSV/PO for `TranslationServer`) |

Functions that cannot be serialized and must be hand-written in GDScript (all specified in this document): item `on/off`
(§4.9), level-up stat `apply` (§6.4), altar power `on/off` (§7.8), mission `match/value/text` (§8.6), achievement `value`
(§8.7), behavior rules (§5.1, verify against `behavior_by_dex`), move `instance/applyMods/levelUp/evolve` (§4.2, §4.7).

Godot side: an autoload `Data` that loads every JSON once with `JSON.parse_string(FileAccess.get_file_as_string(path))`
and builds typed lookup dictionaries (`dex_by[dex]`, `move_by[id]`, …). Note JSON object keys become **strings** (dex
numbers in `sprite_meta.json` → `str(dex)` keys) and all numbers become `float` — cast where you need `int`.

### 10.3 Assets

| Asset | Plan |
|---|---|
| `assets/pokemon/{dex}/{Anim}.png`, `/s/` | copy as-is into `res://assets/pokemon/` (95 MB, ~13,500 files). Import preset: Texture2D, Lossless, mipmaps off; project default filter Nearest. Load lazily with `ResourceLoader.load_threaded_request` (§2.3). Optional build step: pack each Pokémon's 7 sheets into one atlas + JSON to cut file count 7× |
| Fonts | `assets/fonts/PixelifyPS-400.ttf`, `-700.ttf`; convert the CJK `woff2` to TTF/OTF for a fallback |
| VFX sprites | build at startup from `vfx.json` grids × palettes into an atlas `ImageTexture` (≈ 1,000 tiny frames), or pre-bake PNG in a tool |
| Icons | same: build from `icons.json` maps, or pre-bake PNGs; keep integer scaling |
| Ground / props | procedural at runtime (§7.7, §11.4) |
| Music / SFX | pre-render WAV/OGG offline from `audio.js` + `music.js` (§9.5) |
| Pokémon names (English) | not in repo; optional PokeAPI fetch |

### 10.4 Shared deterministic helpers (port bit-exact; verified with Python against Node)

```gdscript
# res://core/u.gd  (class_name U) — JS Math.imul / >>> semantics on 64-bit ints
const M32 := 0xFFFFFFFF

static func imul32(a: int, b: int) -> int:
	a &= M32; b &= M32
	return ((a & 0xFFFF) * b + ((((a >> 16) * b) & 0xFFFF) << 16)) & M32   # never overflows int64

static func hash01(x: int, y: int, seed: int = 0) -> float:   # G.U.hash — pass int(x) (JS x|0 truncates toward 0)
	var h := imul32(x, 374761393) ^ imul32(y, 668265263) ^ imul32(seed, 2246822519)
	h = imul32(h ^ (h >> 13), 1274126177)
	h ^= h >> 16
	return float(h) / 4294967296.0

static func damp(a: float, b: float, rate: float, dt: float) -> float:
	return b + (a - b) * exp(-rate * dt)
```

Test vectors (JS output): `hash(0,0,0) = 0.0`, `hash(1,0,0) = 0.5081244609`, `hash(5,-3,4242) = 0.0931424084`,
`hash(25,7,11) = 0.3687830963`, `hash(-17,123,909) = 0.5947388003`, `hash(1000,7,11) = 0.0754888116`,
`hash(123456,-654321,2246822519) = 0.7198840545`.

Mission RNG (`progress.js:27-30`, FNV-1a + mulberry32) — same masking rules:
```gdscript
class Mulberry:
	var h: int
	func _init(seed_str: String) -> void:
		h = 2166136261
		for c in seed_str.to_utf8_buffer():      # JS charCodeAt: ASCII-only seeds here ('d20261013' + digits)
			h = U.imul32(h ^ c, 16777619)
	func next() -> float:
		h = (h + 0x6D2B79F5) & U.M32
		var t := h
		t = U.imul32(t ^ (t >> 15), t | 1)
		t = (t ^ ((t + U.imul32(t ^ (t >> 7), t | 61)) & U.M32)) & U.M32
		return float((t ^ (t >> 14)) & U.M32) / 4294967296.0
```
Test vector: seed `"d20261013" + "1700000000000"` → `0.4235570813, 0.6687115475, 0.4403369226`.

JS → GDScript numeric pitfalls (apply everywhere):

| JS | GDScript equivalent | Why |
|---|---|---|
| `a / b` (always float) | `float(a) / b` when both may be `int` | GDScript `int / int` truncates (e.g. `ceil(xp / 14)`, `time / 240`) |
| `Math.round(x)` | `floor(x + 0.5)` | JS rounds .5 toward +∞; GDScript `round()` rounds half away from zero (differs for negatives) |
| `x \| 0`, `~~x` | `int(x)` | truncation toward zero |
| `((a % n) + n) % n` | `posmod(a, n)` / `fposmod(a, n)` | sign of `%` with negatives |
| `x >>> n` | `(x & 0xFFFFFFFF) >> n` | unsigned shift |
| `Math.imul(a, b)` | `U.imul32(a, b)` | 32-bit wraparound |
| `Math.random()` | `randf()` (seeded `RandomNumberGenerator` if you want replays) | — |
| `Math.atan2(y, x)` | `atan2(y, x)` / `Vector2.angle()` | same convention (y down) |
| `performance.now()` (ms) | `Time.get_ticks_msec()` | wall clock |

Value noise / fbm (`world.js:50-59`) are built on `hash01` — port the formulas in §7.2 verbatim and diff a chunk's terrain
against a Node dump (`G.World` / `G.Tiles.paintChunk` can be run in the same sandbox) before trusting it.

---

## 11. Godot 4.7 architecture & phased port plan

### 11.1 Guiding principles

1. **Mirror the JS architecture: data-oriented simulation in plain GDScript objects, rendered by a few custom-drawn
   layers.** The JS game is not entity/scene based; porting it 1:1 (managers + arrays + an explicit update order) is the
   fastest way to reach behavioral parity, and avoids scene-tree overhead for hundreds of short-lived objects.
2. **No physics engine.** Collisions are circle-vs-tile-AABB push-out, circle-vs-circle props, swept circle vs. enemies,
   spatial hash queries (§4.6, §5.12, §7.5). Port them as math; `CharacterBody2D`/`Area2D` would change feel and cost.
3. **Same units.** 1 Godot pixel = 1 wu; Camera2D zoom reproduces the 768-wu view; every number in this spec ports verbatim.
4. **Explicit state machine** (`ui/playing/levelup/paused/choice/over`, §1.3) instead of `get_tree().paused` for the sim;
   UI nodes run with `PROCESS_MODE_ALWAYS`. Clamp `dt = min(delta, 1/30)` exactly like JS.
5. **Determinism where JS is deterministic** (hash/noise/behaviors/missions) — bit-exact helpers + test vectors (§10.4).

### 11.2 Project settings

| Setting | Value |
|---|---|
| Renderer | **Compatibility** (best for web export and low-end mobile; all needs are 2D) |
| `display/window/stretch/mode` | `canvas_items`, aspect `expand`, base size 1280×720 (HUD numbers in this spec are CSS px at ~1280 wide) |
| Camera2D zoom | `z = min(vis.x/768, vis.y/420)` from `get_viewport().get_visible_rect().size`, recomputed on `size_changed` |
| `rendering/textures/canvas_textures/default_texture_filter` | Nearest |
| `rendering/2d/snap/snap_2d_transforms_to_pixel` / `snap_2d_vertices_to_pixel` | on / on |
| Physics | unused (can leave default) |
| Input map | `move_up/down/left/right` (WASD + arrows + left stick), `slot_1..4`, `cycle_prev` (Q), `cycle_next` (E, Tab), `pause` (Esc, P), `reroll` (R), `pick_1..4`; use **physical** keycodes |

### 11.3 Scene tree and autoloads

```
Autoloads (singletons):
  Data      – loads godot/data/*.json (§10.2), lookup tables
  Save      – newSave/migrate/sanitize/commit (user://save.json), grant/owns helpers (§8.1)
  Settings  – user://settings.cfg (quality, dmgNumbers, calm, fps, stick, volumes, lang)
  Sfx/Music – audio buses, MIN_GAP limiter, voice pool, crossfading music (§9.5)
  Sprites   – sheet cache (threaded loads, LRU 200/20 s), white-silhouette cache, meta helpers (§2)
  Progress  – missions/achievements events (§8.6-8.7)

Main.tscn (Node)
├── Game (Node, script game.gd)          – state machine, run lifecycle, update order (§1.4), onCollect (§3.9)
│   ├── WorldView (Node2D)               – everything in world space
│   │   ├── Ground      (Node2D, z -10)  – chunk Sprite2D pool (baked ImageTextures) or ground shader quads (§11.4)
│   │   ├── Liquid      (Node2D, z -9)   – _draw: shimmer rects (§7.7)
│   │   ├── Hazards     (Node2D, z -8)   – _draw: telegraphs (§5.7)
│   │   ├── GroundFields(Node2D, z -7)   – _draw: patches, mines, meteor shadows (§4.6)
│   │   ├── Pickups     (Node2D, z -6)   – _draw (§5.10)
│   │   ├── Entities    (Node2D, z 0)    – _draw: y-sorted props + enemies + player + rift + event actors (§1.6)
│   │   ├── Projectiles (Node2D, z 1)    – _draw: shadows, red rings, VFX sprites at y-18
│   │   ├── AirFields   (Node2D, z 2)    – _draw: falling meteors, turrets
│   │   ├── FX          (Node2D, z 3)    – _draw: beams, slashes, rings, particles, sprites, damage text
│   │   └── Camera2D
│   ├── ScreenFX (CanvasLayer 1)         – weather tint + particles (_draw), vignette+fog ColorRect shader
│   ├── HUD (CanvasLayer 2)              – Control with _draw for bars/arrows/banner + TextureButtons for move slots/pause
│   ├── Touch (CanvasLayer 3)            – floating joystick (_unhandled_input by touch index)
│   ├── Screens (CanvasLayer 4)          – Control scenes: Menu, Dex, Upgrades, Gacha(+SlotMachine), Goals, Settings,
│   │                                      Test/Result/Starters, LevelUp, Bond, Item, Pause, Results, Toast, AchPopup
│   └── Flash (CanvasLayer 5)            – full-screen ColorRect
└── (MenuBackdrop reuses WorldView with seed 4242 and 20 wanderers while state == 'ui')
```

Simulation classes (`RefCounted`, owned by managers, no nodes): `Player`, `Enemy`, `Projectile`, `Pickup`, `Field`,
`Hazard`, `Prop`, `Chunk`; managers (plain scripts instanced by `Game`): `World` (chunks, terrain, props, collision),
`PathField`, `EnemyMgr` (+ `SpatialGrid`, corpses), `Projectiles`, `Combat` (cast + resolve + fields), `Pickups`,
`Spawner`, `LevelUp`, `Interact`, `Events`, `Weather`, `Rift`, `Hazards`, `FX`, `Animator`.
Use typed arrays where hot (`PackedFloat32Array`/`PackedInt32Array` for the flow field and particles), iterate by index,
and **defer additions/removals** (JS relies on `for…of` seeing appended minions, reverse splices, and `die()` inside
`hurt()`; reproduce with index loops over a snapshot + pending lists).

### 11.4 Rendering choices

- **Entities: custom `_draw()`** in one `Entities` node, y-sorted array each frame, `draw_texture_rect_region` with the
  per-animation anchor (§2.2). This mirrors JS exactly, batches per texture, and handles ≤ ~150 sprites easily (cap 64
  enemies + corpses ≤ 120 + props on screen). `AnimatedSprite2D` is a poor fit (per-animation frame sizes/anchors, 8 rows,
  per-frame durations in 1/60 s) — if you prefer nodes, use `Sprite2D` with `region_rect`/`offset` driven by the same
  `Animator` and a parent with `y_sort_enabled`.
- **Hit flash**: per sheet, build a white silhouette once: `white.fill(Color.WHITE)` then
  `out.blit_rect_mask(white, sheet_image, Rect2i(Vector2i.ZERO, size), Vector2i.ZERO)` (C++ op, fast) →
  `ImageTexture`; draw it instead of (enemies) or over at α 0.55 (player). A per-node `canvas_item` shader with a `flash`
  uniform is the alternative if entities are nodes.
- **MultiMeshInstance2D** is not a good fit for Pokémon (one texture per species/animation); consider it only for
  particles if profiling demands it (1,400 `draw_rect` calls per frame are fine in Compatibility).
- **Ground** (the heaviest CPU part — ~65k px per chunk with several hash calls each; ~4 ms in V8, likely 100–400 ms in
  GDScript): 
  - Phase 1: flat-color tiles (palette `floor[0]`, `wallTop[0]`, `liq`) baked into a 16×16 `Image` per chunk scaled ×32 —
    instant, correct collision layout.
  - Phase 3: port `paintFloor/paintWall/paintLiquid/dirtMask` literally into a worker (`WorkerThreadPool.add_task`) that
    fills a `PackedByteArray` → `Image.create_from_data(256, 256, false, FORMAT_RGBA8, bytes)` → `ImageTexture` on the
    main thread; show the flat placeholder until ready; keep ≤ 48 textures FIFO. Verify pixel-exactness against a Node
    dump of `G.Tiles.paintChunk`. If still too slow, move the painter to a `canvas_item` shader (uint hashing; the per-tile
    "dirt tile" aggregate needs a first pass or CPU precompute) or a GDExtension.
  - Biome crossfade: draw old texture then new with `modulate.a = smoothstep(t/2.6)` (chunks are opaque).
- **Props**: port the small painters to build `ImageTexture`s cached by `"biome/type/variant"`; draw in the y-sorted pass.
- **Text in world space** (damage numbers): `draw_string` with the pixel `FontFile` + outline (`draw_string_outline`
  first); it scales with the camera like JS.
- **Ellipses / dashed strokes**: helper funcs — `draw_set_transform(center, 0, Vector2(1, ry/rx))` + `draw_circle` for
  fills, generated point arrays + `draw_polyline` for strokes, manual dash runs for `setLineDash`.
- **Vignette/fog**: one full-screen `ColorRect` shader (inner/outer radii in screen px, §7.7, §1.6).

### 11.5 Performance budget (GDScript)

| System | Load | Note |
|---|---|---|
| Enemies | ≤ 64 (+ ≤ 15 minions, bosses) | per-enemy update + soft separation over 3×3 cells: fine |
| Spatial grid | rebuilt per frame, cell 52 | `Dictionary[Vector2i, Array]` or a fixed 2D array around the camera |
| Projectiles | ~50–300 | swept collision via grid queries |
| Flow field | 57×57 BFS per 0.35 s | `PackedInt32Array` ring queue: < 1 ms |
| LOS checks | per enemy every 200 ms | cheap |
| Pickups | ≤ 420 | one loop |
| FX | ≤ 1,400 particles | quality caps §2.7 |
| Ground baking | ~65k px / chunk | **worker threads** (see 11.4) |

Profile early with 64 enemies + 300 projectiles + bursting FX at 1× and on a low-end Android device.

### 11.6 Asset pipeline

1. `node tools/export_godot.js` → `godot/data/*.json` (Appendix A).
2. Copy `assets/pokemon/` → `res://assets/pokemon/` with an import preset (Lossless, no mipmaps, Nearest). Optional:
   a tool script that packs each Pokémon's 7 sheets (normal + shiny) into one atlas PNG + JSON offsets to reduce file count
   from ~13,500 to ~1,900.
3. Fonts → `res://assets/fonts/` (convert CJK woff2).
4. Audio pre-render (headless Chromium + `OfflineAudioContext` running `audio.js`/`music.js`) → `res://assets/audio/`.
5. VFX/icons: generate at startup from JSON (or pre-bake PNG atlases with a `@tool` script).
6. Keep licensing files (`CREDITS.md` — SpriteCollab CC BY-NC 4.0 with 114 artists; Pixelify OFL) in the Godot project.

### 11.7 Phased plan

**Phase 0 — Foundation (1–2 days)**: project settings (11.2); `export_godot.js`; `Data` autoload; `U` helpers with the
§10.4 test vectors as unit tests (GUT or a simple `@tool` test scene); `Sprites` loader + `Animator` + shadow; camera.

**Phase 1 — Minimal playable core loop** (goal: feels like the JS game for the first 5 minutes):
- Fixed partner (e.g. dex 4 Charmander, start move from `startMoveOf`), stats from `pokedex.json`, no perks.
- World: exact `terrainRaw` (§7.2) for biome 0 with flat-color chunks; `collide`/`isFree`/`isLiquid`; water slow; no props
  (or trees as solid circles only).
- Player: movement (§3.4), targeting (§3.5), hurt/i-frames/flash (§3.6), regen, XP curve (§3.8), death → 1.3 s → results.
- Enemies: tiers + `defFor` + `rollRun` cast (behaviors other than chase/tank/runner/charger may temporarily fall back to
  chase), spawner rate/CAP/elite/ring placement/surges (§5.2-5.3), time scaling, contact damage (§5.8), separation +
  grid (§5.12), knockback, statuses, corpses; straight-line chase (no flow field yet); laggard relocation.
- Moves: **projectile, melee, aura** (+ `orbit` if time allows) with exact casting loop (§4.4), damage formula & type chart
  (§4.5), ladders (§4.2); all moves of those kinds from `moves.json`.
- Pickups: `xp`/`xpBig` gems with magnet physics, merge cap; heal/magnet/bomb drops.
- Level-up: `new/up/stat` cards with weights and caps (§6), keys 1–3, reroll.
- HUD: XP bar, HP bar + numbers, name/level, timer, sub-line (biome · kills · coins), move slots with cooldown overlay +
  level pips, banner, damage numbers; pause screen; results screen; restart.
- Audio: optional (one pre-rendered loop + hit/xp SFX).
- Acceptance: enemy HP/dmg multipliers at t = 0/60/180/300 s match §5.3; cumulative XP to reach level 5 = 510 and level 6
  = 768 (before `xpMul`); spawn rate at 60 s ≈ 0.907/s; projectiles hit enemies hugging the player (swept collision,
  §4.6 — the GDD log records this exact bug).

**Phase 2 — Combat completeness**: remaining 10 kinds (nova, beam, buff, boomerang, chain, mine, meteor, turret, dash,
trail, cone), evolutions + gold card, held items + swap UI, all enemy behaviors (charger, ranged/fan/beamer/zoner,
healer/shielder/summoner, jumper, bomber), enemy projectiles, hazards + telegraphs, bosses (5 slots, AI, enrage, casts,
boss bar, music switch), flow-field pathing + LOS + unstick, VFX shapes/palettes, FX layer parity, crits, shiny spawns +
catch flow + HUD arrows.

**Phase 3 — World completeness**: faithful ground painter (threaded) + crossfade, 21-palette biome cycle, props + prop
painters + destructibles + loot, liquids (lava/poison/spark/swamp/ice), interactables (altars, springs, locked chests,
traps), events (horde, golden hour, lost Pokémon, thieves), weather (logic + tint/particles + fog), rifts (portal, arena
generation, legendary, keepInside, win/loss, stash/restore) and bonds (fusion UI + multi-move slots).

**Phase 4 — Meta-progression**: Save (format §8.1, migrate/sanitize), end-of-run coins + stats, results screen parity,
upgrade shop (+ ban picker, hotkeys `pbind`), collection/partner/shiny toggle, gacha (logic + slot machine + reveal cards),
personality test + starters, missions (Madrid-time period ids + seeded RNG), achievements + titles + popups, settings.

**Phase 5 — Presentation & platforms**: menu theme (Theme resource, 9-patches for the PMD boxes), menu backdrop, audio
pipeline + buses + limiter, i18n (CSV/PO from `i18n_en.json` + `lang-zh.js`; convert all concatenations to `tr().format()`),
touch joystick + safe areas + portrait handling, gamepad, quality auto-scaling (§8.8), FPS counter, accessibility toggles
(`calm`, damage numbers).

**Excluded**: login/accounts (use a local profile), cloud sync, friends, ranking, co-op, news/support/legal, auto-updater.
When porting gameplay code, delete every `G.Coop`/`G.Social`/`G.Ranking`/`remote`/`ghost` branch (single player = host).

### 11.8 Hard-to-port items and recommendations

| Item | Why hard | Recommendation |
|---|---|---|
| Procedural music/SFX (Web Audio synth, convolution reverb, compressor, look-ahead sequencer) | no equivalent; GDScript per-sample synthesis too slow for ~20 voices | pre-render offline with the original JS in `OfflineAudioContext`; pitch-shift parametric SFX (§9.5) |
| Ground painter (per-pixel `ImageData`) | CPU cost in GDScript | worker threads → `Image.create_from_data`; shader or GDExtension as fallback (§11.4) |
| 32-bit integer math (`Math.imul`, `>>>`, `x\|0`) | GDScript ints are 64-bit | `U.imul32`/`hash01` + test vectors (§10.4) |
| PMD sprite sheets with per-anim anchors and 1/60 s frame durations | `AnimatedSprite2D`/`SpriteFrames` assume uniform frames/offsets | custom `Animator` + `draw_texture_rect_region` (§2.2) |
| ~13,500 PNGs | slow first import, memory | threaded lazy loading + LRU; optional per-Pokémon atlas packing |
| `source-in` white flash | no composite ops in `_draw` | `Image.blit_rect_mask` white sheets or shader (§11.4) |
| DOM/CSS menus (gradients, double borders, flex/grid, hover transforms, responsive breakpoints) | Godot `StyleBoxFlat` lacks gradients/multi-borders | Theme + `StyleBoxTexture` 9-patches; containers; Tweens; `size_changed` layout variants (§9.1) |
| Automatic translation (MutationObserver + monkey-patched `fillText`) | Godot needs explicit `tr()` | convert every string build to `tr("…{0}…").format()`; Spanish msgids (§9.6) |
| Canvas ellipses, dashed lines, radial gradients | missing direct APIs | helpers + shaders (§11.4) |
| Frame-rate-dependent JS quirks (`vy *= 0.94` per frame in damage text, weather/flash) | dt-dependent | use `pow(k, dt*60)`; keep `dt ≤ 1/30` |
| Wall-clock timers (`performance.now`): Focus Sash 60 s, pathing LOS 200 ms, pulses/blinks, liquid shimmer, grass sway | pause semantics differ | `Time.get_ticks_msec()` for visuals; consider game time for Focus Sash (behavior change — document it) |
| Arena at tile 5000–8000 (~160k–256k wu) | float32 precision & noise from float coords | compute noise from ints; optionally relocate the arena offset |
| Pokémon names are Spanish only | English UI | optional PokeAPI name fetch |

---

## 12. Appendix: top gotchas

1. **Stats are a stack of multiplicative layers — port them from data, not from the GDD.** Enemy HP =
   `def.hp (tier × species) × (1 + t/95) × late(t) × hpK(t)` then `×1.6` elite (≥ 55 alive) then `×2` shiny; damage also
   `×2.4` (`DMG_K`), XP `×5.6` (`XP_K`). Moves get a **load-time melee buff** (`dmg×1.2`, `radius×1.25`, `arc×1.25 ≤ 3`)
   and ladder/evolution mods where a multiplicative key with no base value is *assigned* (§4.2). Use the exported
   post-transform JSON (§10.2) and the acceptance numbers (§11.7).
2. **Bit-exact 32-bit hashing.** `G.U.hash` (Math.imul / `>>>` / `|0`) drives terrain, props, ground art, enemy
   personalities (`hash(dex,7,11)`), boss move sets, and the mission RNG. GDScript ints are 64-bit: use `U.imul32` and the
   test vectors (§10.4); verify `behaviorOf` against `enemies.json → behavior_by_dex`.
3. **PMD sprites are feet-anchored with a different frame size and anchor per animation** (8 direction rows, per-frame
   durations in 1/60 s, one-shot anims over a background loop, `Faint` holds). Use a custom `Animator` with
   `draw_texture_rect_region` at `(x - ax*2*scale, y - ay*2*scale)`; collision radius and HP-bar height are derived from the
   Idle frame (§2.2). ~13,500 PNGs must be lazily loaded with an LRU.
4. **Time semantics.** Variable `dt` clamped to 1/30 s (slow-mo below 30 FPS), state-machine pauses where FX keep running at
   0.25×, run clock that keeps ticking inside rift arenas while spawning stops, a few **per-frame** (not per-second)
   damping factors, and wall-clock timers (`performance.now`) for Focus Sash, LOS throttling and pulses (§1.4, §11.8).
5. **Everything visual and audible is procedural** — ground painter, props, VFX, icons are generated per pixel from
   hashes/char maps, and all music/SFX come from a Web Audio synth. Plan for threaded ground baking (or a shader), generate
   VFX/icons from the exported grids, and pre-render audio offline. The menus are DOM with implicit translation — they must
   be rebuilt as Control scenes with explicit `tr()` calls.

Also worth remembering: code ≠ GDD on several points — enemy cap **64** (not 280), the run cycles through **21** biome
palettes every 4 min (not 3), rift chance 20% escalating (not 14%), boss `ticket10` 1/3 (not always), wild ticket 1/400;
legendaries defeated in rifts are **not** added to the collection; quitting from pause still pays out coins.

---

## Appendix A — `tools/export_godot.js` (sketch, tested against the current tree)

Run: `node tools/export_godot.js . godot/data` (it only reads the JS files; patches are applied in memory).

```js
/* Sketch of tools/export_godot.js — dumps every static table the Godot port needs.
 *   node export_godot.js <repoRoot> <outDir>
 * Loads the game's data files in a vm sandbox (like tools/export_data.js). Module-private
 * tables are exposed by patching the source text in memory (files on disk are untouched). */
const fs = require('fs'), path = require('path'), vm = require('vm');
const ROOT = process.argv[2] || path.join(__dirname, '..');
const OUT = process.argv[3] || path.join(ROOT, 'godot', 'data');
const noop = () => {};
const fakeCtx = new Proxy({}, { get: () => noop });
const G = {};
const sandbox = {
  G, console, Math, JSON, Date, Map, Set, Object, Array, Number, String, RegExp, Promise, Symbol, Infinity, NaN, isFinite, parseInt, parseFloat,
  location: { pathname: '/', protocol: 'file:', search: '' }, navigator: { language: 'es', languages: ['es'] },
  localStorage: { getItem: () => null, setItem: noop },
  document: { documentElement: { style: { setProperty: noop } }, createElement: () => ({ getContext: () => fakeCtx, width: 0, height: 0 }),
              addEventListener: noop, querySelector: () => null, body: {} },
  addEventListener: noop, matchMedia: () => ({ matches: false }), CanvasRenderingContext2D: function () {}, Image: function () {},
  performance: { now: () => 0 }, setTimeout: noop, setInterval: noop, requestAnimationFrame: noop
};
sandbox.window = sandbox;
vm.createContext(sandbox);
const load = (f, patch) => {
  let src = fs.readFileSync(path.join(ROOT, f), 'utf8');
  if (patch) { const s2 = patch(src); if (s2 === src) throw new Error('patch did not apply: ' + f); src = s2; }
  vm.runInContext(src, sandbox, { filename: f });
};
const EN = {};
load('js/core/util.js'); load('js/core/i18n.js');
const add = G.I18n.add; G.I18n.add = (d, l = 'en') => { if (l === 'en') Object.assign(EN, d); add(d, l); };
load('js/data/lang-en.js'); load('js/core/settings.js'); load('js/data/music.js'); load('js/data/pokedex.js'); load('js/data/sprites-meta.js');
G.Sprites = { PX: 2, hovers: d => !!(G.SPRITE_META[d] && G.SPRITE_META[d].hv), hasShiny: d => !!(G.SPRITE_META[d] && G.SPRITE_META[d].sh) };
load('js/data/moves.js', s => s.replace('G.Moves = { ALL: RAW,', 'G.Moves = { LADDERS, EVO_MODS, START, MULT, ADD, ALL: RAW,'));
load('js/data/enemies.js', s => s.replace('TIERS, BOSS_SLOTS, LATE_FROM,', 'behaviorOf, defFor, HEAL: [...HEAL], SHIELD: [...SHIELD], BOMB: [...BOMB], SUMMON, TIERS, BOSS_SLOTS, LATE_FROM,'));
for (const f of ['js/data/types.js', 'js/data/starters.js', 'js/data/upgrades.js', 'js/data/items.js',
                 'js/data/missions.js', 'js/data/achievements.js', 'js/world/tiles.js']) load(f);
load('js/entities/vfx.js', s => s.replace('return { PAL, SHAPES, draw,', 'return { grid, MOVE, TYPE_SHAPE, PAL, SHAPES, draw,'));
load('js/ui/icons.js', s => s.replace('return { canvas, url,', 'return { KIND_GLYPH, canvas, url,'));
load('js/systems/levelup.js'); load('js/systems/gacha.js');
load('js/systems/weather.js', s => s.replace('KINDS, reset,', 'KINDS, BIOME_W, reset,'));
load('js/systems/interact.js');

const strip = o => JSON.parse(JSON.stringify(o));       // drops functions
const files = {};

files['pokedex.json'] = G.DEX;
files['sprite_meta.json'] = G.SPRITE_META;
const M = G.Moves;
files['moves.json'] = {
  moves: M.ALL.map(m => { const o = strip(m); delete o.ups; return o; }),   // post melee transform
  ladders: M.LADDERS, evo: M.EVO, evo_mods: M.EVO_MODS, need_name: M.NEED_NAME, start_by_type: M.START,
  mult_keys: M.MULT, add_keys: M.ADD, pool_by_type: M.POOL,
  vfx: Object.fromEntries(M.ALL.map(m => [m.id, G.VFX.forMove(m)]))
};
files['types.json'] = { chart: G.Types.CHART, soft: { '2': 1.6, '0.5': 0.6, '0': 0.3 }, min: 0.3, max: 2.4,
  order: Object.keys(G.U.TYPE_NAME), color: G.U.TYPE_COLOR, name_es: G.U.TYPE_NAME };
files['starters.json'] = { starters: G.STARTERS, test: G.PERSONALITY_TEST, trait_text: G.TRAIT_TEXT };
const E = G.Enemies;
files['enemies.json'] = { tiers: E.TIERS, boss_slots: E.BOSS_SLOTS, late_from: E.LATE_FROM,
  heal: E.HEAL, shield: E.SHIELD, bomb: E.BOMB, summon: E.SUMMON,
  behavior_by_dex: Object.fromEntries(G.DEX.map(p => [p.dex, E.behaviorOf(p)])),          // verification table
  candidates_by_tier: E.TIERS.map(t => E.candidates(t).map(p => p.dex)) };
files['upgrades.json'] = G.Upgrades.LIST;
files['items.json'] = strip(G.Items.LIST);
files['levelup_stats.json'] = strip(G.LevelUp.STATS);
files['missions.json'] = { daily: strip(G.MissionDefs.daily), weekly: strip(G.MissionDefs.weekly) };
files['achievements.json'] = { cats: G.AchDefs.CATS, list: strip(G.AchDefs.LIST) };
files['gacha.json'] = { banners: G.Gacha.BANNERS, rates: G.Gacha.RATES, pity: G.Gacha.PITY_5, shiny_rate: G.Gacha.SHINY_RATE,
  refund: G.Gacha.REFUND, rarity_name: G.Gacha.RARITY_NAME, rarity_color: G.Gacha.RARITY_COLOR };
files['world.json'] = { tile_px: G.Tiles.T, biomes: G.Tiles.BIOMES, arena_first: G.Tiles.ARENA, arena_types: G.Tiles.ARENA_TYPES,
  arena_themes: G.Tiles.ARENA_THEMES, weather: G.Weather.KINDS, weather_biome_w: G.Weather.BIOME_W, altar_powers: strip(G.Interact.POWERS) };
// VFX shapes as palette-letter grids (o d m l w L) per frame.
const shapes = {};
for (const [name, S] of Object.entries(G.VFX.SHAPES)) {
  const frames = [];
  for (let f = 0; f < (S.frames || 1); f++) { const P = G.VFX.grid(S.w, S.h); S.gen(P, f); frames.push(P.g.map(r => r.map(c => c || '.').join(''))); }
  shapes[name] = { w: S.w, h: S.h, dir: !!S.dir, spin: !!S.spin, frames };
}
files['vfx.json'] = { pal: G.VFX.PAL, type_shape: G.VFX.TYPE_SHAPE, shapes };
files['icons.json'] = { ui: G.Icons.UI, type_glyph: G.Icons.TYPE_GLYPH, kind_glyph: G.Icons.KIND_GLYPH, rarity_ball: G.Icons.RARITY_BALL };
files['music.json'] = { songs: G.MUSIC, biome_music: G.BIOME_MUSIC };
files['i18n_en.json'] = EN;

fs.mkdirSync(OUT, { recursive: true });
for (const [name, data] of Object.entries(files)) {
  const s = JSON.stringify(data);
  fs.writeFileSync(path.join(OUT, name), s);
  console.log(name.padEnd(22), (s.length / 1024).toFixed(1).padStart(7), 'KB');
}
```

