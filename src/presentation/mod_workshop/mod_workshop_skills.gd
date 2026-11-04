class_name ModWorkshopSkills
extends RefCounted

## The Skills tab: make and edit talent ("skill") trees. A tree is a grid of
## skills; each skill teaches a line of moves rank by rank, and may require
## skills from earlier rows. Trees are assigned to minions from the Minions
## tab (their "Skill trees" list), one tree per specialization.

var host: ModWorkshopView

func _init(owner: ModWorkshopView) -> void:
	host = owner

static func key_of(cell: Vector2i) -> String:
	return "%d_%d" % [cell.x, cell.y]

static func cell_of(key: String) -> Vector2i:
	var parts := key.split("_")
	return Vector2i(int(parts[0]), int(parts[1])) if parts.size() == 2 else Vector2i(-1, -1)

func new_blank() -> void:
	var record := {"id": host._unique_id("talent_tree", "new_tree"), "name": "New Tree", "nodes": []}
	_add(record)

## A copy of a recovered tree (or one of this mod's), ready to edit.
func new_from_existing() -> void:
	host._open_picker("talent_tree", func(id: String) -> void:
		var record: Dictionary = {}
		for own in host._manifest.talent_trees:
			if String(own.id) == id: record = own.duplicate(true)
		if record.is_empty():
			var tree := host.catalog.get_definition(StringName(id)) as TalentTreeDefinition
			if tree == null: return
			record = UserModBuilder.tree_record(tree)
		record["id"] = host._unique_id("talent_tree", "new_" + String(record.get("name", "tree")))
		record["name"] = ("New " + String(record.get("name", "Tree"))).left(14)
		_add(record))

func _add(record: Dictionary) -> void:
	host._manifest.talent_trees.append(record)
	host._selection["talent_trees"] = host._manifest.talent_trees.size() - 1
	host._selection.erase("skill")
	host._changed()
	host._build_editor()

## The move tiers a skill teaches, starting at `move_id` and going up.
func ranks_from(move_id: String) -> Array:
	for record in host._manifest.moves:
		var prefix := String(record.id) + "/tier"
		if move_id.begins_with(prefix):
			var result: Array = []
			for tier in range(int(move_id.trim_prefix(prefix)), record.tiers.size() + 1): result.append("%s%d" % [prefix, tier])
			return result.slice(0, UserModBuilder.TREE_MAX_RANKS)
	var picked := host.catalog.get_definition(StringName(move_id)) as MoveDefinition
	if picked == null: return [move_id]
	var tiers: Array[MoveDefinition] = []
	for definition in host.catalog._by_id.values():
		if definition is MoveDefinition and definition.family_id == picked.family_id and definition.available and not definition.effects.is_empty() and definition.tier >= picked.tier: tiers.append(definition)
	tiers.sort_custom(func(a: MoveDefinition, b: MoveDefinition) -> bool: return a.tier < b.tier)
	var ids: Array = []
	for tier in tiers: ids.append(String(tier.id))
	return ids.slice(0, UserModBuilder.TREE_MAX_RANKS) if not ids.is_empty() else [move_id]

func move_name(move_id: String) -> String:
	return host._describe("move", move_id).trim_prefix("* ").get_slice(" (tier", 0)

func skill_at(record: Dictionary, cell: Vector2i) -> Dictionary:
	for node in record.nodes:
		if int(node.get("column", -1)) == cell.x and int(node.get("row", -1)) == cell.y: return node
	return {}

## Requirements may only point at an existing skill in an earlier row.
func prune(record: Dictionary) -> void:
	var rows: Dictionary = {}
	for node in record.nodes: rows[key_of(Vector2i(int(node.column), int(node.row)))] = int(node.row)
	for node in record.nodes:
		var kept: Array = []
		for requirement in node.get("requires", []):
			if rows.has(String(requirement)) and int(rows[String(requirement)]) < int(node.row) and String(requirement) not in kept: kept.append(String(requirement))
		node["requires"] = kept

func move_skill(record: Dictionary, from: Vector2i, to: Vector2i) -> void:
	var moving := skill_at(record, from)
	var other := skill_at(record, to)
	if moving.is_empty(): return
	moving["column"] = to.x
	moving["row"] = to.y
	if not other.is_empty():
		other["column"] = from.x
		other["row"] = from.y
	var from_key := key_of(from)
	var to_key := key_of(to)
	for node in record.nodes:
		var requires: Array = node.get("requires", [])
		for index in requires.size():
			if requires[index] == from_key: requires[index] = to_key
			elif requires[index] == to_key and not other.is_empty(): requires[index] = from_key
	prune(record)

func remove_skill(record: Dictionary, cell: Vector2i) -> void:
	var node := skill_at(record, cell)
	if node.is_empty(): return
	record.nodes.erase(node)
	var gone := key_of(cell)
	for other in record.nodes: other["requires"] = (other.get("requires", []) as Array).filter(func(key: Variant) -> bool: return String(key) != gone)

func users(record: Dictionary) -> PackedStringArray:
	var names := PackedStringArray()
	for minion in host._manifest.minions + host._manifest.minion_patches:
		if String(record.id) in minion.get("talent_trees", []):
			names.append(String(minion.get("name", host._describe("minion", String(minion.get("target", ""))))))
	return names

