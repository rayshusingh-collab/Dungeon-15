class_name RoomRole
extends RefCounted
## Tactical purpose of a room (Milestone 2.2). Assigned per space by the
## PacingDirector before templates are chosen, so every room exists for a
## reason and the floor has a rhythm instead of combat after combat.
##
##   ENTRY          start; always safe
##   TRAVERSAL      quiet pass-through (may host a tension event)
##   TRANSITION     junction / crossroads between routes (3+ links)
##   EXPLORATION    discovery: lore or a future-secret sign
##   COMBAT         locked fight in a clean arena (pillars/walls as cover only)
##   HAZARD         environmental challenge without enemies (timing, crossing)
##   HAZARD_COMBAT  locked fight where the terrain matters (pits, water, spikes)
##   AMBUSH         unlocked fight triggered mid-room; always has another exit
##   REWARD         optional reward, no threat
##   RISK_REWARD    optional cache guarded by a visible risk; a safe route exists
##   REST           recovery shrine (heal), placed after heavy rooms
##   STORY          reserved special room
##   CHALLENGE      optional harder (elite placeholder) fight with a better reward
##   OBJECTIVE      depth exit (may be sealed by a fight)

enum {
	ENTRY, TRAVERSAL, TRANSITION, EXPLORATION, COMBAT, HAZARD, HAZARD_COMBAT, AMBUSH,
	REWARD, RISK_REWARD, REST, STORY, CHALLENGE, OBJECTIVE,
}

## Profile weight keys (DepthProfile.*_role_weights) -> role. "secret" is an
## EXPLORATION room with a future-secret marker instead of lore.
const KEYS := {
	"traversal": TRAVERSAL, "exploration": EXPLORATION, "secret": EXPLORATION, "combat": COMBAT,
	"hazard": HAZARD, "hazard_combat": HAZARD_COMBAT, "ambush": AMBUSH, "reward": REWARD,
	"risk_reward": RISK_REWARD, "rest": REST, "challenge": CHALLENGE,
}
const NAMES := [
	"ENTRY", "TRAVERSAL", "TRANSITION", "EXPLORATION", "COMBAT", "HAZARD", "HAZARD_COMBAT", "AMBUSH",
	"REWARD", "RISK_REWARD", "REST", "STORY", "CHALLENGE", "OBJECTIVE",
]

## Hazard purposes: why a hazard is there. Risk purposes are never required.
const PURPOSE_TIMING := &"timing"
const PURPOSE_ROUTE_SHAPING := &"route_shaping"
const PURPOSE_AREA_DENIAL := &"area_denial"
const PURPOSE_RISK_ROUTE := &"risk_route"


static func name_of(role: int) -> String:
	return NAMES[role] if role >= 0 and role < NAMES.size() else "?"


## A fight the player must deal with (pacing: heavy rooms need relief after them).
static func is_heavy(role: int) -> bool:
	return role == COMBAT or role == HAZARD_COMBAT or role == AMBUSH or role == CHALLENGE


## The room's challenge is mostly terrain (pacing: avoid trap after trap).
static func is_terrain_challenge(role: int) -> bool:
	return role == HAZARD or role == HAZARD_COMBAT or role == RISK_REWARD


static func has_enemies(role: int) -> bool:
	return is_heavy(role)


## Encounter kind for a role (OBJECTIVE fights are decided by the profile).
static func encounter_for(role: int) -> int:
	match role:
		COMBAT, HAZARD_COMBAT:
			return DungeonGraph.Encounter.COMBAT
		CHALLENGE:
			return DungeonGraph.Encounter.OPTIONAL
		AMBUSH:
			return DungeonGraph.Encounter.AMBUSH
	return DungeonGraph.Encounter.NONE


## Hazard purposes that may appear in a room with this role. Anything else is a
## hazard without a reason, which the validator rejects.
static func allowed_purposes(role: int) -> Array[StringName]:
	match role:
		HAZARD:
			return [PURPOSE_TIMING, PURPOSE_ROUTE_SHAPING]
		HAZARD_COMBAT:
			return [PURPOSE_TIMING, PURPOSE_AREA_DENIAL]
		RISK_REWARD:
			return [PURPOSE_RISK_ROUTE]
	return []


## Share of a room's optional structure sockets ('x' rubble, 'o' pillar) that
## the "dressing" stream turns solid, by purpose (M2.2 play-test polish):
## quiet spaces are furnished as ruins; fights keep open floor for maneuvering
## (their large rooms are deliberately open arenas); terrain rooms stay sparse
## so hazards read clearly; risk rooms and story chambers stay as authored
## (clean risk routes, authored content).
static func dressing_density(role: int) -> float:
	match role:
		TRAVERSAL, TRANSITION, EXPLORATION:
			return 0.85
		ENTRY, REWARD, REST:
			return 0.75
		AMBUSH:
			return 0.65
		COMBAT, OBJECTIVE, CHALLENGE:
			return 0.5
		HAZARD, HAZARD_COMBAT:
			return 0.3
	return 0.0


## Template size preference by purpose (template choice weight multiplier for
## size class 0 / 1 / 2): quiet and intimate rooms rarely need a large hall;
## fights prefer the space their maneuvering needs.
static func size_weight(role: int, size_class: int) -> float:
	var weights: Array = [1.0, 1.0, 1.0]
	match role:
		TRAVERSAL, EXPLORATION, REWARD, REST:
			weights = [1.4, 1.0, 0.3]
		COMBAT, HAZARD_COMBAT, CHALLENGE:
			weights = [0.7, 1.0, 1.3]
	return weights[clampi(size_class, 0, 2)]


## Roles whose template variant must carry terrain (pits, water, spikes or
## hazard sockets). Every other role uses "clean" variants (walls and pillars
## only), so dangerous terrain only ever appears where it is the point.
static func wants_terrain(role: int) -> bool:
	return is_terrain_challenge(role)
