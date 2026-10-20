# M3 — The Descent

Standalone scene: `src/game_3d/the_descent.tscn` (F6). Three-depth vertical slice,
not the full 15-depth campaign. Starting checkpoint: clean
`feature/conventional-15-depths` at `02889ab`. No commits or pushes performed.

## Implementation

`descent/run_controller.gd` owns depth, health, upgrade ranks, per-depth cleared
encounters and claimed rewards. Its phases are BUILDING, PLAYING, REWARD, DEAD
and VICTORY. Each floor is a disposable child using `descent/descent_floor.gd`,
a thin subclass of the accepted M2 floor. Whole-floor deletion removes geometry,
hazards, enemies, projectiles, camera, UI and the scene-owned input adapter.
Rebuilding waits for deletion before creating the next floor. Scene-local input
actions and connection listeners use M1/M2's existing teardown.

Depth 1 uses the run seed unchanged. Depths 2 and 3 use
`StableHash.hash62("DUNGEON15:M3:<run seed>:<depth>") % 2147483647`.
Each calls the existing generator with the existing profile for that depth.
Invalid depth seed requests return -1. No generation algorithm, profile, golden
output, original 2D file or configured main scene changes are involved.

Validated run fixtures (floor seed / generated fingerprint):

| Run seed | Depth 1 | Depth 2 | Depth 3 |
| --- | --- | --- | --- |
| 12345 | 12345 / `2994f8107a89ee44` | 1068606711 / `15378e45842510e1` | 1118939568 / `1afd9d286c64883c` |
| 42 | 42 / `31476b85897e6431` | 1718941579 / `223b1795cb031e89` | 1668608722 / `1f123211f6862aa5` |
| 7 | 7 / `21ae2fd9691ea505` | 1604320830 / `049b25eaa3050f6e` | 1654653687 / `38b509327401e80e` |

The final selected patrol is required; other patrols remain optional and no room
locks are introduced. Clearing the objective freezes the floor and presents one
reward choice. Selection unlocks descent, but the player must reach the exit
tile and freshly press E, Enter or south. Contact alone never advances a floor.
Phase and transition guards reject duplicate interactions. Depth 3 offers its
reward and then explicitly labels completion **VERTICAL-SLICE VICTORY**.

Health carries across floors without automatic healing. R starts a fresh run
at Depth 1 using the same run seed. Death freezes the floor and waits for R,
Enter or south; it never silently restarts. Pits and raised spikes remain fatal;
water slowdown, bridge support and timed spike windows are inherited from M1.
The M2 standalone floor retains its accepted full-floor reset behavior.

## Difficulty and rewards

Enemy HP increases by exactly `depth - 1`: basic/ranged 4/5/6 HP, brute
12/13/14 HP. Damage remains basic 1, brute 3, projectile 1. Windups, movement,
attack ranges, invulnerability and obstacle-aware navigation remain M2's.

The planner reuses M2's validated main-path room scan and safe 3×3 spawn patches,
door/entry/exit separation and minimum 64 dry room tiles. M3 selects up to
3/4/5 suitable rooms, distributed along that path. The first has one basic;
subsequent patrols alternate basic+ranged and brute+basic. On Depth 3 the final
patrol has brute+basic+ranged when three separated safe patches exist. Otherwise
it retains two enemies. There are at most ten enemies, all pre-placed before
play begins, and at most twelve concurrent projectiles.

An input-bot investigation found clear spawn patches could lie beyond a hazard
barrier. M3 additionally requires a dry navigation path from the actual incoming
door to every selected spawn. M2's default placement stays unchanged. This is a
placement filter; it neither fills hazards nor modifies the generated layout.
Fewer than three suitable rooms produces an explicit safe-build failure screen,
not unsafe fallback spawns or hidden seed rerolls.

| Choice | Effect per selection | Run bound |
| --- | --- | --- |
| Sharpened Blade | +1 damage to both cuts, starting at 2/3 | +3; cuts 5/6 |
| Reinforced Guard | +2 maximum HP and heal 2 | maximum 14 HP |
| Swift Step | -0.08s interval between dodge starts, starting at 0.60s | minimum 0.36s |

