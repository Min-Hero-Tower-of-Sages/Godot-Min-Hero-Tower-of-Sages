extends Node

const DEFAULT_INPUT := "res://development/staged_import/content-20260911-j"
const DEFAULT_MOVE_INPUT := "res://development/staged_import/moves-20260911-g"
const DEFAULT_OUTPUT := "res://content/imported/recovered-20260911"
const MinionPresentation = preload("res://src/content/minion_presentation_definition.gd")
const DamageExecutor = preload("res://src/domain/battle/damage_effect_executor.gd")
const HealExecutor = preload("res://src/domain/battle/heal_effect_executor.gd")
const EnergyExecutor = preload("res://src/domain/battle/energy_effect_executor.gd")
const ShieldExecutor = preload("res://src/domain/battle/shield_effect_executor.gd")
const StatStageExecutor = preload("res://src/domain/battle/stat_stage_effect_executor.gd")
const ConditionExecutor = preload("res://src/domain/battle/condition_effect_executor.gd")
const PeriodicExecutor = preload("res://src/domain/battle/periodic_effect_executor.gd")
const SelfDamageExecutor = preload("res://src/domain/battle/self_damage_effect_executor.gd")

func _ready() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var input_path: String = arguments[0] if arguments.size() >= 1 else DEFAULT_INPUT
	var output_path: String = arguments[1] if arguments.size() >= 2 else DEFAULT_OUTPUT
	var move_input_path: String = arguments[2] if arguments.size() >= 3 else DEFAULT_MOVE_INPUT
	var errors: Array[String] = []
	var types: Array = _load_json(input_path.path_join("types.json"), errors) as Array
	var type_chart: Dictionary = _load_json_object(input_path.path_join("type_chart.json"), errors)
	var minions: Array = _load_json(input_path.path_join("minions.json"), errors) as Array
	var talent_trees: Array = _load_json(input_path.path_join("talent_trees.json"), errors) as Array
	var move_index: Array = _load_json(input_path.path_join("move_index.json"), errors) as Array
	var moves: Array = _load_json(move_input_path.path_join("moves.json"), errors) as Array
	if not errors.is_empty():
		_finish(errors, 0, 0, 0, 0, 0)
		return
	var absolute_output := ProjectSettings.globalize_path(output_path)
	if DirAccess.dir_exists_absolute(absolute_output):
		errors.append("refusing to overwrite staged Resource directory: %s" % output_path)
		_finish(errors, 0, 0, 0, 0, 0)
		return
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute_output.path_join("types"))
	if directory_error != OK:
		errors.append("cannot create output directory: %s" % error_string(directory_error))
		_finish(errors, 0, 0, 0, 0, 0)
		return
	DirAccess.make_dir_recursive_absolute(absolute_output.path_join("minions"))
	DirAccess.make_dir_recursive_absolute(absolute_output.path_join("presentations"))
	DirAccess.make_dir_recursive_absolute(absolute_output.path_join("moves"))
	DirAccess.make_dir_recursive_absolute(absolute_output.path_join("talent_trees"))
	DirAccess.make_dir_recursive_absolute(absolute_output.path_join("type_charts"))
	var type_count := _save_types(types, output_path, errors)
	var type_chart_count := _save_type_chart(type_chart, output_path, errors)
	var presentation_count := _save_presentations(minions, output_path, errors)
	var minion_count := _save_minions(minions, output_path, errors)
	var move_count := _save_moves(moves, output_path, errors)
	move_count += _save_unconstructed_moves(move_index, moves, output_path, errors)
	var talent_tree_count := _save_talent_trees(talent_trees, output_path, errors)
	var catalog_count := _save_catalog(output_path, errors) if errors.is_empty() else 0
	_finish(errors, type_count, type_chart_count, minion_count, presentation_count, move_count, talent_tree_count, catalog_count)

func _load_json(path: String, errors: Array[String]) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		errors.append("cannot read %s: %s" % [path, error_string(FileAccess.get_open_error())])
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Array: errors.append("%s is not a JSON array" % path)
	return parsed

func _load_json_object(path: String, errors: Array[String]) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		errors.append("cannot read %s: %s" % [path, error_string(FileAccess.get_open_error())])
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		errors.append("%s is not a JSON object" % path)
		return {}
	return parsed as Dictionary

func _save_types(entries: Array, output: String, errors: Array[String]) -> int:
	var count := 0
	for entry in entries:
		var definition := TypeDefinition.new()
		_apply_identity(definition, entry)
		definition.legacy_numeric_id = int(entry.legacy_numeric_id) if entry.legacy_numeric_id != null else -1
		if _save(definition, output.path_join("types").path_join(_filename(definition.id)), errors): count += 1
	return count

