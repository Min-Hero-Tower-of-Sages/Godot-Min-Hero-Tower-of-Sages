class_name EffectExecutor
extends RefCounted

func execute(_effect: EffectDefinition, _context: Dictionary) -> void:
	push_error("EffectExecutor.execute must be overridden")
