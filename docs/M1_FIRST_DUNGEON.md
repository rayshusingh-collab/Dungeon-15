# M1.1 human playtest corrections

The owner accepted M1 scene boot, responsive keyboard movement, wall/obstacle
collision, entrance-to-exit traversal, comfortable camera framing and movement
without noticeable stuttering. M1.1 changes below need a fresh visual/hazard review.
Physical GP325 acceptance remains **unverified**. Stop after M1.1; no M2 work,
commits or pushes are authorized by this pass.

## What was missing, exactly

The unchanged depth-1 profile offers pit/bridge, water and trap templates. Template
selection does not guarantee that every hazard appears in every seed. The source
of truth is the generated tile grid, not the list of available templates.

[Complete reproducible layout audit](M1_LAYOUT_AUDIT.json) records **every exact
[x,y] tile position**, room footprint/anchor, source spike region and room-level
content metadata for seeds 12345, 42 and 7. Coordinates are integer tiles; their
world centre is `(2*x+1, 0, 2*y+1)` metres. Audit script:
`tools/first_dungeon_audit.gd`. Counts below are tiles, except explicitly labelled
regions/rooms; obstacle tiles are not a count of separate mesh objects.

| Seed | Pits | Bridges | Water | Spike tiles / source trap regions | Obstacle tiles | Inner-wall tiles | Rubble tiles | Special rooms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 12345 | 0 | 0 | 0 | 28 / 2 | 59 | 0 | 46 | 1 |
| 42 | 0 | 0 | 0 | 36 / 3 | 75 | 36 | 26 | 1 |
| 7 | 0 | 0 | 60 | 0 / 0 | 46 | 7 | 23 | 1 |

Exact hazard positions (inclusive ranges, no inferred or invented content):

- **12345:** spikes at `x=68..69, y=39..45` and `x=80..81, y=39..45`,
  both in room 05 (`trap_gallery`). No pit, bridge or water positions exist.
- **42:** spikes at `x=132..133, y=17..23` and `x=144..145, y=17..23`
  in room 01 (`trap_gallery`), plus `x=134..137, y=69..70` in room 10
  (`room_medium`). No pit, bridge or water positions exist.
- **7:** water at `x=79..88, y=84..89` in room 05 (`water_chamber`).
  No pit, bridge or spike positions exist.

All obstacle positions are enumerated under each seed's
`terrain.obstacles.tiles` in the audit; rubble and inner walls have their own
lists. These lists preserve irregular shapes rather than approximating them
with bounding boxes.

"Special room" here means a generated `special_rule`, not an encounter role.
Each sample has one `story_chamber`, variant 0, with 230 accessible tiles (920 m�):

| Seed | Room | Footprint origin / size in tiles | Anchor |
| --- | --- | --- | --- |
| 12345 | 04 | `(30,36)` / `(22,14)` | `(40,42)` |
| 42 | 04 | `(34,12)` / `(22,14)` | `(44,18)` |
| 7 | 03 | `(6,80)` / `(22,14)` | `(16,86)` |

Diagnosis by category:

- **A � Not generated:** all pits and bridges in the three samples; water in
  12345/42; spikes in 7. The selected profile contains these templates, but
  those particular layouts do not select them. No procedural configuration,
  generator algorithm or golden fingerprint was changed to force a result.
- **B � Generated but not instantiated:** no missing terrain tiles were found;
  M1's exhaustive collision/coverage tests verify their footprints. Story room
  geometry exists, but its story marker/content is intentionally omitted by M1.
  Enemy/encounter/reward metadata is also intentionally inactive. These rooms
  therefore lack much of the meaningful content planned by the legacy generator.
- **C � Present but unclear:** M1 water was a flat blue surface without ripples
  or shoreline cues. Safe spikes were a brown pad with invisible tips and no
  visible sockets. An unmarked story room looked like another empty hall.
- **D � Distant or outside a representative route:** the nearest spikes are
  162 walking steps from entry in 12345, and 25 in 42. Water in 7 first appears
  144 steps from entry. The chosen shortest exit paths touch 2/28 spike tiles
  in 12345, 2/36 in 42, and 10/60 water tiles in 7. Seed 42's extra eight spike
  tiles in room 10 lie outside that route. All water/spike tiles are reachable.
  This is one deterministic shortest route, not a claim about every human path.

