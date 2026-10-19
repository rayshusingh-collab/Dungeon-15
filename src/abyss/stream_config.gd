class_name AbyssStreamConfig
extends Resource

@export var world_radius: int = 8
@export var load_radius: int = 1
@export var jobs_per_frame: int = 1
@export var cell_spacing: float = 36.0
@export var min_room_size: int = 10
@export var max_room_size: int = 16
@export var level_count: int = 3
@export var level_height: float = 4.0
@export var retry_frames: int = 30
@export var max_attempts: int = 3


func errors() -> PackedStringArray:
	var result := PackedStringArray()
	if world_radius < 2 or world_radius > 16 or load_radius < 1 or load_radius > 2:
		result.append("world radius requires 2–16; load radius requires 1–2")
	if jobs_per_frame < 1 or jobs_per_frame > 2 or retry_frames < 2 or retry_frames > 600 \
			or max_attempts < 1 or max_attempts > 5:
		result.append("invalid streaming work/retry limits")
	if min_room_size < 8 or max_room_size < min_room_size or max_room_size > 24:
		result.append("room sizes require 8 <= minimum <= maximum <= 24")
	if level_count < 2 or level_count > 5 or not is_finite(level_height) or level_height < 2 or level_height > 5 \
			or not is_finite(cell_spacing) or cell_spacing > 80 \
			or cell_spacing - max_room_size < level_height / 0.35 + 1:
		result.append("invalid elevations or insufficient safe ramp spacing")
	return result


func capacity() -> int:
	return (2 * load_radius + 1) * (2 * load_radius + 1)


func contains(cell: Vector2i) -> bool:
	return absi(cell.x) <= world_radius and absi(cell.y) <= world_radius


func identity() -> String:
	# Scheduling/radius settings do not alter geometry identity.
	return "%d|%.6f|%d|%d|%d|%.6f" % [world_radius, cell_spacing,
		min_room_size, max_room_size, level_count, level_height]
