# Stage 5A: ancient mechanism and deploying bridge

Manual acceptance pending. One event, one predefined bridge deployment. No
combat, enemies, further transformation types or Stage 5B work.

## Scene and architecture

Open `src/abyss/mechanism_demo.tscn` with F6. This separate scene reuses the Stage
4 catalog, coordinate IDs, scheduling, residency, collision-readiness gates and
visited state. It instances the same player, camera and GP325 movement adapter.
Original Stage 3/4 demos, 2D main scene and procedural generators are unchanged.

New source:

| File | Responsibility |
|---|---|
| `mechanism_input.gd` | Scene-owned E/south-button action; mapping capture and cleanup |
| `deploying_bridge.gd` | Gold mechanism pedestal, bridge visual/collision assembly, fixed poses and sweep bounds |
| `mechanism_streamer.gd` | Event/state, proximity, occupancy, deployment, collision commit and chunk restoration |
| `mechanism_demo.gd/.tscn` | Playable acceptance scene, prompt and input connection |
| `tools/abyss_mechanism_test.gd` | Focused input, safety, persistence and traversal tests |

Associated GDScript `.uid` files are included. The only shared runtime modification
is four small overridable hooks in `chunk_streamer.gd`: selected links, edge-open
policy, chunk-loaded notification and chunk-unloading notification. Defaults
preserve Stage 4 behavior. No catalog, spatial composer, validator, movement,
camera, project actions or generator fingerprints were changed.

The home chunk is `(0,0)`; the destination is `(1,0)`. The specialized streamer
withholds normal geometry for the destination's links. Its sole runtime entrance
is the deploying bridge from home; all other entrances remain gated. This avoids
an alternate grid route bypassing the mechanism. Before activation, all 288
non-destination default-world chunks remain connected; afterward all 289 connect.
The Wayfinder chamber provides a route-discovery success marker when its center
is reached. This is a test objective, not a full narrative/quest system.

## Event, state and lifecycle

The stable mechanism ID is `<home chunk ID>:mechanism:bridge-east:v1`. It uses the
existing world/seed/config identity; no chunk IDs or deterministic placement rules
change. State lives in the streamer's `world_state[mechanism_id]` dictionary:

```text
activated: bool
completed: bool
progress: float 0..1
destination_reached: bool
```

Only a fresh interaction within the configurable range starts the event. Default
range is 2.4 m from the mechanism's floor position. Activation also requires both
chunks to be collider-ready and the bridge sweep to be unoccupied. Input while
already activated/completed does not restart the event. The prompt confirms
activation, deployment, occupancy pauses and route opening.

The predefined visual states are six metres below the final socket position,
then the exact final validated bridge/ramp pose. A smooth three-second vertical
deployment is the only animated transformation. The whole deck/rail body has
collision layer zero while moving; both endpoint gates remain closed. A physics
query checks the complete swept volume, including clearance, against player
layer 2. An occupied sweep rejects activation or pauses an ongoing deployment.
No player position is altered by this system; no moving collidable body carries
or crushes the player. The moving volume is not traversable while deployment waits.

At the final pose, another clear-volume check permits layer-1 collision. Gates
wait two further physics ticks before `completed` is committed. Existing streamer
readiness checks also apply. The bridge then remains fixed and bidirectional.
No retraction, rotation, alternate random destination or physics-driven motion
is implemented. The supported actor is the existing capsule on layer 2; future
actor layers and occupancy shapes require explicit additional validation.

The owner chunk contains the visual assembly. Eviction frees it, while its state
record remains. A completed reload restores the final pose/collision and observes
normal chunk readiness before opening gates. An in-progress unload retains its
progress and pauses animation work until the chunk returns; it never resets or
creates a second activation. The root input adapter stays alive across eviction.
State is session-only, like Stage 4 visited state: stopping/restarting the scene
starts a fresh run. No disk save system is claimed.

## Controller mapping and interaction

Keyboard E always uses the scene-owned action. For a device recognized by Godot,
the controller binding uses the engine's logical south face button
(`JOY_BUTTON_A`), not a physical Xbox label/number. Unknown mappings receive no
assumed face-button binding. F4 captures the actual selected device's next button
event, records its reported index under the device GUID, and requires release
then a fresh press before interaction. This capture overrides the default even
on recognized devices, allowing the owner to verify the physical south button.
The mapping survives chunk eviction and device rebind within this scene session.

