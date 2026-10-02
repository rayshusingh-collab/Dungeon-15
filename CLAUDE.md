# Dungeon15 — Claude Code guide

Top-down 2D mobile (Android-first) dungeon roguelite. Defining feature: deterministic
seeded procedural generation. Godot **4.7.2**, GDScript, `gl_compatibility` renderer.

Live status, architecture, decisions, and known bugs are tracked in **DEVELOPMENT.md**; read it
at the start of a session and update it when meaningful work lands.

## Commands

```sh
GODOT="/c/Users/raysh/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"

# 1. Import / re-scan (registers class_name globals, generates .uid files). Grep for errors.
"$GODOT" --headless --path . --import 2>&1 | grep -iE 'error|warn'
# 2. Boot the main scene headlessly (parser, resource, node-path, startup errors)
"$GODOT" --headless --path . --quit-after 300
# 3. Smoke/integration tests (exit code 1 on failure). --fixed-fps makes every frame exactly 1/60 s.
"$GODOT" --headless --fixed-fps 60 --path . --script res://tools/smoke_test.gd
# 4. Generation stress suite (~5 min; 1,500 floors over depths 1-3, determinism, golden seeds,
#    traversal, navigation, tactics). Append `-- --quick` for a ~3 min sample (used for mutation tests).
"$GODOT" --headless --fixed-fps 60 --path . --script res://tools/generation_stress.gd
# Play a specific seed/depth:
"$GODOT" --path . -- --seed=12345 --depth=1
```

Run 1–3 after meaningful changes, and 4 after any generation/template/profile change. Look at the output, not just the exit code: `--quit-after`
exits 0 even when scripts fail to parse. Extend `tools/smoke_test.gd` when adding systems that can be
checked automatically. Test functions return `true` at the end. The harness fails any test that aborts
or logs an engine/script error or warning. Passing automated checks is **not** proof that gameplay feels
right; the user does the gameplay testing.

To visually check placeholder presentation, drive a scripted scenario (a throwaway `SceneTree` script)
with Movie Maker (not headless; it opens a window) and read the PNGs:
`"$GODOT" --path . --fixed-fps 60 --write-movie <scratch>/f.png --script res://tools/_scenario.gd`.
Delete the throwaway script afterwards. To compare frames, build a contact sheet with a throwaway Godot
script (`Image.load_from_file` + `blit_rect` + `save_png`); there is no Python/ImageMagick on this machine.

`--import` runs editor code, which can rewrite files (for example, it converted a space-indented
script to tabs). Check `git status` afterwards.

## Project layout

Feature folders under `src/`. Each scene sits next to its script.

- `src/main/`: `Main`, the run orchestrator (RunConfig → generate → build → signal wiring)
- `src/core/`: `RunConfig` (seed/depth across reloads, command line), `StableHash`
- `src/dungeon/generation/`: **pure-data** generator (graph, pacing director/room roles, layout,
  content, tactical composer, threat model, validator), headless-testable
- `src/dungeon/world/`: `DungeonBuilder` → `DungeonWorld` nodes (rooms, gates, exit, markers, hazards,
  water/pit zones, event triggers, `DungeonNavigation`)
- `src/player/`, `src/enemies/`: actors (`EnemyCatalog` maps generation ids to scenes)
- `src/components/`: reusable gameplay components (`HealthComponent`, `Hitbox`, `Hurtbox`, `MeleeAttack`, `HealthBar`, `TerrainState`)
- `src/effects/`: cosmetic-only effects (`AttackArcEffect`, `BurstEffect`)
- `src/camera/`: `GameCamera` (follow, bounds, kick/shake)
- `src/ui/`: HUD, debug map, seed panel, touch controls
- `data/rooms/`, `data/depths/`: room templates (ASCII) and depth profiles
- `docs/DUNGEON_GENERATION.md`: generation design and **determinism contract** — read before touching generation
- `tools/`: test harness + suites (not shipped gameplay)

## Rules

- Work milestone by milestone (see DEVELOPMENT.md). Keep the project playable. Stop for review at
  milestone boundaries.
- Inspect before changing; don't blindly rewrite. Delete obsolete files only after confirming
  they're unused (grep for `res://` paths and class names).
- No god scripts. Prefer small scenes/components with typed GDScript (`class_name`, typed vars,
  `-> void`). Use tabs for indentation.
- Gameplay reads **InputMap actions only** (`move_left/right/up/down`, `attack`, `dodge`). Touch
  controls press those actions and must not be referenced by gameplay code.
- Damage always goes Hitbox → Hurtbox → HealthComponent. Don't add ad-hoc `take_damage` paths.
  Actors react to component signals. UI, camera and controls are driven by Main from signals and never
  reach into gameplay nodes.
- Spawn transient effects into the world (`BurstEffect.spawn(get_parent(), ...)`), not as children of
  moving actors. Create tweens on the node they animate.
