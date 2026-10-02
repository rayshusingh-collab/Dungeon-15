class_name EnemyCatalog
extends RefCounted
## Maps the enemy ids used by generation (DepthProfile.enemy_pool) to scenes
## and tactical data. Milestone 2.2 archetypes are PLACEHOLDERS that exist to
## exercise encounter composition (roles), not the final roster:
##   chaser   melee pressure / pursuit (Milestone 1 enemy)
##   brute    slow, heavy knockback, body-blocks (dangerous near pits)
##   spitter  keeps distance, telegraphed slow projectile (cover matters)
## `threat` feeds ThreatModel; `tags` feed TacticalComposer recipes.

const ARCHETYPES: Dictionary = {
	&"chaser": {"scene": "res://src/enemies/enemy.tscn", "threat": 2.0,
		"tags": [&"melee", &"pursuit"], "letter": "C"},
	&"brute": {"scene": "res://src/enemies/brute.tscn", "threat": 3.0,
		"tags": [&"melee", &"knockback", &"blocking"], "letter": "B"},
	&"spitter": {"scene": "res://src/enemies/spitter.tscn", "threat": 2.5,
		"tags": [&"ranged", &"area_denial"], "letter": "S"},
}


static func has(enemy_id: StringName) -> bool:
	return ARCHETYPES.has(enemy_id)


static func instantiate(enemy_id: StringName) -> Enemy:
	return (load(ARCHETYPES[enemy_id].scene) as PackedScene).instantiate() as Enemy


static func threat(enemy_id: StringName) -> float:
	return float(ARCHETYPES[enemy_id].threat) if has(enemy_id) else 0.0


static func has_tag(enemy_id: StringName, tag: StringName) -> bool:
	return has(enemy_id) and (ARCHETYPES[enemy_id].tags as Array).has(tag)


## One-letter code for debug views.
static func letter(enemy_id: StringName) -> String:
	return ARCHETYPES[enemy_id].letter if has(enemy_id) else "?"
