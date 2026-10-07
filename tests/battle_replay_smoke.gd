extends SceneTree

## Battle replays: recordings of campaign trainer battles (many encounters,
## including modifier fights) survive a share-code round trip and re-simulate
## to the same winner without drift; damaged codes are refused; the history
## keeps the newest battles, never prunes kept ones and ignores a code pasted
## twice; and a replay plays to its end card in the real battle scene at x4.
##   godot --headless --path . --script res://tests/battle_replay_smoke.gd

class MemorySaveRepository extends SaveRepository:
	var saved: Dictionary = {}
	func save_slot(slot: int, payload: Dictionary) -> Dictionary:
		saved[slot] = payload.duplicate(true)
		return {"ok": true}
	func load_slot(slot: int) -> Dictionary:
		return {"ok": true, "state": saved[slot].duplicate(true)} if saved.has(slot) else {"ok": false, "code": "not_found"}

const HISTORY_DIR := "user://battle_replay_smoke"

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func _run() -> void:
	await process_frame
	var runtime := root.get_node("CampaignRuntime")
	runtime.session.save_repository = MemorySaveRepository.new()
	runtime.start_new_campaign(1, "Vala", &"female")
	runtime.load_campaign(1)
	var state = runtime.session.state
	while state.party.size() < 5:
		var extra: OwnedMinionState = OwnedMinionState.from_dictionary(state.party[state.party.size() % 2].to_dictionary())
		extra.instance_id = StringName("replay-extra-%d" % state.party.size())
		state.party.append(extra)
	var replays := _test_campaign_recordings(runtime)
	_test_codes(replays)
	_test_history(replays)
	if not replays.is_empty():
		await _test_scene_playback(runtime, replays[0])
	_clean_history_dir()
	if failures.is_empty():
		print("battle_replay_smoke: %d checks passed" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("battle_replay_smoke: %d of %d checks failed" % [failures.size(), checks])
		quit(1)

## The campaign rules main.gd builds for a trainer encounter.
func _campaign_rules(encounter: EncounterDefinition) -> Dictionary:
	var configuration := {
		"ai_teams": [1],
		"refill_on_activation": true,
		"ai_difficulty": {"trainer_type": String(encounter.source_trainer_type), "floor_rate": 0.5, "floor_index": encounter.source_floor_index},
	}
	if not encounter.battle_modifier_configuration.is_empty():
		configuration["battle_modifiers"] = encounter.battle_modifier_configuration.duplicate(true)
	return bytes_to_var(var_to_bytes({"id": "base:rules/playable_battle", "display_name": "Campaign trainer battle", "party_size": 5, "configuration": configuration}))

## Fight encounters with a varied human policy, record them, and check each
## recording replays to the same result without any fingerprint drift.
func _test_campaign_recordings(runtime: Node) -> Array[Dictionary]:
	var catalog: ContentCatalog = runtime.catalog
	BattleReplay.ensure_packs(catalog)
	var encounters: Array[EncounterDefinition] = []
	var with_modifiers := 0
	for pack in catalog.packs:
		for definition in pack.definitions:
			if definition is EncounterDefinition and not definition.team_entries.is_empty():
				encounters.append(definition)
	encounters.sort_custom(func(a: EncounterDefinition, b: EncounterDefinition) -> bool: return String(a.id) < String(b.id))
	var replays: Array[Dictionary] = []
	var human_turns := 0
	var stride := maxi(1, encounters.size() / 24)
	for index in range(0, encounters.size(), stride):
		var encounter := encounters[index]
		var top_level := 1
		for entry in encounter.team_entries:
			top_level = maxi(top_level, int(entry.get("level", 1)))
		# Floors scale trainers differently: try a few party levels and keep
		# the closest fight, so recordings hold many human turns.
		var best: Dictionary = {}
		for offset in [-2, 0, 3, 7, 12]:
			var fought := _record_battle(runtime, encounter, maxi(1, top_level + offset), 20260911 + index)
			if not fought.is_empty() and (best.is_empty() or (fought.commands as Array).size() > (best.commands as Array).size()):
				best = fought
		_expect(not best.is_empty(), "%s can be fought and finishes within 600 turns" % encounter.id)
		if best.is_empty():
			continue
		if not encounter.battle_modifier_configuration.is_empty():
			with_modifiers += 1
		human_turns += (best.commands as Array).size()
		var simulated := BattleReplay.simulate(best, catalog)
		_expect(simulated.ok, "%s replays: %s" % [encounter.id, simulated.message])
		_expect(int(simulated.drift) == -1, "%s replays without drift (first drift at command %d)" % [encounter.id, simulated.drift])
		_expect(simulated.result != null and simulated.result.winning_team == int(best.result.winner) and simulated.result.rounds == int(best.result.rounds), "%s replays to the same winner and round" % encounter.id)
		_expect(int(simulated.played) == (best.commands as Array).size(), "%s replays every recorded command" % encounter.id)
		replays.append(best)
	print("recorded %d battles, %d human turns" % [replays.size(), human_turns])
	_expect(human_turns >= replays.size() * 4, "the recordings hold many human turns (%d)" % human_turns)
	_expect(replays.size() >= 10, "recorded at least ten campaign battles (%d)" % replays.size())
	_expect(with_modifiers >= 1, "at least one recorded battle uses battle modifiers (%d)" % with_modifiers)
	return replays

## One trainer battle with the party at `level`, recorded; {} if it could not run.
func _record_battle(runtime: Node, encounter: EncounterDefinition, level: int, seed: int) -> Dictionary:
	var catalog: ContentCatalog = runtime.catalog
	for owned in runtime.session.state.party:
		owned.level = level
		owned.persistent_health = -1
		owned.persistent_energy = -1
	# The setup a trainer battle gets, without walking to the trainer's room.
	runtime.session.state.pending_battle = {"battle_id": "replay-test-%d" % seed, "encounter_id": String(encounter.id)}
	var prepared: Dictionary = CampaignProgressionService.build_battle_setup(runtime.session.state, catalog, encounter)
	runtime.session.state.pending_battle = {}
	if not prepared.get("ok", false):
		return {}
	prepared.erase("ok")
	var setup: Dictionary = bytes_to_var(var_to_bytes(prepared))
	var rule_data := _campaign_rules(encounter)
	var replay := BattleReplay.create("trainer", seed, setup, rule_data, {0: "Vala", 1: "Trainer %d" % seed}, 0, {"content": String(catalog.content_version), "encounter_id": String(encounter.id), "floor": 0})
	var controller := BattleController.new()
	if not controller.start(setup.duplicate(true), catalog, BattleReplay.make_rules(rule_data), BattleRng.new(seed)).accepted:
		return {}
	var turns := 0
	while controller.engine.get_result().is_empty() and turns < 600:
		var decision := controller.engine.get_decision()
		if decision.is_empty():
			break
		turns += 1
		if int(decision.team) == 1:
			controller.submit_ai_turn()
			continue
		var command := _policy_command(catalog, decision, turns)
		var pre := controller.engine.snapshot()
		if controller.submit(command).accepted:
			BattleReplay.record_command(replay, command, pre)
	var result = controller.engine.get_result()
	if result.is_empty():
		return {}
	BattleReplay.record_result(replay, result, turns)
	return replay

## Cycle through legal moves; sometimes forfeit late in a long fight.
func _policy_command(catalog: ContentCatalog, decision: Dictionary, turn: int) -> BattleCommand:
	var legal: Array = decision.legal_moves
	if legal.is_empty() or turn == 397:
		return BattleCommand.new(StringName(decision.actor_id), BattleCommand.Kind.FORFEIT, &"", [], int(decision.revision))
	var choice: Dictionary = legal[turn % legal.size()]
	var move := catalog.get_definition(StringName(choice.move_id)) as MoveDefinition
	var targets: Array[StringName] = []
	if move.target_mode == MoveDefinition.TargetMode.CHOSEN:
		for index in mini(move.target_count, choice.target_ids.size()):
			targets.append(StringName(choice.target_ids[(index + turn) % choice.target_ids.size()]))
	return BattleCommand.new(StringName(decision.actor_id), BattleCommand.Kind.USE_MOVE, StringName(choice.move_id), targets, int(decision.revision))

func _test_codes(replays: Array[Dictionary]) -> void:
	if replays.is_empty():
		return
	var replay := replays[0]
	var code := BattleReplay.encode(replay)
	_expect(code.begins_with(BattleReplay.CODE_PREFIX), "share codes carry their prefix")
	var lengths: Array = replays.map(func(r: Dictionary) -> String: return "%d cmds -> %d chars" % [(r.commands as Array).size(), BattleReplay.encode(r).length()])
	print("share codes: ", ", ".join(PackedStringArray(lengths)))
	var decoded := BattleReplay.decode(code)
	_expect(decoded.ok and MultiplayerWorldSync.fingerprint(decoded.replay) == MultiplayerWorldSync.fingerprint(replay), "a share code decodes to the identical replay")
	var wrapped := "```\n" + code.substr(0, 40) + "\n" + code.substr(40) + "\n```"
	_expect(BattleReplay.decode(wrapped).ok, "a code wrapped over lines in a code block still decodes")
	_expect(not BattleReplay.decode("hello").ok, "text that is not a code is refused")
	_expect(not BattleReplay.decode(code.substr(0, code.length() / 2)).ok, "a truncated code is refused")
	var damaged := code.substr(0, 30) + ("A" if code[30] != "A" else "B") + code.substr(31)
	var damaged_result := BattleReplay.decode(damaged)
	if damaged_result.ok:
		# Base64 damage can survive inflation; the engine still validates every command.
		_expect(BattleReplay.simulate(damaged_result.replay, root.get_node("CampaignRuntime").catalog) is Dictionary, "a damaged but decodable code simulates safely")
	_expect(not BattleReplay.validate({"v": 1, "setup": [], "rules": {}, "commands": [], "seed": 1}).ok, "a replay with a malformed setup is refused")
	var tampered: Dictionary = replay.duplicate(true)
	(tampered.commands as Array)[0]["m"] = "base:move/does_not_exist"
	var tampered_run := BattleReplay.simulate(tampered, root.get_node("CampaignRuntime").catalog)
	_expect(not tampered_run.ok, "a tampered command stops the replay instead of inventing a turn")

func _test_history(replays: Array[Dictionary]) -> void:
	if replays.is_empty():
		return
	_clean_history_dir()
	var history := BattleHistoryRepository.new(HISTORY_DIR)
	var first_id := history.add(replays[0])
	_expect(history.set_kept(first_id, true), "a replay can be kept")
	var imported_id := history.add(replays[1 % replays.size()], true)
	_expect(history.add(replays[1 % replays.size()], true) == imported_id, "the same code pasted twice is stored once")
	for index in BattleHistoryRepository.MAX_RECENT + 5:
		var copy: Dictionary = replays[index % replays.size()].duplicate(true)
		copy["recorded_at"] = 1000 + index # Distinct recordings.
		history.add(copy)
	var entries := history.list()
	var unkept := entries.filter(func(entry: Dictionary) -> bool: return not bool(entry.get("kept", false))).size()
	_expect(unkept == BattleHistoryRepository.MAX_RECENT, "only the newest %d unkept battles stay (%d)" % [BattleHistoryRepository.MAX_RECENT, unkept])
	_expect(entries.any(func(entry: Dictionary) -> bool: return String(entry.id) == first_id), "a kept battle is never pruned")
	_expect(entries.any(func(entry: Dictionary) -> bool: return String(entry.id) == imported_id and bool(entry.imported)), "a pasted code is kept and marked as shared")
	_expect(int(entries[0].recorded_at) == 1000 + BattleHistoryRepository.MAX_RECENT + 4, "the newest battle is listed first")
	var files := DirAccess.get_files_at(HISTORY_DIR)
	_expect(files.size() == entries.size() + 1, "pruned replay files are deleted (%d files for %d entries)" % [files.size(), entries.size()])
	var loaded := history.load_replay(first_id)
	_expect(loaded.ok and MultiplayerWorldSync.fingerprint(loaded.replay) == MultiplayerWorldSync.fingerprint(replays[0]), "a stored replay loads back identically")
	history.remove(first_id)
	_expect(not history.list().any(func(entry: Dictionary) -> bool: return String(entry.id) == first_id) and not FileAccess.file_exists(HISTORY_DIR.path_join(first_id + ".mhr")), "deleting removes the entry and its file")
	_expect(not history.load_replay("../../escape").ok, "ids cannot leave the history folder")
	_expect(BattleReplay.outcome(replays[0]) in ["Victory", "Defeat", "Forfeited"], "a fought battle has an outcome (%s)" % BattleReplay.outcome(replays[0]))

## The real battle scene plays the replay to its end card.
func _test_scene_playback(runtime: Node, replay: Dictionary) -> void:
	var recorded_before := BattleHistoryRepository.new().list().size()
	var battle: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(battle)
	await process_frame
	var finished := [false]
	battle.network_battle_finished.connect(func() -> void: finished[0] = true)
	battle.call("begin_replay", replay)
	battle.set_playback_speed(4.0)
	var hud: Control = battle.get_node("ReplayHud")
	var deadline := Time.get_ticks_msec() + 240000
	while Time.get_ticks_msec() < deadline and hud.get_node_or_null("ReplayEnd") == null:
		await create_timer(0.25, true, false, true).timeout
	var end_card := hud.get_node_or_null("ReplayEnd")
	_expect(end_card != null, "the replay reaches its end card in the battle scene")
	if end_card != null:
		var winner := BattleReplay.team_name(replay, int(replay.result.winner))
		var title: Label = end_card.find_child("EndTitle", true, false)
		_expect(title != null and title.text == ("%s wins!" % winner).to_upper(), "the end card names the recorded winner (%s)" % (title.text if title != null else "none"))
		_expect(int(battle.get("_replay_cursor")) == (replay.commands as Array).size(), "playback used every recorded command")
		_expect(int(battle.get("_turns_played")) == int(replay.result.turns), "playback took the recorded number of turns")
		_expect(BattleHistoryRepository.new().list().size() == recorded_before, "watching a replay does not record it again")
		(hud.find_child("ExitButton", true, false) as Button).pressed.emit()
		_expect(finished[0], "Exit leaves the replay")
	_expect(is_equal_approx(Engine.time_scale, 1.0), "leaving a replay restores normal speed")
	battle.queue_free()
	await process_frame
	_expect(is_equal_approx(Engine.time_scale, 1.0), "the game runs at normal speed after the replay scene closes")

func _clean_history_dir() -> void:
	if not DirAccess.dir_exists_absolute(HISTORY_DIR):
		return
	for file in DirAccess.get_files_at(HISTORY_DIR):
		DirAccess.remove_absolute(HISTORY_DIR.path_join(file))
	DirAccess.remove_absolute(HISTORY_DIR)
