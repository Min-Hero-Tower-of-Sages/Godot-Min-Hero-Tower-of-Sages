class_name ModWorkshopForm
extends VBoxContainer

## Labelled fields bound straight to a mod's JSON records: every edit writes
## into the record and emits `changed`, so the Workshop autosaves the manifest.

signal changed
## Asked to open a picker: (kind: String, on_pick: Callable(id: String)).
signal pick_requested(kind: String, on_pick: Callable)

const FONT := preload("res://content/base/fonts/BurbinCasual.ttf")
# Colours sampled from the recovered Flash menus (menus_movesBackground,
# menus_statsBackground, conformationBox_*), so the Workshop reads like the game.
const GOLD := Color8(255, 236, 112) ## Yellow accent, as in move descriptions.
const INK := Color8(242, 242, 242)
const MUTED := Color8(185, 192, 207)
const SLATE := Color8(94, 106, 128) ## The stone menu background.
const CHARCOAL := Color8(45, 49, 56) ## Inset menu panels.
const CHARCOAL_LIGHT := Color8(58, 63, 72) ## Alternate rows, raised controls.
const DEEP := Color8(25, 30, 37) ## Panel rims, wells and lists.
const EDGE := Color8(98, 105, 118) ## Quiet borders on dark panels.
const RIM := Color8(154, 160, 171) ## Light bevel, like the portrait frames.
const FIELD := Color8(24, 38, 61) ## Text boxes, like the confirmation box.
const GREEN := Color8(74, 195, 11)
const RED := Color8(187, 40, 25)
const OUTLINE := Color8(3, 12, 33)
## The in-game stats panel colours, in order: health, energy, attack, healing, speed.
const STAT_COLORS := [Color8(244, 43, 43), Color8(154, 81, 173), Color8(246, 131, 76), Color8(255, 247, 100), Color8(64, 144, 222)]
const LABEL_WIDTH := 112.0

## A charcoal inset panel, like the game's Stats/Moves/Gems boxes.
static func card_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = CHARCOAL
	style.border_color = DEEP
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	style.shadow_color = Color(0, 0, 0, 0.18)
	style.shadow_size = 2
	style.shadow_offset = Vector2(0, 2)
	return style

## A dark well for lists and pictures.
static func inset_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = DEEP
	style.border_color = Color8(14, 17, 22)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.set_content_margin_all(3)
	return style

## The stone background of the game's menus, stretched inside its white rim.
static func stone_style() -> StyleBox:
	var art := SourceMenuArt.texture("menus_backgroundMedium")
	if art == null:
		var fallback := flat(SLATE, Color.WHITE, 6)
		fallback.set_content_margin_all(10)
		return fallback
	var style := StyleBoxTexture.new()
	style.texture = art
	style.set_texture_margin_all(14)
	style.set_content_margin_all(11)
	return style

## A raised button in one colour, with the game's dark outline.
static func button_style(fill: Color, border: Color = OUTLINE, border_width: int = 2) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(4)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 3
	style.content_margin_bottom = 4
	return style

## Display text for a referenced ID: Callable(kind, id) -> String.
var describe: Callable
## Width of the caption column; narrow panes (the room inspector) use less.
var label_width := LABEL_WIDTH
## Dresses a reference button with pictures: Callable(control, kind, id).
## The Workshop adds type badges, move icons, portraits and move hover cards.
var decorate: Callable

