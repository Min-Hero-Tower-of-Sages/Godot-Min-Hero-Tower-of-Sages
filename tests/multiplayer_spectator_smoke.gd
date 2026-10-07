extends SceneTree

## Drives the real battle scene (main.tscn) in its multiplayer roles:
## - spectator: replays a recorded arena battle from the command stream,
##   including commands that arrived before the scene subscribed;
## - arena fighter on team 1: views are mirrored so "my" team is on the left.

const Sync = preload("res://src/application/multiplayer_world_sync.gd")
const MAIN_SCENE := preload("res://scenes/main.tscn")

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func _make_team(runtime: Node, prefix: String) -> Array:
	var state := CampaignState.new()
	for index in 2:
		var owned := OwnedMinionState.new()
		owned.instance_id = StringName("%s-%d" % [prefix, index])
		owned.definition_id = [&"base:minion/fire_pig_1", &"base:minion/tiger_1"][index]
		owned.level = 8
		var definition := runtime.catalog.get_definition(owned.definition_id) as MinionDefinition
		owned.learned_move_ids.assign(definition.initial_move_ids)
		state.party.append(owned)
	return CampaignProgressionService.party_setup_combatants(state, runtime.catalog).combatants

## Plays the spec on a bare engine and records the stream fighters would send.
func _record(runtime: Node, spec: Dictionary) -> Dictionary:
	var rules := RuleSetDefinition.new()
	rules.configuration = (spec.rules.configuration as Dictionary).duplicate(true)
	var controller := BattleController.new()
	controller.start((spec.setup as Dictionary).duplicate(true), runtime.catalog, rules, BattleRng.new(int(spec.seed)))
	var commands: Array[Dictionary] = []
	var step := 0
	while controller.engine.get_result().is_empty() and step < 300:
		step += 1
		var decision: Dictionary = controller.engine.get_decision()
		var choice: Dictionary = decision.legal_moves[step % decision.legal_moves.size()]
		var move := runtime.catalog.get_definition(StringName(choice.move_id)) as MoveDefinition
		var targets: Array[StringName] = []
		var count := mini(move.target_count, choice.target_ids.size()) if move.target_mode == MoveDefinition.TargetMode.CHOSEN else 0
		for index in count: targets.append(StringName(choice.target_ids[index]))
		var pre := controller.engine.snapshot()
		var command := BattleCommand.new(StringName(decision.actor_id), BattleCommand.Kind.USE_MOVE, StringName(choice.move_id), targets, int(decision.revision))
		controller.submit(command)
		var target_strings: Array = []
		for target in targets: target_strings.append(String(target))
		commands.append({"revision": int(decision.revision), "actor": String(command.actor_id), "kind": "move", "move": String(command.move_id), "targets": target_strings, "check": Sync.fingerprint(pre), "sender": 2})
	return {"commands": commands, "winner": controller.engine.get_result().winning_team}

func _run() -> void:
	await process_frame
	var runtime := root.get_node("CampaignRuntime")
	var net := root.get_node("NetSession")
	net.mode = net.Mode.HOST # Session logic without sockets; this process is peer 1.
	net.players = {1: {"name": "Watcher"}, 2: {"name": "Ana"}, 3: {"name": "Bo"}}
	var spec: Dictionary = net.build_pvp_spec("battle-spectate", 2, _make_team(runtime, "ana"), 3, _make_team(runtime, "bo"), 99)
	spec = bytes_to_var(var_to_bytes(spec))
	var recording := _record(runtime, spec)
	_expect(not recording.commands.is_empty(), "the reference arena battle records commands")
	# Spectator: half the stream is already buffered before the scene exists.
	net._begin_snapshot_history(String(spec.key))
	var early: int = recording.commands.size() / 2
	for index in early:
		net._command_log.append(recording.commands[index])
	Engine.time_scale = 12.0
	var battle: Node = MAIN_SCENE.instantiate()
	root.add_child(battle)
	var finished: Array = []
	battle.network_battle_finished.connect(func() -> void: finished.append(true))
	battle.begin_network_battle(spec)
	await create_timer(1.0).timeout
	_expect(battle.net_role == &"spectator", "a non-fighter watches the battle")
	_expect(not battle.forfeit_button.visible, "spectators cannot forfeit someone else's battle")
	for index in range(early, recording.commands.size()):
		net.battle_command_received.emit(String(spec.key), recording.commands[index])
	var deadline := Time.get_ticks_msec() + 240000
	while finished.is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
	_expect(not finished.is_empty(), "the spectated battle finishes and hands back to the room")
	var expected_winner: String = "Ana" if int(recording.winner) == 0 else "Bo"
	_expect(String(battle.result_title.text).begins_with("%s wins!" % expected_winner), "the spectator sees the real winner (%s), got: %s" % [expected_winner, battle.result_title.text])
	battle.queue_free()
	await process_frame
	# Arena fighter controlling team 1 sees their own minions on the left.
	net.players[3] = {"name": "Bo"}
	var mirrored_spec: Dictionary = spec.duplicate(true)
	mirrored_spec["key"] = "battle-mirror"
	mirrored_spec["controllers"] = {0: 2, 1: 1}
	var fighter: Node = MAIN_SCENE.instantiate()
	root.add_child(fighter)
	fighter.begin_network_battle(mirrored_spec)
	await create_timer(0.5).timeout
	_expect(fighter.net_role == &"pvp" and fighter._local_teams == [1], "the challenged player fights as team 1")
	var own_left := true
	var rival_right := true
	for view in fighter.combatant_views.values():
		var engine_team := int(fighter._combatant_state(view.instance_id).get("team", -1))
		if engine_team == 1: own_left = own_left and view.team == 0
		if engine_team == 0: rival_right = rival_right and view.team == 1
	_expect(not fighter.combatant_views.is_empty() and own_left and rival_right, "team-1 fighters see their team on the player side")
	fighter.queue_free()
	Engine.time_scale = 1.0
	net.mode = net.Mode.OFFLINE
	net.players.clear()
	await process_frame
	if failures.is_empty():
		print("PASS: %d multiplayer spectator checks" % checks)
		quit(0)
		return
	for failure in failures: push_error(failure)
	print("FAIL: %d of %d multiplayer spectator checks" % [failures.size(), checks])
	quit(1)
