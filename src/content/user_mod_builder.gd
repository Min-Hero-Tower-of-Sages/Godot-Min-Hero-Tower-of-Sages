class_name UserModBuilder
extends RefCounted

## Turns a user mod manifest (plain JSON data) into content definitions and
## reversible edits of existing content. Mods never carry scripts: every effect
## kind maps to an engine executor chosen here, so a shared mod cannot run code.
## The format is documented in docs/USER_MODS.md.

const FORMAT_VERSION := 1
const ID_PATTERN := "^[a-z][a-z0-9_]{1,31}$"
const LOCAL_ID_PATTERN := "^[a-z0-9_]+$"
const TEXT_FIELDS := ["id", "name", "version", "author", "description", "target", "attacker", "defender", "result", "based_on", "looks_like", "type", "evolves_into", "from", "file", "badge", "move_badge", "kind", "phase", "scaling", "roll", "removal", "stat", "target_side", "target_mode", "trainer_name", "first_visit_text", "repeat_text", "after_win_text", "mode", "target_room_id", "target_spawn_id", "encounter_id", "text", "locked_text", "add"]
const NUMBER_FIELDS := ["format", "energy_cost", "cooldown", "charge", "exhaust", "accuracy", "target_count", "enemy_target_count", "ally_target_count", "amount", "random_bonus", "chance", "duration", "health", "energy", "attack", "healing", "speed", "xp_rate", "gem_slots", "locked_gem_slots", "evolution_level", "hue_shift", "saturation", "value", "money", "level", "floor", "weight", "transition_id", "required_floor_keys", "required_eggery_keys", "column", "row", "x", "y", "index", "x_scale", "y_scale", "rotation"]
const BOOL_FIELDS := ["passive", "global_passive", "hit_each_target", "random_targets", "only_self", "type_effectiveness", "can_critical", "blocked_by_shield", "remove"]
const STAT_FIELDS := {"health": "base_health", "energy": "base_energy", "attack": "base_attack", "healing": "base_healing", "speed": "base_speed"}
const SECTIONS := ["types", "type_chart", "moves", "talent_trees", "minions", "minion_patches", "move_patches", "trainers", "hatchery", "rooms", "floors"]
const DAMAGE := preload("res://src/domain/battle/damage_effect_executor.gd")
const HEAL := preload("res://src/domain/battle/heal_effect_executor.gd")
const ENERGY := preload("res://src/domain/battle/energy_effect_executor.gd")
const STAT_STAGE := preload("res://src/domain/battle/stat_stage_effect_executor.gd")
const SHIELD := preload("res://src/domain/battle/shield_effect_executor.gd")
const PERIODIC := preload("res://src/domain/battle/periodic_effect_executor.gd")
const SELF_DAMAGE := preload("res://src/domain/battle/self_damage_effect_executor.gd")
const CONDITION := preload("res://src/domain/battle/condition_effect_executor.gd")
## The kind -> executor pairs used by every recovered move. Kinds the recovered
## content never constructs (status application/removal, revive, cooldown) are
## not offered: the engine has no tested path for them.
const EXECUTORS := {
	EffectDefinition.Kind.DAMAGE: DAMAGE,
	EffectDefinition.Kind.HEAL: HEAL,
	EffectDefinition.Kind.ENERGY: ENERGY,
	EffectDefinition.Kind.STAT_STAGE: STAT_STAGE,
	EffectDefinition.Kind.SHIELD: SHIELD,
	EffectDefinition.Kind.REFLECT: PERIODIC,
	EffectDefinition.Kind.PERIODIC_DAMAGE: PERIODIC,
	EffectDefinition.Kind.PERIODIC_HEAL: PERIODIC,
	EffectDefinition.Kind.ARMOR: PERIODIC,
	EffectDefinition.Kind.SELF_DAMAGE: SELF_DAMAGE,
	EffectDefinition.Kind.HEALTH_PERCENT_DAMAGE: SELF_DAMAGE,
	EffectDefinition.Kind.STUN: CONDITION,
	EffectDefinition.Kind.FREEZE: CONDITION,
	EffectDefinition.Kind.CLEAR_BUFFS_DEBUFFS: CONDITION,
	EffectDefinition.Kind.STAT_PERCENT: null,
	EffectDefinition.Kind.REDIRECT_DAMAGE: null,
	EffectDefinition.Kind.CRITICAL_CHANCE: null,
}
## The in-game talent screen is a fixed 3 x 4 grid and each skill has up to
## five ranks (usually the tiers of one move).
const TREE_COLUMNS := 3
const TREE_ROWS := 4
const TREE_MAX_RANKS := 5
const MATCHUPS := {"strong": 1.5, "weak": 0.66666666667, "normal": 1.0}
const ROOM_INTERACTION_FIELDS := {
	"egg_pick": ["candidates", "weights"],
	"unlock_eggery_door": ["required_eggery_keys", "locked_text"],
	"unlock_boss_door": ["required_floor_keys", "locked_text"],
	"gem_shop": ["text"], "gem_combiner": ["text", "locked_text"], "minion_storage": ["text", "locked_text"],
}

## Records the original value of every property a mod changes, so turning the
## mod off restores the shared catalog exactly.
class ChangeLog:
	var _entries: Array = []
	var _seen: Dictionary = {}

	func assign(target: Object, property: StringName, value: Variant) -> void:
		var key := "%d/%s" % [target.get_instance_id(), property]
		if not _seen.has(key):
			_seen[key] = true
			var original: Variant = target.get(property)
			_entries.append([target, property, original.duplicate(true) if original is Array or original is Dictionary else original])
		target.set(property, value)

	func revert() -> void:
		for index in range(_entries.size() - 1, -1, -1):
			var entry: Array = _entries[index]
			(entry[0] as Object).set(entry[1], entry[2])
		_entries.clear()
		_seen.clear()

	func is_empty() -> bool:
		return _entries.is_empty()

var catalog: ContentCatalog
var manifest: Dictionary
var mod_id: String
var changes := ChangeLog.new()
var errors := PackedStringArray()
var pack: ContentPackDefinition
## Room edits are re-applied after every index rebuild (rooms are rebuilt from
## their JSON graphs), so they are kept as data rather than applied once.
var room_edits: Array[Dictionary] = []
var hatchery_rules: Array[Dictionary] = []
var dialogue: Dictionary = {}
## virtual sprite name -> {"from": definition id or "", "file": path or "", "hue_shift"...}
var sprite_requests: Dictionary = {}
var type_badges: Dictionary = {}
## Packs of mods activated earlier in the same set, so a mod can use
## another mod's content.
var prior_packs: Array[ContentPackDefinition] = []
var _added: Dictionary = {}

static func enum_names(values: Dictionary) -> PackedStringArray:
	var names := PackedStringArray()
	for key in values: names.append(String(key).to_lower())
	return names

static func effect_kind_names() -> PackedStringArray:
	var names := PackedStringArray()
	for kind in EXECUTORS: names.append(String(EffectDefinition.Kind.keys()[kind]).to_lower())
	return names

static func enum_name(values: Dictionary, value: int) -> String:
	for key in values:
		if int(values[key]) == value: return String(key).to_lower()
	return ""