static func theme() -> Theme:
	var result := Theme.new()
	result.default_font = FONT
	result.default_font_size = 14
	var stone := stone_style()
	result.set_stylebox("panel", "PanelContainer", stone)
	result.set_stylebox("panel", "Panel", stone)
	# Buttons: steel grey like the game's tabs; GreenButton/RedButton for
	# adding and removing, like the confirmation box's YES and NO.
	var steel := {"normal": [Color8(72, 79, 92), DEEP], "hover": [Color8(92, 101, 117), RIM], "pressed": [CHARCOAL, Color.WHITE], "disabled": [Color8(52, 56, 63), DEEP]}
	var palettes := {
		"Button": steel,
		"GreenButton": {"normal": [GREEN, OUTLINE], "hover": [GREEN.lightened(0.18), OUTLINE], "pressed": [GREEN.darkened(0.2), OUTLINE], "disabled": [Color8(70, 96, 60), OUTLINE]},
		"RedButton": {"normal": [RED, OUTLINE], "hover": [RED.lightened(0.15), OUTLINE], "pressed": [RED.darkened(0.2), OUTLINE], "disabled": [Color8(100, 62, 58), OUTLINE]},
	}
	var outlines := {"Button": OUTLINE, "GreenButton": Color8(36, 92, 6), "RedButton": Color8(92, 16, 10)}
	for variation in ["GreenButton", "RedButton"]: result.set_type_variation(variation, "Button")
	var focus := button_style(Color(0, 0, 0, 0), Color(1, 1, 1, 0.55))
	focus.draw_center = false
	for control in palettes:
		for state in ["normal", "hover", "pressed", "disabled"]:
			var colours: Array = palettes[control][state]
			var style := button_style(colours[0], colours[1])
			result.set_stylebox(state, control, style)
			if control == "Button":
				for other in ["OptionButton", "MenuButton"]: result.set_stylebox(state, other, style)
		result.set_stylebox("focus", control, focus)
		result.set_color("font_color", control, INK)
		result.set_color("font_hover_color", control, Color.WHITE)
		result.set_color("font_pressed_color", control, Color.WHITE)
		result.set_color("font_hover_pressed_color", control, Color.WHITE)
		result.set_color("font_focus_color", control, Color.WHITE)
		result.set_color("font_disabled_color", control, Color8(140, 144, 152))
		result.set_color("font_outline_color", control, outlines[control])
		result.set_constant("outline_size", control, 3)
		result.set_constant("h_separation", control, 6)
	for control in ["OptionButton", "MenuButton"]:
		result.set_stylebox("focus", control, focus)
		result.set_color("font_color", control, INK)
		result.set_color("font_hover_color", control, Color.WHITE)
		result.set_color("font_outline_color", control, OUTLINE)
		result.set_constant("outline_size", control, 3)
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]: result.set_stylebox(state, "CheckBox", StyleBoxEmpty.new())
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]: result.set_color(state, "CheckBox", INK)
	# Text boxes: navy wells with a light rim, like the confirmation box.
	var field := flat(FIELD, Color8(110, 118, 132), 3)
	var field_focus := flat(FIELD.lightened(0.06), Color.WHITE, 3)
	var field_read_only := flat(FIELD.darkened(0.25), Color8(80, 86, 96), 3)
	for control in ["LineEdit", "TextEdit"]:
		result.set_stylebox("normal", control, field)
		result.set_stylebox("focus", control, field_focus)
		result.set_stylebox("read_only", control, field_read_only)
		result.set_color("font_color", control, INK)
		result.set_color("font_placeholder_color", control, Color8(128, 140, 160))
		result.set_color("caret_color", control, Color.WHITE)
		result.set_color("selection_color", control, Color(GOLD, 0.35))
	# Lists: dark wells; the selected row is raised with a light rim.
	result.set_stylebox("panel", "ItemList", inset_style())
	var selected := flat(CHARCOAL_LIGHT, RIM, 3)
	result.set_stylebox("selected", "ItemList", selected)
	result.set_stylebox("selected_focus", "ItemList", selected)
	result.set_stylebox("hovered", "ItemList", flat(Color(CHARCOAL_LIGHT, 0.6), Color(0, 0, 0, 0), 3))
	result.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	result.set_constant("v_separation", "ItemList", 5)
	result.set_color("font_color", "ItemList", INK)
	result.set_color("font_selected_color", "ItemList", Color.WHITE)
	result.set_color("font_hovered_color", "ItemList", Color.WHITE)
	result.set_color("font_color", "Label", INK)
	var popup := flat(CHARCOAL, RIM, 4)
	popup.set_content_margin_all(4)
	result.set_stylebox("panel", "PopupMenu", popup)
	result.set_stylebox("hover", "PopupMenu", flat(CHARCOAL_LIGHT, Color(0, 0, 0, 0), 3))
	result.set_color("font_color", "PopupMenu", INK)
	result.set_color("font_hover_color", "PopupMenu", GOLD)
	# Section titles: white capitals with a dark outline, like "MINION TYPE".
	result.set_type_variation("HeaderLabel", "Label")
	result.set_font_size("font_size", "HeaderLabel", 17)
	result.set_color("font_color", "HeaderLabel", Color.WHITE)
	result.set_color("font_outline_color", "HeaderLabel", DEEP)
	result.set_constant("outline_size", "HeaderLabel", 4)
	# Picker rows: flat until hovered.
	result.set_type_variation("PickerRow", "Button")
	result.set_stylebox("normal", "PickerRow", flat(Color(CHARCOAL, 0.0), Color(0, 0, 0, 0), 3))
	result.set_stylebox("hover", "PickerRow", flat(CHARCOAL_LIGHT, RIM, 3))
	result.set_stylebox("pressed", "PickerRow", flat(CHARCOAL, Color.WHITE, 3))
	result.set_stylebox("focus", "PickerRow", flat(Color(0, 0, 0, 0), Color(1, 1, 1, 0.4), 3))
	# Tooltips match the game's hover card.
	var tip := flat(Color8(94, 100, 116, 242), Color8(229, 230, 232, 217), 3)
	tip.set_border_width_all(2)
	tip.set_content_margin_all(6)
	result.set_stylebox("panel", "TooltipPanel", tip)
	result.set_color("font_color", "TooltipLabel", Color8(242, 242, 242))
	result.set_color("font_outline_color", "TooltipLabel", DEEP)
	result.set_constant("outline_size", "TooltipLabel", 2)
	result.set_font_size("font_size", "TooltipLabel", 13)
	# Scroll bars: a dark track with a steel grip.
	for bar in ["VScrollBar", "HScrollBar"]:
		result.set_stylebox("scroll", bar, flat(Color(DEEP, 0.75), Color(0, 0, 0, 0), 4))
		result.set_stylebox("grabber", bar, flat(EDGE, Color(0, 0, 0, 0), 4))
		result.set_stylebox("grabber_highlight", bar, flat(RIM, Color(0, 0, 0, 0), 4))
		result.set_stylebox("grabber_pressed", bar, flat(Color.WHITE.darkened(0.15), Color(0, 0, 0, 0), 4))
	result.set_stylebox("tab_unselected", "TabBar", flat(DEEP, Color(0, 0, 0, 0), 4))
	result.set_stylebox("tab_hovered", "TabBar", flat(DEEP, Color(0, 0, 0, 0), 4))
	result.set_stylebox("tab_selected", "TabBar", flat(CHARCOAL_LIGHT, RIM, 4))
	result.set_color("font_selected_color", "TabBar", Color.WHITE)
	result.set_color("font_unselected_color", "TabBar", RIM)
	result.set_color("font_hovered_color", "TabBar", Color.WHITE)
	# Two-level navigation, styled like the game's STATS / MOVES / GEMS tabs:
	# dark tabs with grey text; the open one is raised with white text.
	for variation in [["NavPrimary", 15, 4], ["NavSecondary", 13, 2]]:
		result.set_type_variation(variation[0], "Button")
		result.set_font_size("font_size", variation[0], variation[1])
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
			var open: bool = state in ["pressed", "hover_pressed"]
			var nav := StyleBoxFlat.new()
			nav.bg_color = {"normal": DEEP, "hover": Color8(40, 45, 54), "pressed": CHARCOAL_LIGHT, "hover_pressed": Color8(68, 74, 85), "disabled": Color8(30, 34, 40), "focus": Color(0, 0, 0, 0)}[state]
			nav.border_color = (Color.WHITE if variation[0] == "NavPrimary" else RIM) if open else Color8(14, 17, 22)
			nav.set_border_width_all(2 if open else 1)
			if variation[0] == "NavPrimary" and open: nav.border_width_bottom = 3
			nav.set_corner_radius_all(4)
			nav.content_margin_left = 9
			nav.content_margin_right = 9
			nav.content_margin_top = variation[2]
			nav.content_margin_bottom = variation[2] + 1
			if state == "focus": nav.draw_center = false
			result.set_stylebox(state, variation[0], nav)
		result.set_color("font_color", variation[0], RIM)
		result.set_color("font_pressed_color", variation[0], Color.WHITE)
		result.set_color("font_hover_pressed_color", variation[0], Color.WHITE)
		result.set_color("font_hover_color", variation[0], Color.WHITE)
		result.set_color("font_focus_color", variation[0], RIM)
		result.set_color("font_outline_color", variation[0], Color8(10, 12, 16))
		result.set_constant("outline_size", variation[0], 3)
	return result

