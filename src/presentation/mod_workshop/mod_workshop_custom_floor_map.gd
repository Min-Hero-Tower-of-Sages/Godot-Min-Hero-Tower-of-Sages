class_name ModWorkshopCustomFloorMap
extends GraphEdit

signal room_pressed(room_id: String)
signal room_activated(room_id: String)
signal room_moved(room_id: String, map_position: Vector2)
signal door_requested(from_room: String, to_room: String)

const CARD_SIZE := Vector2(150, 72)
const CELL_SIZE := Vector2(212, 118)
const COLUMNS := 2
const PORT_COLOR := Color8(160, 199, 229)

var _cards: Dictionary = {}
var _rooms: Array = []
var _floor: Dictionary = {}

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(260, 200)
	clip_contents = true
	show_menu = false
	minimap_enabled = false
	snapping_enabled = true
	snapping_distance = 12
	zoom_min = 0.18
	zoom_max = 1.5
	connection_lines_curvature = 0.3
	add_theme_stylebox_override("panel", ModWorkshopForm.inset_style())
	add_theme_color_override("grid_major", Color8(103, 119, 146, 93))
	add_theme_color_override("grid_minor", Color8(103, 119, 146, 34))
	node_selected.connect(func(node: Node) -> void: room_pressed.emit(String(node.name)))
	connection_request.connect(func(from: StringName, _out: int, to: StringName, _in: int) -> void:
		if from != to: door_requested.emit(String(from), String(to)))

static func default_position(index: int) -> Vector2:
	return Vector2(index % COLUMNS, floori(float(index) / COLUMNS)) * CELL_SIZE

func show_floor(floor_record: Dictionary, selected: String) -> void:
	_floor = floor_record
	_rooms = floor_record.rooms
	for index in _rooms.size():
		var room: Dictionary = _rooms[index]
		var card := GraphNode.new()
		card.name = String(room.id)
		card.position_offset = _saved_position(room, index)
		card.custom_minimum_size = CARD_SIZE
		card.size = CARD_SIZE
		var style := ModWorkshopForm.card_style()
		style.bg_color = ModWorkshopForm.CHARCOAL
		card.add_theme_stylebox_override("panel", style)
		card.add_theme_stylebox_override("panel_selected", ModWorkshopForm.flat(ModWorkshopForm.CHARCOAL_LIGHT, Color8(235, 239, 247), 4))
		card.add_theme_stylebox_override("titlebar", ModWorkshopForm.button_style(ModWorkshopForm.SLATE))
		card.add_theme_stylebox_override("titlebar_selected", ModWorkshopForm.button_style(Color8(108, 127, 151), Color8(235, 239, 247)))
		var title := card.get_titlebar_hbox().get_child(0) as Label
		title.add_theme_font_size_override("font_size", 13)
		title.clip_text = true
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var metadata := Label.new()
		metadata.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		metadata.add_theme_font_size_override("font_size", 12)
		metadata.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(metadata)
		card.set_slot(0, true, 0, PORT_COLOR, true, 0, ModWorkshopForm.GOLD)
		card.dragged.connect(func(_from: Vector2, to: Vector2) -> void: room_moved.emit(String(room.id), to))
		card.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
				room_activated.emit(String(room.id)))
		_cards[String(room.id)] = card
		add_child(card)
		card.selected = String(room.id) == selected
	refresh_routes()

static func _saved_position(room: Dictionary, index: int) -> Vector2:
	var fallback := default_position(index)
	return Vector2(float(room.get("map_x", fallback.x)), float(room.get("map_y", fallback.y))).clamp(Vector2(-12000, -12000), Vector2(12000, 12000))

func refresh_routes() -> void:
	clear_connections()
	var records: Dictionary = {}
	for room in _rooms: records[String(room.id)] = room
	var reachable := CustomFloorBuilder.reachable_rooms(String(_floor.get("start_room", "")), records)
	for room in _rooms:
		var id := String(room.id)
		var card := _cards[id] as GraphNode
		var caption := String(room.get("name", id))
		var metadata := card.get_child(0) as Label
		card.title = caption
		card.tooltip_text = caption + "\nDouble-click to edit this room"
		var badges := PackedStringArray()
		if id == String(_floor.get("start_room", "")): badges.append("Entrance")
		var doors := 0
		for feature in room.get("features", []):
			if feature.kind == "return" and "Side Hall exit" not in badges: badges.append("Side Hall exit")
			if feature.kind != "door": continue
			doors += 1
			var target := String(feature.get("destination", ""))
			if target != id and _cards.has(target) and not is_node_connected(id, 0, target, 0):
				connect_node(id, 0, target, 0)
		if badges.is_empty(): badges.append("%d %s" % [doors, "Door" if doors == 1 else "Doors"])
		metadata.text = " / ".join(badges) if reachable.has(id) else "Unreachable"
		metadata.add_theme_color_override("font_color", ModWorkshopForm.GOLD if reachable.has(id) else ModWorkshopFloorMap.COLOR_LOST)

func fit_rooms() -> void:
	if _cards.is_empty(): return
	var bounds := Rect2()
	for card: GraphNode in _cards.values():
		var rect := Rect2(card.position_offset, card.size)
		bounds = rect if bounds.size == Vector2.ZERO else bounds.merge(rect)
	var available := size - Vector2(90, 60)
	zoom = clampf(minf(available.x / bounds.size.x, available.y / bounds.size.y), zoom_min, 1.05)
	scroll_offset = bounds.get_center() * zoom - size * 0.5
