class_name SpikeTrap
extends Node2D
## Timed floor spikes (placeholder mechanical hazard). Cycle:
##   RETRACTED (safe, holes)  -> WARNING (red outline + rising tips + a
##   progress bar that fills to the strike) -> RAISED (bright spikes, hurts).
## Damage goes through a normal Hitbox -> Hurtbox -> HealthComponent path, so
## invulnerability and dodge work exactly as for any other hit. Raised spikes
## hurt enemies too (Milestone 2.2): baiting attackers across them is a tactic.
## Regions are capped (RoomShape.MAX_TIMED_REGION) so one safe window is always
## enough to cross.

enum Phase { RETRACTED, WARNING, RAISED }

@export var retracted_time: float = 1.4
@export var warning_time: float = 0.6
@export var raised_time: float = 0.5
@export var damage: int = 1

var phase: Phase = Phase.RETRACTED

var _time_left: float = 0.0
var _local_tiles: Array[Rect2] = []
var _hitbox: Hitbox


## `tiles` are world tile coordinates. `phase_offset` staggers traps (seconds).
func setup(tiles: Array[Vector2i], phase_offset: float) -> void:
	var center := Vector2.ZERO
	for t in tiles:
		center += Vector2((t.x + 0.5) * DungeonLayout.TILE_SIZE, (t.y + 0.5) * DungeonLayout.TILE_SIZE)
	center /= maxf(tiles.size(), 1)
	position = center
	_hitbox = Hitbox.new()
	_hitbox.requires_line_of_sight = false
	_hitbox.damage = damage
	_hitbox.directional_bias = 0.0
	_hitbox.collision_layer = 0
	_hitbox.collision_mask = 8 | 16 # player_hurtbox, enemy_hurtbox
	_hitbox.monitorable = false
	for t in tiles:
		var tile_center := Vector2((t.x + 0.5) * DungeonLayout.TILE_SIZE, (t.y + 0.5) * DungeonLayout.TILE_SIZE) - center
		var rect := Rect2(tile_center - Vector2.ONE * DungeonLayout.TILE_SIZE / 2.0, Vector2.ONE * DungeonLayout.TILE_SIZE)
		_local_tiles.append(rect)
		var shape := RectangleShape2D.new()
		shape.size = Vector2.ONE * (DungeonLayout.TILE_SIZE - 6)
		var node := CollisionShape2D.new()
		node.shape = shape
		node.position = tile_center
		_hitbox.add_child(node)
	add_child(_hitbox)
	var cycle := retracted_time + warning_time + raised_time
	_time_left = retracted_time - fmod(phase_offset, cycle)
	if _time_left <= 0.0:
		_time_left += cycle


func is_dangerous() -> bool:
	return phase == Phase.RAISED


func _physics_process(delta: float) -> void:
	_time_left -= delta
	if _time_left > 0.0:
		return
	match phase:
		Phase.RETRACTED:
			phase = Phase.WARNING
			_time_left += warning_time
		Phase.WARNING:
			phase = Phase.RAISED
			_time_left += raised_time
			_hitbox.activate(false)
		Phase.RAISED:
			phase = Phase.RETRACTED
			_time_left += retracted_time
			_hitbox.deactivate()
	queue_redraw()


func _process(_delta: float) -> void:
	if phase == Phase.WARNING:
		queue_redraw()


func _draw() -> void:
	var blink := fmod(_time_left, 0.2) > 0.1
	var bounds := _local_tiles[0]
	for rect in _local_tiles:
		bounds = bounds.merge(rect)
	for rect in _local_tiles:
		draw_rect(rect.grow(-1.0), Color("2a1414"))
		var c := rect.get_center()
		match phase:
			Phase.RETRACTED:
				for o: Vector2 in [Vector2(-7, -7), Vector2(7, -7), Vector2(-7, 7), Vector2(7, 7)]:
					draw_circle(c + o, 2.5, Color(0.08, 0.05, 0.05))
			Phase.WARNING:
				var tint := Color(1, 0.35, 0.3) if blink else Color(0.6, 0.25, 0.25)
				for o: Vector2 in [Vector2(-7, -7), Vector2(7, -7), Vector2(-7, 7), Vector2(7, 7)]:
					_spike(c + o, 4.0, tint)
			Phase.RAISED:
				for o: Vector2 in [Vector2(-7, -7), Vector2(7, -7), Vector2(-7, 7), Vector2(7, 7)]:
					_spike(c + o, 8.0, Color(0.92, 0.9, 0.95))
	# Region-level readability: a dashed hint when safe, a red outline and a
	# filling bar during the warning, a solid red outline while raised.
	match phase:
		Phase.RETRACTED:
			draw_rect(bounds, Color(0.8, 0.3, 0.3, 0.25), false, 1.0)
		Phase.WARNING:
			draw_rect(bounds, Color(1, 0.3, 0.25, 0.9 if blink else 0.5), false, 3.0)
			var fill := 1.0 - clampf(_time_left / warning_time, 0.0, 1.0)
			draw_rect(Rect2(bounds.position + Vector2(0, -8), Vector2(bounds.size.x * fill, 4)), Color(1, 0.35, 0.3))
		Phase.RAISED:
			draw_rect(bounds, Color(1, 0.2, 0.2, 0.95), false, 3.0)


func _spike(at: Vector2, height: float, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array([at + Vector2(-4, 3), at + Vector2(4, 3), at + Vector2(0, 3 - height)]), color)
