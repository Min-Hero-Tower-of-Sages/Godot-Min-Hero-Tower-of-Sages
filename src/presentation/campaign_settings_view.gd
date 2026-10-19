class_name CampaignSettingsView
extends Control

signal closed

const GRAPHIC_SYMBOLS: Array[String] = [
	"menus_settings_graphicSetting_low",
	"menus_settings_graphicSetting_mid",
	"menus_settings_graphicSetting_high",
]
const MENU_FONT: Font = preload("res://content/base/fonts/BurbinCasual.ttf")

var settings: CampaignSettingsService
var _panel: Control
var _toggle_buttons: Dictionary = {}
var _quality_icon: TextureRect
var _next_quality: TextureButton
var _previous_quality: TextureButton
var _source_root: Control
var _session: CampaignSession
var _debug_page := false
var _debug_message := ""

func configure(settings_service: CampaignSettingsService, campaign_session: CampaignSession = null) -> void:
	settings = settings_service
	_session = campaign_session
	if is_inside_tree():
		_build_view()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	focus_mode = Control.FOCUS_ALL
	grab_focus()
	if settings != null:
		_build_view()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
		if _debug_page: _back_to_settings()
		else: closed.emit()
		get_viewport().set_input_as_handled()

func _build_view() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_toggle_buttons.clear()
	_quality_icon = null
	_next_quality = null
	_previous_quality = null
	if settings == null:
		return
	if not settings.settings_changed.is_connected(_refresh_controls):
		settings.settings_changed.connect(_refresh_controls)
	var viewport_size := get_viewport_rect().size
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.0, 0.0, 0.0, 0.65)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	var menu_size := Vector2(359.0, 415.0)
	var menu_scale := minf(viewport_size.x / 700.0, viewport_size.y / 525.0)
	_source_root = Control.new()
	_source_root.size = Vector2(700, 525)
	_source_root.position = (viewport_size - _source_root.size * menu_scale) * 0.5
	_source_root.scale = Vector2.ONE * menu_scale
	add_child(_source_root)
	_panel = Control.new()
	_panel.position = Vector2(148, 56)
	_panel.size = menu_size
	_source_root.add_child(_panel)
	_source_image(_panel, "menus_backgroundMedium", Vector2.ZERO)
	_source_image(_panel, "menus_skillTree_background", Vector2(17.0, 21.0))
	_debug_page = _debug_page and _session != null and CampaignDebugService.available(_session.state)
	var title := _make_label("Debug Mode" if _debug_page else "Settings", Vector2(73.0, 40.0), Vector2(210.0, 34.0), 28, Color8(250, 250, 250))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_panel.add_child(title)
	if _debug_page:
		_build_debug_controls()
		_source_button("menus_returnButton", Vector2(2, 356), _back_to_settings)
		_source_button("menus_exitButton", Vector2(296, -22), _close_menu)
		return
	var labels := ["Sound", "Music", "Tips", "Quality"]
	var toggle_names := ["sound", "music", "tips"]
	for index in labels.size():
		var row_y := 84.0 + float(index) * 38.0
		var label := _make_label(labels[index], Vector2(86.0, row_y), Vector2(150.0, 30.0), 22, Color8(250, 250, 250))
		_panel.add_child(label)
		if index >= toggle_names.size():
			continue
		var key: String = toggle_names[index]
		var callback := Callable(self, "_toggle_setting").bind(key)
		var toggle := _source_button("menus_settings_offButton", Vector2(200.0, 90.0 + float(index) * 38.0), callback)
		if toggle != null:
			_toggle_buttons[key] = toggle
	_quality_icon = _source_image(_panel, GRAPHIC_SYMBOLS[settings.quality_level], Vector2(209.0, 202.0))
	_next_quality = _source_button("menus_settings_nextGraphicSetting", Vector2(262.0, 203.0), Callable(self, "_step_quality").bind(1))
	var previous_texture := SourceMenuArt.texture("menus_settings_nextGraphicSetting")
	if previous_texture != null:
		var previous := TextureButton.new()
		previous.texture_normal = previous_texture
		previous.texture_hover = previous_texture
		previous.texture_pressed = previous_texture
		previous.size = previous_texture.get_size()
		previous.position = Vector2(207.0, 203.0)
		previous.scale = Vector2(-1.0, 1.0)
		previous.focus_mode = Control.FOCUS_NONE
		_panel.add_child(previous)
		preload("res://src/presentation/source_menu_button_audio.gd").bind_button(previous)
		previous.pressed.connect(_step_quality.bind(-1))
		_previous_quality = previous
	var hint_label := _make_label("Type Hints", Vector2(86, 240), Vector2(150, 30), 22, Color8(250, 250, 250))
	_panel.add_child(hint_label)
	var hints_toggle := _source_button("menus_settings_offButton", Vector2(200, 246), _toggle_setting.bind("type_hints"))
	if hints_toggle != null:
		hints_toggle.name = "EffectivenessHintsToggle"
		hints_toggle.tooltip_text = "Preview type effectiveness while hovering a move or choosing its targets."
		_toggle_buttons["type_hints"] = hints_toggle
	if _session != null and CampaignDebugService.available(_session.state):
		var debug_button := _add_text_button(_panel, "Debug Mode", Vector2(86, 290), Vector2(196, 34), _open_debug)
		debug_button.name = "DebugMenuButton"
	var return_button := _source_button("menus_returnButton", Vector2(2.0, 356.0), Callable(self, "_close_menu"))
	var close_button := _source_button("menus_exitButton", Vector2(296.0, -22.0), Callable(self, "_close_menu"))
	if return_button == null:
		_add_text_button(_panel, "Return", Vector2(2.0, 356.0), Vector2(100.0, 32.0), Callable(self, "_close_menu"))
	if close_button == null:
		_add_text_button(_panel, "Close", Vector2(296.0, -22.0), Vector2(60.0, 32.0), Callable(self, "_close_menu"))
	_refresh_controls()

