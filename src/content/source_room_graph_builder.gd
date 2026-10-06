class_name SourceRoomGraphBuilder
extends RefCounted

const PLAYER_ENTRY_OFFSET := Vector2(15.0, 66.0)

static func load_rooms(graph_path: String, default_height_thresholds: Dictionary = {}) -> Array[RoomDefinition]:
	var result: Array[RoomDefinition] = []
	if graph_path.is_empty():
		return result
	var file := FileAccess.open(graph_path, FileAccess.READ)
	if file == null:
		push_error("Cannot read source room graph %s" % graph_path)
		return result
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or not parsed.get("rooms", []) is Array:
		push_error("Source room graph %s is not a room-list object" % graph_path)
		return result
	for room_data in parsed.rooms:
		if not room_data is Dictionary:
			continue
		var room := RoomDefinition.new()
		room.id = StringName(room_data.get("id", ""))
		room.display_name = String(room_data.get("display_name", room.id))
		room.legacy_class_name = String(room_data.get("legacy_class_name", ""))
		room.source_location = String(room_data.get("source_location", ""))
		room.source_room_symbol = StringName(room_data.get("source_symbol", ""))
		room.source_payload_path = String(room_data.get("source_payload", ""))
		room.encounter_ids.assign(_string_names(room_data.get("encounter_ids", [])))
		room.minimap_metadata = {
			"floor_index": int(parsed.get("floor_index", 0)),
			"room_index": int(room_data.get("room_index", -1)),
			"source_payload": room.source_payload_path,
		}
		var payload := room.ensure_payload(default_height_thresholds)
		if payload == null:
			continue
		room.minimap_metadata["source_dimensions"] = payload.dimensions
		for raw_exit in room_data.get("exits", []):
			if not raw_exit is Dictionary:
				continue
			var exit_data: Dictionary = raw_exit.duplicate(true)
			exit_data["target_room_id"] = StringName(exit_data.get("target_room_id", ""))
			exit_data["target_spawn_id"] = StringName(exit_data.get("target_spawn_id", ""))
			# ExpertRoomTransitionObject.OnColl is active only in hard mode.
			if int(exit_data.get("transition_id", -1)) == 99:
				exit_data["requires_tower_mode"] = "hard"
			room.exits.append(exit_data)
		for attributes in payload.objects:
			var sprite_name := String(attributes.get("spriteName", ""))
			if sprite_name == "expert_entryObject":
				room.spawn_ids.append(&"entry-expert")
				room.spawn_positions["entry-expert"] = _flash_player_destination(attributes)
				continue
			if not sprite_name.begins_with("entryObject"):
				continue
			var suffix := sprite_name.trim_prefix("entryObject")
			var numeric_prefix := ""
			for character in suffix:
				if not String(character).is_valid_int():
					break
				numeric_prefix += String(character)
			if numeric_prefix.is_empty():
				continue
			var spawn_id := StringName("entry-%d" % int(numeric_prefix))
			room.spawn_ids.append(spawn_id)
			room.spawn_positions[String(spawn_id)] = _flash_player_destination(attributes)
			var direction := _entry_direction(suffix.trim_prefix(numeric_prefix))
			if not direction.is_empty():
				room.spawn_directions[String(spawn_id)] = direction
		for raw_spawn in room_data.get("source_spawns", []):
			if not raw_spawn is Dictionary:
				continue
			var spawn_id := StringName(raw_spawn.get("id", ""))
			var source_marker := String(raw_spawn.get("source_marker", ""))
			for attributes in payload.objects:
				if String(attributes.get("spriteName", "")) != source_marker:
					continue
				room.spawn_ids.append(spawn_id)
				room.spawn_positions[String(spawn_id)] = _flash_player_destination(attributes)
				break
			if not room.spawn_positions.has(String(spawn_id)):
				push_error("Room %s source spawn marker %s is missing from its payload" % [room.id, source_marker])
		if room_data.has("start_spawn_source_marker"):
			var source_marker_name := String(room_data.get("start_spawn_source_marker", ""))
			var start_marker_found := false
			for attributes in payload.objects:
				if String(attributes.get("spriteName", "")) != source_marker_name:
					continue
				room.spawn_ids.push_front(&"start")
				room.spawn_positions["start"] = _flash_player_destination(attributes)
				var marker_suffix := source_marker_name.trim_prefix("entryObject")
				var marker_numeric_prefix := ""
				for character in marker_suffix:
					if not String(character).is_valid_int():
						break
					marker_numeric_prefix += String(character)
				room.spawn_directions["start"] = _entry_direction(marker_suffix.trim_prefix(marker_numeric_prefix))
				start_marker_found = true
				break
			if not start_marker_found:
				push_error("Room %s start spawn marker %s is missing from its source payload" % [room.id, source_marker_name])
		elif room_data.has("start_position"):
			var start_position: Variant = room_data.get("start_position", [])
			if start_position is Array and start_position.size() >= 2:
				room.spawn_ids.push_front(&"start")
				room.spawn_positions["start"] = Vector2(float(start_position[0]), float(start_position[1]))
		for raw_interaction in room_data.get("interactions", []):
			if raw_interaction is Dictionary:
				var interaction: Dictionary = raw_interaction.duplicate(true)
				interaction["id"] = StringName(interaction.get("id", ""))
				interaction["kind"] = StringName(interaction.get("kind", ""))
				if interaction.has("encounter_id"):
					interaction["encounter_id"] = StringName(interaction.encounter_id)
				if room.source_room_symbol.begins_with("TopDown.Levels.MainTower.ExpertRoom_") and StringName(interaction.get("kind", "")) == &"trainer":
					interaction["requires_tower_mode"] = "hard"
				for field in ["source_position", "source_scale"]:
					var coordinates: Variant = interaction.get(field)
					if coordinates is Array and coordinates.size() >= 2:
						interaction[field] = Vector2(float(coordinates[0]), float(coordinates[1]))
				room.interactions.append(interaction)
		_bind_source_doors(room, payload)
		result.append(room)
	for raw_external_transition in parsed.get("external_transitions", []):
		if not raw_external_transition is Dictionary:
			continue
		var source_room_id := StringName(raw_external_transition.get("room_id", ""))
		for room in result:
			if room.id == source_room_id:
				room.external_transitions.append(raw_external_transition.duplicate(true))
				break
	return result

