class_name ModWorkshopPicker
extends Control

## A searchable list over the Workshop: pick a minion, move, type, trainer...
## Each row shows the entry's picture (portrait, move icon or type badge) and
## the type badges of minions and moves, like the game's own menus.

signal picked(id: String)

const ROW_HEIGHT := 32.0

## Callable(kind, id) -> Texture2D: the row's picture.
var icon_for := Callable()
## Callable(kind, id) -> Array of type IDs shown as badges on the right.
var types_for := Callable()
## Callable(kind, id) -> Texture2D for one type badge.
var badge_for := Callable()
## Callable(control, id): binds the move hover card to a row.
var hover_for := Callable()

var _entries: Array = []
var _kind := ""
var _rows: Array[Button] = []
var _filter: LineEdit
var _count: Label
var _empty: Label

## `entries`: [{"id", "label", "detail"}], already sorted.
func open(title: String, entries: Array, kind: String = "") -> void:
	_entries = entries
	_kind = kind
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 50
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0, 0, 0, 0.55)
	shade.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed: queue_free())
	add_child(shade)
	var panel := PanelContainer.new()
	panel.position = Vector2(130, 24)
	panel.size = Vector2(440, 477)
	add_child(panel)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	panel.add_child(rows)
	var header := HBoxContainer.new()
	rows.add_child(header)
	var heading := Label.new()
	heading.text = title
	heading.uppercase = true
	heading.theme_type_variation = &"HeaderLabel"
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	_count = Label.new()
	_count.add_theme_font_size_override("font_size", 12)
	_count.add_theme_color_override("font_color", ModWorkshopForm.MUTED)
	header.add_child(_count)
	_filter = LineEdit.new()
	_filter.placeholder_text = "Search by name, ID or type"
	_filter.clear_button_enabled = true
	_filter.text_changed.connect(func(_value: String) -> void: _refresh())
	_filter.text_submitted.connect(func(_value: String) -> void:
		var shown := _rows.filter(func(row: Button) -> bool: return row.visible)
		if shown.size() == 1: _choose(String(shown[0].get_meta(&"id"))))
	rows.add_child(_filter)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", ModWorkshopForm.inset_style())
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(frame)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	frame.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 1)
	scroll.add_child(list)
	for entry in entries: list.add_child(_row(entry))
	_empty = Label.new()
	_empty.text = "Nothing matches that search."
	_empty.add_theme_color_override("font_color", ModWorkshopForm.MUTED)
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	list.add_child(_empty)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(queue_free)
	rows.add_child(cancel)
	_refresh()
	_filter.grab_focus.call_deferred()

func _row(entry: Dictionary) -> Button:
	var id := String(entry.id)
	var row := Button.new()
	row.theme_type_variation = &"PickerRow"
	row.custom_minimum_size.y = ROW_HEIGHT
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.set_meta(&"id", id)
	row.pressed.connect(func() -> void: _choose(id))
	var line := HBoxContainer.new()
	line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	line.offset_left = 4
	line.offset_right = -6
	line.add_theme_constant_override("separation", 7)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(line)
	var is_type := _kind in ["type", "minion_type"]
	var picture: Texture2D = icon_for.call(_kind, id) if icon_for.is_valid() else null
	if picture != null or not is_type:
		ModWorkshopForm.picture(picture, Vector2(64, 20) if is_type else Vector2(28, 28), line)
	var name_label := Label.new()
	name_label.text = String(entry.label)
	name_label.clip_text = true
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if String(entry.label).begins_with("* "): name_label.add_theme_color_override("font_color", ModWorkshopForm.GOLD)
	line.add_child(name_label)
	var search_text := "%s %s %s" % [entry.label, id, entry.get("detail", "")]
	var types: Array = types_for.call(_kind, id) if types_for.is_valid() else []
	for type_id in types:
		var badge: Texture2D = badge_for.call(String(type_id)) if badge_for.is_valid() else null
		if badge != null: ModWorkshopForm.picture(badge, Vector2(50, 16), line)
		search_text += " " + String(type_id).get_file()
	if types.is_empty() and not String(entry.get("detail", "")).is_empty():
		var detail := Label.new()
		detail.text = String(entry.detail)
		detail.add_theme_font_size_override("font_size", 12)
		detail.add_theme_color_override("font_color", ModWorkshopForm.MUTED)
		detail.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(detail)
	row.set_meta(&"search", search_text.to_lower())
	if _kind == "move" and hover_for.is_valid(): hover_for.call(row, id)
	else: row.tooltip_text = id
	_rows.append(row)
	return row

func _refresh() -> void:
	var query := _filter.text.strip_edges().to_lower()
	var shown := 0
	for row in _rows:
		row.visible = query.is_empty() or String(row.get_meta(&"search")).contains(query)
		if row.visible: shown += 1
	_empty.visible = shown == 0
	_count.text = "%d of %d" % [shown, _rows.size()] if not query.is_empty() else "%d to choose from" % _rows.size()

func has_entry(id: String) -> bool:
	return _rows.any(func(row: Button) -> bool: return row.get_meta(&"id") == id)

func _choose(id: String) -> void:
	picked.emit(id)
	queue_free()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		queue_free()
