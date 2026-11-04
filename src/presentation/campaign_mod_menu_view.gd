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
	var categories := _categories()
	for index in categories.size():
		var category: Dictionary = categories[index]
		var count := 0
		for group in category.groups:
			if _enabled(String(group)): count += 1
		var button := TypeGuideView.text_button(_panel, "%s\n%d / %d enabled" % [category.name, count, category.groups.size()], Vector2(37, 103 + index * 59), Vector2(190, 53), _open_category.bind(index), 16)
		button.name = "SavedModCategory_%s" % category.id
		button.modulate = Color.WHITE if index == _category else Color(0.78, 0.8, 0.85)
		_category_buttons.append(button)
	_category = clampi(_category, 0, categories.size() - 1)
	var category: Dictionary = categories[_category]
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
	for group in category.groups:
		if String(group).begins_with(PLAYER_PREFIX): _build_player_row(rows, String(group))
		else: _build_row(rows, String(group))
	_description = _label("", Vector2(254, 297), Vector2(389, 108), 13, Color8(223, 226, 235))
	_description.name = "SavedModDescription"
	if category.groups.is_empty():
		_selected_group = ""
		_description.text = category.description
	else:
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

const PLAYER_PREFIX := "player:"

## The built-in categories plus one for player mods installed on this computer.
func _categories() -> Array:
	var categories: Array = CampaignModService.CATEGORIES.duplicate(true)
	var groups: Array = []
	for manifest in UserModRepository.list():
		if not manifest.get("broken", false): groups.append(PLAYER_PREFIX + String(manifest.id))
	# Mods the save uses but that are no longer installed still show.
	for ref in _session.state.user_mods:
		if not PLAYER_PREFIX + String(ref.id) in groups: groups.append(PLAYER_PREFIX + String(ref.id))
	categories.append({"id": "player", "name": "Player Mods", "groups": groups, "description": "No player mods are installed. Make one, or import a share code, in the Mod Workshop on the title screen."})
	return categories

func _enabled(group: String) -> bool:
	if group.begins_with(PLAYER_PREFIX):
		for ref in _session.state.user_mods:
			if String(ref.id) == group.trim_prefix(PLAYER_PREFIX): return true
		return false
	return CampaignModService.group_enabled(_session.state.active_mods, group)

func _build_player_row(rows: VBoxContainer, group: String) -> void:
	var mod_id := group.trim_prefix(PLAYER_PREFIX)
	var loaded := UserModRepository.read(mod_id)
	var row := Control.new()
	row.custom_minimum_size = Vector2(373, 42)
	rows.add_child(row)
	var label := _label(String(loaded.manifest.name) if loaded.ok else mod_id, Vector2.ZERO, Vector2(258, 25), 20, Color8(248, 248, 248), row)
	var on := _enabled(group)
	var blockers := UserModService.removal_blockers(_session.state, mod_id) if on else PackedStringArray()
	var caption := "Not installed" if not loaded.ok else "Owned content keeps it on" if not blockers.is_empty() else "Player mod · v%s" % loaded.manifest.get("version", "1")
	var rule := _label(caption, Vector2(1, 26), Vector2(272, 19), 12, Color8(185, 192, 207), row)
	var toggle := SourceMenuArt.button(row, "menus_settings_onButton" if on else "menus_settings_offButton", Vector2(288, 6), _toggle.bind(group))
	if toggle != null:
		toggle.name = "SavedModToggle_%s" % group.replace(":", "_")
		toggle.disabled = (not on and not loaded.ok) or not blockers.is_empty()
		toggle.modulate.a = 0.45 if toggle.disabled else 1.0
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
	if group.begins_with(PLAYER_PREFIX):
		var mod_id := group.trim_prefix(PLAYER_PREFIX)
		var loaded := UserModRepository.read(mod_id)
		var blockers := UserModService.removal_blockers(_session.state, mod_id) if _enabled(group) else PackedStringArray()
		if not loaded.ok:
			_description.text = "This save used %s, which is no longer installed." % mod_id
		else:
			var rule := ("Release or reset its content to switch off: %s." % "; ".join(blockers)) if not blockers.is_empty() else "Switch on any time; switch off while nothing you own comes from it."
			_description.text = "%s\nBy %s. %s" % [String(loaded.manifest.get("description", "")).left(220), loaded.manifest.get("author", "unknown"), rule]
		return
	var option: Dictionary = CampaignModService.OPTIONS[CampaignModService.option_index(group)]
	_description.text = "%s\n%s" % [option.description, CampaignModService.change_rule(group)]

func _toggle(group: String) -> void:
	if group.begins_with(PLAYER_PREFIX):
		var mod_id := group.trim_prefix(PLAYER_PREFIX)
		var value := not _enabled(group)
		var changed := _session.set_user_mod(mod_id, value)
		_message = "%s %s · saved" % [mod_id, "enabled" if value else "disabled"] if changed.ok else String(changed.get("message", "Could not save mod change.")).left(120)
		_selected_group = group
		_build()
		return
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
