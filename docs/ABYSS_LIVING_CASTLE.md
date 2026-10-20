# Stage 5B: the Living Castle

Manual acceptance pending. A separate graybox demonstration of an unseen Castle
Master's rule-based influence, not a demon character, combat system or unrestricted
world-changing AI. Original identity comes from suspended tiers, an inhabited void,
muted violet background structures and legible, deliberate route changes; no
copyrighted castle design, character, animation or story assets are used.

The earlier event-driven gameplay rule remains: route changes require explicit
zone/script/milestone events and predefined safe states. Stage 5B separately
authorizes periodic **decorative** movement. It cannot change collision or
navigation. That distinction allows a visibly active castle while the player
stands still without constantly forcing new gameplay-route animations.

## Source and preservation

New files:

| File | Responsibility |
|---|---|
| `src/abyss/castle_director.gd` | Pure-data event rules, stable IDs, cooldown, warning and bounded history |
| `src/abyss/living_streamer.gd` | Safe route state machine, occupancy/reachability checks, stream restoration |
| `src/abyss/director_bridge.gd` | Stage 5A bridge pose/sweep/mesh reuse without its manual pedestal |
| `src/abyss/ambient_architecture.gd` | Fixed-budget collision-free architectural motion |
| `src/abyss/living_demo.gd/.tscn` | Playable scene and warning/status UI |
| `tools/abyss_living_test.gd` | Focused scheduler, safety, traversal and streaming tests |

New GDScript files have associated `.uid` files. Existing runtime source is not
edited in Stage 5B. The Stage 5A files and its previously uncommitted hooks in
`chunk_streamer.gd` are preserved. At inspection the latest Git checkpoint was
`b3b2432` (Stage 4), with Stage 5A work already in the working tree; no commit or
history change was performed. Stage 5A remains `mechanism_demo.tscn`, Stage 4
remains `streaming_demo.tscn`, and the original main scene is unchanged.

## Castle Director and Castle Master rules

The Director's state dictionary lives in the streamer's `world_state`, keyed by
`<home chunk ID>:castle-director:v1`. It stores simulation/ambient clocks, stable
route state, bridge pose, one active event with phase, cooldown/release deadlines,
zone/milestone flags and event identities. IDs are hashes of a separate versioned
namespace, world identity and one of three fixed event keys. The saved dictionary
contains no scene instances.

Rules and defaults:

1. With home/east/south collision ready and the player within 1.15 cells of home,
   three seconds of active-zone time trigger `threshold`: redirect the east route.
2. Every route event first warns for three seconds. Occupancy may defer the change
   indefinitely; a warning does not remove existing support.
3. Redirection lasts eighteen seconds of active-zone time, then `release` requests
   restoration. Reaching the Wayfinder center also requests restoration, subject
   to the six-second cooldown, and records the `wayfinder` milestone.
4. That milestone raises decorative motion intensity from 1.0 to 1.5. It does not
   produce another uncontrolled route shift.
5. `threshold` and `release` each run once per session. The scene then settles
   with continuing ambient motion. There is no endless route-animation loop.

The public scripted entry point is `director.request("threshold", "redirected")`
or `director.request("release", "direct")`. Other keys/target combinations are
rejected. Requests cannot bypass cooldowns, deduplication or the single-active
event limit. The geometry controller still performs safety checks after a request.
Scripted threshold requests consume the proximity trigger too, so a later zone
check cannot duplicate the event or suppress its timed restoration.

Streamer Inspector exports configure zone radius, trigger/warning/cooldown/hold
times and movement duration (two seconds by default). Change startup settings
before running. For the same world/configuration, timestep sequence and player
facts, schedules and identities are deterministic. Different player movement can
legitimately defer an event; wall-clock timing is not promised to be identical.

There is no demon actor or AI implementation. The Castle Master is represented
by these explicit rules and warned status messages. The player remains the
validated capsule stand-in for the planned lone samurai.

## Playable connection states and safety

The east bridge links `(0,0)` to `(1,0)`. A southern entrance links `(0,0)` to
`(0,1)`; the detour continues through `(1,1)` to the Wayfinder chamber `(1,0)`.