Exactly one selection per depth, at most three ranks per option, three selections
per run. Repeated clicks, held button events, opening-frame confirmation and
invalid indices cannot grant extra rewards. All ranks and claims reset on a new
run. Rewards do not change dodge invulnerability or water speed. The final
reward applies before leaving Depth 3; there is no further depth in this slice.

The HUD shows health, both seeds, depth progress, ranks, combat state and a
screen-relative direct bearing to the next uncleared patrol or exit. This is
wayfinding, not a safe-path promise: follow doorways and respect hazards.
Architectural geometry and existing room landmarks are retained. No decoration
is presented as evidence of improved engagement. Corridor lengths remain those
of the accepted generator and need human pacing assessment.

## Automated evidence

Godot 4.7.2 console executable used:

```powershell
$godot='C:/Users/raysh/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe'
$env:APPDATA=Join-Path $PWD '.godot/m3_appdata'
New-Item -ItemType Directory -Force $env:APPDATA | Out-Null
& $godot --headless --path . --editor --import --quit
& $godot --headless --path . --script tools/the_descent_test.gd
& $godot --headless --path . --fixed-fps 60 --script tools/the_descent_playthrough.gd
& $godot --path . --fixed-fps 60 --script tools/the_descent_render_test.gd
```

The focused run suite passes **206 checks**. It verifies all nine requested
seed/depth combinations against freshly generated fingerprints, supported routes,
safe reachable pre-placed actors, exit gates, one reward per depth, remote and
repeated exit rejection, floor deletion, victory, complete reset, actual upgraded
sword damage/HP/dodge timing and synthetic keyboard/controller reward navigation.
Five repeated death resets show stable node counts, input action counts and
joypad connection subscription counts.

The live combat suite passes **68 checks**: seeds 12345, 42 and 7 complete all
three depths, defeating **64 demons in 35 patrols** through actual movement,
sword and dodge inputs. It carries health, applies Blade then Guard then Step,
never forces damage, health or invulnerability, and never resets a fight.
Final HP before the last reward is 10, 10 and 9 respectively. The tool warps to
each patrol entrance and to the exit; this is not an end-to-end hallway walk or
proof of human combat feel. Its waypoint driver skips the current path tile on
repath to avoid oscillating back toward the tile centre.

Rendered UI passes **17 checks**, including actual mouse selection, keyboard
confirmation, each reward screen, victory and death confirmation at 1280×720.
Screenshots are in ignored `.godot/m3_*.png`. The inherited harness rejects
suite-time engine/script warnings and errors and incomplete test coroutines.
Godot emits the pre-existing Windows root-certificate-store error before the
harness is installed; this is not a claim of entirely clean engine startup.

Regression commands (same environment, logs `.godot/m3_<suite>.log`):

```powershell
foreach($suite in @('first_dungeon_test','first_dungeon_hazard_test',
  'prototype_3d_test','abyss_input_test','smoke_test',
  'blood_and_steel_test','blood_and_steel_playthrough')) {
  & $godot --headless --path . --script "tools/$suite.gd"
}
foreach($suite in @('first_dungeon_visual_test','blood_and_steel_render_test')) {
  & $godot --path . --fixed-fps 60 --script "tools/$suite.gd"
}
& $godot --headless --path . --script tools/generation_stress.gd -- --quick
```

| Suite | Passing checks | Failing checks |
| --- | ---: | ---: |
| M1 first dungeon | 61 | 0 |
| M1 hazard/controller | 37 | 0 |
| M1 rendered hazard visibility | 9 | 0 |
| P1A 3D | 43 | 0 |
| Accepted input regression | 50 | 0 |
| Original 2D smoke | 378 | 0 |
| Generator stress `--quick`, including six unchanged goldens | 337 | 0 |
| M2 combat | 113 | 0 |
| M2 live encounter driver | 21 | 0 |
| M2 rendered combat | 12 | 0 |
| M3 run/upgrade/input/teardown | 206 | 0 |
| M3 live three-depth combat | 68 | 0 |
| M3 rendered UI | 17 | 0 |
| **Total** | **1,352** | **0** |

Generator stress completed in 309.3 seconds; no golden fingerprints were edited.
Final Godot import, standalone rendered boot (120 fixed frames), and original
main headless boot (five frames) completed without script errors or leak reports.
The pre-existing certificate-store startup error noted above remains.

