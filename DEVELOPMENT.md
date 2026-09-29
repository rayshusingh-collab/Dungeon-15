# Dungeon15 — Development Status

## Current milestone

**Milestone 1 — Playable combat foundation: the manual functionality play-test PASSED. A combat-feel
refinement pass is done and automatically validated; it's awaiting the user's feel re-test before the Milestone 1 commit.**
Milestone 0 is complete and committed (`a094ca2`). Milestone 2 is not started.

## Milestone roadmap

0. Audit & cleanup ✅
1. Playable combat foundation 🟡 (functionality passed; feel pass awaiting re-test)
2. Seeded procedural dungeon: RNG strategy, maze-like room/corridor graph, templates, encounters, floors, seed display/replay (see the design note below)
3. Combat/content framework: enemy archetypes, weapons, loot, upgrades, traps, chests, special rooms, scaling, boss framework
4. Run/roguelite systems: run state, saves, meta progression, stats, seed sharing
5. Content & presentation: art, animation, themes, VFX, audio, menus, tutorial, settings
6. Mobile production: Android input, resolutions/safe areas, profiling, pause/resume, export
7. Release candidate: bug fixing, balance, many-seed validation, final build

## Implemented systems (Milestone 1)

- **Movement:** velocity-based `CharacterBody2D` (frame-rate independent). `Input.get_vector` clamps the
  vector, so diagonals aren't faster. Keyboard and touch share one path (InputMap actions).
- **Camera:** `GameCamera` fits the whole room below a 60 px HUD strip at any aspect ratio. The stretch aspect is
  `expand`, so wider phones get extra margin instead of letterboxing or cropping. It has a `shake()` hook used for hit feedback.
- **Health/damage:** a reusable `HealthComponent` (hit points, a post-hit invulnerability window, `grant_invulnerability`)
  plus `Hitbox` / `Hurtbox` areas. A hitbox hits each hurtbox at most **once per activation**.
- **Melee:** a reusable `MeleeAttack` (WINDUP → ACTIVE → RECOVERY, cooldown, sector-shaped hitbox built from
  reach/arc). The player swings in their facing direction and gets a visible sweeping slash (`AttackArcEffect`).
  An input buffer is included, and moving is slowed while swinging.
- **Combat feedback:** slash arc, a white flash and shards on the enemy, knockback, a short stagger, an enemy HP bar
  (shown after the first hit), and camera shake. Enemy death shows a flash, expanding ring, shards and fade before removal.
  When the player is hit: red flash, knockback, blinking during invulnerability, a red screen flash, a heart flashing in the HUD, and camera shake.
- **Enemy AI:** an explicit state machine `IDLE / CHASE / ATTACK / HURT / RETURN / DEAD`, with a "!" alert on
  aggro. Once engaged it keeps chasing (no invisible range boundary). It returns home only if the player dies or goes
  beyond the leash range from its home.
- **Enemy attack:** a telegraphed melee attack. The windup shows the danger sector outline plus a growing fill,
  and the enemy tints orange. The strike flashes the sector. There's no contact damage; the attack has a cooldown.
- **Dodge:** a directional burst (input direction, or facing when idle) with a cooldown, invulnerability frames, afterimage
  ghosts, and a ring. It can cancel an attack. The next dodge can't start until the cooldown ends.
- **Mobile controls:** the native `VirtualJoystick` (styled, labelled "MOVE") on the left, and labelled **ATTACK** (sword
  icon) and **DODGE** (chevron icon) buttons on the right, with cooldown pie overlays. Multi-touch is supported.
- **Rooms:** `Room` is ACTIVE while enemies live and CLEARED afterwards. The `ExitDoor` is a physical blocker while
  locked (red, barred, "LOCKED"). When cleared the blocker is removed and the door turns green and pulses with
  chevrons and "EXIT". A permanent threshold wall behind the doorway means the player can never leave the room bounds.
- **Room progression:** entering the open exit fades out, loads the next room, and shows a "ROOM N" banner. Rooms
  alternate `room.tscn` / `room_pillars.tscn` (teal floor, two pillars). There are 3 enemies in room 1 and one more per room (max 6).
  This is deliberately not procedural generation.
