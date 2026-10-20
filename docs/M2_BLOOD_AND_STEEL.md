# M2 - Blood and Steel

M2 implements a playable combat floor: explore the accepted dungeon, fight small
pre-placed demon patrols, defeat the required patrol, then reach the exit. Two
patrols are optional. Rooms stay open throughout. Death waits for R to restart.
There is no next-depth transition, boss, reward system, inventory or saving.

Starting checkpoint verified clean: `feature/conventional-15-depths`, `26d795b`,
`C:/Users/raysh/Development/Dungeon15-15-depths`. The owner approved M1 with 915
checks and 7/7 manual acceptances. M2 automated checks pass; M2 combat feel and
new GP325 face-button controls remain **pending manual acceptance**.
No commits, pushes, resets, stashes or destructive Git operations were performed.

## Play

Open **`src/game_3d/blood_and_steel.tscn`** in Godot **4.7.2** and press **F6**.
F5 still starts the original 2D game. The accepted M1 and hazard-validation scenes
remain independent and unchanged. Default seed is 12345; change the root's
`Run Seed` or pass `-- --seed=42` / `-- --seed=7`.

| Action | Keyboard | GP325 logical default |
| --- | --- | --- |
| Move, relative to the screen | WASD / arrows | Left stick / D-pad |
| Sword cut | Space / J | South face button (`JOY_BUTTON_A`, 0) |
| Dodge | Shift / K | East face button (`JOY_BUTTON_B`, 1) |
| Restart the whole combat run | R | Keyboard R |
| Show/hide controller diagnostics | H | Keyboard H |

Press attack again during the first cut to queue its follow-up. Holding a button
produces one cut; a chain contains at most two. Dodge cancels an attack, including
its queued follow-up. Attacks do not queue while dodging or staggered. Walking
remains available during attacks/recovery. Read the amber enemy anticipation,
dodge its strike and punish recovery. Brutes keep their committed swing through
light hits; basic and ranged demons can be stagger-interrupted.

The HUD shows health, current state, dodge readiness, patrol counts and the
required hall. Patrol signs at doorways turn green on completion. Clearing the
required patrol changes the exit label to OPEN; entering the exit reports
**DEPTH 1 CLEARED - R TO FIGHT AGAIN**. Other patrols may remain alive. R restores the
same seeded run with full health and all five enemies; geometry is not rebuilt.

## Combat rules

The samurai reuses the accepted capsule, movement input, camera-relative mapping,
gravity, slide collision and fixed isometric camera. A dark shoulder/helmet
silhouette and lightweight katana identify the player. The combat script extends
M1's player script and supplies a state-aware physics loop. The original M1/P1A
scripts are untouched.

| Player rule | Value |
| --- | --- |
| Health | 8 |
| First cut | 2 damage; 0.075 s windup, 0.12 s strike, 0.18 s recovery |
| Second cut | 3 damage; 0.11 s windup, 0.14 s strike, 0.25 s recovery |
| Sword reach / half-angle | 2.65 metres / 65 degrees |
| Walk speed | M1's 5 m/s dry, 2.5 m/s in water |
| Movement while cutting / recovering | 65% / 80% of current walk speed |
| Dodge | 9.5 m/s for 0.28 s; first 0.22 s invulnerable; 0.6 s cooldown |
| Hit reaction / hurt grace | 0.19 s reaction, 0.65 s repeated-damage protection |

A target is hit once per cut, only in the forward arc and with an unobstructed
world collision ray at Y=0.65, below the one-metre wall tops. Recovery, dodge,
stagger and death terminate active sword damage appropriately. Both directions
of melee and projectile flight respect solid obstacles. Dodge is stamina-free;
its cooldown and vulnerable tail prevent continuous invulnerability. It is a
burst move, so its speed differs from walking, including in water.

The player has a visible blade sweep, pooled contact burst, enemy white hit flash,
physical knockback, red player/body/screen flash, red health bar, fall/death poses
and explicit restart/completion messages. No hit-stop, time-scale changes, audio,
camera shake or high-cost lighting were introduced.

| Demon | HP / speed | Anticipation and behavior |
| --- | --- | --- |
| Basic | 4 / 3.2 m/s | Approaches; 0.5 s telegraphed melee, 1 damage; stagger interrupts the swing. |
| Brute | 12 / 1.8 m/s | 0.95 s committed windup, 3 damage, larger reach, 0.9 s recovery; resists light stagger while winding up/striking. |
| Ranged | 4 / 2.5 m/s | Backs away inside 4.5 m, approaches when distant/occluded; 0.65 s locked-direction aim telegraph, then visible firebolt; 1 damage. |

