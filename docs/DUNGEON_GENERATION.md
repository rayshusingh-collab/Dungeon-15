# Dungeon generation (Milestones 2, 2.1 and 2.2)

This document covers how a depth is built from a seed, what the generator guarantees, and how to extend it.
The code lives in two folders:
- `src/dungeon/generation/`: pure data, testable headlessly.
- `src/dungeon/world/`: turns that data into nodes.

Milestone 2.1 added interior geometry, room variants, water, pits and bridges, authored spikes,
event/tension sockets, enemy pathfinding and the exploration map. Milestone 2.2 made the generator
reason about purpose and difficulty: room roles and pacing, tactical encounter composition under a
threat budget, hazards with a purpose, risk/reward routes, resource hooks and fairness validation
(sections "Room roles and pacing" onwards). Generator version: **3**.

The question behind every generated element: *why is this here, and what decision does it force?*
Difficulty comes from positioning, route choice, timing and enemy/terrain combinations, never from
inflated counts, invisible traps or unavoidable damage.

## Pipeline

```
RunConfig (run seed, depth)
  -> DepthProfile         data/depths/depth_NN.tres
  -> SeedStreams          named RNG streams for this (version, seed, depth, attempt)
  -> GraphBuilder         "graph": macro-grid topology
  -> PacingDirector       "pacing": a RoomRole per space (rhythm, neighbours, depth unlocks)
  -> LayoutBuilder        "templates", "variants" (per room), "layout", "corridors",
                          "corridor_dressing" (per corridor): templates by role and size by purpose,
                          tiles, rooms, corridors, corridor alcoves
  -> ContentPlacer        per room: "hazards" (purposeful), "dressing" (optional structure),
                          "spawns", "tactics" (TacticalComposer
                          recipe + enemies under the ThreatModel budget); per floor: "events";
                          DecorPlacer: "decor" (per room), "corridor_decor" (per corridor)
  -> DungeonValidator     reject anything unplayable or unfair (on the real tile geometry)
  -> (retry with attempt+1, up to 24) or safe failure
  -> DungeonBuilder       DungeonWorld nodes (tiles, merged wall collision, water/pit zones,
                          navigation grid, rooms, gates, markers, hazards, event triggers, exit,
                          one DecorLayer)
```

No stage after `DungeonValidator` makes decisions. The builder only instantiates, so the same
layout always builds the same world.

## Determinism contract

For the same **generator version + run seed + depth + profile data**, the whole dungeon is
identical: topology, room and variant choice, placement, corridors, terrain, encounters, enemy ids,
spawn candidates, hazards, markers, and event sockets (including which one is armed).

- Every random decision uses a `RandomNumberGenerator` from `SeedStreams.stream(name, index)`.
  The stream is seeded with `StableHash.hash62("dungeon15|v<GEN>|<seed>|<depth>|<attempt>|<name>|<index>")`.
  `StableHash` is FNV-1a written in GDScript, so it doesn't depend on Godot's `hash()`.
- **Streams are independent.** Changing how one stage draws numbers never changes another stage.
  Room content and room variants use per-room substreams (`"variants"`, `"hazards"`, `"spawns"`,
  `"tactics"`), so rooms don't affect each other. Tests: hazard density and the threat budget never
  change topology or room roles; the threat budget never changes hazards; each does change what
  it controls.
- **Never use the global `randi()`/`randf()` in generation.** The determinism tests disturb the
  global RNG between runs (layout fingerprint at depth 1, full tactical signature at depth 3).
  Mutation tests (variants, tactics) prove this catches global RNG use.
- **Bump `DungeonGenerator.GENERATOR_VERSION`** for any change that alters output for existing
  seeds: algorithms, template data, profile data, stream usage. `tools/generation_stress.gd` pins
  golden fingerprints (v5 values, depths 1-3) that fail if output changes silently. The fingerprint
  hashes the full tile grid plus roles, recipes, enemies, threat, hazard purposes and markers.
- Godot's `RandomNumberGenerator` (PCG32) is part of the contract.
- Runtime choices that depend on the player are not seeded:
  - Which seeded spawn candidates are used: `SpawnPlanner.plan` is a pure function of the room data
    and the point where the player triggered the room (deterministic for a given entry).
  - Enemy paths (they depend on where the player is).
  - Which rooms the exploration map has revealed.

Seed input: numbers are used directly; any other text is hashed (`RunConfig.parse_seed_text`).
Depth *n* of a run uses the same run seed with `depth = n`.

## Graph model (`DungeonGraph`)

Spaces live on a coarse macro grid, one space per cell.

| Role | Meaning |
|---|---|
| ENTRY | start of the main path; always safe |
| MAIN | main-path room; may hold a locking combat encounter |
| SPECIAL | reserved handcrafted room on the main path (exactly 2 links) |
| OBJECTIVE | end of the main path; holds the depth exit |
| BRANCH | off the main path, not a leaf |
| DEAD_END | branch leaf; always has a purpose (reward, lore, optional fight, future secret) |

Link kinds: MAIN, BRANCH, LOOP (an extra link that creates an alternative route).

