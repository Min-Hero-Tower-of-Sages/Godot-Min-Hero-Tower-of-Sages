class_name TypeChartDefinition
extends ContentDefinition

@export var default_multiplier: float = 1.0
@export var not_effective_multiplier: float = 0.66666666667
@export var super_effective_multiplier: float = 1.5
@export var multipliers: Dictionary = {}

func multiplier(attacking_type: StringName, defending_type: StringName) -> float:
	if defending_type == &"base:type/none": return 1.0
	return float(multipliers.get("%s>%s" % [attacking_type, defending_type], default_multiplier))

func healing_multiplier(attacking_type: StringName, defending_type: StringName) -> float:
	var value := multiplier(attacking_type, defending_type)
	if is_equal_approx(value, not_effective_multiplier): return super_effective_multiplier
	if is_equal_approx(value, super_effective_multiplier): return not_effective_multiplier
	return value

func combined_multiplier(attacking_type: StringName, defending_types: Array[StringName], healing: bool = false) -> float:
	var result := 1.0
	for defending_type in defending_types:
		result *= healing_multiplier(attacking_type, defending_type) if healing else multiplier(attacking_type, defending_type)
	return result