```powershell
& $godot --path . --fixed-fps 60 src/game_3d/the_descent.tscn --quit-after 120
& $godot --headless --path . --quit-after 5
git diff --check
git diff --exit-code HEAD -- project.godot src/main src/dungeon data `
  src/game_3d/first_dungeon.gd src/game_3d/gamepad_input.gd `
  src/game_3d/combat/demon.gd src/game_3d/combat/demon_projectile.gd
```

The protected-path diff is empty. The full changed-file inventory follows;
unchanged generator goldens and original 2D smoke are independently exercised.

## Runtime performance

Measured with Godot 4.7.2, OpenGL Compatibility, AMD Radeon(TM) Graphics,
1280×720 physical window, 1152×648 logical canvas, 60 Hz reported display,
orthographic camera size 27. No regression processes ran concurrently.
Run seed 12345, Depth 3 seed 1118939568, ten enemies already instantiated.

```powershell
& $godot --path . --script tools/the_descent_benchmark.gd -- --realtime
& $godot --path . --fixed-fps 60 --script tools/the_descent_benchmark.gd
```

The tool builds Depth 3 directly after its normal Depth 1 bootstrap, without
forcing a live run through objectives. It resets actors, projectiles and spike
time between scenarios. Entry is stationary at (37,0,31); active is stationary
at (367,0,125), inside the required brute/basic/ranged patrol. Benchmark-only
hurt grace keeps the target alive; it is not a gameplay feature. Camera motion
is disabled, while normal AI and projectiles continue. Each realtime scenario
warms for one second and samples five seconds. Average FPS is reciprocal mean
wall-frame interval; 1% low uses the mean of the slowest ceiling(1%) intervals.

| Realtime scenario | Samples | Average FPS | 1% low FPS | p50 / p95 ms | Mean draws |
| --- | ---: | ---: | ---: | --- | ---: |
| Entry, VSync on | 145 | 28.98 | 27.21 | 34.502 / 35.797 | 94 |
| Entry, uncapped | 2644 | 528.66 | 256.24 | 1.720 / 3.035 | 94 |
| Active, VSync on | 145 | 28.90 | 26.15 | 34.605 / 35.776 | 88.77 |
| Active, uncapped | 2669 | 533.65 | 259.24 | 1.687 / 3.127 | 88.74 |

All realtime samples observed 300–301 physics steps over five seconds. The
fixed-step comparison uses 60 warmup frames and 300 measured render/physics
steps per scenario; it measures wall throughput with a fixed simulation clock,
not normal realtime game speed. Its separate JSON is `.godot/m3_performance.json`;
realtime data is `.godot/m3_performance_realtime.json`.

| Fixed-step scenario | Average FPS | 1% low FPS | p50 / p95 ms |
| --- | ---: | ---: | --- |
| Entry, VSync on | 29.73 | 28.24 | 33.684 / 34.714 |
| Entry, uncapped | 300.94 | 182.66 | 3.250 / 4.404 |
| Active, VSync on | 29.23 | 25.25 | 34.008 / 35.976 |
| Active, uncapped | 272.31 | 149.53 | 3.496 / 5.297 |

Complete Depth 3 floor construction took **434.849 ms** in the realtime run and
**435.548 ms** in the fixed-step run, including M3 stat application and UI setup
for that floor, excluding the deferred transition wait and persistent run UI.
There are **483 static collision boxes + 11 actor capsules = 494 shapes**.
Nodes remain **1121 at entry and 1121–1124 active**, the additional three nodes
being one projectile. Tracked static-memory peak is **67,644,130 bytes
(about 64.5 MiB)**. Process RSS and GPU memory were not measured.

For context, accepted M2's Depth 1 realtime measurements were 29.10/28.56 FPS
at entry/active with VSync and 641.43/702.77 uncapped, with 77/89 draw calls,
410 collision shapes and about 62.5 MiB tracked peak. M3's measured Depth 3
has more geometry and twice as many enemies; these are different workloads,
not a controlled attribution of the difference to one code change.