`GraphBuilder` works in four steps:
1. **Main path:** a self-avoiding walk, with turn and outward biases and a minimum entry/exit distance.
2. **Special rooms:** claim fixed main-path fractions.
3. **Branches:** short walks from the main path or from other branches; their tips become dead ends.
4. **Loops:** optional extra links between adjacent MAIN/BRANCH/DEAD_END spaces.

## Spatial layout (`LayoutBuilder`)

- **Tiles:** 32 px. Corridors are `RoomShape.CORRIDOR_WIDTH` = 3 tiles (96 px) wide.
- **Template choice by RoomRole** (`RoomTemplate.suits`, "templates" stream):

  | Role | Pool | Variant filter |
  |---|---|---|
  | TRANSITION | `junction` | clean |
  | HAZARD | `environmental` (weight ×3) or the position pool (rooms whose `H` sockets become spikes) | terrain |
  | HAZARD_COMBAT | `arena` or the position pool, combat-capable | terrain |
  | RISK_REWARD | `risk` | terrain |
  | CHALLENGE | position pool, size class ≥ 1, combat-capable | clean |
  | COMBAT, AMBUSH | position pool (`main`/`branch`/`dead_end`), combat-capable | clean |
  | everything else | position pool | clean |
  | ENTRY / OBJECTIVE / STORY | their fixed pools | any |

  *Clean* variants have no pits, water or authored spikes (walls, pillars and rubble are fine;
  hazard sockets stay floor). *Terrain* variants have pits, water, spikes or hazard sockets. So
  dangerous terrain only appears where it is the point of the room. If nothing fits the door sides,
  the role is downgraded along a fixed chain (HAZARD_COMBAT/AMBUSH → COMBAT, CHALLENGE/RISK_REWARD →
  REWARD, REST → TRAVERSAL or REWARD, HAZARD/TRANSITION → TRAVERSAL): pacing only ever gets lighter.
- **Variant:** `RoomTemplate.pick_variant(streams.stream("variants", space.id), filter)`. Variants share
  size and door sockets with the base layout, so topology and corridors never depend on the variant.
- **Irregular macro grid:** cell size is the largest room + margins + random slack, and each room is
  jittered inside its cell.
- **Corridors:** straight, L or Z shaped, running from socket to cell boundary to socket. Tiles
  claimed twice are counted as `conflicts` and rejected.

## Terrain

| Tile | Class | Player | Enemies (navigation) | Validator |
|---|---|---|---|---|
| WALL, OBSTACLE (`O`), INNER_WALL (`I`), RUBBLE (`%`) | solid | blocked (collision) | solid | blocked |
| PIT (`P`) | blocking | falls: 1 damage, respawn on last safe ground | solid (lethal if knocked in) | blocked |
| WATER (`W`) | slow | 0.62× speed, dodge half affected | walkable, cost 2.0 | walkable |
| HAZARD (spikes, `^`/`H`) | timed | damaged only while raised | walkable, cost 2.5 | route-passable, strictly blocked |
| FLOOR, CORRIDOR, DOOR, BRIDGE (`=`) | plain | normal | normal (cost 1.4 next to solids) | walkable |

- **Solids** are batched into a single `StaticBody2D` with greedy-merged rectangles. That covers
  walls, pillars, interior walls and rubble.
- **Water** (`WaterZone`, one per room):
  - An `Area2D` registers with the body's `TerrainState` component, which scales speed.
  - It draws a splash ring when a body enters.
  - Water is always walkable: it slows you down but never blocks a route, so it can never softlock.
- **Pits** (`PitZone`, one per room):
  - A body falls only when its centre is 6 px inside a pit tile (edge forgiveness).
  - Player: 1 damage through the normal Hitbox → Hurtbox path, then a short fall animation, then a
    respawn at `Main`'s last safe position (ground that is strictly clear) with 1 s of invulnerability.
  - Enemies take lethal damage, so knocking them in works as a tactic and encounters still clear.
  - Pit edges bordering walkable ground are drawn as a light lip with a shadow band.
  - Pits never cut a required route. The validator treats them as solid.
- **Bridges** are plain walkable tiles, at least `MIN_BRIDGE_WIDTH` = 3 tiles (96 px, mobile
  friendly). The stress suite checks that every pit room keeps all its walkable sides joined.
- **Spikes** (`SpikeTrap`, one per connected region), cycling through three states:
  1. retracted
  2. warning, 0.6 s: region outline plus a warning progress bar
  3. raised
  - A region can never be larger than `MAX_TIMED_REGION` = 8 tiles in either direction, so it can
    be crossed in one safe window.
  - Spikes hit through the Hitbox → Hurtbox path, so invulnerability and dodge apply. They hurt
    enemies too (Milestone 2.2), so baiting enemies onto them is a tactic.
  - Line of sight is disabled for this hitbox, because the spikes are on the floor itself.
  - Spikes come from two sources:
    - authored (`^`): always placed (purpose `timing`, or `risk_route` in risk rooms).
    - optional sockets (`H`): filled only in terrain rooms (see "Hazards have a purpose").

