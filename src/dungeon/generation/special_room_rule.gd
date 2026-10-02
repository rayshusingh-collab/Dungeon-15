class_name SpecialRoomRule
extends Resource
## Reserves a handcrafted room (story chamber, guardian arena, boss arena...)
## on the main path of a generated depth. The generator places it at
## `main_path_fraction` along the path (never on the entry or objective) and
## gives it exactly two connections (in and out), so authored rooms can rely
## on a predictable flow. Special rooms never get loops, branches or hazards.

@export var id: StringName
@export var template: RoomTemplate
## 0 = right after the entry, 1 = right before the objective.
@export_range(0.0, 1.0) var main_path_fraction: float = 0.5
@export var required: bool = true