The roughly 29 FPS VSync result persists despite uncapped median intervals
around 1.7 ms. Presentation scheduling is a plausible limiter of the VSync
case; an exact OS/driver cause has not been established. The denser floor has
more nodes/colliders/draws, but no CPU/GPU profiler attribution was attempted.
These short stationary scenarios do not measure full-run percentiles or prove
hardware-wide performance. No architecture rewrite or speculative optimization
was introduced.

## Changed-file inventory

Modified (4):

- `DEVELOPMENT.md` — current milestone and acceptance status.
- `src/game_3d/combat/combat_floor.gd` — overridable encounter-plan hook; default M2 plan retained.
- `src/game_3d/combat/combat_navigation.gd` — opt-in M3 room selection, compositions and safe room access filter.
- `src/game_3d/combat/samurai.gd` — configurable sword bonus and dodge interval with unchanged defaults.

Created (14):

- `src/game_3d/the_descent.tscn`
- `src/game_3d/descent/descent_floor.gd`
- `src/game_3d/descent/descent_floor.gd.uid`
- `src/game_3d/descent/run_controller.gd`
- `src/game_3d/descent/run_controller.gd.uid`
- `tools/the_descent_test.gd`
- `tools/the_descent_test.gd.uid`
- `tools/the_descent_playthrough.gd`
- `tools/the_descent_playthrough.gd.uid`
- `tools/the_descent_render_test.gd`
- `tools/the_descent_render_test.gd.uid`
- `tools/the_descent_benchmark.gd`
- `tools/the_descent_benchmark.gd.uid`
- `docs/M3_THE_DESCENT.md`

Evidence logs, screenshots and performance JSON remain under ignored `.godot/`.

## Human acceptance — pending

1. Open `src/game_3d/the_descent.tscn`, press F6. Expect Depth 1/3 and seed 12345.
   For another run seed launch `... --path . src/game_3d/the_descent.tscn -- --seed=42`
   or `--seed=7`. The project main scene remains the original 2D game.
2. Move with WASD/arrows. Space/J cuts; a fresh second press queues cut two.
   Shift/K dodges. Confirm responsive movement, wall collision and sword occlusion.
3. Follow doorway signs and HUD bearings. Patrols before the required
   objective are optional. Check small encounters have readable dodge space.
   Pits are openings, bridges support traversal, water slows, red spikes kill.
4. Clear the required patrol. Choose an upgrade using arrows/WASD + Enter or
   mouse. Check only one choice applies, health/ranks update, and combat resumes.
5. Reach the green exit marker. Standing on it must not transition. Press E or
   Enter to descend once. Confirm Depth 2 retains HP/upgrades and has changed
   enemy combinations. Repeat for Depth 3; complete its reward and exit to see
   **VERTICAL-SLICE VICTORY**, with 3/3 completed and no Depth 4.
6. Press R. Check Depth 1, 8/8 HP, no upgrades, all patrols restored. Die to an
   enemy or fatal terrain. Confirm death waits for a fresh restart action and
   that restart resets the entire run, not just the current floor.
7. Connect GP325. H shows device/deadzone diagnostics. Verify left-stick analog
   movement and all four D-pad directions, south attack and east dodge, including
   a two-cut chain. Centre the stick for several seconds: no unintended movement.
8. With GP325, clear an objective. Use D-pad and left-stick up/down to navigate;
   south confirms one reward. Holding south must not choose twice or immediately
   descend. Release and freshly press south at the exit to advance.
   Reward stick navigation triggers above 0.60 and rearms below 0.30 on each
   axis; gameplay movement retains the accepted 0.22 deadzone.
9. Alternate keyboard and pad without unplugging, including reward selection.
   Restart with R, then south/Enter from death/victory. Re-enter with F6; check
   mappings, no drift, and no inherited upgrade. Disconnect/reconnect the pad and
   verify diagnostics and controls recover.
10. Assess the full hallway walk, clarity of exits and whether encounter spacing
    feels purposeful. Record uncomfortable empty stretches and unfair groups.

Real GP325 hardware, human combat feel and complete hallway pacing acceptance
remain pending. Automated synthetic input is not hardware acceptance. No bosses,
Depths 4–15, persistence, menus, new dependencies or archived Abyss runtime
systems were added. Stop here for human playtesting and approval.
