class_name Hitbox
extends Area2D
## Damaging area. While active it hits every overlapping Hurtbox at most once
## per activation, so a single swing can never multi-hit the same target.
## Its global_position is the attacker's centre and its global rotation the
## attack direction; receivers use get_knockback_direction().

signal hit_landed(hurtbox: Hurtbox)

@export var damage: int = 1
## How much knockback follows the swing direction instead of pointing straight
## away from the attacker (0 = purely radial). Makes hits feel directional.
@export var directional_bias: float = 1.0

var active: bool = false

var _already_hit: Array[Hurtbox] = []
var _skip_frame: bool = false


## `skip_first_frame`: overlaps are refreshed by the physics step, so if the
## hitbox was rotated/moved this frame its results are one step stale.
func activate(skip_first_frame: bool = true) -> void:
	active = true
	_skip_frame = skip_first_frame
	_already_hit.clear()


func deactivate() -> void:
	active = false


func get_knockback_direction(target_position: Vector2) -> Vector2:
	var radial := (target_position - global_position).normalized()
	var forward := Vector2.from_angle(global_rotation)
	var direction := radial + forward * directional_bias
	return direction.normalized() if direction != Vector2.ZERO else forward


func _physics_process(_delta: float) -> void:
	if not active:
		return
	if _skip_frame:
		_skip_frame = false
		return
	for area: Area2D in get_overlapping_areas():
		var hurtbox := area as Hurtbox
		if hurtbox == null or _already_hit.has(hurtbox):
			continue
		_already_hit.append(hurtbox)
		if hurtbox.receive_hit(self):
			hit_landed.emit(hurtbox)
