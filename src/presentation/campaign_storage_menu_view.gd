class_name CampaignStorageMenuView
extends Control

signal closed
signal details_requested(member_id: StringName)
signal gems_requested(member_id: StringName, socket: int)

const FONT: Font = preload("res://content/base/fonts/BurbinCasual.ttf")
const GRID_COLUMNS := 5
const GRID_ROWS := 4
const SLOTS_PER_BOX := GRID_COLUMNS * GRID_ROWS
const MAX_BOXES := 10
const SOURCE_MENU_SIZE := Vector2(667.0, 480.0)
const SOURCE_SCREEN_SIZE := Vector2(700.0, 525.0)
const STAT_NAMES := ["health", "energy", "attack", "healing", "speed"]
const STAT_ART := ["health", "armor", "attack", "armorPenetration", "speed"]

var _session: Variant
var _row_builder: Callable
var _menu: Control
var _box_page := 0
var _selected_id: StringName = &""
var _swap_mode := false
var _swap_first_id: StringName = &""
var _detail_tab := 0
var _move_page := 0
var _confirm_release_id: StringName = &""
var _party_slot_picker_id: StringName = &""
var _tooltip: BattleMoveTooltip
var _swap_animating := false

func configure(session, row_builder: Callable) -> void:
	_session = session
	_row_builder = row_builder
	if is_inside_tree():
		_render()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	focus_mode = Control.FOCUS_ALL
	grab_focus()
	if _session != null:
		_render()

func _process(_delta: float) -> void:
	if is_instance_valid(_tooltip) and _tooltip.visible:
		_tooltip.follow_mouse(get_local_mouse_position(), get_viewport_rect().size)

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
		# Rebuilding or closing the view would retire the live swap tween's targets.
		if _swap_animating:
			get_viewport().set_input_as_handled()
			return
		if not _confirm_release_id.is_empty():
			_confirm_release_id = &""
		elif not _party_slot_picker_id.is_empty():
			_party_slot_picker_id = &""
		else:
			closed.emit()
		_render()
		get_viewport().set_input_as_handled()

func _render() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	if _session == null or _session.state == null or _session.catalog == null:
		return
	var viewport_size := get_viewport_rect().size
	var scale_factor := minf(viewport_size.x / SOURCE_SCREEN_SIZE.x, viewport_size.y / SOURCE_SCREEN_SIZE.y)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.0, 0.0, 0.0, 0.34)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	_menu = Control.new()
	# The original storage menu fades at stage origin, not at panel center.
	_menu.position = (viewport_size - SOURCE_SCREEN_SIZE * scale_factor) * 0.5
	_menu.size = SOURCE_MENU_SIZE
	_menu.scale = Vector2.ONE * scale_factor
	add_child(_menu)
	SourceMenuArt.image(_menu, "menus_backgroundLarge", Vector2.ZERO)
	SourceMenuArt.image(_menu, "menus_minionStorage_minionsBackground", Vector2(15.0, 54.0))
	SourceMenuArt.image(_menu, "menus_minionStorage_boxSelectBar", Vector2(60.0, 21.0))
	var selected_tab := SourceMenuArt.image(_menu, "menus_minionStorage_boxSelectedIcon", Vector2(45.0 + float(_box_page) * 56.2, 9.0))
	if selected_tab != null:
		selected_tab.z_index = 2
	_build_tabs()
	_build_grid()
	_build_detail_panel()
	_build_footer()
	_build_release_confirmation()
	_build_party_slot_picker()
	_tooltip = BattleMoveTooltip.new()
	_tooltip.z_index = 80
	add_child(_tooltip)

