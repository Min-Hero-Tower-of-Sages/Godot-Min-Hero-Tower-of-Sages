class_name MinionPaletteService
extends RefCounted

# Appearance-only registry/prototype. No rarity rolls or save mutation here.
const REGISTRY_PATH := "res://content/base/palettes/shiny_palettes.json"
const SHADER := preload("res://src/presentation/shaders/minion_palette.gdshader")
static var _registry: Dictionary = {}

static func registry() -> Dictionary:
	if _registry.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(REGISTRY_PATH))
		if parsed is Dictionary: _registry = parsed
	return _registry

static func line_id(definition_id: StringName, catalog: ContentCatalog) -> StringName:
	var members: Dictionary = registry().get("members", {})
	if members.has(String(definition_id)): return StringName(members[String(definition_id)])
	# New authored models need no replacement sprite or hand-authored palette.
	# Follow the catalog's evolution links back to a stable family root.
	if catalog == null or not catalog.ensure_index().is_empty(): return definition_id
	var current := definition_id
	var visited: Dictionary = {}
	while not visited.has(current):
		visited[current] = true
		var parent := &""
		for definition in catalog._by_id.values():
			if definition is MinionDefinition and definition.evolution_id == current:
				parent = definition.id
				break
		if parent.is_empty(): return current
		current = parent
	return definition_id

static func palette(definition_id: StringName, catalog: ContentCatalog = null) -> Dictionary:
	var root_id := line_id(definition_id, catalog)
	var choice: Dictionary = registry().get("lines", {}).get(String(root_id), {})
	if not choice.is_empty():
		return {"line_id": root_id, "palette_name": choice.palette_name, "parameters": choice.parameters.duplicate(true), "procedural": false}
	# Stable fallback: future evolution stages share their root's hue transform.
	var seed := absi(String(root_id).hash())
	return {"line_id": root_id, "palette_name": "Procedural Variant", "procedural": true, "parameters": {
		"hue_shift": 0.18 + float(seed % 640) / 1000.0,
		"source_hue": -1.0, "hue_width": 0.5, "saturation_scale": 1.0,
		"value_scale": 1.0, "minimum_saturation": 0.12, "minimum_value": 0.10,
	}}

static func make_material(definition_id: StringName, catalog: ContentCatalog = null) -> ShaderMaterial:
	return make_material_for_line(line_id(definition_id, catalog))

static func texture_for_definition(definition_id: StringName) -> Texture2D:
	var data := registry()
	var root_id := String(data.get("members", {}).get(String(definition_id), ""))
	for stage in data.get("lines", {}).get(root_id, {}).get("stages", []):
		if String(stage.id) == String(definition_id):
			return load("res://" + String(stage.texture)) as Texture2D
	return null

static func make_material_for_owned(owned: OwnedMinionState, catalog: ContentCatalog = null) -> ShaderMaterial:
	return make_material_for_line(owned.shiny_line_id if not owned.shiny_line_id.is_empty() else line_id(owned.definition_id, catalog))

static func make_material_for_line(root_id: StringName) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SHADER
	var selected := palette(root_id)
	for parameter in selected.parameters:
		material.set_shader_parameter(parameter, selected.parameters[parameter])
	return material
