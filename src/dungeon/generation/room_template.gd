class_name RoomTemplate
extends Resource
## One reusable room layout, authored as ASCII (legend in RoomShape and
## docs/DUNGEON_GENERATION.md), plus optional structural variants.
## Variants change the interior (walls, pillars, water, pits, sockets) but must
## keep the same size and door sockets as `layout`, so topology and corridors
## never depend on which variant is picked (the "variants" stream picks it).
## Geometry always lives in the layouts; `content_scene` is optional authored
## decoration/story content placed at the anchor (it must not add collision).

@export var id: StringName
@export var display_name: String
## Which pools may use this template: "entry", "main", "branch", "dead_end",
## "junction", "objective", "special", "environmental" (non-combat challenge
## spaces), "arena" (environmental rooms that may also host fights on their
## terrain), "risk" (risk/reward rooms: a '$' cache behind visible spikes).
## See `suits()` for how RoomRoles map onto these pools.
@export var roles: PackedStringArray = PackedStringArray(["main"])
## 0 small, 1 medium, 2 large. Selects encounter size from the depth profile.
@export_range(0, 2) var size_class: int = 1
@export var weight: float = 1.0
@export var combat_allowed: bool = true
@export_multiline var layout: String
## Alternative interiors (same size and door sockets as `layout`).
@export var variant_layouts: PackedStringArray = PackedStringArray()
## Short names for the variants, index 0 = `layout` (debug map / docs).
@export var variant_names: PackedStringArray = PackedStringArray()
@export var content_scene: PackedScene

var _shapes: Array[RoomShape] = []


func variant_count() -> int:
	return 1 + variant_layouts.size()


## Parsed shape of a variant (0 = base layout).
func get_shape(variant: int = 0) -> RoomShape:
	if _shapes.is_empty():
		_shapes.append(RoomShape.parse(layout))
		for text in variant_layouts:
			_shapes.append(RoomShape.parse(text))
	return _shapes[clampi(variant, 0, _shapes.size() - 1)]


func variant_name(variant: int) -> String:
	return variant_names[variant] if variant < variant_names.size() else "v%d" % variant


func has_role(role: String) -> bool:
	return roles.has(role)


## Whether this template belongs to the pool of a room with RoomRole `tactic`
## at graph position `graph_role`. "main"/"branch"/"dead_end" are position
## pools; "junction", "environmental", "arena" and "risk" are purpose pools.
func suits(tactic: int, graph_role: int) -> bool:
	var position := "main"
	if graph_role == DungeonGraph.Role.BRANCH:
		position = "branch"
	elif graph_role == DungeonGraph.Role.DEAD_END:
		position = "dead_end"
	match tactic:
		RoomRole.TRANSITION:
			return has_role("junction")
		RoomRole.HAZARD:
			# Dedicated environmental rooms, or a normal room whose hazard
			# sockets become spike patches that shape the routes through it.
			return has_role("environmental") or has_role(position)
		RoomRole.HAZARD_COMBAT:
			return has_role("arena") or has_role(position)
		RoomRole.RISK_REWARD:
			return has_role("risk")
		RoomRole.CHALLENGE:
			return has_role(position) and size_class >= 1
	return has_role(position)


## Problems across all variants, including variant/base mismatches.
func lint() -> PackedStringArray:
	var problems := PackedStringArray()
	var base := get_shape(0)
	for i in variant_count():
		var shape := get_shape(i)
		for e in shape.errors:
			problems.append("%s[%s]: %s" % [id, variant_name(i), e])
		if i > 0 and shape.socket_signature() != base.socket_signature():
			problems.append("%s[%s]: size/door sockets differ from the base layout" % [id, variant_name(i)])
	return problems


## Variant filters (Milestone 2.2): a room's role decides which interiors fit.
enum VariantFilter { ANY, CLEAN, TERRAIN }


## Uniform pick among the variants that parse cleanly and match `filter`
## (seeded by the caller). -1 if none matches.
func pick_variant(rng: RandomNumberGenerator, filter: int = VariantFilter.ANY) -> int:
	var valid := matching_variants(filter)
	return valid[rng.randi_range(0, valid.size() - 1)] if not valid.is_empty() else -1


func matching_variants(filter: int) -> Array[int]:
	var valid: Array[int] = []
	for i in variant_count():
		var shape := get_shape(i)
		if not shape.errors.is_empty():
			continue
		if filter == VariantFilter.CLEAN and not shape.is_clean():
			continue
		if filter == VariantFilter.TERRAIN and not shape.has_terrain():
			continue
		valid.append(i)
	return valid
