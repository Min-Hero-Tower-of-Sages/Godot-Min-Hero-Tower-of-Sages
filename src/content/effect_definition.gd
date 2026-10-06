class_name EffectDefinition
extends ContentDefinition

enum Kind {
	DAMAGE, HEAL, ENERGY, STAT_STAGE, APPLY_STATUS, REMOVE_STATUS, SHIELD, REFLECT, REVIVE, COOLDOWN,
	PERIODIC_DAMAGE, PERIODIC_HEAL, ARMOR, SELF_DAMAGE, HEALTH_PERCENT_DAMAGE, STUN, FREEZE,
	CLEAR_BUFFS_DEBUFFS, STAT_PERCENT, REDIRECT_DAMAGE, CRITICAL_CHANCE
}
enum TargetScope { ACTOR, ENEMY_TARGETS, ALLY_TARGETS, BOTH_TARGET_GROUPS, ALLIED_TEAM }
enum Phase { BEFORE_ACCURACY, ENEMY_TARGET, ALLY_TARGET, ACTOR_AFTER_TARGETS, PASSIVE }
enum Scaling { NONE, ATTACK, HEALING, ENERGY_STAT_PERCENT, HEALTH_STAT_PERCENT }
enum RollScope { NONE, SHARED_MOVE, PER_TARGET, PER_EFFECT_TARGET, PERIODIC_TICK }
enum ImplementationStatus { IMPLEMENTED, RUNTIME_PENDING }

@export_group("Effect")
@export var kind: Kind = Kind.DAMAGE
@export var target_scope: TargetScope = TargetScope.ENEMY_TARGETS
@export var phase: Phase = Phase.ENEMY_TARGET
@export var scaling: Scaling = Scaling.NONE
@export var roll_scope: RollScope = RollScope.NONE
@export var amount: int = 0
@export var random_bonus: int = 0
@export_range(0, 100) var chance_percent: int = 100
@export var stat_type_id: StringName
@export var status_id: StringName
@export var duration: int = 0
@export var uses_type_effectiveness: bool = false
@export var can_critical: bool = false
@export var blocked_by_battle_mod_shield: bool = false
@export var legacy_order: int = 0
@export var implementation_status: ImplementationStatus = ImplementationStatus.IMPLEMENTED
@export var executor: Script

func validation_errors() -> PackedStringArray:
	var errors := super()
	if random_bonus < 0:
		errors.append("%s has a negative random bonus" % id)
	if implementation_status == ImplementationStatus.RUNTIME_PENDING:
		errors.append("%s has pending runtime implementation" % id)
	elif executor == null and not kind in [Kind.ARMOR, Kind.REFLECT, Kind.STAT_PERCENT, Kind.REDIRECT_DAMAGE, Kind.CRITICAL_CHANCE]:
		errors.append("%s has no executor script" % id)
	return errors