func _save_type_chart(entry: Dictionary, output: String, errors: Array[String]) -> int:
	if entry.is_empty(): return 0
	var definition := TypeChartDefinition.new()
	_apply_identity(definition, entry)
	definition.default_multiplier = float(entry.default_multiplier)
	definition.not_effective_multiplier = float(entry.not_effective_multiplier)
	definition.super_effective_multiplier = float(entry.super_effective_multiplier)
	definition.multipliers = entry.multipliers.duplicate(true)
	return 1 if _save(definition, output.path_join("type_charts").path_join(_filename(definition.id)), errors) else 0

func _save_presentations(entries: Array, output: String, errors: Array[String]) -> int:
	var count := 0
	var seen: Dictionary = {}
	for entry in entries:
		var presentation_id := StringName(entry.presentation_id)
		var signature := "%s|%d|%d" % [entry.migration.legacy_sprite, entry.icon_offset_x, entry.icon_offset_y]
		if seen.has(presentation_id):
			if seen[presentation_id] != signature:
				errors.append("presentation %s has conflicting sprite metadata" % presentation_id)
			continue
		seen[presentation_id] = signature
		var definition: Variant = MinionPresentation.new()
		definition.id = presentation_id
		definition.display_name = "%s presentation" % entry.display_name
		definition.source_location = "%s:%d" % [entry.migration.source, entry.migration.line]
		definition.source_mod = StringName(entry.migration.source_mod)
		definition.legacy_sprite_name = StringName(entry.migration.legacy_sprite)
		definition.icon_offset = Vector2i(int(entry.icon_offset_x), int(entry.icon_offset_y))
		if _save(definition, output.path_join("presentations").path_join(_filename(definition.id)), errors): count += 1
	return count

func _save_minions(entries: Array, output: String, errors: Array[String]) -> int:
	var count := 0
	for entry in entries:
		var definition := MinionDefinition.new()
		_apply_identity(definition, entry)
		definition.legacy_numeric_id = int(entry.migration.legacy_numeric_id) if entry.migration.legacy_numeric_id != null else -1
		definition.legacy_class_name = String(entry.migration.legacy_function)
		definition.source_location = "%s:%d" % [entry.migration.source, entry.migration.line]
		definition.source_mod = StringName(entry.migration.source_mod)
		definition.base_health = int(entry.base_stats.health)
		definition.base_energy = int(entry.base_stats.energy)
		definition.base_attack = int(entry.base_stats.attack)
		definition.base_healing = int(entry.base_stats.healing)
		definition.base_speed = int(entry.base_stats.speed)
		definition.type_ids = _string_names(entry.types)
		definition.initial_move_ids = _string_names(entry.initial_move_ids)
		definition.specialization_move_ids = _string_names(entry.specialization_move_ids)
		definition.talent_tree_ids = _string_names(entry.talent_tree_ids.filter(func(value): return value != null))
		definition.evolution_id = StringName(entry.evolution_id) if entry.evolution_id != null else &""
		definition.evolution_level = int(entry.evolution_level)
		definition.experience_gain_rate = int(entry.experience_gain_rate)
		definition.gem_slots = int(entry.gem_slots)
		definition.locked_gem_slots = int(entry.locked_gem_slots)
		definition.presentation_id = StringName(entry.presentation_id)
		if _save(definition, output.path_join("minions").path_join(_filename(definition.id)), errors): count += 1
	return count

func _save_talent_trees(entries: Array, output: String, errors: Array[String]) -> int:
	var count := 0
	for entry in entries:
		var definition := TalentTreeDefinition.new()
		_apply_identity(definition, entry)
		definition.legacy_class_name = String(entry.legacy_function)
		definition.source_location = "%s:%d" % [entry.source, entry.line]
		definition.nodes.assign((entry.nodes as Array).duplicate(true))
		if _save(definition, output.path_join("talent_trees").path_join(_filename(definition.id)), errors): count += 1
	return count