## Room templates (`data/rooms/*.tres`)

A template is ASCII art plus metadata: `roles`, `size_class`, `weight`, `combat_allowed`,
`variant_layouts`, `variant_names`, and an optional `content_scene`.

```
Structure: #  wall     I  interior wall   O  pillar/obstacle   %  rubble   .  floor   (space) outside
Terrain:   W  water    P  pit             =  bridge            ^  authored spikes
Sockets:   D  door (3 in a row on the outer edge)   C  anchor (exactly one)   E  enemy spawn
           H  optional hazard   R  reward   L  lore   T  tension/event   +  prop   ?  secret
           $  risk cache (optional high-value reward behind a visible risk)
Dressing:  x  optional rubble / broken wall   o  optional pillar  (floor unless the room's
           "dressing" stream uses the region; see "Dungeon density")
```

**Template lint** (`RoomTemplate.lint()`, checked for every variant in the stress suite; failing
variants are also never picked):
- The anchor exists and is clear (all 8 neighbours are safe floor).
- At least one door socket; the tile behind each door is plain floor.
- E/R/L/T/$ sockets are clear.
- Every timed hazard region is ≤ 8 tiles.
- Pits and spikes are ≥ 2 tiles from every doorway.
- Bridges are ≥ 3 tiles wide.
- **Door approaches:** from the anchor, a player-sized body reaches every doorway. Interior walls,
  rubble, pits and water edges can never squeeze an approach below 3 tiles.
- All walkable tiles form one connected area.
- Every variant has the same size and door sockets as the base.
- **Fully dressed:** with every `x`/`o` socket solid, the variant still passes every rule above, and
  each socket is ≥ 2 tiles from doorway insides and never touches terrain or `H` sockets. Removing
  structure never breaks connectivity or clearance, so any subset the generator picks is safe.

| Template | Size | Pools | Variants |
|---|---|---|---|
| `entry_hall` | 26×16 | entry | – |
| `chamber_small` | 12×10 | main, branch, dead_end | open, center block |
| `room_medium` | 18×12 | main, branch, dead_end | spike socket, split wall, pillar lanes |
| `chamber_large` | 26×16 | main | pillar hall, inner sanctum, ruined hall |
| `hall_narrow` | 24×9 | main, branch | open hall, cover pillars |
| `room_l_shape` | 20×16 | main, branch, dead_end | – |
| `junction_cross` | 11×11 | junction, branch (no combat) | – |
| `junction_hall` | 15×15 | junction, branch (no combat) | – (3×3 central obstacle) |
| `pit_bridge_chamber` | 22×14 | environmental, arena | single bridge, twin bridges |
| `water_chamber` | 20×14 | environmental, arena, branch | open pool, rubble island |
| `trap_gallery` | 24×9 | environmental, branch (no combat) | twin spike strips, baffled strips |
| `risk_cache` | 18×16 | risk (no combat) | spike ring, chasm causeway |
| `risk_shortcut` | 24×14 | risk (no combat) | wall gap, flooded bypass |
| `objective_vault` | 20×14 | objective | – |
| `story_chamber` | 22×14 | special (no combat) | – |

In total there are 15 templates and 26 distinct layouts; the stress run uses all of them at depths 2-3.

## Dungeon density (M2.2 play-test polish, generator v5)

The play-test found rooms and corridors empty: big plain floors and long bare 3-wide corridors. Density
comes from composition with rules, never from clutter that blocks play.

- **Structure** (`ContentPlacer._place_dressing`, "dressing" stream per room): each `x`/`o` region of
  the variant is used with `RoomRole.dressing_density(role)` (one draw per region):

  | Roles | Density | Why |
  |---|---|---|
  | traversal, transition, exploration | 0.85 | quiet spaces read as ruins |
  | entry, reward, rest | 0.75 | furnished, with the spawn clearing open |
  | ambush | 0.65 | cover and funnels |
  | combat, objective, challenge | 0.5 | open arena for maneuvering |
  | hazard, hazard fight | 0.3 | hazards must read clearly |
  | risk, story | 0 | clean risk routes, authored content |

  A region is refused if it would touch terrain, or, in a fight room, if it would cut clear floor below
  `MANEUVER_BASE + MANEUVER_PER_ENEMY × enemies_by_size[size]`. The template lint already guarantees
  doorways, lanes and sockets for any subset, so no flood fill is needed here.
- **Room size by purpose** (`RoomRole.size_weight`, applied to template choice): traversal, exploration,
  reward and rest prefer small rooms (large ×0.3); fights prefer space (large ×1.3).
- **Corridor alcoves** (`LayoutBuilder._dress_corridor`, "corridor_dressing" stream per corridor):
  - For each straight segment ≥ 9 tiles: one chance per 6 tiles (85%) of a 3-tile recess, 1–2 deep,
    on a random side, kept 4 tiles from the segment ends.
  - Kinds: **nook** (floor; a future environmental-storytelling spot, gets remains) or **collapse**
    (floor, then rubble against the outer wall).
  - Carved only where everything within 2 tiles is void or the lane itself, so it touches no other
    room or corridor. The lane is never altered. Every draw happens whether or not an alcove fits.
