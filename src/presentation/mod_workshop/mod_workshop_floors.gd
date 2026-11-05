class_name ModWorkshopFloors
extends RefCounted

const FEATURE_NAMES := {"door": "Door to a room", "return": "Return to the Side Hall", "egg": "Hatchery egg", "trainer": "Trainer", "heal_party": "Healing stone"}
const TILE_NOTES := {
	"ice": "Continue in the direction you entered.",
	"slow": "Slow movement and stop forced movement.",
	"arrow": "Keep moving in the arrow’s direction until stopped.",
	"jump": "Leap in the marked direction and clear gaps.",
	"pit": "Block walking. Cross it with a jump pad.",
}

var host: ModWorkshopView
var _floor: Dictionary
var _room: Dictionary
var _blueprint: ModWorkshopRoomBlueprint
var _map: ModWorkshopCustomFloorMap
var _inspector: ScrollContainer
var _brush := ""
var _brush_settings := {"rotation": 0}
var _section := "room"
var _show_map := true

func _init(owner: ModWorkshopView) -> void:
	host = owner

func build(content: Control) -> void:
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 5)
	content.add_child(column)
	var bar := HBoxContainer.new()
	column.add_child(bar)
	var floors: Array = host._manifest.floors
	var selected := clampi(int(host._selection.get("custom_floor", 0)), 0, maxi(0, floors.size() - 1))
	var add_floor := host._button("+ New floor", _new_floor, bar)
	add_floor.disabled = floors.size() >= 24
	if floors.is_empty():
		var empty := host._make_form()
		column.add_child(empty)
		empty.card("Build a custom floor").note("Create rooms, link them with doors, and place trainers, hatchery eggs and puzzle tiles. Enabled floors appear behind the lobby’s right-hand door.")
		return
	_floor = floors[selected]
	_pick_option(bar, floors, selected, "Choose a floor", func(index: int) -> void:
		host._selection["custom_floor"] = index
		host._selection["custom_room"] = 0
		_brush = ""
		_section = "room"
		_show_map = true
		host._build_editor())
	host._button("Floor details", func() -> void:
		_section = "floor" if _section != "floor" else "room"
		if _show_map: _rebuild_map_inspector()
		else: _rebuild_inspector(), bar)
	var rooms: Array = _floor.get("rooms", [])
	if rooms.is_empty() or rooms.any(func(room: Variant) -> bool: return not room is Dictionary or not room.has("id")):
		var invalid := host._make_form()
		column.add_child(invalid)
		var card := invalid.card("This floor needs valid rooms")
		card.note("Use the Test tab’s Check button for details.")
		card.button("Remove floor", _remove_floor)
		return
	var room_index := clampi(int(host._selection.get("custom_room", 0)), 0, rooms.size() - 1)
	_room = rooms[room_index]
	if _show_map:
		_build_floor_map(column)
	else:
		_build_room_blueprint(column, rooms, room_index)

func _build_floor_map(column: VBoxContainer) -> void:
	var bar := HBoxContainer.new()
	column.add_child(bar)
	var add := host._button("+ Room", _new_room, bar)
	add.disabled = _floor.rooms.size() >= CustomFloorBuilder.MAX_ROOMS
	_map = ModWorkshopCustomFloorMap.new()
	host._button("Fit map", _map.fit_rooms, bar)
	host._button("−", func() -> void: _map.zoom /= 1.2, bar).tooltip_text = "Zoom out"
	host._button("+", func() -> void: _map.zoom *= 1.2, bar).tooltip_text = "Zoom in"
	var help := host._label("Drag rooms to arrange them. Connect gold to blue to add a door.", 12, ModWorkshopForm.MUTED, bar)
	help.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	help.clip_text = true
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)
	body.add_child(_map)
	_inspector = ScrollContainer.new()
	_inspector.custom_minimum_size.x = 258
	_inspector.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(_inspector)
	_map.show_floor(_floor, String(_room.id))
	_map.room_pressed.connect(_select_map_room)
	_map.room_activated.connect(_open_room_blueprint)
	_map.room_moved.connect(_move_map_room)
	_map.door_requested.connect(_link_map_rooms)
	_rebuild_map_inspector()
	_map.fit_rooms.call_deferred()

