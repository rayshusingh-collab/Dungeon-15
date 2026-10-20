# Dungeon15 — Development Status

## Current milestone: conventional Dungeon15 M1.1

Dungeon15 is a conventional 3D isometric dark-fantasy action roguelite with exactly
15 depths: a samurai descends through demon-infested floors and ultimately escapes.
The Shifting Abyss / Living Castle direction below is archived.

M1 implements one static generated graybox floor in
`src/game_3d/first_dungeon.tscn` (F6); the existing 2D main scene remains unchanged.
See [M1 implementation, validation and manual acceptance](docs/M1_FIRST_DUNGEON.md).
M1 keyboard/collision/traversal/camera playtest passed. M1.1 improves terrain readability
and provides `src/game_3d/hazard_validation.tscn` for F6 hazard acceptance.
Real GP325 and the new hazard presentation still require manual testing.
Stop after M1.1; enemies, combat, rewards and additional depths require manual approval.

## Archived progress history


**Shifting Abyss Stage 4:** separate deterministic chunk-streaming demo implemented;
manual acceptance pending. Open `src/abyss/streaming_demo.tscn` with F6. Defaults
bound residency to nine chunks and one build job per render frame, with gated
readiness, eviction/reconstruction and bounded session state. Accepted Stage 3,
fixed/P1A demos, input and 2D main/generator remain preserved. No moving rooms.
[Architecture, evidence and manual checks](docs/ABYSS_STREAMING.md). Stop at Stage 4.

**Narrative/design freeze and Stage 3 usability:** approved samurai/demon-castle
premise and event-driven transformation rules recorded in
[design direction](docs/SHIFTING_ABYSS_DESIGN.md). October 25 RC scope is separated
from the long-term vision; a full release checklist remains owner-confirmed work.
The generated demo now has seed buttons for 12345, 42 and 7. Selecting one restarts
the demo at entry; no in-world transformations or Stage 4 work are implemented.

**Shifting Abyss Stage 3:** deterministic graph-based spatial composition,
configurable multi-level chambers, guarded bridges/ramps and a generated test
scene implemented; manual acceptance pending. Open `src/abyss/generated_demo.tscn`
with F6. Existing main/P1A/fixed demo, input, generator and profiles are unchanged.
No streaming or moving architecture. Stop at Stage 3.
[Architecture, play instructions and evidence](docs/ABYSS_SPATIAL_COMPOSITION.md).

**Shifting Abyss Stage 2B:** scene-local analog stick/D-pad input, configurable
axis/button mappings and F3 controller diagnostics implemented; hardware acceptance
pending. Eight-direction camera-relative movement is preserved. P1A's input read
is now an overridable method; its default behavior is unchanged. Original 2D input
configuration, player and generator are unchanged. GP325 manual procedure:
[controller acceptance](docs/ABYSS_CONTROLLER_TEST.md). Stop before Stage 3.

**The Shifting Abyss — Stages 1–2:** architecture/compatibility plan and isolated
three-level graybox fixture implemented; manual acceptance pending. Run
`src/abyss/vertical_demo.tscn` with F6. The fixed fixture includes three chambers,
two stairways and a bridge; it reuses the P1A player and camera without edits.
Stage 3 and later stages require approval. Main scene and generator are unchanged.
Plan, interfaces, limitations and verification: [Shifting Abyss](docs/SHIFTING_ABYSS.md).

**3D branch P1A:** isolated foundation in `src/prototype_3d/foundation_3d.tscn`;
manually accepted by the project owner. Stop at P1A pending approval for further work.
Includes capsule movement,
wall/floor collision, facing, and a fixed orthographic camera with smooth follow.
Focused 3D suite: 43 checks passed; existing smoke suite: 378 checks passed.
Existing 2D main scene, configuration, and generator are unchanged. Launch and
verification details, including environment startup errors and manual acceptance:
[P1A instructions](src/prototype_3d/README.md).

**Milestone 2.2 — Dungeon logic & tactical difficulty: implemented and automatically validated;
awaiting the user's manual play-test.**
- Milestone 2 passed automated validation. Its manual play-test found gray-box rooms too empty,
  which is why Milestone 2.1 exists. Milestone 2.2 makes the generator reason like a designer: every
  room has a purpose, encounters are composed for the room they are in, and difficulty comes from
  tactical combinations under a threat budget.
- Milestone 2.2 continuation (generator v4): recipes were labels without placement; enemies now start
  where their recipe's terrain matters (`SpawnPlanner`), ranged fairness is validated, and spitters
  shoot across pits/water.
- Milestone 2.2 play-test polish (generator v5): the play-test found rooms/corridors empty and group
  combat too easy. Rooms and corridors are now composed (structure sockets, alcoves, decor), and enemies
  have physical presence (contact damage, stagger guard, surrounding). See "Milestone 2.2 play-test polish".
- Milestones 2, 2.1 and 2.2 are one uncommitted diff on top of `931e5c7` (Milestone 1).
- Milestone 3 has not started.

## Milestone 2.2 play-test polish — what changed

**Why groups were easy (measured, not guessed):**
- Every player hit cancelled the enemy's windup and reset its attack cooldown. The player swings every
  0.34 s, faster than the chaser's 0.5 s windup, so anything in the arc was stun-locked.
- All enemies steered straight at the player, arrived on one side, and queued inside one 130° cleave.
- The player's reach (84 px) beat the chaser's attack range (60 px): chasers were staggered before they
  could even wind up.
- Touching an enemy did nothing.

A stand-still, swing-at-the-nearest bot lost **0 hp** to 3 chasers, **0.25 hp** to 4 chasers and **0 hp** to
brute + 2 chasers (avg of 4 spread spawn layouts).

**Combat changes (all values are `@export`s on `Enemy` or the enemy scenes; enemy HP unchanged):**
- **Contact damage (`ContactDamage`, a `Hitbox`):** an enemy that is chasing or attacking hurts on contact
  (1 damage plus a radial shove; brute ×1.4 shove, spitter ×0.6). It goes through Hitbox → Hurtbox →
  HealthComponent, so the player's invulnerability after a hit means **4 bodies touching at once cost
  exactly 1 hit**, and dodge i-frames cover contact. A staggered or recovering (dimmed) enemy is safe to
  touch, which keeps the "opening" readable.
- **Stagger guard:** a hit interrupts an enemy once per attack cycle. After that, for `stagger_guard_time`
  (chaser 1.5 s, brute 2 s) or until its attack finishes, hits still damage it but it fights through
  them (gold spark instead of the white stagger ring, shove ×0.15). The **brute's windup is armored**.
- **Crowd steering:** enemies separate, and one whose side is already taken (another enemy within 70°,
  closer to the player) circles at the edge of the player's reach (115 px) until it has its own angle.
  It commits anyway once it is outside the player's swing arc (65°). Groups surround instead of queueing.
  The loop runs over a static registry of living enemies, with no per-frame allocation.
