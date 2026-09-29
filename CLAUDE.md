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
```

Run all three after meaningful changes. Look at the output, not just the exit code: `--quit-after`
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

- `src/main/`: `Main`, the run orchestrator (seed, room swapping, signal wiring to HUD/camera/controls)
- `src/player/`, `src/enemies/`, `src/rooms/`: gameplay actors, rooms, exit door, spawn placement
- `src/components/`: reusable gameplay components (`HealthComponent`, `Hitbox`, `Hurtbox`, `MeleeAttack`, `HealthBar`)
- `src/effects/`: cosmetic-only effects (`AttackArcEffect`, `BurstEffect`)
- `src/camera/`: `GameCamera` (room framing, shake)
- `src/ui/`: HUD and touch controls
- `src/shared/`: small shared helpers (placeholder visuals)
- `tools/`: headless test/dev scripts (not shipped gameplay)

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
- Determinism: all seeded generation draws from an explicitly passed/owned
  `RandomNumberGenerator`, never the global `randi()`/`randf()` (cosmetic-only randomness such as
  camera shake is the exception). Draw order matters, so treat changes to generation call order as
  seed-breaking.
- Treat warnings as real problems. Never suppress errors to make validation pass.
- Keep mobile performance in mind (compatibility renderer, few draw calls, no per-frame allocations
  in hot paths).
- No new plugins or dependencies without a clear reason.

## Git

- Never rewrite history, reset, or revert the user's work without explicit permission. Never push.
- After a validated milestone/sub-milestone, summarize the changes and validation, then propose a
  commit. Don't commit unasked.
