extends "res://tools/test_harness.gd"

const Director = preload("res://src/abyss/castle_director.gd")
const Scene = preload("res://src/abyss/living_demo.tscn")
var _floor_safe: bool = true
var _bounded: bool = true


func _suite_name() -> String:
	return "ABYSS LIVING"


func _get_tests() -> Array[Callable]:
	return [_test_schedule, _test_occupied_warning, _test_redirection_and_streaming, _test_active_eviction_and_handover]


func _test_schedule() -> bool:
	var a := Director.new({}, "same-world")
	var b := Director.new({}, "same-world")
	for i in 240:
		a.advance(1.0 / 60, true, false)
		seed(123 + i)
		randi()
		b.advance(1.0 / 60, true, false)
	_check(a.state == b.state and not a.state.active.is_empty(), "same seed/world facts and time produce deterministic event identity and schedule")
	_check(a.state.active.phase == "warning", "zone event warns before changing routes")
	_check(not a.request("release", "direct") and a.max_active == 1, "only one active gameplay transformation can be scheduled")
	var state: Dictionary = a.state
	a.complete()
	_check(state.stable == "redirected" and state.events.threshold == a.event_id("threshold"), "committed event identity is stable and recorded once")
	_check(not a.request("release", "direct"), "cooldown blocks immediate scripted restoration")
	for i in 300:
		a.advance(1.0 / 60, true, true)
	_check(a.state.active.is_empty(), "milestone does not bypass cooldown")
	for i in 100:
		a.advance(1.0 / 60, true, true)
	_check(a.state.active.get("key", "") == "release" and a.state.ambient_intensity == 1.5, "milestone schedules predefined restoration after cooldown and changes ambient intensity")
	a.complete()
	for i in 600:
		a.advance(1.0 / 60, true, true)
	_check(a.state.active.is_empty() and a.state.events.size() == 3, "events are deduplicated with bounded history and no repeated route churn")
	_check(not a.request("arbitrary", "redirected") and not a.request("threshold", "direct"), "unrestricted or mismatched scripted changes are rejected")
	var restored := Director.new(a.state, "same-world")
	_check(restored.state == a.state and restored.event_id("threshold") == b.event_id("threshold"), "director reconstruction preserves stable state/event IDs")
	var clock: float = restored.state.clock
	var ambient_clock: float = restored.state.ambient_clock
	restored.advance(10, false, false)
	_check(restored.state.clock == clock and restored.state.ambient_clock > ambient_clock, "unloaded/far gameplay schedule pauses while decorative clock continues")
	var scripted := Director.new({}, "scripted-world")
	_check(scripted.request("threshold", "redirected") and scripted.state.zone_seen,
		"scripted threshold consumes the zone trigger to prevent later duplicate scheduling")
	scripted.complete()
	for i in 1200:
		scripted.advance(1.0 / 60, true, false)
	_check(scripted.state.active.get("key", "") == "release", "scripted redirection still receives its automatic timed restoration")
	return true


func _new_demo() -> Node3D:
	var demo := Scene.instantiate()
	root.add_child(demo)
	await _frames(30)
	return demo


func _test_occupied_warning() -> bool:
	var demo: Node3D = await _new_demo()
	var stream: Node3D = demo.get_node("Streamer")
	var player: CharacterBody3D = demo.get_node("Player3D")
	var camera: Camera3D = demo.get_node("Camera")
	# Keep the first warning long enough to walk onto the currently safe bridge.
	stream.director.trigger_seconds = 100
	var midpoint: Vector3 = (stream.bridge.link.start + stream.bridge.link.end) * 0.5
	_check(await _walk(stream, player, camera, midpoint), "player can stand on initial direct bridge before a shift")
	stream.director.request("threshold", "redirected")
	var pose: Transform3D = stream.bridge.deck.transform
	await _frames(90)
	_check(stream.state().active.phase == "warning" and stream.bridge.deck.collision_layer == 1
		and stream.bridge.deck.transform.is_equal_approx(pose), "warning preserves visible collision under the player")
	await _frames(150)
	_check(stream.state().active.phase == "waiting" and stream.bridge.deck.collision_layer == 1
		and player.is_on_floor() and stream.state().pose == 1, "occupied supporting bridge defers withdrawal indefinitely without removing collision")
	_check(await _walk(stream, player, camera, Vector3.ZERO), "player leaves the warned bridge without trapping or teleportation")
	_check(await _wait_until(func() -> bool: return stream.state().stable == "redirected", 300), "clear structure can safely complete automatic withdrawal")
	_check(stream.bridge.deck.collision_layer == 0 and stream.state().pose == 0, "withdrawn bridge has no invisible traversable collision")
	demo.queue_free()
	await process_frame
	return true


