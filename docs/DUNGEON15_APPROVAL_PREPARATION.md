# Transition approval preparation

Planning audit, 2026-10-20. No gameplay or Git mutations performed.

## Verification

- Branch `3d-development-v2`; HEAD `b3b24323a8d51d7ff90d739ac6be9d4baeaa7d40`.
- Snapshot: `preservation/scope-reset-20261020-085931/`.
- Manifest contains exactly 30 files. All 30 snapshot copies AND all 30 working originals match recorded byte lengths and SHA-256 hashes.
- Snapshot base commit matches HEAD. `tracked.patch` passes `git apply --reverse --check` against the current working files. `index.patch` is empty, matching the currently empty staged diff. These were read-only checks.
- Dirty implementation inventory remains four modified tracked files and 26 untracked Stage 5A/5B files. The transition plan, this preparation document and recovery snapshot are additional planning/preservation artifacts.
- Original generator, P1A player/camera, Stage 2B adapters, original main scene and `project.godot` have no diff from HEAD. Generator version remains 5. Configured main scene remains `res://src/main/main.tscn`.
- No engine import or gameplay test was run. Existing documented manual/controller acceptance remains pending where stated.

## Review findings and decisions for approval

The proposed single static floor, original pure-data generator, separate 3D builder and retained movement/input foundation form a suitable small architecture. Keep experimental code present but outside the new game's runtime dependency graph. Use existing catalog IDs for initial enemies so presentation work does not silently change procedural output.

Clarifications required in implementation acceptance:

1. Use tile centers `(tile + 0.5) * metres_per_tile`, with inverse conversion in one coordinate adapter. `DungeonNavigation` consumes legacy pixel positions using `DungeonLayout.TILE_SIZE`, and uses a 14-pixel actor half-width. Convert world metres to legacy pixels for queries and back for returned waypoints; verify capsule clearance at the chosen scale. Keep 3D physics raycasts authoritative for attacks. Do not feed XZ metres directly into the old navigation API.
2. `SpecialRoomRule` places a two-link special room inside the main path, never at entry/objective. Prefer a boss objective template via `objective_templates` for boss depths; otherwise require both guardian clear and normal objective clear before descent. Do not assume special-room insertion already models a final boss objective. Arena shape/doors remain valid template ASCII; 3D content scenes add no undisclosed walls.
3. Existing profiles can select pits, water, spikes and Node2D authored scenes. Milestone 1 must faithfully present terrain used by its selected profile, with unsupported authored content mapped to an explicit 3D placeholder. Do not silently render pits as safe floors or change profile data merely to pass a movement demo. Combat/reward logic can remain disabled until its milestone; the exit is a traversal marker until progression is implemented.
4. Basic run-state/depth transition handling is needed by the 1–5 slice, before milestone 5. Milestone 5 completes persistence, menu flow, error recovery and presentation. The full campaign gate must exercise the actual 3D profile set and boss objectives, not only the existing depth 1–3 stress loop.
5. Keep the current 2D profiles unchanged initially. Use game-specific copies of profiles 1–3 plus new profiles 4–15 in `data/game_3d/depths/`; the 3D campaign loader selects these explicitly. This avoids changing what the legacy game loads through `DepthProfile.path_for_depth()`.
6. Choose release hardware and a target frame budget before large art/content expansion, then measure full-floor build cost and peak memory in the first floor milestone. Streaming remains deferred unless measurements require it.
7. Recovery copies contain scripts and duplicate UIDs. Before any Godot import, exclude `preservation/` using a root `.gdignore` inside that folder. The manual backup procedure below adds it in the new worktree only. No engine was launched in the current checkout; that checkout still lacks this exclusion.

Boss placement at 5/10/15, three theme bands, reward cadence and run length remain proposed tuning/content decisions. The approved direction alone does not imply acceptance of those choices. Death resets the run to depth 1; victory requires final boss defeat followed by escape, never depth 16. No hidden ending, Living Castle, moving architecture, large meta economy or new dependency is needed.

## Concrete implementation file map

The following is a proposed file contract for future approved work, not files created by this audit. Keep scripts small; create each only when its milestone needs it. Every new `.gd` will also have its Godot-generated `.gd.uid`, which must be preserved in Git. Art/audio asset filenames remain unspecified until assets are selected; this is the exact proposed code/data map, not a claim that final shipping art already exists.

### Existing files retained and reused