Enemy strike states last 0.13 s; basic/ranged recovery is 0.55 s, followed by a
0.4 s attack cooldown. Aim and melee direction lock during anticipation, enabling
positioning and dodging. Demons show WATCH/HUNT/WINDUP/ATTACK/RECOVERY/STAGGER/FALLEN
labels and health. Bodies fall briefly, disable collision and hide on death.
The five enemy instances stay allocated for bounded reuse on reset.

## Deterministic encounters and navigation

M2 uses the unchanged validated tile grid, graph links, room footprints and door
inside tiles. Quiet legacy rooms often have no enemy spawn candidates, so a new
M2 placement pass scans that existing grid. It never alters layout/content data.
Candidates use a stable `M2|seed|room|tile` hash to break positioning ties near the
actual incoming main-path door. It selects the first two suitable main-path rooms
and the last suitable room; entry, objective and special/story rooms are excluded.

Each selected room must have at least 64 dry supported tiles and two usable spawn
points. Each point has a safe 3x3 neighbourhood, stays at least three tiles from
every door inside, five from the exit and eight from the player's start. Group
members are separated by at least three tiles. One tile is two metres. No enemy
starts on pit, water, spikes, a solid tile, or an entry/exit lane. All five enemies
exist before player movement; room entry activates AI, not enemy spawning.

Exact spawn tiles, listed in order with basic/ranged/brute identities:

| Seed | Optional patrol 1 | Optional patrol 2 | Required patrol |
| --- | --- | --- | --- |
| 12345 | H01 basic `(110,15)` | H02 basic `(80,13)`, ranged `(77,14)` | H06 brute `(79,66)`, ranged `(70,64)` |
| 42 | H01 basic `(139,18)` | H02 basic `(112,17)`, ranged `(115,12)` | H06 brute `(35,65)`, ranged `(37,69)` |
| 7 | H01 basic `(18,44)` | H02 basic `(21,67)`, ranged `(15,67)` | H05 brute `(76,91)`, ranged `(78,82)` |

World centre is `(2*x+1, 0, 2*y+1)` metres. Layout fingerprints remain
`2994f8107a89ee44`, `31476b85897e6431`, `21ae2fd9691ea505` respectively. Repeated
plans match, and 20 additional seeds (0-19) supply suitable patrols. A floor that
cannot supply three safe rooms fails explicitly with a visible message instead
of substituting unsafe spawns. This is not an exhaustive guarantee for all seeds.

Enemy pathfinding uses one cardinal `AStarGrid2D` built from tile coordinates;
only floor/corridor/door/bridge tiles are eligible. Water, timed spikes, pits,
void and solids are blocked. Waypoints pass through the shared `grid_space.gd`
conversion; no pixel navigation receives metre coordinates. Steering checks dry
support and uses physical slide collision. AI stays within its room plus one
border tile, returns home when the player retreats, and retains damage taken.
There is no doorway locking or infinite reinforcement/spawn loop. A displaced
enemy falling below Y=-3 dies safely rather than falling forever.

Collision layers: world 1, player 2, demons 4. Projectile rays test world/player;
they can fly across gaps but cannot penetrate solids. No friendly fire is modeled.
Firebolts move at 8 m/s, expire after 2.4 s, and are capped at 12 simultaneous
instances. Impacts, expiry, death and resets clean them up. Contact FX reuse one
small node group; sword and enemy telegraphs are persistent reused meshes.

M1 terrain remains physically unchanged. Water halves walking speed; bridges
support bodies; pits remain open drops; safe/amber/red spikes retain their phases.
In M2, a pit fall or red-spike reset also restores the combat run, health and
patrols. Demon-hit dodge invulnerability does not bypass M1 terrain reset rules.
Deaths require R. All resets preserve seed/layout and clear projectiles, queued
combos, exit completion, hit state and room-clear state without rebuilding nodes.

## Verification

**1,061 assertions passed; zero failures in final suites.**

| Suite | Checks | Result |
| --- | ---: | --- |
| M1 geometry, traversal, deterministic layouts, input/action cleanup | 61 | passed |
| M1.1 physical hazards and controller integration | 37 | passed |
| M1.1 rendered hazard visibility | 9 | passed |
| Accepted P1A | 43 | passed |
| Existing controller suite | 50 | passed |
| Original 2D smoke | 378 | passed |
| Quick generator stress, including six unchanged golden fingerprints | 337 | passed, 328.4 s |
| M2 combat, navigation/occlusion, reset, controls, M1 terrain in combat | 113 | passed |
| M2 live-input encounter runs, seeds 12345/42/7 | 21 | passed, 7.4 s |
| M2 actual rendered combat/health/death/restart | 12 | passed, 1.5 s |