- **Decor** (`DecorPlacer`): non-colliding, seeded, validated.
  - Floor marks (crack, stones, bones) at 5% of floor tiles: ×1.3 in quiet rooms, ×0.5 in terrain
    rooms, none in story rooms; no bones in rest rooms. Corridors get 3.5%.
  - Remains in 70% of nooks.
  - Torch sockets on walls beside floor (12% per wall tile, ≥ 8 tiles apart, not beside doorways).
  - Never on terrain or next to it, never on a socket (anchor, spawn, exit, markers, spawn candidates,
    event sockets), never within the doorway approach.
  - `DecorLayer` draws everything in one static canvas item; art replaces it later.
- Measured (stress suite):
  - open-field floor (7×7 empty windows) about 13% → 5%; entry hall 43% → 6%
  - ~18 structure pieces, ~5–7 alcoves and ~150–200 decor items per floor
  - quiet rooms use more of their sockets than fight rooms

## Room roles and pacing (`RoomRole`, `PacingDirector`)

Every space gets a role before templates are chosen ("pacing" stream):

| Role | Purpose | Encounter |
|---|---|---|
| ENTRY | safe start | – |
| TRAVERSAL | quiet passage | – |
| TRANSITION | junction between routes (3+ links) | – |
| EXPLORATION | lore or a future-secret sign | – |
| COMBAT | locked fight in a clean arena (cover only) | COMBAT (locks) |
| HAZARD | terrain challenge (timing, crossing, flooded floor) | – |
| HAZARD_COMBAT | locked fight where the terrain matters | COMBAT (locks) |
| AMBUSH | fight triggered mid-room, doors stay open, ≥ 2 exits | AMBUSH (never locks) |
| REWARD | optional reward | – |
| RISK_REWARD | cache behind a visible risk; a safe route always exists | – |
| REST | recovery shrine after a fight | – |
| STORY | reserved special room | – |
| CHALLENGE | optional elite-placeholder fight guarding a power socket | OPTIONAL (locks) |
| OBJECTIVE | depth exit (sealed by a fight if the profile says so) | COMBAT or – |

Director rules (main path, entry to objective, reading the sequence so far):
- at most `max_consecutive_combat` fights in a row; **the objective fight counts** (the space right
  before it sees one fight less), so combat → combat → combat never happens at max 2;
- at most `max_consecutive_terrain` terrain challenges (HAZARD, HAZARD_COMBAT, RISK_REWARD) in a row;
- no role three times in a row (junction rolls included);
- REST only right after a fight, at most `max_rest_rooms` per floor;
- after two quiet rooms, fights are twice as likely (uncertainty → release);
- top-ups: `min_combat_rooms` fights and `min_terrain_rooms` terrain lessons, using only spaces that
  keep the rhythm. Floors that still fall short are rejected by the validator and regenerated.

Branches read their neighbours: next to a fight, fight roles are weighted ×0.25; a REST is only placed
next to a fight and never next to another REST; an AMBUSH needs ≥ 2 links. Dead ends always get a
purpose (reward, lore, secret, risk cache, challenge, recovery).

Weights per position (`main_role_weights`, `branch_role_weights`, `dead_end_role_weights`) come from the
depth profile; a role without weight never appears, which is how depths unlock mechanics. The
director's own output is unit-tested (before any validation) so it never relies on retries.

The armed tension event is placed, when possible, in a quiet socket right before a fight (a main-path
room whose next room is a fight, or a corridor opening into one): uncertainty → combat.

## Tactical composition (`TacticalComposer`, "tactics" stream per room)

A fight is built from a **recipe**: enemy roles, the room features it needs, and the decision it forces.

| Recipe | Roles | Needs | Core + fill | Decision |
|---|---|---|---|---|
| `open_brawl` | combat, objective, ambush, challenge | – | 2 chasers + chasers | keep moving, don't get surrounded |
| `pillar_skirmish` | combat, objective, challenge | cover | spitter, chaser + chaser/spitter | break line of sight behind pillars |
| `choke_hold` | combat, objective | narrow hall | brute, chaser + chaser | don't get pinned in the lane |
| `chasm_brawl` | hazard fight | pit | brute, chaser + chaser | keep your back from the chasm, knock them in |
| `ledge_fight` | hazard fight | pit | 2 chasers + chaser | dodge along the edge, not toward it |
| `spike_bait` | hazard fight | spikes | 2 chasers + chaser | lure them onto rising spikes |
| `wading_fight` | hazard fight | water | 2 chasers + chaser/brute | hold dry ground |
| `sniper_nest` | hazard fight | pit or water | spitter, chaser + spitter | cross between shots |
| `ambush_pincer` | ambush | – | 2 chasers + chaser/spitter | funnel them in a doorway, or run |
| `elite_guard` | challenge | – | brute, chaser + chaser/spitter | optional: skip it if hurt |

