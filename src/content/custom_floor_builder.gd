class_name CustomFloorBuilder
extends RefCounted

const HALL_ID := &"extended:room/side_hall"
const ICE_MANIFEST := "res://content/mods/builtin/ice_floor.json"
const ICE_ID := &"tower_ice:floor/ice"
const PLAYER_FEET := Vector2(36.5, 82.5)
const TEMPLATE_OPTIONS := ["stone", "frost", "blank"]
const DOOR_MOUNTS := ["auto", "north", "south", "west", "east", "freestanding"]
const MAX_ROOMS := 24
const MAX_OBJECTS := 500
const MAX_FEATURES := 24

static func install_builtin(catalog: ContentCatalog) -> PackedStringArray:
	if catalog.has_definition(HALL_ID): return PackedStringArray()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ICE_MANIFEST))
	if not parsed is Dictionary: return PackedStringArray(["The built-in Ice Floor manifest is missing or invalid."])
	var builder := UserModBuilder.new(parsed, catalog)
	if not builder.build(): return builder.errors
	builder.pack.source_mod = &"extended"
	for definition in builder.pack.definitions:
		definition.source_mod = &"extended"
		if definition is CustomFloorDefinition: definition.required_mod_flag = "iceFloor"
	builder.pack.definitions.append(_side_hall())
	catalog.packs.append(builder.pack)
	return catalog.rebuild_index()

static func _side_hall() -> RoomDefinition:
	var record := {"id": "hall", "name": "Side Hall", "width": 700, "height": 540, "entry_x": 350, "entry_y": 342,
		"objects": [
			{"add": "generalRoom_genericTapestry_plant", "x": 137, "y": 19},
			{"add": "generalRoom_genericTapestry_plant", "x": 493, "y": 19},
			{"add": "generalRoom_candelabra", "x": 235, "y": 88},
			{"add": "generalRoom_candelabra", "x": 418, "y": 88},
		],
		"features": [
			{"id": "custom_floors", "kind": "custom_floor_picker", "x": 350, "y": 154, "mount": "north", "label": "Custom Floors"},
			{"id": "lobby", "kind": "side_hall_exit", "x": 328, "y": 477, "mount": "south", "label": "Tower Lobby"},
		]}
	var hall := make_room("", record)
	hall.id = HALL_ID
	hall.payload.source_room_id = HALL_ID
	return hall

static func room_id(floor_id: String, local_id: String) -> StringName:
	return StringName("%s:room/%s/%s" % [floor_id.get_slice(":", 0), floor_id.get_file(), local_id])

static func encounter_id(floor_id: String, local_id: String, feature_id: String) -> StringName:
	return StringName("%s:encounter/%s/%s/%s" % [floor_id.get_slice(":", 0), floor_id.get_file(), local_id, feature_id])

static func point(record: Dictionary, x: String = "x", y: String = "y") -> Vector2:
	return Vector2(float(record.get(x, 0)), float(record.get(y, 0)))

static func reachable_rooms(start: String, rooms: Dictionary) -> Array[String]:
	var reached: Array[String] = []
	if not rooms.has(start): return reached
	reached.append(start)
	var cursor := 0
	while cursor < reached.size():
		for feature in rooms[reached[cursor]].get("features", []):
			var destination := String(feature.get("destination", ""))
			if feature.get("kind") == "door" and rooms.has(destination) and destination not in reached:
				reached.append(destination)
		cursor += 1
	return reached

static func can_stand(room: RoomDefinition, feet: Vector2) -> bool:
	var half := Vector2(22.5, 12.5)
	var body := PackedVector2Array([feet - half, feet + Vector2(half.x, -half.y), feet + half, feet + Vector2(-half.x, half.y)])
	if not Rect2(Vector2.ZERO, room.payload.dimensions).has_point(feet): return false
	for attributes in room.payload.objects:
		var sprite := String(attributes.get("spriteName", ""))
		if sprite == "puzzle_pit" and RoomPuzzleTile.contains(RoomPuzzleTile.contact(attributes), feet):
			return false
		if sprite != "collRect": continue
		var origin := Vector2(float(attributes.xPos), float(attributes.yPos))
		var extent := Vector2(float(attributes.xScale) * 100.0, float(attributes.yScale) * 50.0)
		var angle := deg_to_rad(float(attributes.rotation))
		var wall := PackedVector2Array([origin, origin + Vector2(extent.x, 0).rotated(angle),
			origin + extent.rotated(angle), origin + Vector2(0, extent.y).rotated(angle)])
		if not Geometry2D.intersect_polygons(body, wall).is_empty(): return false
	return true

