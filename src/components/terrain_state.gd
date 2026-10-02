class_name TerrainState
extends Node
## Tracks which terrain zones (water, later mud, ice...) an actor stands in.
## Zones register by instance id; the strongest slowdown wins. Actors read
## speed_scale(); zones never touch actor internals. Signals are the hook for
## later splash VFX, footstep audio and similar reactions.

signal terrain_entered(kind: StringName)
signal terrain_exited(kind: StringName)

## zone instance id -> {kind: StringName, speed_scale: float}
var _zones: Dictionary = {}


func enter_zone(zone_id: int, kind: StringName, zone_speed_scale: float) -> void:
	var was_in := is_in(kind)
	_zones[zone_id] = {"kind": kind, "speed_scale": zone_speed_scale}
	if not was_in:
		terrain_entered.emit(kind)


func exit_zone(zone_id: int) -> void:
	if not _zones.has(zone_id):
		return
	var kind: StringName = _zones[zone_id].kind
	_zones.erase(zone_id)
	if not is_in(kind):
		terrain_exited.emit(kind)


func clear() -> void:
	var kinds := {}
	for zone: Dictionary in _zones.values():
		kinds[zone.kind] = true
	_zones.clear()
	for kind: StringName in kinds:
		terrain_exited.emit(kind)


func is_in(kind: StringName) -> bool:
	for zone: Dictionary in _zones.values():
		if zone.kind == kind:
			return true
	return false


func speed_scale() -> float:
	var result := 1.0
	for zone: Dictionary in _zones.values():
		result = minf(result, zone.speed_scale)
	return result
