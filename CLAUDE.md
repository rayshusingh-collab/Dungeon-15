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
# 3. Smoke test (exit code 1 on failure)
"$GODOT" --headless --path . --script res://tools/smoke_test.gd
```

Run all three after meaningful changes. Look at the output, not just the exit code: `--quit-after`
exits 0 even when scripts fail to parse. Extend `tools/smoke_test.gd` when adding systems that can be
checked automatically. Passing automated checks is **not** proof that gameplay feels right; the user
does the gameplay testing.

`--import` runs editor code, which can rewrite files (for example, it converted a space-indented
script to tabs). Check `git status` afterwards.

## Project layout

Feature folders under `src/`. Each scene sits next to its script.

- `src/main/`: entry scene; seeds the run and wires the room, player, and controls
- `src/player/`, `src/enemies/`, `src/rooms/`: gameplay actors and rooms
- `src/ui/`: HUD and touch controls
- `src/shared/`: small reusable components (for example, placeholder visuals)
- `tools/`: headless test/dev scripts (not shipped gameplay)

## Rules

- Work milestone by milestone (see DEVELOPMENT.md). Keep the project playable. Stop for review at
  milestone boundaries.
- Inspect before changing; don't blindly rewrite. Delete obsolete files only after confirming
  they're unused (grep for `res://` paths and class names).
- No god scripts. Prefer small scenes/components with typed GDScript (`class_name`, typed vars,
  `-> void`). Use tabs for indentation.
- Gameplay reads **InputMap actions only** (`move_left/right/up/down`, `attack`). Touch controls
  press those actions and must not be referenced by gameplay code.
- Visuals are placeholders (`PlaceholderCircle`, `ColorRect`). Never couple gameplay logic to them.
  Art must be swappable without touching gameplay.
- Sub-resources (shapes, materials) must not be shared across instances that are configured
  independently. Call `duplicate()` before mutating a shared resource at runtime.
- Physics layers: 1 `world`, 2 `player`, 3 `enemies` (named in project.godot).
- Determinism: all seeded generation draws from an explicitly passed/owned
  `RandomNumberGenerator`, never the global `randi()`/`randf()`. Draw order matters, so treat
  changes to generation call order as seed-breaking.
- Treat warnings as real problems. Never suppress errors to make validation pass.
- Keep mobile performance in mind (compatibility renderer, few draw calls, no per-frame allocations
  in hot paths).
- No new plugins or dependencies without a clear reason.

## Git

- Never rewrite history, reset, or revert the user's work without explicit permission. Never push.
- After a validated milestone/sub-milestone, summarize the changes and validation, then propose a
  commit. Don't commit unasked.
