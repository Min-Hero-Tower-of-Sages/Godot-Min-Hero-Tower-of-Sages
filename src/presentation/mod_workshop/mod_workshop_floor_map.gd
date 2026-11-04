class_name ModWorkshopFloorMap
extends Control

## One tower floor drawn like the in-game minimap, with an arrow for every
## door. Rooms this mod edits are marked in gold and rooms the player could
## no longer reach from the floor's entrance are marked in red.

signal room_pressed(room_id: String)
signal room_activated(room_id: String)

const COLOR_EDGE := Color8(122, 158, 196)
const COLOR_EDITED := Color8(246, 219, 150)
const COLOR_LOST := Color8(240, 110, 100)
const KIND_COLORS := {"trainer": Color8(236, 96, 88), "egg_pick": Color8(246, 214, 104), "heal_party": Color8(112, 205, 128), "gem_shop": Color8(104, 164, 255), "gem_combiner": Color8(104, 164, 255), "minion_storage": Color8(104, 164, 255), "grand_sage": Color8(200, 140, 255), "unlock_boss_door": Color8(255, 170, 70), "unlock_eggery_door": Color8(255, 170, 70)}

var selected := ""
var _rooms: Array[Dictionary] = []
var _edges: Array[Dictionary] = []
var _bounds := Rect2()
var _hover := -1

## `rooms`: every RoomDefinition on the floor. `layout`: the authored minimap
## layout (may be empty). `edited` / `lost`: room id -> true. `exits`: room id
## -> [{"target": id, "edited": bool}].
func show_floor(rooms: Array, layout: Dictionary, edited: Dictionary, lost: Dictionary, exits: Dictionary) -> void:
	_rooms.clear()
	_edges.clear()
	_hover = -1
	var by_index: Dictionary = {}
	for room in rooms: by_index[int(room.minimap_metadata.get("room_index", -1))] = room
	var placed: Dictionary = {}
	for piece in layout.get("pieces", []):
		var room := by_index.get(int(piece.room_index)) as RoomDefinition
		if room == null or placed.has(room.id): continue
		var texture := SourceMenuArt.texture(String(piece.sprite_name))
		var piece_size := Vector2(texture.get_size()) if texture != null else Vector2(40, 24)
		var scale := float(piece.get("override_scale", -99.0))
		if scale > -50.0 and scale > 0.0: piece_size *= scale
		placed[room.id] = true
		_rooms.append({"room": room, "rect": Rect2(float(piece.x), float(piece.y), piece_size.x, piece_size.y), "texture": texture, "eggery": bool(piece.get("is_eggery", false))})
	var loose: Array[RoomDefinition] = []
	for room in rooms:
		if not placed.has(room.id): loose.append(room)
	if not _rooms.is_empty():
		# Rooms the minimap does not draw (lobby, expert rooms) wait in a column beside it.
		var used := _union()
		for index in loose.size():
			_rooms.append({"room": loose[index], "rect": Rect2(used.end.x + 22.0, used.position.y + index * 34.0, 40, 24), "texture": null, "eggery": false})
	else:
		for index in loose.size():
			var angle := TAU * float(index) / maxf(1.0, float(loose.size()))
			_rooms.append({"room": loose[index], "rect": Rect2(Vector2(cos(angle), sin(angle)) * 90.0 + Vector2(100, 100), Vector2(40, 24)), "texture": null, "eggery": false})
	_bounds = _union().grow(8.0)
	for entry in _rooms:
		var room: RoomDefinition = entry.room
		entry["edited"] = edited.has(String(room.id))
		entry["lost"] = lost.has(String(room.id))
		entry["kinds"] = []
		for interaction in room.interactions:
			var kind := String(interaction.get("kind", ""))
			if KIND_COLORS.has(kind) and kind not in entry.kinds: entry.kinds.append(kind)
	var index_of: Dictionary = {}
	for index in _rooms.size(): index_of[String(_rooms[index].room.id)] = index
	for source_id in exits:
		if not index_of.has(source_id): continue
		for exit_data in exits[source_id]:
			if index_of.has(String(exit_data.target)): _edges.append({"from": index_of[source_id], "to": index_of[String(exit_data.target)], "edited": bool(exit_data.edited)})
	queue_redraw()