## Readability and environmental interest changes

Generated geometry and collision remain identical. Presentation now provides:

- Safe stone floor joints and simple wall masonry, with shared materials.
- A genuinely recessed pit opening with vertical side faces down to its dark
  bottom. It has no horizontal collider, and falling still resets at Y=-3.
- Opaque teal water with animated ripple bands and pale shoreline edges;
  physically supported water still halves movement speed.
- Timber bridge plank seams and low edge beams where it borders pit/water/void.
  The existing bridge floor supplies traversal collision; no rail blockers were added.
- Dark spike sockets during the safe phase, short amber tips during warning,
  and full red tips during activation. Timings and entry-reset rules remain intact.
- Numbered chamber inlays, door sill accents and a restrained inscription-floor
  motif in the existing special room. These identify places without adding story,
  rewards, encounters or new obstacles. Details are batched and non-colliding; no additional lights were added.
- **H** toggles actual generated-terrain counts and controller diagnostics.

Room-size analysis explains the remaining emptiness:

| Seed | Rooms | Accessible room area min / mean / max, m� | Plain floor / accessible room tiles |
| --- | ---: | --- | --- |
| 12345 | 14 | 252 / 653.7 / 1300 | 2182 / 2288 (95.4%) |
| 42 | 13 | 316 / 725.8 / 1296 | 2245 / 2359 (95.2%) |
| 7 | 10 | 344 / 712.0 / 1244 | 1666 / 1780 (93.6%) |

Total accessible walkable tiles, including corridors, are 3023, 2941 and 2176.
The footprint scale and plain-floor distribution remain unchanged. Numbering and
surface cues help players judge scale, recognize rooms and read terrain. Most
rooms still have no active gameplay beyond traversal and collision. This pass
makes no claim that added decoration makes the dungeon engaging. A later approved
milestone must assess room scale, meaningful activity and pacing together.

## Separate playable hazard validation fixture

Open **`src/game_3d/hazard_validation.tscn` and press F6**. Its banner explicitly
says **NOT A CAMPAIGN FLOOR**. `hazard_fixture_data.gd` supplies fixed test data;
it is outside the campaign scene's dependency graph and does not edit a profile.
The fixture contains 24 pit tiles, 18 bridge tiles, 18 water tiles, nine spike
tiles and four obstacle tiles. Every run uses the same layout (fixture ID 1101).

- **1:** stand before the bridge/pit. Cross the timber surface; step sideways
  off it into the opening to verify falling and entry reset.
- **2:** stand before the water. Walk into it, compare speed with dry floor,
  then leave it and verify full speed returns.
- **3:** stand before the spikes. Begin crossing at the start of the safe phase.
  Watch sockets, amber warning tips and raised red tips. Standing on red resets.
  Amber is a warning, not a guarantee there is enough remaining time to cross.
- **R:** return to entry. **H:** show diagnostics. All movement bindings match M1.
  Numeric shortcuts exist only in this fixture. Terrain labels have no floating
  marker platforms over hazards.

Rendered pixel probes test pit/floor contrast, bridge surface, water colour/ripples,
warning and raised colours, alongside the separate physical fixture suite. Ignored
captures `.godot/m11_fixture_entry.png`, `m11_pit.png`, `m11_bridge.png`,
`m11_water.png`, `m11_spikes_safe.png`, `m11_spikes_warning.png` and
`m11_spikes_raised.png` are regenerated by the visual suite and were inspected.

## GP325 manual acceptance checklist

The scene's `ControllerInput` node is assigned to the active P1A player's
`movement_input`. It owns private actions and leaves project `move_*` bindings
unchanged. Diagnostics show selected device ID, processed pad vector (including
D-pad), combined movement, deadzone, latest axis/button event and connection event.
Only diagnostics were refactored; the accepted mapping/movement logic is retained.

1. Connect GP325 in its normal Windows mode, F6 either scene, focus the window,
   press H. Record device ID/name from Godot, mode and any mapping adjustments.
   Automated runs reported no connected hardware (ID -1).
