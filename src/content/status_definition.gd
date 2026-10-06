class_name StatusDefinition
extends ContentDefinition

enum StackPolicy { REJECT, REFRESH, STACK_DURATION, STACK_INTENSITY }

@export var default_duration: int = 1
@export var stack_policy: StackPolicy = StackPolicy.REFRESH
@export_range(1, 99) var maximum_stacks: int = 1
@export var periodic_effects: Array[EffectDefinition] = []
@export var remove_on_defeat: bool = true
@export var priority: int = 0