func _toggle_setting(key: String) -> void:
	match key:
		"sound": settings.set_sound_enabled(not settings.sound_enabled)
		"music": settings.set_music_enabled(not settings.music_enabled)
		"tips": settings.set_tips_enabled(not settings.tips_enabled)
		"type_hints": settings.set_effectiveness_hints_enabled(not settings.effectiveness_hints_enabled)
	_refresh_controls()

func _step_quality(step: int) -> void:
	settings.set_quality_level(settings.quality_level + step)
	_refresh_controls()

func _refresh_controls() -> void:
	if _debug_page: return
	if settings == null or _panel == null or not is_instance_valid(_panel):
		return
	var values := {
		"sound": settings.sound_enabled,
		"music": settings.music_enabled,
		"tips": settings.tips_enabled,
		"type_hints": settings.effectiveness_hints_enabled,
	}
	for key in _toggle_buttons:
		var button := _toggle_buttons[key] as TextureButton
		var texture := SourceMenuArt.texture("menus_settings_onButton" if bool(values[key]) else "menus_settings_offButton")
		if button != null and texture != null:
			button.texture_normal = texture
			button.texture_hover = texture
			button.texture_pressed = texture
	if _quality_icon != null and is_instance_valid(_quality_icon):
		var texture := SourceMenuArt.texture(GRAPHIC_SYMBOLS[settings.quality_level])
		if texture != null:
			_quality_icon.texture = texture
			_quality_icon.size = texture.get_size()
	if is_instance_valid(_next_quality):
		_next_quality.visible = settings.quality_level < 2
	if is_instance_valid(_previous_quality):
		_previous_quality.visible = settings.quality_level > 0

func _close_menu() -> void:
	closed.emit()

func _source_image(parent: Control, symbol: String, at: Vector2) -> TextureRect:
	var image := SourceMenuArt.texture(symbol)
	if image == null:
		return null
	var rect := TextureRect.new()
	rect.texture = image
	rect.position = at
	rect.size = image.get_size()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)
	return rect

func _source_button(symbol: String, at: Vector2, callback: Callable) -> TextureButton:
	var image := SourceMenuArt.texture(symbol)
	if image == null:
		return null
	var button := TextureButton.new()
	button.texture_normal = image
	button.texture_hover = image
	button.texture_pressed = image
	button.position = at
	button.size = image.get_size()
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_panel.add_child(button)
	preload("res://src/presentation/source_menu_button_audio.gd").bind_button(button)
	button.pressed.connect(callback)
	return button

func _make_label(text: String, at: Vector2, label_size: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at + Vector2(2, 2)
	label.size = label_size
	label.add_theme_font_override("font", MENU_FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _add_text_button(parent: Control, text: String, at: Vector2, button_size: Vector2, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.position = at
	button.size = button_size
	button.add_theme_font_override("font", MENU_FONT)
	button.add_theme_font_size_override("font_size", 19)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(callback)
	parent.add_child(button)
	preload("res://src/presentation/source_menu_button_audio.gd").bind_button(button)
	return button

func _open_debug() -> void:
	if _session == null or not CampaignDebugService.available(_session.state): return
	_debug_page = true
	_build_view()

func _back_to_settings() -> void:
	_debug_page = false
	_build_view()

func _build_debug_controls() -> void:
	for index in CampaignDebugService.OPTIONS.size():
		var option: Dictionary = CampaignDebugService.OPTIONS[index]
		var caption := _make_label(option.name, Vector2(34, 84 + index * 34), Vector2(208, 30), 19, Color8(250, 250, 250))
		_panel.add_child(caption)
		var active := CampaignDebugService.enabled(_session.state, option.id)
		var toggle := _source_button("menus_settings_onButton" if active else "menus_settings_offButton", Vector2(245, 91 + index * 34), _toggle_debug.bind(String(option.id)))
		if toggle != null:
			toggle.name = "DebugToggle_%s" % option.id
			toggle.tooltip_text = option.description
			toggle.disabled = not _session.state.pending_battle.is_empty()
	var description := Label.new()
	description.name = "DebugDescription"
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.position = Vector2(36, 267)
	description.size = Vector2(290, 70)
	description.clip_text = true
	description.mouse_filter = Control.MOUSE_FILTER_IGNORE
	description.add_theme_font_override("font", MENU_FONT)
	description.add_theme_font_size_override("font_size", 12)
	description.add_theme_color_override("font_color", Color8(244, 221, 145))
	description.text = _debug_message if not _debug_message.is_empty() else "Saved with this campaign. Granted levels/upgrades remain when disabled. 100% Shiny affects new minions."
	_panel.add_child(description)

func _toggle_debug(option: String) -> void:
	var result := _session.set_debug_option(option, not CampaignDebugService.enabled(_session.state, option))
	_debug_message = "" if result.ok else String(result.get("message", "Could not save debug setting"))
	_build_view()
