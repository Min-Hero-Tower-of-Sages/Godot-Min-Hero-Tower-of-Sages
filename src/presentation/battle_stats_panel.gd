class_name BattleStatsPanel
extends PanelContainer

## Opened by clicking a minion's health bar. Your own minion: its current
## health, energy, attack, healing and speed (with buffs/debuffs), and a
## Details toggle for its name and types. An enemy you have faced before
## (it is in your Minion-pedia): only its name and types. It reads the minion
## view's presented state, never the engine's, so it never spoils a turn.
## Styled like the move tooltip (the source's grey battle frame).

const BURBIN_FONT := preload("res://content/base/fonts/BurbinCasual.ttf")
const SCREEN := Vector2(700.0, 525.0)
const LABEL := "#c9ccd4"
const UP := "#fff568"
const DOWN := "#e57dff"
const HEALTH := "#8ee07a"
const ENERGY := "#7fc4ff"
const SHIELD := "#d8dde6"

## The Details toggle is remembered between minions and battles.
static var details_open := false

var instance_id: StringName = &""
var _identity: VBoxContainer
var _name: Label
var _types: HBoxContainer
var _stats: RichTextLabel
var _details_button: Button
var _anchor := Vector2.ZERO
var _own := true

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color8(94, 100, 116, 242)
	frame.border_color = Color8(229, 230, 232, 217)
	frame.set_border_width_all(2)
	frame.set_corner_radius_all(3)
	frame.content_margin_left = 8
	frame.content_margin_right = 8
	frame.content_margin_top = 4
	frame.content_margin_bottom = 3
	add_theme_stylebox_override("panel", frame)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 2)
	add_child(column)
	_identity = VBoxContainer.new()
	_identity.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_identity.add_theme_constant_override("separation", 2)
	column.add_child(_identity)
	_name = Label.new()
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.add_theme_font_override("font", BURBIN_FONT)
	_name.add_theme_font_size_override("font_size", 17)
	_name.add_theme_color_override("font_color", Color8(242, 242, 242))
	_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_identity.add_child(_name)
	_types = HBoxContainer.new()
	_types.alignment = BoxContainer.ALIGNMENT_CENTER
	_types.add_theme_constant_override("separation", 4)
	_types.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_identity.add_child(_types)
	_stats = RichTextLabel.new()
	_stats.bbcode_enabled = true
	_stats.fit_content = true
	_stats.scroll_active = false
	_stats.autowrap_mode = TextServer.AUTOWRAP_OFF
	_stats.custom_minimum_size.x = 132.0
	_stats.add_theme_font_override("normal_font", BURBIN_FONT)
	_stats.add_theme_font_size_override("normal_font_size", 14)
	_stats.add_theme_constant_override("table_h_separation", 10)
	_stats.add_theme_constant_override("line_separation", -2)
	_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_stats)
	_details_button = Button.new()
	_details_button.name = "DetailsButton"
	_details_button.flat = true
	_details_button.focus_mode = Control.FOCUS_NONE
	_details_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_details_button.add_theme_font_override("font", BURBIN_FONT)
	_details_button.add_theme_font_size_override("font_size", 12)
	_details_button.add_theme_color_override("font_color", Color8(201, 204, 212))
	_details_button.add_theme_color_override("font_hover_color", Color8(255, 245, 104))
	_details_button.add_theme_color_override("font_pressed_color", Color8(255, 245, 104))
	for state in ["normal", "hover", "pressed", "focus"]:
		_details_button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	_details_button.pressed.connect(_toggle_details)
	column.add_child(_details_button)

## Your own minion: stats (and, with Details, its name and types).
func show_own(view: BattleCombatantView, content: ContentCatalog) -> void:
	_own = true
	_open(view, content)

## An enemy you have faced before: its name and types only.
func show_enemy(view: BattleCombatantView, content: ContentCatalog) -> void:
	_own = false
	_open(view, content)

func close() -> void:
	visible = false
	instance_id = &""

func _open(view: BattleCombatantView, content: ContentCatalog) -> void:
	instance_id = view.instance_id
	_anchor = view.get_global_transform_with_canvas().origin
	_fill_identity(view, content)
	refresh(view)
	visible = true
	modulate.a = 0.0
	# Real time: the panel also opens while a replay is paused.
	create_tween().set_ignore_time_scale(true).tween_property(self, "modulate:a", 1.0, 0.1)

func refresh(view: BattleCombatantView) -> void:
	_identity.visible = details_open or not _own
	_stats.visible = _own
	_details_button.visible = _own
	_details_button.text = "Hide details" if details_open else "Details"
	if _own:
		_stats.text = _stat_rows(view.state_cache)
	_place()

func _toggle_details() -> void:
	details_open = not details_open
	_identity.visible = details_open
	_details_button.text = "Hide details" if details_open else "Details"
	_place()

func _fill_identity(view: BattleCombatantView, content: ContentCatalog) -> void:
	_name.text = view.minion_definition.display_name if view.minion_definition != null else "Minion"
	for child in _types.get_children():
		_types.remove_child(child) # Now, so the panel sizes to the new badges.
		child.queue_free()
	for type_id in view.state_cache.get("type_ids", []):
		# The source's own type badges ("ELECTRIC" for base:type/energy).
		var badge := SourceMenuArt.image(_types, "menus_minionType_%s" % String(type_id).get_file(), Vector2.ZERO)
		if badge == null:
			var fallback := content.get_definition(StringName(type_id))
			var label := Label.new()
			label.text = fallback.display_name if fallback != null else String(type_id).get_file().capitalize()
			label.add_theme_font_override("font", BURBIN_FONT)
			label.add_theme_font_size_override("font_size", 12)
			_types.add_child(label)

## Health, energy, attack, healing, speed. A stat stage shows as +N / -N.
func _stat_rows(state: Dictionary) -> String:
	var stages: Dictionary = state.get("stat_stages", {})
	var health := "[color=%s]%d[/color]/%d" % [HEALTH, int(state.get("health", 0)), int(state.get("max_health", 0))]
	if int(state.get("shield", 0)) > 0:
		health += " [color=%s]+%d[/color]" % [SHIELD, int(state.shield)]
	var rows := [
		["Health", health],
		["Energy", "[color=%s]%d[/color]/%d" % [ENERGY, int(state.get("energy", 0)), int(state.get("max_energy", 0))]],
		["Attack", _staged(int(state.get("attack", 0)), int(stages.get(&"base:stat/attack", 0)))],
		["Healing", _staged(int(state.get("healing", 0)), int(stages.get(&"base:stat/healing", 0)))],
		["Speed", _staged(int(state.get("speed", 0)), int(stages.get(&"base:stat/speed", 0)))],
	]
	var cells := ""
	for row in rows:
		cells += "[cell][color=%s]%s[/color][/cell][cell]%s[/cell]" % [LABEL, row[0], row[1]]
	return "[table=2]%s[/table]" % cells

func _staged(value: int, stage: int) -> String:
	if stage == 0:
		return str(value)
	return "%d [color=%s]%+d[/color]" % [value, UP if stage > 0 else DOWN, stage]

## Beside the minion, on the open side, kept on screen.
func _place() -> void:
	size = Vector2.ZERO
	reset_size()
	var at := _anchor + Vector2(42.0, -size.y * 0.5 - 50.0)
	if at.x + size.x > SCREEN.x - 6.0:
		at.x = _anchor.x - size.x - 42.0
	position = Vector2(clampf(at.x, 6.0, SCREEN.x - size.x - 6.0), clampf(at.y, 6.0, SCREEN.y - size.y - 6.0))
