extends Control

signal cancelled
signal saved(return_to_lobby: bool)
## Resolved at runtime so this script compiles before autoloads exist.
var net: Node:
	get: return get_node_or_null("/root/NetSession")

var _session: CampaignSession
var _panel: Control
var _saving: TextureRect
var _save_button: TextureButton
var _lobby_button: TextureButton
var _cancel_button: TextureButton
var _error: Label
var _busy := false
var _lobby_available := false

func configure(session: CampaignSession) -> void:
	_session = session
	_build_view()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	focus_mode = Control.FOCUS_ALL
	grab_focus()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_M):
		_cancel()
		get_viewport().set_input_as_handled()

func _build_view() -> void:
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0, 0, 0, 0.65)
	add_child(shade)
	var viewport_size := get_viewport_rect().size
	var factor := minf(viewport_size.x / 700.0, viewport_size.y / 525.0)
	var source_root := Control.new()
	source_root.size = Vector2(700, 525)
	source_root.position = (viewport_size - source_root.size * factor) * 0.5
	source_root.scale = Vector2.ONE * factor
	source_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(source_root)
	_panel = Control.new()
	_panel.name = "SaveMenuPanel"
	_panel.position = Vector2(245, 156)
	source_root.add_child(_panel)
	var background := SourceMenuArt.image(_panel, "menus_selectionPopUp_background", Vector2.ZERO)
	_panel.size = background.size
	_panel.pivot_offset = _panel.size * 0.5
	set_meta("source_transition_visuals", _panel)
	_saving = SourceMenuArt.image(_panel, "menus_savingPopup", Vector2(14, -27))
	_saving.visible = false
	_save_button = SourceMenuArt.button(_panel, "menus_selectionPopUp_saveButton", Vector2(15, 15), _begin_save.bind(false))
	_save_button.name = "SaveButton"
	_lobby_button = SourceMenuArt.button(_panel, "menus_selectionPopUp_saveReturnToLobbyButton", Vector2(15, 54), _begin_save.bind(true))
	_lobby_button.name = "SaveReturnToLobbyButton"
	var highest := int(_session.state.progression.get("highest_beaten_floor", 0))
	# Older saves predate the explicit completion frontier.
	if not _session.state.progression.has("highest_beaten_floor"):
		for index in _session.state.progression.get("unlocked_floor_indices", [0]):
			highest = maxi(highest, int(index))
	_lobby_available = highest > 1
	_cancel_button = SourceMenuArt.button(_panel, "menus_selectionPopUp_cancelButton", Vector2(15, 104), _cancel)
	_cancel_button.name = "CancelButton"
	_error = Label.new()
	_error.position = Vector2(-60, 153)
	_error.size = Vector2(_panel.size.x + 120, 50)
	_error.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_error.add_theme_font_override("font", preload("res://content/base/fonts/BurbinCasual.ttf"))
	_error.add_theme_font_size_override("font_size", 14)
	_error.add_theme_color_override("font_color", Color.hex(0xed5e5eff))
	_panel.add_child(_error)
	_set_busy(false)

func _set_busy(value: bool) -> void:
	_busy = value
	_save_button.disabled = value
	_cancel_button.disabled = value
	# Going to the lobby changes floor, which only the host may do (except in
	# versus, where every racer runs their own tower).
	var lobby_allowed: bool = _lobby_available and (not net.is_guest() or net.is_versus())
	_lobby_button.disabled = value or not lobby_allowed
	_lobby_button.modulate.a = 1.0 if lobby_allowed else 0.3

func _cancel() -> void:
	if not _busy:
		cancelled.emit()

func _begin_save(return_to_lobby: bool) -> void:
	if _busy or (return_to_lobby and not _lobby_available):
		return
	_set_busy(true)
	_error.text = ""
	_saving.visible = true
	_saving.modulate.a = 0.0
	var show_saving := create_tween()
	show_saving.tween_property(_saving, "modulate:a", 1.0, 0.5)
	show_saving.tween_interval(0.1)
	await show_saving.finished
	# Lobby entry and persistence are one transaction. A rejected write must not
	# move the player or destroy the old room, unlike a pre-save visual switch.
	var result: Dictionary = _session.enter_tower_lobby() if return_to_lobby else _session.save()
	if not bool(result.get("ok", false)):
		_error.text = "Save failed: %s. Please retry." % String(result.get("message", "unknown error"))
		_saving.visible = false
		_set_busy(false)
		return
	await get_tree().create_timer(0.2 if return_to_lobby else 0.1).timeout
	saved.emit(return_to_lobby)
