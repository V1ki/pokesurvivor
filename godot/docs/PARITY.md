# Feature parity: web game (JS) → Godot port

A systematic audit of the Godot port against the browser game (`../js`, `../dev.html`,
`../css/style.css`, plus `../mobile/shell.js` for the Android app), done module by module after
Phases 0–5 and audio. Every gameplay rule, screen, button, setting, HUD element, banner / toast,
sound and music call, shortcut and touch control was located on both sides and read to confirm
that it behaves the same (same text, constants, condition and timing).

Out of scope by design (single-player, offline): Firebase accounts and login, cloud saves,
friends, lobby / co-op, ranking, nickname, invites, news (changelog), support / donations, the
auto-updater, browser fullscreen / iOS tips. Those rows are marked *excluded (online)*. The web
game's own offline app mode (`window.PS_APP`, `.ps-app` in the CSS) is the reference for what an
offline build shows (e.g. "Entrenador" in the top bar, no Friends / Ranking).

**Status**: *present* = same behaviour · *different → fixed* / *missing → fixed* = was not the
same, fixed by this audit (Godot file named in the row) · *different* / *missing* = still not the
same (reason in Notes; see *Remaining*) · *excluded (online)* · *n/a* = not applicable natively.
Line numbers are from the audit and can drift. Many numeric rules are additionally covered
bit-exactly by the unit tests (marked *tested*).

## Summary

| | rows |
|---|---|
| checked (rows below; each row may group several items of the same rule) | **424** |
| present | 292 |
| fixed by this audit | 93 |
| still different / missing (intended or cosmetic, see *Remaining*) | 13 |
| excluded (online) / n/a | 24 / 2 |

The audit itself read ~850 individual items (6 parallel sweeps: run core, combat, world, HUD,
meta screens, core/data, plus a cross-reference of all 98 `G.Audio` call sites and the generic UI
sounds). New checks for the fixed rules: `tests/parity_tests.gd` (17 checks, in `run_tests.gd`;
also `res://tests/run_parity_tests.gd` alone) and one more step in `tests/nav_smoke.gd`.

### Fixed by this audit (by area)

- **Credits / licensing**: Settings › Acerca de now has the web's version line ("Versión 1.2 ·
  2026-10-09"), "Créditos completos" (SpriteCollab CC BY-NC 4.0 attribution with the 114 artists
  of `CREDITS.md`, PokeAPI, Pixelify Sans and Fusion Pixel Font under SIL OFL 1.1 with their full
  licence texts, trademark), "Aviso legal y privacidad" (the offline parts of `#scr-legal`:
  fan-project and non-affiliation notice — Nintendo / Creatures / GAME FREAK / The Pokémon Company
  —, crypto, third-party content, contact and removal, source code, privacy), "Contacto" and
  "Código (GitHub)"; the menu shows the web's credits line. `godot/CREDITS.md` and the font
  licences are copied by `exportCredits()` (tools/export_godot.js) and packed by the export preset.
- **Run**: Esc that closes Ajustes over the pause no longer also resumes the run; one tap picks one
  bond / item card (a tap fused two moves); held-item pickups show their own icon and gold pulse;
  deleting / importing the save mid-run ends the run first; silent auto-pause (app in background
  or window minimised, not on focus loss); in-pause sound controls; Android vibration on a hit
  (shell.js); item / bond card keys, chip, dim, compact 2-column bond grid, "Atrás" button;
  results 2×2 stats; aura `drain`; corpse alpha²; damage numbers under weather / vignette; screen
  flash over the joystick.
- **Sounds**: hover on every clickable (not on keyboard focus), the per-button click / back /
  confirm ids of `ui.js`, silent Esc on sub-screens, item choice `click`, slider click only on a
  change.
- **HUD**: `bar()` and slot cooldown clipped like the canvas (true sliver at low HP, flat
  cooldown edge), edge arrows without camera shake, FPS over 0.5 s windows, popup / toast pop-in
  and gold popup titles.
- **Meta screens**: top-bar sound button + sound panel, tickets tooltip, user pill → Perfil,
  credits line, the gacha overlay covering the top bar and ignoring Esc (stale results), public
  profile preview ("Ver mi perfil público"), gold `.gen-tab`s, cyan Normal/Shiny `.seg`, shiny stage
  glow, gold stat bars, tooltips, red struck-through banned chips, Spanish move order
  (`localeCompare('es')`), gacha lines with icons, pull buttons, radial overlay, card glow /
  pulse, slot glow / pop, personality-test answer cursor, starter "Volver" keeping the result,
  "Cuenta" tab, gold headings, joystick description, desktop fullscreen toggle, menu stats in
  white, tiny-screen menu, profile texts, save name "Invitado", boot splash colour.

### Remaining (not changed, with reason / estimate)