static func header_errors(data: Variant) -> PackedStringArray:
	var problems := PackedStringArray()
	if not data is Dictionary:
		problems.append("the mod file is not a JSON object")
		return problems
	problems.append_array(_shape_errors(data, "mod"))
	if not problems.is_empty(): return problems
	if int(data.get("format", 0)) != FORMAT_VERSION:
		problems.append("unsupported mod format %s (this game reads format %d)" % [data.get("format", "?"), FORMAT_VERSION])
	var regex := RegEx.create_from_string(ID_PATTERN)
	if regex.search(String(data.get("id", ""))) == null or String(data.get("id", "")) in ["base", "extended", "user"]:
		problems.append("mod id must be 2-32 lowercase letters, digits or underscores, starting with a letter")
	if String(data.get("name", "")).strip_edges().is_empty():
		problems.append("mod has no name")
	for section in SECTIONS:
		if data.has(section) and not data[section] is Array:
			problems.append("%s must be a list" % section)
		elif data.has(section):
			for entry in data[section]:
				if not entry is Dictionary: problems.append("%s entries must be objects" % section)
	return problems

## Check JSON shapes before converting values or mutating the catalog. Unknown
## fields remain inert; only the explicitly supported fields below are applied.
static func _shape_errors(record: Dictionary, context: String) -> PackedStringArray:
	var problems := PackedStringArray()
	for key in record:
		var value: Variant = record[key]
		var field := "%s.%s" % [context, key]
		if key in TEXT_FIELDS and not value is String:
			problems.append("%s must be text" % field)
		elif key in NUMBER_FIELDS and not ((value is int or value is float) and is_finite(float(value))):
			problems.append("%s must be a number" % field)
		elif key in BOOL_FIELDS and not value is bool:
			problems.append("%s must be true or false" % field)
		elif key in ["stats", "sprite", "set"]:
			if not value is Dictionary: problems.append("%s must be an object" % field)
		elif key in SECTIONS + ["tiers", "effects", "team", "entries", "exits", "interactions", "initial_moves", "specialization_moves", "talent_trees", "moves", "weights", "candidates", "nodes", "requires", "spawns", "objects", "features"]:
			if not value is Array: problems.append("%s must be a list" % field)
		elif key in ["width", "height", "entry_x", "entry_y", "map_x", "map_y"] and not ((value is int or value is float) and is_finite(float(value))):
			problems.append("%s must be a finite number" % field)
		elif key in ["template", "start_room", "destination", "requires_trainer", "minion", "art", "mount", "label"] and not value is String:
			problems.append("%s must be text" % field)
		elif key == "above_player" and not value is bool:
			problems.append("%s must be true or false" % field)
		if value is Dictionary:
			problems.append_array(_shape_errors(value, field))
		elif value is Array:
			for index in value.size():
				if value[index] is Dictionary: problems.append_array(_shape_errors(value[index], "%s[%d]" % [field, index]))
	return problems

func _init(source: Dictionary, target_catalog: ContentCatalog) -> void:
	manifest = source
	catalog = target_catalog
	mod_id = String(source.get("id", ""))

## Builds the mod's own pack and applies its edits to existing definitions.
## On failure everything already changed is reverted and `errors` explains why.
func build() -> bool:
	errors = header_errors(manifest)
	if not errors.is_empty(): return false
	pack = ContentPackDefinition.new()
	pack.id = StringName("%s:pack/user_mod" % mod_id)
	pack.display_name = String(manifest.get("name", mod_id))
	pack.source_mod = StringName("user:%s" % mod_id)
	# Additions first so edits and references can point at them.
	for record in manifest.get("types", []): _add_type(record)
	for record in manifest.get("moves", []): _add_move_family(record)
	for record in manifest.get("talent_trees", []): _add_talent_tree(record)
	for record in manifest.get("minions", []): _add_minion(record)
	for record in manifest.get("type_chart", []): _edit_matchup(record)
	for record in manifest.get("minion_patches", []): _patch_minion(record)
	for record in manifest.get("move_patches", []): _patch_move(record)
	for record in manifest.get("trainers", []): _edit_trainer(record)
	for record in manifest.get("hatchery", []): _add_hatchery_rule(record)
	for record in manifest.get("rooms", []): _add_room_edit(record)
	for record in manifest.get("floors", []): _add_custom_floor(record)
	if not errors.is_empty():
		changes.revert()
		return false
	return true

## Move tiers as the mod would build them, for previews (e.g. the Workshop's
## hover cards): {tier id: MoveDefinition}. Nothing is registered or edited;
## a changed existing move comes back as an edited copy under its own ID.
## Records that would not build are left out rather than reported.
static func preview_moves(source: Dictionary, target_catalog: ContentCatalog) -> Dictionary:
	var builder := new(source, target_catalog)
	builder.pack = ContentPackDefinition.new()
	builder.pack.source_mod = StringName("user:%s" % builder.mod_id)
	for record in source.get("types", []): builder._add_type(record)
	for record in source.get("moves", []): builder._add_move_family(record)
	var result: Dictionary = {}
	for definition in builder.pack.definitions:
		if definition is MoveDefinition: result[String(definition.id)] = definition
	for record in source.get("move_patches", []):
		if not record is Dictionary: continue
		var original := builder._lookup(record.get("target", ""), MoveDefinition) as MoveDefinition
		if original == null: continue
		var copy := original.duplicate() as MoveDefinition
		var failures := builder.errors.size()
		builder._apply_move_fields(copy, record, false)
		if builder.errors.size() == failures: result[String(original.id)] = copy
	return result

func _context(record: Variant, kind: String) -> String:
	return "%s %s" % [kind, record.get("id", record.get("target", "?"))] if record is Dictionary else kind

func _fail(message: String) -> bool:
	errors.append("%s: %s" % [mod_id, message])
	return false

func _own_id(record: Dictionary, category: String) -> StringName:
	var raw := String(record.get("id", ""))
	var prefix := "%s:%s/" % [mod_id, category]
	if not raw.begins_with(prefix) or RegEx.create_from_string(LOCAL_ID_PATTERN).search(raw.trim_prefix(prefix)) == null:
		_fail("%s id %s must start with %s and use lowercase letters, digits or underscores" % [category, raw, prefix])
		return &""
	if _added.has(raw) or _lookup(raw, ContentDefinition) != null:
		_fail("%s id %s is already used" % [category, raw])
		return &""
	_added[raw] = true
	return StringName(raw)

func _lookup(id: Variant, script_type: Variant) -> ContentDefinition:
	var key := StringName(String(id))
	for definition in pack.definitions:
		if definition.id == key: return definition if is_instance_of(definition, script_type) else null
	var existing := catalog.get_definition(key)
	if existing == null:
		for prior in prior_packs:
			for definition in prior.definitions:
				if definition.id == key: existing = definition
	return existing if existing != null and is_instance_of(existing, script_type) else null

func _put(target: Object, property: StringName, value: Variant, editing: bool) -> void:
	if editing: changes.assign(target, property, value)
	else: target.set(property, value)

