class_name ModWorkshopRooms
extends RefCounted

## The Rooms tab. Two views share one tab:
##  - the floor map: the in-game minimap with an arrow per door, your edited
##    rooms marked in gold and rooms that can no longer be reached in red;
##  - a room's blueprint: the real room drawn to scale with its doors,
##    arrival points and interaction zones, next to an inspector.
## Edits are stored as the usual room records; a record is only added to the
## mod once something in the room actually changes.

const LAYOUTS := preload("res://content/base/ui/source_minimap_layouts.tres")
const FLOOR_COUNT := 31
const INTERACTION_NAMES := {"trainer": "Trainer", "egg_pick": "Egg", "unlock_boss_door": "Boss door lock", "unlock_eggery_door": "Hatchery door lock", "gem_shop": "Gem shop", "gem_combiner": "Gem combiner", "minion_storage": "Minion storage", "heal_party": "Healing stone", "map_station": "Map station", "grand_sage": "Grand Sage", "titan_reward": "Titan reward", "titan_guard": "Titan guard", "floor_picker": "Floor picker"}

var host: ModWorkshopView
var _drafts: Dictionary = {}
var _floor_cache: Dictionary = {}
var _blueprint: ModWorkshopRoomBlueprint
var _inspector_scroll: ScrollContainer
var _inspector_box: VBoxContainer
var _current: RoomDefinition
var _arrival_spins: Dictionary = {}
var _door_cards: Dictionary = {}
var _zone_cards: Dictionary = {}
var _picked_kind := ""
var _picked_key: Variant = null
## Undo history of the open room's record, as JSON snapshots.
var _undo: Array[String] = []
var _redo: Array[String] = []
var _last_state := ""
var _last_push_msec := 0
var _history_room := ""
var _undo_button: Button
var _redo_button: Button
var _panel_visible := true
const INSPECTOR_WIDTH := 286.0

func _init(owner: ModWorkshopView) -> void:
	host = owner

# --- Data ---------------------------------------------------------------------------

func rooms_on_floor(floor_index: int) -> Array:
	if not _floor_cache.has(floor_index):
		var rooms: Array = []
		for definition in host.catalog._by_id.values():
			if definition is RoomDefinition and String(definition.id).begins_with("base:room/") and int(definition.minimap_metadata.get("floor_index", -1)) == floor_index: rooms.append(definition)
		rooms.sort_custom(func(a: RoomDefinition, b: RoomDefinition) -> bool:
			var left := int(a.minimap_metadata.get("room_index", 999))
			var right := int(b.minimap_metadata.get("room_index", 999))
			return left < right if left != right else String(a.id) < String(b.id))
		_floor_cache[floor_index] = rooms
	return _floor_cache[floor_index]

func _edit_record(room_id: String) -> Dictionary:
	for record in host._manifest.rooms:
		if String(record.target) == room_id: return record
	return {}

## The record the forms edit: the saved one, or a draft that joins the mod on its first change.
func _working(room: RoomDefinition) -> Dictionary:
	var saved := _edit_record(String(room.id))
	if not saved.is_empty(): return saved
	if not _drafts.has(String(room.id)): _drafts[String(room.id)] = host._room_draft(room)
	return _drafts[String(room.id)]

func _attach(room: RoomDefinition) -> void:
	if not _edit_record(String(room.id)).is_empty(): return
	if _drafts.has(String(room.id)): host._manifest.rooms.append(_drafts[String(room.id)])
	host._changed()

func _floor_of(room_id: String) -> int:
	var room := host.catalog.get_definition(StringName(room_id)) as RoomDefinition
	return int(room.minimap_metadata.get("floor_index", 0)) if room != null else 0

## Where each door of a room leads once this mod's edits are applied.
func effective_exits(room: RoomDefinition) -> Array:
	var record := _edit_record(String(room.id))
	var result: Array = []
	for exit_data in room.exits:
		var target := String(exit_data.get("target_room_id", ""))
		var spawn := String(exit_data.get("target_spawn_id", ""))
		var edited := false
		for edit in record.get("exits", []):
			if int(edit.get("transition_id", -2)) == int(exit_data.get("transition_id", -1)):
				if String(edit.get("target_room_id", target)) != target or String(edit.get("target_spawn_id", spawn)) != spawn: edited = true
				target = String(edit.get("target_room_id", target))
				spawn = String(edit.get("target_spawn_id", spawn))
		result.append({"transition_id": int(exit_data.get("transition_id", -1)), "target": target, "spawn": spawn, "edited": edited})
	return result

## Rooms of the floor that cannot be reached from its entrance any more.
func unreachable(floor_index: int) -> Dictionary:
	var rooms := rooms_on_floor(floor_index)
	var by_id: Dictionary = {}
	var start: RoomDefinition = null
	for room in rooms:
		by_id[String(room.id)] = room
		if int(room.minimap_metadata.get("room_index", -1)) == 0: start = room
	var lost: Dictionary = {}
	if start == null: return lost
	var seen: Dictionary = {String(start.id): true}
	var queue: Array = [start]
	while not queue.is_empty():
		var room: RoomDefinition = queue.pop_front()
		for exit_data in effective_exits(room):
			if by_id.has(exit_data.target) and not seen.has(exit_data.target):
				seen[exit_data.target] = true
				queue.append(by_id[exit_data.target])
	for room in rooms:
		if int(room.minimap_metadata.get("room_index", -1)) >= 0 and not seen.has(String(room.id)): lost[String(room.id)] = true
	return lost

func _room_name(room_id: String) -> String:
	return host._describe("room", room_id)