static func _object(sprite: String, at: Vector2, scale: Vector2 = Vector2.ONE, rotation: float = 0.0, tint: String = "") -> Dictionary:
	return {"spriteName": sprite, "xPos": at.x, "yPos": at.y, "xScale": scale.x, "yScale": scale.y, "rotation": rotation, "tint": tint}

static func _stretch(sprite: String, at: Vector2, dimensions: Vector2, tint: String = "") -> Dictionary:
	var texture := RoomArtCatalog.texture(sprite)
	return _object(sprite, at, dimensions / texture.get_size(), 0, tint) if texture != null else {}

static func door_geometry(entry: Dictionary, at: Vector2, dimensions: Vector2, frost: bool) -> Dictionary:
	var mount := String(entry.get("mount", "auto"))
	if mount == "auto":
		mount = "freestanding"
		if at.x < 96: mount = "west"
		elif at.x > dimensions.x - 96: mount = "east"
		elif at.y < 172: mount = "north"
		elif at.y > dimensions.y - 108: mount = "south"
	var sprite := "iDoor_top" if frost else "generalRoom_specialDoor_open"
	var art_size := Vector2(96, 106)
	var label_offset := Vector2(0, -113)
	var art_position := at + Vector2(-48, -101)
	match mount:
		"north":
			at.y = 145
			art_position = Vector2(at.x - 48, 18)
			label_offset = Vector2(0, -124)
		"south":
			at.y = dimensions.y - 63
			sprite = "iDoor_down" if frost else "generalRoom_bottomDoor"
			art_size = Vector2(112, 35)
			art_position = Vector2(at.x - 56, dimensions.y - 53)
			label_offset = Vector2(0, -19)
		"west", "east":
			var west := mount == "west"
			at.x = 70 if west else dimensions.x - 70
			sprite = "iDoor_side" if frost else "generalRoom_sideDoor"
			art_size = Vector2(47 if west else -47, 112)
			art_position = Vector2(8 if west else dimensions.x - 8, at.y - 70)
			label_offset = Vector2(26 if west else -26, -57)
	var art := _stretch(String(entry.get("art", sprite)), art_position, art_size)
	return {"art": art, "contact": at, "label_position": at + label_offset}

static func _template(room: RoomDefinition, style: String) -> void:
	var dimensions := room.payload.dimensions
	var objects := room.payload.objects
	if style != "blank":
		var frost := style == "frost"
		var tile_size := Vector2(155, 155) if frost else Vector2(121, 118)
		var count := Vector2i((dimensions / tile_size).ceil())
		var tile_step := dimensions / Vector2(count)
		for y in count.y:
			for x in count.x:
				var tile := "iFloor%d" % [1 + posmod(x * 3 + y * 5, 5)] if frost else "generalRoom_floorTile"
				objects.append(_stretch(tile, Vector2(x, y) * tile_step, tile_step + Vector2.ONE))
		for x in range(0, int(dimensions.x), 200):
			objects.append(_stretch("iUp" if frost else "generalRoom_topWall", Vector2(x, 0), Vector2(201, 119)))
			objects.append(_stretch("iDown" if frost else "generalRoom_bottomWall", Vector2(x, dimensions.y - 37), Vector2(201, 37)))
		for y in range(100, int(dimensions.y - 37), 106):
			objects.append(_stretch("iSide" if frost else "generalRoom_sideWall", Vector2(0, y), Vector2(53, 107)))
			objects.append(_stretch("iSide" if frost else "generalRoom_sideWall", Vector2(dimensions.x, y), Vector2(-53, 107)))
		objects.append(_object("halfVolume_music_override", Vector2.ZERO))
		if style == "frost": objects.append(_object("riverMusic_music_override", Vector2.ZERO))
	var top := 113.0 if style != "blank" else 12.0
	var side := 42.0 if style != "blank" else 12.0
	var bottom := 37.0 if style != "blank" else 12.0
	objects.append(_object("collRect", Vector2.ZERO, Vector2(dimensions.x / 100.0, top / 50.0)))
	objects.append(_object("collRect", Vector2(0, dimensions.y - bottom), Vector2(dimensions.x / 100.0, bottom / 50.0)))
	objects.append(_object("collRect", Vector2.ZERO, Vector2(side / 100.0, dimensions.y / 50.0)))
	objects.append(_object("collRect", Vector2(dimensions.x - side, 0), Vector2(side / 100.0, dimensions.y / 50.0)))

