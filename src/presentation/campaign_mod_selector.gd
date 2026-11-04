class_name CampaignModSelector
extends Control

const FONT := preload("res://content/base/fonts/BurbinCasual.ttf")
const BUTTON_AUDIO := preload("res://src/presentation/source_menu_button_audio.gd")
var flags: Dictionary = {}
## Player mods (Mod Workshop) chosen for the new save, in activation order.
var user_mod_ids: Array[String] = []
var _player_mods: Array[Dictionary] = []
var _body: Control
var _description: Label
var _buttons: Array[TextureButton] = []
var _option_indices: Array[int] = []
var _category_buttons: Array[Button] = []
var _category := -1

func _ready() -> void:
	name = "ModSelector"
	size = Vector2(215, 300)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	SourceMenuArt.image(self, "mainMenu_modMenuBackground", Vector2.ZERO)
	_body = Control.new()
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_body)
	_description = _label("Choose a category.", Vector2(12, 211), Vector2(191, 84), 12, self)
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.clip_text = true
	_description.add_theme_color_override("font_color", Color8(218, 220, 229))
	_show_categories()

func _clear_body() -> void:
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	_buttons.clear()
	_option_indices.clear()
	_category_buttons.clear()

func _show_categories() -> void:
	_category = -1
	_clear_body()
	_player_mods.clear()
	for manifest in UserModRepository.list():
		if not manifest.get("broken", false): _player_mods.append(manifest)
	var count := CampaignModService.CATEGORIES.size() + 1
	var step := minf(36.0, 146.0 / count)
	for index in count:
		var description := "Mods made in the Mod Workshop on this computer." if index == CampaignModService.CATEGORIES.size() else String(CampaignModService.CATEGORIES[index].description)
		var button := _text_button("", Vector2(11, 62 + index * step), Vector2(193, step - 3.0), 12)
		button.pressed.connect(_open_category.bind(index))
		button.mouse_entered.connect(_describe.bind(description))
		_category_buttons.append(button)
	_describe("Choose a category to configure your run. Enabled counts appear beside each category.")
	_refresh()

func _open_category(index: int) -> void:
	if index == CampaignModService.CATEGORIES.size():
		_open_player_mods()
		return
	if index < 0 or index >= CampaignModService.CATEGORIES.size(): return
	_category = index
	_clear_body()
	var category: Dictionary = CampaignModService.CATEGORIES[index]
	var back := _text_button("< Back", Vector2(11, 48), Vector2(62, 25), 14)
	back.pressed.connect(_show_categories)
	_label(category.name, Vector2(11, 78), Vector2(193, 22), 15, _body)
	# Four rows fit today; scrolling supports future additions without overlap.
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(11, 105)
	scroll.size = Vector2(193, 104)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 0)
	scroll.add_child(rows)
	for group in category.groups:
		var option_index := CampaignModService.option_index(String(group))
		if option_index < 0: continue
		var option: Dictionary = CampaignModService.OPTIONS[option_index]
		var row := Control.new()
		row.custom_minimum_size = Vector2(185, 26)
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		rows.add_child(row)
		var caption := _label(option.name, Vector2(2, 1), Vector2(113, 24), 15, row)
		caption.mouse_filter = Control.MOUSE_FILTER_PASS
		caption.mouse_entered.connect(_describe.bind(option.description))
		var toggle := SourceMenuArt.button(row, "menus_settings_offButton", Vector2(117, 2), _toggle.bind(option_index))
		if toggle != null:
			toggle.ignore_texture_size = true
			toggle.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
			toggle.size = Vector2(66, 24)
			toggle.mouse_entered.connect(_describe.bind(option.description))
			_buttons.append(toggle)
			_option_indices.append(option_index)
	_describe(CampaignModService.OPTIONS[CampaignModService.option_index(category.groups[0])].description)
	_refresh()