func _short_name(room_id: String) -> String:
	var name := _room_name(room_id)
	return name.get_slice("—", 1).strip_edges() if name.contains("—") else name

# --- Entry --------------------------------------------------------------------------

func build(content: Control) -> void:
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 5)
	content.add_child(column)
	var room_id := String(host._selection.get("room", ""))
	var room := host.catalog.get_definition(StringName(room_id)) as RoomDefinition if not room_id.is_empty() else null
	if room != null: _room_view(column, room)
	else: _floor_view(column, int(host._selection.get("room_floor", _first_floor())))

func _first_floor() -> int:
	for record in host._manifest.rooms:
		return _floor_of(String(record.target))
	return 0

func open_room(room_id: String) -> void:
	host._selection["room"] = room_id
	host._selection["room_floor"] = _floor_of(room_id)
	_picked_kind = ""
	_picked_key = null
	host._build_editor()

func _back_to_map() -> void:
	host._selection.erase("room")
	host._build_editor()

# --- Floor map ----------------------------------------------------------------------

func _floor_view(column: VBoxContainer, floor_index: int) -> void:
	floor_index = clampi(floor_index, 0, FLOOR_COUNT - 1)
	host._selection["room_floor"] = floor_index
	var rooms := rooms_on_floor(floor_index)
	var edited: Dictionary = {}
	for record in host._manifest.rooms: edited[String(record.target)] = true
	var lost := unreachable(floor_index)
	var exits: Dictionary = {}
	for room in rooms: exits[String(room.id)] = effective_exits(room)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	column.add_child(bar)
	var previous := host._button("< Floor", func() -> void:
		host._selection["room_floor"] = floor_index - 1
		host._selection.erase("map_room")
		host._build_editor(), bar)
	previous.disabled = floor_index <= 0
	var heading := host._label("Floor %d" % (floor_index + 1), 18, ModWorkshopForm.GOLD, bar)
	heading.custom_minimum_size.x = 70
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var next := host._button("Floor >", func() -> void:
		host._selection["room_floor"] = floor_index + 1
		host._selection.erase("map_room")
		host._build_editor(), bar)
	next.disabled = floor_index >= FLOOR_COUNT - 1
	var edited_here := 0
	for room in rooms:
		if edited.has(String(room.id)): edited_here += 1
	ModWorkshopForm.chip("%d rooms" % rooms.size(), Color8(168, 184, 199), bar)
	if edited_here > 0: ModWorkshopForm.chip("%d edited" % edited_here, ModWorkshopFloorMap.COLOR_EDITED, bar)
	if not lost.is_empty(): ModWorkshopForm.chip("%d cut off" % lost.size(), ModWorkshopFloorMap.COLOR_LOST, bar)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	if not host._manifest.rooms.is_empty():
		var menu := MenuButton.new()
		menu.text = "Edited rooms (%d)" % host._manifest.rooms.size()
		var popup := menu.get_popup()
		for index in host._manifest.rooms.size(): popup.add_item("Floor %d: %s" % [_floor_of(String(host._manifest.rooms[index].target)) + 1, _short_name(String(host._manifest.rooms[index].target))], index)
		popup.id_pressed.connect(func(index: int) -> void: open_room(String(host._manifest.rooms[index].target)))
		bar.add_child(menu)
	var map := ModWorkshopFloorMap.new()
	map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(map)
	var picked_id := String(host._selection.get("map_room", ""))
	var layout: Dictionary = LAYOUTS.layout_for_floor(floor_index % 31)
	map.show_floor(rooms, layout, edited, lost, exits)
	map.selected = picked_id
	var info := PanelContainer.new()
	info.add_theme_stylebox_override("panel", ModWorkshopForm.card_style())
	column.add_child(info)
	var info_row := HBoxContainer.new()
	info_row.add_theme_constant_override("separation", 8)
	info.add_child(info_row)
	var caption := host._label("", 12, ModWorkshopForm.INK, info_row)
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.custom_minimum_size = Vector2(120, 30)
	var open_button := host._button("Edit this room", func() -> void: open_room(String(map.selected)), info_row)
	var describe := func(room_id: String) -> void:
		map.selected = room_id
		host._selection["map_room"] = room_id
		map.queue_redraw()
		open_button.disabled = room_id.is_empty()
		if room_id.is_empty():
			caption.text = "Press a room to see where its doors lead; double-click to open it. Gold = changed by this mod, red = cut off. Dots: trainers (red), eggs (yellow), healing (green), services (blue)."
			open_button.text = "Edit this room"
			return
		var room := host.catalog.get_definition(StringName(room_id)) as RoomDefinition
		var legs := PackedStringArray()
		for exit_data in effective_exits(room): legs.append("door %d to %s%s" % [exit_data.transition_id, _short_name(String(exit_data.target)), " (changed)" if exit_data.edited else ""])
		caption.text = "%s: %s" % [_room_name(room_id), "; ".join(legs) if not legs.is_empty() else "no doors"]
		open_button.text = "Open room" if edited.has(room_id) else "Edit this room"
	map.room_pressed.connect(describe)
	map.room_activated.connect(open_room)
	describe.call(picked_id)

# --- Room blueprint -------------------------------------------------------------------