## Add and remove buttons take the game's green and red; other buttons stay
## steel grey. Decided from the caption so every caller agrees.
static func tint_button(control: Button) -> void:
	var caption := control.text.strip_edges()
	for prefix in ["+", "New ", "Add ", "Start "]:
		if caption.begins_with(prefix):
			control.theme_type_variation = &"GreenButton"
			return
	if caption == "x" or caption.begins_with("Remove") or caption.begins_with("Delete"):
		control.theme_type_variation = &"RedButton"

## A small coloured label, e.g. a count or a status.
static func chip(text: String, tint: Color, parent: Control = null) -> PanelContainer:
	var holder := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(tint, 0.2)
	style.border_color = Color(tint, 0.65)
	style.set_border_width_all(1)
	style.set_corner_radius_all(9)
	style.content_margin_left = 7
	style.content_margin_right = 7
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	holder.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", tint.lightened(0.35))
	holder.add_child(label)
	if parent != null: parent.add_child(holder)
	return holder

## A StyleBoxFlat with one flat colour, for custom-drawn buttons and panels.
static func flat(color: Color, border: Color = Color(0, 0, 0, 0), radius: int = 4) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1 if border.a > 0.0 else 0)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	return style

## A fixed-size picture (portrait, icon or badge) inside the form.
static func picture(texture: Texture2D, picture_size: Vector2, parent: Control = null) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = texture
	rect.custom_minimum_size = picture_size
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if parent != null: parent.add_child(rect)
	return rect

