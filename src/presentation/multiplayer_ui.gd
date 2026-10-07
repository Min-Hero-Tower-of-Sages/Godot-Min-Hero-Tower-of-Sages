class_name MultiplayerUi
extends RefCounted

## Widget helpers for the multiplayer panels. Colors are sampled from the
## source in-game menu (menus_topDownMenuPopUp_*): a slate panel with a light
## rim and steel-blue buttons, so the multiplayer screens read as part of it.

const FONT := preload("res://content/base/fonts/BurbinCasual.ttf")
const BUTTON_AUDIO := preload("res://src/presentation/source_menu_button_audio.gd")
const PANEL_FILL := Color8(45, 49, 56)
const PANEL_RIM := Color8(66, 72, 83)
const PANEL_EDGE := Color8(214, 219, 228)
const BUTTON_FILL := Color8(114, 129, 151)
const BUTTON_HOVER := Color8(136, 152, 176)
const BUTTON_EDGE := Color8(36, 42, 51)
const BUTTON_SHINE := Color8(178, 184, 194)
const INK := Color8(236, 238, 242)
const CREAM := Color8(255, 255, 255)
const GOLD := Color8(255, 214, 110)
const ERROR := Color8(255, 120, 110)
const MUTED := Color8(168, 176, 190)
const SCREEN_SIZE := Vector2(700.0, 525.0)

## Slate panel styled like the source menu popup background.
static func panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_FILL
	style.border_color = PANEL_RIM
	style.set_border_width_all(4)
	style.set_corner_radius_all(6)
	style.shadow_color = Color(0, 0, 0, 0.4)
	style.shadow_size = 5
	style.expand_margin_left = 2.0
	style.expand_margin_right = 2.0
	style.expand_margin_top = 2.0
	style.expand_margin_bottom = 2.0
	return style

## A standalone slate panel (no shade), e.g. beside the in-game menu popup.
static func panel(parent: Control, at: Vector2, panel_size: Vector2) -> Panel:
	var widget := Panel.new()
	widget.position = at
	widget.size = panel_size
	widget.add_theme_stylebox_override("panel", panel_style())
	var edge := ReferenceRect.new()
	edge.border_color = PANEL_EDGE
	edge.border_width = 1.0
	edge.editor_only = false
	edge.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	edge.offset_left = -2.0
	edge.offset_top = -2.0
	edge.offset_right = 2.0
	edge.offset_bottom = 2.0
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	widget.add_child(edge)
	parent.add_child(widget)
	return widget

## Full-screen shade with a centered slate panel; returns the panel.
static func modal(owner: Control, panel_size: Vector2) -> Panel:
	owner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	owner.mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.0, 0.0, 0.0, 0.45)
	owner.add_child(shade)
	return panel(owner, ((SCREEN_SIZE - panel_size) * 0.5).round(), panel_size)

## Uppercase heading like the source menu button captions.
static func title(parent: Control, text: String, at: Vector2, width: float, font_size: int = 22) -> Label:
	var widget := label(parent, text.to_upper(), at, Vector2(width, font_size + 10.0), font_size, CREAM)
	widget.add_theme_color_override("font_outline_color", BUTTON_EDGE)
	widget.add_theme_constant_override("outline_size", 4)
	return widget

static func label(parent: Control, text: String, at: Vector2, label_size: Vector2, font_size: int = 16, color: Color = INK) -> Label:
	var widget := Label.new()
	widget.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	widget.add_theme_font_override("font", FONT)
	widget.add_theme_font_size_override("font_size", font_size)
	widget.add_theme_color_override("font_color", color)
	widget.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# A wrapping label sizes itself from its text unless its width is pinned
	# first: minimum width keeps long sentences inside the panel.
	widget.custom_minimum_size = Vector2(label_size.x, 0.0)
	widget.position = at
	widget.size = label_size
	widget.text = text
	parent.add_child(widget)
	return widget