func _room_view(column: VBoxContainer, room: RoomDefinition) -> void:
	_current = room
	_arrival_spins.clear()
	_door_cards.clear()
	_zone_cards.clear()
	var record := _working(room)
	var saved := not _edit_record(String(room.id)).is_empty()
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	column.add_child(bar)
	var focus := host.room_focus()
	host._button("< Map", _back_to_map, bar).tooltip_text = "Back to the floor map (Esc)"
	var title := host._label(_short_name(String(room.id)), 15, ModWorkshopForm.GOLD, bar)
	title.clip_text = true
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.custom_minimum_size.x = 40
	title.tooltip_text = _room_name(String(room.id)) + (" (edited by this mod)" if saved else "")
	if saved: title.add_theme_color_override("font_color", ModWorkshopFloorMap.COLOR_EDITED)
	if focus:
		# The Workshop header (and its save status) is hidden in focus mode.
		host._status = host._label("Saving..." if host._dirty else "Saved", 11, Color8(154, 216, 179), bar)
	_blueprint = ModWorkshopRoomBlueprint.new()
	_blueprint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_blueprint.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_blueprint.snap = float(host._selection.get("room_snap", 10.0))
	_blueprint.layers.merge(host._selection.get("room_layers", {}), true)
	if _history_room != String(room.id):
		_history_room = String(room.id)
		_undo.clear()
		_redo.clear()
		_last_state = JSON.stringify(record)
	var layers_menu := MenuButton.new()
	layers_menu.text = "Show"
	layers_menu.tooltip_text = "Choose what the blueprint draws"
	var layer_popup := layers_menu.get_popup()
	var layer_keys := ["art", "walls", "doors", "arrivals", "zones"]
	for index in layer_keys.size():
		layer_popup.add_check_item(["Art", "Walls (red)", "Doors (teal)", "Arrival points (green)", "Interaction zones (orange)"][index], index)
		layer_popup.set_item_checked(index, bool(_blueprint.layers[layer_keys[index]]))
	layer_popup.hide_on_checkable_item_selection = false
	layer_popup.id_pressed.connect(func(index: int) -> void:
		var on := not layer_popup.is_item_checked(index)
		layer_popup.set_item_checked(index, on)
		_blueprint.layers[layer_keys[index]] = on
		host._selection["room_layers"] = _blueprint.layers.duplicate()
		_blueprint.queue_redraw())
	bar.add_child(layers_menu)
	var snap_choice := OptionButton.new()
	snap_choice.tooltip_text = "Grid that dragged objects snap to (hold Ctrl to place freely)"
	var snaps := [0.0, 5.0, 10.0, 25.0, 50.0]
	for value in snaps: snap_choice.add_item("Free" if value == 0.0 else "Grid %d" % int(value))
	snap_choice.select(maxi(0, snaps.find(_blueprint.snap)))
	snap_choice.item_selected.connect(func(index: int) -> void:
		_blueprint.snap = snaps[index]
		host._selection["room_snap"] = snaps[index]
		_blueprint.queue_redraw())
	bar.add_child(snap_choice)
	_undo_button = host._button("Undo", undo, bar)
	_undo_button.tooltip_text = "Undo (Ctrl+Z)"
	_redo_button = host._button("Redo", redo, bar)
	_redo_button.tooltip_text = "Redo (Ctrl+Y)"
	_update_history_buttons()
	var panel_button := Button.new()
	panel_button.text = "Panel ▸" if _panel_visible else "Panel ◂"
	panel_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel_button.tooltip_text = "Show or hide the side panel (P)"
	bar.add_child(panel_button)
	var focus_button := host._button("Exit focus" if focus else "Focus", func() -> void:
		host._selection["room_focus"] = not focus
		host._build_editor(), bar)
	focus_button.tooltip_text = "Leave full screen (Esc)" if focus else "Give the room the whole screen"
	# The blueprint fills the area; the inspector slides over its right side
	# and the blueprint fits the room into whatever is left.
	var body := Control.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.clip_contents = true
	column.add_child(body)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", ModWorkshopForm.flat(Color8(14, 15, 17), Color8(92, 100, 114), 6))
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.add_child(frame)
	frame.add_child(_blueprint)
	var dock := PanelContainer.new()
	dock.add_theme_stylebox_override("panel", ModWorkshopForm.flat(Color(ModWorkshopForm.DEEP, 0.95), ModWorkshopForm.RIM, 6))
	dock.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	dock.offset_left = -INSPECTOR_WIDTH
	dock.visible = _panel_visible
	body.add_child(dock)
	_inspector_scroll = ScrollContainer.new()
	_inspector_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dock.add_child(_inspector_scroll)
	_inspector_box = VBoxContainer.new()
	_inspector_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inspector_scroll.add_child(_inspector_box)
	_blueprint.inset_right = INSPECTOR_WIDTH + 4.0 if _panel_visible else 0.0
	var toggle_panel := func() -> void:
		_panel_visible = not _panel_visible
		dock.visible = _panel_visible
		panel_button.text = "Panel ▸" if _panel_visible else "Panel ◂"
		_blueprint.inset_right = INSPECTOR_WIDTH + 4.0 if _panel_visible else 0.0
		_blueprint.queue_redraw()
	panel_button.pressed.connect(toggle_panel)
	_blueprint.panel_toggle_requested.connect(toggle_panel)
	_blueprint.show_room(room, record.get("objects", []))
	_blueprint.select_objects(host._selection.get("room_objects", []))
	_apply_arrival_edits(record)
	_refresh_captions(room, record)
	_blueprint.element_pressed.connect(func(kind: String, key: Variant) -> void:
		_picked_kind = kind
		_picked_key = key
		_rebuild_inspector()
		var card: Control = (_door_cards if kind == "door" else _zone_cards if kind == "zone" else {}).get(key)
		if card != null and is_instance_valid(card): _inspector_scroll.ensure_control_visible.call_deferred(card))
	_blueprint.arrival_moved.connect(_arrival_dragged)
	_blueprint.selection_changed.connect(func(keys: Array) -> void:
		host._selection["room_objects"] = keys
		_rebuild_inspector()
		# The Objects card is first: bring it into view for the new selection.
		if not keys.is_empty(): _inspector_scroll.set_deferred("scroll_vertical", 0))
	_blueprint.objects_moved.connect(_objects_moved)
	_blueprint.delete_requested.connect(remove_objects)
	_blueprint.duplicate_requested.connect(duplicate_objects)
	_blueprint.undo_requested.connect(undo)
	_blueprint.redo_requested.connect(redo)
	_rebuild_inspector()