## Builds the same geometry for the editor preview and for exploration.
static func make_room(floor_id: String, record: Dictionary) -> RoomDefinition:
	var room := RoomDefinition.new()
	var local_id := String(record.get("id", "room"))
	room.id = room_id(floor_id, local_id)
	room.custom_floor_id = StringName(floor_id)
	room.display_name = String(record.get("name", local_id))
	room.payload = RoomPayloadDefinition.new()
	room.payload.source_room_id = room.id
	room.payload.dimensions = Vector2(float(record.get("width", 840)), float(record.get("height", 580)))
	room.spawn_ids.append(&"start")
	room.spawn_positions["start"] = point(record, "entry_x", "entry_y") - PLAYER_FEET
	var template := String(record.get("template", "stone"))
	_template(room, template)
	for index in record.get("objects", []).size():
		var entry: Dictionary = record.objects[index]
		var sprite := String(entry.get("add", ""))
		var obj := _object(sprite, point(entry), Vector2(float(entry.get("x_scale", 1)), float(entry.get("y_scale", 1))), float(entry.get("rotation", 0)))
		obj["workshop_object"] = index
		obj["above_player"] = bool(entry.get("above_player", false))
		room.payload.objects.append(obj)
	var egg_slot := 0
	for index in record.get("features", []).size():
		var entry: Dictionary = record.features[index]
		var at := point(entry)
		var kind := String(entry.get("kind", ""))
		var feature_id := String(entry.get("id", "feature%d" % index))
		var interaction := {"id": StringName(feature_id), "kind": StringName(kind), "source_zone_id": 10 + index}
		var zone_size := Vector2(92, 84)
		match kind:
			"door", "return", "custom_floor_picker", "side_hall_exit":
				var geometry := door_geometry(entry, at, room.payload.dimensions, template == "frost")
				var locked := String(entry.get("requires_trainer", ""))
				var door: Dictionary = geometry.art
				at = geometry.contact
				if not locked.is_empty():
					door["custom_lock"] = encounter_id(floor_id, local_id, locked)
				room.payload.objects.append(door)
				interaction["kind"] = &"custom_door" if kind == "door" else &"custom_floor_return" if kind == "return" else StringName(kind)
				interaction["world_label"] = String(entry.get("label", ""))
				interaction["world_label_position"] = geometry.label_position
				if kind == "door":
					var target := room_id(floor_id, String(entry.get("destination", "")))
					var route := {"transition_id": index, "target_room_id": target, "target_spawn_id": &"start"}
					if not String(entry.get("requires_trainer", "")).is_empty():
						route["requires_encounter"] = encounter_id(floor_id, local_id, String(entry.requires_trainer))
					room.exits.append(route)
					interaction.merge(route)
			"trainer":
				var id := encounter_id(floor_id, local_id, feature_id)
				room.encounter_ids.append(id)
				interaction["encounter_id"] = id
				interaction["trainer_name"] = String(entry.get("name", "Trainer"))
				interaction["first_visit_text"] = String(entry.get("text", "A trainer challenges you.")).left(400)
				var trainer_art := String(entry.get("art", "iSage" if template == "frost" else "iNPC_bluey"))
				room.payload.objects.append(_stretch(trainer_art, at + Vector2(-31, -74), Vector2(62, 78)))
			"egg":
				if egg_slot >= 9: continue
				var egg_sprite := _object("eggery_egg%d" % egg_slot, at - Vector2(27, 58), Vector2(0.58, 0.58))
				room.payload.objects.append(egg_sprite)
				interaction.merge({"kind": &"egg_pick", "source_zone_id": egg_slot, "candidates": [String(entry.get("minion", ""))], "weights": [100], "level": int(entry.get("level", 5))}, true)
				egg_slot += 1
				zone_size = Vector2(78, 70)
			"heal_party":
				room.payload.objects.append(_object("generalRoom_healStone", at - Vector2(38, 36), Vector2(0.7, 0.7)))
			_:
				continue
		var marker := _object("buttonZoneObject%d" % int(interaction.source_zone_id), at - zone_size * 0.5, zone_size / 100.0)
		marker["workshop_feature"] = index
		room.payload.objects.append(marker)
		room.interactions.append(interaction)
	return room

static func valid_local_id(id: String) -> bool:
	return id.length() <= 32 and RegEx.create_from_string("^[a-z][a-z0-9_]*$").search(id) != null
