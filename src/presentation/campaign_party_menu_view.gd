class_name CampaignPartyMenuView
extends Control

signal closed
signal storage_requested
signal talents_requested(member_id: StringName)
signal gems_requested(member_id: StringName, socket: int)

const FONT := preload("res://content/base/fonts/BurbinCasual.ttf")
const SOURCE_VIEWPORT_SIZE := Vector2(700.0, 525.0)
const SOURCE_PANEL_POSITION := Vector2(168.0, 77.0)
const SOURCE_PANEL_SIZE := Vector2(359.0, 415.0)
# TopDownMenuScreen starts this panel at 0.9 scale, then expands around
# its bounds center (including the close button at y=-22). Its settled
# bitmap origin is not the authored, pre-animation x/y.
const SOURCE_SETTLED_PANEL_POSITION := SOURCE_PANEL_POSITION - Vector2(179.5, 196.5) * 0.1
# The roster has its own center expansion inside the panel. Copying (39,45)
# verbatim without that nested transform pushed 323px cards beyond a 359px
# panel, and put the details card over the XP strip at y=92.
const SOURCE_ROSTER_INSET := Vector2(18, 21)
const STAT_KEYS := ["health", "energy", "attack", "healing", "speed"]
const STAT_ART := ["health", "armor", "attack", "armorPenetration", "speed"]
var _session: Variant
var _row_builder: Callable
var _selected := -1
var _showing_details := false
var _tab := 0
var _move_page := 0
var _detail: Control
var _source_root: Control
var _tooltip: BattleMoveTooltip
var _rename_entry: LineEdit
var _transitioning := false

func configure(session, row_builder: Callable) -> void:
	_session = session
	_row_builder = row_builder
	_render()

func _process(_delta: float) -> void:
	if is_instance_valid(_tooltip) and _tooltip.visible:
		_tooltip.follow_mouse(get_local_mouse_position(), get_viewport_rect().size)

func _render() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var viewport_size := get_viewport_rect().size
	var scale_factor := minf(viewport_size.x / SOURCE_VIEWPORT_SIZE.x, viewport_size.y / SOURCE_VIEWPORT_SIZE.y)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.65)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	_source_root = Control.new()
	_source_root.position = (viewport_size - SOURCE_VIEWPORT_SIZE * scale_factor) * 0.5
	_source_root.size = SOURCE_VIEWPORT_SIZE
	_source_root.scale = Vector2.ONE * scale_factor
	set_meta("source_transition_center", _source_root.position + (SOURCE_SETTLED_PANEL_POSITION + Vector2(179.5, 196.5)) * scale_factor)
	add_child(_source_root)
	SourceMenuArt.image(_source_root, "menus_backgroundMedium", SOURCE_SETTLED_PANEL_POSITION)
	_tooltip = BattleMoveTooltip.new()
	_tooltip.z_index = 50
	add_child(_tooltip)
	if not _showing_details:
		for index in _session.state.party.size():
			var host := Control.new()
			host.name = "RosterRow%d" % index
			host.position = SOURCE_SETTLED_PANEL_POSITION + SOURCE_ROSTER_INSET + Vector2(0, index * 75)
			_source_root.add_child(host)
			_row_builder.call(host, _session.state.party[index], _select.bind(index))
			if _selected >= 0:
				_hide_row_reminders(host)
			if _selected >= 0 and index != _selected:
				create_tween().tween_property(host, "modulate:a", 0.3, 0.3)
		if _selected < 0 and not _session.state.owned_gems.is_empty() and not bool(_session.state.progression.get("gem_tutorial_seen", false)):
			SourceMenuArt.image(_source_root, "tutorial_choosingAMinionBar", SOURCE_SETTLED_PANEL_POSITION + Vector2(382, 58))
			var hint := _text(_source_root, "Choose a minion to add your gem to", SOURCE_SETTLED_PANEL_POSITION + Vector2(448, 161), Vector2(90, 150), 20)
			hint.name = "GemTutorialHint"
			hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		SourceMenuArt.button(_source_root, "menus_exitButton", SOURCE_SETTLED_PANEL_POSITION + Vector2(296, -22), func() -> void: closed.emit())
		if _selected >= 0:
			_build_options_popup(_session.state.party[_selected] as OwnedMinionState)
		return
	var owned := _session.state.party[_selected] as OwnedMinionState
	_detail = Control.new()
	_detail.position = SOURCE_SETTLED_PANEL_POSITION
	_detail.size = SOURCE_PANEL_SIZE
	_source_root.add_child(_detail)
	var row := Control.new()
	row.name = "OverviewRow"
	row.position = SOURCE_ROSTER_INSET
	_detail.add_child(row)
	# On the source details screen the overview row is presentation, not another
	# roster-selection target. Its only interactive element is the rename button.
	_row_builder.call(row, owned, Callable(self, "_ignore_row_click"))
	_build_rename_controls(owned)
	SourceMenuArt.image(_detail, "menus_minionXP_background", Vector2(18, 92))
	_bar(_detail, "menus_minionXP_fill", Vector2(54, 99), clampf(float(owned.experience - owned.level * 1000) / 1000.0, 0, 1))
	_refresh_detail_page()
	if _gem_guidance_needed():
		_add_reminder(_detail, "tutorial_firstGemMenuPopup", Vector2(256, 62))
	for index in 3:
		var hit := Button.new()
		hit.position = Vector2(23 + index * 106, 120)
		hit.size = Vector2(105, 32)
		hit.flat = true
		hit.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		hit.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
		hit.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
		hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		hit.pressed.connect(_choose_tab.bind(index))
		_detail.add_child(hit)
	SourceMenuArt.button(_detail, "menus_returnButton", Vector2(2, 356), _return_to_overview)
	SourceMenuArt.button(_detail, "menus_exitButton", Vector2(296, -22), func() -> void: closed.emit())
	_build_minion_compare_arrows()
	_hide_row_reminders(row)