- **Body pressure:** a melee enemy waiting for its next attack keeps pressing in (contact) while spreading.
- **Chaser tempo:** lunge-in attack (winds up at 92 px, just outside the player's reach, and strikes with a
  ~40 px lunge); windup 0.5 → 0.42 s, cooldown 1.3 → 1.05 s, post-stagger delay 0.6 → 0.35 s.

After (same bot, same layouts): **1.75 / 2.0 / 2.25 hp** lost of 5; a static player dies to 2 chasers + a
spitter in 4/4 runs. A crude bot that dodges away from nearby windups loses only **0.25 / 1.0 / 1.0 hp**, and
one-on-one a stand-still swinger still beats a chaser, taking at most 1 hit. Skill pays; carelessness hurts.

**Dungeon density (generator v5):**
- **Structure sockets** in templates: `x` (optional rubble or broken wall), `o` (optional pillar). There are
  44 regions across entry hall, chamber_large (3 variants), room_medium, hall_narrow, room_l_shape and
  objective_vault. The **entry hall** is now a ruined colonnade with an open clearing around the spawn.
  A seeded `dressing` stream uses each region with a density by role (`RoomRole.dressing_density`):
  - quiet rooms 0.75–0.85
  - ambush 0.65
  - fights and the objective 0.5 (large fight rooms stay deliberately open arenas)
  - terrain rooms 0.3
  - risk rooms and story chambers 0

  In a fight room a region is refused if it would cut clear floor below what the size class needs for
  its full enemy count.
- **Fully-dressed lint:** template lint also checks each variant with *every* socket solid. Removing
  structure can never break connectivity or clearance, so any subset the generator picks is safe by
  construction. It caught three authoring mistakes during this pass. `chamber_small`, `junction_hall` and
  `hall_narrow[cover pillars]` got no sockets: every free tile there is on a 3-wide door lane or next to
  a spawn point.
- **Room size by purpose** (`RoomRole.size_weight`): traversal, exploration, reward and rest rooms rarely
  get a large hall (×0.3); fights prefer space (large ×1.3).
- **Corridor alcoves** (`corridor_dressing` stream per corridor): recesses beside long straight segments,
  outside the 3-wide lane, carved only into empty space. They are either a nook (with remains, a future
  environmental-storytelling spot) or a collapsed section (floor, then rubble). The lane never changes;
  the validator checks every lane tile.
- **Decor** (`DecorPlacer`, `decor` / `corridor_decor` streams): non-colliding floor marks (cracks, stones,
  bones; more remains in quiet rooms, none in rest rooms), remains in nooks, and torch sockets on walls
  (future light sources). Never on terrain, sockets or doorway approaches (validated). One `DecorLayer`
  node draws it all in a single static canvas item.
- **Measured:**
  - open-field floor (7×7 empty windows) 13% → 5%; entry hall 43% → 6%
  - per floor: ~18 structure pieces, ~5–7 corridor alcoves, ~150–200 decor items
  - depth-3 fights using a room-specific tactic 62% → 77% (more rooms now have cover)

**Design requirements recorded for later milestones (not implemented now):**
- **Power-ups (M3/M4): important upgrades must change gameplay, not just numbers.** Examples:
  - a throwing weapon adds a real ranged attack
  - a weapon enhancement visibly changes the attack (reach, arc, trail)
  - an element changes attack behaviour and VFX
  - a special attack adds a tactical option
  - a mobility upgrade changes dodge/movement

  Stat upgrades may exist, but major rewards must feel physically different. Today's hooks: the reward,
  cache and power markers (placeholders), `MeleeAttack`/`Hitbox` as swappable attack components, and
  `EnemyProjectile` as a reusable projectile.
- **Capture (future enemy mechanic):** some special enemies may capture the player. It must be an
  intentional, telegraphed attack, never sprite contact:
  - telegraphed grab windup (a `MeleeAttack` phase like any other)
  - successful grab (a dedicated grab `Hitbox`)
  - a new Player state (e.g. CAPTURED) with an escape/consequence rule

  Body contact stays `ContactDamage` (1 damage plus a shove) and must never trigger a capture.

## Milestone roadmap

0. Audit & cleanup ✅
1. Playable combat foundation ✅ (manual play-test passed, feel pass approved)
2. Seeded procedural dungeon ✅ automated validation (manual play-test showed the rooms were too plain)
   - 2.1 Environment, readability & thriller foundation 🟡 (awaiting play-test)
   - 2.2 Dungeon logic & tactical difficulty 🟡 (awaiting play-test)
3. Combat/content framework: enemy archetypes, weapons, loot, upgrades, traps, chests, special rooms, scaling, boss framework
4. Run/roguelite systems: run state, saves, meta progression, stats, seed sharing
5. Content & presentation: art, animation, themes, VFX, audio, menus, tutorial, settings
6. Mobile production: Android input, resolutions/safe areas, profiling, pause/resume, export
7. Release candidate: bug fixing, balance, many-seed validation, final build

Campaign direction (for later milestones): 15 finite narrative depths; the Queen and King rule the final
portion; minibosses throughout; environmental storytelling and short cinematics; build choices; hazards
(water, pits, traps, lava); difficulty from learning and strategy, not enemy spam. **The hidden ending is
deliberately undecided.** Earlier "Break the Thread" material is non-canon placeholder; nothing may define it yet.

## Milestone 2 — what exists

The endless sequential-room prototype is gone. Each run seed + depth produces a finite, explorable floor:
**ENTRY → navigable dungeon (rooms, corridors, junctions, branches, loops, dead ends) → OBJECTIVE/EXIT.**

- **Deterministic generation pipeline** (graph → layout → content → validation → retry), pure data and
  headless-testable. Full design: **[docs/DUNGEON_GENERATION.md](docs/DUNGEON_GENERATION.md)**.
- **Maze-like topology:** a twisting main path, branches (sometimes off branches), dead ends that always
  have a purpose (reward / lore / optional fight / future-secret socket), occasional loops.
- **9 ASCII room templates:** entry hall, small chamber, medium room, large pillared chamber, narrow hall,
  L-shaped room, crossroads junction, descent vault (objective), story chamber (special).
- **Corridors:** 3 tiles (96 px) wide, straight / L / Z shaped, walled, connecting actual doorways.
- **Encounters inside the dungeon:** only combat rooms lock. Entering one seals its doorways (red barred
  gates), telegraphs spawn points, spawns enemies away from the player (they engage at once), and reopens
  on clear. Exploration rooms and corridors never lock.
- **Special-room insertion:** the story chamber is reserved on the main path (exactly 2 links) with authored
  placeholder content. This is the mechanism for future guardian/boss/story rooms.