func _build_tabs() -> void:
	var page_count := MAX_BOXES
	_box_page = clampi(_box_page, 0, page_count - 1)
	for index in MAX_BOXES:
		var hit := Button.new()
		hit.name = "StorageBoxTab%d" % (index + 1)
		hit.position = Vector2(61.0 + float(index) * 56.2, 22.0)
		hit.size = Vector2(56.2, 29.0)
		hit.flat = true
		hit.focus_mode = Control.FOCUS_NONE
		hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		hit.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		hit.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
		hit.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
		# Transparent hit targets must stay visible in Godot to receive clicks.
		hit.z_index = 4
		hit.pressed.connect(_change_box.bind(index))
		_menu.add_child(hit)
	var arrow := SourceMenuArt.texture("menus_minionStorage_nextContainerButton")
	if arrow != null:
		var previous := _texture_button(arrow, Vector2(55.0, 22.0), Callable(self, "_turn_box").bind(-1))
		previous.scale = Vector2(-1.0, 1.0)
		previous.disabled = false
		_menu.add_child(previous)
		var next := _texture_button(arrow, Vector2(635.0, 22.0), Callable(self, "_turn_box").bind(1))
		next.disabled = false
		_menu.add_child(next)

func _build_grid() -> void:
	var combined: Array = []
	for owned in _session.state.party:
		combined.append({"owned": owned, "party_index": combined.size(), "storage_index": -1})
	for storage_index in _session.state.storage.size():
		combined.append({"owned": _session.state.storage[storage_index], "party_index": -1, "storage_index": storage_index})
	var selection_texture := SourceMenuArt.texture("menus_minionStorage_minionSelectIcon")
	for slot in SLOTS_PER_BOX:
		var column := slot % GRID_COLUMNS
		var row := floori(float(slot) / float(GRID_COLUMNS))
		var center := Vector2(15.0 + 44.0 + column * 65.0, 54.0 + 78.0 + row * 78.0)
		var global_index := _box_page * SLOTS_PER_BOX + slot
		if global_index >= combined.size():
			continue
		var entry: Dictionary = combined[global_index]
		var owned := entry.owned as OwnedMinionState
		var presentation := _presentation_for(owned)
		var icon_texture := _minion_texture(presentation)
		if icon_texture == null:
			continue
		var host := Control.new()
		host.name = "StorageMinion%d" % slot
		host.set_meta("member_id", owned.instance_id)
		host.set_meta("baseline", center)
		# Source buttons use the battle bitmap at 0.4 scale, centered on
		# the column with its bottom edge at the authored row baseline.
		host.size = icon_texture.get_size() * 0.4
		host.position = center - Vector2(host.size.x * 0.5, host.size.y)
		host.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_menu.add_child(host)
		var icon := Sprite2D.new()
		icon.name = "SourceStoragePortrait"
		icon.texture = icon_texture
		icon.centered = false
		icon.scale = Vector2.ONE * 0.4
		host.add_child(icon)
		if StringName(owned.instance_id) == _selected_id or StringName(owned.instance_id) == _swap_first_id:
			if selection_texture != null:
				var selected := TextureRect.new()
				selected.texture = selection_texture
				selected.position = center - Vector2(28.0, 11.0)
				selected.size = selection_texture.get_size()
				selected.mouse_filter = Control.MOUSE_FILTER_IGNORE
				selected.z_index = 1
				_menu.add_child(selected)
		var hit := Button.new()
		hit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		hit.flat = true
		hit.focus_mode = Control.FOCUS_NONE
		hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for style in ["normal", "hover", "pressed", "focus"]:
			hit.add_theme_stylebox_override(style, StyleBoxEmpty.new())
		hit.pressed.connect(_slot_pressed.bind(owned.instance_id))
		host.add_child(hit)
	if _box_page == 0:
		var team_marker := SourceMenuArt.image(_menu, "menus_minionStorage_currTeamIndecator", Vector2(22.0, 66.0))
		if team_marker != null:
			team_marker.z_index = 3