func _select_map_room(room_id: String) -> void:
	var index := _room_index(room_id)
	if index < 0: return
	host._selection["custom_room"] = index
	_room = _floor.rooms[index]
	_section = "room"
	_rebuild_map_inspector()

func _open_room_blueprint(room_id: String) -> void:
	var index := _room_index(room_id)
	if index < 0: return
	host._selection["custom_room"] = index
	_show_map = false
	_section = "room"
	_brush = ""
	host._build_editor()

func return_to_floor_map() -> bool:
	if _show_map: return false
	_show_map = true
	_section = "room"
	_brush = ""
	host._build_editor()
	return true

func _room_index(room_id: String) -> int:
	for index in _floor.rooms.size():
		if String(_floor.rooms[index].id) == room_id: return index
	return -1

func _move_map_room(room_id: String, map_position: Vector2) -> void:
	var index := _room_index(room_id)
	if index < 0: return
	var record: Dictionary = _floor.rooms[index]
	record["map_x"] = map_position.x
	record["map_y"] = map_position.y
	host._changed()

func _rebuild_map_inspector() -> void:
	var form := _reset_inspector()
	form.changed.connect(_map.refresh_routes)
	if _section == "floor":
		_floor_details(form)
		return
	var room_card := form.card(String(_room.get("name", _room.id)))
	var actions := room_card.row("")
	room_card.button("Edit room", _open_room_blueprint.bind(String(_room.id)), actions)
	if _floor.get("start_room", "") == _room.id:
		room_card.note("Entrance room", ModWorkshopForm.GOLD)
	else:
		room_card.button("Set entrance", func() -> void:
			_floor["start_room"] = _room.id
			_map_changed(), actions)
	if _floor.rooms.size() > 1:
		room_card.button("Remove room", _remove_room)
	var links := form.card("Doors from this room")
	if _room.features.size() < CustomFloorBuilder.MAX_FEATURES:
		var tools := links.row("")
		if _floor.rooms.size() > 1: links.button("+ Door to room", _choose_map_destination, tools)
		links.button("+ Side Hall exit", func() -> void: _link_map_rooms(String(_room.id), ""), tools)
	var number := 0
	var any_links := false
	for feature in _room.get("features", []):
		if feature.kind not in ["door", "return"]: continue
		any_links = true
		if feature.kind == "door": number += 1
		var caption := "Side Hall exit" if feature.kind == "return" else String(feature.get("label", ""))
		if caption.is_empty(): caption = "Door %d" % number
		var door := links.card(caption)
		if feature.kind == "door": _door_route_fields(door, feature)
		door.button("Remove door", func() -> void:
			_room.features.erase(feature)
			_map_changed())
	if not any_links: links.note("No outgoing doors.")

func _choose_map_destination() -> void:
	var entries: Array = []
	for room in _floor.rooms:
		if room.id != _room.id: entries.append({"id": String(room.id), "label": String(room.get("name", room.id))})
	var picker := ModWorkshopPicker.new()
	host._picker = picker
	host.add_child(picker)
	picker.open("Link to a room", entries)
	var source_id := String(_room.id)
	picker.picked.connect(func(id: String) -> void: _link_map_rooms(source_id, id))