func _apply_arrival_edits(record: Dictionary) -> void:
	for spawn in record.get("spawns", []):
		if _blueprint.arrivals.has(String(spawn.id)): _blueprint.arrivals[String(spawn.id)] = Vector2(float(spawn.x), float(spawn.y))
	_blueprint.queue_redraw()

func _refresh_captions(room: RoomDefinition, record: Dictionary) -> void:
	_blueprint.door_captions.clear()
	for exit_data in effective_exits(room):
		_blueprint.door_captions[exit_data.transition_id] = "Leads to %s%s" % [_short_name(String(exit_data.target)), " (changed)" if exit_data.edited else ""]
	_blueprint.zone_captions.clear()
	for interaction in room.interactions:
		_blueprint.zone_captions[int(interaction.get("source_zone_id", -1))] = _interaction_title(interaction)
	_blueprint.queue_redraw()

func _interaction_title(interaction: Dictionary) -> String:
	var kind := String(interaction.get("kind", ""))
	var name := String(INTERACTION_NAMES.get(kind, kind.capitalize()))
	if kind == "trainer":
		var encounter := host.catalog.get_definition(StringName(String(interaction.get("encounter_id", "")))) as EncounterDefinition
		return "Trainer: %s" % (encounter.display_name if encounter != null else "?")
	if kind == "egg_pick": return "Egg %d" % (int(interaction.get("source_zone_id", 0)) + 1)
	return name

func _arrival_dragged(spawn_id: String, point: Vector2) -> void:
	var record := _working(_current)
	if not record.get("spawns") is Array: record["spawns"] = []
	var found := false
	for spawn in record.spawns:
		if String(spawn.id) == spawn_id:
			spawn["x"] = point.x
			spawn["y"] = point.y
			found = true
	if not found: record.spawns.append({"id": spawn_id, "x": point.x, "y": point.y})
	_attach(_current)
	_record_changed()
	if _arrival_spins.has(spawn_id):
		_arrival_spins[spawn_id][0].set_value_no_signal(point.x)
		_arrival_spins[spawn_id][1].set_value_no_signal(point.y)

# --- Inspector ------------------------------------------------------------------------

func _rebuild_inspector() -> void:
	for child in _inspector_box.get_children():
		_inspector_box.remove_child(child)
		child.queue_free()
	_arrival_spins.clear()
	_door_cards.clear()
	_zone_cards.clear()
	var room := _current
	var record := _working(room)
	var form := host._make_form()
	form.label_width = 74.0
	form.changed.connect(func() -> void:
		_attach(room)
		_record_changed())
	_inspector_box.add_child(form)
	_objects_section(form, room, record)
	_doors_section(form, room, record)
	_arrivals_section(form, room, record)
	_inside_section(form, room, record)
	if not _edit_record(String(room.id)).is_empty():
		var reset := form.card("This room")
		reset.note("Remove every change this mod makes to the room: doors, arrival points, objects and what's inside.")
		reset.button("Reset room", func() -> void:
			for index in range(host._manifest.rooms.size() - 1, -1, -1):
				if String(host._manifest.rooms[index].target) == String(room.id): host._manifest.rooms.remove_at(index)
			_drafts.erase(String(room.id))
			host._selection["room_objects"] = []
			host._changed()
			_record_changed()
			host._build_editor())

func _selected_style(selected: bool) -> StyleBoxFlat:
	return ModWorkshopForm.flat(Color8(40, 43, 49) if selected else Color8(24, 27, 30), ModWorkshopForm.GOLD if selected else Color8(80, 87, 99), 6)