| State | East bridge | Southern entrance |
|---|---|---|
| Direct, initial/final | Raised, collidable and open | Floor remains; visible gate blocks entry |
| Redirected | Lowered, collision disabled, endpoints gated | Open onto the static detour |
| Restoring handover | Raised/collider-ready and open | Remains open until clear |

All 289 default-world chunks remain logically reachable in direct, redirected
and both-open modes. Before any committed change, a bounded graph search checks
reachability across the finite grid. The whole streaming catalog is not rebuilt.

The runtime phases are warning, waiting for a clear sweep, gating, moving,
settling and handover. Closing the east bridge checks the swept volume, including
approach clearance, against player layer 2. Both endpoint gates must actually
exist and settle for two physics ticks before deck collision is disabled. A new
occupant defers movement; a player already standing on the bridge keeps its
unchanged visible collision until they leave. The southern path opens before
the east bridge withdraws.

During movement, the deck is non-colliding behind closed gates. Restoring it waits
two physics ticks at the exact final pose before opening its endpoints. Both
routes then remain open while any player occupies the southern entrance/bridge.
Only after that volume clears can the southern gate close. Its floor is never
removed. No actor is teleported, carried, crushed or forced to wait on unsupported
geometry. Occupancy checks support the current layer-2 capsule contract, not
arbitrary future actor types.

## Ambient movement and streaming

Twelve decorative structures contain twenty-four mesh instances sharing one box
mesh/material. Towers turn, suspended tiers rise/fall and bridge/panel-like slabs
rotate through controlled seeded phases. There are no bodies, collision shapes,
navigation nodes or gameplay connections in this branch. Transform updates run
at most 20 Hz over this fixed set; the scene can have twelve decorative moving
targets plus at most one gameplay transformation, never an unbounded simulation.

The decorative ring follows the current streamed cell and stays below the local
play plane. It is a finite background illusion, not persistent world geometry or
a complete distant-architecture LOD system. Reanchoring at cell changes can pop;
this is a documented graybox limitation.

The Director pauses its gameplay clock and bridge pose updates when the affected
chunks are not collider-ready or the player is outside the configured zone.
The ambient clock continues. Chunk eviction destroys the route visual but keeps
its saved pose, phase and event IDs. A reload reconstructs that pose/collision
state and reobserves stream/gate readiness before resuming. Active shifts are
tested through eviction as well as completed-state visits. No distant unloaded
gameplay structure is animated or reconstructed each frame.

Residency remains 9 chunks by default, up to the existing configurable 25 cap.
The special bridge replaces the normal three-box connector with three boxes;
there is no new gameplay geometry count beyond that replacement and existing
gates. One Director record adds to the bounded visited-state store (290 records
maximum with default world extent). Events have at most three recorded keys and
one active dictionary, with no unbounded scheduling queue. All persistence is
in-memory session state; restarting the scene resets it. No disk saves are added.

## Exact manual acceptance

1. Open **`src/abyss/living_demo.tscn`** in Godot 4.7.2 and press **F6**.
   F5 still starts the original 2D game. Use WASD/arrows or GP325 left stick/D-pad.
   **F3** hides/shows controller diagnostics; **R** retains streaming retry behavior.
2. Stand at the start. Observe several dark-violet structures moving below and
   around the gray playable platforms. The east bridge starts open, and the
   southern entrance has a visible orange gate.
3. After about three seconds of ready/proximate simulation, read the Castle Master
   warning. After its three-second warning and safe deployment phase, the east
   bridge lowers and its gates close; the southern entrance opens. Nothing needs
   to be manually activated. Occupancy/load delays can extend this timing.
4. Follow **`(0,0) → (0,1) → (1,1) → (1,0)`**, using the chamber labels and physical
   bridge directions. Reach the Wayfinder center. The milestone increases ambient
   intensity and requests the warned restoration. The timer can also restore the
   direct route when nearby; neither path strands the player if already traversing.