- A recipe applies only if the depth allows it (`tactical_recipes`), its core enemies are in the
  depth's `enemy_pool`, the room's role matches and the room has the features it needs (measured on
  the tiles: cover = pillars/inner walls/rubble, pit, water, spikes, narrow ≤ 9 tiles).
- Order: recipes dedicated to the role (ambush, challenge, every hazard-fight recipe) first; among the
  rest, feature-specific recipes are twice as likely as the open brawl. Later recipes are fallbacks.
- Filling: the core enemies must fit; then fill enemies are added while the ThreatModel score stays
  under a seeded target (75-100% of the budget), and the count stays within the capacity:
  `min(enemies_by_size[size], maneuver capacity, far spawn points behind every doorway)`.
- Placement (`placement_ok`): a recipe (or a fill enemy) is accepted only if `SpawnPlanner` can place
  every enemy fairly from **every** doorway, there is no ranged crossfire in a room without cover, and
  the recipe's tactic is **realized from the approach doorway** (see below). A recipe that would only
  be a label is skipped and the next one tried.
- Budget = the role's budget, reduced to what is left of the floor budget (main path first).

### Enemy placement (`SpawnPlanner`)

A recipe only matters in play if its enemies start where the geometry matters. `SpawnPlanner.INTENTS`
gives the recipe's **lead** enemy of a type (its first occurrence) a placement intent, judged on the
straight line from where the player triggers the room:

| Recipe | Lead | Intent | Meaning |
|---|---|---|---|
| `pillar_skirmish` | spitter | screened | a pillar/wall breaks its sight line: you enter in cover |
| `sniper_nest` | spitter | across | pit or water lies between you, nothing solid: it has a clear shot you can't rush |
| `chasm_brawl` | brute | ledge | starts within 3 tiles of the chasm |
| `ledge_fight` | chaser | ledge | starts within 3 tiles of the chasm |
| `wading_fight` | chaser | wade | must cross water to reach you |
| `spike_bait` | chaser | bait | must cross the spikes to reach you |

- `plan(layout, room, from)`: intent enemies take the first seeded candidate that satisfies their
  intent and distance; the others take the next fair candidates; a last-resort fallback uses the
  farthest remaining candidates (validation prevents needing it).
- Fairness: every enemy ≥ 150 px (`MIN_SPAWN_DISTANCE`) from the player; ranged enemies ≥ 224 px
  (`RANGED_MIN_DISTANCE`: time to read the telegraph and reach cover); at most one ranged enemy in a
  room without cover.
- The **approach doorway** is the one whose link leads toward the entry (fewest rooms; ties by link
  id): where the player normally arrives. Tactics are guaranteed from there; from other doorways
  they hold in 93-100% of cases (stress-suite measurement) and fairness always holds.
- The same function runs at generation (composer, validator, tests) and at runtime
  (`DungeonRoom.choose_spawn_points`), so play matches what was validated.
- Sight: spitters decide whether they can shoot with `DungeonNavigation.clear_sight` (only solids
  block it; pits and water don't, and projectiles fly over them), not with the walking test
  `line_of_sight`. Both the planner and `clear_sight` use `DungeonLayout.segment_hits`, sampled every 8 px.
- Placeholder archetypes (EnemyCatalog, tags feed the recipes): **chaser** (melee, pursuit, threat 2),
  **brute** (melee, knockback ×2 ≈ 3.4 tiles, blocking; threat 3), **spitter** (ranged, area denial;
  threat 2.5). They exist to make the composition logic real, not as the final roster.

## Threat model (`ThreatModel`)

Every room gets a deterministic, explainable score (`ThreatModel.explain` lists each contribution;
the F4 overlay and F3 map show score/budget):

| Contribution | Weight |
|---|---|
| each enemy | its catalog threat (chaser 2, brute 3, spitter 2.5) |
| knockback enemy + pit in the room | +1.0 each |
| ranged enemy without cover | +0.75 each |
| melee enemy + water | +0.25 each |
| locked doors (no retreat) | +0.5 |
| spike areas in a fight | +0.75 each |
| pit in a fight | +0.5 |
| cramped arena (< 14 strict-clear tiles per enemy) | +1.0 |
| timed spike areas without enemies | +0.5 each |
| chasm crossing without enemies | +0.5 |
| risk area | +0.75 each |

Budgets per role come from the depth profile: fights `room_threat_budget` (ambush ×0.8, challenge
×1.3), quiet rooms `quiet_room_threat_cap`, risk rooms `risk_room_threat_cap`, entry/rest/reward/story
0, and the whole floor `floor_threat_budget`. The composer builds under the budget; the validator
recomputes the score independently and rejects any room or floor over budget, or a recorded score
that does not match. Budgets are a ceiling, not a target to fill ("fair challenge, not forced failure").

## Hazards have a purpose

| Purpose | Where | Why it is there |
|---|---|---|
| `timing` | authored spikes in HAZARD rooms (trap galleries) | cross in the safe window; may be on a required route (always ≤ 8 tiles, always telegraphed) |
| `route_shaping` | `H` sockets in HAZARD rooms (density, at least one if the room has no other terrain) | split lanes, shape where you walk |
| `area_denial` | every safe `H` socket in HAZARD_COMBAT rooms | fight around them, bait enemies onto them |
| `risk_route` | authored spikes in RISK_REWARD rooms | guard the cache / the shortcut; **never required** |

Every other role places no hazards at all (sockets stay floor). A hazard whose purpose is not allowed
for its room's role is rejected by the validator. If a terrain room's only terrain was sockets that
all had to be refused (unsafe), the room is downgraded (HAZARD → TRAVERSAL, HAZARD_COMBAT → COMBAT);
`planned_tactic` keeps the original role for the debug views.

## Risk / reward routes

Risk templates put a `$` cache behind visible spikes:
- `risk_cache` spike ring: the cache stands in a 3×3 pocket inside a 7×7 spike ring (guarded; the
  safe way round leads past it). Chasm causeway: the cache stands on an island in a pit, reached by a
  3-wide spiked causeway (rising spikes can push you sideways toward the chasm: stay in the middle).
- `risk_shortcut` wall gap: a 6-long spiked gap through an interior wall is the short way between the
  room's halves and leads to an alcove with the cache; the safe route goes round the wall (in the
  flooded bypass variant, through slow water).

