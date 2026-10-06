extends RefCounted

## Utility.AutoBuildMovesForMinion. The authored move list is a preference
## list, not a free grant of every requested highest-tier move.
var _content: ContentCatalog
var _rng: BattleRng
var _known: Array[StringName] = []
var _preferences: Array[MoveDefinition] = []
var _budget := 0
var _initial_count := 0

func build(definition: MinionDefinition, level: int, preferred_ids: Array, content: ContentCatalog, rng: BattleRng) -> Array[StringName]:
	_content = content
	_rng = rng
	_known = definition.initial_move_ids.duplicate()
	_initial_count = _known.size()
	var points := float(level - 3) / 3.0 if level < 31 else float(level - 30) / 4.0 + 9.0
	_budget = maxi(0, int(points) + (1 if level == 60 else 0))
	_preferences.clear()
	for raw_id in preferred_ids:
		var move := content.get_definition(StringName(raw_id)) as MoveDefinition
		if move != null: _preferences.append(move)
	if _remaining() <= 0 or definition.specialization_move_ids.is_empty():
		return _highest_tiers()
	var specialization := -1
	for index in definition.specialization_move_ids.size():
		if _preferred(definition.specialization_move_ids[index]):
			specialization = index
			break
	if specialization < 0:
		var roll := int(_rng.next_unit() * 300.0)
		specialization = 0 if roll > 200 else 2 if roll > 100 else 1
	_known.append(definition.specialization_move_ids[specialization])
	var primary := _content.get_definition(definition.talent_tree_ids[specialization]) as TalentTreeDefinition
	_build_primary(primary)
	if _remaining() <= 0: return _highest_tiers()
	for index in definition.talent_tree_ids.size():
		if index != specialization:
			_build_preferred(_content.get_definition(definition.talent_tree_ids[index]) as TalentTreeDefinition)
	for iteration in 10:
		var tree_index := int(_rng.next_unit() * 3.0)
		if tree_index != specialization:
			_build_random(_content.get_definition(definition.talent_tree_ids[tree_index]) as TalentTreeDefinition)
		if _remaining() <= 0: break
	return _highest_tiers()

func _remaining() -> int:
	return _budget - (_known.size() - _initial_count)

func _columns() -> Array[int]:
	var roll := int(_rng.next_unit() * 300.0)
	var order: Array[int] = []
	order.assign([2, 0, 1] if roll > 200 else [0, 1, 2] if roll > 100 else [1, 2, 0])
	return order

func _preferred(move_id: StringName) -> bool:
	var candidate := _content.get_definition(move_id) as MoveDefinition
	if candidate == null: return false
	for preference in _preferences:
		if candidate.family_id == preference.family_id and candidate.tier <= preference.tier:
			return true
	return false

func _node(tree: TalentTreeDefinition, column: int, row: int) -> Dictionary:
	if tree == null: return {}
	for node in tree.nodes:
		if int(node.get("column", -1)) == column and int(node.get("row", -1)) == row:
			return node
	return {}

func _dependencies_owned(tree: TalentTreeDefinition, node: Dictionary) -> bool:
	for prerequisite_id in node.get("prerequisite_node_ids", []):
		for prerequisite in tree.nodes:
			if String(prerequisite.id) != String(prerequisite_id): continue
			for move_id in prerequisite.get("move_ids", []):
				if StringName(move_id) not in _known: return false
	return true

func _add_from_row(tree: TalentTreeDefinition, columns: Array[int], row: int, preferred_only: bool) -> bool:
	if tree == null or _remaining() <= 0: return false
	for column in columns:
		var node := _node(tree, column, row)
		for raw_id in node.get("move_ids", []):
			var move_id := StringName(raw_id)
			if move_id in _known: continue
			# Source preference passes deliberately do not apply dependency gates;
			# fallback/random passes require every rank in the preceding node.
			if preferred_only:
				if not _preferred(move_id): continue
			elif not _dependencies_owned(tree, node):
				continue
			_known.append(move_id)
			return true
	return false

func _build_primary(tree: TalentTreeDefinition) -> void:
	var columns := _columns()
	var row := 0
	var previous_row := 0
	var added := 0
	var max_row := 0
	for iteration in 25:
		if _remaining() <= 0: return
		var found := _add_from_row(tree, columns, row, true)
		if found:
			added += 1
		else:
			max_row += 1
			row = mini(3, mini(int(added / 3), max_row))
		if not found and previous_row == row:
			if _add_from_row(tree, columns, row, false): added += 1
		previous_row = row
	if _budget > 10 and _known.size() - _initial_count < 11:
		_add_from_row(tree, columns, 0, false)

func _build_preferred(tree: TalentTreeDefinition) -> void:
	var columns := _columns()
	var row := 0
	var added := 0
	for iteration in 8:
		if _remaining() <= 0: return
		if _add_from_row(tree, columns, row, true):
			added += 1
		else:
			row = int(added / 3)

func _build_random(tree: TalentTreeDefinition) -> void:
	var columns := _columns()
	var added := 0
	for iteration in 20:
		if _remaining() <= 0: return
		if _add_from_row(tree, columns, int(added / 3), false): added += 1

func _highest_tiers() -> Array[StringName]:
	var result: Array[StringName] = []
	var positions: Dictionary = {}
	for move_id in _known:
		var move := _content.get_definition(move_id) as MoveDefinition
		if move == null: continue
		if not positions.has(move.family_id):
			positions[move.family_id] = result.size()
			result.append(move.id)
		else:
			var position := int(positions[move.family_id])
			var previous := _content.get_definition(result[position]) as MoveDefinition
			if move.tier > previous.tier: result[position] = move.id
	return result