- `src/prototype_3d/player_3d.gd`, `player_3d.tscn`, `isometric_camera_3d.gd`; retain `foundation_3d.tscn` as the accepted fixture.
- `src/abyss/abyss_player.gd`, `gamepad_input.gd`, `controller_diagnostics.gd`. Their current scene wiring is demonstrated in `src/abyss/vertical_demo.tscn`; reuse the adapters without importing that demo's geometry.
- `src/core/stable_hash.gd`, `src/core/run_config.gd` for seed utilities/initial configuration; no claim of complete save support.
- `src/components/health_component.gd` for dimension-independent health.
- All 18 scripts in `src/dungeon/generation/`: `content_placer.gd`, `decor_placer.gd`, `depth_profile.gd`, `dungeon_generator.gd`, `dungeon_graph.gd`, `dungeon_layout.gd`, `dungeon_validator.gd`, `graph_builder.gd`, `layout_builder.gd`, `pacing_director.gd`, `room_role.gd`, `room_shape.gd`, `room_template.gd`, `seed_streams.gd`, `spawn_planner.gd`, `special_room_rule.gd`, `tactical_composer.gd`, `threat_model.gd`.
- `src/dungeon/world/dungeon_navigation.gd` through the coordinate adapter, subject to clearance verification.
- Existing room resources in `data/rooms/`; preserve original `data/depths/depth_01.tres`, `depth_02.tres`, `depth_03.tres`.
- Existing `.uid` companions and all legacy tests remain intact.

### Milestone 1: static 3D floor

- `src/game_3d/game_3d.tscn`, `src/game_3d/game_3d.gd`: separate launch fixture and orchestration, launched with F6/explicit scene path.
- `src/game_3d/world/grid_coordinates_3d.gd`: tile/pixel/metre conversion.
- `src/game_3d/world/dungeon_builder_3d.gd`: static mesh/collider assembly from validated layout.
- `src/game_3d/world/dungeon_world_3d.gd`: floor references/spawn/runtime signals.
- `src/game_3d/world/dungeon_navigation_3d.gd`: wrap existing grid queries; convert waypoints, validate clearance.
- `tools/dungeon_3d_test.gd`: generator identity, build geometry, movement/route integration checks.
- Initial selected campaign profile copies under `data/game_3d/depths/`; preserve baseline values and compare their output with their legacy source profiles before content changes.

### Milestone 2: combat floor

- `src/game_3d/player/samurai_3d.tscn`, `samurai_3d.gd`: inherited P1A body/Stage 2B input extension.
- `src/game_3d/input/combat_input.gd`: scene-owned keyboard/controller attack and dodge actions; no global binding edits.
- `src/game_3d/components/hitbox_3d.gd`, `hurtbox_3d.gd`, `melee_attack_3d.gd`, `dodge_3d.gd`: 3D damage/attack/mobility counterparts.
- `src/game_3d/enemies/enemy_3d.gd`, `enemy_3d.tscn`, `brute_3d.tscn`, `spitter_3d.tscn`, `spitter_3d.gd`, `enemy_projectile_3d.gd`, `enemy_projectile_3d.tscn`, `enemy_catalog_3d.gd`.
- `src/game_3d/world/dungeon_room_3d.gd`, `encounter_gate_3d.gd`: triggers, bounded encounters and safe gate lifecycle.
- `src/game_3d/ui/game_hud_3d.gd`, `game_hud_3d.tscn`: health, depth, seed and clear/death feedback.
- `tools/combat_3d_test.gd`: damage, occlusion, dodge, encounter and death/retry behavior.

### Milestones 3–4: rewards, guardians and campaign

- `src/game_3d/run/run_state_3d.gd`: run identity, health/build, depth and terminal state.
- `src/game_3d/run/campaign_3d.gd`: load game-specific profiles and boss/reward definitions; enforce depths 1–15.
- `src/game_3d/world/depth_exit_3d.gd`, `escape_exit_3d.gd`: intentional descent and final escape.
- `src/game_3d/world/spike_trap_3d.gd`, `water_zone_3d.gd`, `pit_zone_3d.gd`: introduce each only after its fair/readable behavior passes.
- `src/game_3d/rewards/reward_pickup_3d.gd`, `reward_pickup_3d.tscn`, `upgrade_definition_3d.gd`, `upgrade_choices_3d.gd`: one-time claims and a small compatible choice pool.
- `src/game_3d/bosses/boss_3d.gd`, `guardian_one_3d.gd`, `guardian_one_3d.tscn`, `guardian_two_3d.gd`, `guardian_two_3d.tscn`, `final_boss_3d.gd`, `final_boss_3d.tscn`: common encounter contract with three authored patterns.
- `data/game_3d/depths/depth_01.tres`, `depth_02.tres`, `depth_03.tres`, `depth_04.tres`, `depth_05.tres`, `depth_06.tres`, `depth_07.tres`, `depth_08.tres`, `depth_09.tres`, `depth_10.tres`, `depth_11.tres`, `depth_12.tres`, `depth_13.tres`, `depth_14.tres`, `depth_15.tres`.
- `data/game_3d/rooms/guardian_one_arena.tres`, `guardian_two_arena.tres`, `final_boss_arena.tres`: valid RoomTemplate objective arenas with static safe doors.
- `data/game_3d/campaign.tres`: boss mapping, limited upgrade definitions and campaign presentation references; keep DepthProfile responsible for generation settings.
- `tools/campaign_3d_test.gd`, `tools/generation_3d_stress.gd`: lifecycle/reward/boss tests and all-15-profile validation.

