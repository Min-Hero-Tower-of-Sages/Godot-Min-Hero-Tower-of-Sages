class_name CampaignMinimapView
extends Control

signal closed
signal open_requested

const ART_ROOT := "res://content/base/art/source_symbols/"
const SOURCE_MAP_BACKGROUND := "190_Utilities.SpriteHandler_miniMap_background.png"
const SOURCE_ROOM_PIECE := "233_Utilities.SpriteHandler_miniMap_room1.png"
const SOURCE_HALLWAY_VERTICAL := "373_Utilities.SpriteHandler_miniMap_hwaySmall_vert.png"
const SOURCE_HALLWAY_HORIZONTAL := "405_Utilities.SpriteHandler_miniMap_hwaySmall_hori.png"
const SOURCE_EGGERY_OVERLAY := "890_Utilities.SpriteHandler_miniMap_eggeryOverlay.png"
const SOURCE_EXIT_BUTTON := "666_Utilities.SpriteHandler_menus_exitButton.png"
const AUTHORED_LAYOUTS = preload("res://content/base/ui/source_minimap_layouts.tres")
var _catalog: ContentCatalog
var _state: CampaignState
var _campaign: CampaignDefinition
var _floor_index := 0
var _embedded := false
var _room_by_source_index: Dictionary = {}
var _room_by_id: Dictionary = {}
var _map_piece_nodes: Array[Dictionary] = []
var _eggery_piece: TextureRect
var _map_scaler: Control
var _map_root: Control
var _close_button: Button
var _presented_room_id: StringName
var _room_transition: Tween
var _base_map_scale := 1.0
## Multiplayer: a colored dot on the room of every other player on this floor.
var _player_marker_layer: Control
var _player_marker_timer := 0.0
const PLAYER_MARKER_REFRESH := 0.25
const PLAYER_MARKER_SIZE := 7.0

func configure(catalog: ContentCatalog, state: CampaignState, campaign: CampaignDefinition, embedded: bool = false) -> void:
	var current_room := catalog.get_definition(state.current_room_id) as RoomDefinition if catalog != null and state != null else null
	var next_floor := int(current_room.minimap_metadata.get("floor_index", state.progression.get("floor_index", 0))) if current_room != null else int(state.progression.get("floor_index", 0)) if state != null else -1
	var can_reuse := embedded == _embedded and catalog == _catalog and campaign == _campaign and next_floor == _floor_index and is_instance_valid(_map_root)
	_catalog = catalog
	_state = state
	_campaign = campaign
	_embedded = embedded
	mouse_filter = Control.MOUSE_FILTER_IGNORE if embedded else Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE if embedded else Control.FOCUS_ALL
	if embedded:
		release_focus()
	if is_inside_tree():
		if can_reuse:
			if _presented_room_id != state.current_room_id:
				_entered_new_room(current_room)
		else:
			_build_view()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE if _embedded else Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE if _embedded else Control.FOCUS_ALL
	if not _embedded:
		grab_focus()
	if _catalog != null and _state != null and _campaign != null:
		_build_view()

func _process(delta: float) -> void:
	_player_marker_timer += delta
	if _player_marker_timer >= PLAYER_MARKER_REFRESH:
		_player_marker_timer = 0.0
		_refresh_player_markers()

## Other players' rooms, from the location each player reports (it survives
## battles, unlike presence). Only rooms of the floor this map shows count.
func _refresh_player_markers() -> void:
	if not is_instance_valid(_player_marker_layer):
		return
	for child in _player_marker_layer.get_children():
		child.queue_free()
	var net: Node = get_node_or_null("/root/NetSession")
	if net == null or not net.is_active():
		return
	var per_room: Dictionary = {}
	for peer_id in net.other_player_ids():
		var room_id := String(net.player_location(peer_id).get("room", ""))
		var room := _room_by_id.get(room_id) as RoomDefinition
		if room == null:
			continue
		var room_index := int(room.minimap_metadata.get("room_index", -1))
		for entry in _map_piece_nodes:
			var piece := entry.node as TextureRect
			if int(entry.room_index) != room_index or piece.modulate.a <= 0.01:
				continue
			var count := int(per_room.get(room_index, 0))
			per_room[room_index] = count + 1
			var dot := ColorRect.new()
			var size := PLAYER_MARKER_SIZE / maxf(0.01, _map_scaler.scale.x)
			dot.size = Vector2.ONE * size
			dot.position = piece.position + piece.size * 0.5 - dot.size * 0.5 + Vector2(size * 1.2 * float(count), 0.0)
			dot.color = net.player_color(peer_id)
			dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			dot.tooltip_text = net.player_name(peer_id)
			_player_marker_layer.add_child(dot)
			break

func _unhandled_key_input(event: InputEvent) -> void:
	if _embedded:
		return
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
		closed.emit()
		get_viewport().set_input_as_handled()