func _string_names(values: Variant, context: String, script_type: Variant, minimum: int, maximum: int) -> Variant:
	if not values is Array:
		_fail("%s must be a list" % context)
		return null
	if values.size() < minimum or values.size() > maximum:
		_fail("%s needs %d to %d entries" % [context, minimum, maximum])
		return null
	var result: Array[StringName] = []
	for value in values:
		if not value is String:
			_fail("%s entries must be content IDs" % context)
			return null
		if script_type != null and _lookup(value, script_type) == null:
			_fail("%s references unknown %s" % [context, value])
			return null
		result.append(StringName(String(value)))
	return result

func _int(record: Dictionary, key: String, minimum: int, maximum: int, fallback: int) -> int:
	var value: Variant = record.get(key, fallback)
	if not (value is int or value is float) or not is_finite(float(value)):
		_fail("%s must be a number" % key)
		return fallback
	return clampi(int(value), minimum, maximum)

# --- Types -----------------------------------------------------------------

func _add_type(record: Variant):
	if not record is Dictionary: return _fail("type entries must be objects")
	var id := _own_id(record, "type")
	if id.is_empty(): return
	# Type art is looked up by the last ID segment, so it must not shadow a
	# recovered type's badges.
	for existing in catalog._by_id.values():
		if existing is TypeDefinition and String(existing.id).get_file() == String(id).get_file():
			return _fail("type %s would share art with %s; choose another name" % [id, existing.id])
	for prior in prior_packs:
		for existing in prior.definitions:
			if existing is TypeDefinition and String(existing.id).get_file() == String(id).get_file():
				return _fail("type %s would share art with %s; choose another name" % [id, existing.id])
	var type := TypeDefinition.new()
	type.id = id
	type.display_name = String(record.get("name", "")).strip_edges().left(16)
	type.description = String(record.get("description", ""))
	type.source_mod = pack.source_mod
	type.color = Color.from_string(String(record.get("color", "#ffffff")), Color.WHITE)
	if type.display_name.is_empty(): return _fail("type %s has no name" % id)
	pack.definitions.append(type)
	type_badges[String(id)] = {"name": type.display_name, "color": type.color, "badge": String(record.get("badge", "")), "move_badge": String(record.get("move_badge", ""))}

func _edit_matchup(record: Variant):
	if not record is Dictionary: return _fail("type chart entries must be objects")
	var chart := catalog.get_type_chart()
	if chart == null: return _fail("the game has no type chart")
	var attacker := String(record.get("attacker", ""))
	var defender := String(record.get("defender", ""))
	if _lookup(attacker, TypeDefinition) == null or _lookup(defender, TypeDefinition) == null:
		return _fail("type chart entry %s > %s references an unknown type" % [attacker, defender])
	var result := String(record.get("result", ""))
	if not MATCHUPS.has(result): return _fail("type chart result must be strong, weak or normal")
	var multipliers: Dictionary = chart.multipliers.duplicate(true)
	var key := "%s>%s" % [attacker, defender]
	if result == "normal": multipliers.erase(key)
	else: multipliers[key] = MATCHUPS[result]
	changes.assign(chart, &"multipliers", multipliers)

# --- Moves -----------------------------------------------------------------

func _add_move_family(record: Variant):
	if not record is Dictionary: return _fail("move entries must be objects")
	var family := _own_id(record, "move")
	if family.is_empty(): return
	var tiers: Variant = record.get("tiers", [])
	if not tiers is Array or tiers.is_empty() or tiers.size() > 5:
		return _fail("move %s needs 1 to 5 tiers" % family)
	var looks_like := _lookup(record.get("looks_like", ""), MoveDefinition) as MoveDefinition
	if looks_like == null: return _fail("move %s looks_like must name an existing move tier" % family)
	for index in tiers.size():
		var tier_record: Variant = tiers[index]
		if not tier_record is Dictionary: return _fail("move %s tiers must be objects" % family)
		var move := MoveDefinition.new()
		move.id = StringName("%s/tier%d" % [family, index + 1])
		move.family_id = StringName("%s:move_family/%s" % [mod_id, String(family).get_file()])
		move.tier = index + 1
		move.source_mod = pack.source_mod
		for property in [&"legacy_class_id", &"legacy_visual_id", &"legacy_dot_visual_id", &"buff_icon_name", &"presentation_id", &"visuals_have_buffer"]:
			move.set(property, looks_like.get(property))
		var merged: Dictionary = record.duplicate(true)
		merged.erase("tiers")
		merged.merge(tier_record, true)
		if not merged.has("effects"): return _fail("%s has no effects" % move.id)
		_apply_move_fields(move, merged, false)
		pack.definitions.append(move)
		_added[String(move.id)] = true

func _patch_move(record: Variant):
	if not record is Dictionary: return _fail("move patches must be objects")
	var move := _lookup(record.get("target", ""), MoveDefinition) as MoveDefinition
	if move == null: return _fail("move patch target %s is not a move tier" % record.get("target", ""))
	_apply_move_fields(move, record, true)

func _apply_move_fields(move: MoveDefinition, record: Dictionary, editing: bool):
	var context := String(move.id)
	if record.has("name"):
		var display := String(record.name).strip_edges().left(32)
		if display.is_empty(): return _fail("%s needs a name" % context)
		_put(move, &"display_name", display, editing)
	if record.has("description"): _put(move, &"description", String(record.description).left(400), editing)
	if record.has("type"):
		if _lookup(record.type, TypeDefinition) == null: return _fail("%s uses unknown type %s" % [context, record.type])
		_put(move, &"type_id", StringName(String(record.type)), editing)
	var numbers := {"energy_cost": [&"energy_cost", 0, 99], "cooldown": [&"cooldown_turns", 0, 99], "charge": [&"charge_turns", 0, 99], "exhaust": [&"exhaust_turns", 0, 99], "accuracy": [&"accuracy_percent", 0, 100], "target_count": [&"target_count", 1, 5], "enemy_target_count": [&"enemy_target_count", 0, 5], "ally_target_count": [&"ally_target_count", 0, 5]}
	for key in numbers:
		if record.has(key): _put(move, numbers[key][0], _int(record, key, numbers[key][1], numbers[key][2], 0), editing)
	var flags := {"passive": &"is_passive", "global_passive": &"is_global_passive", "hit_each_target": &"hit_each_target", "random_targets": &"random_targets", "only_self": &"only_self"}
	for key in flags:
		if record.has(key): _put(move, flags[key], bool(record[key]), editing)
	if record.has("target_side"): _put(move, &"target_side", _enum(MoveDefinition.TargetSide, record.target_side, context + " target_side"), editing)
	if record.has("target_mode"): _put(move, &"target_mode", _enum(MoveDefinition.TargetMode, record.target_mode, context + " target_mode"), editing)
	if record.has("effects"):
		var effects: Array[EffectDefinition] = []
		if not record.effects is Array or record.effects.is_empty() or record.effects.size() > 8:
			return _fail("%s needs 1 to 8 effects" % context)
		for index in record.effects.size():
			var effect := _build_effect(record.effects[index], "%s/effect/%02d" % [move.id, index], index)
			if effect == null: return
			effects.append(effect)
		_put(move, &"effects", effects, editing)

