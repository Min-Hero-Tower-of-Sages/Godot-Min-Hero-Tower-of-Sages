class_name RoomDefinition
extends ContentDefinition

@export_file("*.tscn") var scene_path: String
@export_file("*.json") var source_payload_path: String
@export var payload: RoomPayloadDefinition
@export var source_room_symbol: StringName
@export var encounter_ids: Array[StringName] = []
@export var exits: Array[Dictionary] = []
@export var external_transitions: Array[Dictionary] = []
@export var spawn_ids: Array[StringName] = []
@export var spawn_positions: Dictionary = {}
@export var spawn_directions: Dictionary = {}
@export var interactions: Array[Dictionary] = []
@export var minimap_metadata: Dictionary = {}

func ensure_payload(default_height_thresholds: Dictionary = {}) -> RoomPayloadDefinition:
	if payload != null:
		return payload
	if source_payload_path.is_empty():
		push_warning("Room %s has no payload resource or normalized payload path" % id)
		return null
	var file := FileAccess.open(source_payload_path, FileAccess.READ)
	if file == null:
		push_warning("Room %s cannot read source payload %s" % [id, source_payload_path])
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or StringName(parsed.get("id", "")) != id:
		push_warning("Room %s source payload identity does not match" % id)
		return null
	var source_data: Dictionary = parsed
	var xml: Dictionary = source_data.get("xml", {})
	var root_attributes: Dictionary = xml.get("attributes", {})
	var dimensions := Vector2(float(root_attributes.get("width", 0.0)), float(root_attributes.get("height", 0.0)))
	if dimensions.x <= 0.0 or dimensions.y <= 0.0:
		push_warning("Room %s source payload has invalid dimensions" % id)
		return null
	var objects: Array[Dictionary] = []
	for child in xml.get("children", []):
		if String(child.get("tag", "")) != "levelObject":
			continue
		var attributes: Dictionary = (child.get("attributes", {}) as Dictionary).duplicate(true)
		objects.append(attributes)
	var identity: Dictionary = source_data.get("asset_identity", {})
	var loaded := RoomPayloadDefinition.new()
	loaded.source_room_id = id
	loaded.source_symbol = StringName(identity.get("class_name", source_room_symbol))
	loaded.source_binary = String(source_data.get("source_binary", ""))
	loaded.dimensions = dimensions
	loaded.objects = objects
	loaded.source_height_thresholds = default_height_thresholds.duplicate(true)
	payload = loaded
	return payload
