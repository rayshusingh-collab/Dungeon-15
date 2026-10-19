# Stage 3: deterministic spatial composition

Stage 3 only. Manual acceptance pending. Streaming and moving architecture are
not implemented. The fixed vertical demo, P1A scene and original main scene stay
available unchanged at protected checkpoint 40a8b25.

## Architecture and generation

`spatial_config.gd` defines a bounded Resource: topology profile, room-size ranges,
cell spacing, 2–5 possible elevation levels, 2–5 m level spacing, 3–4 m connection
width, and a 1–16 attempt limit. Defaults: depth-1 profile, 10–16 m rectangular
chambers, 36 m cells, three possible levels at 4 m intervals, 4 m connections,
eight attempts. A generated layout must actually occupy at least two levels;
it need not use every configured level.

`spatial_composer.gd` reuses the existing `GraphBuilder` and `PacingDirector`.
Entry/main-path/objective/branch/loop identities and pacing roles are retained.
The role/encounter values are metadata only: no combat, terrain hazard, enemy or
loot systems are instantiated. This deliberately consumes the logical graph,
not `DungeonGenerator`'s 2D tile layout. It does not port ASCII interiors or claim
that its rooms reproduce the 2D dungeon's geometry.

RNG is local to `abyss-spatial|v1|seed|attempt|stream`, hashed by existing
`StableHash`. Graph, pacing and spatial streams are separate. No existing RNG
namespace, generator version, profile, template or golden fingerprint is changed.
Identical seed/config/profile/engine version reproduces equivalent graph and
spatial data. `spatial_layout.gd` carries graph IDs, metre-based room bounds,
connection endpoints/width, entry/exit and a stable identity including logical
roles/link kinds. Timing and runtime node IDs are excluded from that identity.

Rooms occupy unique logical grid cells. A seeded triangular level field along
one grid axis makes adjacent cells differ by at most one level; the other axis
gives flat bridges. Seeded rectangular dimensions vary each room. Each adjacent
graph link becomes a direct bridge or ramp between opposing face-center sockets.
Sufficient space is reserved for the steepest allowed transition (rise/run <=
0.35, about 19.3 degrees). Both positive and negative elevations relative to the
entry are supported. Entry is centered at world origin, floor elevation zero.

`spatial_validator.gd` checks finite data, room dimensions, conservative XZ room
separation, graph/connection identity, exact sockets, slope/width, duplicate
doorways, unrelated-room obstruction, nonincident connection crossings, complete
graph reachability and interior spawn/exit support. Intersections are rejected
even when projected objects could pass above each other: stacked overlapping
rooms and crossing bridges are deferred. Graph construction failures and failed
spatial attempts retry up to the configured cap. Invalid configuration fails
before any attempt. Failure returns no usable layout; failed-attempt diagnostics
remain in `Result.errors`, including earlier failures if a later attempt succeeds.

`spatial_geometry.gd` validates again before constructing nodes. It owns one
immutable build and refuses invalid data without partial geometry. Every room
and link has a distinct `Room_<id>` / `Link_<id>` section node, ready for future
ownership work. It does not implement chunk lifecycle. Box meshes are cached by
size and share a gray material. Simple layer-1, mask-2 static collision matches
the validated player. Each ramp has continuous visible/collidable geometry;
rooms have low perimeter walls interrupted only at actual connections. Bridge
and ramp rails prevent stepping into the void. There are no ceilings.

Intentional construction contacts: floor/wall bases, guard joins and 0.06 m total
connector overlap at socket seams. These prevent cracks; they are not unrelated
solid intersections. The validator rejects spatial envelopes that intersect
unrelated sections. Physics probes and capsule walks verify the built surfaces,
rather than treating logical connectivity alone as proof of navigability.

`generated_demo.gd/.tscn` combines the composer and builder with the existing
`abyss_player.gd`, GP325 input adapter, diagnostics and fixed orthographic camera.
It spawns only after successful generation/build, disables movement on failure,
marks chambers/entry/exit and reports reaching the exit center. No movement/input
scripts or project-wide actions were changed in Stage 3.

## Open and play

1. Open `src/abyss/generated_demo.tscn` in Godot 4.7.2; press **F6**.
2. Use WASD, arrows, left stick or D-pad. Movement is screen-relative; follow the
   visible bridge/ramp direction, including diagonals. Explore chambers and find
   the **EXIT** marker. Approach its center to display **EXIT REACHED**. Connections
   are bidirectional, so you can return and explore branches.
3. **F3** hides/shows the reused controller overlay. GP325 hardware calibration
   remains as documented in `ABYSS_CONTROLLER_TEST.md`.
4. Click **Seed: 12345**, **42**, or **7** at the top right to restart the demo at
   the selected seed's entry, clearing exit completion. The current seed's button
   is disabled. This is an explicit demo reset, not an in-world transformation.
   For any other seed, stop the scene, select its root and change **World Seed**,
   then run F6 again.
   Expand the **Spatial Config** resource to edit room ranges, levels, spacing or
   topology profile. Start with seeds **12345**, **42**, **7** for comparison.
   Configuration changes apply at startup; the preset buttons rebuild only on
   explicit selection. There is no per-frame rebuilding.
5. F5 still launches the original 2D main scene. The fixed test remains
   `src/abyss/vertical_demo.tscn`; P1A remains `src/prototype_3d/foundation_3d.tscn`.

Console launch (substitute the installed Godot console executable):

```text
godot --path . res://src/abyss/generated_demo.tscn -- --abyss-seed=42
```