func _doors_section(form: ModWorkshopForm, room: RoomDefinition, record: Dictionary) -> void:
	var section := form.card("Doors")
	if room.exits.is_empty():
		section.note("This room has no doors to other rooms.")
		return
	section.note("Numbers match the circles on the map. Rerouting doors can make a floor impossible to finish, so test the route in a save before sharing.", Color8(240, 200, 120))
	for exit_data in room.exits:
		var transition_id := int(exit_data.get("transition_id", -1))
		var edit := _exit_edit(record, transition_id)
		if edit.is_empty():
			edit = {"transition_id": transition_id, "target_room_id": String(exit_data.get("target_room_id", "")), "target_spawn_id": String(exit_data.get("target_spawn_id", ""))}
			if not record.get("exits") is Array: record["exits"] = []
			record.exits.append(edit)
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", _selected_style(_picked_kind == "door" and _picked_key == transition_id))
		section.add_child(card)
		_door_cards[transition_id] = card
		var inner := ModWorkshopForm.new()
		card.add_child(inner)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 6)
		inner.add_child(head)
		ModWorkshopForm.chip(str(transition_id), ModWorkshopRoomBlueprint.COLOR_DOOR, head)
		host._label("Door %d" % transition_id, 14, ModWorkshopForm.INK, head)
		if not _blueprint.has_door(transition_id): ModWorkshopForm.chip("no marker", Color8(240, 130, 120), head)
		var normally := String(exit_data.get("target_room_id", ""))
		var changed_chip := ModWorkshopForm.chip("changed", ModWorkshopFloorMap.COLOR_EDITED)
		head.add_child(changed_chip)
		changed_chip.visible = String(edit.get("target_room_id", normally)) != normally or String(edit.get("target_spawn_id", "")) != String(exit_data.get("target_spawn_id", ""))
		var leads := ModWorkshopForm.new()
		leads.describe = host._describe
		leads.label_width = 74.0
		leads.changed.connect(form.changed.emit)
		leads.pick_requested.connect(host._open_picker)
		inner.add_child(leads)
		var footer := HBoxContainer.new()
		footer.add_theme_constant_override("separation", 6)
		inner.add_child(footer)
		var preview_holder := Control.new()
		preview_holder.custom_minimum_size = Vector2(104, 72)
		footer.add_child(preview_holder)
		var preview := ModWorkshopRoomBlueprint.new()
		preview.custom_minimum_size = Vector2(104, 72)
		preview.size = Vector2(104, 72)
		preview.editable = false
		preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		preview.layers = {"art": true, "walls": false, "doors": false, "arrivals": true, "zones": false}
		preview_holder.add_child(preview)
		var side := VBoxContainer.new()
		side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		side.add_theme_constant_override("separation", 3)
		footer.add_child(side)
		var show_target := func() -> void:
			var target := host.catalog.get_definition(StringName(String(edit.get("target_room_id", "")))) as RoomDefinition
			if target != null:
				preview.show_room(target)
				preview.only_arrival = String(edit.get("target_spawn_id", ""))
				preview.queue_redraw()
		show_target.call()
		leads.reference("Leads to", edit, "target_room_id", "room", false, null, func() -> void:
			var target := host.catalog.get_definition(StringName(String(edit.target_room_id))) as RoomDefinition
			edit["target_spawn_id"] = String(target.spawn_ids[0]) if target != null and not target.spawn_ids.is_empty() else ""
			_refresh_captions(room, record)
			_rebuild_inspector())
		var target_room := host.catalog.get_definition(StringName(String(edit.get("target_room_id", "")))) as RoomDefinition
		var spawns: Array = Array(target_room.spawn_ids).map(func(value: StringName) -> String: return String(value)) if target_room != null else []
		if not spawns.is_empty(): leads.choice("Arrives at", edit, "target_spawn_id", spawns, [], null, func() -> void:
			show_target.call()
			_refresh_captions(room, record))
		var normal_label := host._label("Normally: %s" % _short_name(normally), 11, ModWorkshopForm.MUTED, side)
		normal_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		normal_label.custom_minimum_size.x = 60
		if edit.get("target_room_id", normally) != normally or edit.get("target_spawn_id", "") != exit_data.get("target_spawn_id", ""):
			host._button("Reset", func() -> void:
				edit["target_room_id"] = normally
				edit["target_spawn_id"] = String(exit_data.get("target_spawn_id", ""))
				host._changed()
				_attach(room)
				_refresh_captions(room, record)
				_rebuild_inspector(), side)
		host._button("Go there", func() -> void: open_room(String(edit.get("target_room_id", normally))), side)

func _exit_edit(record: Dictionary, transition_id: int) -> Dictionary:
	for edit in record.get("exits", []):
		if int(edit.get("transition_id", -2)) == transition_id: return edit
	return {}

func _arrivals_section(form: ModWorkshopForm, room: RoomDefinition, record: Dictionary) -> void:
	if room.spawn_ids.is_empty(): return
	var section := form.card("Arrival points")
	section.note("Where you stand after coming through a door. Drag the green circle on the map, or type exact coordinates.")
	if not record.get("spawns") is Array: record["spawns"] = []
	var dimensions: Vector2 = room.minimap_metadata.get("source_dimensions", Vector2(4000, 4000))
	for spawn_id in room.spawn_ids:
		var key := String(spawn_id)
		var original: Vector2 = room.spawn_positions.get(key, Vector2.ZERO)
		var current := original
		for spawn in record.spawns:
			if String(spawn.id) == key: current = Vector2(float(spawn.x), float(spawn.y))
		var line := section.row(key.trim_prefix("entry-").capitalize() if key.begins_with("entry-") else key)
		var x_spin := SpinBox.new()
		var y_spin := SpinBox.new()
		for spin in [x_spin, y_spin]:
			spin.min_value = 0
			spin.max_value = 6000
			spin.step = 1
			spin.custom_minimum_size.x = 52
			spin.get_line_edit().add_theme_font_size_override("font_size", 12)
			# The default 4-character minimum makes two boxes overflow the panel.
			spin.get_line_edit().add_theme_constant_override("minimum_character_width", 1)
		x_spin.max_value = dimensions.x
		y_spin.max_value = dimensions.y
		x_spin.set_value_no_signal(current.x)
		y_spin.set_value_no_signal(current.y)
		var apply := func(_value: float) -> void:
			_arrival_dragged(key, Vector2(x_spin.value, y_spin.value))
			_blueprint.arrivals[key] = Vector2(x_spin.value, y_spin.value)
			_blueprint.queue_redraw()
		x_spin.value_changed.connect(apply)
		y_spin.value_changed.connect(apply)
		line.add_child(x_spin)
		line.add_child(y_spin)
		host._button("Reset", func() -> void:
			for index in range(record.spawns.size() - 1, -1, -1):
				if String(record.spawns[index].id) == key: record.spawns.remove_at(index)
			_blueprint.arrivals[key] = original
			_blueprint.queue_redraw()
			host._changed()
			_attach(room)
			_rebuild_inspector(), line)
		_arrival_spins[key] = [x_spin, y_spin]

