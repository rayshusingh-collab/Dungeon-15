# Dungeon15 scope reset — transition proposal

Status: planning only; awaiting owner approval. No implementation phase started.

## Approved direction and boundaries

Dungeon15 is a 3D isometric dark-fantasy action roguelite: a samurai descends through 15 finite dungeon depths, defeats demons and corrupted creatures, defeats the final boss, and escapes. Shifting Abyss / Living Castle is outside active scope. Earlier documents remain historical evidence; their architecture and milestone authorizations do not govern this proposal. Boss identities and hidden endings are not established here.

This transition makes no gameplay, input, scene, generator, project configuration, index, branch, or history changes. The original 2D main scene remains the configured main scene. Switching the launch scene is a separate future approval, after the new game passes acceptance.

## Repository evidence and preservation

Inspected branch: `3d-development-v2`, tracking `origin/3d-development-v2`; local HEAD `b3b2432` (Stage 4). No staged changes at inspection. Remote freshness was not checked. Earlier checkpoints include `b7bdde0` (Stage 3), `40a8b25` (vertical architecture/controller integration), and `53ef19f` (P1A).

All 30 pre-existing dirty files were copied byte-for-byte into `preservation/scope-reset-20261020-085931/files/`, preserving relative paths. Each copy's SHA-256 was compared with its source. `manifest.json` records paths, sizes, and hashes; `base-commit.txt`, `git-status.txt`, `tracked.patch`, and `index.patch` record the Git context. This is a local recovery snapshot, not an off-device backup or commit. Keep it until a separately authorized durable checkpoint exists. Restore by comparing individual files against the manifest and base commit, then selectively copying/applying into a separate checkout; never bulk overwrite subsequent work.

Uncommitted inventory (30 files; the manifest is exhaustive):

| Group | Files | Attribution |
|---|---|---|
| Modified tracked documentation | `DEVELOPMENT.md`, `docs/SHIFTING_ABYSS.md`, `docs/SHIFTING_ABYSS_DESIGN.md` | Combined 5A/5B status and scope additions; not cleanly separable by whole file |
| Modified tracked runtime | `src/abyss/chunk_streamer.gd` | 5A extension hooks retained by 5B: link ownership, edge policy, load/unload notifications; 22 changed lines (+20/-2) |
| New 5A documentation | `docs/ABYSS_MECHANISM.md` | Mechanism design/evidence |
| New 5A runtime | `src/abyss/mechanism_input.gd`, `deploying_bridge.gd`, `mechanism_streamer.gd`, `mechanism_demo.gd`, `mechanism_demo.tscn` | Four scripts, their four `.gd.uid` companions, one scene |
| New 5A tests | `tools/abyss_mechanism_test.gd` and `.gd.uid` | Safety/input/persistence suite |
| New 5B documentation | `docs/ABYSS_LIVING_CASTLE.md` | Living Castle design/evidence |
| New 5B runtime | `src/abyss/castle_director.gd`, `living_streamer.gd`, `director_bridge.gd`, `ambient_architecture.gd`, `living_demo.gd`, `living_demo.tscn` | Five scripts, their five `.gd.uid` companions, one scene |
| New 5B tests | `tools/abyss_living_test.gd` and `.gd.uid` | Director/route/stream safety suite |

The four tracked files total +53/-3 lines. 5A/5B documentation reports automated success but manual/physical GP325 acceptance pending. This planning audit did not rerun those tests and does not promote them to accepted gameplay.

## Reuse decisions

