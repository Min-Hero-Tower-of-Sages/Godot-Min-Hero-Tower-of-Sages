class_name CampaignModMenuView
extends Control

signal closed

const FONT := preload("res://content/base/fonts/BurbinCasual.ttf")
var _session: CampaignSession
var _panel: Control
var _category := 0
var _selected_group := ""
var _message := ""
var _description: Label
var _category_buttons: Array[Button] = []
var _toggles: Dictionary = {}

func configure(session: CampaignSession) -> void:
	_session = session
	if is_inside_tree(): _build()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if _session != null: _build()

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey: return
	get_viewport().set_input_as_handled()
	if event.pressed and not event.echo and event.keycode == KEY_ESCAPE: closed.emit()

func _build() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_category_buttons.clear()
	_toggles.clear()
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0, 0, 0, 0.65)
	add_child(shade)
	var factor := minf(get_viewport_rect().size.x / 700.0, get_viewport_rect().size.y / 525.0)
	_panel = Control.new()
	_panel.name = "SavedModPanel"
	_panel.size = Vector2(690, 468)
	_panel.position = (get_viewport_rect().size - Vector2(700, 525) * factor) * 0.5 + Vector2(5, 40) * factor
	_panel.scale = Vector2.ONE * factor
	add_child(_panel)
	SourceMenuArt.image(_panel, "menus_backgroundLarge", Vector2.ZERO)
	SourceMenuArt.image(_panel, "minionPedia_background", Vector2(21, 18))
	_label("Mod Menu", Vector2(35, 26), Vector2(615, 38), 28).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label("For this save", Vector2(38, 78), Vector2(190, 24), 17, Color8(247, 226, 153))
	for index in CampaignModService.CATEGORIES.size():
		var category: Dictionary = CampaignModService.CATEGORIES[index]
		var count := 0
		for group in category.groups:
			if CampaignModService.group_enabled(_session.state.active_mods, group): count += 1
		var button := TypeGuideView.text_button(_panel, "%s\n%d / %d enabled" % [category.name, count, category.groups.size()], Vector2(37, 109 + index * 63), Vector2(190, 55), _open_category.bind(index), 16)
		button.name = "SavedModCategory_%s" % category.id
		button.modulate = Color.WHITE if index == _category else Color(0.78, 0.8, 0.85)
		_category_buttons.append(button)
	var category: Dictionary = CampaignModService.CATEGORIES[_category]
	_label(category.name, Vector2(253, 78), Vector2(390, 30), 21)
	var scroll := ScrollContainer.new()
	scroll.name = "SavedModRows"
	scroll.position = Vector2(253, 118)
	scroll.size = Vector2(390, 168)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 0)
	scroll.add_child(rows)
	for group in category.groups: _build_row(rows, String(group))
	_description = _label("", Vector2(254, 297), Vector2(389, 108), 13, Color8(223, 226, 235))
	_description.name = "SavedModDescription"
	if _selected_group not in category.groups: _selected_group = String(category.groups[0])
	_describe(_selected_group)
	_label(_message if not _message.is_empty() else "Changes save immediately · no new save needed", Vector2(146, 415), Vector2(493, 26), 13, Color8(247, 226, 153)).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	SourceMenuArt.button(_panel, "menus_returnButton", Vector2(3, 409), func() -> void: closed.emit())
	SourceMenuArt.button(_panel, "menus_exitButton", Vector2(624, -22), func() -> void: closed.emit())

func _build_row(rows: VBoxContainer, group: String) -> void:
	var option: Dictionary = CampaignModService.OPTIONS[CampaignModService.option_index(group)]
	var row := Control.new()
	row.custom_minimum_size = Vector2(373, 42)
	rows.add_child(row)
	var label := _label(option.name, Vector2.ZERO, Vector2(258, 25), 20, Color8(248, 248, 248), row)
	var on := CampaignModService.group_enabled(_session.state.active_mods, group)
	var status := CampaignModService.change_status(_session.state, group, not on)
	var caption := "One-way once enabled" if group == "nuzlocke" else "Reset added talents to switch off" if group == "restored_moves" and not status.ok and status.code == "mod_talents_owned" else "Switch on or off"
	var rule := _label(caption, Vector2(1, 26), Vector2(272, 19), 12, Color8(185, 192, 207), row)
	var toggle := SourceMenuArt.button(row, "menus_settings_onButton" if on else "menus_settings_offButton", Vector2(288, 6), _toggle.bind(group))
	if toggle != null:
		toggle.name = "SavedModToggle_%s" % group
		toggle.disabled = not bool(status.ok)
		toggle.modulate.a = 0.45 if toggle.disabled else 1.0
		toggle.tooltip_text = CampaignModService.change_rule(group) if status.ok else String(status.message)
		toggle.mouse_entered.connect(_describe.bind(group))
		_toggles[group] = toggle
	for target in [row, label, rule]:
		target.mouse_filter = Control.MOUSE_FILTER_PASS
		target.mouse_entered.connect(_describe.bind(group))

func _open_category(index: int) -> void:
	_category = index
	_selected_group = ""
	_message = ""
	_build()

func _describe(group: String) -> void:
	_selected_group = group
	var option: Dictionary = CampaignModService.OPTIONS[CampaignModService.option_index(group)]
	_description.text = "%s\n%s" % [option.description, CampaignModService.change_rule(group)]

func _toggle(group: String) -> void:
	var value := not CampaignModService.group_enabled(_session.state.active_mods, group)
	var result := _session.set_mod_option(group, value)
	var option: Dictionary = CampaignModService.OPTIONS[CampaignModService.option_index(group)]
	_message = "%s %s · saved" % [option.name, "enabled" if value else "disabled"] if result.ok else String(result.get("message", "Could not save mod change."))
	_selected_group = group
	_build()

func _label(value: String, at: Vector2, dimensions: Vector2, font_size: int, color: Color = Color(0.96, 0.96, 0.96), parent: Control = null) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.position = at
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.text = value
	label.size = dimensions
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(parent if parent != null else _panel).add_child(label)
	return label
