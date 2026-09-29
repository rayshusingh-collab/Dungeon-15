# Dungeon15 — Development Status

## Current milestone

**Milestone 0 — Project audit & cleanup: complete. User play-test passed.**
Next: Milestone 1 (playable combat foundation). Not started; waiting for the go-ahead.

## Milestone roadmap

0. Audit & cleanup ✅
1. Playable combat foundation: movement, controls, camera, attack, dodge, health, one enemy, room completion, door unlock, room transition
2. Seeded procedural dungeon: RNG strategy, room graph, templates, encounters, floors, seed display/replay
3. Combat/content framework: enemy archetypes, weapons, loot, upgrades, traps, chests, special rooms, scaling, boss framework
4. Run/roguelite systems: death/restart, run state, saves, meta progression, stats, seed sharing
5. Content & presentation: art, animation, themes, VFX, audio, menus, tutorial, settings
6. Mobile production: Android input, resolutions/safe areas, profiling, pause/resume, export
7. Release candidate: bug fixing, balance, many-seed validation, final build

## Completed systems (prototype level)

Behaviour carried over from the original prototype, now split into components:

- Player movement (keyboard WASD/arrows + touch joystick through the same InputMap actions)
- Touch controls: engine-native `VirtualJoystick` (fixed mode) and a multi-touch `TouchActionButton` for attack
- Static room with walls/collision and an exit door indicator (red → green when cleared)
- Enemy chaser AI (aggro range, stop distance), 2 HP, dies when HP reaches 0
- Prototype radial melee attack (Space/J, or the on-screen button): hits every enemy within 85 px
- Seeded enemy placement (seed currently = unix time, printed to the console)
- Headless smoke test (`tools/smoke_test.gd`)

## Architecture

```
project.godot            InputMap, physics layer names, display, renderer
src/main/main.tscn       Main (main.gd): seeds RNG, places player, asks room to spawn enemies
  ├─ Room                src/rooms/room.tscn (Room): walls, ExitDoor, Enemies container, PlayerSpawn
  ├─ Player              src/player/player.tscn (Player): CharacterBody2D, reads InputMap
  └─ MobileControls      src/ui/mobile_controls.tscn: CanvasLayer (layer 10)
       ├─ VirtualJoystick   native Godot 4.7 node → presses move_* actions
       └─ AttackButton      TouchActionButton → presses `attack`
src/enemies/enemy.tscn   Enemy: CharacterBody2D chaser, `died` signal, take_damage()
src/shared/placeholder_circle.gd   @tool placeholder visual used by Player/Enemy
tools/smoke_test.gd      headless integration checks
```

Data flow: touch/keyboard → InputMap actions → `Player`. The player's attack finds nodes in group
`enemies` and calls `Enemy.take_damage()`. `Enemy.died` → `Room` counts the living enemies → at 0 it
emits `cleared` and turns the door green.

Groups: `player`, `enemies`. Physics layers: 1 world, 2 player, 3 enemies
(player mask = world+enemies; enemy mask = world+player+enemies; walls mask none).

## Technical decisions

- **Feature-folder layout** (`src/<feature>/`), with each scene next to its script.
- **InputMap is the only input API gameplay uses.** Touch controls inject into actions via
  `Input.action_press(action, strength)`. The move actions use a 0.2 deadzone.
- **Native `VirtualJoystick`** (new in Godot 4.7) instead of a custom joystick. It's less code and supports
  fixed/dynamic/following modes. Its class reference has no descriptions yet, so behaviour must be verified on device.
- `emulate_touch_from_mouse = true`, so the touch controls can be tested with a mouse on desktop.
- **Placeholder visuals are separate child nodes** (`Visual`), never referenced by gameplay scripts.
- **Explicit RNG ownership:** `Room.spawn_enemies(rng, count)` takes the RNG. Global random functions
  are not used for anything seeded.
- Display: 1152×648 base viewport, `canvas_items` stretch, sensor-landscape orientation.
- Renderer: `gl_compatibility` on desktop and mobile (widest Android support).

## Known bugs / limitations

- The door gap in the right wall is always walkable. Nothing blocks it before the room is cleared, and leaving
  the room leads into the void. (Door locking and room transitions are Milestone 1.)
- Enemies can spawn on top of the player (the spawn area includes the player spawn).
- Enemies do not damage the player. The player has no health yet.
- The attack has no telegraph, cooldown, direction or feedback; it's a radial check with instant damage.
- There is no camera node. The room exactly fits the base viewport. With `stretch/aspect = keep`, wider phones get letterboxing.
- The seed comes from the clock and can't be entered or replayed yet (Milestone 2).
- Hand-written `.tscn` files reference resources by path only (no `uid=`). Godot adds UIDs on the
  first editor save; expect a one-time diff.
- With both keyboard and the joystick active, releasing the joystick may release a held key's action
  (`Input.action_release` is global). Development-only edge case.

## Testing status

| Check | Result |
|---|---|
| `--import` (editor scan) | clean, no errors/warnings |
| `--quit-after 300` main scene boot | clean |
| `tools/smoke_test.gd` | 15/15 pass (loading, typed nodes, spawn count, keyboard move, joystick → actions, attack button → action, room clear, seed determinism) |
| Negative check (broken attack button) | smoke test fails with exit 1, as expected |
| Manual gameplay (desktop) | passed (user play-test, Milestone 0): runs; the core prototype works. See the observations below |
| Android device | **not yet tested** |

## Asset status

All visuals are placeholders: circles drawn by `PlaceholderCircle`, `ColorRect` walls/floor/door,
and default-theme joystick/button drawing. `icon.svg` is the stock Godot icon. There is no audio. No final assets exist yet.

## Play-test observations (Milestone 0 → inputs for Milestone 1)

1. **Enemy aggro/chase behaviour needs a redesign.** Enemies stop chasing as soon as the player
   leaves their 300 px range. This matches the current implementation, but it isn't the intended
   final behaviour. Replace the distance check with a proper enemy state model
   (for example idle → aggro → chase → return/leash, with aggro persisting beyond the detection radius).
2. **Combat feedback is unclear.** The player can kill enemies without being able to see what's happening:
   - there's no visible attack or sword swing
   - there's not enough hit feedback, and enemy damage isn't communicated
   - enemy death has no visual feedback or animation

   Milestone 1 must make attacking, hitting, taking damage and death visually readable even with
   placeholder art (swing arc, hit flash, knockback, hit-stop, damage/death effects).
3. **The mobile attack control is unclear.** The large red circle on the right shows no sign of what it's for.
   Because attacks have no visible effect, pressing it can look like it does nothing. Replace or
   improve its presentation (icon/label, pressed state) so its purpose is obvious, and pair it with
   visible attack feedback (see 2).

## Next tasks (Milestone 1 proposal, pending go-ahead)

1. Camera2D and a TileMapLayer-based room (replacing ColorRect walls)
2. Door blocker that unlocks on `Room.cleared`, then room transition
3. Health component (player + enemy), hurt/invulnerability frames, death
4. Directional melee with a hitbox, cooldown and **visible swing + hit feedback** (observation 2); dodge/roll action + button
5. Enemy state machine (idle/aggro/chase/return) (observation 1) and an enemy attack with a readable telegraph
6. Clear, labelled mobile attack (and dodge) buttons (observation 3)
7. Enemy damage and death feedback (flash, knockback, death effect) (observation 2)