func _link_map_rooms(from_room: String, to_room: String) -> void:
	var index := _room_index(from_room)
	if index < 0 or from_room == to_room: return
	var source: Dictionary = _floor.rooms[index]
	if not to_room.is_empty() and _room_index(to_room) < 0: return
	if not to_room.is_empty() and source.features.any(func(feature: Dictionary) -> bool: return feature.get("destination") == to_room):
		host.show_message("There is already a door to that room. Use the room blueprint to place a second one.")
		return
	if not _append_door(source, to_room):
		host.show_message("There is no open wall space for an automatic door. Use the room blueprint to place it.")
		return
	_select_map_room(from_room)
	host._changed()
	_map.refresh_routes()

func _map_changed() -> void:
	host._changed()
	_map.refresh_routes()
	_rebuild_map_inspector()

func _build_room_blueprint(column: VBoxContainer, rooms: Array, room_index: int) -> void:
	var room_bar := HBoxContainer.new()
	column.add_child(room_bar)
	host._button("< Floor map", return_to_floor_map, room_bar)
	_pick_option(room_bar, rooms, room_index, "Choose a room", func(index: int) -> void:
		host._selection["custom_room"] = index
		_section = "room"
		_brush = ""
		host._build_editor())
	host._button("+ Object", _pick_object, room_bar)
	host._button("+ Feature", _pick_feature, room_bar)
	host._button("Paint tiles", _pick_brush, room_bar)
	host._button("Import PNG", _import_art, room_bar)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", ModWorkshopForm.inset_style())
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(frame)
	_blueprint = ModWorkshopRoomBlueprint.new()
	_blueprint.custom_room = true
	_blueprint.paint_tiles = not _brush.is_empty()
	_blueprint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_blueprint.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_child(_blueprint)
	_inspector = ScrollContainer.new()
	_inspector.custom_minimum_size.x = 258
	_inspector.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(_inspector)
	_blueprint.selection_changed.connect(func(_keys: Array) -> void:
		_section = "room"
		_rebuild_inspector())
	_blueprint.objects_moved.connect(_move_objects)
	_blueprint.delete_requested.connect(_remove_objects)
	_blueprint.duplicate_requested.connect(_duplicate_objects)
	_blueprint.tile_placed.connect(_stamp_tile)
	_blueprint.arrival_moved.connect(func(_id: String, position: Vector2) -> void:
		_room.entry_x = clampf(position.x + CustomFloorBuilder.PLAYER_FEET.x, 68, float(_room.width) - 69)
		_room.entry_y = clampf(position.y + CustomFloorBuilder.PLAYER_FEET.y, 134, float(_room.height) - 56)
		_blueprint.arrivals["start"] = CustomFloorBuilder.point(_room, "entry_x", "entry_y") - CustomFloorBuilder.PLAYER_FEET
		host._changed())
	_refresh_blueprint()
	_rebuild_inspector()

func _pick_option(parent: Control, records: Array, selected: int, caption: String, on_select: Callable) -> void:
	var picker := OptionButton.new()
	picker.tooltip_text = caption
	picker.fit_to_longest_item = false
	picker.clip_text = true
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.custom_minimum_size.x = 110
	for record in records: picker.add_item(String(record.get("name", record.id)))
	picker.select(selected)
	picker.item_selected.connect(on_select)
	parent.add_child(picker)

func _new_floor() -> void:
	var room := _default_room("entrance", "Entrance")
	room.features.append({"id": "hall", "kind": "return", "x": 420, "y": 490})
	host._manifest.floors.append({"id": host._unique_id("floor", "new_floor"), "name": "New Floor", "description": "", "start_room": "entrance", "rooms": [room]})
	host._selection["custom_floor"] = host._manifest.floors.size() - 1
	host._selection["custom_room"] = 0
	_section = "room"
	_show_map = true
	_brush = ""
	_changed_and_rebuild()

func _new_room() -> void:
	var id := _local_id(_floor.rooms, "room")
	var room := _default_room(id, "Room %d" % (_floor.rooms.size() + 1))
	if _append_door(_room, id):
		_append_door(room, String(_room.id))
	_floor.rooms.append(room)
	host._selection["custom_room"] = _floor.rooms.size() - 1
	_section = "room"
	_brush = ""
	_changed_and_rebuild()

