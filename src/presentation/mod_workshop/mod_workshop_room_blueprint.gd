class_name ModWorkshopRoomBlueprint
extends Control

## A to-scale drawing of one tower room, built from the same payload the game
## plays: the real floor and wall art, with the invisible parts shown as
## overlays (walls, door markers, arrival points and interaction zones).
##
## Editing (when `editable`):
##  - click an object to select it, Shift+click to add or remove it from the
##    selection, drag to move the selection (Ctrl while dragging = no snap);
##  - arrows nudge (Shift = 10x), Delete removes, Ctrl+D duplicates, Ctrl+Z undoes;
##  - mouse wheel zooms around the cursor, right or middle drag pans, F fits,
##    P shows or hides the side panel.
## Objects are keyed by payload index; objects a mod adds continue the
## numbering after the room's own objects, in the order they were added.

signal element_pressed(kind: String, key: Variant)
signal arrival_moved(spawn_id: String, position: Vector2)
signal selection_changed(keys: Array)
## Emitted while dragging (live) and once more with `finished` on release.
signal objects_moved(keys: Array, delta: Vector2, finished: bool)
signal delete_requested(keys: Array)
signal duplicate_requested(keys: Array)
signal undo_requested
signal redo_requested
signal panel_toggle_requested
signal tile_placed(position: Vector2)

const WALL_SIZE := Vector2(100.0, 50.0)
const DOOR_SIZE := Vector2(67.0, 67.0)
const ZONE_SIZE := Vector2(100.0, 100.0)
const ARRIVAL_RADIUS := 15.0
const COLOR_WALL := Color8(236, 96, 88)
const COLOR_DOOR := Color8(80, 214, 200)
const COLOR_ZONE := Color8(255, 170, 70)
const COLOR_ARRIVAL := Color8(130, 235, 120)
const COLOR_SELECT := Color8(246, 219, 150)
const COLOR_ADDED := Color8(140, 200, 255)
const MAX_ZOOM := 12.0

var layers := {"art": true, "walls": true, "doors": true, "arrivals": true, "zones": true}
var selected_kind := ""
var selected_key: Variant = null
## door id -> "Leads to ..." text; zone id -> text; both drawn beside the marker.
var door_captions: Dictionary = {}
var zone_captions: Dictionary = {}
var arrivals: Dictionary = {}
var editable := true
## When set, only this arrival point is drawn (door previews show where you land).
var only_arrival := ""
## Grid, in room pixels, that dragged objects snap to (0 = free).
var snap := 10.0
## When true, art and walls can be selected and moved (not only markers).
var object_mode := true
var selected_objects: Array = []
## Pixels on the right covered by an overlay; the room is fitted beside it.
var inset_right := 0.0
var custom_room := false
var paint_tiles := false

var _dimensions := Vector2(800, 600)
var _objects: Array[Dictionary] = []
var _original_count := 0
var _doors: Dictionary = {}
var _hover_kind := ""
var _hover_key: Variant = null
var _drag_arrival := ""
var _drag_start := Vector2.ZERO
var _drag_applied := Vector2.ZERO
var _dragging := false
var _panning := false
var _zoom := 1.0
var _pan := Vector2.ZERO

func _init() -> void:
	custom_minimum_size = Vector2(300, 240)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_CLICK
	clip_contents = true