Focused checks include one hit per swing, deliberate two-cut cap, held/echo and
sub-physics-frame tap handling, dodge cancellation/invulnerability expiry, hurt
grace, knockback, stagger interruption, brute commitment/recovery, actual ranged
damage/backoff, thin-wall sword and enemy-melee rejection, projectile interception,
source-obstacle/pit detours, visible/damage cone boundary matching, falling enemy
cleanup, death/restart, optional/required
exit logic, repeat resets without growth, synthetic GP325 face buttons and unchanged
shared actions. M2 bridge crossing and water/pit/spike reset rules are exercised with the accepted
fixture data inside the combat runtime.

The live-input driver defeats all five demons in each seed using actual movement,
attack and dodge inputs against active AI, carrying health with no forced damage,
invulnerability, health refill or encounter reset. It starts at each patrol's
entrance and moves to the exit after combat; it does not claim a complete automated
walk through the connecting halls. Input directions are world-axis only in that
tools driver. The normal game uses the accepted isometric camera mapping.

Rendered scenarios cover sword/contact/stagger, brute warning, a flying projectile,
health/screen flash, death and R restart. A pixel probe verifies the actual orange
projectile core after accounting for the project's logical-to-window canvas stretch.
Captures were inspected in ignored `.godot/m2_*.png` files. They supplement state
checks and do not accept human gameplay feel or physical controller hardware.

Godot 4.7.2 import, independent combat boot and original 2D main-scene boot exited 0.
No final suite-time engine/script warnings or errors, exit leak warnings, orphan
increase on repeated scene teardown, or unbounded node growth were observed.
The existing Windows `Failed to read the root certificate store` startup error
still occurs before logger installation and is excluded from passing suite counts.
No golden outputs were changed. `git diff --quiet -- src data project.godot`
returned 0 for all original tracked runtime/data files.

## Performance

Measured on Windows / AMD Radeon(TM) Graphics, Godot 4.7.2 Compatibility/OpenGL,
**1280x720 window/capture**, with the unchanged project's **1152x648 logical canvas**
and canvas-items stretch. Fixed isometric camera size 27. Display reported 60 Hz.
Seed 12345. No concurrent Godot regression or benchmark processes were running.
Project VSync/input settings were not edited; only the benchmark process switches
VSync between scenarios.

Two protocols are reported separately:

- **Real time:** one-second warmup, five seconds of actual elapsed-time sampling
  per scenario. Physics runs at its normal 60 Hz. Average FPS is reciprocal mean
  wall-frame interval. The 1% low uses the mean of the slowest ceil(1%) intervals.
- **Fixed-step repeatability:** `--fixed-fps 60`, 60 warmup frames and 300 sample
  frames. One gameplay step per rendered frame gives the same AI schedule in
  VSync-on/off samples. Its uncapped values are simulation throughput, not directly
  comparable to real-time render rates. The tool verifies observed physics-step
  counts and rejects a mismatched timing protocol.

Entry scenarios leave all five enemies dormant. Active scenarios place a
stationary target at `(149,0,129)` in the required room, running the brute and
ranged demon, collision, telegraphs and projectiles. **Benchmark-only** hurt grace
keeps that target alive; no such invulnerability is enabled in the game or in the
live-input encounter tests. Resets restore the same conditions before each sample.

### Actual real-time frame samples

| Scenario | Frames | Average FPS | 1% low FPS | p50 / p95 frame ms | Approx. draw calls |
| --- | ---: | ---: | ---: | --- | ---: |
| Entry, VSync on | 146 | 29.10 | 25.94 | 34.267 / 36.266 | 77 |
| Entry, uncapped | 3208 | 641.43 | 170.82 | 1.240 / 3.329 | 77 |
| Active patrol, VSync on | 143 | 28.56 | 18.17 | 34.628 / 36.693 | 88.99 |
| Active patrol, uncapped | 3514 | 702.77 | 230.24 | 1.231 / 3.183 | 88.98 |

Real-time samples contain 300-301 physics steps over approximately five seconds,
confirming normal simulation timing. Short samples vary; an active scene's higher
uncapped average here is not evidence that combat improves performance. The active
VSync 1% low contains only the two slowest intervals and warrants manual long-run
pacing review.

### Matched fixed-step throughput