func _inside_section(form: ModWorkshopForm, room: RoomDefinition, record: Dictionary) -> void:
	var section := form.card("Inside this room")
	var read_only := PackedStringArray()
	var shown := 0
	for interaction_edit in record.get("interactions", []):
		var original: Dictionary = {}
		for interaction in room.interactions:
			if String(interaction.get("id", "")) == String(interaction_edit.id): original = interaction
		var zone_id := int(original.get("source_zone_id", -1))
		var kind := String(original.get("kind", "trainer" if interaction_edit.has("encounter_id") else ""))
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", _selected_style(_picked_kind == "zone" and _picked_key == zone_id))
		section.add_child(card)
		_zone_cards[zone_id] = card
		var inner := host._make_form()
		inner.label_width = 74.0
		inner.changed.connect(func() -> void: _attach(room))
		card.add_child(inner)
		inner.heading(_interaction_title(original))
		_interaction_fields(inner, kind, interaction_edit, original)
		shown += 1
	for interaction in room.interactions:
		var editable := false
		for interaction_edit in record.get("interactions", []):
			if String(interaction_edit.id) == String(interaction.get("id", "")): editable = true
		if not editable: read_only.append(_interaction_title(interaction))
	if shown == 0: section.note("Nothing here can be edited.")
	if not read_only.is_empty(): section.note("Also here (not editable): %s." % ", ".join(read_only))

func _interaction_fields(form: ModWorkshopForm, kind: String, interaction_edit: Dictionary, original: Dictionary) -> void:
	match kind:
		"trainer":
			form.reference("Trainer here", interaction_edit, "encounter_id", "encounter")
		"egg_pick":
			var values: Dictionary = interaction_edit["set"]
			var candidates: Array = values.get("candidates", [])
			var weights: Array = values.get("weights", [])
			for index in candidates.size():
				var line := form.row("")
				var proxy := {"minion": String(candidates[index]), "weight": int(weights[index]) if index < weights.size() else 0}
				var portrait := ModWorkshopForm.picture(host._minion_texture(String(proxy.minion)), Vector2(28, 28), line)
				form.reference("", proxy, "minion", "minion", false, line, func() -> void:
					candidates[index] = proxy.minion
					portrait.texture = host._minion_texture(String(proxy.minion)))
				form.number("", proxy, "weight", 0, 100, proxy.weight, 1, line).value_changed.connect(func(value: float) -> void: weights[index] = int(value))
			form.note("This egg's own chances (used when no hatchery rule or recovered mod overrides the floor). They must add up to 100.")
		"unlock_boss_door":
			form.number("Boss door keys", interaction_edit["set"], "required_floor_keys", 0, 9, 3)
		"unlock_eggery_door":
			form.number("Hatchery door keys", interaction_edit["set"], "required_eggery_keys", 0, 9, 1)
		"gem_shop", "gem_combiner", "minion_storage":
			form.text("Text", interaction_edit["set"], "text", 300, true)

# --- Undo -----------------------------------------------------------------------------

## Call after any change to the open room's record. Changes within half a
## second (a drag, typing) merge into one undo step.
func _record_changed() -> void:
	var record := _working(_current)
	var now := JSON.stringify(record)
	if now == _last_state: return
	var msec := Time.get_ticks_msec()
	if _undo.is_empty() or msec - _last_push_msec > 500:
		_undo.append(_last_state)
		if _undo.size() > 100: _undo.pop_front()
	_last_push_msec = msec
	_redo.clear()
	_last_state = now
	_update_history_buttons()

func undo() -> void:
	if _undo.is_empty() or _current == null: return
	_redo.append(_last_state)
	_restore_state(_undo.pop_back())

func redo() -> void:
	if _redo.is_empty() or _current == null: return
	_undo.append(_last_state)
	_restore_state(_redo.pop_back())

func _restore_state(state: String) -> void:
	var parsed: Variant = JSON.parse_string(state)
	if not parsed is Dictionary: return
	var record := _working(_current)
	record.clear()
	record.merge(parsed)
	_last_state = state
	_last_push_msec = 0
	_attach(_current)
	host._changed()
	_refresh_room()

func _update_history_buttons() -> void:
	if is_instance_valid(_undo_button): _undo_button.disabled = _undo.is_empty()
	if is_instance_valid(_redo_button): _redo_button.disabled = _redo.is_empty()

## Redraws the blueprint from the record (keeping zoom and selection) and the inspector.
func _refresh_room() -> void:
	var record := _working(_current)
	_blueprint.show_room(_current, record.get("objects", []))
	_blueprint.select_objects(host._selection.get("room_objects", []))
	_apply_arrival_edits(record)
	_refresh_captions(_current, record)
	_rebuild_inspector()
	_update_history_buttons()

# --- Objects ----------------------------------------------------------------------------

## The record entry for object `key`: an index edit for the room's own objects,
## or the matching "add" entry for objects this mod placed.
func _object_edit(record: Dictionary, key: int, create: bool = true) -> Dictionary:
	if not record.get("objects") is Array: record["objects"] = []
	var original := _blueprint.original_count()
	if key >= original:
		var added: Array = record.objects.filter(func(edit: Dictionary) -> bool: return edit.has("add"))
		return added[key - original] if key - original < added.size() else {}
	for edit in record.objects:
		if not edit.has("add") and int(edit.get("index", -1)) == key: return edit
	if not create: return {}
	var edit := {"index": key}
	record.objects.append(edit)
	return edit