## Reads everything drawable from the room's payload, with a room record's
## object edits applied the same way the game applies them.
func show_room(room: RoomDefinition, object_edits: Array = []) -> void:
	_objects.clear()
	_doors.clear()
	arrivals.clear()
	selected_kind = ""
	selected_key = null
	var payload := room.ensure_payload() if room != null else null
	if payload == null:
		queue_redraw()
		return
	_dimensions = payload.dimensions
	for key in room.spawn_positions:
		arrivals[String(key)] = room.spawn_positions[key]
	_original_count = payload.objects.size()
	var edited := UserModBuilder.edited_objects(payload.objects, object_edits, _dimensions)
	for index in edited.size():
		var attributes: Dictionary = edited[index]
		var sprite_name := String(attributes.get("spriteName", "")).strip_edges()
		var original_name := String(payload.objects[index].get("spriteName", "")).strip_edges() if index < _original_count else sprite_name
		var item := {
			"key": index, "sprite": original_name, "removed": sprite_name.is_empty(), "added": index >= _original_count,
			"position": Vector2(float(attributes.get("xPos", 0.0)), float(attributes.get("yPos", 0.0))),
			"scale": Vector2(float(attributes.get("xScale", 1.0)), float(attributes.get("yScale", 1.0))),
			"rotation": deg_to_rad(float(attributes.get("rotation", 0.0))),
			"tint": Color.from_string(String(attributes.get("tint", "")), Color.WHITE),
			"workshop_object": int(attributes.get("workshop_object", -1)),
			"workshop_feature": int(attributes.get("workshop_feature", -1)),
		}
		var normalized := original_name.trim_prefix("teleport_").trim_prefix("telport_")
		if original_name == "collRect" or original_name.begins_with("wallRect_"):
			item.merge({"kind": "wall", "size": WALL_SIZE})
		elif normalized.begins_with("roomTransitionObject"):
			var suffix := normalized.trim_prefix("roomTransitionObject")
			if suffix.is_valid_int(): _doors[int(suffix)] = item.merged({"kind": "door", "size": DOOR_SIZE})
			continue
		elif original_name.begins_with("buttonZoneObject"):
			var zone_suffix := original_name.trim_prefix("buttonZoneObject")
			var zone_id := 0 if zone_suffix.is_empty() else int(zone_suffix) if zone_suffix.is_valid_int() else -1
			if zone_id < 0: continue
			item.merge({"kind": "zone", "zone_id": zone_id, "size": ZONE_SIZE})
		elif _is_hidden(original_name):
			continue
		else:
			var texture := RoomArtCatalog.texture(original_name)
			if texture == null: continue
			item.merge({"kind": "art", "texture": texture, "size": texture.get_size()})
		item["editable"] = UserModBuilder.object_editable(original_name)
		if custom_room: item["editable"] = item.workshop_object >= 0 or item.workshop_feature >= 0
		_objects.append(item)
	selected_objects = selected_objects.filter(func(key: Variant) -> bool: return _object(int(key)) != null)
	queue_redraw()

func has_door(transition_id: int) -> bool:
	return _doors.has(transition_id)

func has_zone(zone_id: int) -> bool:
	return _objects.any(func(item: Dictionary) -> bool: return item.kind == "zone" and int(item.zone_id) == zone_id)

func door_ids() -> Array:
	return _doors.keys()

func object_info(key: int) -> Dictionary:
	var item: Variant = _object(key)
	return {} if item == null else item.duplicate()

func original_count() -> int:
	return _original_count

## The centre of the visible part of the room, for placing new objects.
func view_center() -> Vector2:
	return _to_room(Vector2(maxf(60.0, size.x - inset_right), size.y) * 0.5).clamp(Vector2.ZERO, _dimensions).round()

func reset_view() -> void:
	_zoom = 1.0
	_pan = Vector2.ZERO
	queue_redraw()

func select_objects(keys: Array) -> void:
	selected_objects = keys.duplicate()
	queue_redraw()

func _object(key: int) -> Variant:
	for item in _objects:
		if int(item.key) == key: return item
	return null

static func _is_hidden(sprite_name: String) -> bool:
	return sprite_name.is_empty() or sprite_name == "regularDoor" or sprite_name == "regularDoor_eggery" \
		or sprite_name.begins_with("menus_speechBubble") or sprite_name.begins_with("entryObject") or sprite_name.begins_with("expert_entryObject") \
		or sprite_name.begins_with("expert_roomTransitionObject") or sprite_name == "roomTransition_startingRoomToLobby" \
		or sprite_name.begins_with("sound") or sprite_name.to_lower().contains("music")