| Scenario | Average FPS | 1% low FPS | Physics steps / rendered frames |
| --- | ---: | ---: | --- |
| Entry, VSync on | 30.02 | 27.05 | 300 / 300 |
| Entry, uncapped | 340.22 | 142.63 | 300 / 300 |
| Active patrol, VSync on | 29.91 | 21.17 | 300 / 300 |
| Active patrol, uncapped | 326.60 | 148.99 | 300 / 300 |

The active fixed-step pair ends with matching enemy-state schedules, demonstrating
repeatable AI work. Do not compare its uncapped 326-340 FPS directly with the older
M1 variable-timestep benchmark.

Complete synchronous generation + floor + combat build: **338.86 ms** in the
real-time run, **345.91 ms** in the fixed-step run. This excludes first-frame GPU
shader compilation. The independent scene boot measured 326.40 ms. SceneTree
counts are **903** at entry, **903-906** during active samples: the three-node range
is one live projectile being created and removed. There are always five enemy
instances. Total collider shapes for this seed: **404 static world boxes + six
actor capsules**. Enemies/projectiles add no lights. The benchmark's tracked
static-memory peak was **65,524,080 bytes (about 62.5 MiB)**; GPU memory and process
RSS were not measured in this pass.

The M1 approximately 31-FPS observation remains reproducible near 29-30 FPS with
VSync enabled. The same scene runs hundreds of frames per second uncapped.
This supports presentation/VSync/compositor pacing as the dominant reason for
that number, rather than a saturated dungeon/combat simulation. The precise
Windows/driver cause remains unverified. No architecture rewrite or speculative
optimization was introduced. These measurements do not constitute a 60-FPS
acceptance claim or replace sustained interactive testing on the target hardware.


## Exact commands and evidence

From the active worktree in PowerShell:

```powershell
$godot = 'C:/Users/raysh/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe'
$env:APPDATA = Join-Path $PWD '.godot/m2_appdata'
New-Item -ItemType Directory -Force $env:APPDATA | Out-Null
& $godot --headless --path . --import
& $godot --headless --path . res://src/game_3d/blood_and_steel.tscn --quit-after 120
& $godot --headless --path . --quit-after 120
& $godot --headless --fixed-fps 60 --path . --script res://tools/first_dungeon_test.gd
& $godot --headless --fixed-fps 60 --path . --script res://tools/first_dungeon_hazard_test.gd
& $godot --path . --script res://tools/first_dungeon_visual_test.gd
& $godot --headless --fixed-fps 60 --path . --script res://tools/prototype_3d_test.gd
& $godot --headless --fixed-fps 60 --path . --script res://tools/abyss_input_test.gd
& $godot --headless --fixed-fps 60 --path . --script res://tools/smoke_test.gd
& $godot --headless --fixed-fps 60 --path . --script res://tools/generation_stress.gd -- --quick
& $godot --headless --fixed-fps 60 --path . --script res://tools/blood_and_steel_test.gd
& $godot --headless --fixed-fps 60 --path . --script res://tools/blood_and_steel_playthrough.gd
& $godot --fixed-fps 60 --path . --script res://tools/blood_and_steel_render_test.gd
# Run these sequentially with all regression processes finished:
& $godot --fixed-fps 60 --path . --script res://tools/blood_and_steel_benchmark.gd
& $godot --path . --script res://tools/blood_and_steel_benchmark.gd -- --realtime
# Manual alternate seeds:
& $godot --path . res://src/game_3d/blood_and_steel.tscn -- --seed=42
& $godot --path . res://src/game_3d/blood_and_steel.tscn -- --seed=7
git diff --check
git diff --quiet -- src data project.godot
```

Test logs are ignored `.godot/m2_*` files: `m2_blood_and_steel_test.gd.log`,
`m2_playthrough.log`, `m2_render_test.log`, `m2_generation_stress.gd.log` and the
corresponding M1/legacy suite logs. Benchmark artifacts are `m2_benchmark.log`,
`m2_benchmark_realtime.log`, `m2_performance.json`, `m2_performance_realtime.json`.
Evidence captures include `m2_sword_contact.png`, `m2_brute_warning.png`,
`m2_ranged_shot.png`, `m2_hurt.png`, `m2_death.png`, `m2_restart.png`.

## Manual acceptance checklist

1. F6 the combat scene, focus the window. Confirm seed/depth, health bar, starting
   marker, sword silhouette and responsive camera-relative WASD/arrows. F5 must
   still launch the original 2D game. Find H01, then the other signed patrols.
2. Hold Space/J: one attack only. Release and tap twice: two directed cuts,
   visible contact/stagger, then recovery. A third press during cut two must not
   extend the chain. Attack while moving, change direction between chains, and
   press dodge while cutting; movement/input must stay usable.