func _append_door(room: Dictionary, destination: String) -> bool:
	var features: Array = room.features
	if features.size() >= CustomFloorBuilder.MAX_FEATURES: return false
	var dimensions := Vector2(float(room.width), float(room.height))
	var candidates: Array[Vector2] = []
	for x in range(int(dimensions.x) - 135, 110, -116):
		candidates.append(Vector2(x, 145))
		candidates.append(Vector2(x, dimensions.y - 63))
	for y in range(235, int(dimensions.y) - 120, 112):
		candidates.append(Vector2(70, y))
		candidates.append(Vector2(dimensions.x - 70, y))
	var occupied: Array[Vector2] = []
	for feature in features:
		var center := CustomFloorBuilder.point(feature)
		if feature.kind in ["door", "return"]:
			center = CustomFloorBuilder.door_geometry(feature, center, dimensions, false).contact
		occupied.append(center)
	for point in candidates:
		if occupied.any(func(center: Vector2) -> bool: return center.distance_squared_to(point) < 104.0 * 104.0): continue
		var kind := "return" if destination.is_empty() else "door"
		var feature := {"id": _local_id(features, kind), "kind": kind, "x": point.x, "y": point.y}
		if not destination.is_empty(): feature["destination"] = destination
		features.append(feature)
		return true
	return false

func _default_room(id: String, label: String) -> Dictionary:
	return {"id": id, "name": label, "template": "stone", "width": 840, "height": 580, "entry_x": 420, "entry_y": 388, "objects": [], "features": []}

func _local_id(records: Array, prefix: String) -> String:
	var index := 1
	while records.any(func(record: Dictionary) -> bool: return String(record.id) == "%s_%d" % [prefix, index]):
		index += 1
	return "%s_%d" % [prefix, index]

func _changed_and_rebuild() -> void:
	host._changed()
	host._build_editor()

func _refresh_blueprint() -> void:
	var definition := CustomFloorBuilder.make_room(_floor.id, _room)
	_blueprint.show_room(definition)
	_blueprint.zone_captions.clear()
	for interaction in definition.interactions:
		var label := String(interaction.get("kind", "")).capitalize()
		match interaction.kind:
			&"custom_door":
				var destination := String(interaction.target_room_id).get_file()
				for record in _floor.rooms:
					if record.id == destination: label = "→ " + String(record.name)
			&"custom_floor_return": label = "→ Side Hall"
			&"egg_pick": label = host._describe("minion", String(interaction.candidates[0]))
			&"trainer": label = String(interaction.trainer_name)
		_blueprint.zone_captions[int(interaction.source_zone_id)] = label

func _reset_inspector() -> ModWorkshopForm:
	for child in _inspector.get_children():
		_inspector.remove_child(child)
		child.queue_free()
	var form := host._make_form()
	form.label_width = 74
	_inspector.add_child(form)
	return form

func _floor_details(form: ModWorkshopForm) -> void:
	var card := form.card("Floor details")
	card.text("Name", _floor, "name", 40)
	card.text("Description", _floor, "description", 160, true)
	var ids: Array = _floor.rooms.map(func(room: Dictionary) -> String: return String(room.id))
	var names: Array = _floor.rooms.map(func(room: Dictionary) -> String: return String(room.get("name", room.id)))
	card.choice("Entrance", _floor, "start_room", ids, names)
	card.note("Available when this mod is enabled. Check the floor in the Test tab before sharing.")
	card.button("Remove floor", _remove_floor)