func _objects_moved(keys: Array, _delta: Vector2, finished: bool) -> void:
	if not finished: return
	var record := _working(_current)
	for key in keys:
		var info := _blueprint.object_info(int(key))
		if info.is_empty() or not info.editable: continue
		var edit := _object_edit(record, int(key))
		edit["x"] = roundf(info.position.x)
		edit["y"] = roundf(info.position.y)
	_object_changes_done()

func _object_changes_done() -> void:
	_attach(_current)
	host._changed()
	_record_changed()
	_refresh_room()

func remove_objects(keys: Array) -> void:
	var record := _working(_current)
	var original := _blueprint.original_count()
	var added_to_drop: Array = []
	for key in keys:
		var info := _blueprint.object_info(int(key))
		if info.is_empty() or not info.editable: continue
		if int(key) >= original: added_to_drop.append(_object_edit(record, int(key)))
		else:
			var edit := _object_edit(record, int(key))
			edit.clear()
			edit.merge({"index": int(key), "remove": true})
	for edit in added_to_drop: record.objects.erase(edit)
	host._selection["room_objects"] = []
	_object_changes_done()

func restore_object(key: int) -> void:
	var record := _working(_current)
	var edit := _object_edit(record, key, false)
	if not edit.is_empty(): record.objects.erase(edit)
	_object_changes_done()

func duplicate_objects(keys: Array) -> void:
	var record := _working(_current)
	if not record.get("objects") is Array: record["objects"] = []
	var created: Array = []
	var next_key: int = _blueprint.original_count() + record.objects.filter(func(edit: Dictionary) -> bool: return edit.has("add")).size()
	for key in keys:
		var info := _blueprint.object_info(int(key))
		if info.is_empty() or not UserModBuilder.object_addable(String(info.sprite)): continue
		record.objects.append({"add": String(info.sprite), "x": roundf(info.position.x + 24.0), "y": roundf(info.position.y + 24.0), "x_scale": info.scale.x, "y_scale": info.scale.y, "rotation": rad_to_deg(float(info.rotation))})
		created.append(next_key)
		next_key += 1
	if created.is_empty():
		host.show_message("Only art and walls can be duplicated. Zones, eggs, chests and healing stones belong to the room's game logic.")
		return
	host._selection["room_objects"] = created
	_object_changes_done()

func add_object(sprite_name: String) -> void:
	var record := _working(_current)
	if not record.get("objects") is Array: record["objects"] = []
	var at := _blueprint.view_center()
	var texture := RoomArtCatalog.texture(sprite_name)
	if texture != null and sprite_name != "collRect": at -= texture.get_size() * 0.5
	record.objects.append({"add": sprite_name, "x": roundf(at.x), "y": roundf(at.y)})
	host._selection["room_objects"] = [_blueprint.original_count() + record.objects.filter(func(edit: Dictionary) -> bool: return edit.has("add")).size() - 1]
	_object_changes_done()

## Selected objects at the top of the inspector, plus the "Add to room" entry point.
func _objects_section(form: ModWorkshopForm, _room: RoomDefinition, record: Dictionary) -> void:
	var section := form.card("Objects")
	var tools := section.row("")
	host._button("+ Add to room", _open_palette, tools)
	host._button("Fit view", _blueprint.reset_view, tools)
	var keys: Array = _blueprint.selected_objects
	if keys.is_empty():
		section.note("Click art, a wall or a zone to select it; Shift+click selects several (a trainer and their zone, say). Drag to move. Arrows nudge, Delete removes, Ctrl+D duplicates, Ctrl+Z undoes. Wheel zooms, right-drag pans.")
	elif keys.size() > 1:
		section.note("%d objects selected. Drag any of them to move them together." % keys.size(), ModWorkshopForm.GOLD)
		var multi := section.row("")
		host._button("Duplicate", func() -> void: duplicate_objects(keys), multi)
		host._button("Remove", func() -> void: remove_objects(keys), multi)
	else:
		_object_card(section, record, int(keys[0]))
	var edits: Array = record.get("objects", [])
	var removed := edits.filter(func(edit: Dictionary) -> bool: return bool(edit.get("remove", false)))
	var added := edits.filter(func(edit: Dictionary) -> bool: return edit.has("add"))
	if not edits.is_empty():
		var summary := section.note("This mod: %d added, %d moved or resized, %d removed." % [added.size(), edits.size() - removed.size() - added.size(), removed.size()], ModWorkshopFloorMap.COLOR_EDITED)
		summary.add_theme_font_size_override("font_size", 11)
	if not removed.is_empty():
		host._button("Bring back removed objects", func() -> void:
			for edit in removed: record.objects.erase(edit)
			_object_changes_done(), section.row(""))

