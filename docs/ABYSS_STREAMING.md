# Stage 4: bounded deterministic chunk streaming

Manual acceptance pending. Stage 3, fixed vertical demo, P1A and original 2D
main scene remain available. No combat, enemies, moving rooms or Stage 5 systems.

## Architecture and limits

`stream_config.gd` defines startup settings. Defaults: world coordinates from
(-8,-8) through (8,8), 36 m cell spacing, seeded 10–16 m chambers, three possible
levels separated by 4 m, a 3x3 resident window and one chunk job per render frame.
Load radius 1–2 supports 9–25 resident chunks; jobs per frame is restricted to 1–2.
World radius 2–16 bounds the world to 25–1,089 possible cells. The default 289-cell
world is about 600 m across; detailed geometry is not generated upfront.

`chunk_catalog.gd` is stateless logical generation. Chunk IDs include the seed,
geometry settings, world extent, version and integer XZ coordinate. Connection
IDs use an ordered endpoint pair, so both neighbours agree on identity. Seed and
coordinate determine room size and absolute position regardless of visit/load
order. A triangular elevation field along X limits adjacent height differences
to one level; Z connections are level bridges. This is a deliberately constrained
streaming test world, not a mathematically infinite world.

Each chunk is one chamber, plus its east/south connectors. West/north chunks own
incoming connectors. Every connector is generated exactly once. To validate a
chunk, the catalog composes a small logical star containing the central chamber
and existing cardinal neighbours, using the Stage 3 `AbyssSpatialLayout` schema
and validator. Neighbour sockets are independently reconstructible; no neighbour
cache is needed. Boundary cells omit outside links, leaving closed perimeter walls.

This reuses Stage 3 validation and geometry, not its whole-dungeon composition
algorithm. The accepted graph/pacing composer and generated demo are unchanged.
The streaming world currently uses a connected cardinal grid rather than Stage
3's branching dungeon graph. It is a distinct versioned `abyss-stream|v1` world.
It does not claim to stream an arbitrary existing Stage 3 layout unchanged.

`spatial_geometry.gd` adds optional room/link filters after full validation, with
selected-ID validation before node construction. With default arguments it still
builds the entire Stage 3 layout. Streaming builds only the chamber and its owned
connectors; logical neighbour rooms never receive duplicate geometry. All prior
Stage 3 fingerprints and demos retain their behavior.

`chunk_streamer.gd` owns a bounded dictionary of logical data plus scene geometry
for resident chunks. Pending collider-ready chunks count toward the same cap.
It schedules the nearest missing chunk first; coordinate tie-breaks do not depend
on dictionary order. There is no unbounded asynchronous task queue or historical
geometry cache. Completed distant chunks and their logical neighbourhoods are
freed when outside the player's resident window. Unload work is also bounded by
the maximum resident count. One job builds one small whole chunk on the main
thread: the work cap counts jobs, not milliseconds, and a slow driver could still
cause a frame spike. No expensive world-wide rebuilding runs each frame.

Visited state is separate from geometry: one small `{visited, schema}` record
per visited coordinate, at most 289 by default or 1,089 at maximum world extent.
On revisit, logical data and meshes are reconstructed; the visited record remains.
No mutable geometry/gameplay state exists yet. This is in-memory session state,
not a disk save system. Geometry is a function of the seed/settings; the current
visited flag intentionally does not change it.

## Boundary safety and recovery

Nearest-cell classification happens in physics ticks. The resident radius is at
least one cell: a player on an inter-chunk connector keeps both endpoint chunks
and the connector owner within the desired window. The capsule radius is much
smaller than the 36 m cell spacing. Normal controller travel cannot reach a
removed floor behind the window. Arbitrary teleports/high-speed controllers and
moving the entire scene transform are not supported by this test contract.

Orange static collision gates close each loaded chamber's doorway whenever its
neighbour is missing or either chunk is awaiting readiness. Newly constructed
collision waits two physics ticks before the doorway is opened. The player is
paused during initial/current-chunk readiness. Gates are removed only when both
endpoint chunks are ready; a connector's owner must be one of those endpoints.
The full connection floor then joins both room-face sockets with intentional
seam overlap. Outer-world walls are permanent, not loading gates.

Load failures retain the gate and retry after a configured frame cooldown, up to
three attempts by default (maximum five). Exhausted attempts stop. **R** explicitly
retries failed nearby loads. Failure records are pruned outside the desired
window. Invalid startup settings disable player physics and show a diagnostic.
There is no seed-changing fallback, dropped collision, or attempt to walk over
failed geometry. A persistent failure can block a doorway until recovery; it
does not silently replace the requested layout.

The initial invalid-settings test found an initialization-order problem: the
player script could register physics after the earlier streamer sibling readied.
The streamer now enforces the disabled state before the player's first physics
callback, and the final failure test passes.

## Play and inspect

1. In Godot 4.7.2, open **`src/abyss/streaming_demo.tscn`** and press **F6**.
   The start briefly waits for collision. F5 still starts the original 2D game.