# --- Geometry -----------------------------------------------------------------------

func _fit() -> Dictionary:
	var margin := 6.0
	var area := Vector2(maxf(60.0, size.x - inset_right), size.y)
	var factor := minf((area.x - margin * 2.0) / maxf(_dimensions.x, 1.0), (area.y - margin * 2.0) / maxf(_dimensions.y, 1.0))
	factor = maxf(factor, 0.01) * _zoom
	return {"scale": factor, "origin": (area - _dimensions * factor) * 0.5 + _pan}

func _to_screen(point: Vector2) -> Vector2:
	var fit := _fit()
	return fit.origin + point * float(fit.scale)

func _to_room(point: Vector2) -> Vector2:
	var fit := _fit()
	return (point - fit.origin) / float(fit.scale)

func _item_transform(item: Dictionary) -> Transform2D:
	var fit := _fit()
	var placed := Transform2D(float(item.rotation), item.scale, 0.0, item.position)
	return Transform2D(0.0, Vector2.ONE * float(fit.scale), 0.0, fit.origin) * placed

func _item_center(item: Dictionary) -> Vector2:
	return _item_transform(item) * (Vector2(item.size) * 0.5)

func _hit_item(item: Dictionary, point: Vector2) -> bool:
	var local := _item_transform(item).affine_inverse() * point
	var item_size: Vector2 = item.size
	return local.x >= 0.0 and local.y >= 0.0 and local.x <= item_size.x and local.y <= item_size.y

func _screen_area(item: Dictionary) -> float:
	return absf(Vector2(item.size).x * item.scale.x * Vector2(item.size).y * item.scale.y)

func _arrival_at(point: Vector2) -> String:
	for key in arrivals:
		if _to_screen(arrivals[key]).distance_to(point) <= maxf(10.0, ARRIVAL_RADIUS * float(_fit().scale) + 4.0): return String(key)
	return ""

func _layer_visible(item: Dictionary) -> bool:
	match String(item.kind):
		"wall": return layers.walls
		"zone": return layers.zones
		"art": return layers.art
	return true

## Markers first; then the smallest object under the cursor, so a bush wins
## over the floor tile beneath it.
func _pick(point: Vector2) -> Array:
	if layers.arrivals:
		var arrival := _arrival_at(point)
		if not arrival.is_empty(): return ["arrival", arrival]
	if layers.doors:
		for key in _doors:
			if _hit_item(_doors[key], point): return ["door", key]
	var best: Variant = null
	for item in _objects:
		if item.removed or not _layer_visible(item) or not _hit_item(item, point): continue
		if custom_room and not item.editable: continue
		if item.kind != "zone" and not object_mode: continue
		var rank := 0 if item.kind == "zone" else 1
		var best_rank := 0 if best != null and best.kind == "zone" else 1
		if best == null or rank < best_rank or (rank == best_rank and _screen_area(item) < _screen_area(best)):
			best = item
	if best != null: return ["object", int(best.key)]
	return ["", null]

# --- Input --------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if _panning:
			_pan += event.relative
			queue_redraw()
			return
		if not _drag_arrival.is_empty():
			var room_point := _snapped(_to_room(event.position).clamp(Vector2.ZERO, _dimensions), event.ctrl_pressed)
			arrivals[_drag_arrival] = room_point
			arrival_moved.emit(_drag_arrival, room_point)
			queue_redraw()
			return
		if _dragging:
			var delta: Vector2 = (event.position - _drag_start) / float(_fit().scale)
			if snap > 0.0 and not event.ctrl_pressed: delta = (delta / snap).round() * snap
			var step: Vector2 = delta - _drag_applied
			if step != Vector2.ZERO:
				_drag_applied = delta
				_shift_selection(step)
				objects_moved.emit(selected_objects.duplicate(), step, false)
			return
		var picked := _pick(event.position)
		if picked[0] != _hover_kind or picked[1] != _hover_key:
			_hover_kind = picked[0]
			_hover_key = picked[1]
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if not _hover_kind.is_empty() else Control.CURSOR_ARROW
			queue_redraw()
	elif event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			_zoom_at(event.position, 1.2 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.2)
			accept_event()
		elif event.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			_panning = event.pressed
			mouse_default_cursor_shape = Control.CURSOR_DRAG if _panning else Control.CURSOR_ARROW
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed: _press(event.position, event.shift_pressed)
			else: _release()

