class_name TypeGuideView
extends Control

signal closed

const FONT := preload("res://content/base/fonts/BurbinCasual.ttf")
var catalog: ContentCatalog
var selected_type: StringName = &"base:type/fire"
var healing := false
var _panel: Control
var _types: Array[TypeDefinition] = []
var _details: Control
var _type_buttons: Dictionary = {}
var _damage_tab: Button
var _healing_tab: Button

func configure(content: ContentCatalog, initial_type: StringName = &"base:type/fire") -> void:
	catalog = content
	selected_type = initial_type
	if is_inside_tree(): _build()

func _ready() -> void:
	name = "TypeGuide"
	z_index = 1800
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if catalog != null: _build()

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree(): return
	if event is InputEventKey:
		# Space/M/Escape belong to this modal, not the campaign menu beneath it.
		get_viewport().set_input_as_handled()
		if event.pressed and not event.echo and event.keycode in [KEY_ESCAPE, KEY_T]: closed.emit()

func _build() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_types.clear()
	_type_buttons.clear()
	catalog.ensure_index()
	for definition in catalog._by_id.values():
		if definition is TypeDefinition and definition.id != &"base:type/none": _types.append(definition)
	_types.sort_custom(func(a: TypeDefinition, b: TypeDefinition) -> bool: return a.display_name < b.display_name)
	if not catalog.get_definition(selected_type) is TypeDefinition or selected_type == &"base:type/none":
		selected_type = _types[0].id if not _types.is_empty() else &""
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0, 0, 0, 0.65)
	add_child(shade)
	_panel = Control.new()
	_panel.name = "TypeGuidePanel"
	var factor := minf(size.x / 700.0, size.y / 525.0)
	_panel.position = (size - Vector2(700, 525) * factor) * 0.5 + Vector2(5, 40) * factor
	_panel.scale = Vector2.ONE * factor
	_panel.size = Vector2(690, 468)
	add_child(_panel)
	SourceMenuArt.image(_panel, "menus_backgroundLarge", Vector2.ZERO)
	SourceMenuArt.image(_panel, "minionPedia_background", Vector2(21, 18))
	_label(_panel, "Type Guide", Vector2(20, 24), Vector2(650, 38), 28, Color8(249, 249, 249), HORIZONTAL_ALIGNMENT_CENTER)
	# A scrolling selector keeps future catalog types usable at the same size.
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(36, 78)
	scroll.size = Vector2(269, 186)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 7)
	scroll.add_child(grid)
	for type in _types:
		var cell := Control.new()
		cell.custom_minimum_size = Vector2(80, 29)
		grid.add_child(cell)
		var button := text_button(cell, "", Vector2.ZERO, Vector2(80, 29), _select_type.bind(type.id), 13)
		button.toggle_mode = true
		button.tooltip_text = type.display_name
		var badge := type_badge(type.id)
		if badge != null:
			var image := TextureRect.new()
			image.texture = badge
			image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			image.size = Vector2(74, 22)
			image.position = Vector2(3, 3)
			image.mouse_filter = Control.MOUSE_FILTER_IGNORE
			button.add_child(image)
		else: button.text = type.display_name
		_type_buttons[type.id] = button
	_damage_tab = tab_button(_panel, "Damage", Vector2(36, 279), Vector2(132, 35), _set_healing.bind(false))
	_healing_tab = tab_button(_panel, "Healing", Vector2(168, 279), Vector2(132, 35), _set_healing.bind(true))
	_damage_tab.toggle_mode = true
	_healing_tab.toggle_mode = true
	_label(_panel, "Move type → target type", Vector2(37, 331), Vector2(265, 24), 15)
	_label(_panel, "↑ Boosted   ↓ Resisted   ? Unknown\n♥ Healing uses reversed matchups", Vector2(37, 361), Vector2(265, 35), 12)
	var details_scroll := ScrollContainer.new()
	details_scroll.position = Vector2(330, 75)
	details_scroll.size = Vector2(330, 321)
	details_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(details_scroll)
	_details = Control.new()
	_details.custom_minimum_size.x = 300
	details_scroll.add_child(_details)
	# The return frame steps into the inset at x=125. Keep the footer to its
	# right instead of letting small text straddle that artwork or the bottom rim.
	_label(_panel, "Type bonuses only · dual types multiply · neutral: no badge", Vector2(145, 415), Vector2(495, 25), 12, Color8(201, 204, 212), HORIZONTAL_ALIGNMENT_CENTER)
	SourceMenuArt.button(_panel, "menus_returnButton", Vector2(3, 409), func() -> void: closed.emit())
	SourceMenuArt.button(_panel, "menus_exitButton", Vector2(624, -22), func() -> void: closed.emit())
	_refresh()
	_panel.modulate.a = 0.0
	create_tween().set_ignore_time_scale(true).tween_property(_panel, "modulate:a", 1.0, 0.15)

func _select_type(type_id: StringName) -> void:
	selected_type = type_id
	_refresh()

func _set_healing(value: bool) -> void:
	healing = value
	_refresh()