Guarantees: the **required** mask (route mask minus every risk tile) must carry every required route
(entry → exit, every room, every corridor, every doorway → anchor), so a risk is never mandatory. The
cache must be reachable through the risk (route mask). `ContentPlacer` records the shortest risky and
safe routes to the cache (`risk_route`, `safe_route`; empty safe route = guarded); the stress suite
checks the risky route is shorter than the safe one, or the only way.

## Resource hooks

Markers that make health and rewards matter later: **heal** (REST rooms; restores 1 heart, not consumed
at full health), **cache** (risk rooms; placeholder high-value reward), **power** (challenge rooms;
future power-up socket), plus reward/lore/secret/story as before. Payloads beyond the heal are
Milestone 3+.

## Encounters (runtime)

- Enemy counts come from composition under the budget and the size cap; they are **never scaled by
  progress**. Spawn candidates are the template's `E` tiles that stay strictly clear after hazards.
- Locked fights (`DungeonRoom`): DORMANT → ACTIVE (gates lock, telegraphed spawns at least 150 px from
  the player, enemies never leash) → CLEARED.
- Ambushes: DORMANT → ACTIVE without gates; enemies spawn with the same telegraph and distance rule but
  keep their leash, so retreating through another exit is a real option.
- The validator measures spawn distance from each doorway's inside tile with a 48 px margin (198 px):
  a player walking in touches the encounter trigger about 30 px past that tile (player radius 18 px,
  trigger inset 2 tiles), so the 150 px runtime guarantee holds for any entry through a doorway.

### Enemy navigation

`DungeonNavigation` is an `AStarGrid2D` over the layout, built once per floor (a few ms per floor,
at most ~65 ms at depth 2).
- **Walls, pillars, rubble and pits are solid.** Water and spikes cost more, and tiles next to a
  solid cost a little more.
