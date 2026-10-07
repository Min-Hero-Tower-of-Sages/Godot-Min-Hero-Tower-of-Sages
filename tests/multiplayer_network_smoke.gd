extends SceneTree

## Real two-process multiplayer smoke over localhost. Run the host role; it
## launches the guest role itself and compares both results:
##   godot --headless --path . --script res://tests/multiplayer_network_smoke.gd
## Covers: username rejection, join, presence, world deltas both ways, the
## host keeping the guest's profile (and giving it back on a later join), guest
## save isolation, battle-slot arbitration (follow mode), and a full PvP
## lockstep battle.

const Sync = preload("res://src/application/multiplayer_world_sync.gd")
const RESULT_PATH := "user://multiplayer_smoke_guest.txt"
const TIMEOUT_MSEC := 45000

class MemorySaveRepository extends SaveRepository:
	var saved: Dictionary = {}
	func save_slot(slot: int, payload: Dictionary) -> Dictionary:
		saved[slot] = payload.duplicate(true)
		return {"ok": true}
	func load_slot(slot: int) -> Dictionary:
		return {"ok": true, "state": saved[slot].duplicate(true)} if saved.has(slot) else {"ok": false, "code": "not_found"}

var role := "host"
var port := 0
var failures: Array[String] = []
var checks := 0
var runtime: Node
var net: Node
var repository: MemorySaveRepository

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--role="): role = argument.trim_prefix("--role=")
		if argument.begins_with("--port="): port = int(argument.trim_prefix("--port="))
	if port == 0:
		port = 24000 + randi() % 2000
	_run.call_deferred()

func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append("[%s] %s" % [role, message])

func _wait_for(condition: Callable, what: String) -> bool:
	var deadline := Time.get_ticks_msec() + TIMEOUT_MSEC
	while not condition.call():
		if Time.get_ticks_msec() > deadline:
			_expect(false, "timed out waiting for " + what)
			return false
		await process_frame
	return true

func _run() -> void:
	await process_frame
	runtime = root.get_node("CampaignRuntime")
	net = root.get_node("NetSession")
	repository = MemorySaveRepository.new()
	runtime.session.save_repository = repository
	var created: Dictionary = runtime.start_new_campaign(1, "Host" if role == "host" else "Guest", &"male" if role == "host" else &"female")
	_expect(created.ok, "campaign starts")
	if role == "host":
		await _run_host()
	else:
		await _run_guest()

func _finish() -> void:
	if role == "guest":
		var file := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
		file.store_string(JSON.stringify({"failures": failures, "checks": checks, "final": get_meta("final", "")}))
		file.close()
	net.leave()
	await create_timer(0.3).timeout
	if failures.is_empty():
		print("PASS: %d multiplayer network checks (%s)" % [checks, role])
		quit(0)
	else:
		for failure in failures: push_error(failure)
		print("FAIL: %d of %d multiplayer network checks (%s)" % [failures.size(), checks, role])
		quit(1)

# --- Host -----------------------------------------------------------------------------------

