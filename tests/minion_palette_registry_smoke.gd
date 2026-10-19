extends SceneTree

const SERVICE := preload("res://src/presentation/minion_palette_service.gd")
const LIMITS := {
	"hue_shift": [-1.0, 1.0], "source_hue": [-1.0, 1.0], "hue_width": [0.0, 0.5],
	"saturation_scale": [0.0, 2.0], "value_scale": [0.0, 2.0],
	"minimum_saturation": [0.0, 1.0], "minimum_value": [0.0, 1.0],
	"target_hue": [-1.0, 1.0], "saturation_floor": [0.0, 1.0], "neutral_tint_strength": [0.0, 1.0],
	"neutral_target_hue": [-1.0, 1.0], "neutral_saturation": [0.0, 1.0], "neutral_value_scale": [0.0, 3.0], "neutral_saturation_max": [0.14, 1.0],
}

func _initialize() -> void:
	var catalog: ContentCatalog = load("res://content/imported/recovered-20260911/catalog.tres")
	assert(catalog.ensure_index().is_empty())
	var registry := SERVICE.registry()
	assert(registry.lines.size() == 62 and registry.members.size() == 122)
	var covered := 0
	for definition in catalog._by_id.values():
		if not definition is MinionDefinition or String(definition.id).begins_with("internal:") or definition.display_name == "Eevee": continue
		assert(registry.members.has(String(definition.id)), "Every playable form has an assignment")
		var choice := SERVICE.palette(definition.id, catalog)
		assert(not choice.procedural and not choice.parameters.is_empty())
		if not definition.evolution_id.is_empty():
			assert(choice.parameters == SERVICE.palette(definition.evolution_id, catalog).parameters, "Same scheme across evolution")
		for parameter in choice.parameters:
			assert(LIMITS.has(parameter))
			assert(float(choice.parameters[parameter]) >= LIMITS[parameter][0] and float(choice.parameters[parameter]) <= LIMITS[parameter][1])
		covered += 1
	assert(covered == 122)
	assert(SERVICE.palette(&"base:minion/tiger_1").parameters.hue_shift == 0.5)
	assert(SERVICE.palette(&"base:minion/fire_pig_1").parameters.hue_shift == 0.69)
	assert(SERVICE.palette(&"arkvian:minion/holybird1").parameters.hue_shift == 0.35)
	# Future models inherit a deterministic family palette without a new PNG.
	var parent := MinionDefinition.new()
	parent.id = &"future:minion/new_stage1"
	parent.evolution_id = &"future:minion/new_stage2"
	var child := MinionDefinition.new()
	child.id = parent.evolution_id
	catalog._by_id[parent.id] = parent
	catalog._by_id[child.id] = child
	var first := SERVICE.palette(parent.id, catalog)
	assert(first.procedural and first.parameters == SERVICE.palette(child.id, catalog).parameters)
	var material := SERVICE.make_material(child.id, catalog)
	assert(is_equal_approx(material.get_shader_parameter("hue_shift"), first.parameters.hue_shift))
	var copy := SERVICE.palette(&"base:minion/tiger_1")
	copy.parameters.hue_shift = 0.0
	assert(SERVICE.palette(&"base:minion/tiger_1").parameters.hue_shift == 0.5, "Callers cannot mutate shared settings")
	catalog._by_id.erase(parent.id)
	catalog._by_id.erase(child.id)
	print("PASS: 62 palette lines / 122 forms, evolution consistency, uniform bounds, approved schemes and future-family fallback")
	quit()