func _rebuild_inspector() -> void:
	var form := _reset_inspector()
	form.changed.connect(_refresh_blueprint)
	if not _brush.is_empty():
		var brush_card := form.card("Tile brush")
		brush_card.note(RoomArtCatalog.caption(_brush), ModWorkshopForm.GOLD)
		brush_card.note(TILE_NOTES[RoomPuzzleTile.kind(_brush)] + " Click the blueprint to place it on the 64-pixel grid.")
		if RoomPuzzleTile.kind(_brush) in ["arrow", "jump"]:
			brush_card.choice("Direction", _brush_settings, "rotation", [0, 90, 180, 270], ["Right", "Down", "Left", "Up"])
		brush_card.button("Finish painting", func() -> void:
			_brush = ""
			_blueprint.paint_tiles = false
			_rebuild_inspector())
		return
	if _section == "floor":
		_floor_details(form)
		return
	var selected := _blueprint.selected_objects
	if selected.size() == 1:
		var info := _blueprint.object_info(int(selected[0]))
		if int(info.get("workshop_object", -1)) >= 0:
			_object_form(form, _room.objects[int(info.workshop_object)])
			return
		if int(info.get("workshop_feature", -1)) >= 0:
			_feature_form(form, _room.features[int(info.workshop_feature)])
			return
	if selected.size() > 1:
		var multi := form.card("%d objects selected" % selected.size())
		multi.note("Drag to move together. Shift-click adds or removes an object from the selection.")
		multi.button("Remove selected", func() -> void: _remove_objects(selected))
		return
	var card := form.card("Room setup")
	card.text("Name", _room, "name", 40)
	card.choice("Template", _room, "template", CustomFloorBuilder.TEMPLATE_OPTIONS, ["Stone", "Frost", "Blank"])
	card.number("Width", _room, "width", 700, 2400, 840)
	card.number("Height", _room, "height", 525, 2400, 580)
	card.note("Drag the green arrival marker. Click any placed item to edit it. Use the mouse wheel to zoom, and right-drag to pan.")
	card.button("Fit room", _blueprint.reset_view)
	if _floor.rooms.size() > 1: card.button("Remove room", _remove_room)

func _object_form(form: ModWorkshopForm, record: Dictionary) -> void:
	var card := form.card(RoomArtCatalog.caption(record.add))
	card.number("X", record, "x", -200, float(_room.width) + 199)
	card.number("Y", record, "y", -200, float(_room.height) + 199)
	card.number("Width ×", record, "x_scale", 0.05, 30, 1, 0.05)
	card.number("Height ×", record, "y_scale", 0.05, 30, 1, 0.05)
	if RoomPuzzleTile.kind(record.add) in ["arrow", "jump"]:
		card.choice("Direction", record, "rotation", [0, 90, 180, 270], ["Right", "Down", "Left", "Up"])
	else:
		card.number("Rotation", record, "rotation", -360, 360)
	if record.add != "collRect" and RoomPuzzleTile.kind(record.add).is_empty():
		card.toggle("Draw above player", record, "above_player")
		var layers := card.row("")
		card.button("Send back", func() -> void: _reorder_object(record, 0), layers)
		card.button("Bring front", func() -> void: _reorder_object(record, _room.objects.size() - 1), layers)
	card.button("Duplicate", func() -> void: _duplicate_objects(_blueprint.selected_objects))
	card.button("Remove object", func() -> void: _remove_objects(_blueprint.selected_objects))

