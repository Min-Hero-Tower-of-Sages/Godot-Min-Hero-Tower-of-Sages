class_name MoveDefinition
extends ContentDefinition

enum TargetSide { ENEMY, ALLY, SELF }
enum TargetMode { CHOSEN, ALL, RANDOM }

@export_group("Family")
@export var family_id: StringName
@export_range(1, 5) var tier: int = 1
@export var type_id: StringName = &"base:type/none"
@export var legacy_class_id: int = -1
@export var legacy_visual_id: int = -1
@export var legacy_dot_visual_id: int = -1
@export var buff_icon_name: StringName
@export var available: bool = true ## False only for source-declared IDs that are never constructed.
@export var is_passive: bool = false
@export var is_global_passive: bool = false

@export_group("Cost and timing")
@export_range(0, 99) var energy_cost: int = 1
@export_range(0, 99) var cooldown_turns: int = 0
@export_range(0, 99) var charge_turns: int = 0
@export_range(0, 99) var exhaust_turns: int = 0
@export_range(0, 100) var accuracy_percent: int = 100

@export_group("Targeting")
@export var target_side: TargetSide = TargetSide.ENEMY
@export var target_mode: TargetMode = TargetMode.CHOSEN
@export_range(1, 5) var target_count: int = 1
@export var hit_each_target: bool = true
@export var visuals_have_buffer: bool = true ## Source queues target visuals sequentially when true.
@export_range(0, 5) var enemy_target_count: int = 1
@export_range(0, 5) var ally_target_count: int = 0
@export var random_targets: bool = false
@export var only_self: bool = false

@export_group("Ordered resolution")
@export var effects: Array[EffectDefinition] = []
@export var presentation_id: StringName

func validation_errors() -> PackedStringArray:
	var errors := super()
	if family_id.is_empty(): errors.append("%s has no family id" % id)
	if available and effects.is_empty(): errors.append("%s has no effects" % id)
	for effect in effects:
		if effect == null:
			errors.append("%s contains a null effect" % id)
		else:
			for error in effect.validation_errors(): errors.append(error)
	return errors