func _enum(values: Dictionary, raw: Variant, context: String) -> int:
	var key := String(raw).to_upper()
	if not values.has(key):
		_fail("%s must be one of %s" % [context, ", ".join(enum_names(values))])
		return 0
	return int(values[key])

func _build_effect(record: Variant, id: String, order: int) -> EffectDefinition:
	if not record is Dictionary:
		_fail("%s must be an object" % id)
		return null
	var effect := EffectDefinition.new()
	var kind := String(record.get("kind", "")).to_upper()
	if not EffectDefinition.Kind.has(kind) or not EXECUTORS.has(EffectDefinition.Kind[kind]):
		_fail("%s kind must be one of %s" % [id, ", ".join(effect_kind_names())])
		return null
	effect.kind = EffectDefinition.Kind[kind]
	effect.executor = EXECUTORS[effect.kind]
	effect.id = StringName("%s_%s" % [id, kind.to_lower()])
	effect.display_name = kind.capitalize()
	effect.source_mod = pack.source_mod
	effect.legacy_order = order
	if record.has("target"): effect.set(&"target_scope", _enum(EffectDefinition.TargetScope, record.target, id + " target"))
	if record.has("phase"): effect.set(&"phase", _enum(EffectDefinition.Phase, record.phase, id + " phase"))
	if record.has("scaling"): effect.set(&"scaling", _enum(EffectDefinition.Scaling, record.scaling, id + " scaling"))
	if record.has("roll"): effect.set(&"roll_scope", _enum(EffectDefinition.RollScope, record.roll, id + " roll"))
	if record.has("removal"): effect.set(&"removal_policy", _enum(EffectDefinition.RemovalPolicy, record.removal, id + " removal"))
	effect.amount = _int(record, "amount", -9999, 9999, 0)
	effect.random_bonus = _int(record, "random_bonus", 0, 9999, 0)
	effect.chance_percent = _int(record, "chance", 0, 100, 100)
	effect.duration = _int(record, "duration", 0, 99, 0)
	if record.has("stat") and not String(record.stat).is_empty():
		var stat := String(record.stat).trim_prefix("base:stat/")
		if not STAT_FIELDS.has(stat):
			_fail("%s stat must be one of %s" % [id, ", ".join(STAT_FIELDS.keys())])
			return null
		effect.stat_type_id = StringName("base:stat/%s" % stat)
	if effect.kind in [EffectDefinition.Kind.STAT_STAGE, EffectDefinition.Kind.STAT_PERCENT] and effect.stat_type_id.is_empty():
		_fail("%s needs a stat to change" % id)
		return null
	effect.uses_type_effectiveness = bool(record.get("type_effectiveness", false))
	effect.can_critical = bool(record.get("can_critical", false))
	effect.blocked_by_battle_mod_shield = bool(record.get("blocked_by_shield", false))
	return effect

## The editable JSON form of an effect, the inverse of _build_effect.
static func effect_record(effect: EffectDefinition) -> Dictionary:
	var record := {
		"kind": String(EffectDefinition.Kind.keys()[effect.kind]).to_lower(),
		"target": enum_name(EffectDefinition.TargetScope, effect.target_scope),
		"phase": enum_name(EffectDefinition.Phase, effect.phase),
		"scaling": enum_name(EffectDefinition.Scaling, effect.scaling),
		"roll": enum_name(EffectDefinition.RollScope, effect.roll_scope),
		"removal": enum_name(EffectDefinition.RemovalPolicy, effect.removal_policy),
		"amount": effect.amount, "random_bonus": effect.random_bonus, "chance": effect.chance_percent,
		"duration": effect.duration, "type_effectiveness": effect.uses_type_effectiveness,
		"can_critical": effect.can_critical, "blocked_by_shield": effect.blocked_by_battle_mod_shield,
	}
	if not effect.stat_type_id.is_empty(): record["stat"] = String(effect.stat_type_id).get_file()
	return record

## The editable JSON form of one move tier (all fields explicit).
static func move_record(move: MoveDefinition) -> Dictionary:
	var effects: Array = []
	for effect in move.effects: effects.append(effect_record(effect))
	return {
		"name": move.display_name, "description": move.description, "type": String(move.type_id),
		"energy_cost": move.energy_cost, "cooldown": move.cooldown_turns, "charge": move.charge_turns,
		"exhaust": move.exhaust_turns, "accuracy": move.accuracy_percent,
		"passive": move.is_passive, "global_passive": move.is_global_passive,
		"target_side": enum_name(MoveDefinition.TargetSide, move.target_side),
		"target_mode": enum_name(MoveDefinition.TargetMode, move.target_mode),
		"target_count": move.target_count, "hit_each_target": move.hit_each_target,
		"enemy_target_count": move.enemy_target_count, "ally_target_count": move.ally_target_count,
		"random_targets": move.random_targets, "only_self": move.only_self, "effects": effects,
	}

# --- Talent trees ----------------------------------------------------------

## A tree is a grid of skills. Each skill lists the moves its ranks teach, in
## order, and may require other skills from an earlier row ("column_row" cells).
func _add_talent_tree(record: Variant):
	if not record is Dictionary: return _fail("talent tree entries must be objects")
	var id := _own_id(record, "talent_tree")
	if id.is_empty(): return
	var display := String(record.get("name", "")).strip_edges().left(14)
	if display.is_empty(): return _fail("talent tree %s has no name" % id)
	var raw_nodes: Variant = record.get("nodes", [])
	if not raw_nodes is Array or raw_nodes.size() > TREE_COLUMNS * TREE_ROWS:
		return _fail("talent tree %s needs at most %d skills" % [id, TREE_COLUMNS * TREE_ROWS])
	var cells: Dictionary = {}
	for node in raw_nodes:
		if not node is Dictionary: return _fail("talent tree %s skills must be objects" % id)
		var column := _int(node, "column", 0, TREE_COLUMNS - 1, 0)
		var row := _int(node, "row", 0, TREE_ROWS - 1, 0)
		if int(node.get("column", 0)) != column or int(node.get("row", 0)) != row:
			return _fail("talent tree %s has a skill outside its %d x %d grid" % [id, TREE_COLUMNS, TREE_ROWS])
		var cell := "%d_%d" % [column, row]
		if cells.has(cell): return _fail("talent tree %s has two skills in column %d, row %d" % [id, column + 1, row + 1])
		cells[cell] = row
	var tree := TalentTreeDefinition.new()
	tree.id = id
	tree.display_name = display
	tree.source_mod = pack.source_mod
	for node in raw_nodes:
		var context := "talent tree %s skill %d_%d" % [id, int(node.get("column", 0)), int(node.get("row", 0))]
		var moves: Variant = _string_names(node.get("moves", []), context + " moves", MoveDefinition, 1, TREE_MAX_RANKS)
		if moves == null: return
		var prerequisites: Array[String] = []
		var requires: Variant = node.get("requires", [])
		if not requires is Array: return _fail("%s requires must be a list" % context)
		for cell in requires:
			if not cells.has(String(cell)): return _fail("%s requires a skill that does not exist (%s)" % [context, cell])
			if int(cells[String(cell)]) >= int(node.get("row", 0)): return _fail("%s can only require skills from an earlier row" % context)
			prerequisites.append("%s/node/%s" % [id, cell])
		var node_moves: Array[String] = []
		for move_id in moves: node_moves.append(String(move_id))
		tree.nodes.append({"id": "%s/node/%d_%d" % [id, int(node.get("column", 0)), int(node.get("row", 0))], "column": int(node.get("column", 0)), "row": int(node.get("row", 0)), "move_ids": node_moves, "prerequisite_node_ids": prerequisites})
	pack.definitions.append(tree)