func _save_moves(entries: Array, output: String, errors: Array[String]) -> int:
	var count := 0
	for entry in entries:
		var definition := MoveDefinition.new()
		_apply_identity(definition, entry)
		definition.family_id = StringName(entry.family_id)
		definition.tier = int(entry.tier)
		definition.type_id = StringName(entry.type_id)
		definition.legacy_numeric_id = int(entry.legacy_numeric_id)
		definition.legacy_class_id = int(entry.legacy_class_id)
		definition.legacy_visual_id = int(entry.legacy_visual_id)
		definition.legacy_dot_visual_id = int(entry.legacy_dot_visual_id)
		definition.buff_icon_name = StringName(entry.buff_icon)
		definition.available = not (entry.effects as Array).is_empty()
		definition.is_passive = bool(entry.is_passive)
		definition.is_global_passive = bool(entry.is_global_passive)
		definition.energy_cost = int(entry.energy_used)
		definition.cooldown_turns = int(entry.cooldown)
		definition.charge_turns = int(entry.charge_time)
		definition.exhaust_turns = int(entry.exhaust_time)
		definition.accuracy_percent = int(entry.accuracy)
		definition.enemy_target_count = int(entry.enemies_hit)
		definition.ally_target_count = int(entry.allies_hit)
		definition.random_targets = bool(entry.hits_random)
		definition.only_self = bool(entry.only_self)
		definition.hit_each_target = bool(entry.hits_each_enemy)
		definition.visuals_have_buffer = bool(entry.visuals_have_buffer)
		if definition.only_self:
			definition.target_side = MoveDefinition.TargetSide.SELF
		elif definition.enemy_target_count == 0 and definition.ally_target_count > 0:
			definition.target_side = MoveDefinition.TargetSide.ALLY
		else:
			definition.target_side = MoveDefinition.TargetSide.ENEMY
		definition.target_count = maxi(1, definition.enemy_target_count if definition.target_side == MoveDefinition.TargetSide.ENEMY else definition.ally_target_count)
		definition.target_mode = MoveDefinition.TargetMode.RANDOM if definition.random_targets else (MoveDefinition.TargetMode.ALL if definition.target_count >= 5 else MoveDefinition.TargetMode.CHOSEN)
		definition.presentation_id = StringName("%s:presentation/move/%s" % [String(entry.id).get_slice(":", 0), String(entry.icon).to_snake_case()])
		var normalized_effects: Array[EffectDefinition] = []
		for effect_entry in entry.effects:
			var effect := EffectDefinition.new()
			effect.id = StringName(effect_entry.id)
			effect.display_name = String(effect_entry.kind_name).replace("_", " ").capitalize()
			effect.source_location = "%s:%d" % [entry.source, entry.line]
			effect.kind = int(effect_entry.kind) as EffectDefinition.Kind
			effect.target_scope = int(effect_entry.target_scope) as EffectDefinition.TargetScope
			effect.phase = int(effect_entry.phase) as EffectDefinition.Phase
			effect.scaling = int(effect_entry.scaling) as EffectDefinition.Scaling
			effect.roll_scope = int(effect_entry.roll_scope) as EffectDefinition.RollScope
			effect.amount = int(effect_entry.amount)
			effect.random_bonus = int(effect_entry.random_bonus)
			effect.chance_percent = int(effect_entry.chance_percent)
			effect.stat_type_id = StringName(effect_entry.stat_type_id)
			effect.duration = int(effect_entry.duration)
			effect.uses_type_effectiveness = bool(effect_entry.uses_type_effectiveness)
			effect.can_critical = bool(effect_entry.can_critical)
			effect.blocked_by_battle_mod_shield = bool(effect_entry.blocked_by_battle_mod_shield)
			effect.legacy_order = int(effect_entry.legacy_order)
			effect.executor = _executor_for_kind(effect.kind)
			effect.implementation_status = EffectDefinition.ImplementationStatus.IMPLEMENTED
			normalized_effects.append(effect)
		definition.effects = normalized_effects
		if _save(definition, output.path_join("moves").path_join(_filename(definition.id)), errors): count += 1
	return count

func _save_unconstructed_moves(index_entries: Array, constructed_entries: Array, output: String, errors: Array[String]) -> int:
	var constructed: Dictionary = {}
	for entry in constructed_entries: constructed[StringName(entry.id)] = true
	var count := 0
	for entry in index_entries:
		if constructed.has(StringName(entry.id)): continue
		var definition := MoveDefinition.new()
		definition.id = StringName(entry.id)
		definition.display_name = "%s (unavailable)" % String(entry.legacy_constant).trim_suffix("_t%d" % entry.tier).replace("_", " ").capitalize()
		definition.description = "Declared in the source ID table but never constructed by the recovered move container."
		definition.source_location = String(entry.source)
		definition.source_mod = StringName(String(entry.id).get_slice(":", 0))
		definition.legacy_numeric_id = int(entry.legacy_numeric_id)
		definition.legacy_class_name = String(entry.legacy_constant)
		definition.family_id = StringName(entry.family_id)
		definition.tier = int(entry.tier)
		definition.type_id = &"base:type/none"
		definition.available = false
		definition.energy_cost = 0
		if _save(definition, output.path_join("moves").path_join(_filename(definition.id)), errors): count += 1
	return count