func _test_redirection_and_streaming() -> bool:
	var demo: Node3D = await _new_demo()
	var stream: Node3D = demo.get_node("Streamer")
	var player: CharacterBody3D = demo.get_node("Player3D")
	var camera: Camera3D = demo.get_node("Camera")
	var ambient: Node3D = demo.get_node("AmbientArchitecture")
	_check(stream.required_route_valid("direct") and stream.required_route_valid("redirected") and stream.required_route_valid("both"),
		"all world chunks and required objective remain connected in both predefined states and handover")
	var decorative_before: Transform3D = ambient.get_child(0).transform
	await _frames(45)
	_check(not ambient.get_child(0).transform.is_equal_approx(decorative_before), "surrounding architecture visibly moves with stationary player")
	_check(_collision_nodes(ambient) == 0 and ambient.get_child_count() == 12,
		"ambient budget is fixed at twelve structures and contains no collision")
	_check(await _wait_until(func() -> bool: return stream.state().stable == "redirected", 600), "proximity/time rule automatically redirects route without manual interaction")
	_check(not stream._edge_open(Vector2i.ZERO, Vector2i.RIGHT) and stream._edge_open(Vector2i.ZERO, Vector2i.DOWN),
		"east bridge becomes unavailable while previously closed southern passage opens")
	# Keep the default restoration from interrupting the deliberate revisit portion.
	stream.director.redirect_seconds = 1000
	stream.state().release_at = stream.state().clock + 1000
	var old: WeakRef = weakref(stream.bridge)
	var event_id: String = stream.state().events.threshold
	var traveled := true
	for cell in [Vector2i(-1, 0), Vector2i(-2, 0), Vector2i(-3, 0)]:
		traveled = await _walk(stream, player, camera, stream.catalog.room(cell).center) and traveled
	var updates: int = stream.pose_updates
	var clock: float = stream.state().clock
	await _frames(60)
	_check(traveled and old.get_ref() == null and stream.bridge == null and stream.pose_updates == updates
		and stream.state().clock == clock, "evicted/far gameplay bridge receives no pose or schedule updates")
	for cell in [Vector2i(-2, 0), Vector2i(-1, 0), Vector2i.ZERO]:
		traveled = await _walk(stream, player, camera, stream.catalog.room(cell).center) and traveled
	_check(traveled and stream.bridge.deck.collision_layer == 0 and stream.state().pose == 0
		and stream.state().events.threshold == event_id, "revisit restores lowered bridge and deterministic director state without repeating event")
	for cell in [Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 0)]:
		traveled = await _walk(stream, player, camera, stream.catalog.room(cell).center) and traveled
	_check(traveled and stream.state().milestone, "player reaches Wayfinder objective through the alternate streamed route")
	_check(await _wait_until(func() -> bool: return stream.state().stable == "direct", 700), "Castle Master milestone restores direct connection through a warned transition")
	_check(stream.bridge.deck.collision_layer == 1 and stream.state().pose == 1,
		"restored bridge collision corresponds to the visible final pose")
	_check(await _walk(stream, player, camera, Vector3.ZERO), "restored direct bridge is physically traversable in reverse")
	_check(_floor_safe and _bounded and stream.director.max_active <= 1 and stream.state().events.size() <= 3,
		"all traversal preserves support, residency/work bounds and single active transformation")
	_check(stream.max_active_boxes <= 171 and stream.world_state.size() <= 290,
		"route reuses existing geometry budget and stores one bounded director record")
	print("LIVING measurements director_max_ms=", stream.update_max_ms, " bridge_assembly_ms=", stream.assembly_max_ms,
		" ambient_build_ms=", ambient.construction_ms, " ambient_update_max_ms=", ambient.update_max_ms,
		" ambient_meshes=24 structures=12 max_route_events=", stream.director.max_active,
		" ", stream.diagnostic_text(), " FPS=not_measured")
	demo.queue_free()
	await process_frame
	return true