## The editable JSON form of an existing tree (copied when starting a new one).
static func tree_record(tree: TalentTreeDefinition) -> Dictionary:
	var cells: Dictionary = {}
	for node in tree.nodes: cells[String(node.get("id", ""))] = "%d_%d" % [int(node.get("column", 0)), int(node.get("row", 0))]
	var nodes: Array = []
	for node in tree.nodes:
		var requires: Array = []
		for prerequisite in node.get("prerequisite_node_ids", []):
			if cells.has(String(prerequisite)): requires.append(cells[String(prerequisite)])
		nodes.append({"column": int(node.get("column", 0)), "row": int(node.get("row", 0)), "moves": Array(node.get("move_ids", [])).map(func(value: Variant) -> String: return String(value)), "requires": requires})
	return {"name": tree.display_name, "nodes": nodes}

# --- Minions ---------------------------------------------------------------

func _add_minion(record: Variant):
	if not record is Dictionary: return _fail("minion entries must be objects")
	var id := _own_id(record, "minion")
	if id.is_empty(): return
	var based_on := _lookup(record.get("based_on", ""), MinionDefinition) as MinionDefinition
	if based_on == null: return _fail("minion %s based_on must name an existing minion" % id)
	var minion := based_on.duplicate(true) as MinionDefinition
	minion.id = id
	minion.source_mod = pack.source_mod
	minion.legacy_numeric_id = -1
	minion.legacy_class_name = ""
	minion.source_location = ""
	# A copy keeps its own line: it never evolves into the original family
	# unless the mod says so.
	minion.evolution_id = &""
	minion.evolution_level = 999
	pack.definitions.append(minion)
	if not record.has("sprite"): record = record.merged({"sprite": {"from": String(based_on.id)}})
	_apply_minion_fields(minion, record, false)

func _patch_minion(record: Variant):
	if not record is Dictionary: return _fail("minion patches must be objects")
	var minion := _lookup(record.get("target", ""), MinionDefinition) as MinionDefinition
	if minion == null: return _fail("minion patch target %s is not a minion" % record.get("target", ""))
	_apply_minion_fields(minion, record, true)

func _apply_minion_fields(minion: MinionDefinition, record: Dictionary, editing: bool):
	var context := String(minion.id)
	if record.has("name"):
		var display := String(record.name).strip_edges().left(24)
		if display.is_empty(): return _fail("%s needs a name" % context)
		_put(minion, &"display_name", display, editing)
	if record.has("description"): _put(minion, &"description", String(record.description).left(400), editing)
	if record.has("types"):
		var types: Variant = _string_names(record.types, context + " types", TypeDefinition, 1, 2)
		if types != null: _put(minion, &"type_ids", types, editing)
	if record.has("stats"):
		if not record.stats is Dictionary: return _fail("%s stats must be an object" % context)
		for stat in record.stats:
			if not STAT_FIELDS.has(stat): return _fail("%s has unknown stat %s" % [context, stat])
			_put(minion, StringName(STAT_FIELDS[stat]), _int(record.stats, stat, 1 if stat == "health" else 0, 999, 1), editing)
	if record.has("xp_rate"): _put(minion, &"experience_gain_rate", _int(record, "xp_rate", 0, 4, 1), editing)
	if record.has("gem_slots"): _put(minion, &"gem_slots", _int(record, "gem_slots", 0, 8, 0), editing)
	if record.has("locked_gem_slots"): _put(minion, &"locked_gem_slots", _int(record, "locked_gem_slots", 0, 8, 0), editing)
	if record.has("initial_moves"):
		var moves: Variant = _string_names(record.initial_moves, context + " initial_moves", MoveDefinition, 1, 8)
		if moves != null: _put(minion, &"initial_move_ids", moves, editing)
	if record.has("specialization_moves"):
		var specials: Variant = _string_names(record.specialization_moves, context + " specialization_moves", MoveDefinition, 0, 3)
		if specials != null and specials.size() not in [0, 3]: return _fail("%s needs zero or three specialization moves" % context)
		if specials != null: _put(minion, &"specialization_move_ids", specials, editing)
	if record.has("talent_trees"):
		var trees: Variant = _string_names(record.talent_trees, context + " talent_trees", TalentTreeDefinition, 0, 3)
		if trees != null: _put(minion, &"talent_tree_ids", trees, editing)
	if record.has("evolves_into"):
		var target := String(record.evolves_into)
		if not target.is_empty() and _lookup(target, MinionDefinition) == null and not _declared_minion(target):
			return _fail("%s evolves into unknown minion %s" % [context, target])
		_put(minion, &"evolution_id", StringName(target), editing)
		_put(minion, &"evolution_level", _int(record, "evolution_level", 2, 99, 30) if not target.is_empty() else 999, editing)
	if record.has("sprite"): _apply_sprite(minion, record.sprite, editing)

## Evolution may point at a minion declared later in the same mod.
func _declared_minion(id: String) -> bool:
	for entry in manifest.get("minions", []):
		if entry is Dictionary and String(entry.get("id", "")) == id: return true
	return false

func _apply_sprite(minion: MinionDefinition, sprite: Variant, editing: bool):
	if not sprite is Dictionary: return _fail("%s sprite must be an object" % minion.id)
	var source := _lookup(sprite.get("from", ""), MinionDefinition) as MinionDefinition
	var file := String(sprite.get("file", ""))
	if source == null and file.is_empty(): return _fail("%s sprite needs an existing minion to copy or an image file" % minion.id)
	if not file.is_empty() and (file.contains("..") or not file.begins_with("sprites/") or file.get_extension().to_lower() != "png"):
		return _fail("%s sprite file must be a PNG inside the mod's sprites folder" % minion.id)
	var source_presentation := _lookup(source.presentation_id if source != null else minion.presentation_id, MinionPresentationDefinition) as MinionPresentationDefinition
	var presentation := source_presentation.duplicate(true) as MinionPresentationDefinition if source_presentation != null else MinionPresentationDefinition.new()
	var virtual_name := "usermod_%s_%s" % [mod_id, String(minion.id).get_file()]
	presentation.id = StringName("%s:presentation/minion/%s" % [mod_id, String(minion.id).get_file()])
	presentation.display_name = minion.display_name
	presentation.source_mod = pack.source_mod
	presentation.legacy_sprite_name = StringName(virtual_name)
	for definition in pack.definitions:
		if definition.id == presentation.id:
			pack.definitions.erase(definition)
			break
	pack.definitions.append(presentation)
	sprite_requests[virtual_name] = {
		"from": String(source_presentation.legacy_sprite_name) if source_presentation != null and file.is_empty() else "",
		"file": file,
		"hue_shift": clampf(float(sprite.get("hue_shift", 0.0)), 0.0, 1.0),
		"saturation": clampf(float(sprite.get("saturation", 1.0)), 0.0, 2.0),
		"value": clampf(float(sprite.get("value", 1.0)), 0.0, 2.0),
	}
	_put(minion, &"presentation_id", presentation.id, editing)