2. Use WASD/arrows, left stick or D-pad. Movement/camera/GP325 scripts are reused
   unchanged. Follow the physical diagonal of a ramp/bridge. Walk through at
   least three successive chambers, then turn along another connection.
3. Watch the streaming readout: current cell, resident/cap counts, current/peak
   box count, builds/unloads, visited-state count, jobs and worst generation/build
   times. Resident geometry should stabilize near nine chunks, not grow as you
   travel. Detailed neighbourhoods pop in/out beyond that window; distant LOD
   architecture is not implemented.
4. Return to chunk (0,0). Its size, elevation, connectors and position should
   match the original. Builds/unloads should increase, while resident counts stay
   bounded. Test standing on connectors, reversing direction, rail sliding and
   walking at full analog speed. **F3** hides/shows controller diagnostics.
5. Orange gates are loading barriers. Wait rather than trying to pass them.
   If a failure is reported, press **R** to retry. Automated tests inject failures;
   normal play is not deliberately sabotaged. At the finite outer edge, the wall
   remains closed. The streaming scene is an exploration test, with no exit quest.
6. Stop the scene, select **Streamer**, and edit **World Seed** or expand
   **Settings**. Try seeds 12345, 42, 7. For a visible world-edge test use world
   radius 2; for a larger resident window use load radius 2 (25 chunks). Settings
   are startup-only: stop and restart after changing them. Do not edit live
   scheduling/geometry settings in the Remote Inspector during traversal.

Console launch, with the installed Godot console executable:

```text
godot --path . res://src/abyss/streaming_demo.tscn
```

This scene reads the Streamer's Inspector seed; it does not use Stage 3's preset
buttons or `--abyss-seed` argument. The accepted Stage 3 seed-selector demo remains
`src/abyss/generated_demo.tscn` unchanged.

## Executed verification

Use the P1A README's executable and ignored-workspace APPDATA redirection:

```text
godot --headless --path . --import
godot --headless --fixed-fps 60 --path . --script res://tools/abyss_stream_test.gd
godot --headless --fixed-fps 60 --path . --script res://tools/abyss_spatial_test.gd
godot --headless --fixed-fps 60 --path . --script res://tools/abyss_seed_ui_test.gd
godot --headless --fixed-fps 60 --path . --script res://tools/abyss_input_test.gd
godot --headless --fixed-fps 60 --path . --script res://tools/prototype_3d_test.gd
godot --headless --fixed-fps 60 --path . --script res://tools/abyss_vertical_test.gd
godot --headless --fixed-fps 60 --path . --script res://tools/smoke_test.gd
godot --headless --fixed-fps 60 --path . --script res://tools/generation_stress.gd -- --quick
```

Streaming suite: **43 checks, zero failures**. It validates all 289 logical chunk
coordinates, reconstructs them with a second catalog, verifies all adjacent
socket/identity pairs and single-owner connections, checks different seeds,
forces startup and persistent neighbour failures, and verifies retry limits.
Actual capsule physics crosses ten chunk boundaries outbound/return, evicts and
reconstructs the origin, preserves visited state, and checks collision support
throughout. 1,350 ray probes check reconstructed connection widths and seams.
An alternate 25-chunk/two-job configuration exercises negative coordinates,
finite-world corners and permanent boundary collision. Invalid settings fail closed.

Latest measured default travel run: **9 resident chunks maximum**, **39 builds /
30 unloads**, **147 boxes resident at return**, **155 peak boxes**, **one job per
frame maximum**, **0.78 ms worst logical generation** and **1.20 ms worst chunk
construction**. Six visited-state records remained. Process static allocation at
the measurement was 34,404,935 bytes, including the engine and test harness; this
is not a per-chunk/GPU-memory estimate. The conservative default box bound is
171 (nine chunks of at most 15 boxes plus at most four gates each). The maximum
25-chunk configuration has a conservative bound of 475 boxes.

Regression results: spatial **39**, seed UI **34**, input **50**, P1A **43**,
vertical **33**, smoke **378** (26.6 s), quick generator **337** (298.2 s), all
zero failures. All six legacy generator golden fingerprints remain unchanged.
The rendered startup was inspected on AMD Radeon compatibility graphics; an
observed startup showed 9 resident chunks / 147 boxes, 0.61 ms worst generation
and 1.35 ms worst construction. No sustained FPS benchmark was performed.

The existing Windows certificate-store startup error persists before test logging;
it is not counted in passing suite totals. Logs/captures remain in ignored `.godot/`.
Manual feel/camera review, sustained hardware performance and physical GP325
hotplug/analog acceptance remain owner checks. No production performance claim.

## Future event-driven changes

Chunk IDs, shared edge IDs and the versioned state schema provide stable targets
for a future event controller. Such a controller must add explicit progression,
occupancy, swept-collision and reachability checks plus persistence/replay rules.
The current catalog reconstructs static geometry only. It does not shift occupied
rooms, consume narrative events, mutate connections, or apply saved geometry
transformations. Stage 5 remains unimplemented and requires approval.
