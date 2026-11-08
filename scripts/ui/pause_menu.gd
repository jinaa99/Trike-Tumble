class_name PauseMenu
extends CanvasLayer
## ESC toggles pause. Runs while the tree is paused (process_mode = Always).

signal restart_requested

@onready var _root: Control = $Root
@onready var _resume_button: Button = %ResumeButton
@onready var _restart_button: Button = %RestartButton
@onready var _quit_button: Button = %QuitButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root.visible = false
	_resume_button.pressed.connect(set_paused.bind(false))
	_restart_button.pressed.connect(_on_restart_pressed)
	_quit_button.pressed.connect(func() -> void: get_tree().quit())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
		set_paused(not get_tree().paused)
		get_viewport().set_input_as_handled()


func set_paused(paused: bool) -> void:
	get_tree().paused = paused
	_root.visible = paused
	if paused:
		_resume_button.grab_focus()


func is_open() -> bool:
	return _root.visible


func _on_restart_pressed() -> void:
	set_paused(false)
	restart_requested.emit()