func _union() -> Rect2:
	var result := Rect2()
	var first := true
	for entry in _rooms:
		result = entry.rect if first else result.merge(entry.rect)
		first = false
	return result

func _fit() -> Dictionary:
	var factor := minf((size.x - 16.0) / maxf(_bounds.size.x, 1.0), (size.y - 16.0) / maxf(_bounds.size.y, 1.0))
	factor = clampf(factor, 0.2, 8.0)
	return {"scale": factor, "origin": (size - _bounds.size * factor) * 0.5 - _bounds.position * factor}

func _screen_rect(rect: Rect2) -> Rect2:
	var fit := _fit()
	return Rect2(fit.origin + rect.position * float(fit.scale), rect.size * float(fit.scale))

func _room_at(point: Vector2) -> int:
	for index in range(_rooms.size() - 1, -1, -1):
		if _screen_rect(_rooms[index].rect).grow(3.0).has_point(point): return index
	return -1

func _ready() -> void:
	custom_minimum_size = Vector2(300, 200)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	clip_contents = true

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var index := _room_at(event.position)
		if index != _hover:
			_hover = index
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if index >= 0 else Control.CURSOR_ARROW
			queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var index := _room_at(event.position)
		if index < 0: return
		var room_id := String(_rooms[index].room.id)
		if event.double_click: room_activated.emit(room_id)
		else: room_pressed.emit(room_id)

func _get_tooltip(at_position: Vector2) -> String:
	var index := _room_at(at_position)
	if index < 0: return ""
	var entry: Dictionary = _rooms[index]
	var lines := PackedStringArray([String(entry.room.display_name)])
	if entry.edited: lines.append("Edited by this mod")
	if entry.lost: lines.append("Cannot be reached from the entrance with these doors")
	lines.append("Double-click to open")
	return "\n".join(lines)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED: queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color8(14, 15, 17))
	var font := ModWorkshopForm.FONT
	_draw_edges(false)
	for index in _rooms.size():
		var entry: Dictionary = _rooms[index]
		var rect := _screen_rect(entry.rect)
		var chosen := selected == String(entry.room.id)
		var texture := entry.texture as Texture2D
		var tint := Color(0.78, 0.9, 1.0, 1.0) if index == _hover or chosen else Color(0.58, 0.72, 0.9, 0.95)
		if entry.lost: tint = Color(1.0, 0.55, 0.5, 0.95)
		if texture != null: draw_texture_rect(texture, rect, false, tint)
		else:
			draw_rect(rect, Color8(51, 55, 63))
		if entry.eggery:
			var overlay := SourceMenuArt.texture("miniMap_eggeryOverlay")
			if overlay != null: draw_texture_rect(overlay, rect, false, tint)
		var outline := Color.WHITE if chosen else COLOR_LOST if entry.lost else COLOR_EDITED if entry.edited else Color(0, 0, 0, 0)
		if outline.a > 0.0: draw_rect(rect.grow(2.0), outline, false, 3.0 if chosen else 2.0)
		for dot in entry.kinds.size():
			draw_circle(rect.position + Vector2(5.0 + dot * 8.0, 5.0), 3.0, KIND_COLORS[entry.kinds[dot]])
		if entry.edited:
			draw_circle(rect.position + Vector2(rect.size.x - 4.0, 4.0), 5.0, COLOR_EDITED)
		if entry.lost:
			draw_string(font, rect.position + Vector2(0, rect.size.y * 0.5 + 6.0), "!", HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 18, Color.WHITE)
	_draw_edges(true)
	_draw_tags()