static func minion_record(minion: MinionDefinition) -> Dictionary:
	return {
		"name": minion.display_name, "description": minion.description,
		"types": Array(minion.type_ids).map(func(value: StringName) -> String: return String(value)),
		"stats": {"health": minion.base_health, "energy": minion.base_energy, "attack": minion.base_attack, "healing": minion.base_healing, "speed": minion.base_speed},
		"xp_rate": minion.experience_gain_rate, "gem_slots": minion.gem_slots, "locked_gem_slots": minion.locked_gem_slots,
		"initial_moves": Array(minion.initial_move_ids).map(func(value: StringName) -> String: return String(value)),
		"specialization_moves": Array(minion.specialization_move_ids).map(func(value: StringName) -> String: return String(value)),
		"talent_trees": Array(minion.talent_tree_ids).map(func(value: StringName) -> String: return String(value)),
		"evolves_into": String(minion.evolution_id), "evolution_level": minion.evolution_level,
	}

# --- Trainers, hatcheries and rooms ----------------------------------------

func _edit_trainer(record: Variant):
	if not record is Dictionary: return _fail("trainer entries must be objects")
	var encounter := _lookup(record.get("target", ""), EncounterDefinition) as EncounterDefinition
	if encounter == null: return _fail("trainer target %s is not an encounter" % record.get("target", ""))
	if record.has("team"):
		if not record.team is Array or record.team.is_empty() or record.team.size() > 5:
			return _fail("%s team needs 1 to 5 minions" % encounter.id)
		var entries: Array[Dictionary] = []
		for index in record.team.size():
			var member: Variant = record.team[index]
			if not member is Dictionary or _lookup(member.get("minion", ""), MinionDefinition) == null:
				return _fail("%s team slot %d needs a known minion" % [encounter.id, index + 1])
			var moves: Variant = _string_names(member.get("moves", []), "%s slot %d moves" % [encounter.id, index + 1], MoveDefinition, 0, 8)
			if moves == null: return
			entries.append({"definition_id": StringName(String(member.minion)), "level": _int(member, "level", 1, 99, 5), "source_level_offset": 0, "slot_index": index, "move_ids": moves})
		_put(encounter, &"team_entries", entries, true)
	if record.has("money"):
		var rewards: Dictionary = encounter.rewards.duplicate(true)
		var first_clear: Dictionary = rewards.get("first_clear", {})
		first_clear["floor_money_basis"] = _int(record, "money", 0, 9999, 0)
		rewards["first_clear"] = first_clear
		_put(encounter, &"rewards", rewards, true)
	var lines: Dictionary = {}
	for key in ["trainer_name", "first_visit_text", "repeat_text", "after_win_text"]:
		if record.has(key) and not String(record[key]).strip_edges().is_empty():
			lines[key] = String(record[key]).left(400 if key != "trainer_name" else 24)
	if not lines.is_empty(): dialogue[String(encounter.id)] = lines

func _add_hatchery_rule(record: Variant):
	if not record is Dictionary: return _fail("hatchery entries must be objects")
	var floor_index := _int(record, "floor", 0, 60, 0)
	var mode := String(record.get("mode", "add"))
	if mode not in ["add", "replace"]: return _fail("hatchery mode must be add or replace")
	var entries: Variant = record.get("entries", [])
	if not entries is Array or entries.is_empty() or entries.size() > 9: return _fail("hatchery floor %d needs 1 to 9 entries" % (floor_index + 1))
	var candidates: Array = []
	var weights: Array = []
	for entry in entries:
		if not entry is Dictionary or (_lookup(entry.get("minion", ""), MinionDefinition) == null and not _declared_minion(String(entry.get("minion", "")))):
			return _fail("hatchery floor %d references an unknown minion" % (floor_index + 1))
		candidates.append(String(entry.minion))
		weights.append(_int(entry, "weight", 1, 100, 10))
	var total := 0
	for weight in weights: total += int(weight)
	if mode == "add" and total > 90: return _fail("hatchery floor %d additions may take at most 90%% of the eggs" % (floor_index + 1))
	if mode == "replace" and total != 100: return _fail("hatchery floor %d replacement weights must total 100" % (floor_index + 1))
	hatchery_rules.append({"floor": floor_index, "mode": mode, "candidates": candidates, "weights": weights})

func _add_room_edit(record: Variant):
	if not record is Dictionary: return _fail("room entries must be objects")
	var target := String(record.get("target", ""))
	if not target.begins_with("base:room/"): return _fail("room edit target %s must be a tower room" % target)
	for section in ["exits", "interactions", "spawns", "objects"]:
		for entry in record.get(section, []):
			if not entry is Dictionary: return _fail("room %s %s entries must be objects" % [target, section])
	room_edits.append(record.duplicate(true))

func _add_custom_floor(record: Dictionary) -> void:
	var id := _own_id(record, "floor")
	if id.is_empty(): return
	var rooms: Array = record.get("rooms", [])
	var start := String(record.get("start_room", ""))
	if rooms.is_empty() or rooms.size() > CustomFloorBuilder.MAX_ROOMS:
		_fail("%s needs 1 to %d rooms" % [id, CustomFloorBuilder.MAX_ROOMS])
		return
	var room_records: Dictionary = {}
	for room in rooms:
		if not room is Dictionary or not CustomFloorBuilder.valid_local_id(String(room.get("id", ""))) or room_records.has(room.id):
			_fail("%s has an invalid or duplicate room ID" % id)
			return
		room_records[room.id] = room
	if not room_records.has(start):
		_fail("%s needs a valid entrance room" % id)
		return
	var floor := CustomFloorDefinition.new()
	floor.id = id
	floor.display_name = String(record.get("name", id)).strip_edges().left(40)
	floor.description = String(record.get("description", "")).strip_edges().left(160)
	floor.source_mod = pack.source_mod
	floor.start_room_id = CustomFloorBuilder.room_id(id, start)
	pack.definitions.append(floor)
	var before := errors.size()
	for room in rooms:
		_add_custom_room(floor, room, room_records)
	if errors.size() != before: return
	# Every room needs a route back to an exit even if links are one-way.
	# Trainer locks are solvable in the room that owns the door.
	var reachable := CustomFloorBuilder.reachable_rooms(start, room_records)
	for local_id in room_records:
		if not reachable.has(local_id):
			_fail("%s: room %s cannot be reached from the entrance" % [id, local_id])
		if not CustomFloorBuilder.reachable_rooms(local_id, room_records).any(func(key: String) -> bool:
			return room_records[key].get("features", []).any(func(feature: Dictionary) -> bool: return feature.kind == "return")):
			_fail("%s: room %s has no route back to the Side Hall" % [id, local_id])