| Item | Why it stays | Estimate |
|---|---|---|
| Frame-error recovery + toast "El juego ha fallado…" (game.js:503-518) | GDScript errors don't throw; the JS failure mode doesn't exist | — (won't fix) |
| User-pill sync dot (cloud / browser storage state) | meaningless offline | — (won't fix) |
| Level-up / item card hover `translateX(4px)` | containers re-layout their children; needs a wrapper per card | ~15 lines, cosmetic |
| HUD slot border widths 2.5 / 1.2 px stroked on the edge | StyleBox borders are whole pixels inside the rect | ~10 lines, cosmetic |
| Flat props drawn before the y-sorted list (goal mark always above springs / traps) | inside the `world_view` draw loop being optimised by the performance work | ~5 lines |
| Rift portal motes spawned per rendered frame (also paused) | sim-side `dt·18` is frame-rate independent (Phase 3b note) | ~5 lines, by design |
| BFS flow field spread over ≤3 frames | performance design (Phase 2 note) | by design |
| Ground placeholder until a chunk is painted | async painting (Phase 3a) | by design |
| SFX reverb tails follow the SFX volume (JS: music bus) | pre-rendered audio | won't fix |
| Music muted while the phone app is in the background (a hidden JS tab keeps playing) | intended on phones | by design |
| Language applies live (JS reloads) | intended | by design |
| Debug hooks `debugSpeed` / `debugLevelUp` | dev only (`--start-t` exists) | ~10 lines |
| Boot overlay text ("Juego de supervivencia…", "Cargando…") | the engine splash can't show translated text (colour + icon now match) | ~40 lines (first-frame loading Control) |
| News / changelog (shown in the web's app mode) | excluded by the brief (online features) | ~70 lines (export `G.CHANGELOG` + overlay + seen dot) |

## 1. Run core loop and in-run screens

JS: `game.js`, `core/input.js`, `core/touch.js`, `core/camera.js`, `entities/player.js`, `entities/pickup.js`, `systems/levelup.js`, `ui/run-ui.js`, dev.html `#scr-levelup/#scr-bond/#scr-item/#scr-pause/#scr-over`.

### Run flow & state
| Item | JS | Godot | Status | Notes |
|---|---|---|---|---|
| States ui/playing/levelup/choice/paused/over | game.js:9-19 | sim.gd:7,33 | present | `held` is co-op only |
| Start run: hide screens + top bar | game.js:94-95 | main.gd, meta_ui.gd:56-62 | present | |
| Start run: clear FX/proj/fields/enemies/pickups/spawner/rift/events/weather/path/hazards | game.js:96-106 | sim.gd:67-77 | present | |
| World seed random 0..1e6, biome 0 | game.js:107-109 | sim.gd:79-81 | present | |
| Reset time / pendingLevels | game.js:110 | sim.gd:82-83 | present | |
| Player built with perks + shiny skin (if owned) | game.js:112 | sim.gd:90, meta.gd:19-28 | present | |
| Hotkey binds (pbind) before learning | game.js:117 | sim.gd:103-106 | present | |
| Start move / Veto bans / Repertorio 2nd move | game.js:118-126 | sim.gd:107-116 | present | |
| Camera snapped to player, shake 0, partner preload | game.js:132-134 | sim.gd:65-66,93-96 | present | |
| Music `forest` at start, deathT reset, state=playing | game.js:135-138 | sim.gd:97-99 | present | |
| Ticket banking (saved as soon as picked up) | game.js:171-181,427 | meta.gd:36-48, main.gd | present | |
| Quit run → endRun(false) | game.js:141-144 | main.gd | present | |
| levelXp() for locked chests | game.js:150-154 | world_map.gd:749-754 | present | |
| Full-screen flash (col, dur), calm ×0.3 | game.js:157-158,678-685 | sim.gd:328-331, event_hud.gd:121-125 | present | |
| onRescue: new → grant+commit, else +150 coins; banner 4 s; shinyGet | game.js:248-255 | sim.gd:334-344 | present | |
| onShinyCaught: grant, stats.shinies++, banner, +300 if dupe | game.js:258-268 | sim.gd:347-355, progress.gd:348-354 | present | |
| endRun: guard, music off, sfx gameover/back | game.js:271-279 | sim.gd:120-124 | present | |
| Coins formula + breakdown + "×N.NN Fortuna" | game.js:282-288,312-313 | meta.gd:7-16 | present | tested (phase4) |
| record = time > bestTime; save coins/tickets/stats, runEnd event, checkAch, commit | game.js:289-301 | meta.gd:51-67 | present | |
| bestGroupTime / publishProfile / Ranking | game.js:296,302-307 | — | excluded (online) | |
| Results → afterRun → menu (state ui, backdrop, village music) | game.js:314,792,845-858 | main.gd, backdrop.gd:27-44 | present | Godot resets the menu camera to (0,0); JS keeps the last position (cosmetic) |
| maybeLevelUp → levelup sfx + cards | game.js:319-338 | sim.gd:188-198 | present | |
| Bond offer each frame (quiet) / after a rift (loud) | game.js:595, rift.js:228 | sim.gd:425-426, rift.gd:320-321 | present | |
| Auto-pause only when the app is hidden (visibilitychange), silently | game.js:36,65-68 | main.gd `_notification` | different → **fixed** | Godot played the `pause` sfx and also paused when a desktop window lost focus; now silent (`toggle_pause(true)`), on a phone going to the background or a minimised desktop window |
| Portrait → "Gira el móvil" overlay | game.js:55-62 | project.godot orientation | present | N/A: orientation locked to landscape |
| Frame-error recovery (180 failing frames → quit + toast) | game.js:503-518 | — | missing (won't fix) | GDScript errors don't throw; no equivalent failure mode |
| dt = min(1/30, real); Settings.sample only while playing | game.js:522-524 | main.gd | present | |
| Frozen states: FX + partner anim at 0.25× | game.js:532 | sim.gd:430-433 | present | |
| Death: 1.3 s anim, enemies 0.3×, then endRun(true); not in arena | game.js:547-555 | sim.gd:371-380 | present | |
| Biome every 240 s: sfx, "— name —" 3 s, ring | game.js:558-565 | sim.gd:383-389 | present | |
| Update order | game.js:568-596 | sim.gd:392-426 | present | |
| Music rift / boss / BIOME_MUSIC[b%3] | game.js:593 | sim.gd:423 | present | |
| Render: world, weather, vignette + fog | game.js:643-667 | main.gd:29-46,94-107 | present | |
| FPS counter (colours 50/30) | game.js:525-526,670-677 | hud.gd:204-207 | present | `Engine.get_frames_per_second()` (1 s average) |
| Menu backdrop (seed 4242, 20 wanderers, drift, 30 s biome) | game.js:694-779 | backdrop.gd | present | see §5 |
| Debug hooks debugTime / debugSpeed / debugLevelUp | game.js:784-791 | sim.gd (`--start-t`) | different | dev only |
| Deleting / importing the save from in-run Ajustes abandons the run | settings-ui.js:166-175 | settings_screen.gd | different → **fixed** | JS calls `G.Game.quit()` first; Godot left the run paused under the new save. Now the run is ended (`Sim.end_run`) and the results skipped before the save changes |
| Logout / account delete | settings-ui.js:163-194 | — | excluded (online) | |
| Android haptics on a hit (mobile/shell.js: Haptics.impact LIGHT when HP drops) | mobile/shell.js:38-46 | player.gd `hurt` | missing → **fixed** | `Input.vibrate_handheld(50, 110/255)` (Capacitor LIGHT) on Android + VIBRATE permission |

### Keyboard / gamepad shortcuts
| Item | JS | Godot | Status | Notes |
|---|---|---|---|---|
| Move WASD + arrows, normalized; touch stick overrides | input.js:7-38 | project.godot move_*, main.gd | present | |
| Keys released on blur | input.js:22 | engine | present | |
| Settings open: only Esc (closes it), everything else blocked | game.js:456 | main.gd, meta_ui.gd | different → **fixed** | Esc closing Ajustes over the pause also resumed the run (MetaUI closed settings in `_unhandled_input`, then `_handle_keys` saw a fresh `pause` press). Now the Esc that closes settings is consumed for that frame |
| Level-up 1-3 / numpad, R reroll | game.js:458-461 | main.gd | present | + gamepad Y |
| Bond 1-4, item 1-2 | game.js:464-474 | main.gd | present | |
| Esc on menu sub-screens → menu (not during a pull) | game.js:476-480 | meta_ui.gd:96-115 | present | |
| Esc / P toggle pause (not on results) | game.js:482 | main.gd | present | + gamepad Start |
| 1-4 set active slot, Q cycle −1, E / Tab cycle +1 | game.js:484-488 | main.gd | present | + LB / RB |
| Gamepad / focus navigation, Android back | mobile/shell.js | input_router.gd | present | Godot-only extras + shell.js back button |

### Touch
| Item | JS | Godot | Status | Notes |
|---|---|---|---|---|
| Touch mode auto + switch on first touch | touch.js:12,33,62 | touch.gd:21,74-81 | present | |
| Floating joystick (playing only, first finger), radius 56 × stick, base follows, dead zone 7, full at R/2 | touch.js:15,60-89 | touch.gd:23-105 | present | |
| Reset on blur / pause | touch.js:39-40 | touch.gd:120-122 | present | |
| HUD buttons (padded hit test, 350 ms de-dupe, mouse never opens stick) | touch.js:43-65,109-110 | touch.gd:26-114 | present | |
| Slot tap → setActive + click; pause button 40×40 | hud.js:258,355-364 | hud.gd:124-126,188-196 | present | |
| Joystick drawing, safe-area insets | touch.js:92-129 | touch.gd:117-138 | present | |
| Key hints hidden on touch (`body.touch kbd`, `.card .key`) | style.css:677,709-710 | screens.gd, item_choice.gd, bond_ui.gd | different → **fixed** | item / bond cards showed their key number on touch; now hidden like level-up |

### Camera / shake / flash
| Item | JS | Godot | Status | Notes |
|---|---|---|---|---|
| VIEW_W 768 / MIN_VIEW_H 420 scale, follow damp 9 | camera.js:8-28 | sim_camera.gd | present | |
| Shake decay 2.4/s, amplitude ×7, kick calm ×0.25 cap 1.2 | camera.js:29-40 | sim_camera.gd:32-44 | present | |
| Pixel-rounded translate, sees(pad 60), outerRadius | camera.js:43-61 | world_view.gd, sim_camera.gd | present | |
| Kick call sites (hurt .28, bomb .8, boss .9/1.1…) | various | various | present | |
| Fog vignette | game.js:660-667 | main.gd:39-43 | present | |

### Player
| Item | JS | Godot | Status | Notes |
|---|---|---|---|---|
| Perk-derived stats, xpFor, getters (reduction cap .8) | player.js:20-97 | player.gd:89-125 | present | tested |
| addMove / arrange (Atajos) / setActive (Choice Band) / cycle | player.js:100-156 | player.gd:141-208 | present | |
| Bonds: BOND_MAX 4, bondOptions, fuse | player.js:162-190 | player.gd:215-264 | present | tested (phase3b) |
| cast: Life Orb, shot sfx map, anim speed | player.js:201-221 | player.gd:297-319 | present | |
| hurt: type × weather, melee ×0.75, i-frames .45, flash, kick, text, burst; Focus Sash; death | player.js:225-256 | player.gd:324-358 | present | |
| heal / gainXp / equip / Shell Bell / powers / buffs / update | player.js:259-326 | player.gd:267-438 | present | |
| Movement, ice slide, liquids, targeting priority, facing | player.js:330-380 | player.gd:441-495 | present | |
| revive (rift) | player.js:384-393 | player.gd:274-283 | present | |
| Draw: halo, shadow, altar ring, blink, flash, buff arcs | player.js:432-471 | world_view.gd | present | |
| frozen / netUpdate / revive ring / name tag | player.js:79,330,402-497 | — | excluded (online) | |

### Pickups
| Item | JS | Godot | Status | Notes |
|---|---|---|---|---|
| KIND table, MAX 420 + merge, BOSS_T10 / LEGEND_T10 / TICKET_RATE | pickup.js:12-52 | pickups.gd:7-67 | present | |
| dropXp, orb spawn, magnet / sticky pull / collect, pullAll | pickup.js:70-150 | pickups.gd:69-141 | present | tested |
| Draw: shadow, glow, XP diamond, spinning coin, heal/magnet/bomb/ticket icons | pickup.js:152-196 | world_view.gd | present | |
| Draw held-item pickup: the item's own icon (24 px) + pulsing gold glow `#ffe14d` r18 α .35±.15 | pickup.js:185-192 | world_view.gd `_draw_pickups` | different → **fixed** | Godot drew the default `star` icon and no glow |
| Collect effects: xp, coin "+N", item → offerItem, tickets "+1 ticket"/"¡Ticket ×10!", heal 30 %, magnet, bomb | game.js:374-450 | sim.gd:225-256 | present | |
| Co-op remote pickups | pickup.js:35-67 | — | excluded (online) | |

### Level-up screen
| Item | JS | Godot | Status | Notes |
|---|---|---|---|---|
| STATS table, new / evo / upgrade / stat cards, weights, offer | levelup.js:9-126 | levelup.gd, levelup_stats.json | present | tested |
| Title "¡Nivel N!", sub "Elige una recompensa · 1 2 3" | dev.html:494-495 | screens.gd | present | |
| Card: tinted icon, title, chip, desc, key; evo gold | run-ui.js:43-58, style.css:655 | screens.gd:141-201 | present | |
| Card hover translateX(4px) | style.css:426 | screens.gd | different | cosmetic (style change only) |
| Hover sfx on cards / buttons (`pointerover` on `.btn,.card…`) | ui.js:68-71 | screens.gd, item_choice.gd, bond_ui.gd | missing → **fixed** | in-run cards now play `hover` (meta buttons already did through UIKit.button) |
| Reroll "Cambiar opciones (N) · R", select sfx | run-ui.js:22-40 | sim.gd:200-210, screens.gd | present | |
| Co-op waiting text | run-ui.js:67-90 | — | excluded (online) | |

### Bond picker
| Item | JS | Godot | Status | Notes |
|---|---|---|---|---|
| Guards, quiet text "Guardas el vínculo…", open with levelup sfx | game.js:350-360 | sim.gd:299-310 | present | |
| Title "¡Vínculo!", hint (hidden compact), sub texts, card descriptions | dev.html:504-505, run-ui.js:178-188 | bond_ui.gd:39-96 | present | |
| Card chip text dark `#10131a` (.tag-chip) | run-ui.js:191-193 | bond_ui.gd | different → **fixed** | was white |
| Key number: muted bordered `.key`, hidden on touch | run-ui.js:194 | bond_ui.gd | different → **fixed** | was a 20 px pink/gold label, always shown |
| Compact: 2-column card grid | style.css:661-665 | bond_ui.gd | different → **fixed** | 2 columns on compact canvases |
| One tap in pair mode picks one move | run-ui.js:201-215 | bond_ui.gd | different → **fixed** | the emulated mouse press and the ScreenTouch both picked: one tap fused two moves. Only the mouse/emulated press picks now (same in item_choice.gd) |
| "Atrás" (step 2) | dev.html:508, run-ui.js:217-221 | bond_ui.gd | different → **fixed** | now a themed `.btn` with the `back` sound |
| Fuse: legend sfx, ring, burst, "¡Vínculo! N movimientos a la vez" | game.js:362-367 | sim.gd:313-323 | present | |

### Item choice
| Item | JS | Godot | Status | Notes |
|---|---|---|---|---|
| Equip directly / "Ya llevas X" / pause + show / "¡Llevas X!" + item event | game.js:381-399 | sim.gd:264-283 | present | |
| Title "¡Un objeto!", sub, cards "Quedarme con X" / "Cambiar a Y" | dev.html:514-515, run-ui.js:146-155 | item_choice.gd | present | |
| Key number: muted bordered `.key`, hidden on touch | run-ui.js:152 | item_choice.gd | different → **fixed** | |
| Choice sound: the card's UI `click` | ui.js:79 | sim.gd:289 | different → **fixed** | Godot played `confirm` |
| Dim backdrop radial (.scr.dim) | style.css:84 | item_choice.gd, bond_ui.gd | different → **fixed** | was a flat dim |

### Pause screen
| Item | JS | Godot | Status | Notes |
|---|---|---|---|---|
| togglePause: `pause` sfx on pause, silent resume | game.js:81-82 | sim.gd:135-140 | present | |
| Title, key hint / touch hint | dev.html:522-524 | screens.gd | present | |
| Inline sound controls (Música, Efectos, "Silenciar todo"/"Activar sonido") | dev.html:526, run-ui.js:224 | screens.gd + ui/sound_controls.gd | missing → **fixed** | shared `SoundControls` (also Settings › Sonido and the top-bar panel) |
| Continuar / Ajustes (Sonido tab) / Abandonar run | dev.html:528-530 | screens.gd | different → **fixed** | they had no UI `click` sound |
| Co-op note / "Salir de la partida" | dev.html:525 | — | excluded (online) | |

### Results screen
| Item | JS | Godot | Status | Notes |
|---|---|---|---|---|
| Title "Has caído…" / "Run terminada" | run-ui.js:106 | results_screen.gd:41 | present | |
| Tiempo / Nivel / Derrotados / Jefes: `.stats` 2×2 boxes, UPPER-CASE 12 px captions, kills as a plain number | run-ui.js:108-111, style.css:434-437 | results_screen.gd | different → **fixed** | was a 4-column strip with `1.234` grouping |
| Coins + breakdown, tickets, shinies caught, record | run-ui.js:112-121 | results_screen.gd | present | |
| Moves joined with " · " | run-ui.js:117-118 | results_screen.gd | different → **fixed** | separators were missing |
| Ko-fi support ask | run-ui.js:96-128 | — | excluded (online) | |
| "Volver al menú" | dev.html:539 | results_screen.gd:97-101 | present | |

## 2. Combat and enemies

JS: `systems/combat.js`, `entities/enemy.js`, `entities/projectile.js`, `systems/spawner.js`, `systems/hazards.js`, `systems/pathing.js`, `entities/vfx.js`, `entities/fx.js`, `data/moves.js`, `data/enemies.js`, `data/items.js`, `data/types.js`. "tested" = covered bit-exactly by `tests/phase2_tests.gd` / `run_tests.gd`.

### Move kinds
| Item | JS | Godot | Status | Notes |
|---|---|---|---|---|
| Active group loop (bonds), own cooldowns, 0.05 s target wait, castAt HUD flash | combat.js:21-77 | combat.gd:45-115, hud.gd:151 | present | reach() tested |
| projectile (n, spread, jitter, muzzle) | combat.js:86-104 | combat.gd:146-155 | present | |
| nova / melee (+ props) / beam (wall cut, strip hits) | combat.js:106-170 | combat.gd:157-218 | present | tested |
| aura: ring + 5 sprites (inward / rise / swirl), damage + props | combat.js:172-194 | combat.gd:220-249 | present | |
| aura `drain` heal `pl.heal(min(Σdrain, 6))` | combat.js:189-195 | combat.gd `_aura` | missing → **fixed** | dead code in JS today (no move has `drain`), ported for parity |
| buff (stacks, ring, rising sprites) | combat.js:198-207 | combat.gd:251-258 | present | tested |
| boomerang / chain (×0.85, Hex ×1.7) / mine / meteor / turret / dash / trail / cone / orbit | combat.js:212-502 | combat.gd:261-562 | present | tested |
| Field draws (ground + air) | combat.js:412-464 | world_view.gd | present | |
| Cast animation per kind + speed-up, cast sound mapping | player.js:207-216 | player.gd:286-311, audio_logic.gd:30 | present | |
| Ladders, evolutions, melee load-time buff | moves.js | moves.gd, moves.json | present | tested (64 moves) |
| ghostCast / ghostOrbit / Coop.cast | combat.js:39,505-523 | — | excluded (online) | |

### Damage, crits, type chart
| Item | JS | Godot | Status | Notes |
|---|---|---|---|---|
| Soft chart ×1.6/×0.6/×0.3, clamp [0.3, 2.4], super/weak labels | types.js:16-49 | types.gd | present | tested |
| Weather multiplier, crit ×1.5 | combat.js:84,526-532 | combat.gd:567-574 | present | tested |
| Damage number colours (crit / super / weak) and sizes | enemy.js:133-134 | enemy.gd:172-182 | present | |
| onDealt, statuses after each hit | combat.js:534-538 | combat.gd:576-583 | present | |
| Enemy → player typed damage, melee −25 %, colours | player.js:226-242 | player.gd | present | |
| Enemy damage def·sc·DMG_K·elite | spawner.js:84-86 | spawner.gd:109-121 | present | tested |

### Status effects
| Item | JS | Godot | Status | Notes |
|---|---|---|---|---|
| Burn (≤8, 3 s, 0.5 s ticks), poison (≤8, 4 s, 0.6 s), slow | enemy.js:140-152,252-262 | enemy.gd:188-280 | present | |
| Burn/poison ground ellipse | enemy.js:710-716 | world_view.gd | present | |
| Shield absorb (#9fd8ff number), expiry | enemy.js:112-117,303 | enemy.gd:155-162,334-337 | present | |

### Held items
| Item | JS | Godot | Status | Notes |
|---|---|---|---|---|
| 11 items (Leftovers, Choice Band + slot lock, Quick Claw, Amulet Coin, Lucky Egg, Choice Scarf, Assault Vest, Life Orb, Focus Sash, Shell Bell, Rocky Helmet), roll(except) | items.js, player.js, combat.js:668 | items.gd, player.gd, combat.gd:708 | present | tested |

### Projectiles
| Item | JS | Godot | Status | Notes |
|---|---|---|---|---|
| Defaults, orbs, boomerang, homing, trails, cull, clearOrbs | projectile.js:19-91 | projectiles.gd | present | tested |
| Swept collision, pierce, rehit, walls / props | combat.js:576-656 | combat.gd:619-695 | present | tested |
| Enemy shots blocked / hit | combat.js:559-571 | combat.gd:608-617 | present | |
| Draw (shadows, red ring, rotation, ×1.5, fade) | projectile.js:110-133 | world_view.gd | present | |

### Enemy behaviours
| Item | JS | Godot | Status | Notes |
|---|---|---|---|---|
| behaviorOf / defFor / cast / runner | enemies.js:58-150 | enemy_defs.gd | present | tested (966 species) |
| chase, tank, runner, charger, keep-distance, ranged, fan, beamer, zoner, healer, shielder, summoner, bomber, jumper, thief | enemy.js:281-665 | enemy.gd:305-759 | present | tested |
| Liquids, weather speed, stuck sidestep, knockback, contact | enemy.js:120-390, combat.js:661-671 | enemy.gd, combat.gd:697-712 | present | |
| Separation, spatial grid, laggards, rift stash | enemy.js:773-939 | enemy_mgr.gd | present | tested |
| Remote enemies | enemy.js:204-233,755-803 | — | excluded (online) | |

### Enemy visuals
| Item | JS | Godot | Status | Notes |
|---|---|---|---|---|
| Glow (fury / shiny / gold / boss), shadow, hover bob, jump lift, hit flash | enemy.js:679-694 | world_view.gd | present | |
| Corpse fade: sprite alpha² (globalAlpha × Animator alpha), shadow alpha | enemy.js:676,688-694, sprites.js:249-250 | world_view.gd `_draw_enemy` | different → **fixed** | the sprite faded linearly (one-line additive edit, agreed with the performance agent) |
| Shield bubble, support icons, HP bars, hurt anim, walk/idle, y-sort, corpse cap 120 | enemy.js:135-954 | world_view.gd, enemy.gd, enemy_mgr.gd | present | |

### Bosses / shinies / spawner / hazards / pathing / drops
| Item | JS | Godot | Status | Notes |
|---|---|---|---|---|
| 5 boss slots, scale, AI (slam/dash/leap/rain/beam/volley/nova), fury chain, enrage text | enemies.js, enemy.js:408-540 | enemy_defs.gd, enemy.gd:468-625 | present | tested |
| Boss spawn banner, HUD boss bar, boss music, waves ×0.25, death FX | spawner.js:100-146, hud.js:103-110 | spawner.gd, hud.gd:79-85 | present | |
| Shinies: 1/4096, ×2 HP ×5 XP, banner, twinkles, edge arrow, catch | spawner.js:25-94, enemy.js:84-247 | spawner.gd, enemy.gd, hud.gd:87-101 | present | |
| Spawner constants, rate, ring spawn, elites, golden, horde bag, overtime warning, surges, burst, ahead() | spawner.js:17-174 | spawner.gd | present | tested |
| Telegraph zones / beams (inside, detonate through i-frames, FX, draw) | hazards.js | hazards.gd, world_view.gd | present | tested |
| BFS flow field, walkable, dirFor, clearLine | pathing.js | pathing.gd | present | tested |
| BFS rebuild timing | pathing.js:60-66 | pathing.gd:64-93 | different | spread over ≤3 frames by design (README Phase 2 notes) |
| Drops: XP, ticket 1/400, heal / magnet / bomb, boss loot, golden coin, thief, rift legend | pickup.js:72-94, enemy.js:172-190 | pickups.gd, enemy.gd:213-233 | present | |

### VFX / FX
| Item | JS | Godot | Status | Notes |
|---|---|---|---|---|
| Quality caps, px / burst / spark / sp / twinkle / trail / ring / slash / beam, stepped alpha | fx.js:12-154 | fx.gd | present | |
| Beam / slash / ring / particle draw | fx.js:156-250 | world_view.gd | present | |
| Damage numbers drawn under weather + vignette | fx.js:253-265, game.js:652-656 | main.gd (Overlay layer 1 < Vignette layer 2) | different → **fixed** | they were drawn above the weather tint, fog and vignette |
| 23 VFX shapes × 19 palettes, forMove / forType | vfx.js | vfx.gd, vfx.json | present | tested |

## 3. Sound and music call sites

Every `G.Audio.sfx` / `G.Audio.music` call in `js/` (98 direct calls) against `Sfx.play` / `Sfx.music` in `godot/`, then the generic UI sounds that `ui.js` attaches to every clickable element, then the audio behaviours.

### Direct calls
| Sound / music | Trigger (JS) | Godot | Status | Notes |
|---|---|---|---|---|
| pause | game.js:81 togglePause | sim.gd `toggle_pause` | present | resume silent in both |
| (none) auto-pause | game.js:36,65 tab hidden → silent | main.gd notifications | different → **fixed** | Godot played `pause`; now quiet |
| music forest / null / village | game.js:135,278,805,841,847 | sim.gd:97,123, main.gd `_enter_meta` | present | |
| gameover / back at endRun | game.js:279 | sim.gd:124 | present | |
| shinyGet (rescue, shiny caught) | game.js:254,267 | sim.gd:344,355 | present | |
| levelup / confirm (level-up), levelup / legend (bond) | game.js:332-363 | sim.gd:196,217,309,318 | present | |
| pickup map xp / coin / heal / break / confirm / shiny / legend | game.js:411 | sim.gd:225 | present | |
| biome, music rift > boss > biome | game.js:562,593 | sim.gd:387,423 | present | |
| select (reroll, bond step 1) | run-ui.js:32,206 | sim.gd:207, bond_ui.gd:166 | present | |
| ball / shake / reveal / legend / shiny / hover (slot machine) | slots.js:54-124 | slot_machine.gd:64-139 | present | |
| click (HUD slot tap) | hud.js:258 | hud.gd:213 | present | |
| error / burst / reveal (gacha) | gacha-ui.js:84-113 | gacha_screen.gd:229-258 | present | |
| setVolume / click on slider release / toggleMute | ui.js:93-96 | sound_controls.gd | present | click now only when the value changed (`drag_ended(changed)`) |
| top-bar sound icon (sound / mute) | ui.js:100 | meta_ui.gd top bar | missing → **fixed** | see §4 top bar |
| music(null) + village after deleting the save; quit the run first | settings-ui.js:167-174 | settings_screen.gd | different → **fixed** | |
| confirm (menu Normal/Shiny, changed only) | menu.js:57 | menu_screen.gd:222 | present | |
| select / buy / select / select (upgrades) | menu.js:248-357 | upgrades_screen.gd | present | |
| break (mine, meteor), rift ×2, boss, legend, back (rift) | combat.js:372,380, rift.js | combat.gd, rift.gd | present | |
| heal (revive), shiny/surge (events), shiny (thief), confirm / legend (lost Pokémon) | player.js:392, events.js | player.gd:283, events.gd | present | |
| legend / confirm (achievement / mission popup) | progress.js:213 | popups.gd:73 | present | |
| break / shot beam (telegraphs), grass / chest / break (props) | hazards.js:55-58, world.js:368 | hazards.gd, world_map.gd:776 | present | |
| shiny / boss / boss / surge (spawner), biome (weather) | spawner.js:92-149, weather.js:76 | spawner.gd, weather.gd:75 | present | |
| select / xp / legend / boss-surge (interactables) | interact.js:42-98 | interact.gd | present | |
| select (setActive), shot per kind × type, hurt | player.js:147,212,240 | player.gd, audio_logic.gd | present | |
| buy / confirm ×2 (missions, title, favourite) | goals-ui.js:74,223 | goals_screen.gd | present | |
| legend (evolution card), hit, faint / bossDown, boss (enrage), heal (healer) | levelup.js:67, enemy.js | levelup.gd:37, enemy.gd | present | |
| co-op / social / login / account calls | game.js:78-201, coop.js, social-ui.js, menu.js:29, settings-ui.js:185-195 | — | excluded (online) | |

### Generic UI sounds (ui.js:64-80: hover on pointer-over, click / `data-back` → back / `data-sfx`)
| Element | JS | Godot | Status | Notes |
|---|---|---|---|---|
| Hover on every `.btn, .menu-item, .tab, .chip, .card, .cell:not(.locked), .answer, .gen-tab` | ui.js:70 | ui_kit.gd `button()` | missing → **fixed** | UIKit buttons play `hover` on mouse-over (not when disabled, not on keyboard / gamepad focus); seg buttons, favourite slots and locked cells opt out like JS |
| Hover on level-up / item / bond cards | ui.js:70 | screens.gd, item_choice.gd, bond_ui.gd | missing → **fixed** | |
| Main menu items (play → confirm, others click, hover) | menu.js:11 | menu_screen.gd | present | |
| Top-bar gear / Volver (`data-back`) | ui.js:79 | meta_ui.gd | present | |
| Esc in a sub-screen is silent | game.js:476 | meta_ui.gd `back()` | different → **fixed** | Godot played `back` |
| Dex gen tabs, filter chips, owned cells, "Elegir de compañero" | menu.js | dex_screen.gd | present | |
| Dex detail Normal/Shiny seg (plain `.seg button`: silent) | menu.js:195-197 | dex_screen.gd | different → **fixed** | played click |
| Upgrades ban chips: click, then select | menu.js:357 | upgrades_screen.gd | missing → **fixed** | |
| Gacha "Continuar" (#pull-close): click | dev.html:487 | gacha_screen.gd | different → **fixed** | played confirm |
| Favourite slots (silent), favourite "Volver" (click), favourite cells (click + confirm) | goals-ui.js:161-223 | goals_screen.gd | different → **fixed** | |
| Test "¡Vamos juntos!" / "Elegir" / starter "Volver" (click), starter cells (click) | dev.html:142-157, test.js:66 | test_screen.gd | different → **fixed** | confirm / back / silent before |
| Settings "Cerrar" (click) | dev.html:228 | settings_screen.gd | different → **fixed** | played back |
| Item choice card: click (not confirm) | run-ui.js:153 | sim.gd `choose_item` | different → **fixed** | |
| Bond "Atrás": click | dev.html:507 | bond_ui.gd | missing → **fixed** | |
| Pause Continuar / Ajustes / Abandonar run: click | dev.html:527-530 | screens.gd | missing → **fixed** | |
| Level-up cards / reroll (`data-sfx="none"`) | run-ui.js:56, dev.html:496 | screens.gd | present | |
| Results "Volver al menú", goals tabs / buttons, settings tabs / switches / chips | various | various | present | |

### Audio behaviours
| Behaviour | JS | Godot | Status | Notes |
|---|---|---|---|---|
| Mute toggle, smoothing τ 0.05, sfx dropped when muted | audio.js:79 | settings.gd, audio.gd:141-157 | present | tested |
| Mute / volume access: top-bar sound button + panel, pause inline controls, Settings › Sonido | ui.js:84-100,177, run-ui.js:224 | meta_ui.gd, screens.gd, settings_screen.gd → `SoundControls` | missing → **fixed** | |
| Volumes 0.55 / 0.7, buses ×0.7 / ×2.4 | audio.js | settings.gd, audio.gd | present | tested |
| Master compressor | audio.js | audio.gd:114-130 | present | approximation (README *Audio*) |
| SFX reverb tails follow the music volume | audio.js | baked at the default balance | different | won't fix (pre-rendered audio) |
| MIN_GAP, 25-voice cap, xp combo, shot keys | audio.js:402-449 | audio_logic.gd | present | tested |
| First-gesture unlock / tap-to-start | game.js:819-833 | — | n/a | native build has no autoplay lock |
| Background: music keeps playing in a hidden tab | audio.js | audio.gd:317-322 mutes Master while the app is paused | different | intended on phones (README *Audio*) |
| No ducking on pause / modals; music selection; crossfade 0.7 / 0.8 / 0.1 s; loops | audio.js, game.js | audio.gd, main.gd, sim.gd | present | tested |

## 4. In-run HUD and on-screen feedback

JS: `ui/hud.js`, `ui/icons.js`, `entities/fx.js`, in-run parts of `ui/ui.js`, every `say()` / `FX.*` / toast call site.

### Player panel, buff chips, timer
| Item | JS | Godot | Status | Notes |
|---|---|---|---|---|
| XP bar (bg .5, #4fd1ff→#a98bff, 7 px) | hud.js:35-41 | hud.gd:33-39 | present | |
| Name, "Nv. N", HP bar 168×11 + "hp / max" | hud.js:44-58 | hud.gd:42-47 | present | Godot adds the safe-area inset to px (notch) |
| `bar()` fill at low fractions: rect `w·frac` clipped to the pill (true sliver, square end) | hud.js:17-26 | draw_util.gd `bar` | different → **fixed** | Godot widened the fill to `h` px under `h/w` (HP < 6.5 % looked like 6.5 %) |
| Buff chips ATK/VEL/DEF/REG ×n (order, colours, box) | hud.js:61-75 | hud.gd:50-61 | present | |
| Altar power chip "NAME Ns" | hud.js:136-146 | event_hud.gd:16-24 | present | |
| In-world buff arcs, altar ring, type halo | player.js:434-471 | world_view.gd | present | |
| Timer mm:ss, sub-line "BIOMA · N DERROTADOS · N MONEDAS" | hud.js:79-85 | hud.gd:65-67 | present | |
| Weather chip "NAME · Ns" | hud.js:88-100 | hud.gd:70-77 | present | |
| Rift "GRIETA · m:ss" (y 98 with a boss), event countdown | hud.js:198-203, events.js:309-321 | event_hud.gd:64-83 | present | |

### Banners
| Item | JS | Godot | Status | Notes |
|---|---|---|---|---|
| `say(text, secs)` one slot, timer, reset | spawner.js:29,111,176-181 | spawner.gd | present | |
| Draw (alpha min(1, t·1.6), 800 22 #ffcb3d, stroke, h·0.3) | hud.js:227-238 | hud.gd:106-110 | present | JS leaks `textAlign='left'` from the weather / power chip (banner starts at the centre): JS bug, Godot centres |
| events.js `say` ignores its colour | events.js:85-91 | events.gd:148-158 | present | |
| "¡SE HA ABIERTO UNA GRIETA!" popup (scale, alpha, box) | hud.js:209-225 | event_hud.gd:86-97 | present | |

### Move slots, item slot, boss bar
| Item | JS | Godot | Status | Notes |
|---|---|---|---|---|
| Layout S 54 / GAP 9, active raised 6, tap to select | hud.js:241-258 | hud.gd:6-126 | present | |
| Background, border colour priority | hud.js:262-267 | hud.gd:128-134 | present | |
| Border widths 2.5 / 2 / 1.2 stroked on the edge | hud.js:265 | draw_util.gd:117 | different | int StyleBox borders (3 / 2 / 1 px); cosmetic, left |
| Cooldown overlay: rect from the top, height S·f, clipped to the slot (flat bottom edge) | hud.js:287-294 | hud.gd | different → **fixed** | was an inset rounded pill |
| Emblem, level pips, key number, active name, fused 2×2 grid, cast flash | hud.js:272-321 | hud.gd:137-168 | present | |
| Stored bond icon ×n, item slot box + icon + name | hud.js:325-351 | hud.gd:171-186 | present | |
| Boss bar (≤420, y 70, uppercase name) | hud.js:103-110 | hud.gd:79-85 | present | |
| World HP bars, auras, shield bubble, status tint, support icons, hit flash | enemy.js:678-728 | world_view.gd | present | |

### Edge arrows and indicators
| Item | JS | Godot | Status | Notes |
|---|---|---|---|---|
| Shiny arrow (pulse, clamp, triangle, icon) | hud.js:114-133 | hud.gd:88-101 | present | |
| Arrow projection ignores the camera shake (`(x − cam.left())·scale`) | hud.js:116,154, events.js:333 | sim_camera.gd `world_to_screen_steady` | different → **fixed** | HUD arrows jittered with the shake |
| Rift arrow off / on screen + "GRIETA · N m · N s" | hud.js:154-195 | event_hud.gd:44-63 | present | |
| Lost Pokémon / "Marca" / thief edge arrows | events.js:298-347 | event_hud.gd:70-118 | present | |
| Lost Pokémon, goal mark, rift portal in the world | events.js:261-294, rift.js:233-251 | event_draw.gd | present | |
| Pickup icons (berry, magnet, bomb, ticket, ticket10) | pickup.js:180-193 | world_view.gd | present | |
| Held-item pickup: item icon + gold pulse | pickup.js:183-192 | world_view.gd | different → **fixed** | see §1 Pickups |

### Touch HUD, FPS, damage numbers, screen effects
| Item | JS | Godot | Status | Notes |
|---|---|---|---|---|
| Touch buttons, pause button 40×40, joystick, control hint (14 s) | hud.js:355-373, touch.js | hud.gd:188-202, touch.gd | present | |
| FPS: `round(frames / t)` over 0.5 s windows | game.js:524-525 | hud.gd | different → **fixed** | was `Engine.get_frames_per_second()` (1 s) |
| FPS text / colours ≥50 / ≥30 | game.js:671-678 | hud.gd | present | |
| Damage numbers: setting, caps 25/45/70, life, motion, draw | fx.js:76-141,253-265 | fx.gd, overlay.gd | present | |
| Damage numbers drawn under weather + vignette | game.js:654-668 | main.gd layers | different → **fixed** | see §2 |
| Every floating text (Banda Focus, heal, Cinta Elección, coins, tickets, spring, Pegajoso, sand/snow, Vínculo) | player.js, game.js, interact.js, weather.js, rift.js | player.gd, sim.gd, interact.gd, weather.gd, rift.gd | present | |
| Shake model, every kick call site (16) | camera.js, combat/enemy/player/spawner/rift/interact/hazards/world/game | sim_camera.gd + call sites | present | |
| Full-screen flash (rift in / out), calm ×0.3 | game.js:157-158,678-685 | sim.gd, event_hud.gd:121-125 | present | |
| Flash also covers the joystick (drawn last) | game.js:668-685 | touch.gd `_draw` | different → **fixed** | was drawn in the HUD layer, under the joystick |
| Vignette, fog, weather tint, hurt flash / blink, prop hit flash | world.js:576-582, game.js:659-667 | main.gd, world_view.gd | present | |

### Achievement / mission popups in a run
| Item | JS | Godot | Status | Notes |
|---|---|---|---|---|
| Queue, texts "Misión completada: …" / "¡Logro: …!" / "Nuevo título: …" | progress.js:76,179,199-219 | progress.gd, popups.gd | present | |
| Icon (sprite / medal), position (top 64; compact bottom 8), 2.8 s + 0.25 s, sfx | progress.js:208-219, style.css:648-651 | popups.gd | present | |
| Title always gold (`.ach-pop b { color: gold }`) | style.css:653 | popups.gd | different → **fixed** | mission titles were white |
| Appear: `pop .2s` (scale .94 → 1 + opacity), hide instantly | style.css:86,650 | popups.gd | different → **fixed** | was an alpha fade in and out |

### Banner / toast call sites (one row per message)
| Message | JS | Godot | Status |
|---|---|---|---|
| "¡Un X shiny anda cerca!", "¡X salvaje apareció!", overtime warning, "¡Marea de Pokémon!" | spawner.js:91-148 | spawner.gd | present |
| Rift: "Has entrado en la grieta…", "¡X te esperaba en la grieta!", "¡Has vencido a X!…", "La grieta os ha expulsado…" | rift.js:134-208 | rift.gd | present |
| Weather "<Tiempo>: <pista>", spring dry, altar "¡Poder X!…" | weather.js:75, interact.js:70-80 | weather.gd, interact.gd | present |
| "¡X se ha enfurecido!", "¡X se ha escapado!" | enemy.js:457,920 | enemy.gd, enemy_mgr.gd | present |
| Events: horde, golden hour, lost Pokémon (×6 texts), thieves (×2) | events.js:85-227 | events.gd | present |
| Rescue / shiny caught (×4), bond (×2), item (×2), biome | game.js:253-563 | sim.gd | present |
| Toast "El juego ha fallado…" | game.js:514 | — | missing (won't fix: no equivalent failure mode) |
| Co-op / updater banners and toasts | game.js:212-240, coop.js, updater.js | — | excluded (online) |

### Icons
| Item | JS | Godot | Status | Notes |
|---|---|---|---|---|
| UI icon set (56), type emblems, kind badges, size snapping, twinkle | icons.js | icons.gd, icons.json | present | |

## 5. Meta screens (out of a run)

JS: `ui/menu.js`, `ui/goals-ui.js`, `ui/gacha-ui.js`, `ui/slots.js`, `ui/test.js`, `ui/settings-ui.js`, `ui/ui.js`, the guest / app path of `ui/login.js`, dev.html sections and `css/style.css`. Reference for the offline build: the web's app mode (`window.PS_APP`, `.ps-app`).

### Boot / tap-to-start
| Item | JS | Godot | Status | Notes |
|---|---|---|---|---|
| Boot overlay `#boot` (bg #050914, "PokéSurvivor", "Juego de supervivencia…", "Cargando…") | dev.html:282-312 | project.godot boot splash | different → **partly fixed** | splash background is now #050914 with the game icon instead of the engine's default; no text (an engine splash can't show translated text) |
| Tap-to-start "Pulsa para empezar" | dev.html:315-321, game.js:819-834 | — | n/a | only shown when a browser blocks audio |
| Village music from boot; offline flow test / menu | game.js:805-844 | main.gd | present | |
| Login screen | login.js | — | excluded (online) | the app mode skips it |
| "Gira el móvil" overlay | dev.html:87 | project.godot orientation | present | landscape forced |

### Top bar, sound panel, credits line
| Item | JS | Godot | Status | Notes |
|---|---|---|---|---|
| Shown on menu + sub-screens; coins pill; tickets pill | ui.js:23-34 | meta_ui.gd | present | |
| Tickets pill tooltip "Tickets del gacha" | dev.html:198 | meta_ui.gd | missing → **fixed** | |
| User pill: `user` icon + "Entrenador" | ui.js:41 | meta_ui.gd | present | |
| User pill sync dot ("Guardado sólo en este navegador") | ui.js:38-43 | — | missing (won't fix) | web storage state, meaningless offline |
| User pill click → Misiones › Perfil | game.js:804 | meta_ui.gd | missing → **fixed** | |
| Sound button (`sound` / `mute` icon, "Sonido") + sound panel (Música, Efectos, Silenciar todo / Activar sonido; hidden with the chrome) | dev.html:202,207, ui.js:84-101,177-181, css:500-503 | meta_ui.gd + sound_controls.gd | missing → **fixed** | |
| Settings gear | dev.html:204 | meta_ui.gd | present | |
| Credits line "Proyecto de fan sin ánimo de lucro · Sprites: SpriteCollab (CC BY-NC 4.0) · Pokémon © Nintendo/Creatures/GAME FREAK" (bottom-left, 12 px, hidden on compact) | dev.html:208, css:321-324,735 | meta_ui.gd | missing → **fixed** | its "Aviso legal" link opens Ajustes › Acerca de › Aviso legal |
| News / support / fullscreen / logout buttons | dev.html:200-205 | — | excluded (online) | hidden in app mode too (except news) |
| Pull overlay covers the top bar (z 40 > 25) | css:307,355 | meta_ui.gd, gacha_screen.gd | different → **fixed** | the gear could open Ajustes mid-pull |

### Toasts, dialogs, global UI behaviour
| Item | JS | Godot | Status | Notes |
|---|---|---|---|---|
| Exclusive screens, sub-screens over the menu, radial dim | ui.js:14-17, css:84 | meta_ui.gd, dim_bg.gd | present | |
| Toast bottom 30, 2.2 s, replaced | ui.js:47-53 | popups.gd | present | |
| Toast pop-in (scale .94 → 1, .2 s) | css:448 | popups.gd | missing → **fixed** | |
| Achievement popup queue | progress.js:199-220 | popups.gd | present | see §4 |
| Hover sound on every clickable | ui.js:64-72 | ui_kit.gd | missing → **fixed** | see §3 |
| Click on a disabled element plays `error` | ui.js:76 | — | present (equivalent) | browsers dispatch no click on a disabled `<button>`, so it never sounds in JS either |
| `[data-back]` → back; Esc → menu; Esc closes Ajustes first | ui.js:79, game.js:456-479 | meta_ui.gd | present | |
| Delete-save confirm + "Partida borrada" | settings-ui.js:167-172 | settings_screen.gd | present | inline dialog instead of `confirm()` |
| Animated Pokémon boxes, menu backdrop | ui.js:203-276, game.js:694-750 | poke_view.gd, backdrop.gd | present | |
| Android back quit dialog | mobile/shell.js | input_router.gd | present | shell.js minimises the app; Godot asks to quit |

### Main menu
| Item | JS | Godot | Status | Notes |
|---|---|---|---|---|
| Layout, logo, "Mundo Misterioso" | dev.html:164-194 | menu_screen.gd | present | |
| Jugar / Pokémon (count) / Mejoras / Gacha / Misiones (pending badge) | dev.html:180-184, menu.js:62-78 | menu_screen.gd | present | |
| Ajustes subtitle "Sonido, gráficos, controles y cuenta" | dev.html:187 | menu_screen.gd | different → **fixed** | was "…y partida" |
| Amigos / Ranking | dev.html:185-186 | — | excluded (online) | hidden in app mode |
| Hover cursor + sfx, focus ring | css:161-167 | menu_screen.gd | present | |
| Stats box values in white bold | menu.js:67-69 | menu_screen.gd | different → **fixed** | was all muted |
| Compact 2-column list, stats hidden | css:750-756 | menu_screen.gd | present | |
| Tiny screens (max-height 400): only Play keeps its subtitle | css:761-766 | menu_screen.gd | missing → **fixed** | |
| Guest-mode line, room / social lines | menu.js:70-102 | — | excluded (online) | |

### Partner card and shiny toggle
| Item | JS | Godot | Status | Notes |
|---|---|---|---|---|
| Stage 260×200 ×4, border type / #9ae6ff, gradient, twinkles | menu.js:42-44 | menu_screen.gd, poke_view.gd | present | |
| `.stage.shiny` glow `0 0 22px rgba(154,230,255,.55)` | css:229 | poke_view.gd | missing → **fixed** | also on the dex detail |
| Name + shiny icon, type chips + rarity | menu.js:45-46 | menu_screen.gd | present | |
| Toggle shown only with the shiny owned; Normal / Shiny; confirm on change | menu.js:49-58 | menu_screen.gd | present | |
| Toggle look: joined segmented control, active cyan (rgba(154,230,255,.22), #c9f3ff) | css:487-492 | menu_screen.gd, dex_screen.gd | different → **fixed** | was gold chips |

### Collection
| Item | JS | Godot | Status | Notes |
|---|---|---|---|---|
| Title + count, Volver, 9 gen tabs (have/total), partner's gen first | menu.js:109-125 | dex_screen.gd | present | |
| Selected tab gold (border, rgba(255,210,63,.14), gold name) | css:483-484 | ui_kit.gd `TabOn` | different → **fixed** | was white; same `.gen-tab` style in Gacha and Ajustes |
| Filters (Todos / Tengo / Me faltan / Shiny / rarities) + logic | menu.js:127-153 | dex_screen.gd | present | |
| Cells (number, crown / shiny badge, sprite or silhouette, name / ???, rarity) | menu.js:157-168 | dex_screen.gd | present | |
| Badge tooltips "Compañero" / "Tienes su shiny" | menu.js:158-159 | dex_screen.gd | missing → **fixed** | |
| Empty filter text | menu.js:171 | dex_screen.gd | present | |
| Detail: stage, toggle, number · region, name, rarity, types | menu.js:183-202 | dex_screen.gd | present | |
| Stat bars gold | css:258 | dex_screen.gd | different → **fixed** | were green |
| "Empieza con …", learnable moves + row tooltip "Movimientos que puede aprender" | menu.js:208-210 | dex_screen.gd | different → **fixed** | tooltip was missing |
| Partner button / pick + toast, unowned text | menu.js:211-230 | dex_screen.gd | present | |

### Upgrades, ban picker, hotkeys
| Item | JS | Godot | Status | Notes |
|---|---|---|---|---|
| Title, stage, subtitle, Pokémon select (order, text), select sfx | menu.js:240-258 | upgrades_screen.gd | present | |
| Changing the Pokémon keeps the ban picker open | menu.js:248 | upgrades_screen.gd | different → **fixed** | Godot closed it |
| 13 upgrades, cost formula, cards, buy button, buy flow + toast | upgrades.js, menu.js:267-291 | upgrades.json, upgrades_screen.gd | present | tested |
| Veto "Elegir (n/lvl)" toggles the picker | menu.js:274-277 | upgrades_screen.gd | present | |
| Picker placed right after the Veto card (full row) | menu.js:293, css:797 | upgrades_screen.gd | present | Veto is the last card, so "after the card" = after the grid |
| Picker text, chips (icon + name), start move excluded, limit toast, select sfx | menu.js:342-358 | upgrades_screen.gd | present | |
| Banned chip look: red (rgba(255,95,109,.25), #ff5f6d border, #ffd3d8 text, strike-through) + `ban` icon | css:806, menu.js:349 | upgrades_screen.gd | different → **fixed** | was a gold chip; strike-through drawn on the label |
| Hotkeys panel (4 slots, Libre + moves, one slot per move) | menu.js:305-326 | upgrades_screen.gd | present | |
| Move names sorted with `localeCompare('es')` | menu.js:306,343 | upgrades_screen.gd | different → **fixed** | accents sorted after "z" |

### Gacha, slot machine, reveal
| Item | JS | Godot | Status | Notes |
|---|---|---|---|---|
| Title, 9 banner tabs (kept), banner art, title, description, featured 3 | gacha-ui.js:15-53 | gacha_screen.gd | present | |
| Owned line "Tienes X de Y · [shiny] N shiny" | gacha-ui.js:46-47 | gacha_screen.gd | different → **fixed** | icon missing |
| Pull buttons "Tirar ×1 · [ticket] 1" … (icon before the number) | gacha-ui.js:69-71 | gacha_screen.gd | different → **fixed** | |
| Tickets line with icons and bold numbers | gacha-ui.js:72 | gacha_screen.gd | different → **fixed** | |
| Pity line, rates, shiny 1 %, four notes | gacha-ui.js:55-66 | gacha_screen.gd | present | |
| Pull flow, no-ticket toast, pull logic | gacha-ui.js:81-87, gacha.js | gacha_screen.gd, gacha.gd | present | tested |
| Esc while the pull overlay is open (also after the reveal) is ignored | game.js:478-479 | meta_ui.gd | different → **fixed** | Esc after the reveal left the stale overlay visible on the next visit |
| Overlay radial background #1b2d63 → #03060f | css:354-362 | gacha_screen.gd | different → **fixed** | was flat |
| Slot machine: canvas, click to speed up, LED texts, lever, suspense, reels, win, sparks, tray, bulbs, sign, tick sfx | slots.js | slot_machine.gd | present | |
| Tooltip "Clic para acelerar" | dev.html:486 | gacha_screen.gd | missing → **fixed** | |
| Slot machine red drop-shadow glow + pop .25 s | css:597-598 | gacha_screen.gd | missing → **fixed** | |
| Burst sfx, cards 150 ms apart, card content, NEW / repeated tags | gacha-ui.js:97-111 | gacha_screen.gd | present | |
| Card glow `0 0 22px rarity` on every card; legend pulse 1.4 s, shiny 1.1 s (ease-in-out, alternate); pop .3 s | css:404-417,493 | gacha_screen.gd | different → **fixed** | glow was only from 4★, one 0.7 s pulse, 0.22 s pop |
| "Continuar" | gacha-ui.js:120-123 | gacha_screen.gd | present | |

### Missions, achievements, titles, profile
| Item | JS | Godot | Status | Notes |
|---|---|---|---|---|
| Tabs Misiones / Logros / Perfil; ensure + checkAch | goals-ui.js:24-30 | goals_screen.gd | present | |
| Daily / weekly lists, reset countdown, rows, states, claim / reroll, menu badge | goals-ui.js:43-85, progress.js:82-125 | goals_screen.gd, progress.gd | present | tested; both share the JS weekly countdown rounding |
| Achievements summary, 6 category chips, cards, legendaries grid | goals-ui.js:94-145 | goals_screen.gd | present | |
| Titles: select, note, "Título: X" | goals-ui.js:143,171-179 | goals_screen.gd | present | |
| Profile tab subtitle (app mode: "Tu perfil se publica cuando juegas con una cuenta online.") | goals-ui.js:153-154 | goals_screen.gd | different → **fixed** | Godot had its own sentence |
| 3 favourites + picker (search, owned, shiny variants) | goals-ui.js:155-218 | goals_screen.gd | present | |
| Shiny icon before a favourite's name | goals-ui.js:164 | goals_screen.gd | missing → **fixed** | |
| "Ver mi perfil público" + profile view (name + title badge, favourites, marks: best time, group, level, bosses, legends, kills; top-8 medals; Cerrar / click outside / Esc) | goals-ui.js:181-291, social.js:441-453, dev.html:410-415 | goals_screen.gd `show_profile` | missing → **fixed** | built from the local save like the web's app mode (`profileData()`) |
| publishProfile, other players' profiles | goals-ui.js:222,239-247 | — | excluded (online) | |

### Personality test, result, starters
| Item | JS | Godot | Status | Notes |
|---|---|---|---|---|
| Test (progress bar, "Pregunta N de M", question, 4 answers + select sfx), scoring | test.js:13-47 | test_screen.gd, meta.gd | present | tested |
| Answer hover: PMD cursor arrow (+ 34 px left padding) | css:204-215 | test_screen.gd, ui_kit.gd | missing → **fixed** | also on keyboard / gamepad focus |
| Result screen (trait, text, stage, partner, buttons) | dev.html:135-147, test.js:45-54 | test_screen.gd | present | |
| Starter grid (29, texts, pre-selection, info line, Elegir) | test.js:57-81 | test_screen.gd | present | |
| Starter "Volver" re-shows the same result | test.js:9 | test_screen.gd | different → **fixed** | Godot re-ran the random tie-break (the offered partner could change) |
| choose(): partner, personality, grant, toast, menu | test.js:83-92 | test_screen.gd | present | |

### Settings
| Item | JS | Godot | Status | Notes |
|---|---|---|---|---|
| Overlay over menu or pause, returns there; last tab kept; pause opens Sonido; Esc closes | settings-ui.js:18-32 | settings_screen.gd | present | |
| Tabs Sonido / Gráficos / Controles / **Cuenta** / Acerca de | dev.html:231-235 | settings_screen.gd | different → **fixed** | 4th tab was "Partida" |
| Section headings gold 17 px (`.set-h`) | css:694 | settings_screen.gd | different → **fixed** | were white 19 px |
| Sound: Música / Efectos sliders, mute button, persisted | ui.js:84-96 | sound_controls.gd | present | Godot showed the numeric value (removed, like JS) |
| Graphics: Idioma (applies live: "Se aplica al momento." vs web reload), Calidad (+ "ahora: …"), 3 toggles | settings-ui.js:76-85 | settings_screen.gd | present | |
| Pantalla completa | settings-ui.js:86-88 | — | excluded | browser fullscreen |
| Controls: touch text, "Tamaño del joystick" + "Cuánto hay que arrastrar el dedo.", chips, PC keys | settings-ui.js:90-101 | settings_screen.gd | different → **fixed** | description was missing; Godot adds R and gamepad rows |
| Account (app mode): "Partida", "Tu partida se guarda en este dispositivo.", "Borrar partida" + confirm + toast | settings-ui.js:129-172 | settings_screen.gd | present | + import / export of web saves (Godot-only) |
| After deleting: quit the run, music off, back to the test | settings-ui.js:169-174 | settings_screen.gd | different → **fixed** | see §1 |
| Guest / account rows | settings-ui.js:134-153 | — | excluded (online) | |
| About: logo, "Versión 1.2 · 2026-10-09" | settings-ui.js:9,105 | settings_screen.gd | different → **fixed** | version line added (+ the native-build line) |
| About: disclaimer, Créditos (4 lines) | settings-ui.js:106-113 | settings_screen.gd | present | |
| About: "Aviso legal y privacidad" (offline parts of #scr-legal: fan project + non-affiliation, crypto, third-party content, contact / removal, source code, privacy), "Contacto", "Código (GitHub)" | settings-ui.js:117-119, dev.html:242-280 | settings_screen.gd | missing → **fixed** | + "Créditos completos" (SpriteCollab artists of CREDITS.md, PokeAPI, OFL fonts with their full licence texts, trademark) |
| "Guía y preguntas" / "Pokédex" web pages | settings-ui.js:115-116 | — | excluded (online) | |

## 6. World, props, weather, events, rifts, bonds, menu backdrop

JS: `world/world.js`, `world/tiles.js`, `systems/weather.js`, `systems/events.js`, `systems/rift.js`, `systems/interact.js`, bond parts of `entities/player.js`, backdrop parts of `game.js`. "tested" = `tests/phase3_tests.gd` / `phase3b_tests.gd`. All 29 player-facing strings of this area exist in Godot with the JS wording.

### Terrain, biomes, liquids
| Item | JS | Godot | Status | Notes |
|---|---|---|---|---|
| terrainRaw, noise / fbm, chunk cache | world.js:52-108 | world_map.gd:146-306 | present | tested (bit-exact) |
| Ground painter, wall autotile, contact shadow, 21 palettes | tiles.js | world_paint.gd, world.json | present | tested (30 chunks byte-exact) |
| Chunk images: 48 cached, drawn at CW+1 | world.js:415-453 | ground_layer.gd | present | LRU instead of FIFO (async painting) |
| Ground before a chunk is painted | world.js:446 (sync) | ground_layer.gd | different | per-tile placeholder until the worker finishes (intended, README Phase 3a) |
| Biome crossfade 2.6 s, every 240 s, wrap, banner / sfx / ring, none in the arena, HUD name, music | world.js, game.js:558-593 | world_map.gd, ground_layer.gd, sim.gd | present | tested |
| Vignette, collide / isFree / projectileBlock / walkable / propsInCircle | world.js:224-336,576-582 | main.gd, world_map.gd | present | tested |
| Liquids (table, immunities, painting, shimmer, player / enemy effects, splash, pathing) | world.js:203-215,456-477, player.js:334-356, enemy.js:266-276 | world_map.gd, world_paint.gd, liquid_layer.gd, player.gd, enemy.gd | present | tested |

### Props and destructibles
| Item | JS | Godot | Status | Notes |
|---|---|---|---|---|
| Placement, PROP table, makeProp | world.js:118-187 | world_map.gd:308-451, world_prop.gd | present | tested (3,565 props) |
| Painters (tree, crystal, dead tree, rock + cracked, grass + sway, chest, altar, spring, bigchest, traps, rift) | tiles.js:386-618 | prop_art.gd | present | tested (424 sprites byte-exact) |
| Shadow, draw offset, crossfade, hit flash + spark, flash timers | world.js:490-546 | prop_art.gd, world_map.gd | present | |
| Y-sort: flat props at y−4000 together with the goal mark | game.js:630,636 | world_view.gd | different | flats are drawn first (goal mark always above springs / traps); left: inside the world_view draw loop the performance agent owns |
| Loot: grass / rock / chest / bigchest; broken props stay broken | world.js:359-409 | world_map.gd:757-823 | present | tested |
| Hits from every attack kind, shots vs grass / solids, enemy shots, auto-aim at breakables | combat.js, player.js:372 | combat.gd, player.gd | present | tested |

### Weather
| Item | JS | Godot | Status | Notes |
|---|---|---|---|---|
| KINDS, biome weights, schedule (120 s, 60 s, 18 %), level / mult / speedFor / hurts | weather.js:18-106 | weather.gd, world.json | present | tested (60-min replay) |
| Start banner + sfx, sand / snow chip, force / clear | weather.js:72-127,176-178 | weather.gd | present | tested |
| HUD chip, tint, particles, frozen unless playing, fog vignette | weather.js:140-169, hud.js:87-100, game.js:660-667 | hud.gd, weather_layer.gd, main.gd | present | |

### Interactables (altars, springs, locked chests, traps)
| Item | JS | Godot | Status | Notes |
|---|---|---|---|---|
| Altars: placement, 8 sprites, halo, trigger, 4 powers 25 s, FX / sfx / banner, player ring, HUD chip | interact.js:18-81, world.js:147-150,505-513 | interact.gd, prop_art.gd, player.gd, event_hud.gd | present | tested |
| Springs: sprite + dry, twinkles, 14 %/s heal, drain / refill, motes, "+N", dry banner | interact.js:55-70 | interact.gd, prop_art.gd | present | tested |
| Locked chests: 3.5 s stand, decay, progress ring, loot + chest event | interact.js:40-46, world.js:396-409,514-521 | interact.gd, prop_art.gd, world_map.gd | present | tested |
| Traps: 3 kinds, triggers, FX, effects on enemies / player ("¡Pegajoso!") | interact.js:47-116 | interact.gd | present | tested |

### Events (horde, golden hour, lost Pokémon, thieves)
| Item | JS | Godot | Status | Notes |
|---|---|---|---|---|
| Schedule 240-300 s, no repeat, boss → 10 s, not in arena | events.js:22-59 | events.gd | present | tested |
| Horde: types, 4 defs, bag, 30 s, burst 6, banner, HUD countdown | events.js:64-88,311-321 | events.gd, spawner.gd, event_hud.gd | present | tested |
| Golden hour: golden enemies, XP ×2, coin, aura, banner, HUD | events.js:72-88, enemy.js:93-97 | events.gd, enemy.gd | present | tested |
| Lost Pokémon: pool, spots, follow, damage, timeout, rescue + join, drawing, goal mark, edge arrows | events.js:130-307 | events.gd, event_draw.gd, event_hud.gd, sim.gd | present | tested |
| Thieves: schedule, Meowth / Gholdengo, flee AI, escape, loot, aura, arrow | events.js:45-123, enemy.js:179-293,917-923 | events.gd, enemy.gd, enemy_mgr.gd | present | tested |

### Rifts, arenas, legendaries, bonds
| Item | JS | Godot | Status | Notes |
|---|---|---|---|---|
| Rift chance escalation, open, portal sprite / glow / fade | rift.js:24-74,234-249 | rift.gd, event_draw.gd | present | tested |
| Portal motes: spawned per rendered frame (also while paused at 0.25×) | rift.js:250 | rift.gd:68-70 | different | spawned in the sim at `dt·18` (frame-rate independent, README Phase 3b notes) |
| HUD arrows, popup, enter, legend pick, begin, arena terrain, legendary, keepInside, arena HUD, win / lose / finish | rift.js:38-229, hud.js:153-225 | rift.gd, world_map.gd, event_hud.gd | present | tested (18 themes) |
| Bonds: options / fuse, offers, picker, fused HUD slot, group casts, stored icon | player.js:100-190, game.js:349-366, run-ui.js:167-221, hud.js:250-334 | player.gd, sim.gd, bond_ui.gd, hud.gd, combat.gd | present | tested; picker fixes in §1 |

### Menu backdrop
| Item | JS | Godot | Status | Notes |
|---|---|---|---|---|
| Seed 4242, CAST of 20, spawn / respawn rules, wander AI, drift, biome every 30 s, draw, village music | game.js:694-768 | backdrop.gd, ground_layer.gd, main.gd | present | |
| Wanderer while its sprite loads: shadow + grey ball (#6b7a94) | sprites.js:238-242 | backdrop.gd | different → **fixed** | Godot skipped it until Idle was loaded |
| Back to the menu after a run: world 4242 around the last camera position (camera not reset) | game.js:771-776 | backdrop.gd | different → **fixed** | Godot reset the camera to (0, 0) every time; now only on the first open, like JS |

## 7. Core systems, data and progression

JS: `core/settings.js`, `core/i18n.js`, `core/sprites.js`, local parts of `core/db.js`, `systems/progress.js`, `systems/gacha.js`, `data/*.js`, `main.js`, `core/util.js`, `core/updater.js`. "tested" = `tests/phase4_tests.gd`, `i18n_tests.gd`, `audio_tests.gd`. An in-memory re-run of `tools/export_godot.js` gives byte-identical data JSONs (only the random / timestamped test vectors differ).

### Settings
| Item | JS | Godot | Status | Notes |
|---|---|---|---|---|
| Storage per device, never written by debug runs | settings.js:15-18 | settings.gd | present | |
| `quality` auto/high/mid/low → fx 0..2, auto sampler (<45 FPS 3 s / >57 FPS 8 s, touch cap), current level shown | settings.js:16-47, game.js:524 | settings.gd:81-115, main.gd | present | |
| fx caps (particles, density, sprites, trails, texts) | fx.js | fx.gd | present | |
| `dmgNumbers`, `calm` (kick ×0.25, flash ×0.3), `fps`, `stick` | settings.js, fx.js:80, camera.js:38, game.js:525-681, touch.js:15 | fx.gd, sim_camera.gd, event_hud.gd, hud.gd, touch.gd | present | FPS window fixed in §4 |
| Audio volumes / mute | audio.js:13-19 | settings.gd | present | tested |
| "Pantalla completa" (Gráficos) where the platform allows it | settings-ui.js:35-53,86-88 | settings_screen.gd | missing → **fixed** | desktop builds only (`DisplayServer` window mode); hidden on phones like the app |

### Language
| Item | JS | Godot | Status | Notes |
|---|---|---|---|---|
| es / en / zh, default from the system language, persisted only when picked | i18n.js:25-30,170-173 | i18n.gd, settings.gd | present | |
| Changing language reloads the page | i18n.js:172 | settings.gd → i18n.gd | different | applied live (intended) |
| Lookup levels, zh → en fallback, `T` / `f`, translation hooks, zh font | i18n.js:44-168 | i18n.gd, i18n_translation.gd, DrawUtil | present | tested (6,020 strings) |
| `/en/` path, guide links | i18n.js:28,145 | — | excluded (online) | |

### Save
| Item | JS | Godot | Status | Notes |
|---|---|---|---|---|
| newSave / migrate (v1→v2→v3) / sanitize | db.js:37-153 | save.gd | present | tested (real web guest save) |
| Save `name` "Invitado" (app mode, playAsGuest) | db.js:625-633 | save.gd | different → **fixed** | was "Entrenador" (seen in exports and the profile preview; the top bar shows "Entrenador" in both) |
| Guest storage → one file, boot loads it, commit sets `updated` | db.js:625-671 | save.gd, main.gd | present | |
| owns / grant / ownsShiny / grantShiny / upgradesOf | db.js:740-761 | save.gd | present | |
| Every save write (test choose, partner, shiny toggle, upgrades, hotkeys, bans, pulls, tickets on pickup, wild shiny, rescue, end of run, missions, profile) | test.js, menu.js, gacha-ui.js, game.js, progress.js, goals-ui.js | test_screen.gd, dex_screen.gd, menu_screen.gd, upgrades_screen.gd, gacha_screen.gd, meta.gd, sim.gd, progress.gd, goals_screen.gd | present | |
| Delete (and Godot's import) while a run is paused: quit the run first | settings-ui.js:165-175 | settings_screen.gd | different → **fixed** | see §1 |
| Cloud sync, accounts, sessions, nickname | db.js | — | excluded (online) | |
| Import / export of web saves | — | save.gd, settings_screen.gd | present | Godot extra, tested |

### Stats, progress hooks, missions, achievements
| Item | JS | Godot | Status | Notes |
|---|---|---|---|---|
| runs, totalKills, bestTime, bestLevel, coinsEarned, pulls, shinies, bossesTotal, riftWins, evolutions, missionsDone, legends, arenas, evoMoves, itemsFound | game.js:289-298, progress.js:87-148, gacha.js:123 | meta.gd, progress.gd, gacha.gd | present | |
| groupRuns / bestGroupTime | progress.js:151, game.js:296 | — | excluded (online) | co-op only |
| Progress hooks: kill, chest, item, evolve, rift, runEnd, missionDone; checkAch after run / gacha / menu / goals; throttle; popups | enemy.js:909, world.js:407, game.js:384, levelup.js:68, rift.js:193, progress.js | enemy_mgr.gd, world_map.gd, sim.gd, levelup.gd, rift.gd, meta.gd, progress.gd | present | |
| Missions: 3 daily + 2 weekly, Madrid period ids, seed, make / advance / claim / reroll / pending / text | progress.js, missions.js | progress.gd | present | tested |
| Mission reward text with ticket / coin icons | progress.js:119-125 | goals_screen.gd | present | the rows draw the icons (`rewardText` words are only used for the summary string) |
| 127 achievements (values, goals, rewards, titles 21) | achievements.js, progress.js:169-187 | progress.gd, achievements.json | present | tested; group1 / group10 unreachable offline |

### Gacha, upgrades, starters
| Item | JS | Godot | Status | Notes |
|---|---|---|---|---|
| Costs, rates, pity 70, ×10 guarantee, shiny 1 %, no repeated shiny, refunds, poolNear, 9 banners, featured | gacha.js | gacha.gd | present | tested (5 seeded sequences bit-identical) |
| 13 upgrades, cost formula, perks applied at run start (hp, atk, spd, cd, def, regen, magnet, xp, coins, Repertorio, crit, rerolls, bans, hotkeys, start move) | upgrades.js, game.js:112-126, player.js | upgrades.gd, meta.gd, sim.gd, player.gd, levelup.gd | present | tested |
| 29 starters, startMoveOf, trait texts, test scoring, result | starters.js, test.js | starters.json, moves.gd, meta.gd, test_screen.gd | present | tested |

### Data, sprites, boot
| Item | JS | Godot | Status | Notes |
|---|---|---|---|---|
| Data tables (pokedex, sprite meta, moves, types, starters, enemies, items, level-up stats, upgrades, missions, achievements, gacha, world, vfx, icons, music, dictionaries) | data/*.js | data/*.json | present | byte-identical re-export |
| Credits / licences shipped with the game | CREDITS.md, assets/fonts/OFL.txt, assets/fonts/fusion-pixel/ | godot/CREDITS.md, godot/assets/fonts/ (+ export preset) | missing → **fixed** | `exportCredits()` in tools/export_godot.js copies them; `include_filter` packs them into the APK |
| Sprite fallbacks (missing anim → Idle → Walk, loading → Idle → grey ball), cache, partner preload, body geometry | sprites.js | sprites.gd, draw_util.gd | present | |
| util (clamp … mmss) | util.js | u.gd | present | |
| Boot order, fonts | game.js:799-846, main.js:48-51 | main.gd | present | |
| Missing-module check, maintenance, tap-to-start, login, updater, service worker | main.js, game.js, updater.js | — | excluded (online) | |
| Version string | settings-ui.js:7 | settings_screen.gd | present (fixed in §5) | Android `version/name` stays "0.1" |
| News / changelog button (shown in the web app mode), Ko-fi ask on results, support page | changelog.js, news-ui.js, run-ui.js:96-127, support-ui.js | — | excluded (online) | per the brief; News would be ~70 lines (export `G.CHANGELOG` + an overlay) |