- **Hazard foundation:** a generic socket model (hazard/reward/lore/encounter/anchor), plus one placeholder
  hazard: spike traps (retract → warn → raise, damage via Hitbox so dodge works). Placement can never
  block a route or split a room.
- **Depth profiles:** data-driven `DepthProfile` resources. Two test profiles (depth 1, depth 2) prove the
  system; no per-depth code.
- **Finite depth completion:** stepping on the exit (sealed until an objective encounter is cleared, if the
  profile has one) shows DEPTH COMPLETE with stats and NEXT DEPTH (if a profile exists), REPLAY SEED, NEW SEED.
- **Seeds:** the HUD always shows depth and seed. The SEED panel (pauses the game) enters a seed (numbers
  or words), restarts the current one, picks a new one, or copies it. Death offers RETRY SEED / NEW SEED.
  The command line takes `-- --seed=<n|word> --depth=<n>`. **A seed only changes when the player asks for a new one.**
- **Camera** follows the player with smoothing inside the dungeon bounds (kick/shake feedback unchanged).
- **Combat from Milestone 1 is unchanged** and its tests all pass in the generated entry hall.

## Milestone 2.1 — what was added

- **Interior geometry:** interior walls (`I`), pillars (`O`), rubble (`%`), chokepoints, alcoves, split
  sections and central structures. All of it is solid collision, merged into the single wall body.
- **Room variants:** templates carry alternative interiors with the same size and doors, chosen per
  room from a seeded "variants" stream. There are now 13 templates and 22 layouts in total.
  - New templates:
    - `pit_bridge_chamber`: single / twin bridges
    - `water_chamber`: open pool / rubble island
    - `trap_gallery`: twin / baffled spike strips
    - `junction_hall`: octagon with a central obstacle
  - New variants of existing templates:
    - `chamber_small`: center block
    - `room_medium`: split wall, pillar lanes
    - `chamber_large`: inner sanctum, ruined hall
    - `hall_narrow`: cover pillars
- **Water:**
  - 0.62× movement speed; dodge is only half affected.
  - A splash ring when entering. Enemies slow too.
  - Water is never an obstacle: routes through it are always valid.
- **Pits / chasms:**
  - You fall only when your centre is over the drop (6 px forgiveness).
  - Player: 1 damage plus a short fall, then respawn on the last safe ground with 1 s of
    invulnerability.
  - Enemies die (knock them in).
  - A light lip marks every walkable edge. The validator treats pits as walls for every required route.
- **Bridges:** at least 3 tiles (96 px) wide. The stress suite verifies every pit room keeps its sides joined.
- **Spikes:**
  - Readability: clearer region outline, a warning progress bar, and a 0.6 s warning.
  - Authored spike strips (`^`) as well as optional sockets.
  - A spike region is never longer than 8 tiles, so it can be crossed in one safe window.
- **Enemy navigation:**
  - An `AStarGrid2D` over the floor. Enemies walk around walls, pillars and pits, and avoid water
    and spikes where they can.
  - Straight steering when there is line of sight.
  - Enemies attack only with line of sight, and **no attack hits through walls** (Hitbox raycast).
- **Sockets:**
  - enemy / hazard / reward / lore / secret, as before
  - `+` prop sockets (reserved for later art)
  - `T` tension/event sockets, plus one in every corridor
  - Each floor arms one event socket in a quiet space. In debug builds it shows
    "[debug] tension event socket fired" on the HUD. This proves the hook only; there is no thriller content yet.
- **Maps:**
  - **MAP** (M / Tab / MAP button) is now the player's exploration map. It shows only rooms and
    corridors you have visited, with doorway stubs for exits you haven't explored and cleared rooms marked.
  - **Debug full map** (F3 / DBG button, **debug builds only**) shows everything: terrain, main path,
    loops, event sockets and a legend.
- **Pacing:** every room has a space type (entry, traversal, combat, environmental, optional, reward,
  story, objective), with a floor tint per type.
  - Peaceful main and branch spaces often become environmental challenge rooms.
  - Depth 1 never has two combat rooms in a row on the main path.
- **Validation on the real geometry:**
  - Two masks: strict and route.
  - Room-interior checks: a doorway cut off inside its room, a split floor.
  - Pit and hazard checks: unlisted hazards, doorway hazards, over-long spike regions.
  - Enemy spawn reachability, and event socket validity.
  - Template lint also checks player clearance on door approaches.

## Milestone 2.2 — what was added

Guiding question for every generated element: *why is it here, and what decision does it force?*
Full design: [docs/DUNGEON_GENERATION.md](docs/DUNGEON_GENERATION.md).

- **Room roles (`RoomRole`, assigned by `PacingDirector` before templates are chosen):**

  | Role | Meaning |
  |---|---|
  | TRAVERSAL | quiet pass-through |
  | TRANSITION | junction |
  | EXPLORATION | lore / secret |
  | COMBAT | locked fight in a clean arena |
  | HAZARD | terrain challenge, no enemies |
  | HAZARD_COMBAT | locked fight on terrain |
  | AMBUSH | unlocked fight, always another exit |
  | REWARD | optional reward |
  | RISK_REWARD | cache behind a visible risk, optional |
  | REST | recovery shrine |
  | CHALLENGE | optional elite-placeholder fight guarding a power socket |

  Plus the fixed roles ENTRY, STORY and OBJECTIVE.
  - Roles decide which templates and variants a room may use. Pits, water and spikes appear only
    where the role is a terrain challenge.
  - Roles also decide which hazards may be placed, whether enemies appear, and the room's floor tint.
- **Pacing director (seeded "pacing" stream):** reads the main-path sequence so far.
  - No more than N fights in a row. The objective fight counts: depth 1 allows 1, depths 2–3 allow 2.
  - No two terrain challenges in a row, and no role three times in a row.
  - Rest only after a fight; after two quiet rooms a fight becomes more likely.
  - At least `min_combat_rooms` fights and `min_terrain_rooms` terrain lessons.
  - Branch rooms read their neighbours: a room next to a fight rarely fights too.
  - Dead ends always get a purpose: reward, lore, secret, risk cache, challenge or recovery.
  - The armed tension event is placed right before a fight in 100% of stress floors (uncertainty → combat).
- **Tactical composition (`TacticalComposer`, seeded "tactics" stream per room):** each fight is built
  from a recipe that pairs enemy roles with the room's actual features:

  | Recipe | Combination | Decision it forces |
  |---|---|---|
  | `pillar_skirmish` | spitter + pillars | use cover |
  | `chasm_brawl` | brute + pit | mind your back, knock them in |
  | `ledge_fight` | chasers + pit | dodge along the edge |
  | `spike_bait` | chasers + spikes | lure them onto raised spikes |
  | `wading_fight` | melee + water | hold dry ground |
  | `choke_hold` | brute + narrow hall | don't get pinned |
  | `sniper_nest` | spitter across pit or water | cross between shots |
  | `ambush_pincer` | open-door ambush | funnel at a doorway, or run |
  | `elite_guard` | optional elite | skip it if hurt |
  | `open_brawl` | fallback | — |

  Enemies are added core first, then fill, while the room stays within its threat budget, its
  maneuvering space and its far spawn points. Dedicated recipes (ambush, challenge) take priority.