func _feature_form(form: ModWorkshopForm, feature: Dictionary) -> void:
	var card := form.card(FEATURE_NAMES[feature.kind])
	card.number("X", feature, "x", 68, float(_room.width) - 69)
	card.number("Y", feature, "y", 134, float(_room.height) - 56)
	match feature.kind:
		"door":
			_door_route_fields(card, feature)
		"egg":
			card.reference("Minion", feature, "minion", "minion")
			card.number("Level", feature, "level", 1, 60, 5)
			card.note("This egg always contains this minion. Players can keep one egg per floor.")
		"trainer":
			card.text("Name", feature, "name", 24)
			card.text("Dialogue", feature, "text", 400, true)
			card.number("Coins", feature, "money", 0, 9999)
			var team := form.card("Trainer team")
			for member in feature.team:
				team.reference("Minion", member, "minion", "minion")
				team.number("Level", member, "level", 1, 60, 5)
				if feature.team.size() > 1:
					team.button("Remove minion", func() -> void:
						feature.team.erase(member)
						_refresh_after_edit())
			if feature.team.size() < 5:
				team.button("+ Minion", func() -> void:
					host._open_picker("minion", func(id: String) -> void:
						feature.team.append({"minion": id, "level": 5})
						_refresh_after_edit()))
	if feature.kind in ["door", "return", "trainer"]:
		var art := card.card("Appearance")
		if feature.kind != "trainer":
			art.choice("Mount", feature, "mount", CustomFloorBuilder.DOOR_MOUNTS, ["Auto", "Top wall", "Bottom wall", "Left wall", "Right wall", "Freestanding"])
			art.text("Sign", feature, "label", 24)
		art.note(RoomArtCatalog.caption(String(feature.art)) if feature.has("art") else "Default room art")
		art.button("Choose artwork", func() -> void:
			_pick_art("Choose feature artwork", _room_art_choices(false), func(id: String) -> void:
				feature["art"] = id
				_refresh_after_edit()))
		if feature.has("art"):
			art.button("Use default", func() -> void:
				feature.erase("art")
				_refresh_after_edit())
	card.button("Remove feature", func() -> void: _remove_objects(_blueprint.selected_objects))

func _door_route_fields(card: ModWorkshopForm, feature: Dictionary) -> void:
	var ids: Array = _floor.rooms.map(func(room: Dictionary) -> String: return String(room.id))
	var labels: Array = _floor.rooms.map(func(room: Dictionary) -> String: return String(room.get("name", room.id)))
	card.choice("Leads to", feature, "destination", ids, labels)
	var trainers: Array = _room.features.filter(func(other: Dictionary) -> bool: return other.kind == "trainer")
	var locks := [""] + trainers.map(func(trainer: Dictionary) -> String: return String(trainer.id))
	var lock_names := ["Always open"] + trainers.map(func(trainer: Dictionary) -> String: return String(trainer.name))
	card.choice("Unlock", feature, "requires_trainer", locks, lock_names)

func _pick_art(title: String, entries: Array, callback: Callable) -> void:
	var picker := ModWorkshopPicker.new()
	host._picker = picker
	picker.icon_for = func(_kind: String, id: String) -> Texture2D: return RoomArtCatalog.texture(id)
	host.add_child(picker)
	picker.open(title, entries, "room_art")
	picker.picked.connect(callback)

func _pick_object() -> void:
	_pick_art("Place an object", _room_art_choices(true), func(id: String) -> void: _place_object(id, _blueprint.view_center()))

func _room_art_choices(include_tiles_and_walls: bool) -> Array:
	var entries: Array = []
	if include_tiles_and_walls:
		entries.append({"id": "collRect", "label": "Wall (collision)", "detail": "Invisible barrier"})
	for file in UserModRepository.sprite_files(host._mod_id):
		if not file.begins_with("sprites/room_"): continue
		var sprite := "mod_art:%s/%s" % [host._mod_id, file.get_file()]
		entries.append({"id": sprite, "label": RoomArtCatalog.caption(sprite), "detail": "Imported PNG"})
	for id in RoomArtCatalog.library():
		if not include_tiles_and_walls and not RoomPuzzleTile.kind(id).is_empty(): continue
		entries.append({"id": id, "label": RoomArtCatalog.caption(id), "detail": "Tower art"})
	return entries

func _pick_brush() -> void:
	var entries: Array = []
	for kind in TILE_NOTES:
		entries.append({"id": RoomPuzzleTile.PREFIX + kind, "label": RoomPuzzleTile.LABELS[kind], "detail": TILE_NOTES[kind]})
	_pick_art("Choose a tile to paint", entries, func(id: String) -> void:
		_brush = id
		_blueprint.paint_tiles = true
		_rebuild_inspector())

