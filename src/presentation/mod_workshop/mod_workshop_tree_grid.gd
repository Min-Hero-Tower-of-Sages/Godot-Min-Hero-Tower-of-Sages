class_name ModWorkshopTreeGrid
extends Control

## The 3 x 4 talent grid exactly as the game lays it out. Press an empty cell
## to add a skill, press a skill to edit it, drag a skill to move or swap it.
## Skills are the manifest's own records: {"column", "row", "moves": [ids],
## "requires": ["column_row", ...]}.

signal cell_pressed(cell: Vector2i)
signal skill_moved(from: Vector2i, to: Vector2i)
## The first rank's move under the pointer, or "" (for the move hover card).
signal skill_hovered(move_id: String)

const CELL := Vector2(112, 58)
const GAP := Vector2(14, 14)
const GUTTER := 44.0
const HEADER := 18.0
const POINTS_PER_ROW := 3

var nodes: Array = []
var selected := Vector2i(-1, -1)
## Callable(move_id: String) -> Texture2D, and Callable(move_id: String) -> String.
var icon_for := Callable()
var label_for := Callable()

var _hover := Vector2i(-1, -1)
var _press := Vector2i(-1, -1)
var _press_at := Vector2.ZERO
var _dragging := false
var _mouse := Vector2.ZERO

func _init() -> void:
	custom_minimum_size = Vector2(GUTTER + UserModBuilder.TREE_COLUMNS * CELL.x + (UserModBuilder.TREE_COLUMNS - 1) * GAP.x + 4, HEADER + UserModBuilder.TREE_ROWS * CELL.y + (UserModBuilder.TREE_ROWS - 1) * GAP.y + 4)
	mouse_filter = Control.MOUSE_FILTER_STOP

func _cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(Vector2(GUTTER + cell.x * (CELL.x + GAP.x), HEADER + cell.y * (CELL.y + GAP.y)), CELL)

func _cell_at(point: Vector2) -> Vector2i:
	for column in UserModBuilder.TREE_COLUMNS:
		for row in UserModBuilder.TREE_ROWS:
			if _cell_rect(Vector2i(column, row)).grow_individual(GAP.x * 0.5, GAP.y * 0.5, GAP.x * 0.5, GAP.y * 0.5).has_point(point):
				return Vector2i(column, row)
	return Vector2i(-1, -1)

func skill_at(cell: Vector2i) -> Dictionary:
	for node in nodes:
		if int(node.get("column", -1)) == cell.x and int(node.get("row", -1)) == cell.y: return node
	return {}

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse = event.position
		var cell := _cell_at(event.position)
		if _press.x >= 0 and not _dragging and event.position.distance_to(_press_at) > 8.0 and not skill_at(_press).is_empty():
			_dragging = true
		if cell != _hover or _dragging:
			if cell != _hover or _dragging: _emit_hover(cell)
			_hover = cell
			queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press = _cell_at(event.position)
			_press_at = event.position
			_dragging = false
		else:
			var target := _cell_at(event.position)
			if _press.x >= 0:
				if _dragging and target.x >= 0 and target != _press: skill_moved.emit(_press, target)
				elif not _dragging and target == _press: cell_pressed.emit(target)
			_press = Vector2i(-1, -1)
			_dragging = false
			queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_hover = Vector2i(-1, -1)
		skill_hovered.emit("")
		queue_redraw()

func _emit_hover(cell: Vector2i) -> void:
	var moves: Array = skill_at(cell).get("moves", []) if cell.x >= 0 and not _dragging else []
	skill_hovered.emit(String(moves[0]) if not moves.is_empty() else "")