func _init() -> void:
	add_theme_constant_override("separation", 4)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

func clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

func heading(text: String) -> Label:
	if get_child_count() > 0:
		var space := Control.new()
		space.custom_minimum_size.y = 4
		add_child(space)
	var label := Label.new()
	label.text = text
	label.uppercase = true
	label.theme_type_variation = &"HeaderLabel"
	# Capitals run wide; long titles wrap instead of widening narrow panels.
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 100
	add_child(label)
	var rule := ColorRect.new()
	rule.color = Color(RIM, 0.35)
	rule.custom_minimum_size.y = 1
	add_child(rule)
	return label

## A boxed group of fields with an optional title. The returned form writes
## to the same records and uses the same picker as this one.
func card(title: String = "") -> ModWorkshopForm:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", card_style())
	add_child(panel)
	var nested := ModWorkshopForm.new()
	nested.describe = describe
	nested.decorate = decorate
	nested.label_width = label_width
	nested.changed.connect(func() -> void: changed.emit())
	nested.pick_requested.connect(func(kind: String, on_pick: Callable) -> void: pick_requested.emit(kind, on_pick))
	panel.add_child(nested)
	if not title.is_empty(): nested.heading(title)
	return nested

## Less common settings stay available without making every editor a wall of
## fields. The nested form writes the same records and uses the same picker.
func foldout(caption: String, expanded: bool = false) -> ModWorkshopForm:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", card_style())
	add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	var toggle := Button.new()
	toggle.text = ("− " if expanded else "+ ") + caption
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggle.flat = true
	column.add_child(toggle)
	var nested := ModWorkshopForm.new()
	nested.describe = describe
	nested.decorate = decorate
	nested.label_width = label_width
	nested.changed.connect(func() -> void: changed.emit())
	nested.pick_requested.connect(func(kind: String, on_pick: Callable) -> void: pick_requested.emit(kind, on_pick))
	nested.visible = expanded
	column.add_child(nested)
	toggle.pressed.connect(func() -> void:
		nested.visible = not nested.visible
		toggle.text = ("− " if nested.visible else "+ ") + caption)
	return nested