| Existing asset/system | Decision for active game |
|---|---|
| P1A `src/prototype_3d/player_3d.gd`, player scene, `isometric_camera_3d.gd` | Reuse capsule movement, gravity, collision, facing, camera-relative mapping, orthographic follow. Keep foundation demo as a regression fixture. P1A was owner-accepted; combat is absent. |
| Stage 2B `src/abyss/abyss_player.gd`, `gamepad_input.gd`, `controller_diagnostics.gd` | Reuse through composition/inheritance despite historical folder name. Preserve scene-owned actions, analog magnitude, D-pad, deadzone, configurable device mapping, reconnect and cleanup. Add combat actions later without changing global 2D bindings. Hardware acceptance still required. |
| `src/dungeon/generation/`, `data/rooms/`, `data/depths/` | Reuse the original finite graph → pacing → layout → content → validation/retry pipeline, deterministic streams, templates, roles, spawn intents and threat budgets. Existing profiles are depths 1–3, not a finished 15-depth campaign. |
| `src/core/stable_hash.gd`, seed streams, `run_config.gd` | Reuse seed identity/parsing and depth initialization. Current RunConfig is session seed/depth state, not full run persistence; keep legacy behavior and give the 3D run its own richer state. |
| `src/components/health_component.gd` | Directly reusable Node-based health/invulnerability/signals. |
| 2D hitbox/hurtbox/melee, enemy AI/projectiles, gates/traps/world/HUD | Reuse damage contract, timing, encounter semantics and tuning knowledge. Area2D, CharacterBody2D, raycasts, visuals and Node2D scenes require 3D counterparts; do not claim drop-in reuse. |
| `DungeonNavigation` / AStarGrid2D | Candidate for grid route queries over the unchanged layout, mapping waypoints onto XZ. It is not a 3D steering/collision solution. Verify its world-coordinate assumptions before adoption; use a small adapter rather than a second generator. |
| Later static geometry (`graybox_builder.gd`, `spatial_geometry.gd`) | Reference for box meshes, rails, ramps and collider construction only. Do not import the Abyss graph/streaming stack to obtain mesh helpers. Extract a helper only if it avoids actual duplication. |
| Original smoke, generation stress, P1A and input suites | Retain as regression coverage; supplement with 3D integration checks at relevant milestones. |

## Smallest maintainable architecture

Use one complete, static, mostly planar floor at a time. Map logical tile `(x,y)` to 3D `(x*s, floor_height, y*s)` through one explicit coordinate adapter. Derive `s` from room-lane clearance, capsule size, attack reach and camera visibility in the first floor milestone; do not interpret 32-pixel tiles as 32 metres. Avoid stacked routes and runtime transformations. Descending changes the loaded depth, rather than requiring a physically continuous tower.

Proposed feature folder `src/game_3d/`:

1. A small root scene/controller wires generation, builder, actors, HUD and run-state signals. It owns scene transitions, never combat or generation rules.
2. A 3D floor builder consumes a successful `DungeonLayout`, creates batched static geometry/collision, room triggers, gates, exit and data-selected content. It makes no procedural decisions. Reject invalid layouts before spawn. Pooling/streaming is deferred unless measured performance requires it.
3. A floor runtime owns encounter lifecycle and room completion. A small actor catalog maps existing generation IDs to 3D enemy scenes. Initially retain existing IDs while changing presentation to demons/corruption.
4. A samurai scene extends the accepted movement foundation with separate attack/dodge and 3D hitbox/hurtbox components. Share HealthComponent. Damage remains hitbox → hurtbox → health; visuals remain replaceable.
5. One run-state object stores seed, generator/content versions, depth 1–15, health, chosen upgrades and terminal outcome. Use per-floor room/reward IDs for one-time claims. Save only at safe boundaries initially; no arbitrary mid-combat restore.
6. Profiles/content resources supply enemies, recipes, traps, rewards, theme and boss assignments. Reuse DepthProfile fields; add narrowly scoped 3D campaign data only where fields are missing. No custom script per ordinary depth, service locator, general event bus or plugin framework.

The legacy `DungeonBuilder` stays untouched: it builds TileMapLayer/StaticBody2D and is the correct boundary for a parallel 3D presentation adapter. Retain generator version 5 and golden outputs while only adapting presentation. A future procedural-output change requires an explained version bump and reviewed golden changes. Existing authored `content_scene` values may be Node2D: map their semantic IDs to 3D scenes rather than instantiating them into the 3D world.