2. **Left stick:** test all cardinal directions and diagonals, partial travel,
   full travel, release and turning. Directions must be camera-relative; diagonal
   speed must stay normalized. Hold neutral for 30 seconds: pad vector and player
   movement must remain zero. Default radial deadzone is 0.22.
3. **D-pad:** test all four directions, diagonal combinations if the pad supports
   them, hold/release, and walking/sliding against walls. Record observed button or
   hat-axis indices; no Xbox physical labels are assumed.
4. **Combined input:** while holding the stick right, hold keyboard up: movement
   should combine diagonally at capped speed. Release keyboard while keeping stick
   held: controller movement continues. Reverse the order. Opposing directions
   should cancel according to their processed magnitudes, without increased speed.
5. **Reset/re-entry:** neutralize the controller, press R: return to entry and
   stay still. Repeat while deliberately holding a direction: reset clears velocity,
   then held input intentionally resumes movement next tick. Stop the scene, release
   all controls and F6 again: no stale movement or extra input actions should remain.
6. **Disconnect/reconnect:** unplug while moving, verify movement stops and keyboard
   still works; reconnect neutral and verify there is no drift, then retest stick
   and D-pad. The overlay should report the connection and selected device changes.
7. **Hazards:** in the fixture, repeat bridge crossing, pit fall/reset, water entry/
   exit and safe spike crossing with the controller. After each reset, neutral and
   held-input behavior should match step 5.
8. If mappings differ, edit only this scene's **ControllerInput** inspector exports:
   preferred device, left-stick axis indices/inversion, D-pad button indices or
   optional hat axes, and deadzone. Retest all steps; do not change global input.

Synthetic checks verify scene wiring, mapped events, analog response, four D-pad
vectors, combined keyboard/pad input, neutral/deadzone behavior and reset lifecycle.
They cannot accept real GP325 detection, physical mappings, drift, disconnects or feel.

## Performance investigation and validation

Godot **4.7.2**, Windows, AMD Radeon(TM) Graphics, windowed **1280�720**, project
**Compatibility/OpenGL** renderer, orthographic camera size 27, reported display
refresh 60 Hz. Seed **12345**. No concurrent regression processes during the final
comparison. Each scenario warms up for 60 rendered frames and samples 300 frames.
`Time.get_ticks_usec()` measures actual intervals between rendered process frames.
Average FPS is 1000 / mean interval in milliseconds; the 1% low is 1000 / mean
of the slowest three intervals. These short uncapped samples are diagnostic,
not sustained-play performance guarantees.

`entry_vsync` is a fixed entry camera with VSync enabled; `entry_uncapped` uses
that same camera with VSync disabled. `entry_hidden_geometry` additionally hides
floor visuals while retaining collision, player and UI. `route_uncapped` places
the fixed-orientation camera at successive route tiles by frame index; follow
smoothing is disabled only in the benchmark, ensuring identical camera samples
before/after. It is a render sweep, not a player movement or hardware-input test.
The normal game's camera and project graphics settings remain unchanged.

| Scenario | M1 average / 1% low FPS | M1.1 average / 1% low FPS | M1.1 frame p50 / p95, ms | Draw calls M1 ? M1.1 |
| --- | --- | --- | --- | --- |
| Entry, VSync enabled | 30.48 / 28.70 | 29.78 / 27.56 | 33.581 / 34.640 | 69 ? 73 |
| Entry, VSync disabled | 709.18 / 154.56 | 695.53 / 168.44 | 1.113 / 3.571 | 69 ? 73 |
| Hidden geometry, VSync disabled | 1099.61 / 195.61 | 1093.51 / 199.08 | 0.654 / 2.816 | 17 ? 19 |
| Route camera sweep, VSync disabled | 823.12 / 206.98 | 757.81 / 184.51 | 0.973 / 3.283 | 47.44 ? 51.69 |

- Complete generation + scene build: **268.76 ms M1 ? 288.03 ms M1.1** in the
  rendered comparison. Latest headless M1.1 samples: **279.56 / 176.12 / 145.11 ms**
  for seeds 12345 / 42 / 7. These are individual samples, not a confidence interval.
- Benchmark SceneTree nodes (including one benchmark camera-focus node and normal
  project roots): **828 ? 844**. Each remains constant across all samples.
  Headless test counts for the three seeds: **843 / 798 / 586**; each remained
  constant in steady-state checks and repeated scene teardown left no extra orphans.