func _refresh() -> void:
	for child in _details.get_children():
		_details.remove_child(child)
		child.queue_free()
	for type_id in _type_buttons:
		(_type_buttons[type_id] as Button).modulate = Color.WHITE if type_id == selected_type else Color(0.8, 0.8, 0.8)
		(_type_buttons[type_id] as Button).set_pressed_no_signal(type_id == selected_type)
	_damage_tab.set_pressed_no_signal(not healing)
	_healing_tab.set_pressed_no_signal(healing)
	var definition := catalog.get_definition(selected_type)
	_label(_details, (definition.display_name if definition != null else "") + (" healing" if healing else " damage"), Vector2.ZERO, Vector2(300, 32), 23, Color8(255, 235, 130))
	_label(_details, "Against these target types:", Vector2(0, 32), Vector2(300, 22), 13)
	var chart := catalog.get_type_chart()
	if chart == null: return
	var strong: Array[TypeDefinition] = []
	var weak: Array[TypeDefinition] = []
	for type in _types:
		var value := chart.healing_multiplier(selected_type, type.id) if healing else chart.multiplier(selected_type, type.id)
		if value > 1.00001: strong.append(type)
		elif value < 0.99999: weak.append(type)
	var y := 62.0
	y = _group(strong, y, "Healing boosted" if healing else "Strong against", chart.super_effective_multiplier, TypeEffectivenessPreview.GOOD)
	y = _group(weak, y + 13, "Healing reduced" if healing else "Weak against", chart.not_effective_multiplier, TypeEffectivenessPreview.WEAK)
	_label(_details, "All other types: ×1", Vector2(0, y + 13), Vector2(295, 24), 15)
	_details.custom_minimum_size.y = y + 40

func _group(types: Array[TypeDefinition], y: float, caption: String, multiplier: float, color: Color) -> float:
	_label(_details, "%s · ×%s" % [caption, TypeEffectivenessPreview.multiplier_text(multiplier)], Vector2(0, y), Vector2(300, 28), 18, color)
	y += 31
	if types.is_empty():
		_label(_details, "None", Vector2(2, y), Vector2(295, 22), 14)
		return y + 22
	for index in types.size():
		var at := Vector2(index % 3 * 98, y + floori(index / 3.0) * 26)
		var badge := type_badge(types[index].id)
		if badge != null:
			var image := TextureRect.new()
			image.texture = badge
			image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			image.position = at
			image.size = Vector2(91, 22)
			image.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_details.add_child(image)
		else: _label(_details, types[index].display_name, at, Vector2(91, 22), 14)
	return y + ceili(types.size() / 3.0) * 26

static func type_badge(type_id: StringName) -> Texture2D:
	var key := String(type_id).get_file()
	var result := SourceMenuArt.texture("menus_minionType_%s" % key)
	return result if result != null else SourceMenuArt.texture("moveDescription_type_%s" % key)

static func text_button(parent: Node, caption: String, at: Vector2, dimensions: Vector2, callback: Callable, font_size: int = 15) -> Button:
	var button := Button.new()
	button.text = caption
	button.position = at
	button.size = dimensions
	button.add_theme_font_override("font", FONT)
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", Color8(249, 249, 249))
	button.add_theme_color_override("font_hover_color", Color8(255, 242, 177))
	button.add_theme_color_override("font_pressed_color", Color8(255, 242, 177))
	button.add_theme_color_override("font_disabled_color", Color8(135, 141, 151))
	# This is the original blank bevel used by Buy/Sell/Refresh, not a flat
	# Godot-style rectangle. Nine-slicing preserves its rim at compact sizes.
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxTexture.new()
		style.texture = SourceMenuArt.texture("menus_gemCombiner_buySellButton")
		style.set_texture_margin_all(4)
		style.content_margin_left = 6
		style.content_margin_right = 6
		style.content_margin_top = 2
		style.content_margin_bottom = 2
		if state == "hover": style.modulate_color = Color(1.14, 1.14, 1.1)
		elif state == "pressed": style.modulate_color = Color(0.88, 0.9, 0.95)
		elif state == "disabled": style.modulate_color = Color(0.65, 0.65, 0.65)
		button.add_theme_stylebox_override(state, style)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	parent.add_child(button)
	preload("res://src/presentation/source_menu_button_audio.gd").bind_button(button)
	button.pressed.connect(callback)
	return button

static func tab_button(parent: Node, caption: String, at: Vector2, dimensions: Vector2, callback: Callable) -> Button:
	var button := text_button(parent, caption, at, dimensions, callback, 18)
	for state in ["normal", "hover", "pressed"]:
		var art := AtlasTexture.new()
		art.atlas = SourceMenuArt.texture("menus_skillTree_advancedTabsLeft" if state == "pressed" else "menus_skillTree_advancedTabsCentert")
		art.region = Rect2(0, 0, 107, 35)
		var style := StyleBoxTexture.new()
		style.texture = art
		style.set_texture_margin_all(4)
		style.set_content_margin_all(2)
		if state == "hover": style.modulate_color = Color(1.15, 1.15, 1.15)
		button.add_theme_stylebox_override(state, style)
	button.add_theme_color_override("font_color", Color8(167, 173, 181))
	button.add_theme_color_override("font_pressed_color", Color8(249, 249, 249))
	return button

func _label(parent: Node, text: String, at: Vector2, dimensions: Vector2, font_size: int, color: Color = Color(0.92, 0.92, 0.94), alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.position = at
	label.size = dimensions
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = alignment
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label