## Proposed campaign design

Three thematic bands reuse a compact enemy roster and modular environments. Difficulty increases through combinations, terrain and timing under bounded threat, not routine HP inflation or enemy spam. Target roughly 3–5 meaningful encounters per ordinary depth initially; confirm total run length through playtests before increasing room count.

| Depth | Learning / challenge | Objective |
|---|---|---|
| 1 | Movement, facing, katana, dodge; isolated melee demon | Small objective encounter, descend |
| 2 | Ranged corruption, line of sight, cover | Melee/ranged pair |
| 3 | Warned spikes introduced in safety before mixed pressure | First elite encounter |
| 4 | Armored brute openings and flanking; optional risk reward | Bounded mixed encounter |
| 5 | Test first-band fundamentals | First guardian boss |
| 6 | Water/slow terrain; new enemy behavior taught alone | Mixed encounter |
| 7 | Safe-edged pits and static bridges; no unavoidable fall | Terrain encounter |
| 8 | Ranged lanes plus melee pressure with a clear escape lane | Elite encounter |
| 9 | Build choices tested by optional hard branches | Pre-guardian objective |
| 10 | Test second-band fundamentals | Second guardian boss |
| 11 | Corrupted variants change one readable behavior | Mixed encounter |
| 12 | Trap timing plus repositioning; no hidden damage stacks | Elite encounter |
| 13 | Strongest fair roster combinations | High-tier objective |
| 14 | Final rehearsal and guaranteed recovery/build choice | Pre-final elite |
| 15 | Short approach, recovery, final arena | Final boss, then escape |

Encounters activate on entry only after the room is ready; gates must not trap the player in a closing collider. Telegraph spawns outside player clearance. Track living encounter actors; reopen gates once on clear. Exploration/rest/reward rooms remain unlocked. Navigation, attack line of sight and collision must agree; no hits through walls. Retry/failure must never leave the player in a sealed empty room.

Start with chaser, armored brute and ranged spitter roles; add only a small number of behavior variants when the basic loop is fun. Traps begin with the existing retract/warn/strike spike cycle. Water and pits follow later, with last-safe-ground recovery and no route softlock. Preserve validated required routes, doorway clearance and bounded timed regions; risky optional rewards must have a safe bypass. Defer lava, capture and new hazard families.

Rewards: a modest clear reward; an optional risk chest; limited healing/rest; and a major choice after guardians. Offer three compatible choices when the pool supports it. Prioritize visible behavior changes (katana arc/reach, ranged technique, dodge interaction) over many percentage bonuses. Guarantee enough baseline power and recovery for an unlucky run to remain viable. Collection is idempotent, and rewards cannot spawn in unreachable terrain. Do not add a large economy or permanent stat grind for the first shipping scope.

Bosses at 5, 10 and 15 use reserved arena templates and a common encounter interface, with bespoke attack patterns rather than a general boss scripting framework. Each has readable windup, danger area, recovery and a limited phase change; no mandatory adds without a threat/fairness review. Boss state controls exit unlocking. Names, lore, art and exact tuning remain content decisions.

Flow: title/new run → depth 1 → objective clear → deliberate descent interaction → next depth with retained health/build → depth 15 final boss defeated → short static escape route and explicit escape interaction → victory/results. Boss death alone is not victory. Never offer depth 16. Death ends the run and offers retry same seed from depth 1 or a new seed. Pause/settings remain available; safe-boundary suspend/resume is part of completion work. No hidden ending or elaborate escape simulation.

## Dependency-ordered milestones and acceptance gates

Every milestone ends with owner review; approval of this plan authorizes no automatic subsequent milestone. Automated results and manual acceptance are reported separately.