func note(text: String, color: Color = MUTED) -> Label:
	var label := _label(text, 12, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 120
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(label)
	return label

func row(caption: String, parent: Control = null) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	(parent if parent != null else self).add_child(line)
	if not caption.is_empty():
		var label := _label(caption, 13, INK)
		label.custom_minimum_size = Vector2(label_width, 0)
		label.clip_text = true
		line.add_child(label)
	return line

func button(text: String, callback: Callable, parent: Control = null) -> Button:
	var control := Button.new()
	control.text = text
	control.pressed.connect(callback)
	control.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tint_button(control)
	(parent if parent != null else row("")).add_child(control)
	return control

func text(caption: String, record: Dictionary, key: String, max_length: int = 32, multiline: bool = false) -> Control:
	var line := row(caption)
	var control: Control
	if multiline:
		var edit := TextEdit.new()
		edit.text = String(record.get(key, ""))
		edit.custom_minimum_size = Vector2(0, 54)
		edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		edit.text_changed.connect(func() -> void:
			record[key] = edit.text.left(max_length)
			changed.emit())
		control = edit
	else:
		var edit := LineEdit.new()
		edit.text = String(record.get(key, ""))
		edit.max_length = max_length
		edit.text_changed.connect(func(value: String) -> void:
			record[key] = value
			changed.emit())
		control = edit
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(control)
	return control

func number(caption: String, record: Dictionary, key: String, minimum: float, maximum: float, fallback: float = 0, step: float = 1, parent: Control = null) -> SpinBox:
	var line := row(caption) if parent == null else parent
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.value = float(record.get(key, fallback))
	spin.custom_minimum_size.x = 92
	spin.get_line_edit().add_theme_font_size_override("font_size", 13)
	if not record.has(key): record[key] = int(fallback) if is_equal_approx(step, 1.0) else fallback
	spin.value_changed.connect(func(value: float) -> void:
		record[key] = int(value) if is_equal_approx(step, 1.0) else value
		changed.emit())
	line.add_child(spin)
	return spin

func slider(caption: String, record: Dictionary, key: String, minimum: float, maximum: float, fallback: float) -> HSlider:
	var line := row(caption)
	var bar := HSlider.new()
	bar.min_value = minimum
	bar.max_value = maximum
	bar.step = 0.01
	bar.value = float(record.get(key, fallback))
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.custom_minimum_size.y = 20
	var readout := _label("%.2f" % bar.value, 12, MUTED)
	readout.custom_minimum_size.x = 36
	bar.value_changed.connect(func(value: float) -> void:
		record[key] = snappedf(value, 0.01)
		readout.text = "%.2f" % value
		changed.emit())
	line.add_child(bar)
	line.add_child(readout)
	return bar

func toggle(caption: String, record: Dictionary, key: String, parent: Control = null) -> CheckBox:
	var box := CheckBox.new()
	box.text = caption
	box.button_pressed = bool(record.get(key, false))
	box.toggled.connect(func(value: bool) -> void:
		record[key] = value
		changed.emit())
	(parent if parent != null else row("")).add_child(box)
	return box

func choice(caption: String, record: Dictionary, key: String, values: Array, labels: Array = [], parent: Control = null, on_change: Callable = Callable()) -> OptionButton:
	var line := row(caption) if parent == null else parent
	var option := OptionButton.new()
	var current := str(record.get(key, values[0] if not values.is_empty() else ""))
	for index in values.size():
		option.add_item(String(labels[index]) if index < labels.size() else String(values[index]).capitalize())
		if str(values[index]) == current: option.select(index)
	option.fit_to_longest_item = false
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.clip_text = true
	option.custom_minimum_size.x = 120
	option.item_selected.connect(func(index: int) -> void:
		record[key] = values[index]
		changed.emit()
		if on_change.is_valid(): on_change.call())
	line.add_child(option)
	return option

func color(caption: String, record: Dictionary, key: String) -> ColorPickerButton:
	var line := row(caption)
	var picker := ColorPickerButton.new()
	picker.color = Color.from_string(String(record.get(key, "#ffffff")), Color.WHITE)
	picker.edit_alpha = false
	picker.custom_minimum_size = Vector2(80, 24)
	picker.color_changed.connect(func(value: Color) -> void:
		record[key] = "#" + value.to_html(false)
		changed.emit())
	line.add_child(picker)
	return picker

## A button showing the referenced content; pressing it opens the picker.
func reference(caption: String, record: Dictionary, key: String, kind: String, allow_empty: bool = false, parent: Control = null, on_change: Callable = Callable()) -> Button:
	var line := row(caption) if parent == null else parent
	var control := Button.new()
	control.clip_text = true
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.custom_minimum_size.x = 120
	control.alignment = HORIZONTAL_ALIGNMENT_LEFT
	control.text = _describe(kind, String(record.get(key, "")))
	control.tooltip_text = String(record.get(key, ""))
	_decorate(control, kind, String(record.get(key, "")))
	control.pressed.connect(func() -> void:
		pick_requested.emit(kind, func(id: String) -> void:
			record[key] = id
			control.text = _describe(kind, id)
			control.tooltip_text = id
			_decorate(control, kind, id)
			changed.emit()
			if on_change.is_valid(): on_change.call()))
	line.add_child(control)
	if allow_empty:
		var clear_button := Button.new()
		clear_button.text = "x"
		tint_button(clear_button)
		clear_button.tooltip_text = "None"
		clear_button.pressed.connect(func() -> void:
			record[key] = ""
			control.text = _describe(kind, "")
			_decorate(control, kind, "")
			changed.emit()
			if on_change.is_valid(): on_change.call())
		line.add_child(clear_button)
	return control

## An ordered list of references with add/remove, e.g. a minion's moves.
func reference_list(caption: String, record: Dictionary, key: String, kind: String, maximum: int, minimum: int = 0) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var header := row(caption)
	var add := Button.new()
	add.text = "+ Add"
	tint_button(add)
	header.add_child(add)
	add_child(box)
	if not record.get(key) is Array: record[key] = []
	var rebuild := func(self_callable: Callable) -> void:
		for child in box.get_children():
			box.remove_child(child)
			child.queue_free()
		var values: Array = record[key]
		add.disabled = values.size() >= maximum
		for index in values.size():
			var line := HBoxContainer.new()
			box.add_child(line)
			var spacer := Control.new()
			spacer.custom_minimum_size.x = label_width
			line.add_child(spacer)
			var item := Button.new()
			item.text = _describe(kind, String(values[index]))
			item.tooltip_text = String(values[index])
			item.clip_text = true
			item.alignment = HORIZONTAL_ALIGNMENT_LEFT
			item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_decorate(item, kind, String(values[index]))
			item.pressed.connect(func() -> void:
				pick_requested.emit(kind, func(id: String) -> void:
					values[index] = id
					changed.emit()
					self_callable.call(self_callable)))
			line.add_child(item)
			var remove := Button.new()
			remove.text = "x"
			tint_button(remove)
			remove.disabled = values.size() <= minimum
			remove.pressed.connect(func() -> void:
				values.remove_at(index)
				changed.emit()
				self_callable.call(self_callable))
			line.add_child(remove)
	add.pressed.connect(func() -> void:
		pick_requested.emit(kind, func(id: String) -> void:
			(record[key] as Array).append(id)
			changed.emit()
			rebuild.call(rebuild)))
	rebuild.call(rebuild)
	return box

func separator() -> void:
	var line := HSeparator.new()
	line.add_theme_constant_override("separation", 8)
	add_child(line)

func _decorate(control: Control, kind: String, id: String) -> void:
	if decorate.is_valid(): decorate.call(control, kind, id)

func _describe(kind: String, id: String) -> String:
	if id.is_empty(): return "(none)"
	return describe.call(kind, id) if describe.is_valid() else id

func _label(value: String, font_size: int, tint: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", tint)
	return label
