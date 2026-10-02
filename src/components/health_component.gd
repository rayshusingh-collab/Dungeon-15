class_name HealthComponent
extends Node
## Reusable hit points + invulnerability window. Owners react through signals;
## this node knows nothing about visuals or who owns it.

signal health_changed(current: int, maximum: int)
signal damaged(amount: int)
signal died

@export var max_health: int = 3
## Invulnerability granted automatically after each successful hit.
@export var invulnerability_after_hit: float = 0.0

var current: int

var _invulnerable_left: float = 0.0


func _ready() -> void:
	current = max_health


func _physics_process(delta: float) -> void:
	if _invulnerable_left > 0.0:
		_invulnerable_left = maxf(_invulnerable_left - delta, 0.0)


## Applies damage unless dead or invulnerable. Returns true if it was applied.
func take_damage(amount: int) -> bool:
	if amount <= 0 or is_dead() or is_invulnerable():
		return false
	current = maxi(current - amount, 0)
	_invulnerable_left = maxf(_invulnerable_left, invulnerability_after_hit)
	health_changed.emit(current, max_health)
	damaged.emit(amount)
	if current == 0:
		died.emit()
	return true


## Restores up to `amount` health (never above max, never when dead).
## Returns the amount actually restored.
func heal(amount: int) -> int:
	if amount <= 0 or is_dead():
		return 0
	var restored := mini(amount, max_health - current)
	if restored > 0:
		current += restored
		health_changed.emit(current, max_health)
	return restored


func is_full() -> bool:
	return current >= max_health


## Extends (never shortens) the current invulnerability window.
func grant_invulnerability(duration: float) -> void:
	_invulnerable_left = maxf(_invulnerable_left, duration)


func is_invulnerable() -> bool:
	return _invulnerable_left > 0.0


func is_dead() -> bool:
	return current <= 0