func _build_view() -> void:
	if _room_transition != null and _room_transition.is_running():
		_room_transition.kill()
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_map_piece_nodes.clear()
	_eggery_piece = null
	if _catalog == null or _state == null or _campaign == null:
		return
	var viewport_size := get_viewport_rect().size
	if not _embedded:
		var shade := ColorRect.new()
		shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		shade.color = Color(0.0, 0.0, 0.0, 0.78)
		shade.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(shade)
	var current_room := _catalog.get_definition(_state.current_room_id) as RoomDefinition
	_floor_index = int(current_room.minimap_metadata.get("floor_index", _state.progression.get("floor_index", 0))) if current_room != null else int(_state.progression.get("floor_index", 0))
	_build_room_lookup()
	# Source uses a single 0..30 layout table for both tower modes.
	var source_floor_index := _floor_index % 31
	var layout: Dictionary = AUTHORED_LAYOUTS.layout_for_floor(source_floor_index)
	var map_piece_data: Array = []
	for piece in layout.get("pieces", []):
		map_piece_data.append([piece.sprite_name, piece.x, piece.y, piece.room_index, piece.group_id, piece.is_eggery, piece.override_scale])
	var authored_map_available := not map_piece_data.is_empty()
	if not authored_map_available:
		layout = {"position": Vector2.ZERO, "scale": 1.0, "pieces": []}
	var background_texture := SourceMenuArt.texture("miniMap_background")
	if background_texture == null:
		return
	var modal_scale := minf(viewport_size.x / 700.0, viewport_size.y / 525.0)
	var map_scale := 1.0 if _embedded else 2.2 * modal_scale
	var source_map_size := Vector2(background_texture.get_size())
	_map_root = Control.new()
	_map_root.position = Vector2.ZERO if _embedded else viewport_size * 0.5 - source_map_size * map_scale * 0.5
	_map_root.size = source_map_size
	_map_root.scale = Vector2.ONE * map_scale
	add_child(_map_root)
	if _embedded:
		_map_root.mouse_filter = Control.MOUSE_FILTER_STOP
		_map_root.gui_input.connect(_on_embedded_map_input)
	var background := TextureRect.new()
	background.texture = background_texture
	background.size = source_map_size
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_SCALE
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_root.add_child(background)
	_map_scaler = Control.new()
	_map_scaler.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var map_position: Vector2 = layout.get("position", Vector2.ZERO)
	var base_scale := float(layout.get("scale", 1.0))
	_base_map_scale = base_scale
	_map_scaler.position = map_position + Vector2(7.0, 7.0)
	_map_scaler.scale = Vector2.ONE * base_scale
	_map_scaler.size = source_map_size
	_map_root.add_child(_map_scaler)
	for piece_data in map_piece_data:
		var asset_name := String(piece_data[0])
		var room_index := int(piece_data[3])
		var group_id := int(piece_data[4])
		var is_eggery := bool(piece_data[5])
		var room := _room_by_source_index.get(room_index) as RoomDefinition
		var texture := SourceMenuArt.texture(asset_name)
		if texture == null:
			continue
		var piece := TextureRect.new()
		piece.texture = texture
		piece.position = Vector2(float(piece_data[1]), float(piece_data[2]))
		piece.size = texture.get_size()
		piece.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		piece.mouse_filter = Control.MOUSE_FILTER_STOP if room != null and not _embedded else Control.MOUSE_FILTER_IGNORE
		piece.tooltip_text = _room_tooltip(room) if room != null else "Unknown source room"
		piece.modulate = Color(1.0, 1.0, 1.0, 0.8)
		_map_scaler.add_child(piece)
		_map_piece_nodes.append({"node": piece, "room_index": room_index, "group_id": group_id, "override_scale": float(piece_data[6]), "is_eggery": is_eggery})
		if is_eggery:
			_eggery_piece = TextureRect.new()
			_eggery_piece.texture = SourceMenuArt.texture("miniMap_eggeryOverlay")
			_eggery_piece.position = piece.position
			_eggery_piece.size = _eggery_piece.texture.get_size() if _eggery_piece.texture != null else piece.size
			_eggery_piece.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			_eggery_piece.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_eggery_piece.modulate.a = piece.modulate.a
			_map_scaler.add_child(_eggery_piece)
	_player_marker_layer = Control.new()
	_player_marker_layer.name = "PlayerMarkers"
	_player_marker_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_scaler.add_child(_player_marker_layer)
	_entered_new_room(current_room)
	if _embedded:
		return
	var title_text := "Floor %d map" % (_floor_index + 1)
	var title := Label.new()
	title.text = title_text
	title.position = Vector2(0.0, maxf(20.0, viewport_size.y * 0.5 - 205.0 * modal_scale))
	title.size = Vector2(viewport_size.x, 38.0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color8(255, 228, 149))
	add_child(title)
	var legend := Label.new()
	legend.text = "Visited rooms are brighter. Blue marks your current room. Hover over a room to see its contents." if authored_map_available else "This floor's source minimap data has not been recovered yet."
	legend.position = Vector2(35.0, minf(viewport_size.y - 85.0, _map_root.position.y + source_map_size.y * map_scale + 14.0))
	legend.size = Vector2(viewport_size.x - 70.0, 28.0)
	legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	legend.add_theme_font_size_override("font_size", 14)
	legend.add_theme_color_override("font_color", Color8(225, 224, 219))
	add_child(legend)
	if not authored_map_available:
		var unavailable := Label.new()
		unavailable.text = "No authored map layout is available for Floor %d." % (_floor_index + 1)
		unavailable.position = Vector2(_map_root.position.x + 12.0, _map_root.position.y + source_map_size.y * map_scale * 0.43)
		unavailable.size = Vector2(source_map_size.x * map_scale - 24.0, 50.0)
		unavailable.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		unavailable.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		unavailable.add_theme_font_size_override("font_size", 16)
		unavailable.add_theme_color_override("font_color", Color8(235, 232, 223))
		add_child(unavailable)
	_close_button = Button.new()
	_close_button.text = "Close map"
	_close_button.position = Vector2(viewport_size.x * 0.5 - 66.0, viewport_size.y - 48.0)
	_close_button.size = Vector2(132.0, 34.0)
	_close_button.pressed.connect(func() -> void: closed.emit())
	add_child(_close_button)
	var exit_texture := SourceMenuArt.texture("menus_exitButton")
	if exit_texture != null:
		var icon := TextureButton.new()
		icon.texture_normal = exit_texture
		icon.texture_hover = exit_texture
		icon.texture_pressed = exit_texture
		icon.position = _map_root.position + Vector2(source_map_size.x * map_scale - exit_texture.get_width() * 0.6, -exit_texture.get_height() * 0.3)
		icon.scale = Vector2.ONE * modal_scale
		icon.pressed.connect(func() -> void: closed.emit())
		add_child(icon)