### Milestones 5–6: completion and delivery

- `src/game_3d/run/run_save_3d.gd`: versioned safe-boundary suspend/resume, validation and invalid-save recovery.
- `src/game_3d/ui/run_menu_3d.gd`, `run_menu_3d.tscn`: new run, retry, pause/settings, resume and results.
- Extend `tools/campaign_3d_test.gd` for disk persistence, terminal-state and repeated-run checks.
- `preservation/.gdignore` before imports; no change to snapshot contents.
- Update `DEVELOPMENT.md` and `CLAUDE.md` to the approved direction when implementation is authorized; preserve the historical Abyss documents.
- `project.godot` only for a separately approved final launch change; `export_presets.cfg` only when a release target/export is chosen. Neither is required to build the isolated prototype.

No edits are planned to the original 2D main, actors, combat components, world builder, HUD, camera, input configuration, generator algorithm or P1A fixtures. If a real limitation demands a shared change later, isolate and review that change with its regression evidence.

## Manual Git procedure — not executed

This procedure makes a backup branch in a separate worktree, commits only reviewed preservation material there, then creates the conventional-dungeon branch from that backup commit in another worktree. The original checkout remains on its original branch with its current dirty files. No stash, reset, clean, forced branch update, branch switch or history rewrite is needed. The new game inherits experimental source as preserved history; it simply does not reference those systems.

Run each block manually in PowerShell. Stop on any unexpected output. The commit is a preservation checkpoint, not acceptance of Stage 5A/5B or authorization to implement.

### 1. Read-only preflight

```powershell
$ErrorActionPreference = 'Stop'
$sourceRepo = 'C:\Users\raysh\Development\Dungeon-15'
$snapshotPath = Join-Path $sourceRepo 'preservation/scope-reset-20261020-085931'
$backupTree = 'C:\Users\raysh\Development\Dungeon15-stage5-backup'
$newTree = 'C:\Users\raysh\Development\Dungeon15-15-depths'
$backupBranch = 'backup/stage5ab-before-15-depths'
$newBranch = 'feature/conventional-15-depths'
$baseCommit = 'b3b24323a8d51d7ff90d739ac6be9d4baeaa7d40'

function Invoke-CheckedGit {
    & git @args
    if ($LASTEXITCODE -ne 0) { throw 'Git command failed; stop and inspect.' }
}

if ((Invoke-CheckedGit -C $sourceRepo rev-parse HEAD).Trim() -ne $baseCommit) {
    throw 'HEAD changed; review the transition procedure before continuing.'
}
Invoke-CheckedGit -C $sourceRepo status --short --branch
Invoke-CheckedGit -C $sourceRepo diff --cached --exit-code
Invoke-CheckedGit -C $sourceRepo diff --stat
Invoke-CheckedGit -C $sourceRepo worktree list
Invoke-CheckedGit -C $sourceRepo branch --list $backupBranch $newBranch
# If either proposed branch is listed, stop and choose unused names.
if ((Test-Path -LiteralPath $backupTree) -or (Test-Path -LiteralPath $newTree)) {
    throw 'A proposed worktree path already exists; choose a new empty destination.'
}
$manifest = Get-Content -LiteralPath (Join-Path $snapshotPath 'manifest.json') -Raw | ConvertFrom-Json
if ($manifest.Count -ne 30) { throw 'Unexpected manifest count.' }
foreach ($entry in $manifest) {
    foreach ($checkPath in @((Join-Path $sourceRepo $entry.path),
                            (Join-Path $snapshotPath ('files/' + $entry.path)))) {
        if ((Get-Item -LiteralPath $checkPath).Length -ne $entry.bytes -or
            (Get-FileHash -LiteralPath $checkPath -Algorithm SHA256).Hash -ne $entry.sha256) {
            throw "Recovery verification failed: $checkPath"
        }
    }
}
Invoke-CheckedGit -C $sourceRepo apply --reverse --check (Join-Path $snapshotPath 'tracked.patch')
```