References: [Godot's known-controller mapping contract](https://docs.godotengine.org/en/latest/classes/class_input.html#class-input-method-is-joy-known)
and [logical south button definition](https://docs.godotengine.org/en/4.6/classes/class_%40globalscope.html#enum-globalscope-joybutton).
Synthetic tests verify this policy; they are not physical GP325 verification.

## Exact manual acceptance steps

1. Open `src/abyss/mechanism_demo.tscn` in Godot 4.7.2 and press **F6**. F5 still
   starts the original 2D game. Wait for initial chunks/collision to become ready.
2. From home `(0,0)`, find the **gold pedestal** beside the visibly lowered east
   bridge. Camera-relative world +X is generally S+D with the current camera;
   use the visible bridge direction rather than forcing a cardinal screen key.
   Approach beside the pedestal. The lower-screen interaction prompt appears
   within 2.4 m. Outside that range, E must not activate it.
3. For keyboard acceptance, press **E** once. Confirm the success prompt and
   visible upward movement. Repeated presses must not restart the bridge. Endpoint
   barriers should prevent crossing while it moves. If you hug its deployment
   area and it pauses, step back to the pedestal approach and let it resume.
4. Wait for **Bridge secured**. Cross the now-open bridge into `(1,0)`, approach
   the Wayfinder chamber's center and confirm **new route discovered**. Return
   across the same bridge. Other destination entrances remain closed by design.
5. To force real eviction, travel through home to `(-1,0)`, `(-2,0)` and `(-3,0)`.
   Watch builds/unloads increase, then return through `(-2,0)`, `(-1,0)`, `(0,0)`.
   The bridge must already be deployed and traversable. Reapproaching/pressing E
   must not repeat the animation. Resident chunks remain capped at nine by default.
6. To inspect state, watch the Godot **Output** panel for `ABYSS mechanism activated`,
   `completed` and `restored`. These lines include the stable mechanism ID and
   state dictionary. In the running **Remote** tree, the Streamer script owns
   `world_state`; `state()` returns the mechanism record. `progress=1` and
   `completed=true` should survive owner-chunk eviction. Look for restoration
   output only after the origin has actually unloaded, not merely left view.
7. For GP325 acceptance, start a fresh scene so the mechanism is unactivated.
   Connect the controller and use **F3** diagnostics to confirm its name/device ID
   and detected events. If multiple controllers are present, set MovementInput's
   Preferred Device before starting. **Press F4**, press the physical bottom/south
   face button once, release it, and verify the reported Godot button index.
   Approach the mechanism and press that same button again. Repeat the crossing
   and eviction checks. Test disconnect/reconnect and recapture with F4 if the
   device/mode/mapping changes. The capture itself must not activate anything.

Console launch:

```text
godot --path . res://src/abyss/mechanism_demo.tscn
```

Use the installed Godot 4.7.2 console executable. World Seed/stream settings and
interaction range/duration are on **Streamer**; change startup settings only after
stopping the scene. Current tests/manual instructions use default seed 12345.

## Executed tests and performance

Using workspace APPDATA redirection from the P1A README:

```text
godot --headless --path . --import
godot --headless --fixed-fps 60 --path . --script res://tools/abyss_mechanism_test.gd
godot --headless --fixed-fps 60 --path . --script res://tools/abyss_stream_test.gd
godot --headless --fixed-fps 60 --path . --script res://tools/abyss_input_test.gd
godot --headless --fixed-fps 60 --path . --script res://tools/abyss_spatial_test.gd
godot --headless --fixed-fps 60 --path . --script res://tools/abyss_seed_ui_test.gd
godot --headless --fixed-fps 60 --path . --script res://tools/prototype_3d_test.gd
godot --headless --fixed-fps 60 --path . --script res://tools/abyss_vertical_test.gd
godot --headless --fixed-fps 60 --path . --script res://tools/smoke_test.gd
godot --headless --fixed-fps 60 --path . --script res://tools/generation_stress.gd -- --quick
```

Final mechanism suite: **49 checks, zero failures, 2.9 s**. It covers logical E
and south-button/capture input, selected-device filtering, range/prompt, physical
closed gate, single activation, sweep occupancy rejection/pause, final collision
and route safety, real capsule traversal, destination objective, completed and
in-progress eviction/restoration, and independent-run deterministic final pose.
The occupancy test deliberately injects a player into the sweep while disabling
its physics to inspect the pause; production code never teleports the player.

Regression results: streaming **43**, input **50**, spatial **39**, seed UI **34**,
P1A **43**, vertical **33**, smoke **378** (34.5 s), quick generator **337**
(343.6 s), all zero failures. All six legacy golden fingerprints remain unchanged.

Latest measured mechanism travel: **9 resident chunks maximum**, **143 boxes at
return**, **156 peak boxes**, **39 builds / 30 unloads**, **one chunk job per frame
maximum**. Worst measured active transition update: **0.106 ms**; mechanism/bridge
assembly on owner-chunk construction: **0.298 ms**. Base chunk generation and
construction maxima were **0.70 ms / 0.90 ms**; base construction timing excludes
the separately reported mechanism assembly hook. These are environment-specific
observations, not fixed hardware budgets or FPS results. No FPS benchmark was run.
The assembly adds four boxes only while its owner is resident. Session state adds
one mechanism record to the bounded Stage 4 store. The default conservative box
bound becomes 175; the tested peak was 156. Streaming limits/IDs remain unchanged.

Before/during/after frames were rendered and visually inspected on AMD Radeon
compatibility graphics. No physical pads were detected during automated runs.
GP325 button position, actual device mode, feel, camera readability, hotplug and
manual acceptance remain owner checks. The existing Windows certificate-store
startup error persists before suite logging and is excluded from passing totals.
Evidence stays in ignored `.godot/`. This is one graybox mechanism and a
route-discovery destination, not a full clue system, save system or moving castle.
Stop at Stage 5A for owner acceptance.
