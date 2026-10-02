class_name DungeonWorld
extends Node2D
## The instantiated floor, built once per depth by DungeonBuilder:
##   Tiles (TileMapLayer, visuals) / Walls (one StaticBody2D with merged
##   rectangle shapes for walls, interior walls, pillars, rubble) / Terrain
##   (water and pit zones) / Hazards / Rooms (DungeonRoom + gates + triggers) /
##   Content (markers, authored room scenes, exit, event triggers) / Actors.
## Nothing here runs per-frame generation work; idle rooms cost nothing.
## Re-emits room and terrain events so Main only listens to one node.

signal room_entered(room: DungeonRoom)
signal encounter_started(room: DungeonRoom)
signal enemies_remaining_changed(room: DungeonRoom, count: int)
signal encounter_cleared(room: DungeonRoom)
signal marker_collected(marker: RoomMarker)
signal exit_reached
signal player_fell(player: Player)
signal tension_event(trigger: EventTrigger)

var layout: DungeonLayout
var navigation: DungeonNavigation
var rooms: Array[DungeonRoom] = []
var markers: Array[RoomMarker] = []
var hazards: Array[SpikeTrap] = []
var water_zones: Array[WaterZone] = []
var pit_zones: Array[PitZone] = []
var event_triggers: Array[EventTrigger] = []
var depth_exit: DepthExit
var actors: Node2D
var player_spawn: Vector2
var wall_shape_count: int = 0


func pixel_bounds() -> Rect2:
	return layout.pixel_bounds()


func get_room(space_id: int) -> DungeonRoom:
	return rooms[space_id] if space_id >= 0 and space_id < rooms.size() else null


func room_at(point: Vector2) -> DungeonRoom:
	var data := layout.room_at_tile(layout.tile_at(point))
	return rooms[data.id] if data != null else null


## Solid ground with room around it (no pit, spike or wall within a tile):
## where a fallen player may safely reappear.
func is_safe_ground(point: Vector2) -> bool:
	return layout.is_clear(layout.tile_at(point))


func get_enemies() -> Array[Enemy]:
	var result: Array[Enemy] = []
	for child in actors.get_children():
		var enemy := child as Enemy
		if enemy != null and enemy.state != Enemy.State.DEAD:
			result.append(enemy)
	return result


func _on_room_encounter_cleared(room: DungeonRoom) -> void:
	encounter_cleared.emit(room)
	if room.data.id == layout.graph.objective_id() and depth_exit != null:
		depth_exit.set_sealed(false)
