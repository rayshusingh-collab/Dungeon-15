class_name ThreatModel
extends RefCounted
## Deterministic, explainable difficulty score of a room (Milestone 2.2).
## Every point has a reason a designer (and `explain()`) can name:
##   enemies        EnemyCatalog threat per enemy
##   interactions   knockback enemy + pit, ranged enemy without cover,
##                  melee enemy + water (spacing)
##   fight context  locked doors (no retreat), spikes/pits in the arena,
##                  cramped arena (little clear space per enemy)
##   terrain        timed spike areas and chasms without enemies, risk areas
## TacticalComposer builds encounters under the depth's budget with this; the
## validator recomputes it independently and rejects anything over budget.

const LOCKED_ROOM := 0.5
const KNOCKBACK_NEAR_PIT := 1.0
const RANGED_WITHOUT_COVER := 0.75
const MELEE_IN_WATER := 0.25
const SPIKES_IN_FIGHT := 0.75
const PIT_IN_FIGHT := 0.5
const CRAMPED := 1.0
## Below this many strict-clear tiles per enemy the arena counts as cramped.
const CRAMPED_TILES_PER_ENEMY := 14
const TIMED_AREA := 0.5
const PIT_CROSSING := 0.5
const RISK_AREA := 0.75

## Maneuvering space: a fight room needs at least MANEUVER_BASE +
## MANEUVER_PER_ENEMY strict-clear tiles per enemy (validated).
const MANEUVER_BASE := 16
const MANEUVER_PER_ENEMY := 8


## What the room offers tactically, measured on the actual tiles.
class Features:
	var clear_tiles: int = 0
	var cover: bool = false
	var pit: bool = false
	var water: bool = false
	## Connected non-risk hazard areas (spikes) and risk areas.
	var spike_regions: int = 0
	var risk_regions: int = 0
	var doors: int = 0
	## Narrowest interior dimension (tiles), for "narrow hall" recipes.
	var narrow: bool = false


## `strict` is DungeonValidator.clear_mask(layout, false) for the current
## tiles; pass it when measuring many rooms (it is computed if omitted).
static func features(layout: DungeonLayout, room: DungeonLayout.PlacedRoom,
		strict: PackedByteArray = PackedByteArray()) -> Features:
	if strict.is_empty():
		strict = DungeonValidator.clear_mask(layout, false)
	var f := Features.new()
	var bounds := room.bounds()
	var w := layout.size.x
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			var i := y * w + x
			if layout.owners[i] != room.id:
				continue
			match layout.tiles[i]:
				DungeonLayout.Tile.OBSTACLE, DungeonLayout.Tile.INNER_WALL, DungeonLayout.Tile.RUBBLE:
					f.cover = true
				DungeonLayout.Tile.PIT:
					f.pit = true
				DungeonLayout.Tile.WATER:
					f.water = true
			f.clear_tiles += strict[i]
	for hazard in room.hazards:
		if hazard.get("purpose", &"") == RoomRole.PURPOSE_RISK_ROUTE:
			f.risk_regions += 1
		else:
			f.spike_regions += 1
	f.doors = room.doors.size()
	f.narrow = mini(room.shape.size.x, room.shape.size.y) <= 9
	return f


## Score of a room with these features holding `enemy_ids`.
static func score(f: Features, enemy_ids: Array[StringName], locked: bool) -> float:
	var t := 0.0
	for id in enemy_ids:
		t += EnemyCatalog.threat(id)
		if EnemyCatalog.has_tag(id, &"knockback") and f.pit:
			t += KNOCKBACK_NEAR_PIT
		if EnemyCatalog.has_tag(id, &"ranged") and not f.cover:
			t += RANGED_WITHOUT_COVER
		if EnemyCatalog.has_tag(id, &"melee") and f.water:
			t += MELEE_IN_WATER
	if not enemy_ids.is_empty():
		if locked:
			t += LOCKED_ROOM
		t += SPIKES_IN_FIGHT * f.spike_regions
		if f.pit:
			t += PIT_IN_FIGHT
		if f.clear_tiles < CRAMPED_TILES_PER_ENEMY * enemy_ids.size():
			t += CRAMPED
	else:
		t += TIMED_AREA * f.spike_regions
		if f.pit:
			t += PIT_CROSSING
	t += RISK_AREA * f.risk_regions
	return snappedf(t, 0.01)


static func is_locked(room: DungeonLayout.PlacedRoom) -> bool:
	return room.encounter == DungeonGraph.Encounter.COMBAT or room.encounter == DungeonGraph.Encounter.OPTIONAL


static func room_threat(layout: DungeonLayout, room: DungeonLayout.PlacedRoom,
		strict: PackedByteArray = PackedByteArray()) -> float:
	return score(features(layout, room, strict), room.enemy_ids, is_locked(room))


## Enemies a room can hold without being too cramped to maneuver.
static func maneuver_capacity(clear_tiles: int) -> int:
	return maxi(floori(float(clear_tiles - MANEUVER_BASE) / MANEUVER_PER_ENEMY), 0)


## Human-readable breakdown (debug overlay / map).
static func explain(layout: DungeonLayout, room: DungeonLayout.PlacedRoom,
		strict: PackedByteArray = PackedByteArray()) -> PackedStringArray:
	var f := features(layout, room, strict)
	var lines := PackedStringArray()
	for id in room.enemy_ids:
		lines.append("%s +%.2f" % [id, EnemyCatalog.threat(id)])
		if EnemyCatalog.has_tag(id, &"knockback") and f.pit:
			lines.append("knockback near chasm +%.2f" % KNOCKBACK_NEAR_PIT)
		if EnemyCatalog.has_tag(id, &"ranged") and not f.cover:
			lines.append("ranged, no cover +%.2f" % RANGED_WITHOUT_COVER)
		if EnemyCatalog.has_tag(id, &"melee") and f.water:
			lines.append("melee in water +%.2f" % MELEE_IN_WATER)
	if not room.enemy_ids.is_empty():
		if is_locked(room):
			lines.append("locked doors +%.2f" % LOCKED_ROOM)
		if f.spike_regions > 0:
			lines.append("spikes in the arena +%.2f" % (SPIKES_IN_FIGHT * f.spike_regions))
		if f.pit:
			lines.append("chasm in the arena +%.2f" % PIT_IN_FIGHT)
		if f.clear_tiles < CRAMPED_TILES_PER_ENEMY * room.enemy_ids.size():
			lines.append("cramped +%.2f" % CRAMPED)
	else:
		if f.spike_regions > 0:
			lines.append("timed spikes +%.2f" % (TIMED_AREA * f.spike_regions))
		if f.pit:
			lines.append("chasm crossing +%.2f" % PIT_CROSSING)
	if f.risk_regions > 0:
		lines.append("risk area +%.2f" % (RISK_AREA * f.risk_regions))
	return lines