func tree_form(form: ModWorkshopForm, record: Dictionary) -> void:
	if not record.get("nodes") is Array: record["nodes"] = []
	var head := form.card()
	var head_title := host._label(String(record.get("name", "Skill tree")), 20, ModWorkshopForm.GOLD, head)
	head_title.clip_text = true
	var used_by := users(record)
	var usage := host._label(("Used by %s." % ", ".join(used_by)) if not used_by.is_empty() else "Not used by any minion yet. Give it to a minion in the Minions tab (Skill trees).", 12, ModWorkshopForm.MUTED if not used_by.is_empty() else Color8(240, 200, 120), head)
	usage.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	usage.custom_minimum_size.x = 120
	form.changed.connect(func() -> void: head_title.text = String(record.get("name", "Skill tree")))
	var identity := form.card("Identity")
	identity.text("Name", record, "name", 14)
	identity.note("The name is the tab's label on the in-game talent screen, so keep it short. ID %s." % record.id, ModWorkshopForm.MUTED)
	var layout := form.card("Skills")
	layout.note("Press an empty box to add a skill, press a skill to edit it, drag a skill to move or swap it. A row opens once the minion has spent that many points in this tree.")
	var grid := ModWorkshopTreeGrid.new()
	grid.nodes = record.nodes
	grid.icon_for = host._move_icon
	grid.label_for = move_name
	grid.skill_hovered.connect(func(move_id: String) -> void:
		if move_id.is_empty(): host._move_tip.visible = false
		else: host.show_move_tip(grid, move_id))
	var chosen: Vector2i = cell_of(String(host._selection.get("skill", "")))
	grid.selected = chosen if not skill_at(record, chosen).is_empty() else Vector2i(-1, -1)
	layout.add_child(grid)
	var inspector := VBoxContainer.new()
	form.card("Selected skill").add_child(inspector)
	var rebuild := func(self_call: Callable) -> void:
		for child in inspector.get_children():
			inspector.remove_child(child)
			child.queue_free()
		var node := skill_at(record, grid.selected)
		if node.is_empty():
			host._label("Press a skill in the grid to edit its ranks and requirements.", 12, ModWorkshopForm.MUTED, inspector)
			return
		var panel := host._make_form()
		inspector.add_child(panel)
		panel.changed.connect(grid.queue_redraw)
		panel.note("Column %d, row %d - opens at %d point%s spent in this tree." % [int(node.column) + 1, int(node.row) + 1, int(node.row) * ModWorkshopTreeGrid.POINTS_PER_ROW, "" if int(node.row) * ModWorkshopTreeGrid.POINTS_PER_ROW == 1 else "s"])
		panel.reference_list("Ranks (moves taught)", node, "moves", "move", UserModBuilder.TREE_MAX_RANKS, 1)
		panel.button("Fill ranks from the first move's tiers", func() -> void:
			node["moves"] = ranks_from(String(node.moves[0]))
			host._changed()
			grid.queue_redraw()
			self_call.call(self_call))
		var earlier: Array = []
		for candidate in record.nodes:
			if int(candidate.row) < int(node.row): earlier.append(candidate)
		if earlier.is_empty():
			panel.note("Skills in the first row are open from the start. Put a skill in a later row to make it require others.")
		else:
			panel.note("Requires (the minion needs every rank of these first):")
			var flow := HFlowContainer.new()
			flow.add_theme_constant_override("h_separation", 4)
			flow.add_theme_constant_override("v_separation", 4)
			panel.add_child(flow)
			for candidate in earlier:
				var requirement := key_of(Vector2i(int(candidate.column), int(candidate.row)))
				var toggle := CheckBox.new()
				toggle.text = "%s (%d,%d)" % [move_name(String(candidate.moves[0])) if not candidate.moves.is_empty() else "?", int(candidate.column) + 1, int(candidate.row) + 1]
				toggle.button_pressed = requirement in node.get("requires", [])
				toggle.toggled.connect(func(on: bool) -> void:
					var requires: Array = node.get("requires", [])
					if on and requirement not in requires: requires.append(requirement)
					elif not on: requires.erase(requirement)
					node["requires"] = requires
					host._changed()
					grid.queue_redraw())
				flow.add_child(toggle)
		panel.button("Remove this skill", func() -> void:
			remove_skill(record, grid.selected)
			grid.selected = Vector2i(-1, -1)
			host._selection.erase("skill")
			host._changed()
			grid.queue_redraw()
			self_call.call(self_call))
	grid.cell_pressed.connect(func(cell: Vector2i) -> void:
		if not skill_at(record, cell).is_empty():
			grid.selected = cell
			host._selection["skill"] = key_of(cell)
			grid.queue_redraw()
			rebuild.call(rebuild)
			return
		if record.nodes.size() >= UserModBuilder.TREE_COLUMNS * UserModBuilder.TREE_ROWS: return
		host._open_picker("move", func(move_id: String) -> void:
			record.nodes.append({"column": cell.x, "row": cell.y, "moves": ranks_from(move_id), "requires": []})
			grid.selected = cell
			host._selection["skill"] = key_of(cell)
			host._changed()
			grid.queue_redraw()
			rebuild.call(rebuild)))
	grid.skill_moved.connect(func(from: Vector2i, to: Vector2i) -> void:
		move_skill(record, from, to)
		grid.selected = to
		host._selection["skill"] = key_of(to)
		host._changed()
		grid.queue_redraw()
		rebuild.call(rebuild))
	rebuild.call(rebuild)
	var tips := form.card("How trees work")
	tips.note("A minion has up to three trees, one for each specialization move (the same position in both lists). Only the tree of the chosen specialization is open at first; the others open after 11 points.")
	tips.note("Each skill is a line of moves: rank 1 teaches the first move, rank 2 the second, and so on, up to five ranks. Rows open every 3 points spent in the tree. Recovered trees show how others were built: start from a copy.")