func _refresh_detail_page() -> void:
	var previous := _detail.get_node_or_null("DetailPage")
	if previous != null:
		_detail.remove_child(previous)
		previous.queue_free()
	_tooltip.hide()
	var owned := _session.state.party[_selected] as OwnedMinionState
	var definition := _session.catalog.get_definition(owned.definition_id) as MinionDefinition
	var page := Control.new()
	page.name = "DetailPage"
	page.position = Vector2(15, 113)
	_detail.add_child(page)
	SourceMenuArt.image(page, ["menus_statsBackground", "menus_movesBackground", "menus_gemsBackground"][_tab], Vector2.ZERO)
	match _tab:
		0: _stats(page, owned, definition)
		1: _moves(page, owned)
		2: _gems(page, owned, definition)

func _gem_guidance_needed() -> bool:
	return not _session.state.owned_gems.is_empty() and not bool(_session.state.progression.get("gem_tutorial_seen", false))

func _add_reminder(parent: Control, symbol: String, at: Vector2) -> void:
	var reminder := preload("res://src/presentation/source_tutorial_popup.gd").new()
	reminder.position = at
	parent.add_child(reminder)
	reminder.configure(symbol)

func _hide_row_reminders(host: Control) -> void:
	for reminder in host.find_children("*", "TextureRect", true, false):
		if reminder.get_script() == preload("res://src/presentation/source_tutorial_popup.gd"):
			reminder.hide()

func _build_minion_compare_arrows() -> void:
	var count: int = _session.state.party.size()
	if count < 2:
		return
	var wraps: bool = count >= 5
	if wraps or _selected > 0:
		var up := SourceMenuArt.button(_detail, "menus_compare_arrow", Vector2(171, -22), _navigate_party.bind(-1))
		if up != null:
			up.tooltip_text = "Previous minion"
	if wraps or _selected < count - 1:
		var down := SourceMenuArt.button(_detail, "menus_compare_arrow", Vector2(171, 439), _navigate_party.bind(1))
		if down != null:
			down.position.x += down.size.x
			down.rotation_degrees = 180.0
			down.tooltip_text = "Next minion"

func _navigate_party(direction: int) -> void:
	if _transitioning:
		return
	if _session == null or _session.state.party.is_empty():
		return
	var count: int = _session.state.party.size()
	if count >= 5:
		_selected = posmod(_selected + direction, count)
	else:
		_selected = clampi(_selected + direction, 0, count - 1)
	_move_page = 0
	_render()