func _press(point: Vector2, additive: bool) -> void:
	grab_focus()
	if paint_tiles:
		var room_point := _to_room(point)
		if Rect2(Vector2.ZERO, _dimensions).has_point(room_point):
			tile_placed.emit((room_point / 64.0).floor() * 64.0)
		return
	var picked := _pick(point)
	if picked[0] == "object":
		var key := int(picked[1])
		var item: Dictionary = _object(key)
		if additive:
			if key in selected_objects: selected_objects.erase(key)
			else: selected_objects.append(key)
		elif key not in selected_objects:
			selected_objects = [key]
		selection_changed.emit(selected_objects.duplicate())
		if item.kind == "zone":
			selected_kind = "zone"
			selected_key = int(item.zone_id)
			element_pressed.emit("zone", int(item.zone_id))
		else:
			selected_kind = "object"
			selected_key = key
		if editable and not selected_objects.is_empty() and selected_objects.all(func(selected: Variant) -> bool: return bool(_object(int(selected)).editable)):
			_dragging = true
			_drag_start = point
			_drag_applied = Vector2.ZERO
		queue_redraw()
		return
	if not additive and not selected_objects.is_empty():
		selected_objects.clear()
		selection_changed.emit([])
	if picked[0].is_empty():
		selected_kind = ""
		selected_key = null
		queue_redraw()
		return
	selected_kind = picked[0]
	selected_key = picked[1]
	if picked[0] == "arrival" and editable: _drag_arrival = String(picked[1])
	element_pressed.emit(picked[0], picked[1])
	queue_redraw()

func _release() -> void:
	if _dragging and _drag_applied != Vector2.ZERO: objects_moved.emit(selected_objects.duplicate(), Vector2.ZERO, true)
	_dragging = false
	_drag_arrival = ""

func _snapped(point: Vector2, free: bool) -> Vector2:
	return (point / snap).round() * snap if snap > 0.0 and not free else point.round()

func _shift_selection(step: Vector2) -> void:
	for key in selected_objects:
		var item: Variant = _object(int(key))
		if item != null: item.position += step
	queue_redraw()

func _zoom_at(point: Vector2, factor: float) -> void:
	var before := _to_room(point)
	_zoom = clampf(_zoom * factor, 1.0, MAX_ZOOM)
	if is_equal_approx(_zoom, 1.0): _pan = Vector2.ZERO
	else: _pan += point - _to_screen(before)
	queue_redraw()

func _unhandled_key_input(event: InputEvent) -> void:
	if not has_focus() or not event.pressed or not editable: return
	var key := event as InputEventKey
	var command := key.ctrl_pressed or key.meta_pressed
	if command and key.keycode == KEY_Z:
		if key.shift_pressed: redo_requested.emit()
		else: undo_requested.emit()
	elif command and key.keycode == KEY_Y: redo_requested.emit()
	elif command and key.keycode == KEY_D and not selected_objects.is_empty(): duplicate_requested.emit(selected_objects.duplicate())
	elif key.keycode in [KEY_DELETE, KEY_BACKSPACE] and not selected_objects.is_empty(): delete_requested.emit(selected_objects.duplicate())
	elif key.keycode == KEY_F: reset_view()
	elif key.keycode == KEY_P: panel_toggle_requested.emit()
	elif key.keycode in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN] and not selected_objects.is_empty():
		var amount := (10.0 if key.shift_pressed else 1.0) * maxf(1.0, snap)
		var step: Vector2 = {KEY_LEFT: Vector2.LEFT, KEY_RIGHT: Vector2.RIGHT, KEY_UP: Vector2.UP, KEY_DOWN: Vector2.DOWN}[key.keycode] * amount
		_shift_selection(step)
		objects_moved.emit(selected_objects.duplicate(), step, true)
	elif key.keycode == KEY_ESCAPE and not selected_objects.is_empty():
		selected_objects.clear()
		selection_changed.emit([])
		queue_redraw()
	else:
		return
	get_viewport().set_input_as_handled()

