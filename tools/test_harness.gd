extends SceneTree
## Shared headless test harness. Suites extend this file and override
## _suite_name() and _get_tests() (and optionally _after_each()).
## A suite fails (exit code 1) if any check fails, a test aborts (script
## errors end a coroutine early, so every test must `return true`), any engine
## or script error/warning is logged, or Engine.time_scale / pause is left set.

var _failures: int = 0
var _checks: int = 0
var _errors := ErrorCounter.new()


## Counts every engine/script error or warning logged while tests run.
class ErrorCounter extends Logger:
	var count: int = 0
	var _mutex := Mutex.new()

	func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String,
			_editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		_mutex.lock()
		count += 1
		_mutex.unlock()

	func get_count() -> int:
		_mutex.lock()
		var value := count
		_mutex.unlock()
		return value


func _initialize() -> void:
	OS.add_logger(_errors)
	_run.call_deferred()


func _suite_name() -> String:
	return "TESTS"


func _get_tests() -> Array[Callable]:
	return []


## Cleanup between tests (may await).
func _after_each() -> void:
	pass


func _run() -> void:
	var started := Time.get_ticks_msec()
	for test in _get_tests():
		print("== ", test.get_method())
		var errors_before := _errors.get_count()
		var completed: Variant = await test.call()
		_check(completed == true, "%s ran to completion" % test.get_method())
		await _after_each()
		var new_errors := _errors.get_count() - errors_before
		_check(new_errors == 0, "%s logged no engine/script errors or warnings (%d)" % [test.get_method(), new_errors])
		_check(is_equal_approx(Engine.time_scale, 1.0) and not paused,
				"%s left Engine.time_scale at 1.0 and the tree unpaused" % test.get_method())
	print("%s: %s (%d checks, %d failure(s), %.1f s)" % [_suite_name(), "OK" if _failures == 0 else "FAILED",
			_checks, _failures, (Time.get_ticks_msec() - started) / 1000.0])
	OS.remove_logger(_errors)
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("  PASS  ", label)
	else:
		_failures += 1
		printerr("  FAIL  ", label)


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _wait_until(condition: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if condition.call():
			return true
		await physics_frame
	return condition.call()


## Taps an action for one physics frame, then leaves one frame to react.
func _press(action: StringName) -> void:
	Input.action_press(action)
	await physics_frame
	Input.action_release(action)
	await physics_frame


func _touch(index: int, at: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = at
	event.pressed = pressed
	root.push_input(event, true)


func _drag(index: int, at: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = at
	root.push_input(event, true)
