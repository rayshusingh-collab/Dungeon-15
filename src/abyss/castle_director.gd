extends RefCounted
## Deterministic bounded rule controller. Input is simulation time + explicit facts.
## Only three event keys exist; one active gameplay event; no growing event queue.

var state: Dictionary
var world_id: String
var warning_seconds: float = 3.0
var cooldown_seconds: float = 6.0
var redirect_seconds: float = 18.0
var trigger_seconds: float = 3.0
var max_active: int = 0


func _init(saved: Dictionary, identity: String) -> void:
	state = saved
	world_id = identity
	if state.is_empty():
		state.merge({"clock": 0.0, "ambient_clock": 0.0, "stable": "direct", "pose": 1.0,
			"active": {}, "events": {}, "cooldown_until": 0.0, "release_at": -1.0,
			"zone_seen": false, "milestone": false, "ambient_intensity": 1.0})


func event_id(key: String) -> String:
	return "%016x" % StableHash.hash62("castle-director|v1|%s|%s" % [world_id, key])


func request(key: String, target: String) -> bool:
	if not ["threshold", "release"].has(key) or not ["direct", "redirected"].has(target):
		return false
	if (key == "threshold" and target != "redirected") or (key == "release" and target != "direct"):
		return false
	if not state.active.is_empty() or state.events.has(key) or state.clock < state.cooldown_until or state.stable == target:
		return false
	state.active = {"id": event_id(key), "key": key, "target": target, "phase": "warning", "elapsed": 0.0}
	if key == "threshold":
		state.zone_seen = true
	max_active = maxi(max_active, 1)
	return true


func advance(delta: float, nearby_ready: bool, milestone_reached: bool) -> void:
	state.ambient_clock += delta
	if not nearby_ready:
		return
	state.clock += delta
	if milestone_reached and not state.milestone:
		state.milestone = true
		state.events["wayfinder"] = event_id("wayfinder")
		state.ambient_intensity = 1.5
	if state.active.is_empty():
		if not state.zone_seen and state.clock >= trigger_seconds:
			state.zone_seen = request("threshold", "redirected")
		elif state.stable == "redirected" and (state.milestone or state.clock >= state.release_at):
			request("release", "direct")
	elif state.active.phase == "warning":
		state.active.elapsed += delta
		if state.active.elapsed >= warning_seconds:
			state.active.phase = "waiting"


func complete() -> void:
	if state.active.is_empty():
		return
	state.events[state.active.key] = state.active.id
	state.stable = state.active.target
	state.cooldown_until = state.clock + cooldown_seconds
	if state.stable == "redirected":
		state.release_at = state.clock + redirect_seconds
	state.active = {}