- Floor collision: **one StaticBody3D, 404 unchanged box shapes** for 12345;
  **382 / 278** shapes for 42 / 7. Player adds one capsule shape. Environmental
  details add **zero** collision shapes and **zero** lights.
- Godot tracked static-memory peak in the final rendered comparison was about
  **54.8 MiB** in both runs. This excludes a full GPU-memory/RSS assessment.

The original approximately 31-FPS result is reproduced by VSync-on entry samples.
Disabling VSync raises throughput by over an order of magnitude on the same
geometry. Hiding all floor visuals improves uncapped throughput further, but does
not explain a 33-ms default frame interval. This supports **VSync/compositor/display
presentation pacing** as the dominant cause of that number. The precise Windows/
driver reason for roughly half the reported 60-Hz refresh remains unverified.
Additional visuals have a measurable cost; this pass makes no performance-improvement
claim. No streaming, batching architecture rewrite, global VSync change or speculative
optimization was introduced to address the 31-FPS observation.

Final tests: **915 checks passed**, zero failures:

| Suite | Checks | Result |
| --- | ---: | --- |
| M1 regression: source geometry, rays, full timed traversal, bindings, teardown | 61 | passed, 15.5 s |
| M1.1 hazard fixture + active controller integration + diagnostics | 37 | passed, 0.7 s |
| Actual rendered hazard visibility | 9 | passed, 1.0 s |
| Existing P1A | 43 | passed |
| Existing accepted controller suite | 50 | passed |
| Existing 2D smoke | 378 | passed, 33.1 s |
| Existing quick generator stress, including six unchanged golden fingerprints | 337 | passed, 312.3 s |

Import and independent fixture boot exited 0. Both final render benchmarks exited 0
with no shutdown leaks or script warnings/errors. Exhaustive M1 coverage/rays still
match the source grid for all three seeds; the physical fixture verifies actual pit
falls, full bridge crossing, measured half-speed water movement and safe/warning/
raised spike rules. Render probes found 10,923 dark pit pixels versus 708 on safe
floor, 27,227 timber-surface pixels, 27,804 water pixels, 12,761 amber warning pixels
and 12,189 active red pixels in the fixed 320�200 central probe region. These checks
supplement the inspected captures and physical tests; they do not certify human
readability or GP325 hardware.

The previously documented Windows **`Failed to read the root certificate store`**
startup error still occurs before test loggers attach. It is excluded from passing
suite counts; no golden output was edited to accommodate it. Benchmark shutdown
resource warnings found during tool development were resolved by retaining the
preloaded scene resource; the final runs have no such warnings.

Exact commands from `C:/Users/raysh/Development/Dungeon15-15-depths`:

```powershell
$godot = 'C:/Users/raysh/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe'
$env:APPDATA = Join-Path $PWD '.godot/m1_appdata'
New-Item -ItemType Directory -Force $env:APPDATA | Out-Null
& $godot --headless --path . --import
& $godot --headless --path . --script res://tools/first_dungeon_audit.gd
& $godot --headless --fixed-fps 60 --path . --script res://tools/first_dungeon_test.gd
& $godot --headless --fixed-fps 60 --path . --script res://tools/first_dungeon_hazard_test.gd
# Actual rendering: omit --headless.
& $godot --path . --script res://tools/first_dungeon_visual_test.gd
& $godot --headless --fixed-fps 60 --path . --script res://tools/prototype_3d_test.gd
& $godot --headless --fixed-fps 60 --path . --script res://tools/abyss_input_test.gd
& $godot --headless --fixed-fps 60 --path . --script res://tools/smoke_test.gd
& $godot --headless --fixed-fps 60 --path . --script res://tools/generation_stress.gd -- --quick
& $godot --headless --path . res://src/game_3d/hazard_validation.tscn --quit-after 120
# Run benchmarks sequentially, with regression processes finished.
& $godot --path . --script res://tools/first_dungeon_benchmark.gd -- --before
& $godot --path . --script res://tools/first_dungeon_benchmark.gd
# Interactive fixture:
& $godot --path . res://src/game_3d/hazard_validation.tscn
git diff --check
git diff --quiet -- src data project.godot
```