- **Enemy placement (`SpawnPlanner`, generator v4):** a recipe is only kept if its enemies actually
  start where the terrain matters, seen from the **approach doorway** (the one leading toward the entry):
  - `sniper_nest`: the spitter starts *across* the pit/water with a clear shot
  - `pillar_skirmish`: the spitter starts *screened* behind a pillar or wall
  - `chasm_brawl` / `ledge_fight`: the brute / a chaser starts on the *ledge* (≤ 3 tiles from the chasm)
  - `wading_fight`: a chaser must *wade* to reach you
  - `spike_bait`: a chaser must cross the *spikes* to reach you

  Fairness from every doorway: all enemies ≥ 150 px away, ranged ≥ 224 px (time to read the
  telegraph), and at most one ranged enemy in a room without cover (no crossfire). The same plan runs
  at generation (composer, validator) and at runtime (`DungeonRoom`), so play matches what was validated.
  A recipe that can't be realized falls back to the next one (often an honest open brawl).
- **Placeholder enemy roles (not the final roster):**
  - `chaser`: melee pressure (the Milestone 1 enemy).
  - `brute`: slow, heavy knockback ×2 (about 3.4 tiles), body blocker; 0.75 s readable windup.
  - `spitter`: keeps its distance and backs off. It fires a slow projectile after a 0.65 s telegraph
    with an aim line. Walls and pillars stop the shots (a swept ray, so they can't tunnel through).
    It sees and shoots **across pits and water** (`DungeonNavigation.clear_sight`: only solids block
    sight); before v4 it used the walking test, so a sniper across a chasm walked around instead of shooting.
- **Threat budget (`ThreatModel`):** a deterministic, explainable score per room. It adds up:
  - enemy base threat
  - interactions: knockback + pit, ranged without cover, melee in water
  - locked doors
  - spikes or pit in the arena
  - a cramped arena
  - timed terrain and risk areas

  Each room has a role budget and each floor a total budget, both set per depth. The validator
  recomputes every score independently.
- **Hazards have a purpose:** timing, route shaping, area denial, or risk route. A hazard without a
  valid purpose for its room's role is rejected. Optional sockets are filled only in terrain rooms.
  Spikes now hurt enemies too, so baiting works.
- **Risk / reward:** two new templates.
  - `risk_cache`: a spike ring, or a chasm causeway with spikes.
  - `risk_shortcut`: a spiked wall gap, or the same with a flooded bypass.

  In both, the cache sits behind visible spikes, and every required route exists without touching
  them. Validator masks: *required* = route mask minus risk tiles. The debug views draw the risky
  (orange) and safe (green) routes.
- **Resource hooks:** a heal shrine in rest rooms restores 1 heart and is not wasted at full health.
  A cache marker (placeholder high-value reward) sits in risk rooms, and a power socket (future
  power-up) in challenge rooms.
- **Ambush:** encounter kind AMBUSH, which never locks. Enemies keep their leash, the room always has
  a second exit, and the banner reads "AMBUSH! - the doors are open". Locked fights say "DOORS SEALED".
- **Fairness validation (new):**
  - no hazard or pit within 4 tiles of the spawn
  - the first two tiles inside every doorway are safe
  - hazards cover at most 45% of a room, with safe footing within 4 tiles of every spike
  - maneuvering space: at least 16 + 8 × enemies clear tiles
  - ambushes need an escape route
  - rest rooms are safe
  - risk caches are reachable only optionally
  - hazard fights need a terrain recipe
  - challenges carry their reward
  - roles are allowed at the depth
  - room and floor budgets hold, and recorded threat equals the recomputed threat
  - pacing (including min fights and min terrain)
  - enemy placement from every doorway: fair distances, no "unavoidable shot" (ranged < 224 px), no
    ranged crossfire without cover, and the recipe's tactic realized from the approach doorway
- **Graceful downgrade:** a terrain room whose only terrain (hazard sockets) had to be refused becomes
  the closest safe role (hazard → traversal, hazard fight → fight). `planned_tactic` records the
  original role, and the debug views show it.
- **Depth progression (data only):**
  - **Depth 1** teaches: melee fights with relief between them, and every floor has a terrain lesson.
  - **Depth 2** adds route decisions: risk rooms, open-door ambushes, optional elite challenges, and
    the brute (via choke/elite recipes only).
  - **Depth 3** (new test profile) adds hazard + enemy interaction: fights on terrain, the spitter, and
    all 10 recipes.

  Budgets grow; enemy counts do not (the cap stays 2/3/4 by room size). Measured (v4): depth 1 uses 1
  recipe, depth 2 uses 4 (39% of fights room-specific), depth 3 uses 10 (62% room-specific; v3 claimed
  79%, but some of those recipes were labels whose enemies didn't start where the terrain mattered).
- **Debug / design views (debug builds only):**
  - **F4 / TAC tactical overlay** in the world: per room, the role, threat/budget, recipe and enemy
    letters, and the decision the room asks for ("situation: advice"). It also shows hazard purposes,
    risk tiles, safe/risky routes and spawn points, and in yellow the spawn plan from the approach
    doorway (a letter per enemy start, a dashed line to each lead enemy placed for the terrain, and a
    "from the approach: S across" line).
  - **F3 debug map:** the same data per room, plus the floor threat against its budget, the main-path
    rhythm, and why earlier attempts of this seed were rejected.
  - The player map stays exploration-only.

## Controls

| Action | Desktop | Mobile |
|---|---|---|
| Move | WASD / arrow keys | left virtual joystick |
| Attack | Space / J | ATTACK button |
| Dodge | Shift / K | DODGE button |
| Exploration map | M or Tab, or the MAP button | MAP button (top right) |
| Debug full map (debug builds only) | F3 or the DBG button | DBG button |
| Tactical overlay (debug builds only) | F4 or the TAC button | TAC button |
| Seed panel | SEED button | SEED button (top right) |
| Retry / new seed / next depth | death and completion screen buttons | same |
| Start with a seed | `godot --path . -- --seed=12345 --depth=1` | SEED panel |

## Architecture

```
src/core/            RunConfig (seed/depth across reloads, cmdline), StableHash (FNV-1a)
src/dungeon/generation/   pure data: SeedStreams, DepthProfile, SpecialRoomRule, RoomTemplate, RoomShape,
                     DungeonGraph, GraphBuilder, PacingDirector (room roles), RoomRole, LayoutBuilder,
                     ContentPlacer, TacticalComposer (recipes), SpawnPlanner (enemy placement), ThreatModel
                     (threat score), DecorPlacer (non-colliding decor), DungeonValidator,
                     DungeonLayout, DungeonGenerator
src/dungeon/world/   DungeonBuilder -> DungeonWorld (TileMapLayer + merged wall body + terrain zones + rooms +
                     content + actors), DungeonRoom (encounter state; locked or open ambush), EncounterGate,
                     DepthExit, RoomMarker (reward/lore/secret/heal/cache/power), SpikeTrap, WaterZone, PitZone,
                     EventTrigger, DungeonNavigation (enemy A*), TacticalOverlay (debug design view), DecorLayer
                     (decor, one node), PlaceholderTileset
src/components/      ... + TerrainState (per-body terrain effects, e.g. water speed); Hitbox.knockback_scale;
                     ContactDamage (body contact as a Hitbox, re-armed on a timer)
src/dungeon/rooms/   authored content scenes for special rooms (story chamber placeholder)
src/enemies/         Enemy (chaser), brute.tscn, Spitter + EnemyProjectile, EnemyCatalog (ids -> scenes,
                     threat, role tags) - placeholder tactical roles, not the final roster
src/main/            Main: RunConfig -> generate -> build -> wire signals; retry/replay/new seed/next depth
src/ui/              Hud (run info, status, banners, death/complete/failure screens), DungeonMap, SeedPanel,
                     HealthDisplay, MobileControls, TouchActionButton
src/camera/          GameCamera: follow + bounds + kick/shake
data/rooms/          RoomTemplate .tres (ASCII layouts)
data/depths/         DepthProfile .tres (depth_01, depth_02, depth_03 test profiles)
docs/DUNGEON_GENERATION.md   generation design + determinism contract
tools/               test_harness.gd, smoke_test.gd, generation_stress.gd
```

**Runtime flow:** `Main._ready` → `RunConfig` → `DepthProfile.load_for_depth` → `DungeonGenerator.generate`
(retries; on failure it shows GENERATION FAILED) → `DungeonBuilder.build` → the player goes to the entry anchor,
the camera follows, the HUD and map get the layout. World signals (`room_entered`, `encounter_started`,
`enemies_remaining_changed`, `encounter_cleared`, `marker_collected`, `exit_reached`, `player_fell`,
`tension_event`) drive the HUD and map. `Main._physics_process` tracks the last safe ground (for pit respawn)
and reveals the room or corridor under the player on the exploration map.
Retry / replay / new seed / next depth set `RunConfig` and reload the scene.

**Physics layers:** 1 world (walls, obstacles, locked gates), 2 player, 3 enemies, 4 player_hurtbox,
5 enemy_hurtbox. Room triggers, markers and the exit scan the player layer; spike hitboxes scan both
hurtbox layers (spikes hurt enemies too); enemy projectiles sweep a ray against layer 1 and hit player_hurtbox.

## Tuning values

Combat values for the player and the chaser are unchanged from Milestone 1 (see git history `931e5c7`
or the scene exports). The placeholder brute and spitter values are in their `.tscn` exports.
Generation values:

| Area | Depth 1 (test) | Depth 2 (test) | Depth 3 (test) |
|---|---|---|---|
| Design goal | teach movement, terrain, simple fights | route decisions | hazard + enemy interaction |
| Macro grid | 5×4, slack 4 | 6×5, slack 3 | 6×5, slack 3 |
| Main path | **7–8**, entry↔exit ≥3 cells | 8–10, ≥4 cells | 8–10, ≥4 cells |
| Loops | 40% chance each, max 1 | 60%, max 2 | 60%, max 2 |
| Main-path role weights | combat 3, hazard 1.5, traversal 1, rest 1, exploration 0.5 | + ambush 1, risk 1 | + hazard fight 2.5 (combat 2) |
| Dead-end role weights | reward 3, exploration 2, secret 1, challenge 1 | + risk 2 | + risk 2, challenge 2 |
| Fights in a row (max) / min fights | 1 / 2 | 2 / 3 | 2 / 3 |
| Terrain rooms in a row (max) / min | 1 / 1 | 1 / 1 | 1 / 1 |
| Rest rooms (max) | 1 | 1 | 2 |
| Objective fight | no | sealed | sealed |
| Enemy pool | chaser | chaser, brute | chaser, brute, spitter |
| Recipes | open_brawl | + ambush_pincer, elite_guard, choke_hold | all 10 |
| Room threat budget | 7 | 8.5 | 10 |
| Floor threat budget | 32 | 60 | 85 |
| Ambush / challenge budget scale | 0.8 / 1.3 | same | same |
| Quiet / risk room caps | 2 / 3 | same | same |
| Enemy cap per fight | small 2 / medium 3 / large 4 (by room size, never by progress) | same | same |
| Optional hazard sockets | density 40% (terrain rooms only) | 60% | 60% |
| Special room | story chamber at 50% | at 40% | at 50% |

Threat weights (`ThreatModel`): chaser 2, brute 3, spitter 2.5; knockback near a pit +1; ranged
without cover +0.75; melee in water +0.25; locked doors +0.5; spikes in the arena +0.75 per area; pit
in the arena +0.5; cramped (<14 clear tiles per enemy) +1; timed spikes without enemies +0.5 per area;
chasm crossing +0.5; risk area +0.75. Maneuvering space: ≥ 16 + 8 × enemies clear tiles.
Enemy placement (`SpawnPlanner`): every enemy ≥ 150 px from the trigger point, ranged ≥ 224 px, ≤ 1 ranged
enemy without cover, "ledge" = ≤ 3 tiles from a pit, line tests sampled every 8 px.

Fixed rules: tile 32 px, corridor 3 tiles, cell margin 4 tiles, encounter trigger inset 2 tiles, spawn
delay 0.6 s, minimum spawn distance 150 px (validated at 198 px from every doorway), hazards ≥2 tiles from
doorways, 24 generation attempts, spikes 1.4 s retracted / 0.6 s warning / 0.5 s raised / 1 damage,
spike region ≤ 8 tiles, water speed 0.62× (dodge half affected), pit edge forgiveness 6 px, fall 0.45 s,
1 damage, 1 s respawn invulnerability, bridges ≥ 3 tiles, required passages ≥ 3 tiles, enemy re-path 0.3 s,
event trigger radius 56 px.

## Technical decisions

- **Graph first, geometry second, content third, validation last.** No scene code makes generation decisions.
- **Macro grid + irregular track sizes + jitter:** guarantees non-overlap and crossing-free corridors by
  construction, while still looking uneven. The validator re-checks everything anyway.
- **Named RNG streams + engine-independent hashing** (see the determinism contract in the docs). The golden-seed
  test pins generator **v5** output (v3: Milestone 2.2 roles, tactics, depth 1's longer main path; v4:
  SpawnPlanner placement and recipe realization; v5: structure sockets, room size by purpose, corridor
  alcoves, decor).
- **Lint the worst case.** Optional structure is linted fully dressed: removing structure never breaks
  connectivity or clearance, so every subset the generator picks is safe by construction.
- **Contact is a Hitbox.** Body pressure reuses Hitbox -> Hurtbox -> HealthComponent, so invulnerability,
  dodge i-frames and one-hit-per-window apply to it with no special cases.
- **Roles before templates.** The pacing director decides what each space is *for*; templates and variants
  follow from that, so terrain only appears where it is the point of the room.
- **One threat model, used twice.** The composer builds fights with `ThreatModel`; the validator recomputes
  the same score independently and compares it with the record and the budgets. A difficulty change is a
  data change (weights, budgets, recipes), never a code branch per depth.
- **One spawn plan, used twice.** `SpawnPlanner.plan` is a pure function of the room data and the trigger
  point; the composer and validator judge it from every doorway, and `DungeonRoom` uses it at runtime. A
  recipe must be realized in that plan, not just named.
- **Sight is not walkability.** Ranged enemies use `clear_sight` (solids only); melee enemies keep the
  walking test, since they have to reach you.
- **Difficulty through composition, not counts.** Depths unlock recipes, archetypes and interactions; the
  enemy cap per room size does not grow.
- **Risk is optional by construction.** Risk hazards are excluded from the *required* mask, so no required
  route can depend on them; the validator checks every required route on that mask.
- **Generator honesty.** The pacing director must satisfy its own rules (unit-tested before validation),
  and content placement downgrades a room it cannot furnish instead of wasting the attempt.
- **Terrain is tile data first.** The validator, enemy navigation, the map and the builder all read the same
  `DungeonLayout` tiles, so there is never a second, drifting source of truth for walkability.
- **Pits are validated as walls**, and water as floor. Hazards may add risk, but never gate progress.
- **AStarGrid2D over NavigationServer:** it is native, deterministic, built from the same tiles, and needs no
  baked navigation polygons. At depth 2 it takes at most ~65 ms, once per floor.
- **Tile-clearance reachability:** paths must fit a player-sized body, not just a 1-tile gap. The stress suite
  also sweeps a real 18 px physics body along those paths in built worlds.
- **Encounter enemies spawn on entry** (not pre-placed), so they can't wander into corridors before the gates
  lock, and idle rooms cost nothing.
- **RunConfig static state** instead of an autoload: survives `reload_current_scene()`, and tests set it directly.
- **Visuals:** a runtime-built placeholder TileSet (swap for an authored TileSet with the same atlas coords),
  floor tints per room role, merged-rectangle wall collision on one body.
- **Seed panel pauses the tree;** the HUD runs with `PROCESS_MODE_ALWAYS`.

## Known issues / limitations

- Placeholder visuals only: flat tiles, labels, drawn markers. Rooms read as rooms-and-corridors on an
  uneven grid; making it look like a *believable* dungeon is presentation work (Milestone 5).
- Rewards, lore and secrets are **placeholder markers** (collecting shows a banner). Their payloads belong to Milestone 3.
- Enemy archetypes are **placeholders for tactical roles** (chaser, brute, spitter), not the final roster; their
  numbers are untuned beyond readability.
- Recipe placement is **guaranteed from the approach doorway** only. Entering a room through another
  doorway (a loop or a backtrack) keeps every fairness rule, but the tactic holds in 93–100% of cases
  (spike_bait 93%, pillar_skirmish 97%, the others 100% in the stress sample).
- Spawn fairness is validated from each doorway's trigger point. A player who walks along the 2-tile
  band inside a room's walls (outside the inset trigger) can trigger a fight from an unusual spot; the
  planner then falls back to the farthest spawn points, which may be closer than 150 px. Not seen in
  testing, but possible in small rooms.
- Pit rooms (the only home of `chasm_brawl`/`ledge_fight`) appear in ~15% of depth-3 floors, so those two
  recipes are rare (about 1 in 20 depth-3 fights).
- The threat model is a designer's estimate (hand-set weights), not measured difficulty; play-testing
  should tune it. Budgets currently use ~60–95% per fight.
- Recipes are chosen per room; there is no cross-room "encounter arc" beyond the pacing rules.
- Heal/cache/power markers are hooks: only the heal has an effect (1 heart); cache and power are banners.
- Only three test depths exist; depths 4–15 are design targets in the profile philosophy, not content.
- Ambush enemies spawn from the room's normal spawn sockets; there are no hidden "ambush alcoves" yet.
- Spike knockback can push a player standing at the side of the chasm causeway into the pit (one damage in
  total thanks to invulnerability); this is the causeway's intended risk but should be judged in play.
- Enemies path on the tile grid. In very tight spots they may briefly scrape a pillar corner before re-planning.
- Tension events are a debug proof only (HUD text). No thriller beats, audio or scripted moments exist yet.
- Prop (`+`) and secret (`?`) sockets are reserved but not used for art or real secrets yet.
- The exploration map has no persistence between reloads (there is no run state until Milestone 4).
- Depth completion offers NEXT DEPTH only while a profile exists (depths 1–3 are test profiles, not the
  15-depth campaign). There is no run state carried between depths yet (health resets on reload; Milestone 4).
- Macro-grid topology means rooms are laid out on an (uneven) grid; no diagonal or free-form corridors yet.
- Encounter spawn selection depends on where the player triggers the room (`SpawnPlanner`; candidates and order are seeded).
- Only locked encounters remove the leash;
  test enemies placed elsewhere keep it.
- Combat difficulty numbers come from scripted bots (stand-still swinger, crude dodger), not human play:
  contact damage, stagger guard and crowd values are first-pass exports and need feel tuning in play.
- Enemies circling for an opening use simple steering; with walls close by they can scrape or hesitate
  (they fall back to path-following when the player is out of sight).
- Decor and torch sockets are placeholder shapes; torches emit no light yet (future light sockets).
- The validator checks decor with the same `DecorPlacer.floor_mark_ok` rule the placer uses (a shared rule,
  not an independent re-derivation); the negative tests cover it.
- Corridor alcoves are carved only where there is empty space two tiles around them, so tight macro
  cells get few (~5-7 per floor).
- The native `VirtualJoystick` still needs on-device verification (Milestone 6).
- Hand-written `.tscn`/`.tres` files reference resources by path only; the editor adds UIDs on first save.

## Testing status

| Check | Result |
|---|---|
| `--import` | clean |
| `--check-only` on every script (`src/`, `tools/`) | no warnings/errors |
| Headless boot | clean at depths 1, 2 and 3 |
| `tools/smoke_test.gd` | **378/378 pass**. Play-test polish: contact damage (1 hit, shove, i-frames), 4 simultaneous contacts = 1 hit, dodge ignores contact, staggered enemies safe to touch, stagger guard (an enemy hit every 0.35 s still strikes), brute windup armor, 4 chasers spread around the player, a 2 chasers + spitter group hurts a stand-still player while one-on-one costs at most 1 hit, decor is one node, structure and corridor rubble solid, nooks walkable. Earlier: Milestone 1–2.1 coverage plus: every archetype instantiates; the brute's knockback throws the player into a chasm where a chaser's does not; the spitter's shot hurts in the open, is stopped by a wall, and it backs away; a spitter sees and shoots across a chasm it cannot walk across, and holds its side; spikes hurt enemies; an ambush has no gates, keeps leashes and an open doorway; the shrine heals once and is not wasted at full health; the risk cache is claimable and the exit reachable without the risk; F4/TAC overlay and role-free player map; completing the last test depth offers no NEXT DEPTH. |
| `tools/generation_stress.gd` | **337/337 pass** (v5): density (open field 5.2%, entry hall 6.3%, structure on every floor, alcoves on ≥ 80% of floors, quiet rooms furnished more than fights), fully-dressed lint negatives, density negatives; 1,500 stress floors (800 depth 1 + 400 depth 2 + 300 depth 3), 0 failures; every floor re-validates; no fight or floor over budget; every hazard has a purpose; every allowed recipe, archetype and weighted role appears; risk rooms in ≥ 50% of depth 2–3 floors, all with a risky route shorter than the safe one or the only way; terrain lesson on 100% of floors; armed event right before a fight on 100% of floors |
| Tactical negatives | 22 fairness rules plus 7 density rules (structure at a doorway, structure touching terrain, structure in a story room, rubble in a corridor lane, decor on a socket, decor on terrain, torch off the wall) broken on valid floors, each named by the validator (spawn hazard, unsafe entry, stacked hazards, room budget, floor budget, tampered threat, mandatory risk route, ambush without escape, spawn beside a pit, purposeless hazard, stacked fights, unsafe rest room, locked role, no maneuvering space, unreachable cache, riskless risk room, hazard fight without interaction, too few fights, challenge without reward, recipe tactic only a label, ranged crossfire without cover, ranged enemy too close to react) |
| Generator honesty | the pacing director's own output (306 graphs) and content placement on every attempt (245 attempts: spawns, budgets, space, purposes, enemy placement) keep their rules without relying on the validator |
| Physical traversal | 50 built worlds (depths 1–3), ~89k path segments swept by a player-sized body, 0 blocked, 0 steps over a pit, 0 steps over a risk tile |
| Enemy placement (v4) | 1,689 encounter/doorway plans: runtime points equal the generation-time plan (0 mismatches), every enemy ≥ 150 px away, no ranged enemy within 224 px; every terrain recipe realized from the approach doorway (pillar_skirmish 71/71, sniper_nest 11/11, chasm_brawl 8/8, ledge_fight 7/7, wading_fight 17/17, spike_bait 72/72; from any doorway 93–100%); sniper spitters have a clear shot across (11/11); the planner finds the intent spot when it comes last in the seeded order (94/94) |
| Enemy navigation | every spawn → doorway path over 60 floors (depths 1–3) reachable (3,206 paths) |
| Determinism / variation | 150 seeds reproduce with a disturbed global RNG; depth 3 tactical data (roles, recipes, enemies, threat, purposes, routes) identical on 60 seeds; 300 seeds → 300 distinct floors (295 topologies); 100 depth-3 seeds → 100 distinct tactical layouts, 99 distinct rhythms, 17 compositions; depth-1 most common rhythm 3% |
| Golden seeds | 6 pinned fingerprints (generator **v5**, depths 1–3, tiles + tactical data + structure + decor) |
| Mutation tests (2.2) | Play-test polish: 8 more, all caught: contact never arms (3 contact checks), staggered bodies hurt (safe-to-touch check), no stagger guard (guard + group tests), no crowd steering (surround test), no brute armor, lint skips the fully dressed variant (2 lint negatives), alcoves cut into the lane (honesty: 3,111 rejected attempts; floors fail), decor ignores sockets (decor negative + goldens). Earlier: 19 protections from the first 2.2 pass, plus 6 for enemy placement (v4): runtime ignores the plan (3 checks fail), composer skips placement checks (honesty), validator skips spawn plans (3 negatives), planner ignores intents (planner unit test + golden), spitter uses the walking test for sight (smoke chasm test), ranged distance not enforced (negative + runtime check) |
| Performance | generation avg 77 / 122 / 139 ms at depths 1 / 2 / 3 (max per floor 162 / 233 / 427 ms; the 427 ms depth-3 floor is a single outlier, the budget is 250 ms average); depth-3 world ≤ 202 nodes (decor is 1 node), ≤ 289 wall shapes, build ≤ 121 ms |
| Rendered-frame review | Milestone 2/2.1 set, plus the depth-3 debug map (roles, threat, recipes, routes, rejected attempts), the tactical overlay on a guarded spike-ring cache, a sealed chasm fight with a brute, and (v4) the overlay's spawn plan on a sniper_nest water room (dashed line across the pool to the spitter) |
| Manual play-test | **pending** |
| Android device | not yet tested |

## Milestone 2.2 play-test polish — manual tests (user)

1. **Rooms aren't empty:** launch (F5). The entry hall has rubble heaps, broken pillars and floor marks
   around an open clearing. Walk several rooms: quiet rooms feel furnished; large fight rooms stay open
   arenas.
2. **Corridors:** long corridors have recesses (some with bones), collapsed rubble bays and torch
   sockets; the 3-wide lane is never blocked.
3. **Movement:** nothing snags you at doorways; no structure next to pits, water or spikes.
4. **Contact:** let a red chaser walk into you: 1 heart, a shove, a short blink. Four touching at once
   still cost one heart. Dodge through one: no damage during the dodge. A dimmed (recovering) or
   staggered enemy is safe to touch.
5. **No stun-lock:** keep swinging at a chaser: the first hit staggers it (white ring); then it fights
   through (gold spark) and strikes back. A brute's slow windup can't be interrupted.
6. **Groups:** a 3–4 enemy fight spreads around you; standing still and swinging costs real hearts,
   while moving and dodging the windups keeps you healthy. One chaser alone is still easy.
7. **Tactics still work:** spitter + pillars (break line of sight), brute + chasm (keep your back off the
   edge), F3/F4 debug views.
8. **Determinism:** REPLAY SEED gives identical rooms, rubble, alcoves and decor; NEW SEED differs.

## Milestone 2.2 manual tests (user)

Use a debug build (F5 from the editor). F3 = full debug map (roles, threat, recipes, routes), F4 = tactical
overlay in the world (role, threat/budget, recipe, the decision each room asks for).

1. **Room variety and rhythm (depth 1):** launch, press F3. The pacing line (top right) reads like
   ENTRY > HAZARD > COMBAT > STORY > COMBAT > REST > OBJECTIVE: never two fights in a row at depth 1, and
   every floor has a terrain lesson. NEW SEED a few times: the rhythm changes.
2. **Terrain lesson:** walk into the HAZARD room (green-grey floor). F4 shows its note, e.g. "Timed spikes:
   watch the warning bar and cross in the safe window."
3. **Recovery:** if the floor has a REST room (after a fight), take a hit, then touch the green SHRINE:
   +1 heart. At full health it says "the shrine will wait" and stays available.
4. **Route choice (depth 2 or 3):** start with `-- --seed=12345 --depth=3` (or NEXT DEPTH). F3 shows
   RISK_REWARD rooms with orange (risky) and green (safe) routes. In the room: the CACHE sits behind spikes
   (spike ring or chasm causeway) or in an alcove off a spiked wall gap. Ignore it and continue: the exit is
   reachable without touching the spikes. Take it: time the spikes (in the causeway, stay in the middle
   lane: the rising spikes push sideways toward the chasm).
5. **Open-door ambush (depth 2/3):** an AMBUSH room looks quiet; entering it spawns enemies with a telegraph
   and "AMBUSH! - the doors are open". Back into a doorway so they come one at a time, or run away (they
   give up after a while).
6. **Environmental combat (depth 3):** find a HAZARD_COMBAT room on F3.
   - `chasm_brawl`: the orange brute's slow blow throws you ~3 tiles; fight with your back to a wall,
     not to the chasm, and try knocking enemies in.
   - `spike_bait`: stand beside the spikes; lure chasers onto them as they rise (spikes hurt enemies too).
   - `wading_fight`: fight from dry ground. `sniper_nest`: cross between the spitter's shots.
7. **Ranged pressure + cover:** in a `pillar_skirmish` fight, the green spitter swells and shows an aim line
   before firing a slow shot; step behind a pillar and the shot breaks on it. Close in and it backs away.
   **Placement (v4):** with F4 on, the yellow dashed line shows where the lead enemy will start when you
   come in through the approach doorway. A `sniper_nest` spitter appears across the chasm/pool and
   shoots across it (it does not walk around); a `pillar_skirmish` spitter starts behind cover; a
   `chasm_brawl` brute starts at the chasm edge; `wading_fight`/`spike_bait` chasers start on the far
   side of the water/spikes. A spitter never starts close enough to hit you before you can react.
8. **Optional challenge:** a CHALLENGE dead end (red floor) holds an elite-placeholder fight (`elite_guard`
   at depth 2+) guarding a violet POWER socket. It is optional: skipping it never blocks the exit.
9. **Fairness spot-checks:** no spikes or pits near where you start; stepping through any doorway never lands
   you on spikes or at a pit edge; enemies never appear right next to you.
10. **Debug views:** TAC toggles the overlay; the F3 header shows floor threat / budget, and "rejected
    attempt N: ..." lines explain retries. The M map still shows only explored rooms, without roles.
11. **Determinism:** REPLAY SEED gives the identical roles, fights, caches and routes (compare F3).

## Milestone 2.1 manual tests (user)

1. Launch (F5). Walk the first few rooms. Look for interior walls, pillars and rubble: you can't walk
   through them, and every doorway still has a comfortable 3-tile approach.
2. Find a **water room** (blue pool, `water_chamber`). Walk into the water: you slow down noticeably and see
   a splash ring. Dodge in water: shorter, but still useful. Lure an enemy through water: it slows too.
3. Find a **pit room** (black drop with a tan lip, `pit_bridge_chamber`). Cross the bridge (3 tiles wide).
   Brush the edge: you don't fall. Walk into the pit: you take 1 damage, fall, and reappear on safe ground,
   briefly invulnerable. If a fight happens there, knock an enemy into the pit: it dies, and the room still clears.
4. Find a **trap gallery** (spike strips): the outline and warning bar should make the timing readable,
   and you can cross each strip in one safe window.
5. Fight near pillars: enemies walk around obstacles instead of pushing into them. Stand behind a pillar
   or wall: enemy attacks don't hit through it.
6. Press **M**: only visited rooms and corridors show, with stubs at unexplored doorways. Explore more and
   the map grows.
7. Press **F3** (or DBG): the full debug map shows every room, terrain, loops, the main path, and event
   sockets (the armed one highlighted).
8. Walk over the armed event socket (see the F3 map): "[debug] tension event socket fired (…)" appears once on the HUD.
9. Depth 1 pacing: the main path never has two red combat rooms back to back. Several rooms are quiet
   (environmental, reward or traversal).
10. REPLAY SEED: identical rooms, variants, water, pits and event socket. NEW SEED: different.
11. Repeat the Milestone 2 checks below briefly (locks, spikes, exit, seed panel, next depth).

## Milestone 2 manual tests (user)

1. Launch (F5). Check the HUD shows `DEPTH 1 (TEST PROFILE) | SEED n`, and that you start in the blue ENTRY hall.
2. Press **F3** (or DBG): the debug map shows entry, exit, story chamber, fights, branches, loops, and you (**M** is now the exploration map).
3. Walk out through a doorway: 3-tile corridors with turns lead to other rooms, and the camera follows smoothly.
4. Find a junction or a branch; take the optional path (purple rooms) to a dead end: a reward/lore marker (touch it) or an optional fight.
5. Enter a red-tinted room: the gates slam shut (red bars), spawn rings flash, enemies appear away from you
   and attack at once. Try to leave (blocked), win, and the gates open (green) and you can continue.
6. Pass through the teal story chamber (monument, placeholder label).
7. Look for spike traps: dark tiles that warn (red) and then raise; walk or dodge over them.
8. Reach the gold vault's EXIT → DEPTH 1 COMPLETE with stats.
9. REPLAY SEED → the same dungeon (compare with the map). NEW SEED → a clearly different one.
10. SEED panel: type `CRYPT` (or any number) → PLAY THIS SEED; RESTART CURRENT keeps it.
11. Die (let enemies win) → RETRY SEED keeps the same dungeon.
12. From DEPTH 1 COMPLETE, press NEXT DEPTH → depth 2 (bigger; the exit stays SEALED until the vault fight is won).
13. Optional: launch with `-- --seed=42` from the command line.

## Asset status

Everything is a placeholder: the runtime-generated TileSet (walls, corridors, role-tinted floors), `PlaceholderCircle`
actors, procedural gates, exit, markers, spikes and story monument, drawn UI, the default font, and the stock Godot icon.
No audio. No final assets exist yet.