func _get_tooltip(at_position: Vector2) -> String:
	var picked := _pick(at_position)
	match String(picked[0]):
		"door": return "Door %s%s\nDoors stay where the room's art puts them." % [picked[1], ("\n" + String(door_captions.get(picked[1], ""))) if door_captions.has(picked[1]) else ""]
		"arrival": return "Arrival point %s\nWhere you stand when you come through a door. Drag to move it." % picked[1]
		"object":
			var item: Dictionary = _object(int(picked[1]))
			var title := String(zone_captions.get(int(item.zone_id), "Interaction zone")) if item.kind == "zone" else RoomArtCatalog.caption(String(item.sprite))
			return "%s\n%s" % [title, "Drag to move. Shift+click to select several." if item.editable else "Part of the room's own logic; it stays put."]
	return ""

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_VISIBILITY_CHANGED: queue_redraw()

# --- Drawing ------------------------------------------------------------------------

func _draw() -> void:
	var fit := _fit()
	var factor := float(fit.scale)
	draw_rect(Rect2(Vector2.ZERO, size), Color8(14, 15, 17))
	draw_rect(Rect2(fit.origin, _dimensions * factor), Color8(26, 29, 33))
	if layers.art:
		for item in _objects:
			if item.kind != "art" or item.removed: continue
			draw_set_transform_matrix(_item_transform(item))
			draw_texture(item.texture, Vector2.ZERO, item.tint)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	if snap > 0.0 and editable and _zoom >= 3.0:
		_draw_grid(fit)
	if layers.walls:
		for item in _objects:
			if item.kind != "wall" or item.removed: continue
			draw_set_transform_matrix(_item_transform(item))
			var tint := COLOR_ADDED if item.added else COLOR_WALL
			draw_rect(Rect2(Vector2.ZERO, item.size), Color(tint, 0.32))
			draw_rect(Rect2(Vector2.ZERO, item.size), Color(tint, 0.8), false, 2.0 / maxf(factor * absf(float(item.scale.x)), 0.1))
	draw_set_transform_matrix(Transform2D.IDENTITY)
	if layers.zones:
		for item in _objects:
			if item.kind == "zone" and not item.removed: _draw_marker(item, COLOR_ZONE, "zone", int(item.zone_id), String(zone_captions.get(int(item.zone_id), "")))
	if layers.doors:
		for key in _doors: _draw_marker(_doors[key], COLOR_DOOR, "door", key, String(door_captions.get(key, "")))
	_draw_selection()
	if layers.arrivals:
		for key in arrivals:
			if only_arrival.is_empty() or String(key) == only_arrival: _draw_arrival(String(key))
	draw_rect(Rect2(fit.origin, _dimensions * factor), Color8(112, 122, 138), false, 1.0)
	if _zoom > 1.01:
		draw_string(ModWorkshopForm.FONT, Vector2(6, size.y - 6), "x%.1f  (F to fit)" % _zoom, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ModWorkshopForm.MUTED)

func _draw_grid(fit: Dictionary) -> void:
	var step := snap * float(fit.scale)
	var top_left := _to_room(Vector2.ZERO).clamp(Vector2.ZERO, _dimensions)
	var bottom_right := _to_room(size).clamp(Vector2.ZERO, _dimensions)
	var color := Color(1, 1, 1, 0.06)
	var x := floorf(top_left.x / snap) * snap
	while x <= bottom_right.x and step > 4.0:
		draw_line(_to_screen(Vector2(x, top_left.y)), _to_screen(Vector2(x, bottom_right.y)), color, 1.0)
		x += snap
	var y := floorf(top_left.y / snap) * snap
	while y <= bottom_right.y and step > 4.0:
		draw_line(_to_screen(Vector2(top_left.x, y)), _to_screen(Vector2(bottom_right.x, y)), color, 1.0)
		y += snap

