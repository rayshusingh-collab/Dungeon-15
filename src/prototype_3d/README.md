# P1A: isolated 3D foundation

Status: automated verification complete; all seven manual acceptance checks passed
and P1A accepted by the project owner. Stop at P1A pending approval for further work.

Open `project.godot` in Godot 4.7.2, open
`res://src/prototype_3d/foundation_3d.tscn`, and press **F6 (Run Current Scene)**.
F5 still launches the existing 2D game. Do not change the project's main scene.

Use **WASD or arrow keys** to move relative to the screen. The blue capsule's
gold marker shows facing. Movement stops immediately on release; diagonals have
the same speed as cardinal movement. Walk into each wall and diagonally along it
to check blocking and sliding. The orthographic camera follows smoothly while
keeping its angle and zoom fixed. Confirm framing, visibility near all four
walls, facing, and movement feel during manual acceptance; these presentation
and interactive checks passed the project owner's manual acceptance.

Files:

- `foundation_3d.tscn`: flat 20-by-20 floor, four low walls, lighting, instructions,
  capsule player instance, and fixed orthographic camera.
- `player_3d.tscn` / `player_3d.gd`: CharacterBody3D, capsule collider, gravity,
  camera-relative movement, move_and_slide collision, and visible facing.
- `isometric_camera_3d.gd`: fixed orientation with exponential position smoothing.
- `../../tools/prototype_3d_test.gd`: focused tests using the existing test harness.

The controller reads the existing move actions without changing their bindings.
The prototype has no generator, combat, enemies, production assets, dependencies,
or integration with the existing 2D scene tree.

Verification on Windows / Godot 4.7.2 (2026-10-18), from the repository root:

```powershell
# Substitute your Godot console executable path.
$godot = 'C:/Users/raysh/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe'
# Keep test logs and editor settings in the ignored workspace cache.
$env:APPDATA = Join-Path $PWD '.godot/p1a_test_appdata'
New-Item -ItemType Directory -Force -Path $env:APPDATA | Out-Null
& $godot --headless --path . --import
& $godot --headless --fixed-fps 60 --path . --script res://tools/prototype_3d_test.gd
& $godot --headless --fixed-fps 60 --path . --script res://tools/smoke_test.gd
& $godot --headless --path . --quit-after 300
& $godot --headless --path . res://src/prototype_3d/foundation_3d.tscn --quit-after 120
```

Results: import/parse completed, both scene boots exited 0; 3D suite **43 checks,
0 failures**; smoke suite **378 checks, 0 failures**. Focused coverage includes
exact WASD/arrow bindings, screen-relative direction, speed, diagonal normalization,
release, floor support, four wall collisions, wall sliding, facing, camera
convergence, smoothing, and fixed orientation. Test bodies logged no engine/script
warnings or errors.

Every Godot invocation logged the startup error `Failed to read the root
certificate store`, before suite logging was installed; passing suite totals do
not include that startup error. The initial run also could not write editor
settings and user logs outside the workspace; redirecting APPDATA as above
resolved those write errors. No other warnings or failures were observed.

Quick generation stress was not repeated: shared logic, project configuration,
and all generator files are unchanged. The supplied baseline remains 337 checks
passed. The project owner confirmed import and scene boot, all seven manual
acceptance checks, and preservation of the original 2D gameplay and generator.