Check that status still contains only the known Stage 5A/5B changes, the two planning documents and `preservation/`. Additional changes need their own preservation/review before continuing. The existing snapshot represents only the recorded 30 files.

### 2. Create and populate the backup worktree

```powershell
Invoke-CheckedGit -C $sourceRepo worktree add -b $backupBranch $backupTree $baseCommit
foreach ($entry in $manifest) {
    $copyFrom = Join-Path $snapshotPath ('files/' + $entry.path)
    $copyTo = Join-Path $backupTree $entry.path
    New-Item -ItemType Directory -Path (Split-Path $copyTo) -Force | Out-Null
    Copy-Item -LiteralPath $copyFrom -Destination $copyTo
    if ((Get-FileHash -LiteralPath $copyTo -Algorithm SHA256).Hash -ne $entry.sha256) {
        throw "Backup worktree copy differs: $($entry.path)"
    }
}
$planningPaths = @('docs/DUNGEON15_TRANSITION_PLAN.md',
                   'docs/DUNGEON15_APPROVAL_PREPARATION.md')
foreach ($relativePath in $planningPaths) {
    Copy-Item -LiteralPath (Join-Path $sourceRepo $relativePath) -Destination (Join-Path $backupTree $relativePath)
}
$backupPreservation = Join-Path $backupTree 'preservation'
New-Item -ItemType Directory -Path $backupPreservation | Out-Null
Copy-Item -LiteralPath $snapshotPath -Destination $backupPreservation -Recurse
# Godot must not import recovery copies as project source.
New-Item -ItemType File -Path (Join-Path $backupPreservation '.gdignore') | Out-Null

# Stage exact manifest paths, documents and the bounded snapshot, never git add .
foreach ($entry in $manifest) {
    Invoke-CheckedGit -C $backupTree add -- $entry.path
}
foreach ($relativePath in $planningPaths) {
    Invoke-CheckedGit -C $backupTree add -- $relativePath
}
Invoke-CheckedGit -C $backupTree add -- preservation/scope-reset-20261020-085931 preservation/.gdignore
Invoke-CheckedGit -C $backupTree diff --cached --stat
Invoke-CheckedGit -C $backupTree diff --cached --name-status
Invoke-CheckedGit -C $backupTree status --short --branch
```

Review the staged list and diff. It must contain the 30 preserved originals, two planning documents, the snapshot and `.gdignore`; no unrelated files or deletions. Inspect `git -C $backupTree diff --cached` if needed. Git may normalize line endings when staging; the retained manifest/snapshot remains the raw-byte recovery reference. Do not open Godot until `.gdignore` is present. Existing historical demo scripts are deliberately retained.

### 3. Make the manual preservation commit

Only after reviewing the staged content:

```powershell
Invoke-CheckedGit -C $backupTree commit -m 'backup: preserve Stage 5A/5B and 15-depth transition planning'
Invoke-CheckedGit -C $backupTree status --short
# Stop if status prints any entries; investigate before creating the new branch.
$backupCommit = (Invoke-CheckedGit -C $backupTree rev-parse HEAD).Trim()
Invoke-CheckedGit -C $backupTree show --stat --oneline HEAD
Invoke-CheckedGit -C $backupTree merge-base --is-ancestor $baseCommit $backupCommit
```

Do not bypass failing hooks or identity errors; resolve them and review again. This is a local backup branch; no remote backup exists unless a later explicit push is authorized.

### 4. Prepare the new development worktree, then stop

```powershell
Invoke-CheckedGit -C $sourceRepo worktree add -b $newBranch $newTree $backupCommit
Invoke-CheckedGit -C $newTree status --short --branch
Invoke-CheckedGit -C $newTree log -3 --oneline
Invoke-CheckedGit -C $newTree merge-base --is-ancestor $backupCommit HEAD
Invoke-CheckedGit -C $sourceRepo status --short --branch
Invoke-CheckedGit -C $sourceRepo worktree list
```

Expected: backup and new branches share the preservation commit; the new worktree is clean; original checkout remains on `3d-development-v2` with its original dirty work. The new worktree contains the original generator, accepted P1A/controller foundation and all historical experiments, ready for an isolated game root after milestone authorization.

Do not implement, switch the configured main scene, remove old files, or push. Obtain plan/milestone approval before editing gameplay. Keep the original dirty checkout intact; its cleanup is outside this procedure.