func _draw() -> void:
	var font := ModWorkshopForm.FONT
	draw_string(font, Vector2(0, 12), "Points", HORIZONTAL_ALIGNMENT_LEFT, GUTTER, 11, ModWorkshopForm.MUTED)
	for row in UserModBuilder.TREE_ROWS:
		var rect := _cell_rect(Vector2i(0, row))
		draw_string(font, Vector2(0, rect.position.y + CELL.y * 0.5 + 5), "%d+" % (row * POINTS_PER_ROW), HORIZONTAL_ALIGNMENT_LEFT, GUTTER - 6, 15, ModWorkshopForm.GOLD.darkened(0.15))
		if row > 0:
			draw_line(Vector2(0, rect.position.y - GAP.y * 0.5), Vector2(size.x, rect.position.y - GAP.y * 0.5), Color8(64, 69, 79, 120), 1.0)
	# Requirement arrows first, so skill cards sit on top of them.
	for node in nodes:
		var to_cell := Vector2i(int(node.get("column", 0)), int(node.get("row", 0)))
		for requirement in node.get("requires", []):
			var parts := String(requirement).split("_")
			if parts.size() != 2: continue
			var from_cell := Vector2i(int(parts[0]), int(parts[1]))
			var from_point := _cell_rect(from_cell).get_center() + Vector2(0, CELL.y * 0.5)
			var to_point := _cell_rect(to_cell).get_center() - Vector2(0, CELL.y * 0.5)
			var hot := selected == to_cell or selected == from_cell
			var color := ModWorkshopForm.GOLD if hot else Color8(150, 132, 84)
			draw_line(from_point, to_point, color, 2.5 if hot else 2.0)
			var direction := (to_point - from_point).normalized()
			var side := Vector2(-direction.y, direction.x)
			draw_colored_polygon(PackedVector2Array([to_point, to_point - direction * 9.0 + side * 5.0, to_point - direction * 9.0 - side * 5.0]), color)
	for column in UserModBuilder.TREE_COLUMNS:
		for row in UserModBuilder.TREE_ROWS:
			var cell := Vector2i(column, row)
			var rect := _cell_rect(cell)
			var node := skill_at(cell)
			if node.is_empty():
				_draw_empty(rect, cell)
			else:
				_draw_skill(rect, cell, node, font)
	if _dragging and _press.x >= 0:
		var ghost := Rect2(_mouse - CELL * 0.5, CELL)
		draw_rect(ghost, Color(ModWorkshopForm.GOLD, 0.25))
		draw_rect(ghost, ModWorkshopForm.GOLD, false, 2.0)

func _draw_empty(rect: Rect2, cell: Vector2i) -> void:
	var hot := cell == _hover
	var target := _dragging and hot
	draw_rect(rect, Color(ModWorkshopForm.GOLD, 0.16) if target else Color8(18, 28, 40, 150 if hot else 90))
	_dashed_outline(rect, Color8(112, 122, 138) if hot else Color8(70, 76, 86))
	if hot and not _dragging:
		draw_string(ModWorkshopForm.FONT, rect.position + Vector2(0, CELL.y * 0.5 + 8), "+", HORIZONTAL_ALIGNMENT_CENTER, CELL.x, 24, ModWorkshopForm.GOLD)

func _dashed_outline(rect: Rect2, color: Color) -> void:
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for index in 4:
		draw_dashed_line(corners[index], corners[(index + 1) % 4], color, 1.5, 5.0)

func _draw_skill(rect: Rect2, cell: Vector2i, node: Dictionary, font: Font) -> void:
	var is_selected := cell == selected
	var moves: Array = node.get("moves", [])
	var style := ModWorkshopForm.card_style()
	style.bg_color = Color8(66, 72, 82) if is_selected else Color8(40, 43, 49)
	style.border_color = ModWorkshopForm.GOLD if is_selected else (Color8(150, 170, 190) if cell == _hover else Color8(92, 100, 114))
	style.set_border_width_all(2 if is_selected else 1)
	draw_style_box(style, rect)
	var icon_rect := Rect2(rect.position + Vector2(6, 6), Vector2(34, 34))
	if not moves.is_empty() and icon_for.is_valid():
		var texture := icon_for.call(String(moves[0])) as Texture2D
		if texture != null: draw_texture_rect(texture, icon_rect, false)
		else: draw_rect(icon_rect, Color8(19, 21, 23))
	else:
		draw_rect(icon_rect, Color8(19, 21, 23))
	var caption := String(label_for.call(String(moves[0]))) if not moves.is_empty() and label_for.is_valid() else "(no move)"
	draw_string(font, rect.position + Vector2(44, 20), caption, HORIZONTAL_ALIGNMENT_LEFT, CELL.x - 48, 13, ModWorkshopForm.INK)
	# One pip per rank the skill can be upgraded to.
	for rank in moves.size():
		draw_rect(Rect2(rect.position + Vector2(46 + rank * 12, 29), Vector2(9, 9)), ModWorkshopForm.GOLD)
		draw_rect(Rect2(rect.position + Vector2(46 + rank * 12, 29), Vector2(9, 9)), Color8(18, 19, 22), false, 1.0)
	if not (node.get("requires", []) as Array).is_empty():
		draw_string(font, rect.position + Vector2(6, CELL.y - 5), "needs %d" % node.requires.size(), HORIZONTAL_ALIGNMENT_LEFT, 60, 10, ModWorkshopForm.MUTED)