func _build_detail_panel() -> void:
	var owned := _find_owned(_selected_id)
	if owned == null or _swap_mode:
		return
	var details := Control.new()
	details.name = "StorageDetails"
	details.position = Vector2(330.0, 43.0)
	details.size = Vector2(330.0, 390.0)
	_menu.add_child(details)
	var overview := Control.new()
	overview.position = Vector2(18.0, 16.0)
	details.add_child(overview)
	if _row_builder.is_valid():
		_row_builder.call(overview, owned, func() -> void: details_requested.emit(owned.instance_id))
	var xp_bg := SourceMenuArt.image(details, "menus_minionXP_background", Vector2(18.0, 92.0))
	if xp_bg != null:
		var progress := clampf(float(owned.experience - owned.level * 1000) / 1000.0, 0.0, 1.0)
		_add_source_bar(details, "menus_minionXP_fill", Vector2(54.0, 99.0), progress)
	for index in 3:
		var tab_hit := Button.new()
		tab_hit.position = Vector2(23.0 + index * 106.0, 120.0)
		tab_hit.size = Vector2(105.0, 32.0)
		tab_hit.flat = true
		tab_hit.disabled = index == _detail_tab
		tab_hit.focus_mode = Control.FOCUS_NONE
		for style in ["normal", "hover", "pressed", "focus"]:
			tab_hit.add_theme_stylebox_override(style, StyleBoxEmpty.new())
		tab_hit.pressed.connect(_change_detail_tab.bind(index))
		details.add_child(tab_hit)
	var definition := _session.catalog.get_definition(owned.definition_id) as MinionDefinition
	var page := Control.new()
	page.position = Vector2(15.0, 113.0)
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	details.add_child(page)
	SourceMenuArt.image(page, ["menus_statsBackground", "menus_movesBackground", "menus_gemsBackground"][_detail_tab], Vector2.ZERO)
	match _detail_tab:
		0: _build_stats(page, owned, definition)
		1: _build_moves(page, owned)
		2: _build_gems(page, owned, definition)
	if _is_storage_owned(owned.instance_id):
		var add := SourceMenuArt.button(details, "menus_minionStorage_addToPartyButton", Vector2(266.0, 354.0), Callable(self, "_add_to_party").bind(owned.instance_id))
		if add != null:
			add.tooltip_text = "Choose a party member to replace" if _session.state.party.size() >= 5 else "Add to party"

func _build_stats(page: Control, owned: OwnedMinionState, definition: MinionDefinition) -> void:
	if definition == null:
		return
	var stats := CampaignProgressionService.owned_display_stats(owned, definition, _session.catalog, _session.state)
	for index in STAT_NAMES.size():
		var value := int(stats.get(STAT_NAMES[index], 0))
		var label := _label(page, str(value), Vector2(78.0, 85.0 + index * 29.0), Vector2(50.0, 22.0), 15, Color8(45, 49, 56))
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_add_source_bar(page, "menus_statsBars_full_%s" % STAT_ART[index], Vector2(110.0, 88.0 + index * 29.0), float(value) / 300.0)
		if String(owned.stat_bonus) == STAT_NAMES[index]:
			_label(page, "+5%", Vector2(115.0 if value > 65 else 270.0, 85.0 + index * 29.0), Vector2(55.0, 22.0), 15, Color8(45, 49, 56))
	for index in mini(2, definition.type_ids.size()):
		var type_name := String(definition.type_ids[index]).get_file()
		SourceMenuArt.image(page, "menus_minionType_%s" % type_name, Vector2(127.0 + index * 82.0, 53.0))