func _draw_selection() -> void:
	for item in _objects:
		var key := int(item.key)
		var chosen := key in selected_objects
		var hot: bool = _hover_kind == "object" and _hover_key == key
		if not chosen and not hot or item.removed: continue
		var transform := _item_transform(item)
		var size_vector: Vector2 = item.size
		var corners := PackedVector2Array([transform * Vector2.ZERO, transform * Vector2(size_vector.x, 0), transform * size_vector, transform * Vector2(0, size_vector.y), transform * Vector2.ZERO])
		draw_polyline(corners, COLOR_SELECT if chosen else Color(1, 1, 1, 0.6), 2.0 if chosen else 1.0)
		if chosen:
			for corner in corners.slice(0, 4): draw_rect(Rect2(corner - Vector2(3, 3), Vector2(6, 6)), COLOR_SELECT)

func _draw_marker(item: Dictionary, color: Color, kind: String, key: Variant, caption: String) -> void:
	var chosen: bool = selected_kind == kind and selected_key == key
	var hot: bool = (_hover_kind == kind and _hover_key == key) or (_hover_kind == "object" and item.has("key") and _hover_key == item.key)
	draw_set_transform_matrix(_item_transform(item))
	var fill := 0.55 if chosen else 0.4 if hot else 0.26
	draw_rect(Rect2(Vector2.ZERO, item.size), Color(color, fill))
	draw_rect(Rect2(Vector2.ZERO, item.size), Color.WHITE if chosen else color, false, 3.0 if chosen else 2.0)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	var center := _item_center(item)
	var font := ModWorkshopForm.FONT
	var label := str(key) if kind == "door" else "?" if caption.is_empty() else caption.left(1).to_upper()
	draw_circle(center, 11.0, Color8(18, 19, 22, 230))
	draw_arc(center, 11.0, 0.0, TAU, 20, Color.WHITE if chosen else color, 2.0)
	draw_string(font, center + Vector2(-11, 5), label, HORIZONTAL_ALIGNMENT_CENTER, 22, 13, Color.WHITE)
	if (chosen or hot) and not caption.is_empty():
		var text_size := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
		var box := Rect2(center + Vector2(-text_size.x * 0.5 - 5, -34), text_size + Vector2(10, 6))
		box.position.x = clampf(box.position.x, 2.0, maxf(2.0, size.x - box.size.x - 2.0))
		box.position.y = maxf(2.0, box.position.y)
		draw_rect(box, Color8(18, 19, 22, 240))
		draw_rect(box, color, false, 1.0)
		draw_string(font, box.position + Vector2(5, 15), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ModWorkshopForm.INK)

func _draw_arrival(key: String) -> void:
	var center := _to_screen(arrivals[key])
	var chosen := selected_kind == "arrival" and String(selected_key) == key
	var radius := maxf(8.0, ARRIVAL_RADIUS * float(_fit().scale))
	draw_circle(center, radius, Color(COLOR_ARRIVAL, 0.35 if not chosen else 0.6))
	draw_arc(center, radius, 0.0, TAU, 24, Color.WHITE if chosen else COLOR_ARRIVAL, 2.5)
	draw_line(center + Vector2(0, -radius * 0.55), center + Vector2(0, radius * 0.55), COLOR_ARRIVAL, 2.0)
	draw_line(center + Vector2(-radius * 0.55, 0), center + Vector2(radius * 0.55, 0), COLOR_ARRIVAL, 2.0)
	draw_string(ModWorkshopForm.FONT, center + Vector2(-30, radius + 12), key.trim_prefix("entry-"), HORIZONTAL_ALIGNMENT_CENTER, 60, 11, COLOR_ARRIVAL)