5. Return over the raised east bridge once it is restored. For an occupancy check,
   stand on the east bridge during its initial warning: it must wait for you to
   step off. During restoration, standing on the southern passage must keep both
   routes open until you clear it.
6. Leave home through `(-1,0)`, `(-2,0)`, `(-3,0)` and return. Watch unload/build
   counts. The state and recorded event IDs must survive; completed events should
   not replay. If you leave during a shift it pauses/resumes instead of resetting.
7. To inspect state, watch `CASTLE DIRECTOR completed <id> target=...` in Output.
   The Streamer's `state()` returns the persistent Director record. The lower UI
   shows the stable route and active-event cap; streaming diagnostics show loaded
   chunks, jobs and geometry. Try seeds 12345, 42 and 7 by stopping and changing
   **Streamer → World Seed** before restarting.

Console launch:

```text
godot --path . res://src/abyss/living_demo.tscn
```

No physical GP325 was detected during automated tests. Its movement adapter is
unchanged and synthetic input regressions pass, but device mode, drift, hotplug,
real control feel, camera readability and sustained performance need owner checks.
This automatic demo adds no new controller button or face-button assumption.
Stage 5A's E/south/F4 manual mechanism remains in its own preserved scene.

## Executed verification and measurements

Use the P1A README's console executable and workspace APPDATA redirection:

```text
godot --headless --path . --import
godot --headless --fixed-fps 60 --path . --script res://tools/abyss_living_test.gd
godot --headless --fixed-fps 60 --path . --script res://tools/abyss_mechanism_test.gd
godot --headless --fixed-fps 60 --path . --script res://tools/abyss_stream_test.gd
godot --headless --fixed-fps 60 --path . --script res://tools/abyss_spatial_test.gd
godot --headless --fixed-fps 60 --path . --script res://tools/abyss_input_test.gd
godot --headless --fixed-fps 60 --path . --script res://tools/abyss_seed_ui_test.gd
godot --headless --fixed-fps 60 --path . --script res://tools/prototype_3d_test.gd
godot --headless --fixed-fps 60 --path . --script res://tools/abyss_vertical_test.gd
godot --headless --fixed-fps 60 --path . --script res://tools/smoke_test.gd
godot --headless --fixed-fps 60 --path . --script res://tools/generation_stress.gd -- --quick
```

Focused suite: **56 checks, zero failures, 4.5 s**. Covers deterministic schedules,
cooldowns, bounded event history, scripted requests and restoration, stationary
ambient movement, no decorative collision, occupied east bridge, required-route
reachability, real detour/direct capsule traversal with continuous support,
completed and active eviction/reload, no distant gameplay pose updates, and
occupied-detour handover. Test timers are shortened/lengthened for specific
scenarios; the playable defaults remain as documented above.

Regressions: Stage 5A **49**, streaming **43**, spatial **39**, input **50**, seed UI
**34**, P1A **43**, vertical **33**, smoke **378** (27.3 s), quick generator **337**
(312.2 s), all zero failures. All six legacy golden fingerprints are unchanged.

Latest measured travel run: Director update maximum **0.981 ms** (includes bounded
reachability searches at transitions), special bridge assembly **0.138 ms**,
ambient construction **0.253 ms**, ambient transform update maximum **0.065 ms**.
Observed residency: **9 maximum**, **39 builds / 30 unloads**, **149 boxes at
return / 157 peak**, **one chunk job per frame maximum**, **one active gameplay
event maximum**, **12 ambient structures / 24 decorative meshes**. Chunk catalog
generation/construction maxima were **0.55 / 1.20 ms**. These are measured
environment-specific observations, not production budgets. No FPS result is claimed.

Idle, warning, redirected and restored frames were rendered and visually inspected
on AMD Radeon compatibility graphics. The restored capture shortened only the
hold deadline in a scratch scenario; it did not bypass cooldown or safety phases.
Import, original-main and Living Castle scene boots, and `git diff --check` passed.
The existing Windows certificate-store startup error persists before suite logging
and is excluded from passing suite totals. Evidence remains in ignored `.godot/`.
Manual acceptance remains pending. Stop at Stage 5B.