func _add_custom_room(floor: CustomFloorDefinition, record: Dictionary, rooms: Dictionary) -> void:
	var context := "%s / %s" % [floor.id, record.id]
	var dimensions := Vector2(float(record.get("width", 0)), float(record.get("height", 0)))
	var template := String(record.get("template", "stone"))
	if dimensions.x < 700 or dimensions.y < 525 or dimensions.x > 2400 or dimensions.y > 2400 or template not in CustomFloorBuilder.TEMPLATE_OPTIONS:
		_fail("%s needs a valid template and dimensions between 700×525 and 2400×2400" % context)
		return
	var walkable := Rect2(Vector2(68, 134), dimensions - Vector2(136, 189))
	if not walkable.has_point(CustomFloorBuilder.point(record, "entry_x", "entry_y")):
		_fail("%s entrance must be inside the room" % context)
		return
	var objects: Array = record.get("objects", [])
	var features: Array = record.get("features", [])
	if objects.size() > CustomFloorBuilder.MAX_OBJECTS or features.size() > CustomFloorBuilder.MAX_FEATURES:
		_fail("%s has too many objects or features" % context)
		return
	for object in objects:
		if not object is Dictionary:
			_fail("%s has an invalid object" % context)
			return
		var sprite := String(object.get("add", ""))
		var foreign_art := sprite.begins_with("mod_art:") and not sprite.begins_with("mod_art:%s/" % mod_id)
		var scale := Vector2(float(object.get("x_scale", 1)), float(object.get("y_scale", 1))).abs()
		var is_directional := RoomPuzzleTile.kind(sprite) in ["arrow", "jump"]
		if foreign_art or not object_addable(sprite) or scale.x < 0.05 or scale.y < 0.05 or scale.x > 30 or scale.y > 30 or not Rect2(Vector2(-200, -200), dimensions + Vector2(400, 400)).has_point(CustomFloorBuilder.point(object)) or (is_directional and not is_equal_approx(fposmod(float(object.get("rotation", 0)), 90.0), 0.0)):
			_fail("%s has invalid art, size, position or tile direction for %s" % [context, sprite])
			return
	var feature_ids: Dictionary = {}
	for feature in features:
		if not feature is Dictionary or not CustomFloorBuilder.valid_local_id(String(feature.get("id", ""))) or feature_ids.has(feature.id):
			_fail("%s has an invalid or duplicate feature ID" % context)
			return
		feature_ids[feature.id] = String(feature.get("kind", ""))
	var eggs := 0
	for feature in features:
		if not walkable.has_point(CustomFloorBuilder.point(feature)):
			_fail("%s: %s must be placed inside the room" % [context, feature.id])
			return
		var art := String(feature.get("art", ""))
		if not art.is_empty() and (feature.kind not in ["door", "return", "trainer"] or not _custom_art_available(art)):
			_fail("%s: %s has invalid artwork" % [context, feature.id])
			return
		if feature.get("mount", "auto") not in CustomFloorBuilder.DOOR_MOUNTS:
			_fail("%s: %s has an invalid door mount" % [context, feature.id])
			return
		match feature.get("kind"):
			"door":
				var requirement := String(feature.get("requires_trainer", ""))
				if not rooms.has(feature.get("destination", "")) or (not requirement.is_empty() and feature_ids.get(requirement) != "trainer"):
					_fail("%s: door %s needs a valid destination and a trainer from this room if locked" % [context, feature.id])
					return
			"egg":
				eggs += 1
				if eggs > 9 or _lookup(feature.get("minion", ""), MinionDefinition) == null:
					_fail("%s needs a known minion for each egg and can have at most nine eggs" % context)
					return
				_int(feature, "level", 1, 60, 5)
			"trainer":
				_add_custom_trainer(floor, record, feature)
			"return", "heal_party": pass
			_:
				_fail("%s: unknown feature %s" % [context, feature.get("kind", "")])
				return
	var room := CustomFloorBuilder.make_room(floor.id, record)
	if not CustomFloorBuilder.can_stand(room, CustomFloorBuilder.point(record, "entry_x", "entry_y")):
		_fail("%s: move the arrival point away from walls and gaps" % context)
		return
	room.source_mod = pack.source_mod
	floor.room_ids.append(room.id)
	pack.definitions.append(room)

func _custom_art_available(sprite: String) -> bool:
	if sprite.begins_with("mod_art:") and not sprite.begins_with("mod_art:%s/" % mod_id): return false
	return sprite != "collRect" and RoomPuzzleTile.kind(sprite).is_empty() and object_addable(sprite)

func _add_custom_trainer(floor: CustomFloorDefinition, room: Dictionary, feature: Dictionary) -> void:
	var encounter := EncounterDefinition.new()
	encounter.id = CustomFloorBuilder.encounter_id(floor.id, room.id, feature.id)
	encounter.display_name = String(feature.get("name", "Trainer")).strip_edges().left(24)
	encounter.source_mod = pack.source_mod
	encounter.ai_profile_id = &"base:ai/trainer/normal"
	encounter.rewards = {"first_clear": {"money": _int(feature, "money", 0, 9999, 0)}}
	var team: Array = feature.get("team", [])
	if team.is_empty() or team.size() > 5:
		_fail("%s needs a team of 1 to 5 minions" % encounter.id)
		return
	for index in team.size():
		var member: Variant = team[index]
		if not member is Dictionary or _lookup(member.get("minion", ""), MinionDefinition) == null:
			_fail("%s needs a known minion in team slot %d" % [encounter.id, index + 1])
			return
		var moves: Variant = _string_names(member.get("moves", []), "%s slot %d moves" % [encounter.id, index + 1], MoveDefinition, 0, 8)
		if moves == null: return
		var entry := {"definition_id": StringName(member.minion), "level": _int(member, "level", 1, 60, 5), "slot_index": index}
		if not moves.is_empty(): entry["move_ids"] = moves
		encounter.team_entries.append(entry)
	pack.definitions.append(encounter)

## Room objects a mod may move, resize or remove: art, walls and the
## invisible interaction zones. Doors, entries and other markers stay fixed
## because exits, spawns and transitions were bound to them when the room was
## built. Added objects must be art or walls.
static func object_editable(sprite_name: String) -> bool:
	if sprite_name == "collRect" or sprite_name.begins_with("buttonZoneObject"): return true
	return object_addable(sprite_name) or sprite_name.begins_with("eggery_egg") or sprite_name in ["room_goldChest", "room_gemChest", "generalRoom_healStone"]

static func object_addable(sprite_name: String) -> bool:
	if sprite_name == "collRect": return true
	if sprite_name.is_empty() or RoomArtCatalog.is_marker(sprite_name): return false
	# Eggs, chests and heal stones carry game state bound to their source slots.
	if sprite_name.begins_with("eggery_egg") or sprite_name in ["room_goldChest", "room_gemChest", "generalRoom_healStone"]: return false
	return RoomArtCatalog.texture(sprite_name) != null