func _collision_nodes(node: Node) -> int:
	var count := 1 if node is CollisionObject3D or node is CollisionShape3D else 0
	for child in node.get_children():
		count += _collision_nodes(child)
	return count


func _test_active_eviction_and_handover() -> bool:
	var demo: Node3D = await _new_demo()
	var stream: Node3D = demo.get_node("Streamer")
	var player: CharacterBody3D = demo.get_node("Player3D")
	var camera: Camera3D = demo.get_node("Camera")
	stream.director.trigger_seconds = 100
	stream.director.warning_seconds = 0.1
	stream.director.cooldown_seconds = 0
	stream.movement_seconds = 1000
	_check(stream.director.request("threshold", "redirected"), "scripted Castle Master request uses the same validated event scheduler")
	_check(await _wait_until(func() -> bool: return stream.state().active.get("phase", "") == "moving", 100),
		"gates settle before collision is disabled for an in-progress shift")
	var old: WeakRef = weakref(stream.bridge)
	var travel := true
	for cell in [Vector2i(-1, 0), Vector2i(-2, 0)]:
		travel = await _walk(stream, player, camera, stream.catalog.room(cell).center) and travel
	var pose: float = stream.state().pose
	await _frames(20)
	_check(travel and old.get_ref() == null and stream.bridge == null and stream.state().active.phase == "moving"
		and stream.state().pose == pose, "evicting an active transformation preserves phase/pose without distant animation")
	for cell in [Vector2i(-1, 0), Vector2i.ZERO]:
		travel = await _walk(stream, player, camera, stream.catalog.room(cell).center) and travel
	_check(travel and stream.bridge.deck.collision_layer == 0 and stream.state().pose <= pose,
		"active reload resumes saved visual motion with endpoint gates and no premature collision")
	stream.movement_seconds = 0.2
	_check(await _wait_until(func() -> bool: return stream.state().stable == "redirected", 150), "resumed shift finishes at its deterministic lowered endpoint")
	stream.state().release_at = stream.state().clock + 1000
	var south_link: AbyssSpatialLayout.Connection
	for link: AbyssSpatialLayout.Connection in stream.active[Vector2i.ZERO].data.connections:
		if link.direction() == Vector3.BACK:
			south_link = link
	_check(await _walk(stream, player, camera, (south_link.start + south_link.end) * 0.5), "player can occupy the southern passage before restoration")
	_check(stream.director.request("release", "direct"), "scripted restoration is accepted after its cooldown")
	_check(await _wait_until(func() -> bool: return stream.state().active.get("phase", "") == "handover", 180), "restored bridge becomes ready before closing the alternate route")
	await _frames(100)
	_check(stream.state().active.get("phase", "") == "handover" and player.is_on_floor()
		and stream._edge_open(Vector2i.ZERO, Vector2i.RIGHT) and stream._edge_open(Vector2i.ZERO, Vector2i.DOWN),
		"occupied alternate passage defers closure while both routes remain traversable")
	_check(await _walk(stream, player, camera, stream.catalog.room(Vector2i.DOWN).center), "player can leave the deferred passage safely")
	_check(await _wait_until(func() -> bool: return stream.state().stable == "direct", 60), "alternate entrance closes only after the player clears it")
	_check(_floor_safe and _bounded, "active eviction and handover never remove player support or exceed stream bounds")
	demo.queue_free()
	await process_frame
	return true


func _walk(stream: Node3D, player: CharacterBody3D, camera: Camera3D, target: Vector3) -> bool:
	for frame in 1000:
		var delta := target - player.position
		delta.y = 0
		if delta.length() < 0.18:
			_release()
			await _frames(4)
			return player.is_on_floor() and absf(player.position.y - target.y) < 0.1
		var right := camera.global_basis.x
		var forward := -camera.global_basis.z
		right.y = 0
		forward.y = 0
		var direction := delta.normalized()
		var vector := Vector2(direction.dot(right.normalized()), -direction.dot(forward.normalized()))
		_release()
		Input.action_press("move_left" if vector.x < 0 else "move_right", absf(vector.x))
		Input.action_press("move_up" if vector.y < 0 else "move_down", absf(vector.y))
		await physics_frame
		_floor_safe = _floor_safe and player.is_on_floor()
		_bounded = _bounded and stream.active.size() <= stream.settings.capacity() and stream.last_jobs <= stream.settings.jobs_per_frame
	_release()
	return false


func _release() -> void:
	for action in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(action)
