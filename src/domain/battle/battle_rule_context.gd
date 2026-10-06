class_name BattleRuleContext
extends RefCounted

## Typed data exposed to ruleset modules at the battle-start lifecycle seam.
## The state reference is mutable so modules can apply deterministic opening rules.
var state: BattleState
var content: ContentCatalog
var configuration: Dictionary

func _init(p_state: BattleState, p_content: ContentCatalog, p_configuration: Dictionary) -> void:
	state = p_state
	content = p_content
	configuration = p_configuration.duplicate(true)