static func _button_style(fill: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = BUTTON_EDGE
	style.set_border_width_all(2)
	style.border_width_top = 3
	style.set_corner_radius_all(4)
	style.content_margin_left = 6.0
	style.content_margin_right = 6.0
	return style

## Steel-blue button matching the source menu buttons (white caps caption).
static func button(parent: Control, text: String, at: Vector2, button_size: Vector2, action: Callable, font_size: int = 17) -> Button:
	var widget := Button.new()
	widget.text = text.to_upper()
	widget.position = at
	widget.size = button_size
	widget.custom_minimum_size = button_size
	widget.clip_text = true
	widget.add_theme_font_override("font", FONT)
	widget.add_theme_font_size_override("font_size", font_size)
	widget.add_theme_color_override("font_color", CREAM)
	widget.add_theme_color_override("font_hover_color", CREAM)
	widget.add_theme_color_override("font_pressed_color", GOLD)
	widget.add_theme_color_override("font_focus_color", CREAM)
	widget.add_theme_color_override("font_disabled_color", Color(CREAM, 0.4))
	widget.add_theme_color_override("font_outline_color", BUTTON_EDGE)
	widget.add_theme_constant_override("outline_size", 3)
	var normal := _button_style(BUTTON_FILL)
	normal.border_color = BUTTON_EDGE
	widget.add_theme_stylebox_override("normal", normal)
	var hover := _button_style(BUTTON_HOVER)
	widget.add_theme_stylebox_override("hover", hover)
	var pressed := _button_style(BUTTON_FILL.darkened(0.15))
	pressed.border_color = GOLD
	widget.add_theme_stylebox_override("pressed", pressed)
	widget.add_theme_stylebox_override("hover_pressed", pressed)
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = BUTTON_SHINE
	focus.set_border_width_all(1)
	focus.set_corner_radius_all(4)
	widget.add_theme_stylebox_override("focus", focus)
	var disabled := _button_style(Color8(78, 84, 96))
	widget.add_theme_stylebox_override("disabled", disabled)
	widget.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	widget.focus_mode = Control.FOCUS_ALL
	if action.is_valid():
		widget.pressed.connect(action)
	parent.add_child(widget)
	BUTTON_AUDIO.bind_button(widget)
	return widget

## A two-or-more way choice made of toggle buttons; `on_pick(index)` fires on
## click. Returns the buttons so callers can relabel or disable them.
static func choice_row(parent: Control, labels: PackedStringArray, at: Vector2, width: float, height: float, selected: int, on_pick: Callable, font_size: int = 15) -> Array[Button]:
	var buttons: Array[Button] = []
	var gap := 6.0
	var each := (width - gap * float(labels.size() - 1)) / float(labels.size())
	for index in labels.size():
		var option := button(parent, labels[index], at + Vector2((each + gap) * float(index), 0.0), Vector2(each, height), Callable(), font_size)
		option.toggle_mode = true
		option.button_pressed = index == selected
		buttons.append(option)
	for index in buttons.size():
		buttons[index].pressed.connect(func() -> void:
			for other in buttons.size():
				buttons[other].set_pressed_no_signal(other == index)
			on_pick.call(index)
		)
	return buttons

static func field(parent: Control, caption: String, value: String, at: Vector2, width: float, max_length: int = 0) -> LineEdit:
	label(parent, caption, at, Vector2(width, 20.0), 14, MUTED)
	var edit := LineEdit.new()
	edit.text = value
	edit.position = at + Vector2(0.0, 20.0)
	edit.size = Vector2(width, 30.0)
	edit.max_length = max_length
	edit.add_theme_font_override("font", FONT)
	edit.add_theme_font_size_override("font_size", 17)
	edit.add_theme_color_override("font_color", INK)
	edit.add_theme_color_override("caret_color", GOLD)
	var style := StyleBoxFlat.new()
	style.bg_color = Color8(30, 33, 39)
	style.border_color = PANEL_RIM.lightened(0.15)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 6.0
	style.content_margin_right = 6.0
	edit.add_theme_stylebox_override("normal", style)
	var focus := style.duplicate() as StyleBoxFlat
	focus.border_color = BUTTON_SHINE
	focus.set_border_width_all(2)
	edit.add_theme_stylebox_override("focus", focus)
	parent.add_child(edit)
	return edit

## Outlined text that stays readable over any room art (HUD, toasts).
static func hud_label(parent: Control, text: String, at: Vector2, label_size: Vector2, font_size: int, color: Color = Color.WHITE) -> Label:
	var widget := label(parent, text, at, label_size, font_size, color)
	widget.autowrap_mode = TextServer.AUTOWRAP_OFF
	widget.custom_minimum_size = Vector2.ZERO
	widget.add_theme_color_override("font_outline_color", Color(0.06, 0.05, 0.1, 0.95))
	widget.add_theme_constant_override("outline_size", 5)
	return widget
