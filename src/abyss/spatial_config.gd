class_name AbyssSpatialConfig
extends Resource
## Bounded Stage 3 composition settings, independent of legacy generator version.

@export var profile: DepthProfile = preload("res://data/depths/depth_01.tres")
@export var min_room_size: Vector2i = Vector2i(10, 10)
@export var max_room_size: Vector2i = Vector2i(16, 16)
@export var cell_spacing: float = 36.0
@export var level_count: int = 3
@export var level_height: float = 4.0
@export var connection_width: float = 4.0
@export var max_attempts: int = 8


func errors() -> PackedStringArray:
	var result := PackedStringArray()
	if profile == null:
		result.append("missing topology profile")
	elif profile.grid_columns < 2 or profile.grid_rows < 2 or profile.grid_columns > 8 or profile.grid_rows > 8 \
			or profile.main_path_min < 3 or profile.main_path_max < profile.main_path_min \
			or profile.main_path_max > profile.grid_columns * profile.grid_rows \
			or profile.branch_min < 0 or profile.branch_max < profile.branch_min or profile.branch_max > 16 \
			or profile.branch_length_min < 1 or profile.branch_length_max < profile.branch_length_min \
			or profile.branch_length_max > 16 or profile.max_loops < 0 or profile.max_loops > 64:
		result.append("topology parameters outside bounded limits")
	if min_room_size.x < 8 or min_room_size.y < 8 or max_room_size.x < min_room_size.x \
			or max_room_size.y < min_room_size.y or max_room_size.x > 24 or max_room_size.y > 24:
		result.append("room sizes require 8 <= minimum <= maximum <= 24 metres")
	if level_count < 2 or level_count > 5 or not is_finite(level_height) or level_height < 2 or level_height > 5:
		result.append("require 2–5 levels, spaced 2–5 metres")
	if not is_finite(connection_width) or connection_width < 3 or connection_width > 4:
		result.append("connection width must be 3–4 metres")
	if not is_finite(cell_spacing) or cell_spacing > 80 \
			or cell_spacing - maxf(max_room_size.x, max_room_size.y) < level_height / 0.35 + 1.0:
		result.append("cell spacing leaves insufficient safe ramp run")
	if max_attempts < 1 or max_attempts > 16:
		result.append("attempt limit must be 1–16")
	return result
