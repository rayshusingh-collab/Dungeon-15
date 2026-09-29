class_name Hurtbox
extends Area2D
## Damageable area. Forwards hits from a Hitbox to its HealthComponent and
## emits hit_received only when damage was actually applied (not while
## invulnerable or dead). Set monitoring = false; hitboxes do the detecting.

signal hit_received(hitbox: Hitbox)

@export var health: HealthComponent


func receive_hit(hitbox: Hitbox) -> bool:
	if health == null or not health.take_damage(hitbox.damage):
		return false
	hit_received.emit(hitbox)
	return true