func _open_player_mods() -> void:
	_category = CampaignModService.CATEGORIES.size()
	_clear_body()
	var back := _text_button("< Back", Vector2(11, 48), Vector2(62, 25), 14)
	back.pressed.connect(_show_categories)
	_label("Player Mods", Vector2(11, 78), Vector2(193, 22), 15, _body)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(11, 105)
	scroll.size = Vector2(193, 104)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 0)
	scroll.add_child(rows)
	for manifest in _player_mods:
		var mod_id := String(manifest.id)
		var text := "%s\nBy %s · v%s" % [String(manifest.get("description", "")).left(160), manifest.get("author", "unknown"), manifest.get("version", "1")]
		var row := Control.new()
		row.custom_minimum_size = Vector2(185, 26)
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		rows.add_child(row)
		var caption := _label(String(manifest.name), Vector2(2, 1), Vector2(113, 24), 15, row)
		caption.clip_text = true
		caption.mouse_filter = Control.MOUSE_FILTER_PASS
		caption.mouse_entered.connect(_describe.bind(text))
		var toggle := SourceMenuArt.button(row, "menus_settings_offButton", Vector2(117, 2), _toggle_player.bind(mod_id))
		if toggle != null:
			toggle.ignore_texture_size = true
			toggle.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
			toggle.size = Vector2(66, 24)
			toggle.mouse_entered.connect(_describe.bind(text))
			toggle.set_meta("player_mod", mod_id)
			_buttons.append(toggle)
			_option_indices.append(-1)
	_describe("Choose player mods for this save. Change them later in Settings > Mod Menu." if not _player_mods.is_empty() else "No player mods are installed. Make one, or import a share code, in the Mod Workshop on the title screen.")
	_refresh()

func _toggle_player(mod_id: String) -> void:
	if mod_id in user_mod_ids: user_mod_ids.erase(mod_id)
	else: user_mod_ids.append(mod_id)
	_refresh()

func _toggle(index: int) -> void:
	var option: Dictionary = CampaignModService.OPTIONS[index]
	var value := not CampaignModService.group_enabled(flags, option.flags[0])
	for flag in option.flags: flags[flag] = value
	_describe(option.description)
	_refresh()

func _refresh() -> void:
	for index in _buttons.size():
		var on := false
		if _option_indices[index] < 0:
			on = String(_buttons[index].get_meta("player_mod", "")) in user_mod_ids
		else:
			var option: Dictionary = CampaignModService.OPTIONS[_option_indices[index]]
			on = CampaignModService.group_enabled(flags, option.flags[0])
		var art := SourceMenuArt.texture("menus_settings_onButton" if on else "menus_settings_offButton")
		_buttons[index].texture_normal = art
		_buttons[index].texture_hover = art
		_buttons[index].texture_pressed = art
	for index in _category_buttons.size():
		if index == CampaignModService.CATEGORIES.size():
			_category_buttons[index].text = "Player Mods  %d/%d" % [user_mod_ids.size(), _player_mods.size()]
			continue
		var category: Dictionary = CampaignModService.CATEGORIES[index]
		var count := 0
		for group in category.groups:
			if CampaignModService.group_enabled(flags, group): count += 1
		_category_buttons[index].text = "%s  %d/%d" % [category.name, count, category.groups.size()]

func _describe(text: String) -> void:
	_description.text = text

func _label(text: String, at: Vector2, dimensions: Vector2, font_size: int, parent: Node) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at
	label.size = dimensions
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color8(250, 250, 250))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _text_button(text: String, at: Vector2, dimensions: Vector2, font_size: int) -> Button:
	var button := Button.new()
	button.text = text
	button.position = at
	button.size = dimensions
	button.add_theme_font_override("font", FONT)
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", Color8(244, 226, 151))
	for state in ["normal", "hover", "pressed"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color8(43, 47, 57) if state == "normal" else Color8(67, 73, 89)
		style.border_color = Color8(130, 141, 160) if state == "normal" else Color8(233, 215, 144)
		style.set_border_width_all(1)
		style.set_corner_radius_all(4)
		button.add_theme_stylebox_override(state, style)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_body.add_child(button)
	BUTTON_AUDIO.bind_button(button)
	return button
