extends Control

## Controls over a battle replay: who is fighting, the turn, pause and speed,
## and leaving. When the recording ends, a card offers to watch it again, copy
## its share code, or go back. Styled like the multiplayer panels (the source
## in-game menu's slate and steel blue).

signal speed_changed(speed: float)
signal restart_requested
signal exit_requested

const BAR_SIZE := Vector2(580.0, 42.0)
const END_SIZE := Vector2(420.0, 178.0)
const SPEEDS: Array[float] = [1.0, 2.0, 4.0]
const NOTICE_SECONDS := 5.0

var _replay: Dictionary = {}
var _bar: Panel
var _turn_label: Label
var _pause_button: Button
var _speed_buttons: Array[Button] = []
var _speed := 1.0
var _paused := false
var _total_turns := 0
var _notice: Label
var _end_layer: Control
var _end_panel: Panel
var _end_title: Label
var _end_detail: Label
var _end_status: Label

func configure(replay: Dictionary) -> void:
	_replay = replay
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_total_turns = int((replay.get("result", {}) as Dictionary).get("turns", 0))
	_bar = MultiplayerUi.panel(self, Vector2((MultiplayerUi.SCREEN_SIZE.x - BAR_SIZE.x) * 0.5, 6.0), BAR_SIZE)
	_bar.name = "ReplayBar"
	_pause_button = MultiplayerUi.button(_bar, "Pause", Vector2(8.0, 5.0), Vector2(78.0, 32.0), _toggle_pause, 15)
	_pause_button.name = "PauseButton"
	var heading := MultiplayerUi.label(_bar, BattleReplay.title(replay), Vector2(96.0, 2.0), Vector2(232.0, 20.0), 15, MultiplayerUi.CREAM)
	heading.autowrap_mode = TextServer.AUTOWRAP_OFF
	heading.clip_text = true
	heading.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_turn_label = MultiplayerUi.label(_bar, "", Vector2(96.0, 20.0), Vector2(232.0, 18.0), 12, MultiplayerUi.GOLD)
	_turn_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_turn_label.name = "TurnLabel"
	_speed_buttons = MultiplayerUi.choice_row(_bar, PackedStringArray(["x1", "x2", "x4"]), Vector2(336.0, 5.0), 136.0, 32.0, 0, _pick_speed, 15)
	for index in _speed_buttons.size():
		_speed_buttons[index].name = "Speed%d" % int(SPEEDS[index])
	MultiplayerUi.button(_bar, "Exit", Vector2(BAR_SIZE.x - 98.0, 5.0), Vector2(90.0, 32.0), _exit, 15).name = "ExitButton"
	_notice = MultiplayerUi.hud_label(self, "", Vector2(0.0, BAR_SIZE.y + 12.0), Vector2(MultiplayerUi.SCREEN_SIZE.x, 20.0), 14, MultiplayerUi.GOLD)
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice.modulate.a = 0.0
	set_turn(0)

func current_speed() -> float:
	return _speed

func set_turn(turn: int) -> void:
	if _total_turns > 0:
		_turn_label.text = "REPLAY · Turn %d of %d" % [mini(turn, _total_turns), _total_turns]
	else:
		_turn_label.text = "REPLAY · Turn %d" % turn

## A short line under the bar (version mismatch, drift).
func show_notice(text: String) -> void:
	if _notice.text == text and _notice.modulate.a > 0.0:
		return
	_notice.text = text
	_notice.modulate.a = 1.0
	# Paused or sped up, the battle's time scale must not hold the notice back.
	var fade := create_tween().set_ignore_time_scale(true)
	fade.tween_interval(NOTICE_SECONDS)
	fade.tween_property(_notice, "modulate:a", 0.0, 0.6)

func show_end(headline: String, detail: String) -> void:
	hide_end()
	_pause_button.disabled = true
	_end_layer = Control.new()
	_end_layer.name = "ReplayEnd"
	add_child(_end_layer)
	_end_panel = MultiplayerUi.modal(_end_layer, END_SIZE)
	(_end_layer.get_child(0) as ColorRect).color = Color(0.0, 0.0, 0.0, 0.3)
	MultiplayerUi.label(_end_panel, "Replay over", Vector2(20.0, 12.0), Vector2(END_SIZE.x - 40.0, 18.0), 13, MultiplayerUi.MUTED)
	_end_title = MultiplayerUi.title(_end_panel, headline, Vector2(20.0, 30.0), END_SIZE.x - 40.0, 22)
	_end_title.name = "EndTitle"
	_end_detail = MultiplayerUi.label(_end_panel, detail, Vector2(20.0, 64.0), Vector2(END_SIZE.x - 40.0, 20.0), 14, MultiplayerUi.INK)
	_end_status = MultiplayerUi.label(_end_panel, "", Vector2(20.0, 90.0), Vector2(END_SIZE.x - 40.0, 20.0), 13, MultiplayerUi.GOLD)
	var row_y := END_SIZE.y - 54.0
	MultiplayerUi.button(_end_panel, "Back", Vector2(20.0, row_y), Vector2(96.0, 36.0), _exit, 16).name = "BackButton"
	MultiplayerUi.button(_end_panel, "Copy code", Vector2(124.0, row_y), Vector2(126.0, 36.0), _copy_code, 16).name = "CopyCodeButton"
	MultiplayerUi.button(_end_panel, "Watch again", Vector2(258.0, row_y), Vector2(END_SIZE.x - 278.0, 36.0), func() -> void: restart_requested.emit(), 16).name = "WatchAgainButton"
	_end_panel.pivot_offset = END_SIZE * 0.5
	_end_panel.scale = Vector2(0.85, 0.85)
	_end_panel.modulate.a = 0.0
	var reveal := create_tween().set_ignore_time_scale(true).set_parallel(true)
	reveal.tween_property(_end_panel, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	reveal.tween_property(_end_panel, "modulate:a", 1.0, 0.2)

func hide_end() -> void:
	if is_instance_valid(_end_layer):
		_end_layer.queue_free()
	_end_layer = null
	_pause_button.disabled = false

func _copy_code() -> void:
	DisplayServer.clipboard_set(BattleReplay.encode(_replay))
	_end_status.text = "Code copied! Friends paste it in Battle replays."

func _toggle_pause() -> void:
	_paused = not _paused
	_pause_button.text = "PLAY" if _paused else "PAUSE"
	speed_changed.emit(0.0 if _paused else _speed)

func _pick_speed(index: int) -> void:
	_speed = SPEEDS[index]
	if not _paused:
		speed_changed.emit(_speed)

func _exit() -> void:
	exit_requested.emit()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if event.is_action_pressed("ui_cancel"):
		_exit()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and (event as InputEventKey).keycode == KEY_SPACE and not is_instance_valid(_end_layer):
		_toggle_pause()
		get_viewport().set_input_as_handled()