func _build_rename_controls(owned: OwnedMinionState) -> void:
	var rename := SourceMenuArt.button(_detail, "menus_minionInfo_renameButton", SOURCE_ROSTER_INSET + Vector2(257, 6), func() -> void: _begin_rename(owned))
	if rename != null:
		rename.name = "RenameButton"
		rename.tooltip_text = "Rename this minion"

func _begin_rename(owned: OwnedMinionState) -> void:
	if is_instance_valid(_rename_entry):
		_rename_entry.queue_free()
	_rename_entry = LineEdit.new()
	_rename_entry.name = "RenameEntry"
	_rename_entry.position = SOURCE_ROSTER_INSET + Vector2(72, -1)
	_rename_entry.size = Vector2(180, 32)
	_rename_entry.max_length = 16
	var definition := _session.catalog.get_definition(owned.definition_id) as MinionDefinition
	_rename_entry.text = owned.nickname if not owned.nickname.is_empty() else definition.display_name if definition != null else String(owned.definition_id)
	_rename_entry.add_theme_font_override("font", FONT)
	_rename_entry.add_theme_font_size_override("font_size", 18)
	_rename_entry.add_theme_color_override("font_color", Color.hex(0x101418ff))
	var input_style := StyleBoxFlat.new()
	input_style.bg_color = Color.hex(0xdcdcdcff)
	input_style.border_color = Color.BLACK
	input_style.set_border_width_all(1)
	input_style.content_margin_left = 4.0
	input_style.content_margin_right = 4.0
	_rename_entry.add_theme_stylebox_override("normal", input_style)
	_rename_entry.add_theme_stylebox_override("focus", input_style)
	_rename_entry.text_submitted.connect(_commit_rename.bind(owned))
	_detail.add_child(_rename_entry)
	_rename_entry.grab_focus()
	_rename_entry.select_all()
	var name_label := _detail.get_node_or_null("OverviewRow/SourceMinionOverview/SourceMinionName") as Label
	if name_label != null:
		name_label.hide()
	var rename_button := _detail.get_node_or_null("RenameButton") as TextureButton
	if rename_button != null:
		rename_button.hide()
	var done := SourceMenuArt.button(_detail, "menus_minionInfo_doneButton", SOURCE_ROSTER_INSET + Vector2(257, 6), func() -> void: _commit_rename(_rename_entry.text, owned))
	if done != null:
		done.name = "RenameDoneButton"
		done.tooltip_text = "Save minion name"

func _commit_rename(value: String, owned: OwnedMinionState) -> void:
	var resolved := value.strip_edges()
	if resolved.is_empty():
		resolved = owned.nickname
	var rename_result: Dictionary = _session.rename_minion(owned.instance_id, resolved.left(16))
	if not rename_result.get("ok", false):
		if is_instance_valid(_rename_entry):
			_rename_entry.tooltip_text = String(rename_result.get("message", "Could not rename this minion"))
			_rename_entry.grab_focus()
		return
	if is_instance_valid(_rename_entry):
		_rename_entry.queue_free()
	_rename_entry = null
	_render()

func _ignore_row_click() -> void:
	pass