func _stamp_tile(point: Vector2) -> void:
	var rotation := int(_brush_settings.rotation) if RoomPuzzleTile.kind(_brush) in ["arrow", "jump"] else 0
	var offset: Vector2 = {0: Vector2.ZERO, 90: Vector2(64, 0), 180: Vector2(64, 64), 270: Vector2(0, 64)}[rotation]
	var origin := point + offset
	for index in range(_room.objects.size() - 1, -1, -1):
		var record: Dictionary = _room.objects[index]
		if not RoomPuzzleTile.kind(record.add).is_empty():
			var tile := RoomPuzzleTile.contact({"spriteName": record.add, "xPos": record.x, "yPos": record.y,
				"xScale": record.get("x_scale", 1), "yScale": record.get("y_scale", 1), "rotation": record.get("rotation", 0)})
			if RoomPuzzleTile.contains(tile, point + Vector2(32, 32)) and is_equal_approx(float(record.get("x_scale", 1)), 1) and is_equal_approx(float(record.get("y_scale", 1)), 1):
				_room.objects.remove_at(index)
	if _room.objects.size() >= CustomFloorBuilder.MAX_OBJECTS: return host.show_message("This room is full.")
	_room.objects.append({"add": _brush, "x": origin.x, "y": origin.y, "rotation": rotation})
	host._changed()
	_refresh_blueprint()

func _import_art() -> void:
	host._pick_file("Import room artwork", ["*.png ; PNG image"], func(path: String) -> void:
		var image := Image.load_from_file(path)
		var result := UserModRepository.import_image(host._mod_id, image, path.get_file().get_basename(), true)
		if not result.ok: return host.show_message(result.message)
		_place_object("mod_art:%s/%s" % [host._mod_id, String(result.path).get_file()], _blueprint.view_center()))

func _place_object(id: String, point: Vector2) -> void:
	if _room.objects.size() >= CustomFloorBuilder.MAX_OBJECTS: return host.show_message("This room is full.")
	var texture := RoomArtCatalog.texture(id)
	var factor := 1.0
	if texture != null:
		factor = minf(1.0, float(_room.width) / texture.get_width())
		factor = minf(factor, float(_room.height) / texture.get_height())
		point -= texture.get_size() * factor * 0.5
	_brush = ""
	_blueprint.paint_tiles = false
	_room.objects.append({"add": id, "x": point.x, "y": point.y, "x_scale": factor, "y_scale": factor, "rotation": 0})
	_refresh_after_edit()
	_select_authored("workshop_object", _room.objects.size() - 1)

func _pick_feature() -> void:
	if _room.features.size() >= CustomFloorBuilder.MAX_FEATURES: return host.show_message("This room is full.")
	var entries: Array = []
	for id in FEATURE_NAMES:
		entries.append({"id": id, "label": FEATURE_NAMES[id]})
	_pick_art("Place a room feature", entries, _place_feature)

func _place_feature(kind: String) -> void:
	var point := _blueprint.view_center().clamp(Vector2(68, 134), Vector2(float(_room.width) - 69, float(_room.height) - 56))
	var feature := {"id": _local_id(_room.features, kind), "kind": kind, "x": point.x, "y": point.y}
	match kind:
		"door":
			var rooms: Array = _floor.rooms.filter(func(room: Dictionary) -> bool: return room.id != _room.id)
			if rooms.is_empty(): return host.show_message("Add another room to give this door a destination.")
			feature["destination"] = rooms[0].id
		"egg", "trainer":
			if kind == "egg" and _room.features.filter(func(other: Dictionary) -> bool: return other.kind == "egg").size() >= 9:
				return host.show_message("A room can hold up to nine eggs.")
			host._open_picker("minion", func(id: String) -> void:
				if kind == "egg":
					feature.merge({"minion": id, "level": 5})
				else:
					feature.merge({"name": "Trainer", "text": "Ready for a battle?", "money": 0, "team": [{"minion": id, "level": 5}]})
				_add_feature(feature))
			return
	_add_feature(feature)