## Name tags: the selected and hovered rooms, plus every room the selected
## room's doors lead to, so a link can be read without hovering each end.
func _draw_tags() -> void:
	var font := ModWorkshopForm.FONT
	var focus := -1
	for index in _rooms.size():
		if String(_rooms[index].room.id) == selected: focus = index
	var tagged: Array = []
	if focus >= 0:
		for edge in _edges:
			if edge.from == focus and edge.to != focus and edge.to not in tagged: tagged.append(edge.to)
	for main in [focus, _hover]:
		if main >= 0:
			tagged.erase(main)
			tagged.append(main)
	for index in tagged:
		var entry: Dictionary = _rooms[index]
		var rect := _screen_rect(entry.rect)
		var primary: bool = index == focus or index == _hover
		var name := String(entry.room.display_name)
		var caption := name.get_slice("—", 1).strip_edges() if name.contains("—") else name
		var font_size := 12 if primary else 10
		var text_size := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var tag := Rect2(rect.get_center() + Vector2(-text_size.x * 0.5 - 4.0, rect.size.y * 0.5 + 3.0), text_size + Vector2(8, 5))
		tag.position.x = clampf(tag.position.x, 2.0, maxf(2.0, size.x - tag.size.x - 2.0))
		tag.position.y = minf(tag.position.y, size.y - tag.size.y - 2.0)
		draw_rect(tag, Color8(14, 20, 28, 235 if primary else 200))
		draw_rect(tag, COLOR_EDITED if entry.edited else Color8(112, 122, 138), false, 1.0)
		draw_string(font, tag.position + Vector2(4, 4 + font_size), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE if primary else ModWorkshopForm.MUTED)

## Two-way links that the mod has not changed are drawn as one faint line;
## one-way and rerouted links get an arrow. Lines stop at room edges, and the
## selected or hovered room's links are drawn bright on top.
func _draw_edges(highlight_only: bool) -> void:
	var focus := -1
	for index in _rooms.size():
		if String(_rooms[index].room.id) == selected: focus = index
	var lookup: Dictionary = {}
	for edge in _edges: lookup["%d>%d" % [edge.from, edge.to]] = edge
	var drawn: Dictionary = {}
	for edge in _edges:
		if edge.from == edge.to: continue
		var involved: bool = edge.from in [focus, _hover] or edge.to in [focus, _hover]
		if highlight_only != involved: continue
		var reverse: Variant = lookup.get("%d>%d" % [edge.to, edge.from])
		var two_way: bool = reverse != null and not edge.edited and not reverse.edited
		var pair_key := "%d-%d" % [mini(edge.from, edge.to), maxi(edge.from, edge.to)]
		if two_way and drawn.has(pair_key): continue
		drawn[pair_key] = true
		var from_rect := _screen_rect(_rooms[edge.from].rect)
		var to_rect := _screen_rect(_rooms[edge.to].rect)
		var a := _edge_point(from_rect, to_rect.get_center())
		var b := _edge_point(to_rect, from_rect.get_center())
		if a.distance_to(b) < 3.0: continue
		var alpha := 0.95 if involved else (0.85 if edge.edited else 0.28)
		var color: Color = Color(COLOR_EDITED, alpha) if edge.edited else Color(0.93, 0.97, 1.0, alpha)
		var width := 2.5 if involved or edge.edited else 1.4
		if not two_way and reverse != null:
			# Both directions exist but differ: offset so each arrow stays visible.
			var side := (b - a).normalized().orthogonal() * 3.0
			a += side
			b += side
		draw_line(a, b, color, width, true)
		if two_way: continue
		var direction := (b - a).normalized()
		var normal := direction.orthogonal()
		draw_colored_polygon(PackedVector2Array([b, b - direction * 9.0 + normal * 4.5, b - direction * 9.0 - normal * 4.5]), color)

## Where the line from a room's centre towards `toward` leaves the room.
func _edge_point(rect: Rect2, toward: Vector2) -> Vector2:
	var center := rect.get_center()
	var delta := toward - center
	if delta.length() < 0.001: return center
	var half := rect.size * 0.5
	var t := INF
	if absf(delta.x) > 0.001: t = minf(t, half.x / absf(delta.x))
	if absf(delta.y) > 0.001: t = minf(t, half.y / absf(delta.y))
	return center + delta * minf(t, 1.0)