`--before` loads the M1 scene/script snapshot captured before editing, in the ignored
`.godot/m11_baseline/` directory in this worktree. It fails explicitly if that
session snapshot is absent; a fresh clone cannot reconstruct this previously
uncommitted M1 baseline from Git. The default benchmark always runs current M1.1.
Logs/JSON measurements and captures are ignored `.godot/m11_*` artifacts. The
layout audit is deliberately persisted in `docs/M1_LAYOUT_AUDIT.json` and is
regenerated deterministically by the audit command. `git diff --quiet -- src data
project.godot` returned 0: all original tracked runtime files remain unchanged;
new M1/M1.1 runtime files are untracked additions. Whitespace checks also passed.


## M1.1 changed files and limits

Modified `first_dungeon.gd` (presentation hook/materials/UI), `gamepad_input.gd`
(exposed processed pad vector), `first_dungeon_benchmark.gd` (repeatable measurements),
this report and the current status note in `DEVELOPMENT.md`. Added:

- `src/game_3d/environment_details.gd`, `stone.gdshader`, `water.gdshader`.
- `src/game_3d/hazard_fixture_data.gd`, `hazard_validation.gd`, `hazard_validation.tscn`.
- `tools/first_dungeon_audit.gd`, `first_dungeon_hazard_test.gd`,
  `first_dungeon_visual_test.gd`, their Godot UID sidecars and `M1_LAYOUT_AUDIT.json`.

The existing M1 work was already uncommitted when this pass began, on
`feature/conventional-15-depths` at `b3b2432`; it was preserved. Original 2D code,
main scene configuration, generation/profile data, golden outputs, P1A and Abyss
sources remain unchanged. No enemies, combat, rewards, streaming or moving-castle
systems were added. M1.1 visual/hazard acceptance and physical GP325 acceptance
remain manual. Stop here pending approval for any M2 work.

---


# M1 baseline implementation and measurements (historical)

M1 implements one static, generated 3D graybox floor. See the M1.1 status above for
subsequent owner keyboard/presentation acceptance and pending GP325 acceptance. Stop at M1; no automatic commits or pushes.

## Run and accept

Open `src/game_3d/first_dungeon.tscn` in Godot **4.7.2** and press **F6**.
F5 still runs `src/main/main.tscn`. Default seed: 12345. Set `Run Seed` on the
scene root to 42 or 7 and repeat F6, or use the console commands below.

1. Confirm the depth/seed overlay, cyan entrance ring, blue capsule and gold
   facing marker. Use WASD and arrows in all eight directions. Release must stop
   movement; diagonals must retain cardinal speed. Walk against walls and slide
   along them; the fixed isometric camera should follow without rotating.
2. Explore rooms and corridors through gold door thresholds. Gray walls,
   pillars, inner walls and brown rubble must block movement. Find the green
   EXIT ring/label. Enter it: the overlay reports completion and stays on depth 1.
   Press R to return to entry. No next depth is loaded.
3. Cross brown spike tiles during the brown safe phase or amber warning. Tips
   rise during warning; red raised spikes return the player to entry. Wait on
   gray ground for the next safe phase. The safe phase is at least 4 seconds,
   warning 0.6 seconds, raised 0.5 seconds. Water is blue and halves speed.
4. Repeat for seeds **12345, 42, 7**. Their preserved depth-1 layouts contain
   spikes (12345, 42) and water (7), but no pits or bridges. The isolated automated
   terrain fixture covers actual pit falls and bridge traversal; runtime code
   also handles these tile kinds without substituting ground for pits.
5. Connect a GP325, focus the window and confirm the overlay selects its Godot
   device ID. Test left-stick directions, partial deflection, diagonals, release,
   resting drift, and all four D-pad directions. Repeat wall sliding and a
   spike crossing. Unplug while moving: movement must stop and keyboard must
   continue working. Reconnect and verify controller movement returns.
6. If the GP325 reports different indices, inspect the overlay's latest event
   and configure **ControllerInput** in this scene: horizontal/vertical axes,
   inversion, D-pad buttons or optional hat axes, deadzone and preferred device.
   These are scene settings; do not edit global project input or driver mappings.
   Repeat the full GP325 procedure after any adjustment.

