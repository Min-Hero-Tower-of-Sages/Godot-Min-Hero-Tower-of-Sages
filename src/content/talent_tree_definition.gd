class_name TalentTreeDefinition
extends ContentDefinition

@export var nodes: Array[Dictionary] = []

func validation_errors() -> PackedStringArray:
	var errors := super()
	var seen: Dictionary = {}
	for node in nodes:
		var node_id := StringName(node.get("id", ""))
		if node_id.is_empty(): errors.append("%s has a talent node without an id" % id)
		elif seen.has(node_id): errors.append("%s repeats talent node %s" % [id, node_id])
		seen[node_id] = true
	for node in nodes:
		for prerequisite in node.get("prerequisite_node_ids", []):
			if not seen.has(StringName(prerequisite)):
				errors.append("%s talent node %s references missing prerequisite %s" % [id, node.get("id", ""), prerequisite])
	return errors