func _build_moves(page: Control, owned: OwnedMinionState) -> void:
	var moves := CampaignProgressionService.highest_tier_move_ids(owned.learned_move_ids, _session.catalog)
	var page_count := maxi(1, ceili(float(moves.size()) / 4.0))
	_move_page = clampi(_move_page, 0, page_count - 1)
	for index in 4:
		var move_index := _move_page * 4 + index
		if move_index >= moves.size():
			break
		var move := _session.catalog.get_definition(moves[move_index]) as MoveDefinition
		if move == null:
			continue
		var icon := SourceMenuArt.image(page, String(move.buff_icon_name), Vector2(20.0, 44.0 + index * 51.0))
		if icon != null:
			icon.scale = Vector2.ONE * 0.75
		var move_name := _label(page, move.display_name, Vector2(62.0, 50.0 + index * 51.0), Vector2(250.0, 32.0), 15, Color8(235, 235, 235))
		move_name.autowrap_mode = TextServer.AUTOWRAP_OFF
		var detail := SourceMenuArt.button(page, "menus_detailsButton", Vector2(228.0, 50.0 + index * 51.0), func() -> void: _tooltip.show_move(move))
		if detail != null:
			detail.mouse_entered.connect(func() -> void: _tooltip.show_move(move))
			detail.mouse_exited.connect(func() -> void: _tooltip.hide())
	# The source hides both arrows for a single page and shows the authored
	# down-state bitmap, not a disabled up-state button, at a paging boundary.
	if page_count > 1:
		var middle_page := _move_page > 0 and _move_page < page_count - 1
		_build_move_page_button(page, Vector2(242.0, 247.0), _move_page > 0, -1, false, middle_page)
		_build_move_page_button(page, Vector2(318.0, 248.0), _move_page < page_count - 1, 1, true, middle_page)

func _build_move_page_button(parent: Control, at: Vector2, enabled: bool, direction: int, mirror: bool, middle_page: bool) -> void:
	if not enabled or middle_page:
		var under := SourceMenuArt.image(parent, "menus_scrollButton_down", at)
		if under != null and mirror:
			under.scale.x = -1.0
	if enabled:
		var button := SourceMenuArt.button(parent, "menus_scrollButton_up", at, Callable(self, "_move_page_step").bind(direction))
		if button != null and mirror:
			button.scale.x = -1.0

func _build_gems(page: Control, owned: OwnedMinionState, definition: MinionDefinition) -> void:
	preload("res://src/presentation/source_minion_gem_panel.gd").build(page, _menu, owned, definition, _session.state, Callable(self, "_request_gems"))

func _build_footer() -> void:
	SourceMenuArt.button(_menu, "menus_returnButton", Vector2(3.0, 409.0), func() -> void: closed.emit())
	var release := SourceMenuArt.button(_menu, "menus_minionStorage_releaseButton", Vector2(580.0, 412.0), Callable(self, "_ask_release"))
	if release != null:
		release.visible = not _selected_id.is_empty() and not _swap_mode
		if not _selected_id.is_empty() and _session.state.party.size() <= 1 and _is_party_owned(_selected_id):
			release.disabled = true
			release.modulate.a = 0.45
	var swap := SourceMenuArt.button(_menu, "menus_minionStorage_swapButtonOn" if _swap_mode else "menus_minionStorage_swapButtonOff", Vector2(269.0, 398.0), Callable(self, "_toggle_swap"))
	if swap != null:
		swap.tooltip_text = "Turn swap mode off" if _swap_mode else "Turn swap mode on"

func _build_release_confirmation() -> void:
	if _confirm_release_id.is_empty():
		return
	var popup := Control.new()
	popup.position = Vector2(485.0, 327.0)
	_menu.add_child(popup)
	SourceMenuArt.image(popup, "conformationBox_background", Vector2.ZERO)
	_label(popup, "This will delete your minion", Vector2(7.0, 11.0), Vector2(200.0, 34.0), 16, Color8(249, 240, 217)).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	SourceMenuArt.button(popup, "conformationBox_yesButton", Vector2(5.0, 42.0), Callable(self, "_release_confirmed"))
	SourceMenuArt.button(popup, "conformationBox_noButton", Vector2(105.0, 42.0), Callable(self, "_cancel_release"))