Synthetic events do **not** accept USB detection, driver mode, physical labels,
resting drift, hot-plug behavior or controller feel on real GP325 hardware.
No physical controller was available in the automated run (device ID -1).

## Implementation and scope

The unchanged generator v5 creates a validated depth-1 layout. M1 refuses failed
generation or an empty cardinal entrance-to-exit route. The generator still
produces legacy content metadata for determinism; M1 never instantiates enemies,
combat, rewards, event sockets or authored content scenes.

`grid_space.gd` is the sole coordinate boundary: one tile = 2 metres, X/Z are grid
X/Y, floor surface Y = 0. Its pixel conversion is explicitly tested against
`DungeonLayout.tile_center`; no pixel navigation receives metre coordinates.

Identical tile kinds are greedily merged into static rectangles, retaining their
kind and footprint. Walkable terrain has a surface at Y=0; all solid kinds are
1 metre high. PIT has only a dark visual bottom at Y=-2.5, **no collider**. VOID
has neither. Falling below Y=-3 returns the capsule to entry. Bridges have real
floor collision. Water has support and half speed. Spikes have support, coloured
telegraphs, batched cone tips, and a raised-phase entry reset (no health system).
Terrain effects sample the player's foot-centre tile each physics tick.

The unchanged P1A capsule/controller and fixed camera provide movement and follow.
`player.gd` only overrides input sourcing. `gamepad_input.gd` is a frozen copy of
the accepted scene-owned GP325 adapter, with M1 action/log names; it creates and
removes private actions and preserves shared move bindings. M1 has no runtime
reference to `src/abyss/`. Future controller fixes should reconcile both adapters
or extract an explicitly shared module after approval.

Spike timing is intentionally scaled from the old 2D timer: its 1.4-second safe
window assumed 230 px/s. The 3D safe window covers the eight-tile validated region
limit at 5 m/s, and grows if this floor's selected route has a longer consecutive
hazard run. All traps share one clock in M1. There is no damage or combat system.

## Changed files

- Created `src/game_3d/first_dungeon.tscn`, `first_dungeon.gd`: independent scene,
  generation, route gate, merged geometry/collision, markers, terrain rules and UI.
- Created `src/game_3d/grid_space.gd`, `player.gd`, `gamepad_input.gd`: coordinates,
  inherited P1A movement, scene-owned controller integration; Godot `.uid` sidecars.
- Created `tools/first_dungeon_test.gd`, `tools/first_dungeon_benchmark.gd`:
  automated acceptance and reproducible render measurement/capture.
- Created this report; updated only the current-direction heading in
  `DEVELOPMENT.md`, leaving its old progress history archived below it.

`project.godot`, legacy game, generator, profiles, golden fingerprints, P1A and
Abyss source files remain unchanged. Initial worktree was clean, branch was
`feature/conventional-15-depths`, HEAD was `b3b2432`. All work stayed in this worktree.

## Exact validation commands

From `C:/Users/raysh/Development/Dungeon15-15-depths` in PowerShell:

```powershell
$godot = 'C:/Users/raysh/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe'
$env:APPDATA = Join-Path $PWD '.godot/m1_appdata'
New-Item -ItemType Directory -Force $env:APPDATA | Out-Null
& $godot --headless --path . --import
& $godot --headless --fixed-fps 60 --path . --script res://tools/first_dungeon_test.gd
& $godot --headless --fixed-fps 60 --path . --script res://tools/prototype_3d_test.gd
& $godot --headless --fixed-fps 60 --path . --script res://tools/abyss_input_test.gd
& $godot --headless --fixed-fps 60 --path . --script res://tools/smoke_test.gd
& $godot --headless --fixed-fps 60 --path . --script res://tools/generation_stress.gd -- --quick
& $godot --headless --path . res://src/game_3d/first_dungeon.tscn --quit-after 120
& $godot --path . --script res://tools/first_dungeon_benchmark.gd
# Interactive alternate seeds:
& $godot --path . res://src/game_3d/first_dungeon.tscn -- --seed=42
& $godot --path . res://src/game_3d/first_dungeon.tscn -- --seed=7
git diff --check
```

