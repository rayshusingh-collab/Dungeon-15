# Stage 2B: movement and GP325 acceptance

## What changed

The camera's horizontal right/forward vectors are diagonal to the world axes.
The fixture's stairs and bridge follow world X, so following their centerline
requires diagonal screen-relative input. This is expected eight-direction
movement, not a stair-specific input rule. The controller uses the same mapping
on flat ground, bridge and stairs. Camera projection also compresses vertical
screen travel: eight world directions do not all draw at 45 degrees on screen.

The checked-in +12/+12/+12 camera and +X ascending route give S+D (screen
right+down) toward the 8 m chamber and A+W for return. Earlier D+W instructions
were incorrect. The owner's report describes A+W as ascent; no geometry/camera
rotation was applied to force different keys. The diagnostic position/elevation
readout makes the direction verifiable in the running scene. Follow the physical
stairway diagonal, with either keyboard, stick or D-pad.

`gamepad_input.gd` owns four temporary InputMap actions per scene instance.
Left stick and logical D-pad events are bound to one selected controller. The
default radial deadzone is 0.22; magnitude is rescaled outside the deadzone and
diagonals are capped at one. Keyboard and joypad vectors combine with a unit cap.
Actions are removed on scene exit. Shared `move_*` bindings and project settings
are unchanged; there is no gamepad addition to the original 2D game.

`abyss_player.gd` subclasses the P1A controller and overrides only the movement
input source. P1A's sole code change is extraction of its original Input.get_vector
call into `_movement_input()`. Its default input, physics, facing, gravity and
camera calculations are unchanged. No movement physics were duplicated.

Device selection uses `Input.get_connected_joypads()` and
`Input.joy_connection_changed`. By default the first connected pad is selected;
the selection stays stable until it disconnects. `preferred_device` can select an
explicit ID. Disconnect/rebind clears owned action state; keyboard stays usable.
The demo does not alter Godot's global controller mapping database.

## Exact GP325 manual test

1. Connect the GP325 using its normal Windows connection. Open
   `src/abyss/vertical_demo.tscn` in Godot 4.7.2 and press F6. Focus the game window.
2. Leave the F3 diagnostics visible. Verify a connected ID, controller name and
   GUID appear. Record those values and `known mapping`. If the list is empty,
   verify Windows detects the controller (Win+R, `joy.cpl`), then reconnect and
   retry. Do not infer a controller mode or button layout from its product name.
3. Without touching the pad, watch axis values and the final input vector for
   several seconds. The capsule should stay still. Tiny reported axis values
   below the radial deadzone should yield zero movement input.
4. Move the left stick slowly in each cardinal direction, then diagonally.
   Screen direction should follow the stick. Partial deflection should walk
   slower; full deflection and diagonals should not exceed normal full speed.
   Release it and confirm the capsule stops.
5. Press each D-pad direction and two adjacent directions together. Check the
   axis/held-button readouts and movement. Tap other buttons to record their
   reported indices; they should have no gameplay effect. The last button event
   persists even if stick events arrive later.
6. Follow the staircase diagonal from the entry (about 0 m) through the middle
   chamber (4 m), bridge and upper chamber (8 m), using the stick. Repeat with
   D-pad diagonals, then WASD and arrow keys. Return along the opposite diagonal.
   Test railings, wall sliding and both end walls. Check all eight directions in
   each chamber and confirm camera-relative directions stay consistent.
7. On a chamber floor, hold the stick, unplug/disconnect the pad, then release it.
   Confirm the overlay reports disconnection and the capsule stops. Confirm
   keyboard movement still works. Reconnect, note the new ID if any, and confirm
   fresh stick and D-pad input works. Repeat after starting the demo without a pad.
8. Press F3 to hide/show diagnostics. Run the original game with F5 to verify
   keyboard controls remain unchanged. Stop for owner acceptance.

## If GP325 mappings differ

Godot's logical axis/button enums are used as defaults; physical Xbox numbering
is not assumed. On unknown/unmapped devices these defaults need hardware review.
The overlay displays Godot-reported indices/values, not electrical/raw HID data.

Stop the scene, select `MovementInput` in `vertical_demo.tscn`, and edit its script
exports in the Inspector, then rerun F6:

- `horizontal_axis` / `vertical_axis`: indices observed for the left stick.
- `invert_horizontal` / `invert_vertical`: reverse an incorrectly signed axis.
- `dpad_left/right/up/down`: observed button indices; use -1 to disable a binding.
- `dpad_horizontal_axis` / `dpad_vertical_axis`: optional hat axes if the D-pad
  reports motion instead of buttons; -1 leaves them disabled. Negative means
  left/up and positive means right/down. Use `invert_dpad_horizontal` /
  `invert_dpad_vertical` if the hat signs are reversed.
- `deadzone`: increase only enough to remove measured resting drift (0–0.9).
- `preferred_device`: -1 selects automatically; otherwise use the displayed ID.

Bindings are applied on startup or connection selection; changing these values
in the Remote Inspector while running does not automatically rebuild bindings.
Do not edit project-wide `move_*` actions to calibrate this demo.

## Automated evidence and limits

Commands use the P1A README's Godot console executable and workspace APPDATA:

```text
godot --headless --path . --import
godot --headless --fixed-fps 60 --path . --script res://tools/abyss_input_test.gd
godot --headless --fixed-fps 60 --path . --script res://tools/abyss_vertical_test.gd
godot --headless --fixed-fps 60 --path . --script res://tools/prototype_3d_test.gd
godot --headless --fixed-fps 60 --path . --script res://tools/smoke_test.gd
```

Tests inject Godot joypad events, flush the input queue, and verify action mapping,
analog speed, circular deadzone, normalized diagonals, D-pad buttons/hat axis,
configurable axes/inversion/buttons, device filtering, action cleanup, simulated
disconnect/rebind and shared-input preservation. They also exercise all eight
camera-relative analog directions and actual capsule traversal using the stick
outbound and keyboard on return. No physical devices were detected during these
tests. USB detection, GP325 driver/mode mapping, resting drift, physical D-pad
reporting and real hotplug behavior therefore remain owner acceptance checks.

The known Windows certificate-store error still appears at engine startup,
before the suite logger. It is not counted in passing test totals.

Executed on 2026-10-19: input suite **50 checks, zero failures**; vertical suite
**33 checks, zero failures**; P1A **43 checks, zero failures**; existing smoke
**378 checks, zero failures** (25.5 seconds). Godot import completed. The rendered
demo booted successfully and its disconnected diagnostic overlay was visually
inspected. `git diff --check` passed. Logs/captures are in ignored `.godot/`.
The new input suite initially needed a type annotation and explicit flushing of
synthetic input events; the final executed run passes. No hardware pass is claimed.

API references: [Godot Input](https://docs.godotengine.org/en/latest/classes/class_input.html)
and [controller input guidance](https://docs.godotengine.org/en/stable/tutorials/inputs/controllers_gamepads_joysticks.html).
