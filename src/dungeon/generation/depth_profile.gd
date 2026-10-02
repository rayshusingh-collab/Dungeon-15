class_name DepthProfile
extends Resource
## Data-driven generation settings for one depth (res://data/depths/depth_NN.tres).
## New depths add a profile; no per-depth branching in code. Depth progression
## (Milestone 2.2) is expressed here: which room roles and tactical recipes a
## depth may use, and how much threat a room / the whole floor may carry.

const PROFILE_PATH := "res://data/depths/depth_%02d.tres"

@export var depth: int = 1
@export var display_name: String = "Depth"
## Environmental theme identifier for later presentation (tiles, props, music).
@export var theme_id: StringName = &"placeholder"
## One line on what this depth teaches or tests (debug map / docs).
@export var design_goal: String = ""

@export_group("Macro grid")
@export var grid_columns: int = 5
@export var grid_rows: int = 4
## Extra random width/height (tiles) per macro cell on top of what its room needs.
@export var cell_slack: int = 4

@export_group("Topology")
@export var main_path_min: int = 6
@export var main_path_max: int = 7
## Minimum macro-grid (Manhattan) distance between entry and objective.
@export var min_entry_exit_distance: int = 3
## Weight of turning vs. going straight on each main-path step (>1 = twistier).
@export var turn_bias: float = 1.6
## Weight multiplier for main-path steps that move away from the entry, so
## entry and objective end up apart (fewer "too close" retries).
@export var outward_bias: float = 1.5
@export var branch_min: int = 2
@export var branch_max: int = 3
@export var branch_length_min: int = 1
@export var branch_length_max: int = 2
## Chance a branch starts from an existing branch instead of the main path.
@export_range(0.0, 1.0) var sub_branch_chance: float = 0.2
@export_range(0.0, 1.0) var loop_chance: float = 0.4
@export var max_loops: int = 1

@export_group("Rooms")
@export var room_templates: Array[RoomTemplate] = []
@export var entry_templates: Array[RoomTemplate] = []
@export var objective_templates: Array[RoomTemplate] = []
@export var special_rooms: Array[SpecialRoomRule] = []

@export_group("Pacing")
## Relative weights of room roles (keys: RoomRole.KEYS) for main-path spaces,
## middle-of-branch spaces and dead ends. A missing key (or 0) means the role
## never appears there at this depth: this is how depths unlock mechanics.
@export var main_role_weights: Dictionary = {"combat": 3.0, "hazard": 1.5, "traversal": 1.5, "rest": 1.0}
@export var branch_role_weights: Dictionary = {"traversal": 2.0, "exploration": 1.0, "hazard": 1.0}
@export var dead_end_role_weights: Dictionary = {"reward": 3.0, "exploration": 2.0, "secret": 1.0, "challenge": 1.0}
## Chance a peaceful space with 3+ connections becomes a TRANSITION (junction room).
@export_range(0.0, 1.0) var junction_chance: float = 0.35
## Heavy rooms (fights) in a row on the main path; the objective fight may add one.
@export var max_consecutive_combat: int = 2
## Terrain-challenge rooms (hazard, hazard fight, risk) in a row on the main path.
@export var max_consecutive_terrain: int = 1
## Recovery rooms per floor (placed after heavy rooms).
@export var max_rest_rooms: int = 1
## Terrain challenges (hazard, hazard fight, risk) the main path must teach.
@export var min_terrain_rooms: int = 1

@export_group("Encounters")
@export var min_combat_rooms: int = 2
@export var objective_encounter: bool = false
@export var enemy_pool: Array[StringName] = [&"chaser"]
## Hard cap on enemies per encounter by template size class (small, medium,
## large). The threat budget usually decides first: difficulty comes from
## composition, not ever-larger counts.
@export var enemies_by_size: PackedInt32Array = PackedInt32Array([2, 3, 4])
## Composition recipes this depth may use (TacticalComposer.RECIPES keys).
@export var tactical_recipes: PackedStringArray = PackedStringArray(["open_brawl"])

@export_group("Threat budget")
## Maximum ThreatModel score of one fight room (COMBAT / HAZARD_COMBAT; the
## objective fight uses it too).
@export var room_threat_budget: float = 7.0
## Budget scale for unlocked ambushes and optional challenge fights.
@export var ambush_budget_scale: float = 0.8
@export var challenge_budget_scale: float = 1.3
## Maximum threat of rooms without enemies (hazard challenges, traversal...).
@export var quiet_room_threat_cap: float = 2.0
## Maximum threat of a risk/reward room (the risk is optional, but readable).
@export var risk_room_threat_cap: float = 3.0
## Maximum summed threat of the whole floor.
@export var floor_threat_budget: float = 40.0

@export_group("Events")
## Tension/event sockets armed per floor. Milestone 2.1 only fires a debug
## proof event; later milestones attach real thriller events here.
@export var armed_event_count: int = 1

@export_group("Hazards")
## Chance for each optional hazard socket region to be filled in rooms whose
## role wants hazards (HAZARD rooms; HAZARD_COMBAT rooms always get at least one).
@export_range(0.0, 1.0) var hazard_density: float = 0.4
@export var hazard_types: Array[StringName] = [&"spikes"]


static func path_for_depth(depth_index: int) -> String:
	return PROFILE_PATH % depth_index


static func exists_for_depth(depth_index: int) -> bool:
	return ResourceLoader.exists(path_for_depth(depth_index))


static func load_for_depth(depth_index: int) -> DepthProfile:
	if not exists_for_depth(depth_index):
		return null
	return load(path_for_depth(depth_index)) as DepthProfile


## Threat budget of a room with this role.
func threat_budget_for(role: int) -> float:
	match role:
		RoomRole.COMBAT, RoomRole.HAZARD_COMBAT, RoomRole.OBJECTIVE:
			return room_threat_budget
		RoomRole.AMBUSH:
			return room_threat_budget * ambush_budget_scale
		RoomRole.CHALLENGE:
			return room_threat_budget * challenge_budget_scale
		RoomRole.RISK_REWARD:
			return risk_room_threat_cap
		RoomRole.ENTRY, RoomRole.REST, RoomRole.REWARD, RoomRole.STORY:
			return 0.0
	return quiet_room_threat_cap


## Every role this profile may produce (weights > 0 plus structural roles and
## the fallbacks the director/layout may use).
func allowed_roles() -> Dictionary:
	var allowed := {RoomRole.ENTRY: true, RoomRole.OBJECTIVE: true, RoomRole.STORY: true,
		RoomRole.TRAVERSAL: true, RoomRole.TRANSITION: true, RoomRole.REWARD: true, RoomRole.COMBAT: true}
	for table: Dictionary in [main_role_weights, branch_role_weights, dead_end_role_weights]:
		for key: String in table:
			if float(table[key]) > 0.0 and RoomRole.KEYS.has(key):
				allowed[RoomRole.KEYS[key]] = true
	return allowed
