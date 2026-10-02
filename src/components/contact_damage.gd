class_name ContactDamage
extends Hitbox
## Body contact as an attack: while `armed`, touching the target's hurtbox is
## a hit, through the normal Hitbox -> Hurtbox -> HealthComponent path. So the
## target's invulnerability (after a hit, or from a dodge) applies, and several
## bodies touching on the same frame cost at most one hit: the first applies
## damage and starts the invulnerability window, the rest are refused.
## The owner decides when its body is dangerous (`armed`); the hitbox re-arms
## every `rearm_time` so sustained contact can hit again once the target's
## invulnerability has run out. Its shape should reach a few pixels past the
## owner's body, so contact means "touching", not "near". Knockback is radial
## (directional_bias 0 in the scenes): the body shoves the target away.

## Seconds between activations while armed (each activation hits a target once).
@export var rearm_time: float = 0.4

var armed: bool = false:
	set(value):
		armed = value
		if not armed:
			deactivate()
			_rearm_left = 0.0

var _rearm_left: float = 0.0


func _physics_process(delta: float) -> void:
	if not armed:
		return
	_rearm_left -= delta
	if _rearm_left <= 0.0:
		activate(false)
		_rearm_left = rearm_time
	super(delta)
