extends BattleRuleModule

@export var marker: StringName = &""
@export var invocation_count := 0

func on_battle_started(context: BattleRuleContext) -> void:
	invocation_count += 1
	var trace: Array = context.state.modifier_state.get("rule_module_trace", [])
	trace.append(String(marker))
	context.state.modifier_state["rule_module_trace"] = trace