func _build_party_slot_picker() -> void:
	if _party_slot_picker_id.is_empty():
		return
	var overlay := Control.new()
	overlay.name = "StoragePartyReplacement"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = 30
	_menu.add_child(overlay)
	var shade := ColorRect.new()
	shade.size = SOURCE_SCREEN_SIZE
	shade.color = Color(0, 0, 0, 0.65)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(shade)
	SourceMenuArt.image(overlay, "menus_backgroundMedium", Vector2(168, 57))
	SourceMenuArt.image(overlay, "tutorial_choosingAMinionBar", Vector2(523, 103))
	var hint := _label(overlay, "Choose a minion to swap", Vector2(587, 220), Vector2(90, 140), 20, Color8(250, 250, 250))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.size = Vector2(90, 140)
	for index in _session.state.party.size():
		var owned := _session.state.party[index] as OwnedMinionState
		var host := Control.new()
		host.position = Vector2(186.0, 77.0 + index * 75.0)
		host.size = Vector2(323.0, 76.0)
		overlay.add_child(host)
		if _row_builder.is_valid():
			_row_builder.call(host, owned, Callable(self, "_replace_party_slot").bind(index))
	SourceMenuArt.button(overlay, "menus_exitButton", Vector2(464, 35), Callable(self, "_cancel_party_slot_picker"))

func _ask_release() -> void:
	if _selected_id.is_empty() or (_session.state.party.size() <= 1 and _is_party_owned(_selected_id)):
		return
	_confirm_release_id = _selected_id
	_render()

func _release_confirmed() -> void:
	if _confirm_release_id.is_empty():
		return
	var id := _confirm_release_id
	_confirm_release_id = &""
	var result: Dictionary
	if _session.has_method("release_storage_minion"):
		result = _session.release_storage_minion(id)
	elif _session.has_method("release_minion"):
		result = _session.release_minion(id)
	else:
		result = {"ok": false, "error": "release_unavailable"}
	if bool(result.get("ok", false)):
		_selected_id = &""
		_swap_first_id = &""
	_render()

func _add_to_party(id: StringName) -> void:
	if not _is_storage_owned(id):
		return
	if _session.state.party.size() < 5:
		if _session.has_method("select_storage_minion"):
			var result: Dictionary = _session.select_storage_minion(id)
			if bool(result.get("ok", false)):
				_selected_id = id
				_render()
		return
	_party_slot_picker_id = id
	_render()

func _replace_party_slot(party_index: int) -> void:
	if _party_slot_picker_id.is_empty():
		return
	var id := _party_slot_picker_id
	_party_slot_picker_id = &""
	var result: Dictionary
	if _session.has_method("select_storage_minion"):
		result = _session.select_storage_minion(id, party_index)
	else:
		result = _session.swap_party_with_storage(party_index, _storage_index(id))
	if bool(result.get("ok", false)):
		_selected_id = id
		_swap_first_id = &""
	_render()

func _slot_pressed(id: StringName) -> void:
	if _swap_animating:
		return
	if _swap_mode:
		if _swap_first_id.is_empty():
			_swap_first_id = id
			_render()
			return
		if id == _swap_first_id:
			_swap_first_id = &""
			_render()
			return
		_swap_selected_pair(_swap_first_id, id)
		return
	_selected_id = &"" if _selected_id == id else id
	_move_page = 0
	details_requested.emit(id)
	_render()