func _object_card(section: ModWorkshopForm, record: Dictionary, key: int) -> void:
	var info := _blueprint.object_info(key)
	if info.is_empty(): return
	var head := section.row("")
	if info.kind == "art": ModWorkshopForm.picture(info.texture, Vector2(40, 40), head)
	var title := String(_blueprint.zone_captions.get(int(info.zone_id), "Interaction zone")) if info.kind == "zone" else RoomArtCatalog.caption(String(info.sprite))
	var name_label := host._label(title, 14, ModWorkshopForm.INK, head)
	name_label.clip_text = true
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if info.added: ModWorkshopForm.chip("added", ModWorkshopRoomBlueprint.COLOR_ADDED, head)
	if not info.editable:
		section.note("Part of the room's game logic (doors, entries and gates stay put).")
		return
	var edit := _object_edit(record, key, false)
	var values := {"x": info.position.x, "y": info.position.y, "x_scale": info.scale.x, "y_scale": info.scale.y, "rotation": rad_to_deg(float(info.rotation))}
	var apply := func() -> void:
		var target := _object_edit(record, key)
		for field in values: target[field] = snappedf(float(values[field]), 0.01)
		_object_changes_done()
	for pair in [["Position", "x", "y", 1.0], ["Scale", "x_scale", "y_scale", 0.05]]:
		var line := section.row(pair[0])
		for field in [pair[1], pair[2]]:
			var spin := SpinBox.new()
			spin.step = pair[3]
			spin.min_value = -2000 if pair[3] == 1.0 else -40.0
			spin.max_value = 8000 if pair[3] == 1.0 else 40.0
			spin.custom_minimum_size.x = 56
			spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			spin.get_line_edit().add_theme_font_size_override("font_size", 12)
			# The default 4-character minimum makes two boxes overflow the panel.
			spin.get_line_edit().add_theme_constant_override("minimum_character_width", 1)
			spin.set_value_no_signal(float(values[field]))
			spin.value_changed.connect(func(value: float) -> void:
				values[field] = value
				apply.call())
			line.add_child(spin)
	if info.kind != "zone":
		var turn := section.row("Rotation")
		var rotation_spin := SpinBox.new()
		rotation_spin.min_value = -360
		rotation_spin.max_value = 360
		rotation_spin.step = 1
		rotation_spin.suffix = "°"
		rotation_spin.custom_minimum_size.x = 70
		rotation_spin.get_line_edit().add_theme_constant_override("minimum_character_width", 1)
		rotation_spin.set_value_no_signal(float(values.rotation))
		rotation_spin.value_changed.connect(func(value: float) -> void:
			values["rotation"] = value
			apply.call())
		turn.add_child(rotation_spin)
		var flip := host._button("Flip", func() -> void:
			# Mirror around the object's centre so it stays in place.
			values["x"] = float(values.x) + Vector2(info.size).x * float(values.x_scale)
			values["x_scale"] = -float(values.x_scale)
			apply.call(), turn)
		flip.tooltip_text = "Mirror left-right"
	var actions := section.row("")
	if UserModBuilder.object_addable(String(info.sprite)): host._button("Duplicate", func() -> void: duplicate_objects([key]), actions)
	host._button("Remove", func() -> void: remove_objects([key]), actions)
	if not edit.is_empty() and not info.added: host._button("Reset", func() -> void: restore_object(key), actions)
	if info.kind == "zone":
		section.note("The zone is where the player presses to talk or interact. To move a trainer, Shift+click their figure and their zone, then drag both.")

# --- Object palette ---------------------------------------------------------------------

func _open_palette() -> void:
	var box := host._overlay_panel("Add to this room", 420.0)
	var filter := LineEdit.new()
	filter.placeholder_text = "Search art, e.g. tree, torch, wall..."
	box.add_child(filter)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var grid := HFlowContainer.new()
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	scroll.add_child(grid)
	# This room's own art first, then the rest of the library.
	var here: Array[String] = []
	for attributes in _current.ensure_payload().objects:
		var sprite_name := String(attributes.get("spriteName", "")).strip_edges()
		if sprite_name != "collRect" and UserModBuilder.object_addable(sprite_name) and sprite_name not in here: here.append(sprite_name)
	var entries: Array[String] = ["collRect"]
	entries.append_array(here)
	for sprite_name in RoomArtCatalog.library():
		if sprite_name not in entries: entries.append(sprite_name)
	var tiles: Array = []
	for sprite_name in entries:
		var tile := Button.new()
		tile.custom_minimum_size = Vector2(76, 70)
		tile.tooltip_text = "%s%s" % [RoomArtCatalog.caption(sprite_name), "\nUsed in this room" if sprite_name in here else ""]
		tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var column := VBoxContainer.new()
		column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_theme_constant_override("separation", 0)
		tile.add_child(column)
		if sprite_name == "collRect":
			var swatch := ColorRect.new()
			swatch.color = Color(ModWorkshopRoomBlueprint.COLOR_WALL, 0.5)
			swatch.custom_minimum_size = Vector2(70, 46)
			swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
			column.add_child(swatch)
		else:
			var picture := ModWorkshopForm.picture(RoomArtCatalog.texture(sprite_name), Vector2(70, 46), column)
			picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var caption := host._label(RoomArtCatalog.caption(sprite_name), 10, ModWorkshopForm.GOLD if sprite_name in here else ModWorkshopForm.INK, column)
		caption.clip_text = true
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.pressed.connect(func() -> void:
			host._close_overlay()
			add_object(sprite_name))
		grid.add_child(tile)
		tiles.append([tile, (sprite_name + " " + RoomArtCatalog.caption(sprite_name)).to_lower()])
	filter.text_changed.connect(func(text: String) -> void:
		for pair in tiles: pair[0].visible = text.is_empty() or pair[1].contains(text.to_lower()))
	var footer := HBoxContainer.new()
	box.add_child(footer)
	var hint := host._label("Gold names are already used in this room. New objects appear in the middle of the view.", 11, ModWorkshopForm.MUTED, footer)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host._button("Cancel", host._close_overlay, footer)
	filter.grab_focus.call_deferred()
