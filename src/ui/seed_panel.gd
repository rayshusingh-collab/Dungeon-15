class_name SeedPanel
extends Control
## Seed display / entry for development and sharing. Numbers are used as-is;
## any other text is hashed into a seed (RunConfig.parse_seed_text), so words
## make shareable seeds too. Emits requests; Main decides what to do.

signal play_seed_requested(seed_value: int)
signal replay_requested
signal new_seed_requested
signal closed

var _current_seed: int = 0

@onready var _current: Label = $Panel/Box/Current
@onready var _edit: LineEdit = $Panel/Box/SeedEdit
@onready var _feedback: Label = $Panel/Box/Feedback


func _ready() -> void:
	$Panel/Box/Row1/PlayButton.pressed.connect(_on_play)
	$Panel/Box/Row1/ReplayButton.pressed.connect(replay_requested.emit)
	$Panel/Box/Row2/NewButton.pressed.connect(new_seed_requested.emit)
	$Panel/Box/Row2/CopyButton.pressed.connect(_on_copy)
	$Panel/Box/Row2/CloseButton.pressed.connect(close)
	_edit.text_submitted.connect(func(_text: String) -> void: _on_play())


func open(current_seed: int, depth: int) -> void:
	_current_seed = current_seed
	_current.text = "Current: seed %d, depth %d" % [current_seed, depth]
	_edit.text = str(current_seed)
	_feedback.text = "Numbers or words. Same seed + depth = same dungeon."
	show()
	_edit.grab_focus()
	_edit.select_all()


func close() -> void:
	if not visible:
		return
	hide()
	closed.emit()


## Parsed entry, or -1 if empty.
func entered_seed() -> int:
	return RunConfig.parse_seed_text(_edit.text)


func set_entry_text(text: String) -> void:
	_edit.text = text


func _on_play() -> void:
	var seed_value := entered_seed()
	if seed_value < 0:
		_feedback.text = "Enter a seed first."
		return
	play_seed_requested.emit(seed_value)


func _on_copy() -> void:
	DisplayServer.clipboard_set(str(_current_seed))
	_feedback.text = "Copied seed %d to the clipboard." % _current_seed