- Hit-stop is owned by `Main.hit_stop()` and works through `Engine.time_scale`. Gameplay timers and tweens
  should slow with it. UI feedback that must stay real-time uses `create_tween().set_ignore_time_scale(true)`.
  Anything that frees the scene must leave `Engine.time_scale` at 1.0 (the smoke harness checks this).
- Combat-feel values (windups, lunges, knockback, hit-stop, camera kick) are `@export`s. Tune them there,
  not with literals.
- Visuals are placeholders (`PlaceholderCircle`, `ColorRect`). Never couple gameplay logic to them.
  Art must be swappable without touching gameplay.
- Sub-resources (shapes, materials) must not be shared across instances that are configured
  independently. Call `duplicate()` before mutating a shared resource at runtime.
- Physics layers: 1 `world`, 2 `player`, 3 `enemies`, 4 `player_hurtbox`, 5 `enemy_hurtbox`
  (named in project.godot). Hitboxes scan the opposing hurtbox layer only.
- Determinism: all generation draws from `SeedStreams.stream(name, index)` RNGs, never the global
  `randi()`/`randf()` (cosmetic-only randomness such as camera shake is the exception). New stages
  or per-room content get their **own named stream** so they don't reshuffle existing output. Any
  change that alters output for existing seeds (algorithm, stream use, template or profile data)
  requires bumping `DungeonGenerator.GENERATOR_VERSION` and re-pinning the golden seeds in
  `tools/generation_stress.gd`. Never "fix" a golden failure by just updating the value.
- Generation decisions live only in `src/dungeon/generation/`. Scene/world code instantiates and
  never decides. Every floor passes `DungeonValidator`; never accept or build a layout with errors.
- Geometry comes from template ASCII only. Authored `content_scene`s must not add collision.
  Hazards (and future terrain) must never block required routes or split a room: the placer
  reverts them and the validator treats hazards as blocked.
- Terrain classes (see docs):
  - solid: WALL / OBSTACLE / INNER_WALL / RUBBLE
  - blocking: PIT (validated as a wall; falling is a penalty, never a softlock)
  - slow: WATER (always walkable)
  - timed: spikes (each region ≤ `RoomShape.MAX_TIMED_REGION`)
  - plain: FLOOR / CORRIDOR / DOOR / BRIDGE

  New terrain must be classified in `DungeonLayout.is_walkable_kind` / `is_solid_kind`, in
  `DungeonNavigation`, and in the validator, with a negative test.
- Required passages (doorway approaches, corridors, bridges) are at least 3 tiles (96 px) wide.
  Template lint enforces this for every variant. Fix the template; never loosen the lint.
- Room variants must keep the base layout's size and door sockets, and are picked only via
  `RoomTemplate.pick_variant` with the per-room "variants" stream.
- Enemies path with `DungeonNavigation` and never attack or hit through walls (`Hitbox` raycasts
  layer 1). Floor-level damage sources (spikes, pits) set `requires_line_of_sight = false`.
- The full debug map (F3 / DBG) and the tactical overlay (F4 / TAC) are debug-build only. The player's
  map (M) reveals only visited spaces and never room roles.
- Every room has a `RoomRole` (PacingDirector) and every generated element needs a reason: hazards carry
  a purpose allowed by their room's role (`RoomRole.allowed_purposes`); pits/water/spikes only appear in
  terrain roles; fights are built from `TacticalComposer` recipes tied to room features.
- Difficulty comes from composition under `ThreatModel` budgets, never from scaling enemy counts or HP
  by depth. The composer and the validator must use the same `ThreatModel`; any new difficulty source
  (enemy, hazard, interaction) gets a threat weight. Depth progression is profile data only.
- Risky routes are optional by construction: risk-purpose tiles are excluded from the required mask
  (`DungeonValidator.required_mask`). Never let a required route depend on a risk.
- Generation stages must satisfy their own rules (e.g. the director's pacing is unit-tested before
  validation); the validator is the safety net, not the mechanism. Placeholder enemy archetypes
  (brute, spitter) are tactical-role stand-ins, not the final roster.
- `--check-only` quirk: a root script whose function signatures mix `RoomTemplate` params with
  `RoomShape.Socket` params reported spurious "ObjectDB instances leaked". Keep variant logic inside
  `RoomTemplate` and avoid const dictionaries or stored lambdas of inner-class types in generation scripts.
- Story: 15 narrative depths; the Queen/King and bosses come later. The **hidden ending is
  undecided**: don't invent or implement it ("Break the Thread" is non-canon placeholder).
- Treat warnings as real problems. Never suppress errors to make validation pass.
- Keep mobile performance in mind (compatibility renderer, few draw calls, no per-frame allocations
  in hot paths).
- No new plugins or dependencies without a clear reason.

## Git

- Never rewrite history, reset, or revert the user's work without explicit permission. Never push.
- After a validated milestone/sub-milestone, summarize the changes and validation, then propose a
  commit. Don't commit unasked.