| Order | Deliverable | Acceptance before advancing |
|---|---|---|
| 0 | Approve scope, reuse boundaries and recovery snapshot | Manifest verifies all 30 originals; owner approves this proposal and explicitly selects the first implementation milestone. |
| 1 | One finite generated 3D floor using existing generator and movement/input | Seeds 12345/42/7 render consistently; spawn, every required doorway and exit physically traversable; walls/pillars block correctly; camera shows hazards/approaches. Same layout fingerprints as legacy generator. P1A/input/legacy smoke pass; owner tests keyboard, GP325 analog/D-pad, reconnect and cleanup. No combat yet. |
| 2 | One enjoyable combat floor | Katana/dodge, three basic enemy roles, gates and health/death work. Tests cover wall occlusion, dodge immunity, one contact hit per invulnerability window, simultaneous damage, encounter clear/unlock and retry. Manual test proves windups readable and movement responsive. Stop if the core loop is not enjoyable. |
| 3 | Reward/trap loop and one guardian; depths 1–5 vertical slice | Real upgrade choice changes play; rewards cannot duplicate; spikes visibly warn; healing is bounded; boss death unlocks descent once. A complete 1–5 run is enjoyable with keyboard/controller. Pit/water behavior must pass before profiles use them. |
| 4 | Full 15-depth campaign using proven components | All 15 profiles exist; boss arenas 5/10/15 and all transitions work. At least 100 deterministic seeds per depth (1,500 floors), plus pinned regression seeds: no invalid accepted layout, inaccessible objective/spawn/reward or broken required route. Validate encounter budgets and required arena insertion. Manual full campaign verifies pacing and build viability. |
| 5 | Complete run lifecycle and presentation | Death/retry, same/new seed, pause, boundary suspend/resume, version-incompatible save handling and results tested. Health/build survive descent; claims do not duplicate; final defeat → escape → one victory; no depth 16. Samurai/enemy silhouettes, VFX/audio and UI explain threats clearly. |
| 6 | Shipping candidate | Full start-to-escape and death/retry runs, controller unplug/replug, repeated runs, loading/error recovery and target-device profiling pass. Choose target hardware and measurable frame-time/memory budget before this gate; keep mobile/Android only if confirmed as a release target. No claimed release readiness from headless checks alone. |

Physical geometry checks supplement pure-data validation: capsule clearance, trap warning readability, ranged occlusion, gate overlap, floor-edge recovery and camera obstruction. Existing generator stress suite remains authoritative for deterministic generation. Add focused behavior tests only when implementing their milestone. This audit ran no engine import or gameplay suites because no gameplay changed; imports can themselves rewrite project files.

## Untouched files and excluded experiments

Keep `project.godot`, `src/main/`, the original `src/player/`, `src/enemies/`, `src/camera/`, `src/ui/`, 2D world/effects/scenes and their tests intact. Keep the original generator, templates, depth 1–3 profiles, hash/seed utilities, accepted P1A fixture and Stage 2B adapters intact during the first 3D adapter milestone. Later profile/content edits must be explicit, scoped and regression-tested; this is not a promise that campaign data never changes.

Keep every Abyss demo and document on disk. Exclude vertical/spatial composition, chunk catalog/streamer, residency/readiness scheduling, mechanism deployment, Castle Director, moving routes and ambient moving architecture from the active game dependency graph. The static dungeon needs none of them. Do not remove the uncommitted streamer hooks merely to tidy the tree. Stage 2B input reuse is the narrow exception to excluding `src/abyss/`; directory location alone does not determine suitability.

Future exports should start at the approved game root and include its actual dependencies, rather than shipping every experimental scene. Verify export dependency resolution when packaging; exclusion here is a design decision, not an export configuration change performed by this audit.

## Approval boundary

Approve or amend the proposed static-floor architecture, campaign pacing/boss placement and milestone gates. After approval, authorize milestone 1 separately. Until then, retain the snapshot and stop: no gameplay implementation, scene switch, cleanup, commit, push or new phase.
