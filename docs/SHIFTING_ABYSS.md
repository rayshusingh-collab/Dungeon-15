# The Shifting Abyss: Stages 1 and 2

Approved narrative, event-driven transformation rules and the October 25 scope
boundary: [design direction and freeze](SHIFTING_ABYSS_DESIGN.md).

Stage 3 now has a separate generated scene and documented spatial composition:
[Stage 3 implementation and acceptance](ABYSS_SPATIAL_COMPOSITION.md).
Stage 4 now has a separate bounded streaming test scene:
[streaming implementation and acceptance](ABYSS_STREAMING.md).
Stage 5A adds one event-driven bridge mechanism in a separate acceptance scene:
[mechanism implementation and acceptance](ABYSS_MECHANISM.md).
Stage 5B adds a separate bounded Living Castle demonstration:
[Castle Director, safety and acceptance](ABYSS_LIVING_CASTLE.md).
Later stages remain unimplemented and require approval.

Stage 2B adds isolated gamepad input and diagnostics; see
[controller acceptance](ABYSS_CONTROLLER_TEST.md) for current controls and evidence.
The implementation/results below describe the Stage 2 baseline.

## Dependency-ordered plan and compatibility boundary

1. Stage 1: audit the generator, controller, camera and test harness; define a
   separate metre-based route contract and negative validation tests.
2. Stage 2: build a fixed, bounded geometry fixture; prove capsule traversal in
   both directions, endpoint support and edge collision. Manual presentation review.
3. Stage 3 (requires approval): adapt validated logical sections into spatial
   placements, using a separately versioned seed namespace; validate overlaps,
   sockets, clearance and graph reachability before constructing nodes.
4. Stage 4 (requires approval): chunk ownership, load/unload radii, occupancy pins,
   stable state keys, bounded resource accounting and lifecycle tests.
5. Stage 5 (requires approval): predefined connection states, occupancy exclusion,
   reachability validation and atomic collision-safe transitions.
6. Stage 6 (requires approval): materials, lighting and bounded distant silhouettes.
7. Stage 7 (requires approval): combined deterministic/traversal/streaming/shift
   tests and hardware performance acceptance.

The actual `DungeonGenerator.generate(profile, run_seed, depth)` returns a Result
with `ok`, `layout`, attempts, failure log and elapsed milliseconds. Its version
is 5. `DungeonLayout` owns tile kinds, room IDs, graph, corridors, spawn, exit,
markers and fingerprints; `DungeonValidator` validates that logical layout.
`DungeonBuilder` and `DungeonWorld` are 2D consumers, not reusable 3D builders.
The legacy tile size is 32 pixels; it must not be interpreted as metres.
Existing documentation contains older version labels; code and pinned stress
fingerprints are authoritative. No legacy generator files or data are changed.

The Stage 2 fixture does not consume the generator yet: mapping arbitrary 2D
rooms into elevations is deliberately reserved for Stage 3. The new pure-data
`vertical_plan.gd` exposes ordered surface sockets in metres, with finite-value,
alignment, monotonicity and maximum-slope validation. It is a fixed route contract,
not a general spatial validator. Future section adapters must retain logical IDs
and terrain semantics, define entry/exit transforms and keep RNG consumption
independent of the existing `SeedStreams` and golden fingerprints.

Future enemy navigation may consume those sockets and section/link IDs; it must
also validate capsule clearance against constructed collision. Encounter markers
will remain data until an approved 3D gameplay consumer exists. Neither system is
implemented here.

## Stage 2 fixture

`src/abyss/vertical_demo.tscn` instances the unmodified P1A player and camera.
`graybox_builder.gd` builds three open suspended chambers (12 by 12 metres), a
4-metre-wide bridge, two 12-metre-run stairways rising 4 metres each, and perimeter
guards. World collision uses layer 1/mask 2, as in P1A. The 0.35-metre-radius,
1.6-metre-tall capsule fits the openings. No ceilings obstruct the camera.

Stair treads are visual geometry above the void; continuous hidden ramp collision
allows the original controller to ascend without step-up changes. Their slope is
18.43 degrees, below the controller's default 45-degree floor limit. No jump,
teleport, controller rewrite or project input changes are needed. The tread tops
sit slightly below the collision surface; feet can appear slightly above treads.
Mesh resources are cached by box size and share one gray material. Static collision
is constructed once. There is no per-frame rebuilding or unbounded generation.

## Inspect and play

Open `src/abyss/vertical_demo.tscn` in Godot 4.7.2 and press F6.
WASD/arrows retain screen-relative movement. The ascending route runs toward the
screen right; S+D follows world +X for the checked-in camera. Walk from the entry across the first
stairway to the middle chamber, across the bridge and second stairway to the
upper chamber. Return to entry; test rails and room corners on all levels.
Check framing, foot placement and any perceived camera obstruction manually.
F5 still starts the original 2D game; P1A is unchanged.

## Verification commands

Use the console executable and APPDATA redirection from the P1A README. Run:

```text
godot --headless --path . --import
godot --headless --fixed-fps 60 --path . --script res://tools/abyss_vertical_test.gd
godot --headless --fixed-fps 60 --path . --script res://tools/prototype_3d_test.gd
godot --headless --fixed-fps 60 --path . --script res://tools/smoke_test.gd
godot --headless --fixed-fps 60 --path . --script res://tools/generation_stress.gd -- --quick
godot --headless --path . res://src/abyss/vertical_demo.tscn --quit-after 120
```

The suite measures one-time fixture build time, box count, and process static
memory (not per-chunk memory or GPU memory). The provisional fixture cap is 100
boxes. Headless timings are diagnostic only. Interactive frame-time percentiles,
GPU cost and real hardware budgets remain unmeasured and are required before
performance acceptance. Chunk counts/streaming instrumentation belongs to Stage 4.
No infinite-world, seed variation, shifting, combat, navigation mesh, distant
architecture, streaming or production performance claim is made at this stage.

## Executed evidence (2026-10-19)

Stage 1: six route contract checks cover the valid fixture, missing sockets,
excessive slope, reversed/alignment errors and non-finite coordinates. Existing
P1A suite: 43 checks, zero failures. Existing smoke suite: 378 checks, zero
failures (32.7 seconds). Godot import and both the original main scene and new
demo boot exited 0, with no parse/resource failures.
The existing generation stress suite executed with `--quick`: 337 checks, zero
failures (334.6 seconds), including all six unchanged golden fingerprints,
determinism, independent streams, validator negatives and physical traversal.

Stage 2: the new suite passes 33 checks total, including harness checks. Actual
P1A capsule traversal reaches both raised chambers and returns to the entry;
ascent and descent maintain floor support. 165 ray probes confirm the route's
surface height across a 2-metre-wide lane. Stair/bridge railings and both end
walls block the capsule; camera orientation stays fixed. Latest headless fixture
build: 2.023 ms, 80 boxes, seven unique meshes. Process static allocation at the
measurement: 28,626,187 bytes (includes the engine and test suite).

Entry and upper-chamber frames were rendered at 1152 by 648 with the compatibility
renderer on AMD Radeon(TM) Graphics and visually inspected. The player is visible
at both elevations. A one/two-frame capture is not a frame-performance benchmark
or proof of interactive feel. Full manual traversal/camera acceptance is pending.

Godot reports the existing Windows startup error `Failed to read the root
certificate store` before the test logger is installed. The passing suite totals
do not include that startup error. No suite-time warnings/errors occurred in the
completed suites. APPDATA and evidence logs/captures stay in ignored `.godot/`.