static func _source_bounds(attributes: Dictionary, base_size: Vector2) -> Rect2:
	var origin := Vector2(float(attributes.get("xPos", 0.0)), float(attributes.get("yPos", 0.0)))
	var scaled := base_size * Vector2(float(attributes.get("xScale", 1.0)), float(attributes.get("yScale", 1.0)))
	var angle := deg_to_rad(float(attributes.get("rotation", 0.0)))
	var bounds := Rect2(origin, Vector2.ZERO)
	for corner in [Vector2(scaled.x, 0.0), scaled, Vector2(0.0, scaled.y)]:
		bounds = bounds.expand(origin + corner.rotated(angle))
	return bounds

static func _bind_source_doors(room: RoomDefinition, payload: RoomPayloadDefinition) -> void:
	# BaseTopDownLevel attaches BOTH source door classes to interaction ID 2.
	# Their solid 100x300 marker overlaps the portal they protect. Derive these
	# bindings from the actual payload, not a floor-specific hallway name.
	var doors: Array[Dictionary] = []
	var portals: Array[Dictionary] = []
	for attributes in payload.objects:
		var sprite := String(attributes.get("spriteName", ""))
		if sprite in ["regularDoor", "regularDoor_eggery"]: doors.append(attributes)
		elif sprite.begins_with("roomTransitionObject") and sprite.trim_prefix("roomTransitionObject").is_valid_int(): portals.append(attributes)
	# Older graphs gated the following hallway's exit instead of the source
	# doorway. Rebuild only these two flags, retaining other authored gates.
	for exit_data in room.exits:
		if String(exit_data.get("requires_progression_flag", "")) in ["boss_door_unlocked", "eggery_door_unlocked"]:
			exit_data.erase("requires_progression_flag")
	for attributes in doors:
		var eggery := String(attributes.spriteName) == "regularDoor_eggery"
		var kind := &"unlock_eggery_door" if eggery else &"unlock_boss_door"
		if not room.interactions.any(func(interaction: Dictionary) -> bool: return StringName(interaction.get("kind", "")) == kind):
			room.interactions.append({"id": StringName("%s-source-%s-door" % [room.id, "eggery" if eggery else "boss"]), "kind": kind, "source_zone_id": 2, "required_floor_keys": 3, "locked_text": "I need more keys to open that door." if eggery else "I need three keys to open that door."})
		var door_bounds := _source_bounds(attributes, Vector2(100.0, 300.0))
		var matches: Array[Dictionary] = []
		for portal in portals:
			if door_bounds.intersects(_source_bounds(portal, Vector2(67.0, 67.0)), true): matches.append(portal)
		if matches.size() != 1:
			push_error("Room %s source door must overlap exactly one portal, found %d" % [room.id, matches.size()])
			continue
		var transition_id := int(String(matches[0].spriteName).trim_prefix("roomTransitionObject"))
		for exit_data in room.exits:
			if int(exit_data.get("transition_id", -1)) == transition_id:
				exit_data["requires_progression_flag"] = "eggery_door_unlocked" if eggery else "boss_door_unlocked"

static func _flash_player_destination(attributes: Dictionary) -> Vector2:
	return Vector2(float(attributes.get("xPos", 0.0)), float(attributes.get("yPos", 0.0))) - PLAYER_ENTRY_OFFSET

static func _entry_direction(marker_suffix: String) -> String:
	var direction := marker_suffix.trim_prefix("_").to_lower()
	return direction if direction in ["up", "down", "left", "right"] else ""

static func _string_names(values: Array) -> Array[StringName]:
	var result: Array[StringName] = []
	for value in values:
		result.append(StringName(value))
	return result