Evidence logs and rendered captures live in ignored `.godot/m1*` files.
The benchmark warms up for 120 rendered frames, samples 600 entry-view frames,
then captures the spike view. It does not disable VSync or modify project settings.

The M1 suite tests exact rectangle coverage, physical ray height/support at every
tile, deterministic repeats, unchanged baseline fingerprints, full cardinal
capsule traversal with water slowdown and waiting for timed spikes, exit arrival,
water/spike rules, isolated bridge/pit/wall physics, synthetic stick/D-pad input,
keyboard movement, shared-binding preservation, private-action teardown, no node
growth over 300 physics frames per seed, and no orphan-node increase after teardown.

## Results and measurements

Godot 4.7.2 import completed and standalone scene boot/render exited 0.
Final M1 suite: **61 checks, 0 failures, 6.1 seconds**, exit 0.
Existing suites: **P1A 43**, **controller 50**, **smoke 378**,
**quick generation stress 337** checks; all passed (869 checks total).
Stress took 326.4 seconds and included the unchanged six golden fingerprints.
`git diff --check` passed. No golden outputs were edited.

| Depth-1 seed | Fingerprint | Generation + complete scene build | Merged rectangles | SceneTree nodes including harness |
| --- | --- | ---: | ---: | ---: |
| 12345 | `2994f8107a89ee44` | 277.61 ms | 404 | 827 |
| 42 | `31476b85897e6431` | 171.95 ms | 382 | 783 |
| 7 | `21ae2fd9691ea505` | 146.14 ms | 278 | 575 |

Cardinal routes contain 229, 228 and 181 tiles respectively. All three were
physically traversed with the real capsule and collision, water slowdown and
spike timing active, with zero resets. The harness feeds waypoint velocity through
`move_and_slide`; separate tests feed keyboard/controller input. Repeated teardown
left no additional orphan nodes. Node counts remained constant over each 300-frame
steady-state check. Headless test-process static-memory peak: 49,522,118 bytes
(47.2 MiB); the final reported physics samples were 1.45-2.04 ms. Headless fixed-FPS
runs are accelerated correctness tests, not interactive framerate benchmarks.

Standalone rendered benchmark, seed 12345, 1152x648, Compatibility/OpenGL on
AMD Radeon(TM) Graphics, unchanged VSync/project settings, no concurrent regression
suite: build **284.04 ms**; reported **31 FPS**; process-frame p50 **33.224 ms**,
p95 **74.059 ms**; physics sample **0.789 ms**; **69 draw calls** at entry.
Godot tracked static-memory peak during the entry sample: **61,650,272 bytes
(58.8 MiB)**. Windows `Get-Process '*Godot*' | Select-Object
Id,ProcessName,CPU,WorkingSet64,PeakWorkingSet64` sampled the renderer process's
peak working set as **307,236,864 bytes (293.0 MiB)** during that run; this is a
sampled process high-water mark, not a complete-session GPU-memory measurement.
Node count stayed **827 -> 827** across 600 rendered frames. Entry and raised-spike
captures were visually inspected. These are measurements of this environment,
not a 60-FPS acceptance claim; pacing and sustained traversal need manual review.

Every invocation emitted the already documented Windows startup error
`Failed to read the root certificate store`, before suite logging starts. Import
and scene boot still succeeded. No script errors, suite-time engine errors or
warnings, exit leak warnings, or unbounded node growth were observed. The startup
certificate error is not included in the passing suite counts.

Limitations: graybox capsule rather than samurai art; low static walls; synchronous
floor build; global synchronized trap clock; centre-tile terrain sampling; entrance
resets rather than death/health; exit completion is an overlay state; the pit/bridge
behaviors use isolated test data because the preserved depth-1 samples
lack those tiles. Real controller acceptance, interactive feel and long-session
performance remain manual. No campaign, enemies or combat were implemented.

## Next milestone dependencies

Manual M1 keyboard, presentation and GP325 acceptance comes first. Further work
requires explicit approval. Future milestones need a defined combat/controller
contract, samurai/enemy grayboxes, encounter integration, rewards and upgrade
rules, guardian/final-boss progression and authored profiles/balance for exactly
15 depths. None of those systems were added here. Existing legacy profiles for
other depths are regression inputs, not new campaign implementation.