func _build_options_popup(owned: OwnedMinionState) -> void:
	var options := Control.new()
	options.name = "SelectionOptions"
	options.position = Vector2(515, 23 + 75 * _selected)
	_source_root.add_child(options)
	var background := SourceMenuArt.image(options, "menus_selectionPopUp_background", Vector2.ZERO)
	options.size = background.texture.get_size() if background != null else Vector2(150, 135)
	options.pivot_offset = options.size * 0.5
	SourceMenuArt.button(options, "menus_selectionPopUp_skillsTreeButton", Vector2(15, 54), func() -> void: talents_requested.emit(owned.instance_id))
	SourceMenuArt.button(options, "menus_selectionPopUp_detailsButton", Vector2(15, 15), _open_details)
	SourceMenuArt.button(options, "menus_selectionPopUp_cancelButton", Vector2(15, 105), _return_to_overview)
	var definition := _session.catalog.get_definition(owned.definition_id) as MinionDefinition
	var points := CampaignProgressionService.available_talent_points(owned, definition)
	if points > 0:
		_add_reminder(options, "tutorial_newTalentPointsPopup_side", Vector2(-92, 48))
	if _gem_guidance_needed():
		_add_reminder(options, "tutorial_firstGem_side", Vector2(-37, 11))
	options.modulate.a = 0.0
	options.scale = Vector2.ONE * 0.9
	var entrance := create_tween().set_parallel(true)
	entrance.tween_property(options, "modulate:a", 1.0, 0.5).set_delay(0.1)
	entrance.tween_property(options, "scale", Vector2.ONE, 0.5).set_delay(0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _stats(page: Control, owned: OwnedMinionState, definition: MinionDefinition) -> void:
	var stats := CampaignProgressionService.owned_display_stats(owned, definition, _session.catalog, _session.state)
	for index in 5:
		var value := int(stats.get(STAT_KEYS[index], 0))
		var label := _text(page, str(value), Vector2(78, 85 + index * 29), Vector2(50, 22), 15)
		label.add_theme_color_override("font_color", Color8(45, 49, 56))
		_bar(page, "menus_statsBars_full_%s" % STAT_ART[index], Vector2(110, 88 + index * 29), float(value) / 300.0, "menus_statsBars_cap_%s" % STAT_ART[index])
		if String(owned.stat_bonus) == STAT_KEYS[index]:
			_text(page, "+5%", Vector2(115 if value > 65 else 270, 85 + index * 29), Vector2(50, 22), 15).add_theme_color_override("font_color", Color8(45, 49, 56))
	for index in mini(2, definition.type_ids.size()):
		var type_name := String(definition.type_ids[index]).get_file()
		SourceMenuArt.image(page, "menus_minionType_%s" % type_name, Vector2(127 + index * 82, 53))

func _moves(page: Control, owned: OwnedMinionState) -> void:
	var moves := CampaignProgressionService.highest_tier_move_ids(owned.learned_move_ids, _session.catalog)
	_move_page = clampi(_move_page, 0, maxi(0, ceili(float(moves.size()) / 4.0) - 1))
	for index in 4:
		var move_index := _move_page * 4 + index
		if move_index >= moves.size():
			break
		var move := _session.catalog.get_definition(moves[move_index]) as MoveDefinition
		if move == null:
			continue
		var icon := SourceMenuArt.image(page, String(move.buff_icon_name), Vector2(20, 44 + index * 51))
		if icon != null:
			icon.scale = Vector2.ONE * 0.75
		var move_name := _text(page, move.display_name, Vector2(62, 50 + index * 51), Vector2(250, 32), 15)
		move_name.autowrap_mode = TextServer.AUTOWRAP_OFF
		move_name.add_theme_color_override("font_color", Color.hex(0xebebebff))
		var button := SourceMenuArt.button(page, "menus_detailsButton", Vector2(228, 50 + index * 51), func() -> void: pass)
		if button != null:
			button.mouse_entered.connect(func() -> void: _tooltip.show_move(move))
			button.mouse_exited.connect(func() -> void: _tooltip.hide())
	if moves.size() > 4:
		var page_count := ceili(float(moves.size()) / 4.0)
		var middle_page := _move_page > 0 and _move_page < page_count - 1
		_build_move_page_button(page, Vector2(242, 247), _move_page > 0, _move_page_change.bind(-1), false, middle_page)
		_build_move_page_button(page, Vector2(318, 248), _move_page < page_count - 1, _move_page_change.bind(1), true, middle_page)

func _build_move_page_button(parent: Control, at: Vector2, enabled: bool, action: Callable, mirror: bool, middle_page: bool) -> void:
	if not enabled or middle_page:
		var under := SourceMenuArt.image(parent, "menus_scrollButton_down", at)
		if under != null and mirror:
			under.scale.x = -1.0
	if not enabled:
		return
	var button := SourceMenuArt.button(parent, "menus_scrollButton_up", at, action)
	if button != null and mirror:
		button.scale.x = -1.0

func _gems(page: Control, owned: OwnedMinionState, definition: MinionDefinition) -> void:
	preload("res://src/presentation/source_minion_gem_panel.gd").build(page, _source_root, owned, definition, _session.state, Callable(self, "_open_gems"))

func _open_gems(member_id: StringName, socket: int) -> void:
	gems_requested.emit(member_id, socket)

func _bar(parent: Control, symbol: String, at: Vector2, ratio: float, end_cap_symbol: String = "") -> void:
	SourceMenuArt.bar(parent, symbol, at, ratio, end_cap_symbol)

func _text(parent: Control, value: String, at: Vector2, label_size: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = value
	label.position = at + Vector2(2, 2) # Flash TextField content inset.
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	label.size = label_size
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color8(250, 250, 250))
	# Text/font changes can expand a Label before wrapping is enabled. Restore
	# the authored width afterwards instead of retaining that unwrapped width.
	label.size = label_size
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _select(index: int) -> void:
	if _transitioning:
		return
	_selected = index
	_showing_details = false
	_move_page = 0
	_render()

func _open_details() -> void:
	if _transitioning or _selected < 0:
		return
	var departing_rows: Array[Control] = []
	for index in _session.state.party.size():
		if index == _selected:
			continue
		var host := _source_root.get_node("RosterRow%d" % index) as Control
		_source_root.remove_child(host)
		departing_rows.append(host)
	_tab = 0
	_showing_details = true
	_render()
	for host in departing_rows:
		_source_root.add_child(host)
		var fade := create_tween()
		fade.tween_property(host, "modulate:a", 0.0, 0.3)
		fade.tween_callback(host.queue_free)
	var row := _detail.get_node("OverviewRow") as Control
	row.position.y += 75 * _selected
	create_tween().tween_property(row, "position:y", SOURCE_ROSTER_INSET.y, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var delay := 0.1 if _selected == 0 else 0.5
	for child in _detail.get_children():
		if child is CanvasItem and child != row:
			child.modulate.a = 0.0
			create_tween().tween_property(child, "modulate:a", 1.0, 0.5).set_delay(delay)
	_guard_transition(delay + 0.5)

func _return_to_overview() -> void:
	if _transitioning:
		return
	var selected := _selected
	var had_details := _showing_details
	var departing: Control = _detail if had_details else _source_root.get_node_or_null("SelectionOptions") as Control
	if is_instance_valid(departing):
		departing.get_parent().remove_child(departing)
		if had_details:
			departing.get_node("OverviewRow").hide()
	var delay := 0.5 if had_details and selected > 0 else 0.0
	_selected = -1
	_showing_details = false
	_render()
	if is_instance_valid(departing):
		_source_root.add_child(departing)
		var fade := create_tween()
		fade.tween_property(departing, "modulate:a", 0.0, 0.5)
		fade.tween_callback(departing.queue_free)
	for index in _session.state.party.size():
		var host := _source_root.get_node("RosterRow%d" % index) as Control
		if had_details and index == selected:
			host.position.y = SOURCE_SETTLED_PANEL_POSITION.y + SOURCE_ROSTER_INSET.y
			create_tween().tween_property(host, "position:y", host.position.y + 75 * index, 0.5).set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		elif index != selected:
			host.modulate.a = 0.0 if had_details else 0.3
			create_tween().tween_property(host, "modulate:a", 1.0, 0.3 if had_details else 0.5).set_delay(delay + (0.3 if had_details else 0.0))
	_guard_transition(delay + 0.6)

func _guard_transition(duration: float) -> void:
	_transitioning = true
	var guard := Control.new()
	guard.name = "PartyTransitionInputGuard"
	guard.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	guard.mouse_filter = Control.MOUSE_FILTER_STOP
	guard.z_index = 4095
	add_child(guard)
	var timer := create_tween()
	timer.tween_interval(duration)
	timer.tween_callback(func() -> void:
		_transitioning = false
		guard.queue_free()
	)

func _choose_tab(index: int) -> void:
	if _transitioning:
		return
	_tab = index
	_refresh_detail_page()

func _move_page_change(direction: int) -> void:
	if _transitioning:
		return
	_move_page += direction
	_refresh_detail_page()