`--abyss-seed=` overrides the Inspector seed at startup. Integer and text seeds
are accepted (text uses StableHash). No override means the saved Inspector seed
is used. In-game preset buttons override the active seed for that session; the
CLI argument is read again on the next scene launch. Buttons do not save changes
to the Inspector or project files.
If settings are incompatible, the on-screen failure explains why and the player
stays disabled; do not increase retry count to hide a configuration error.

## Validation and measurements

Use the P1A README's console path and workspace APPDATA redirection. Commands:

```text
godot --headless --path . --import
godot --headless --fixed-fps 60 --path . --script res://tools/abyss_spatial_test.gd
godot --headless --fixed-fps 60 --path . --script res://tools/abyss_seed_ui_test.gd
godot --headless --fixed-fps 60 --path . --script res://tools/prototype_3d_test.gd
godot --headless --fixed-fps 60 --path . --script res://tools/abyss_vertical_test.gd
godot --headless --fixed-fps 60 --path . --script res://tools/abyss_input_test.gd
godot --headless --fixed-fps 60 --path . --script res://tools/smoke_test.gd
godot --headless --fixed-fps 60 --path . --script res://tools/generation_stress.gd -- --quick
```

Focused evidence: 100 repeated seeds with global RNG disturbances, 100 distinct
topologies and spatial variants, 12 alternate configurations sampled, and an
impossible topology exhausting exactly three retries. Negative mutations cover
room overlap, obstructed links, incorrect socket alignment, excessive slope,
insufficient width, unsafe spawn/exit and disconnected platforms. The builder is
tested for refusal before geometry creation.

Four physical configurations (seeds 12345/42/7 default, 91 with 8–20 by 9–18 m
rooms, five possible levels at 3 m spacing, 40 m cells, 3 m connections) cover
84 bidirectional link traversals, 3,597 support probes and four continuous
camera-relative entry-to-exit walks. Probes sample room floors, connection widths
and socket seams. Each link's guard is tested with the actual capsule. The
existing input suite separately covers synthetic analog/D-pad events; generated
traversal tests drive the same adapter/controller via movement actions.

Final focused run: 39 checks, zero failures, 14.0 seconds. It also verifies
depth-2/depth-3 graph profiles and safe demo failure with movement disabled.
Across 200 default generation calls, worst generation time 1.785 ms; four scene
builds 2.747–3.325 ms. An earlier run under concurrent load observed up to
8.791 ms generation and 5.045 ms construction.
Geometry: 95–120 boxes/static collision bodies (each with mesh and shape),
42–64 cached meshes. Process static allocation at measurement: 32,161,389 bytes,
including engine and test suite, not isolated world/GPU memory. A rendered seed-42
startup measured 1.213 ms generation and 6.961 ms construction. Measurements are
environment-specific diagnostics, not budgets or FPS claims; no FPS benchmark
was performed. All geometry is resident; draw calls are not batched into MultiMesh.

The builder's count is exactly `5 * (rooms + links)` for these rectangular
sections. Config bounds permit at most 64 grid rooms and 112 adjacent links
(880 boxes); the tested layouts use far fewer. This is bounded eager generation,
not an infinite world or a streaming implementation.

Regression results executed for Stage 3: P1A **43 checks**, vertical **33 checks**,
input **50 checks**, smoke **378 checks** (33.4 s), quick generator **337 checks**
(346.3 s), all with zero failures. All six generator golden fingerprints remain
unchanged. Import and rendered entry/exit scene launches passed; entry/exit frames
were inspected on the AMD Radeon compatibility renderer. `git diff --check` passed.

The known Windows `Failed to read the root certificate store` startup error
persists before the suite logger. Passing suite totals exclude that startup error.
Evidence logs and render captures remain in ignored `.godot/`.

## Seed-selection usability verification

The follow-up design/usability task executed the seed UI suite (34 checks),
spatial suite (39 checks, including physical traversal) and input suite (50 checks),
all with zero failures. Inspector exposure/startup selection was verified using
seed 777. The UI suite dispatches mouse press/release events to the actual preset
buttons, verifies old geometry release, supported spawn/reset, unchanged input
actions/camera orientation, and a repeated selection of 12345.

| Selected seed | Layout fingerprint | Chambers | Links |
|---|---|---|---|
| 12345 | `2a981cbd3fcbf8c1` | 10 | 10 |
| 42 | `22a34785a04f9a19` | 11 | 11 |
| 7 | `27838a529221a4f6` | 10 | 9 |

All three layouts validate and differ; returning to 12345 reproduces its identity.
Import and rendered seed-42 launch passed, and the button layout was visually
inspected. `git diff --check` passed. Composer, geometry generation, movement,
camera, GP325 adapter and original 2D systems were not changed by this follow-up.
Manual checks remain: click through the three seeds on the owner's display,
traverse each layout, confirm camera/input feel after resets, and test physical
GP325 hardware. The documented certificate-store startup error persists.

Approved narrative, event-driven transformation contract and October 25 scope
boundary are in [design direction and freeze](SHIFTING_ABYSS_DESIGN.md).

## Limits and acceptance

Manual movement feel, navigation readability and camera review are pending.
GP325 physical hardware is not tested by synthetic event checks. Rooms are open
rectangular grayboxes with ramps, not dressed interiors or authored stairs.
The elevation field and orthogonal grid are deliberately constrained; there are
no stacked rooms, crossing passages, alternate orientation modules or arbitrary
3D routing. Pacing metadata has no gameplay effects. Preset seed changes restart
the whole layout; configuration changes require a new scene run. Failure UI,
seed buttons and exit readout are test-scene behavior only.
No combat, enemies, production art, streaming or shifting mechanisms were added.
Stop at Stage 3 for manual acceptance.
