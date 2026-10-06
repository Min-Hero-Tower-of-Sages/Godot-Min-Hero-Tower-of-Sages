extends SceneTree

const RecoveredCatalog: ContentCatalog = preload("res://content/imported/recovered-20260911/catalog.tres")
const ExtensionPack: ContentPackDefinition = preload("res://tests/fixtures/content_extension_pack.tres")

var failures: Array[String] = []

func _initialize() -> void:
	var catalog := RecoveredCatalog.duplicate(true) as ContentCatalog
	catalog.packs.append(ExtensionPack)
	var validation_errors := catalog.rebuild_index()
	_expect(validation_errors.is_empty(), "test extension pack should register with recovered content: %s" % " | ".join(validation_errors))
	var minion := catalog.get_definition(&"tests:minion/extension_probe") as MinionDefinition
	var combo := catalog.get_definition(&"tests:move/combo") as MoveDefinition
	var custom_move := catalog.get_definition(&"tests:move/custom_energy") as MoveDefinition
	_expect(minion != null and minion.presentation_id == &"base:presentation/minion/normalslime1", "fixture minion should reuse an existing production presentation")
	_expect(combo != null and combo.effects.size() == 2, "fixture combo should compose existing damage and energy executors")
	_expect(custom_move != null and custom_move.effects.size() == 1 and custom_move.effects[0].executor == load("res://tests/fixtures/content_extension_energy_executor.gd"), "custom effect script should be supplied through the pack resource")
	if minion == null or combo == null or custom_move == null:
		_finish()
		return
	var engine := BattleEngine.new()
	var rules := RuleSetDefinition.new()
	rules.id = &"tests:rules/extension_probe"
	rules.display_name = "Test extension rules"
	rules.party_size = 2
	var setup := {
		"battle_id": "tests-extension-contract",
		"tie_first_team": 0,
		"combatants": [
			{"instance_id": "tests-player", "definition_id": "tests:minion/extension_probe", "team": 0, "slot_index": 0, "move_ids": ["tests:move/combo", "tests:move/custom_energy"], "max_health": 40, "max_energy": 10, "health": 40, "energy": 5, "attack": 0, "healing": 0, "speed": 20},
			{"instance_id": "tests-enemy", "definition_id": "tests:minion/extension_probe", "team": 1, "slot_index": 0, "move_ids": ["tests:move/combo", "tests:move/custom_energy"], "max_health": 40, "max_energy": 10, "health": 40, "energy": 5, "attack": 0, "healing": 0, "speed": 1},
		],
	}
	var started := engine.start(setup, catalog, rules, BattleRng.new(41, [0, 0, 0, 0, 0, 0, 0, 0]))
	_expect(started.accepted, "BattleEngine should start with the extension minion and its pack moves")
	if not started.accepted:
		_finish()
		return
	var decision := engine.get_decision()
	var combo_result := engine.submit(BattleCommand.new(&"tests-player", BattleCommand.Kind.USE_MOVE, &"tests:move/combo", [&"tests-enemy"], int(decision.revision)))
	_expect(combo_result.accepted, "BattleEngine should accept the pack's existing-executor combo")
	var enemy_state := _combatant_snapshot(engine, &"tests-enemy")
	var player_state := _combatant_snapshot(engine, &"tests-player")
	_expect(int(enemy_state.get("health", -1)) == 35, "composed existing damage executor should apply four damage with the fixture type's matching STAB modifier")
	_expect(int(player_state.get("energy", -1)) == 6, "composed existing energy executor should restore two energy after move cost")
	var enemy_decision := engine.get_decision()
	_expect(StringName(enemy_decision.get("actor_id", "")) == &"tests-enemy", "the deterministic faster player should act before the enemy")
	if StringName(enemy_decision.get("actor_id", "")) == &"tests-enemy":
		var enemy_result := engine.submit(BattleCommand.new(&"tests-enemy", BattleCommand.Kind.USE_MOVE, &"tests:move/combo", [&"tests-player"], int(enemy_decision.revision)))
		_expect(enemy_result.accepted, "the fixture enemy should complete its deterministic response so the player's next turn is reachable")
	var custom_decision := engine.get_decision()
	_expect(StringName(custom_decision.get("actor_id", "")) == &"tests-player", "completed round should return the next decision to the fixture player")
	if StringName(custom_decision.get("actor_id", "")) == &"tests-player":
		var custom_result := engine.submit(BattleCommand.new(&"tests-player", BattleCommand.Kind.USE_MOVE, &"tests:move/custom_energy", [&"tests-player"], int(custom_decision.revision)))
		_expect(custom_result.accepted, "BattleEngine should execute a pack-supplied custom effect during a real move command")
		var after_custom := _combatant_snapshot(engine, &"tests-player")
		_expect(int(after_custom.get("energy", -1)) == 8, "pack-supplied custom executor should apply its declared +3 energy after the move's cost")
		_expect(_has_fixture_energy_event(custom_result.events), "custom executor should emit its observable energy event through the engine context")
	_finish()

func _combatant_snapshot(engine: BattleEngine, instance_id: StringName) -> Dictionary:
	var snapshot := engine.snapshot()
	var state := snapshot.get("state", {}) as Dictionary
	for combatant in state.get("combatants", []) as Array:
		var entry := combatant as Dictionary
		if StringName(entry.get("instance_id", "")) == instance_id: return entry
	return {}

func _has_fixture_energy_event(events: Array[BattleEvent]) -> bool:
	for event in events:
		if event.kind == &"energy_changed" and event.values.get("fixture_executor", "") == "tests:effect/custom_energy":
			return true
	return false

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _finish() -> void:
	if failures.is_empty():
		print("PASS: content extension contract")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("FAIL: %d content extension checks" % failures.size())
		quit(1)