3. Fight the basic demon: read amber anticipation, interrupt with a sword cut,
   observe white flash/knockback and falling death. Approach/retreat repeatedly;
   enemies must already be present, retain damage and avoid doorway spawning.
4. Fight the brute: compare slower approach, longer warning and stronger damage.
   Light hits during its committed warning must not cancel it. Dodge the strike,
   exploit long recovery and verify there is a vulnerable gap between dodges.
5. Fight ranged demons: verify backoff, visible aim/firebolt, projectile travel,
   dodge and hit reactions. Put a pillar/wall between you and a demon; both swords
   and projectiles must fail to damage through it. Watch for stuck steering.
6. Confirm clear banners/signs. Skip an optional patrol; only the starred required
   patrol should gate exit completion. Rooms must remain traversable throughout.
   Win and confirm depth 1 completion without loading M3/boss/next-depth content.
7. Take damage, die, and press R. Confirm full health, identical enemy positions,
   reset patrol/exit state, no lingering shots and normal movement/attacks. Hold
   attack through restart: it must require release before attacking again. Repeat R.
8. Repeat seeds 42 and 7. Verify preserved spikes/water presentation and effects;
   water slows walking, safe spikes can be crossed, red spikes reset the run even
   while dodging. Pit/bridge fixture acceptance remains available in the unchanged
   M1 validation scene; combat integration tests exercise those tile rules too.
9. **Real GP325:** connect it, F6, H for device/axis/button diagnostics. Test left
   stick/D-pad movement, partial deflection, diagonals, release and 30-second resting
   drift. Test south attack and east dodge; record actual logical button indices.
   Hold south for a single cut, tap twice, and test combined keyboard/stick controls.
   Verify no double attacks when sources overlap; dodge wins simultaneous requests.
10. Unplug/reconnect during movement/combat. Keyboard must remain usable; neutral
    reconnect must not drift or retain attacks. Repeat death/R and stop/F6 re-entry.
    If mappings differ, change only **ControllerInput** inspector fields (inherited
    axes/D-pad/deadzone/device, plus `attack_button`/`dodge_button`) and repeat all
    checks. No global InputMap/controller database changes are needed.

M1's earlier hardware acceptance is the owner's checkpoint. The new M2 attack/
dodge bindings and combat behavior have **not** been accepted on real GP325
hardware by automation. The automated environment had no connected controller.

## Exact changed-file inventory

Modified: `DEVELOPMENT.md` (current milestone/status only).

Created gameplay files:

- `src/game_3d/blood_and_steel.tscn`
- `src/game_3d/combat/combat_floor.gd`
- `src/game_3d/combat/combat_input.gd`
- `src/game_3d/combat/combat_navigation.gd`
- `src/game_3d/combat/combat_visuals.gd`
- `src/game_3d/combat/samurai.gd`
- `src/game_3d/combat/demon.gd`
- `src/game_3d/combat/demon_projectile.gd`

Created validation files:

- `tools/blood_and_steel_test.gd`
- `tools/blood_and_steel_playthrough.gd`
- `tools/blood_and_steel_render_test.gd`
- `tools/blood_and_steel_benchmark.gd`
- `docs/M2_BLOOD_AND_STEEL.md`

Each of the 11 new `.gd` files has its generated `<filename>.uid` sidecar: seven
in `src/game_3d/combat/`, four in `tools/`. Total inventory: **25 files** including
sidecars and the modified status document. All logs, screenshots and benchmark
probe files stay in ignored `.godot/`; no generated source or goldens were replaced.
The original 2D game, M1/M1.1 sources, generation/profile data, accepted camera/
controller foundations, main-scene setting and Abyss sources remain unchanged.

## Limits and stop condition

This is one short graybox combat floor, with five enemies across three patrols.
Quiet routes remain; later approved work must assess density, pacing and balance.
Meshes/animation/feedback are placeholders and silent. There is no stamina,
friendly fire, reward collection, save system, boss or campaign progression.
Navigation is deliberately conservative around water/spikes; enemies may wait
at those boundaries. Static paths plus physical capsules provide separation,
without a crowd-steering system. Projectiles use a swept centre ray; their visual
sphere is not a swept-volume collider. Difficulty and the two-cut/dodge feel still
need human testing. Short automated timing and render samples do not replace a
long interactive session or guarantee performance on other hardware.

Stop after M2. Manual keyboard/GP325 combat acceptance and feedback come next.
M3, bosses, rewards and further depths require explicit approval. No automatic
commit or push was performed.