func _swap_selected_pair(first_id: StringName, second_id: StringName) -> void:
	var first_party := _party_index(first_id)
	var second_party := _party_index(second_id)
	var result := {"ok": false}
	if first_party >= 0 and second_party < 0:
		result = _session.swap_party_with_storage(first_party, _storage_index(second_id))
	elif second_party >= 0 and first_party < 0:
		result = _session.swap_party_with_storage(second_party, _storage_index(first_id))
	elif first_party < 0 and second_party < 0 and _session.has_method("swap_storage_minions"):
		result = _session.swap_storage_minions(first_id, second_id)
	elif first_party >= 0 and second_party >= 0:
		result = _session.swap_party_minions(first_id, second_id)
	if bool(result.get("ok", false)):
		var first_host: Control
		var second_host: Control
		for child in _menu.get_children():
			if child is Control and child.has_meta("member_id"):
				if StringName(child.get_meta("member_id")) == first_id:
					first_host = child
				elif StringName(child.get_meta("member_id")) == second_id:
					second_host = child
		if first_host != null and second_host != null:
			_swap_animating = true
			var guard := Control.new()
			guard.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			guard.mouse_filter = Control.MOUSE_FILTER_STOP
			guard.z_index = 4095
			add_child(guard)
			var first_baseline: Vector2 = first_host.get_meta("baseline")
			var second_baseline: Vector2 = second_host.get_meta("baseline")
			var tween := create_tween().set_parallel(true)
			tween.tween_property(first_host, "position", second_baseline - Vector2(first_host.size.x * 0.5, first_host.size.y), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tween.tween_property(second_host, "position", first_baseline - Vector2(second_host.size.x * 0.5, second_host.size.y), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			await tween.finished
			_swap_animating = false
		_selected_id = &""
	_swap_first_id = &""
	_render()

func _toggle_swap() -> void:
	if _swap_animating:
		return
	_swap_mode = not _swap_mode
	# Source uses one selection for both modes, including across box pages.
	if _swap_mode:
		_swap_first_id = _selected_id
		_selected_id = &""
	else:
		_selected_id = _swap_first_id
		_swap_first_id = &""
	_render()

func _change_box(index: int) -> void:
	if _swap_animating:
		return
	_box_page = index
	_render()

func _turn_box(direction: int) -> void:
	_change_box(posmod(_box_page + direction, MAX_BOXES))

func _change_detail_tab(index: int) -> void:
	_detail_tab = index
	_move_page = 0
	_render()

func _request_gems(member_id: StringName, socket: int) -> void:
	gems_requested.emit(member_id, socket)

func _move_page_step(step: int) -> void:
	_move_page += step
	_render()

func _cancel_release() -> void:
	_confirm_release_id = &""
	_render()

func _cancel_party_slot_picker() -> void:
	_party_slot_picker_id = &""
	_render()

func _presentation_for(owned: OwnedMinionState) -> MinionPresentationDefinition:
	var definition := _session.catalog.get_definition(owned.definition_id) as MinionDefinition
	return _session.catalog.get_definition(definition.presentation_id) as MinionPresentationDefinition if definition != null else null

func _minion_texture(presentation: MinionPresentationDefinition) -> Texture2D:
	if presentation == null or presentation.legacy_sprite_name.is_empty():
		return null
	var path := "res://content/base/art/battle/minions/%s.png" % String(presentation.legacy_sprite_name)
	if not ResourceLoader.exists(path):
		path = "res://content/base/art/battle/%s.png" % String(presentation.legacy_sprite_name)
	return load(path) as Texture2D if ResourceLoader.exists(path) else null

func _find_owned(id: StringName) -> OwnedMinionState:
	if id.is_empty():
		return null
	for owned in _session.state.party + _session.state.storage:
		if owned.instance_id == id:
			return owned as OwnedMinionState
	return null

func _is_party_owned(id: StringName) -> bool:
	return _party_index(id) >= 0

func _is_storage_owned(id: StringName) -> bool:
	return _storage_index(id) >= 0

func _party_index(id: StringName) -> int:
	for index in _session.state.party.size():
		if _session.state.party[index].instance_id == id:
			return index
	return -1

func _storage_index(id: StringName) -> int:
	for index in _session.state.storage.size():
		if _session.state.storage[index].instance_id == id:
			return index
	return -1

func _texture_button(texture: Texture2D, at: Vector2, action: Callable) -> TextureButton:
	var button := TextureButton.new()
	button.texture_normal = texture
	button.texture_hover = texture
	button.texture_pressed = texture
	button.position = at
	button.size = texture.get_size()
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(action)
	return button

func _label(parent: Control, value: String, at: Vector2, label_size: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.position = at + Vector2(2, 2) # Flash TextField content inset.
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	label.size = label_size
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _add_source_bar(parent: Control, symbol: String, at: Vector2, ratio: float) -> void:
	SourceMenuArt.bar(parent, symbol, at, ratio, symbol.replace("_full_", "_cap_") if symbol.contains("_full_") else "")