func _run_host() -> void:
	if FileAccess.file_exists(RESULT_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RESULT_PATH))
	var state = runtime.session.state
	var hosted: Dictionary = net.host(port, "Hosty", {"mode": net.MODE_FOLLOW})
	_expect(hosted.ok, "host opens port %d: %s" % [port, hosted.get("message", "")])
	var guest_pid := OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tests/multiplayer_network_smoke.gd", "--", "--role=guest", "--port=%d" % port])
	_expect(guest_pid > 0, "guest process launches")
	var specs: Array = []
	net.battle_spec_received.connect(func(spec: Dictionary) -> void: specs.append(spec))
	# Arena challenges ask first: decline the first one, accept the next.
	var prompts: Array = []
	net.prompt_requested.connect(func(prompt_id: int, kind: String, _from: int, _text: String) -> void:
		prompts.append(kind)
		net.answer_prompt(prompt_id, prompts.size() > 1))
	var room_id: StringName = state.current_room_id
	# Keep publishing our position so the guest sees us.
	var presence_ticker := func() -> void: net.update_local_presence(room_id, Vector2(300, 400), {"pose": "side", "walking": true, "left": true})
	process_frame.connect(presence_ticker)
	if not await _wait_for(func() -> bool: return net.players.size() == 2, "the guest to join"):
		await _finish()
		return
	var guest_id: int = net.other_player_ids()[0]
	_expect(net.player_name(guest_id) == "Guesty", "the guest joined under its own name")
	await _wait_for(func() -> bool: return not net.presence_of(guest_id).is_empty(), "guest presence")
	var presence: Dictionary = net.presence_of(guest_id)
	_expect(presence.get("room", &"") == room_id, "guest presence reports the host room")
	await _wait_for(func() -> bool: return int(state.progression.get("floor_keys", 0)) == 1, "the guest's key pickup to merge")
	_expect(bool(state.progression.get("completed_encounters", {}).get("base:encounter/smoke", false)), "guest encounter completion merged into the host world")
	_expect(int(state.progression.currency) == 0, "the guest's money never reaches the host")
	await _wait_for(func() -> bool: return int(net._profiles.profile("guesty").get("progression", {}).get("currency", 0)) == 777, "the guest's profile to reach the host")
	_expect(net._profiles.profile("Guesty").party.size() == 2, "the host keeps the guest's team")
	state.progression["sage_seals"] = 2 # Host-side world change, broadcast by polling.
	# Battle arbitration: the guest holds the slot first.
	await _wait_for(func() -> bool: return String(net.battle_lock.get("kind", "")) == "trainer", "the guest to reserve a battle")
	var denied: Dictionary = await net.request_battle("trainer", "host fight")
	_expect(not denied.ok, "a second battle is refused while one is running")
	await _wait_for(func() -> bool: return net.battle_lock.is_empty(), "the guest to release its battle")
	var granted: Dictionary = await net.request_battle("trainer", "host fight")
	_expect(granted.ok, "the slot is free again after release")
	net.release_battle(String(granted.get("key", "")))
	# PvP: the guest challenges us; drive our team when it is our turn.
	if not await _wait_for(func() -> bool: return not specs.is_empty(), "the arena challenge"):
		await _finish()
		return
	set_meta("final", await _drive_pvp(specs[0]))
	process_frame.disconnect(presence_ticker)
	await _wait_for(func() -> bool: return FileAccess.file_exists(RESULT_PATH), "the guest's report")
	await create_timer(0.3).timeout
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RESULT_PATH))
	for failure in report.get("failures", []):
		failures.append(String(failure))
	checks += int(report.get("checks", 0))
	_expect(String(report.get("final", "")) == String(get_meta("final")), "both machines finish the arena battle identically (%s vs %s)" % [report.get("final", ""), get_meta("final")])
	await _wait_for(func() -> bool: return net.players.size() == 1, "the guest to leave")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(net._profiles.path()))
	await _finish()

# --- Guest ----------------------------------------------------------------------------------

