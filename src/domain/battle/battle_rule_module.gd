class_name BattleRuleModule
extends Resource

## Override this hook to apply a deterministic opening rule before turn order is built.
## Modules are invoked in RuleSetDefinition.rule_modules order.
func on_battle_started(_context: BattleRuleContext) -> void:
	pass
