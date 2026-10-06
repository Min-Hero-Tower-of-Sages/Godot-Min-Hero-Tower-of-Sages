class_name LegacyCombatMath
extends RefCounted

const STAB_MODIFIER := 1.1

static func calculate_scaled_amount(base_amount: float, random_bonus: float, stat: float, level: float, random_unit: float) -> int:
	var rolled_power := base_amount + random_bonus * clampf(random_unit, 0.0, 0.999999)
	var level_factor := level * 3.0 / 5.0 + 2.0
	return ceili(level_factor * rolled_power * stat / 3000.0)

static func apply_stab(amount: float, move_type: StringName, actor_types: Array[StringName]) -> float:
	return amount * STAB_MODIFIER if move_type in actor_types else amount

static func apply_multipliers(amount: float, multipliers: Array[float]) -> float:
	var result := amount
	for multiplier in multipliers:
		result *= multiplier
	return result