## The payload objects with a room record's `objects` edits applied. Indices
## never shift: removed objects keep their slot with an empty sprite name, so
## chest and egg slot IDs (which are payload indices) stay stable. Problems
## are appended to `problems` and the offending edit is skipped.
static func edited_objects(objects: Array, edits: Array, dimensions: Vector2, problems: PackedStringArray = PackedStringArray(), context: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for attributes in objects: result.append((attributes as Dictionary).duplicate(true))
	var bounds := Rect2(-200.0, -200.0, dimensions.x + 400.0, dimensions.y + 400.0) if dimensions != Vector2.ZERO else Rect2(-1e6, -1e6, 2e6, 2e6)
	for edit in edits:
		if not edit is Dictionary: continue
		var target: Dictionary
		if edit.has("add"):
			var sprite_name := String(edit.add)
			if not object_addable(sprite_name):
				problems.append("%s: %s cannot be placed in a room" % [context, sprite_name])
				continue
			target = {"spriteName": sprite_name, "xPos": 0.0, "yPos": 0.0, "xScale": 1.0, "yScale": 1.0, "rotation": 0.0}
			result.append(target)
		else:
			var index := int(edit.get("index", -1))
			if index < 0 or index >= objects.size():
				problems.append("%s: object %d does not exist" % [context, index])
				continue
			target = result[index]
			if not object_editable(String(objects[index].get("spriteName", "")).strip_edges()):
				problems.append("%s: object %d (%s) cannot be edited" % [context, index, objects[index].get("spriteName", "")])
				continue
			if bool(edit.get("remove", false)):
				target["spriteName"] = ""
				continue
		for pair in [["x", "xPos"], ["y", "yPos"], ["x_scale", "xScale"], ["y_scale", "yScale"], ["rotation", "rotation"]]:
			if edit.has(pair[0]): target[pair[1]] = float(edit[pair[0]])
		for pair in [["x_scale", "xScale"], ["y_scale", "yScale"]]:
			if absf(float(target.get(pair[1], 1.0))) < 0.05 or absf(float(target.get(pair[1], 1.0))) > 40.0:
				problems.append("%s: object scale must be between 0.05 and 40" % context)
				target[pair[1]] = clampf(float(target.get(pair[1], 1.0)), 0.05, 40.0)
		if not bounds.has_point(Vector2(float(target.xPos), float(target.yPos))):
			problems.append("%s: an object was placed outside the room" % context)
			target["xPos"] = clampf(float(target.xPos), bounds.position.x, bounds.end.x)
			target["yPos"] = clampf(float(target.yPos), bounds.position.y, bounds.end.y)
	return result

## Applied to freshly built rooms after every catalog index rebuild.
func apply_room_edits(rooms: Dictionary, problems: PackedStringArray) -> void:
	for record in room_edits:
		var room := rooms.get(StringName(String(record.target))) as RoomDefinition
		if room == null:
			problems.append("%s: room %s does not exist" % [mod_id, record.target])
			continue
		if not record.get("objects", []).is_empty() and room.payload != null:
			# Some payloads are shared, preloaded resources: never edit them in place.
			var payload := room.payload.duplicate() as RoomPayloadDefinition
			var edited := edited_objects(room.payload.objects, record.objects, room.payload.dimensions, problems, "%s: room %s" % [mod_id, room.id])
			payload.objects = edited
			room.payload = payload
			# Healing stones are bound to their zones when the room is built;
			# rebind them, and drop the healing if every stone was removed.
			if not edited.any(func(attributes: Dictionary) -> bool: return String(attributes.get("spriteName", "")) == "generalRoom_healStone"):
				for index in range(room.interactions.size() - 1, -1, -1):
					if StringName(room.interactions[index].get("kind", "")) == &"heal_party": room.interactions.remove_at(index)
			SourceRoomGraphBuilder._bind_source_heal_zones(room, payload)
		for exit_edit in record.get("exits", []):
			var matched := false
			for exit_data in room.exits:
				if int(exit_data.get("transition_id", -1)) == int(exit_edit.get("transition_id", -2)):
					exit_data["target_room_id"] = StringName(String(exit_edit.get("target_room_id", exit_data.target_room_id)))
					exit_data["target_spawn_id"] = StringName(String(exit_edit.get("target_spawn_id", exit_data.get("target_spawn_id", ""))))
					matched = true
			if not matched: problems.append("%s: room %s has no exit %s" % [mod_id, room.id, exit_edit.get("transition_id", "?")])
		var dimensions: Vector2 = room.minimap_metadata.get("source_dimensions", Vector2.ZERO)
		for spawn_edit in record.get("spawns", []):
			var spawn_id := String(spawn_edit.get("id", ""))
			var spawn_point := Vector2(float(spawn_edit.get("x", -1.0)), float(spawn_edit.get("y", -1.0)))
			if not room.spawn_positions.has(spawn_id):
				problems.append("%s: room %s has no arrival point %s" % [mod_id, room.id, spawn_id])
			elif dimensions != Vector2.ZERO and (spawn_point.x < 0.0 or spawn_point.y < 0.0 or spawn_point.x > dimensions.x or spawn_point.y > dimensions.y):
				problems.append("%s: arrival point %s of %s is outside the room" % [mod_id, spawn_id, room.id])
			else:
				room.spawn_positions[spawn_id] = spawn_point
		for interaction_edit in record.get("interactions", []):
			var interaction_id := StringName(String(interaction_edit.get("id", "")))
			var found := false
			for interaction in room.interactions:
				if StringName(interaction.get("id", "")) != interaction_id: continue
				found = true
				var allowed: Array = ROOM_INTERACTION_FIELDS.get(String(interaction.get("kind", "")), [])
				if String(interaction.get("kind", "")) == "trainer" and interaction_edit.has("encounter_id"):
					var encounter_id := StringName(String(interaction_edit.encounter_id))
					if not encounter_id in room.encounter_ids: room.encounter_ids.append(encounter_id)
					interaction["encounter_id"] = encounter_id
				for key in interaction_edit.get("set", {}):
					if key in allowed: interaction[key] = interaction_edit["set"][key]
					else: problems.append("%s: %s.%s cannot be edited" % [mod_id, interaction_id, key])
				if String(interaction.get("kind", "")) == "egg_pick":
					var candidates: Variant = interaction.get("candidates", [])
					var weights: Variant = interaction.get("weights", [])
					if not candidates is Array or not weights is Array or candidates.is_empty() or candidates.size() != weights.size():
						problems.append("%s: egg %s needs equally sized minion and weight lists" % [mod_id, interaction_id])
					else:
						var total := 0
						for index in candidates.size():
							if not candidates[index] is String or not rooms.get(StringName(str(candidates[index]))) is MinionDefinition:
								problems.append("%s: egg %s references an unknown minion" % [mod_id, interaction_id])
							if not (weights[index] is int or weights[index] is float) or int(weights[index]) < 0 or int(weights[index]) > 100:
								problems.append("%s: egg %s weights must be 0-100" % [mod_id, interaction_id])
							else: total += int(weights[index])
						if total != 100: problems.append("%s: egg %s weights must total 100" % [mod_id, interaction_id])
			if not found: problems.append("%s: room %s has no interaction %s" % [mod_id, room.id, interaction_id])