- **Spawning:** `SpawnPlacer` uses deterministic rejection sampling. It keeps enemies ≥320 px from the player spawn, inside the
  spawn area, and clear of obstacles, and it prefers ≥96 px separation. Each room's RNG seed is `hash([run_seed, room_index])`.
- **Death/restart:** when HP reaches 0, the player is dead (no movement or attack), the controls hide, the player collapses,
  and "YOU DIED" appears with a room count and a RESTART button (keyboard focus; briefly disabled against mashing).
  Restart reloads the scene with a fresh time-based seed and clears held inputs.
- **HUD:** hearts with "HP x/y", "ROOM N | ENEMIES LEFT: n" / "CLEARED", banners, a desktop control hint
  (hidden on mobile builds), fades, and the death screen.

## Controls

| Action | Desktop | Mobile |
|---|---|---|
| Move | WASD / arrow keys | left virtual joystick |
| Attack | Space / J | ATTACK button (bottom right) |
| Dodge | Shift / K | DODGE button (left of ATTACK) |
| Restart (on death screen) | click RESTART, or Space/Enter (focused) | tap RESTART |

The mouse emulates touch on desktop (single touch only, so it can't test simultaneous touches).

## Combat-feel refinement (Milestone 1 feel pass)

The user's play-test feedback was that attacks should feel more real, valuable and convincing. Changes, all using
placeholder art and no new systems:

- **Player swing = anticipation → strike → follow-through.** A 0.06 s windup cocks the blade back past the
  arc with a faint reach outline, and the body gathers in slightly. The strike sweeps the blade across the arc in
  0.05 s with a ~17 px forward step, and the body pops out. The trail fades through a 0.14 s recovery.
  Consecutive swings alternate direction.
- **Damage frame = visual frame.** With a windup, the hitbox is already rotated, so damage lands on the **first**
  active frame, exactly when the blade starts crossing. The test asserts that hit frame == strike frame.
- **Impact:** directional white spark spray and a small ring at the contact point, a white flash and squash on the
  enemy, knockback along the swing direction (radial + facing blend), **hit-stop** (0.045 s, 0.08 s on
  kills), and a camera **kick** toward the impact (4 px, 7 px on kills). The kill slides the body ~48 px as it fades.
- **Enemy attack is physical:** it coils back ~11 px while swelling and heating orange during the 0.5 s telegraph,
  **lunges** ~12 px on the strike with a bright flash, then dims during recovery (a visible opening). The
  strike flash lasts 0.18 s, so danger visuals never outlive the damage window. The telegraph moves with the
  enemy, so it always shows the real hit area.
- **Player hit reaction:** stronger knockback (≈27 px) in the hit direction, a 0.12 s stagger where movement input is
  ignored (**dodge still works**), a red spark spray, squash, 0.07 s hit-stop, a camera kick plus a light shake, and a
  lighter real-time red screen flash.
- **Restraint:** the camera offset is hard-capped at 14 px with a global `feedback_scale`. Hit-stop is short and
  never stacks longer. There are at most ~3 small effect nodes per hit. No particles or shaders.
- **Responsiveness preserved:** press to damage is 4 frames (~67 ms), attacks buffer input, dodge cancels a
  windup/swing and works during a stagger, and hit-stop doesn't drop buffered inputs.

## Tuning values (current)

| Area | Value |
|---|---|
| Player | 5 HP, speed 230 px/s, 0.8 s invulnerability after a hit, knockback 360 (decay 2400), hurt stagger 0.12 s |
| Player attack | 1 dmg, reach 84 px, arc 130°, **windup 0.06 s**, active 0.08 s, recovery 0.14 s, cooldown 0.34 s, lunge 320 px/s (decay 3600, ≈14–17 px), move ×0.35 while swinging, input buffer 0.15 s |
| Slash visual | sweep 0.05 s, alternating direction, trail inner radius 40% |
| Dodge | 620 px/s for 0.20 s (≈124 px), cooldown 0.6 s (from start), invulnerable 0.25 s |
| Enemy | 3 HP, speed 95 px/s, aggro 260 px, attack trigger 60 px, leash 700 px from home, stagger 0.25 s, knockback 380 (decay 2200), death knockback 480 |
| Enemy attack | 1 dmg, **reach 72 px** (+≈12 px lunge), arc 100°, **windup 0.5 s** (pull-back 22 px/s), active 0.1 s, recovery 0.45 s, cooldown 1.3 s, next attack 0.6 s after a stagger, strike flash 0.18 s |
| Hit-stop (Main) | time scale 0.05; on hit 0.045 s, on kill 0.08 s, on player hurt 0.07 s |
| Camera (Main/GameCamera) | kick: hit 4 px, kill 7 px, player hurt 8 px + shake 5 px; offset cap 14 px; `feedback_scale` 1.0 |
| Spawning | ≥320 px from player spawn, ≥96 px apart (soft), 28 px obstacle clearance, 40 attempts/enemy |
| Rooms | 3 + room_index enemies (max 6); fade 0.25 s each way |

All values are `@export`s on the relevant scene or script (Player, Enemy, MeleeAttack, AttackArcEffect,
HealthComponent, Hitbox, Room, GameCamera, Main).

## Architecture

```
src/main/main.tscn  Main (main.gd): run seed, room swapping, wires signals → HUD/camera/controls
  ├─ <Room>         instanced at runtime from Main.room_scenes (index 0 = drawn first)
  ├─ Player         src/player/player.tscn
  │    ├─ HealthComponent, Hurtbox(layer 4)        ← components
  │    ├─ MeleeAttack ─ Hitbox(mask 5), ArcEffect   ← component + visual
  │    └─ Visual (PlaceholderCircle), FacingMarker  ← placeholder art
  ├─ GameCamera     src/camera/game_camera.gd
  ├─ Hud            src/ui/hud.tscn (CanvasLayer 5): HealthDisplay, labels, banner, fade, death screen
  └─ MobileControls src/ui/mobile_controls.tscn (CanvasLayer 10): VirtualJoystick, Dodge/AttackButton

src/rooms/room.tscn        Room: FloorPlaceholder, Walls, Obstacles, ExitDoor, Enemies, PlayerSpawn
src/rooms/room_pillars.tscn  inherits room.tscn (+2 pillars, teal floor)
src/rooms/exit_door.tscn   ExitDoor: Blocker, Threshold, Trigger(mask player), Label
src/rooms/spawn_placer.gd  static deterministic placement
src/enemies/enemy.tscn     Enemy: HealthComponent, Hurtbox(layer 5), MeleeAttack(Hitbox mask 4), HealthBar, AlertLabel
src/components/            HealthComponent, Hitbox, Hurtbox, MeleeAttack, HealthBar
src/effects/               AttackArcEffect (slash/telegraph), BurstEffect (ring/disc/shards)
src/shared/                PlaceholderCircle
tools/smoke_test.gd        headless integration tests
```

**Signal flow:** input → Player → `MeleeAttack.start` → `Hitbox` overlaps a `Hurtbox` → `HealthComponent.take_damage`
→ `damaged`/`died`/`hit_received` → the owner reacts (flash, knockback, state). `Enemy.died` → `Room` counts →
`Room.cleared` → the ExitDoor unlocks → `ExitDoor.player_entered` → `Room.exit_entered` → Main transitions.
Main listens to Player/Room signals and pushes state into the Hud, GameCamera and MobileControls. None of those
know about gameplay nodes.

**Physics layers:** 1 world, 2 player, 3 enemies, 4 player_hurtbox, 5 enemy_hurtbox.
Player body mask = world+enemies; enemy body mask = world+player+enemies; the player hitbox scans enemy_hurtbox;
the enemy hitbox scans player_hurtbox; the exit trigger scans player.

## Technical decisions

- **Feature folders** (`src/<feature>/`), with each scene next to its script. Reusable gameplay pieces go in
  `src/components/`; cosmetic effects go in `src/effects/`.
- **InputMap is the only input API gameplay uses.** Touch controls press actions (`Input.action_press`).
- **Hitbox/Hurtbox/HealthComponent composition** instead of per-actor damage code. The player and enemies share it.
- **Hitboxes poll overlaps** while active (monitoring always on, gated by `active`). A no-windup attack skips
  its activation frame, because physics overlap results are one step stale after a rotation change. With a windup
  the rotation happened earlier, so the hit lands on the first active frame.
- **Hit-stop through `Engine.time_scale`**, owned by `Main.hit_stop()` (a real-time timer restores it; a token
  makes the latest call win; `_exit_tree`/`restart` always restore 1.0). Gameplay tweens and timers freeze with it.
  UI feedback opts out with `set_ignore_time_scale(true)`.
- **Knockback direction** = radial from the attacker plus the swing direction (`Hitbox.directional_bias`), so
  hits push the way the weapon travelled.
- **Logic/visual split:** `MeleeAttack` drives `AttackArcEffect` through a narrow API
  (`configure/play_windup/play_strike/stop`). Hit/death effects are `BurstEffect` nodes spawned into the world.
  Feedback uses `modulate`/`scale`/`visible` on `$Visual`, so it works with any future sprite.
- **Invulnerability windows only ever extend** (`grant_invulnerability` takes the max), so a dodge can't
  shorten post-hit invulnerability or the reverse.
- **Explicit RNG ownership:** each room gets its own `RandomNumberGenerator` seeded from the run seed and room
  index. Camera shake uses the global RNG on purpose; it's cosmetic.
- **Restart = `reload_current_scene()`**, the simplest guarantee of a clean state. Main releases all gameplay
  actions on `_ready` and before reloading, so touch-held inputs can't leak across a restart.
- Tweens are created on the node they animate (auto-killed when it's freed), never awaited on timers that can
  outlive their node.
- Display: 1152×648 base, `canvas_items` stretch, `expand` aspect, sensor-landscape orientation, `gl_compatibility` renderer.

## Known issues / limitations

- **Stun-lock:** every player hit staggers the enemy and cancels its windup (player cooldown 0.34 s < enemy
  stagger 0.25 s + 0.6 s delay + 0.5 s windup). A player standing in melee range and attacking continuously can keep an enemy
  from ever attacking. Knockback now pushes enemies out of reach, which softens this, but it remains a Milestone 3
  balance question (poise/hyper-armour, heavier archetypes).
- The hit feedback strengths (hit-stop, kick, knockback) are first-pass values tuned from rendered frames, not from
  hands-on play. They need the user's feel re-test, ideally on a phone as well as desktop.
- Hit-stop freezes the whole game (global time scale). That's fine with one player, but with many simultaneous hits
  it could feel choppy; revisit if multi-enemy fights make it noticeable.
- The player swing squash and the enemy squash scale the placeholder `$Visual` on its dominant axis only (no rotation);
  real sprites may want dedicated hit/attack animations instead.
- Attacks aim only by facing. There's no aim assist on mobile yet; this should be evaluated on device.
- Rooms alternate between two fixed layouts; the transition proves progression only (procedural generation is Milestone 2).
- The run seed is time-based. It's printed to the console but not shown in the UI and can't be entered.
- Restart starts a new run with a new seed (no "retry same seed" yet).
- Enemies can bunch up (bodies collide but there's no separation steering).
- The native `VirtualJoystick` has no class docs in 4.7. Its size, deadzone and feel still need checking on a real device.
- Releasing the joystick while a movement key is held may release that key's action (global `Input.action_release`).
  Development-only edge case.
- Hand-written `.tscn` files reference resources by path only (no `uid=`); the editor adds UIDs on first save.
- The desktop hint label is hidden via `OS.has_feature("mobile")`. It shows on touchscreen Windows laptops (fine).

## Testing status

| Check | Result |
|---|---|
| `--import` | clean, no errors/warnings |
| `--check-only` on every script | no warnings/errors |
| `--quit-after 300` main scene boot | clean |
| `tools/smoke_test.gd --fixed-fps 60` | **152/152 pass** (includes the combat-feel checks) |
| Mutation checks (multi-hit dedupe removed, exit blocker disabled, i-frames ignored, dodge cooldown ignored, spawn ignores player, controls not hidden on death, damage frame delayed, hit-stop never ends, stagger ignored, no attack lunge) | each one makes the suite fail |
| Rendered-frame review (Movie Maker + contact sheets) | Milestone 1 flow, plus the feel pass: windup/strike/impact/trail, alternating swings, enemy coil/lunge/recovery, player hurt, kill slide |
| Manual gameplay: functionality (desktop) | **PASSED** (user play-test, Milestone 1) |
| Manual gameplay: combat feel after the refinement pass | **pending the user's re-test** |
| Android device | **not yet tested** |

Smoke-test coverage: scene instancing; HealthComponent rules; movement distance, diagonal speed and stopping;
joystick press/release/neutral; multi-touch attack while steering; the dodge button; hidden controls ignoring
touch; a single hit per swing; the attack cooldown; attack direction; dodge burst, i-frames, cooldown and
attack-cancel; enemy IDLE→CHASE→ATTACK→HURT→CHASE→RETURN→IDLE; enemy death effect and removal; the enemy
telegraph giving time to react; one hit per enemy strike; no continuous contact damage; dodging a telegraphed attack;
spawn rules over 120 seeded rooms; seed determinism; locked exit blocks the player; clear unlocks it; transition to
the pillars room; player state preserved across the transition; death stops the player; the death screen; restart
reset; held inputs cleared. Feel pass: attack windup (hitbox off); press-to-strike latency; forward step; damage
on the exact strike frame; hit-stop engages and ends; knockback along the swing; kill slide; enemy coil and lunge;
player stagger ignores movement but allows dodge. The harness also fails on any engine/script error or warning, on any
aborted test, and if a test leaves `Engine.time_scale` ≠ 1.

## Remaining Milestone 1 manual tests (user)

A feel re-test of the refinement pass: do swings feel deliberate but still responsive? Do hits feel
physical without the hit-stop feeling like lag? Is the camera comfortable? Is the enemy attack readable and fair?
Also check on an Android device when possible.

## Milestone 2 design note: dungeon structure (user direction, recorded for Milestone 2)

The dungeon must **not** feel like a sequence of rectangular combat boxes. Milestone 2 targets a seeded
dungeon that feels **maze-like and explorable**:

- connected rooms **and corridors**
- branching paths, turns, and dead ends where appropriate
- multiple room shapes and sizes
- real route choices
- deterministic generation from the run seed, with guaranteed valid connectivity
- encounter placement integrated into the dungeon structure (not "every box is an arena")

The same compatible seed must reproduce the same dungeon structure and content, as defined by the project's
deterministic-generation rules (explicit, owned RNG streams; call order is part of the format; version-gated).
Later presentation should make it feel like a believable dungeon rather than a generated grid, but final
environmental art is **not** part of Milestone 2.

Implications of the current code: `Main`'s fixed room cycle and the one-room-at-a-time camera framing
will be replaced. The camera will likely need to follow the player through larger connected spaces. `SpawnPlacer`,
`ExitDoor`, `Room`'s ACTIVE/CLEARED encounter logic and the per-room derived seeds are meant to be reused.
The user's dungeon/maze feedback was explicitly **deferred to Milestone 2**; nothing about it is implemented yet.

## Asset status

Everything is a placeholder: `PlaceholderCircle` actors with facing triangles, `FloorPlaceholder` grid floor,
`ColorRect` walls and pillars, procedural door, slash, telegraph and burst effects, drawn hearts and button icons, StyleBoxFlat
joystick and buttons, and the default font. `icon.svg` is the stock Godot icon. There's no audio. No final assets exist yet.

## Play-test observations (Milestone 0), now addressed

1. Enemies stopped chasing at 300 px. **Fixed:** the state machine has persistent chase, a leash from home, and RETURN.
2. Combat feedback was unclear. **Fixed:** slash arc, hit flash/shards/knockback, HP bars, death effects, player hurt feedback.
3. The attack control was unclear. **Fixed:** labelled ATTACK and DODGE buttons with icons, a pressed state and cooldown pies.