func _run_guest() -> void:
	var outcomes: Array = []
	net.join_finished.connect(func(ok: bool, message: String) -> void: outcomes.append([ok, message]))
	runtime.session.state = null
	net.join("127.0.0.1", port, "hosty", {"slot": 1})
	if not await _wait_for(func() -> bool: return not outcomes.is_empty(), "the duplicate-name answer"):
		await _finish()
		return
	_expect(not outcomes[0][0] and String(outcomes[0][1]).contains("already taken"), "a duplicate username (any case) is refused: %s" % outcomes[0][1])
	await create_timer(0.6).timeout
	outcomes.clear()
	net.join("127.0.0.1", port, "Guesty", {"slot": 1})
	if not await _wait_for(func() -> bool: return not outcomes.is_empty(), "the join answer"):
		await _finish()
		return
	_expect(outcomes[0][0], "the guest is accepted: %s" % outcomes[0][1])
	_expect(net.join_profile_status == "imported", "a first join brings the save's team (%s)" % net.join_profile_status)
	_expect(String(runtime.session.state.party[0].instance_id).begins_with("mp"), "imported minions are renamed for the host world")
	var state = runtime.session.state
	_expect(state != null and state.current_room_id == net.host_room_id, "the guest is placed in the host's room")
	var presence_ticker := func() -> void: net.update_local_presence(state.current_room_id, Vector2(500, 420), {"pose": "front", "walking": false, "left": false})
	process_frame.connect(presence_ticker)
	await _wait_for(func() -> bool: return not net.presence_of(1).is_empty(), "host presence")
	var host_presence: Dictionary = net.presence_of(1)
	_expect(host_presence.get("pose", &"") == &"side" and bool(host_presence.get("left", false)), "host pose and facing arrive")
	_expect((host_presence.get("position", Vector2.ZERO) as Vector2).distance_to(Vector2(300, 400)) < 1.0, "host position arrives")
	# World edits flow to the host as deltas; personal money stays here.
	state.progression["floor_keys"] = int(state.progression.get("floor_keys", 0)) + 1
	var completed: Dictionary = state.progression.get("completed_encounters", {}).duplicate(true)
	completed["base:encounter/smoke"] = true
	state.progression["completed_encounters"] = completed
	state.progression["currency"] = 777
	await _wait_for(func() -> bool: return int(state.progression.get("sage_seals", 0)) == 2, "the host's seal change")
	_expect(int(state.progression.get("floor_keys", 0)) == 1, "the merged key count comes back from the host")
	_expect(int(state.progression.currency) == 777, "host broadcasts never overwrite guest money")
	var saved: Dictionary = runtime.save_campaign()
	_expect(saved.ok, "the guest can save while connected")
	var written: Dictionary = repository.saved.get(1, {})
	_expect(int(written.get("progression", {}).get("currency", -1)) == 0, "the guest's own save is untouched by money earned in the host world")
	_expect(int(written.get("progression", {}).get("sage_seals", -1)) == 0, "the guest's own save keeps its own seals, not the host's")
	_expect(not written.get("progression", {}).get("completed_encounters", {}).has("base:encounter/smoke"), "the guest's own save keeps its own encounter progress")
	# Battle arbitration.
	var slot: Dictionary = await net.request_battle("trainer", "guest fight")
	_expect(slot.ok, "the guest reserves the battle slot")
	await create_timer(1.5).timeout
	net.release_battle(String(slot.get("key", "")))
	await _wait_for(func() -> bool: return net.battle_lock.is_empty(), "the slot to clear")
	await create_timer(1.5).timeout # Let the host run its own reservation.
	await _wait_for(func() -> bool: return net.battle_lock.is_empty(), "the host to release its slot")
	var specs: Array = []
	net.battle_spec_received.connect(func(spec: Dictionary) -> void: specs.append(spec))
	var refused: Dictionary = await net.request_pvp(1, net.provide_pvp_team())
	_expect(not refused.ok and String(refused.get("message", "")).contains("declined"), "a declined challenge says so: %s" % refused.get("message", ""))
	await _wait_for(func() -> bool: return net.battle_lock.is_empty(), "the declined challenge to free the arena")
	var challenge: Dictionary = await net.request_pvp(1, net.provide_pvp_team())
	_expect(challenge.ok, "the arena challenge is accepted: %s" % challenge.get("message", ""))
	if not await _wait_for(func() -> bool: return not specs.is_empty(), "the arena spec"):
		await _finish()
		return
	set_meta("final", await _drive_pvp(specs[0]))
	process_frame.disconnect(presence_ticker)
	# Leave and come back asking for a fresh start: the kept team wins.
	net.leave()
	_expect(runtime.session.state == null, "leaving drops the borrowed host world")
	await create_timer(0.8).timeout
	outcomes.clear()
	net.join("127.0.0.1", port, "GUESTY", {"fresh": true, "gender": "male"})
	if await _wait_for(func() -> bool: return not outcomes.is_empty(), "the second join"):
		_expect(outcomes[0][0] and net.join_profile_status == "returning", "a returning username gets its kept team (%s)" % net.join_profile_status)
		_expect(int(runtime.session.state.progression.currency) == 777, "the money earned last time is still there")
	await _finish()