- Enemies steer straight when `line_of_sight` passes (it is tested with the actor's half-width).
  Otherwise they follow a grid path, re-planned every 0.3 s.
- Enemies start an attack only with line of sight to the player.
- Every `Hitbox` casts a ray on the wall layer before dealing damage, so nothing hits through walls
  or pillars.

## Sockets and events

| Socket | Used for |
|---|---|
| `E` | enemy spawn candidates |
| `H` / `^` | optional / authored spikes |
| `R`, `L`, `?` | reward (also heal in REST, power in CHALLENGE rooms) / lore / secret markers (fall back to the anchor if missing) |
| `$` | risk cache |
| `+` | `prop_sockets`: reserved decoration points for later art (no gameplay) |
| `T` | tension/event sockets |

**Event (tension) sockets:**
- Candidates: every `T` tile in rooms, plus the middle tile of every corridor.
- Per floor, `profile.armed_event_count` (1) of them is armed. The seeded `"events"` stream picks
  among sockets in quiet rooms (TRAVERSAL, TRANSITION, EXPLORATION, HAZARD, REWARD) or corridors,
  preferring one right before a fight; never in fights, the entry or the exit.
- The builder places an `EventTrigger` (radius 56 px, fires once) on each armed socket.
- `DungeonWorld.tension_event` fires once. In debug builds, `Main` shows it as HUD text.
- This is the hook for later thriller moments (sounds, lights, scripted scares). There is no final
  content yet.

## Exploration map

`DungeonMap` has two modes:
- **EXPLORATION** (the player's map, the MAP button):
  - Only rooms and corridors the player has entered are drawn.
  - Discovery comes from `Main._physics_process`, via the tile owner under the player.
  - Revealed rooms show stubs for their doorways, so unexplored exits are visible. Cleared rooms are
    marked.
- **DEBUG_FULL** (development only, F3 or the DBG button; debug builds only):
  - Shows all geometry and terrain.
  - Per room: role, threat/budget, enemy letters (C chaser, B brute, S spitter), recipe or variant,
    and the planned role if it was downgraded.
  - Overlays: loops, the main path, event sockets (armed ones highlighted), risk tiles, risky
    (orange) and safe (green) routes to caches, markers, and a legend.
  - Notes: floor threat vs budget, the main-path rhythm, and why earlier attempts of this seed were
    rejected (the generator's failure log).

The map renders into a single image texture, one pixel per tile. The player map never shows roles.

**Tactical overlay** (`TacticalOverlay`, F4 / TAC, debug builds only): the same design data drawn in
the world over each room ("situation: advice" note, hazard purposes, risk tiles, routes, spawn points,
and in yellow the spawn plan from the approach doorway: an enemy letter per start tile, a dashed line
to each lead enemy placed for the terrain, and a "from the approach: S across" line),
for play-testing why a room is the way it is.

## Validation rules (`DungeonValidator`)

Three player masks are built from the real tile grid:
- **Strict** (spikes blocked). Used for: the player spawn, the exit, enemy spawns, markers and event
  sockets.
- **Route** (spikes crossable, because regions are ≤ 8 tiles). Used for: reaching a risk cache.
- **Required** (route minus every risk-route tile). Used for: every required route, so an optional
  risk can never be mandatory.

"Clear" means the tile is walkable in that mask and all 8 of its neighbours are too (a player-sized
body fits). Pits and all solids are always blocked. Water and bridges are walkable.

The validator checks:
- **Graph:** exactly one entry and one objective; a consecutive main path; every space connected;
  required special rooms present.
- **Rooms:** inside the map; no overlap or touching; no carve conflicts; every link has a doorway in
  both rooms.
- **Reachability:** from the player spawn, required-clear tiles reach the exit and **every** room. The
  spawn and the exit are strictly clear.
- **Corridors:** each link's corridor is required-traversable between its doorways.
- **Room interiors:** every doorway reaches the anchor inside the room ("cut off inside the room"),
  and the walkable floor is one piece. This catches pits cutting a room, removed bridges, and
  interior walls blocking doorways.
- **Hazards:**
  - every HAZARD tile belongs to a listed hazard
  - no hazard on a doorway or the anchor
  - ≥ 2 tiles from doorways
  - every region ≤ 8 tiles ("too long to cross in one safe window")
- **Pits:** ≥ 2 tiles from doorways.
- **Encounters:**
  - enemy ids exist
  - spawns are strictly clear, inside the room, and reachable by enemies
  - behind **every** doorway there are enough spawns ≥ 198 px away
  - spawn plan (`SpawnPlanner`) from every doorway's trigger point: every enemy placed ≥ 150 px
    away, ranged ≥ 224 px ("unavoidable shot"); ≤ 1 ranged enemy without cover ("crossfire"); the
    recipe's intents realized from the approach doorway ("where the terrain matters")
- **Markers and event sockets:**
  - clear and reachable (a risk cache: reachable through its risk)
  - event sockets sit inside their room or corridor
  - no event socket overlaps the spawn, the exit or a marker
- **Tactical fairness (Milestone 2.2):**
  - spawn safety: no enemies in the entry, no hazard or pit within 4 tiles of the player spawn
  - room entries: the first two tiles inside every doorway are strict-clear (no unavoidable damage
    right after entering)
  - hazard stacking: hazard + pit tiles ≤ 45% of a room's floor; every spike tile has safe footing
    within 4 tiles
  - roles fit their graph place and are allowed at the depth; encounters match roles; quiet rooms have
    no enemies; pits/water/spikes only in terrain roles, and terrain roles have terrain
  - every hazard's purpose is allowed for its room's role
  - role rules: ambush ≥ 2 exits (escape route); rest room has a heal socket and no hazards/enemies;
    risk room has a cache, a visible risk and a reachable cache; hazard fight uses a terrain recipe;
    challenge guards a power socket; reward room has a reward; recipes exist
  - threat: recomputed score equals the record; room ≤ its role budget; floor ≤ floor budget
  - maneuvering space: ≥ 16 + 8 × enemies strict-clear tiles in every fight room
  - pacing on the main path: fight runs, terrain runs, no triple role, rest after a fight, rest count,
    min fights, min terrain lessons

- **Density (v5):** structure only where its role furnishes rooms, solid where recorded, ≥ 2 tiles from
  doorway insides, never touching terrain; every corridor lane tile is open corridor and alcoves lie
  outside it; decor torches on walls, floor marks off terrain, sockets and doorway approaches.

Failure → next attempt. After 24 attempts generation fails safely: "GENERATION FAILED" with a
NEW SEED button.

`ContentPlacer` runs the same kind of check before it keeps an optional hazard
(`hazard_keeps_room_intact`):
- the region is ≤ 8 tiles
- the anchor, the tiles just inside doorways, and the R/L/T sockets stay clear
- doors still connect to the anchor
- the floor stays one piece

If any of these fail, the hazard is reverted. A hostile fixture at density 1.0 proves the refusal
works.

## Depth profiles

`data/depths/depth_NN.tres` (`DepthProfile`) holds:
- `design_goal` (what the depth teaches) and `theme_id`
- grid and topology settings
- template pools and special-room rules
- pacing: role weights per position, `junction_chance`, `max_consecutive_combat`,
  `max_consecutive_terrain`, `max_rest_rooms`, `min_terrain_rooms`, `min_combat_rooms`
- encounters: `objective_encounter`, `enemy_pool`, `enemies_by_size` (hard cap), `tactical_recipes`
- threat budget: `room_threat_budget`, ambush/challenge scales, quiet and risk caps, `floor_threat_budget`
- hazard density and types, `armed_event_count`

There is no per-depth branching in code. Depths 1-3 are **test** profiles.

### Depth progression philosophy

Each depth keeps everything earlier depths taught and adds mechanics, with a larger budget; enemy
counts per room size do not grow (the stress suite checks both):

| Depth | Goal | Unlocks |
|---|---|---|
| 1 | teach movement, reading terrain, simple melee fights with relief | combat, hazard, rest, challenge (open brawl) |
| 2 | basic route decisions | risk rooms, open-door ambushes, elite challenges, the brute (choke/elite only) |
| 3 | hazard + enemy interaction | hazard fights (chasm, ledge, spike bait, wading, sniper), the spitter, all recipes |
| 4-6 (target) | complex positioning, environmental combat combinations | more recipes combining two features, mixed ranged + knockback |
| 7-10 (target) | deliberate multi-step encounters and route decisions | multi-room set pieces, stacked (validated) interactions |
| 11-14 (target) | mastery of learned mechanics | tighter budgets per role, fewer rests, harder risk rooms |
| 15 (target) | final exam of the dungeon's rules | reserved (the Queen/King and the ending are not designed yet) |

Measured on generated floors (stress suite): depth 1 uses 1 recipe (0% room-specific fights), depth 2
uses 4 (33%), depth 3 uses 10 (79%); max 3 / 3 / 4 enemies per fight.

## Performance (desktop, headless)

| | Depth 1 | Depth 2 | Depth 3 |
|---|---|---|---|
| Generation + validation (avg) | ~77 ms | ~122 ms | ~139 ms |
| Generation + validation (max) | ~162 ms | ~233 ms | ~427 ms (one outlier) |
| Attempts (avg) | 1.3 | 1.8 | 1.9 |

- Budget: 250 ms average. Generation runs once, at depth start. Generator v4 enemy placement
  (`SpawnPlanner`, judged from every doorway in the composer and the validator) costs ≤ ~10 ms per floor
  in A/B runs (within run-to-run noise); its line tests are bit-mask lookups with no allocation.
- Milestone 2.2 optimisations: clearance masks are built with a lookup table and a separable 3×3 test
  (~4.5 ms instead of ~16 ms); one strict mask is shared by all rooms' feature measurements; variant
  terrain classification is cached per shape; risk-route searches are bounded to the room.
- A built depth-3 world has ≤ 275 nodes and ≤ 268 merged wall shapes, and builds in ≤ 131 ms. The
  navigation grid is the largest part (≤ 72 ms).
- Water and pit zones process only while a body overlaps them.
- Enemies re-path at most every 0.3 s and only while chasing. Rooms without an active encounter
  have no enemies.

## Extending

- **New room layout or variant:**
  1. Add it to `data/rooms/<id>.tres` (variants go in `variant_layouts` + `variant_names`).
  2. Add it to a profile pool.
  3. Run the stress suite. Lint rejects bad geometry.
  4. Bump `GENERATOR_VERSION` and re-pin the golden seeds if an existing profile uses it.
- **New terrain:**
  1. Add a `RoomShape.Cell`, a `DungeonLayout.Tile`, a `LayoutBuilder.tile_for_cell` mapping and a
     tileset look.
  2. Classify it in `is_walkable_kind` / `is_solid_kind` and in `DungeonNavigation`.
  3. Add a builder zone if it has runtime behaviour.
  4. Add validator negatives and a mutation test.
- **New hazard type:** add a builder mapping (like `spikes` → `SpikeTrap`) and keep the "room stays
  intact" rule. Give it a purpose and allow that purpose only in the roles where it makes sense
  (`RoomRole.allowed_purposes`).
- **New enemy archetype:** a scene + an `EnemyCatalog` entry (threat, tags, letter); add interaction
  weights to `ThreatModel` if it combines with terrain; use it in recipes; add it to profiles'
  `enemy_pool`.
- **New recipe:** add it to `TacticalComposer.RECIPES` (roles, needs, core, fill, note), enable it in
  profiles' `tactical_recipes`; the stress suite fails if an enabled recipe never appears.
- **New room role:** add it to `RoomRole` (name, heavy/terrain classification, encounter, allowed
  purposes), the director's weights, `RoomTemplate.suits`, the builder's floor look and the validator's
  role rules, with a negative test.
- **New event content:** listen to `DungeonWorld.tension_event(trigger)` (the trigger carries its tile and kind). Don't add a new
  trigger mechanism.