func _build_room_lookup() -> void:
	_room_by_source_index.clear()
	_room_by_id.clear()
	var floor_rooms: Array = []
	for floor_data in _campaign.floors:
		if int(floor_data.get("floor_index", -1)) == _floor_index:
			floor_rooms = floor_data.get("room_ids", [])
			break
	for room_id in floor_rooms:
		var room := _catalog.get_definition(StringName(room_id)) as RoomDefinition
		if room == null:
			continue
		_room_by_id[String(room.id)] = room
		var source_index := int(room.minimap_metadata.get("room_index", -1))
		if source_index >= 0:
			_room_by_source_index[source_index] = room

func _entered_new_room(room: RoomDefinition) -> void:
	if room == null:
		return
	_presented_room_id = room.id
	if _room_transition != null and _room_transition.is_running():
		_room_transition.kill()
	var room_index := int(room.minimap_metadata.get("room_index", -1))
	var group := 0
	var target_scale := _base_map_scale
	for entry in _map_piece_nodes:
		if int(entry.room_index) == room_index:
			group = int(entry.group_id)
			if float(entry.override_scale) != -99.0:
				target_scale = float(entry.override_scale)
			break
	_room_transition = create_tween().set_parallel(true)
	_room_transition.tween_property(_map_scaler, "scale", Vector2.ONE * target_scale, 0.05).set_delay(0.5)
	for entry in _map_piece_nodes:
		var piece := entry.node as TextureRect
		var opacity := 1.0 if int(entry.group_id) == group else 0.0
		_room_transition.tween_property(piece, "modulate", Color(1, 1, 1, opacity), 0.05).set_delay(0.5)
		if bool(entry.is_eggery) and is_instance_valid(_eggery_piece):
			_room_transition.tween_property(_eggery_piece, "modulate:a", opacity, 0.05).set_delay(0.5)
		if int(entry.room_index) == room_index:
			_room_transition.tween_property(piece, "modulate", Color8(51, 153, 255), 0.05).set_delay(0.55)

func _current_group(map_piece_data: Array, room_index: int) -> int:
	for piece_data in map_piece_data:
		if int(piece_data[3]) == room_index:
			return int(piece_data[4])
	return 0

func _room_visited(room: RoomDefinition) -> bool:
	if room == null:
		return false
	var room_state: Dictionary = _state.room_state.get(String(room.id), {})
	return bool(room_state.get("visited", false)) or room.id == _state.current_room_id

func _room_tooltip(room: RoomDefinition) -> String:
	var visited := _room_visited(room)
	var details := "%s\n%s" % [room.display_name, "Visited" if visited else "Not visited"]
	for interaction in room.interactions:
		var kind := String(interaction.get("kind", ""))
		var label := ""
		match kind:
			"trainer": label = "Trainer"
			"map_station": label = "Map station"
			"heal_party": label = "Healing room"
			"egg_pick": label = "Hatchery"
			"claim_room_chest", "claim_room_gem_chest": label = "Treasure chest"
			"grand_sage": label = "Grand Sage"
			"unlock_eggery_door": label = "Hatchery door"
		if not label.is_empty():
			details += "\n" + label
	return details

func _on_embedded_map_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		open_requested.emit()
		accept_event()