func _executor_for_kind(kind: EffectDefinition.Kind) -> Script:
	match kind:
		EffectDefinition.Kind.DAMAGE:
			return DamageExecutor
		EffectDefinition.Kind.SELF_DAMAGE, EffectDefinition.Kind.HEALTH_PERCENT_DAMAGE:
			return SelfDamageExecutor
		EffectDefinition.Kind.HEAL:
			return HealExecutor
		EffectDefinition.Kind.ENERGY:
			return EnergyExecutor
		EffectDefinition.Kind.SHIELD:
			return ShieldExecutor
		EffectDefinition.Kind.STAT_STAGE:
			return StatStageExecutor
		EffectDefinition.Kind.STUN, EffectDefinition.Kind.FREEZE, EffectDefinition.Kind.CLEAR_BUFFS_DEBUFFS:
			return ConditionExecutor
		EffectDefinition.Kind.PERIODIC_DAMAGE, EffectDefinition.Kind.PERIODIC_HEAL, EffectDefinition.Kind.ARMOR, EffectDefinition.Kind.REFLECT:
			return PeriodicExecutor
		_:
			return null

func _apply_identity(definition: ContentDefinition, entry: Dictionary) -> void:
	definition.id = StringName(entry.id)
	definition.display_name = String(entry.display_name)
	definition.source_location = String(entry.get("source", ""))
	definition.source_mod = StringName(String(entry.id).get_slice(":", 0))

func _save_catalog(output: String, errors: Array[String]) -> int:
	var by_namespace: Dictionary = {}
	for folder in ["types", "type_charts", "minions", "presentations", "moves", "talent_trees"]:
		for filename in DirAccess.get_files_at(output.path_join(folder)):
			if not filename.ends_with(".tres"): continue
			var path := output.path_join(folder).path_join(filename)
			var definition := ResourceLoader.load(path) as ContentDefinition
			if definition == null:
				errors.append("cannot load generated definition %s" % path)
				continue
			var pack_namespace := String(definition.id).get_slice(":", 0)
			if not by_namespace.has(pack_namespace): by_namespace[pack_namespace] = []
			(by_namespace[pack_namespace] as Array).append(definition)
	var catalog := ContentCatalog.new()
	catalog.content_version = "2026.09.11-recovered"
	var namespaces: Array = by_namespace.keys()
	namespaces.sort()
	for pack_namespace in namespaces:
		var pack := ContentPackDefinition.new()
		pack.id = StringName("%s:pack/recovered" % pack_namespace)
		pack.display_name = "%s recovered content" % String(pack_namespace).replace("_", " ").capitalize()
		pack.source_mod = StringName(pack_namespace)
		pack.enabled_by_default = true
		if pack_namespace != "base": pack.dependencies = [&"base:pack/recovered"]
		pack.definitions.assign(by_namespace[pack_namespace])
		catalog.packs.append(pack)
	var validation := catalog.rebuild_index()
	for error in validation: errors.append("catalog: %s" % error)
	if not errors.is_empty(): return 0
	return 1 if _save(catalog, output.path_join("catalog.tres"), errors) else 0

func _string_names(values: Array) -> Array[StringName]:
	var result: Array[StringName] = []
	for value in values: result.append(StringName(value))
	return result

func _filename(id: StringName) -> String:
	return String(id).replace(":", "__").replace("/", "_") + ".tres"

func _save(resource: Resource, path: String, errors: Array[String]) -> bool:
	var result := ResourceSaver.save(resource, path)
	if result != OK: errors.append("failed saving %s: %s" % [path, error_string(result)])
	return result == OK

func _finish(errors: Array[String], type_count: int, type_chart_count: int, minion_count: int, presentation_count: int, move_count: int, talent_tree_count := 0, catalog_count := 0) -> void:
	if errors.is_empty():
		print("IMPORT PASS: %d types, %d type charts, %d minions, %d presentations, %d moves, %d talent trees, %d catalog" % [type_count, type_chart_count, minion_count, presentation_count, move_count, talent_tree_count, catalog_count])
	else:
		for error in errors: push_error(error)
		print("IMPORT FAIL: %d errors" % errors.size())
	await get_tree().create_timer(3.0).timeout
	get_tree().quit(0 if errors.is_empty() else 1)
