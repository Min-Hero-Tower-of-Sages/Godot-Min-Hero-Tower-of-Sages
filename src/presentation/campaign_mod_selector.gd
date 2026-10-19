class_name CampaignModSelector
extends Control

const FONT := preload("res://content/base/fonts/BurbinCasual.ttf")
const BUTTON_AUDIO := preload("res://src/presentation/source_menu_button_audio.gd")
var flags: Dictionary = {}
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
	for index in CampaignModService.CATEGORIES.size():
		var category: Dictionary = CampaignModService.CATEGORIES[index]
		var button := _text_button("", Vector2(11, 62 + index * 36), Vector2(193, 33), 12)
		button.pressed.connect(_open_category.bind(index))
		button.mouse_entered.connect(_describe.bind(category.description))
		_category_buttons.append(button)
	_describe("Choose a category to configure your run. Enabled counts appear beside each category.")
	_refresh()

func _open_category(index: int) -> void:
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

func _toggle(index: int) -> void:
	var option: Dictionary = CampaignModService.OPTIONS[index]
	var value := not bool(flags.get(option.flags[0], false))
	for flag in option.flags: flags[flag] = value
	_describe(option.description)
	_refresh()

func _refresh() -> void:
	for index in _buttons.size():
		var option: Dictionary = CampaignModService.OPTIONS[_option_indices[index]]
		var on := bool(flags.get(option.flags[0], false))
		var art := SourceMenuArt.texture("menus_settings_onButton" if on else "menus_settings_offButton")
		_buttons[index].texture_normal = art
		_buttons[index].texture_hover = art
		_buttons[index].texture_pressed = art
	for index in _category_buttons.size():
		var category: Dictionary = CampaignModService.CATEGORIES[index]
		var count := 0
		for group in category.groups:
			if bool(flags.get(group, false)): count += 1
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