# --- Shared PvP driver ----------------------------------------------------------------------

## Plays an arena battle exactly as main.gd does: local turns are chosen and
## streamed, remote turns are awaited and fingerprint-checked.
func _drive_pvp(spec: Dictionary) -> String:
	var key := String(spec.key)
	var local_teams: Array = []
	for team in spec.controllers:
		if int(spec.controllers[team]) == net.local_peer_id(): local_teams.append(int(team))
	_expect(local_teams.size() == 1, "each fighter controls exactly one arena team")
	var queue: Array = []
	var on_command := func(battle_key: String, command: Dictionary) -> void:
		if battle_key == key: queue.append(command)
	net.battle_command_received.connect(on_command)
	queue.append_array(net.buffered_battle_commands(key))
	var rules := RuleSetDefinition.new()
	rules.party_size = 5
	rules.configuration = (spec.rules.configuration as Dictionary).duplicate(true)
	var controller := BattleController.new()
	var started := controller.start((spec.setup as Dictionary).duplicate(true), runtime.catalog, rules, BattleRng.new(int(spec.seed)))
	_expect(started.accepted, "arena battle starts: %s" % started.message)
	var drift := 0
	var turns := 0
	while controller.engine.get_result().is_empty() and turns < 400:
		turns += 1
		var decision: Dictionary = controller.engine.get_decision()
		var revision := int(decision.revision)
		var command: BattleCommand
		if int(decision.team) in local_teams:
			var legal: Array = decision.legal_moves
			if legal.is_empty():
				command = BattleCommand.new(StringName(decision.actor_id), BattleCommand.Kind.FORFEIT, &"", [], revision)
			else:
				var choice: Dictionary = legal[turns % legal.size()]
				var move := runtime.catalog.get_definition(StringName(choice.move_id)) as MoveDefinition
				var targets: Array[StringName] = []
				var count := mini(move.target_count, choice.target_ids.size()) if move.target_mode == MoveDefinition.TargetMode.CHOSEN else 0
				for index in count: targets.append(StringName(choice.target_ids[index]))
				command = BattleCommand.new(StringName(decision.actor_id), BattleCommand.Kind.USE_MOVE, StringName(choice.move_id), targets, revision)
			var pre := controller.engine.snapshot()
			var target_strings: Array = []
			for target in command.target_ids: target_strings.append(String(target))
			controller.submit(command)
			net.send_battle_command(key, {"revision": revision, "actor": String(command.actor_id), "kind": "forfeit" if command.kind == BattleCommand.Kind.FORFEIT else "move", "move": String(command.move_id), "targets": target_strings}, pre)
			continue
		var deadline := Time.get_ticks_msec() + TIMEOUT_MSEC
		while queue.filter(func(entry: Dictionary) -> bool: return int(entry.revision) == revision).is_empty():
			if Time.get_ticks_msec() > deadline:
				_expect(false, "timed out waiting for the opponent's turn %d" % revision)
				return "timeout"
			await process_frame
		var queued: Dictionary = queue.filter(func(entry: Dictionary) -> bool: return int(entry.revision) == revision)[0]
		queue.erase(queued)
		if Sync.fingerprint(controller.engine.snapshot()) != int(queued.check):
			drift += 1
		var targets: Array[StringName] = []
		for raw in queued.targets: targets.append(StringName(raw))
		var remote := BattleCommand.new(StringName(queued.actor), BattleCommand.Kind.FORFEIT if queued.kind == "forfeit" else BattleCommand.Kind.USE_MOVE, StringName(queued.move), targets, revision)
		_expect(controller.submit(remote).accepted, "the opponent's command is legal here (revision %d)" % revision)
	_expect(drift == 0, "no state drift between fighters (%d mismatches)" % drift)
	var result = controller.engine.get_result()
	_expect(not result.is_empty(), "the arena battle finishes")
	net.release_battle(key)
	net.battle_command_received.disconnect(on_command)
	return "%d:%d:%d" % [Sync.fingerprint(controller.engine.snapshot()), result.winning_team, turns]
