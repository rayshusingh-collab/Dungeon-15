class_name DungeonRoom
extends Node2D
## Runtime side of one generated room: tracks visits and runs its encounter.
##   NONE      no encounter; free to explore
##   DORMANT   encounter waiting; doorways show a faint red hint
##   ACTIVE    player stepped fully inside: gates lock, spawn points flash,
##             enemies appear after spawn_delay, far from the player
##   CLEARED   all enemies dead: gates open for good
## The trigger is inset from the walls, so gates never close on a player who
## is still standing in a doorway.
## AMBUSH encounters (Milestone 2.2) never lock: there are no gates, the
## enemies keep their leash, and the player may fight at a doorway or leave
## (the validator guarantees an ambush room has another exit).

signal entered(room: DungeonRoom)
signal encounter_started(room: DungeonRoom)
signal enemies_remaining_changed(room: DungeonRoom, count: int)
signal encounter_cleared(room: DungeonRoom)

enum EncounterState { NONE, DORMANT, ACTIVE, CLEARED }

## Tiles between the room walls and the encounter trigger.
const TRIGGER_INSET_TILES := 2

@export var spawn_delay: float = 0.6

var data: DungeonLayout.PlacedRoom
var state: EncounterState = EncounterState.NONE
var visited: bool = false
var gates: Array[EncounterGate] = []
var enemies: Array[Enemy] = []

var _actors: Node2D
var _layout: DungeonLayout
var _navigation: DungeonNavigation
var _living: int = 0


func setup(room_data: DungeonLayout.PlacedRoom, layout: DungeonLayout, actors: Node2D,
		navigation: DungeonNavigation = null) -> void:
	data = room_data
	_layout = layout
	_actors = actors
	_navigation = navigation
	name = "Room%d" % room_data.id
	var tile := DungeonLayout.TILE_SIZE
	var bounds := room_data.bounds()
	var inner := Rect2(Vector2(bounds.position * tile), Vector2(bounds.size * tile)).grow(-(1 + TRIGGER_INSET_TILES) * tile)
	var trigger := Area2D.new()
	trigger.name = "Trigger"
	trigger.collision_layer = 0
	trigger.collision_mask = 2
	trigger.monitorable = false
	var shape := RectangleShape2D.new()
	shape.size = inner.size
	var node := CollisionShape2D.new()
	node.shape = shape
	node.position = inner.get_center()
	trigger.add_child(node)
	add_child(trigger)
	trigger.body_entered.connect(_on_trigger_body_entered)
	if room_data.encounter != DungeonGraph.Encounter.NONE:
		state = EncounterState.DORMANT
	if locks_doors():
		for door in room_data.doors:
			var gate := EncounterGate.new()
			gate.name = "Gate%d" % door.link
			var first := layout.tile_center(door.tiles[0])
			var last := layout.tile_center(door.tiles[door.tiles.size() - 1])
			var horizontal: bool = door.side == RoomShape.Side.NORTH or door.side == RoomShape.Side.SOUTH
			gate.setup((first + last) / 2.0, Vector2(tile * RoomShape.CORRIDOR_WIDTH, tile) if horizontal
					else Vector2(tile, tile * RoomShape.CORRIDOR_WIDTH))
			add_child(gate)
			gates.append(gate)


func has_encounter() -> bool:
	return state != EncounterState.NONE


## Locked fights seal the doors; ambushes leave them open.
func locks_doors() -> bool:
	return data.encounter == DungeonGraph.Encounter.COMBAT or data.encounter == DungeonGraph.Encounter.OPTIONAL


func is_ambush() -> bool:
	return data.encounter == DungeonGraph.Encounter.AMBUSH


func pixel_rect() -> Rect2:
	var tile := DungeonLayout.TILE_SIZE
	var bounds := data.bounds()
	return Rect2(Vector2(bounds.position * tile), Vector2(bounds.size * tile))


func _on_trigger_body_entered(body: Node2D) -> void:
	var player := body as Player
	if player == null:
		return
	if not visited:
		visited = true
		entered.emit(self)
	if state == EncounterState.DORMANT and not player.is_dead():
		start_encounter(player)


func start_encounter(player: Player) -> void:
	if state != EncounterState.DORMANT:
		return
	state = EncounterState.ACTIVE
	for gate in gates:
		gate.set_state(EncounterGate.State.LOCKED)
	var points := choose_spawn_points(player.global_position)
	for point in points:
		BurstEffect.spawn(_actors, point, BurstEffect.Style.RING, Color(1, 0.3, 0.25, 0.9), 34.0, 8.0, spawn_delay)
	_living = points.size()
	encounter_started.emit(self)
	enemies_remaining_changed.emit(self, _living)
	var tween := create_tween()
	tween.tween_interval(spawn_delay)
	tween.tween_callback(_spawn_enemies.bind(points, player))


## One point per enemy (data.enemy_ids order), planned by SpawnPlanner from
## where the player triggered the room: the recipe's lead enemies start where
## the terrain matters, everyone starts a fair distance away. The generator and
## validator use the same plan.
func choose_spawn_points(from: Vector2) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for t in SpawnPlanner.plan(_layout, data, from):
		if t != SpawnPlanner.NONE:
			result.append(_layout.tile_center(t))
	return result


func _spawn_enemies(points: Array[Vector2], player: Player) -> void:
	for i in points.size():
		var enemy := EnemyCatalog.instantiate(data.enemy_ids[i])
		enemy.position = points[i]
		enemy.target = player
		enemy.navigator = _navigation
		# Alternate flank sides so a group fans out both ways around the player.
		enemy.flank_sign = 1.0 if i % 2 == 0 else -1.0
		enemy.died.connect(_on_enemy_died)
		_actors.add_child(enemy)
		# Sealed fight: engage at once and never leash away from it. Open ambush:
		# engage at once but keep the leash, so running away is a real option.
		enemy.engage(INF if locks_doors() else enemy.leash_range)
		enemies.append(enemy)


func _on_enemy_died(enemy: Enemy) -> void:
	enemies.erase(enemy)
	_living -= 1
	enemies_remaining_changed.emit(self, _living)
	if _living <= 0 and state == EncounterState.ACTIVE:
		state = EncounterState.CLEARED
		for gate in gates:
			gate.set_state(EncounterGate.State.OPEN)
		encounter_cleared.emit(self)