func _add_feature(feature: Dictionary) -> void:
	_brush = ""
	_blueprint.paint_tiles = false
	_room.features.append(feature)
	_refresh_after_edit()
	_select_authored("workshop_feature", _room.features.size() - 1)

func _select_authored(field: String, index: int) -> void:
	for key in _blueprint.original_count():
		if int(_blueprint.object_info(key).get(field, -1)) == index:
			_blueprint.select_objects([key])
			_section = "room"
			_rebuild_inspector()
			return

func _move_objects(keys: Array, delta: Vector2, finished: bool) -> void:
	for key in keys:
		var info := _blueprint.object_info(int(key))
		var object := int(info.get("workshop_object", -1))
		var feature := int(info.get("workshop_feature", -1))
		if object >= 0:
			var record: Dictionary = _room.objects[object]
			record.x = float(record.x) + delta.x
			record.y = float(record.y) + delta.y
		elif feature >= 0:
			var record: Dictionary = _room.features[feature]
			record.x = clampf(float(record.x) + delta.x, 68, float(_room.width) - 69)
			record.y = clampf(float(record.y) + delta.y, 134, float(_room.height) - 56)
	if delta != Vector2.ZERO: host._changed()
	if finished: _refresh_after_edit()

func _remove_objects(keys: Array) -> void:
	var objects: Array = []
	var features: Array = []
	for key in keys:
		var info := _blueprint.object_info(int(key))
		var object := int(info.get("workshop_object", -1))
		var feature := int(info.get("workshop_feature", -1))
		if object >= 0: objects.append(_room.objects[object])
		if feature >= 0: features.append(_room.features[feature])
	for object in objects: _room.objects.erase(object)
	for feature in features:
		_room.features.erase(feature)
		for door in _room.features:
			if door.get("requires_trainer", "") == feature.id: door.erase("requires_trainer")
	_blueprint.select_objects([])
	_refresh_after_edit()

func _duplicate_objects(keys: Array) -> void:
	for key in keys:
		var index := int(_blueprint.object_info(int(key)).get("workshop_object", -1))
		if index < 0 or _room.objects.size() >= CustomFloorBuilder.MAX_OBJECTS: continue
		var copy: Dictionary = _room.objects[index].duplicate(true)
		copy.x = float(copy.x) + 16
		copy.y = float(copy.y) + 16
		_room.objects.append(copy)
	_refresh_after_edit()

func _remove_room() -> void:
	_confirm_remove("Remove %s and the doors leading to it?" % _room.name, func() -> void:
		_floor.rooms.erase(_room)
		if _floor.start_room == _room.id: _floor.start_room = _floor.rooms[0].id
		for room in _floor.rooms:
			room.features = room.features.filter(func(feature: Dictionary) -> bool: return feature.get("destination", "") != _room.id)
		host._selection["custom_room"] = 0
		_changed_and_rebuild())

func _remove_floor() -> void:
	_confirm_remove("Remove %s?" % _floor.get("name", "this floor"), func() -> void:
		host._manifest.floors.erase(_floor)
		_changed_and_rebuild())

func _reorder_object(record: Dictionary, destination: int) -> void:
	_room.objects.erase(record)
	_room.objects.insert(destination, record)
	_refresh_after_edit()
	_select_authored("workshop_object", destination)

func _confirm_remove(caption: String, callback: Callable) -> void:
	var panel := host._overlay_panel(caption, 140)
	host._button("Remove", func() -> void:
		host._close_overlay()
		callback.call(), panel)
	host._button("Cancel", host._close_overlay, panel)

func _refresh_after_edit() -> void:
	host._changed()
	_refresh_blueprint()
	_rebuild_inspector()
