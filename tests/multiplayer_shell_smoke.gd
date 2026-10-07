extends SceneTree

## End-to-end: two full game shells over localhost, driven like players.
##   godot --headless --path . --script res://tests/multiplayer_shell_smoke.gd
##   godot --headless --path . --script res://tests/multiplayer_shell_smoke.gd -- --mode=follow
##   godot --headless --path . --script res://tests/multiplayer_shell_smoke.gd -- --mode=duo
##   godot --headless --path . --script res://tests/multiplayer_shell_smoke.gd -- --mode=versus
## Co-op (default): the guest joins with a fresh start, walks to another room
## on its own, fights a trainer the host does not watch, follows the host to
## the lobby, then both fight in the arena. Follow: the guest follows the host
## between rooms, starts a trainer battle the host must watch, then the arena.
## Duo: the guest's trainer fight invites the host, who accepts through the
## prompt and fights as the partner. Versus: both race their own runs, the
## host's campaign is swapped out and comes back when the game closes.

const SHELL_SCENE := preload("res://scenes/application_shell.tscn")
const RESULT_PATH := "user://multiplayer_shell_smoke_guest.txt"
## The guest's progress, printed by the host when something fails.
const TRACE_PATH := "user://multiplayer_shell_smoke_guest_trace.txt"
const TRAINER_ROOM := &"base:room/level_1_1_a"
const TRAINER_ENCOUNTER := &"base:encounter/grass_floor1_room1_normal"
const TIMEOUT_MSEC := 45000

class MemorySaveRepository extends SaveRepository:
	var saved: Dictionary = {}
	func save_slot(slot: int, payload: Dictionary) -> Dictionary:
		saved[slot] = payload.duplicate(true)
		return {"ok": true}
	func load_slot(slot: int) -> Dictionary:
		return {"ok": true, "state": saved[slot].duplicate(true)} if saved.has(slot) else {"ok": false, "code": "not_found"}

var role := "host"
var mode := "coop"
var port := 0
var failures: Array[String] = []
var checks := 0
var runtime: Node
var net: Node
var shell: Control

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--role="): role = argument.trim_prefix("--role=")
		if argument.begins_with("--port="): port = int(argument.trim_prefix("--port="))
		if argument.begins_with("--mode="): mode = argument.trim_prefix("--mode=")
	if port == 0:
		port = 26000 + randi() % 2000
	_run.call_deferred()

func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append("[%s] %s" % [role, message])

func _trace(text: String) -> void:
	if role != "guest":
		return
	var file := FileAccess.open(TRACE_PATH, FileAccess.READ_WRITE if FileAccess.file_exists(TRACE_PATH) else FileAccess.WRITE)
	file.seek_end()
	file.store_line("%.1fs %s" % [Time.get_ticks_msec() / 1000.0, text])
	file.close()

func _wait_for(condition: Callable, what: String, timeout_msec: int = TIMEOUT_MSEC) -> bool:
	_trace("waiting for " + what)
	var deadline := Time.get_ticks_msec() + timeout_msec
	while not condition.call():
		if Time.get_ticks_msec() > deadline:
			_expect(false, "timed out waiting for " + what)
			return false
		await process_frame
	return true

func _exploring() -> bool:
	return is_instance_valid(shell.current_room) and shell.current_room.room != null and shell.current_battle == null and not shell._room_transition_active

func _run() -> void:
	Engine.time_scale = 4.0
	await process_frame
	runtime = root.get_node("CampaignRuntime")
	net = root.get_node("NetSession")
	runtime.session.save_repository = MemorySaveRepository.new()
	var created: Dictionary = runtime.start_new_campaign(1, "Host" if role == "host" else "Guest", &"male" if role == "host" else &"female")
	_expect(created.ok, "campaign starts")
	# Skip first-visit tutorials that would pause either player.
	for key in ["move_select_tutorial_seen", "battle_basics_tutorial_seen", "energy_tutorial_seen", "type_effectiveness_tutorial_seen", "focus_targets_tutorial_seen", "key_keepers_tutorial_seen"]:
		runtime.session.state.progression[key] = true
	runtime.save_campaign()
	shell = SHELL_SCENE.instantiate()
	root.add_child(shell)
	await process_frame
	match [role, mode]:
		["host", "follow"]: await _run_host()
		["host", "duo"]: await _run_host_duo()
		["host", "versus"]: await _run_host_versus()
		["host", _]: await _run_host_coop()
		[_, "follow"]: await _run_guest()
		[_, "duo"]: await _run_guest_duo()
		[_, "versus"]: await _run_guest_versus()
		_: await _run_guest_coop()

func _finish() -> void:
	if role == "guest":
		var file := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
		file.store_string(JSON.stringify({"failures": failures, "checks": checks}))
		file.close()
	net.leave()
	Engine.time_scale = 1.0
	await create_timer(0.5).timeout
	_trace("finished with failures: %s" % [failures])
	if failures.is_empty():
		print("PASS: %d multiplayer shell checks (%s, %s)" % [checks, role, mode])
		quit(0)
	else:
		for failure in failures: push_error(failure)
		if role == "host" and FileAccess.file_exists(TRACE_PATH):
			print("guest trace:
" + FileAccess.get_file_as_string(TRACE_PATH))
		print("FAIL: %d of %d multiplayer shell checks (%s, %s)" % [failures.size(), checks, role, mode])
		quit(1)

## Whoever holds the decision forfeits; used to end battles headlessly.
func _forfeit_when_my_turn(battle: Node) -> void:
	while is_instance_valid(battle) and battle.controller.engine.get_result().is_empty():
		var decision: Dictionary = battle.controller.engine.get_decision()
		if not battle.busy and not decision.is_empty() and battle._is_local_decision(decision):
			battle.forfeit_confirmation.visible = true
			battle._confirm_forfeit()
			return
		await process_frame

# --- Host -----------------------------------------------------------------------------------

func _open_and_launch_guest(options: Dictionary = {}) -> bool:
	if FileAccess.file_exists(TRACE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TRACE_PATH))
	var hosted: Dictionary = net.host(port, "Hosty", options if not options.is_empty() else {"mode": mode})
	_expect(hosted.ok, "the host opens its game: %s" % hosted.get("message", ""))
	var guest_pid := OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tests/multiplayer_shell_smoke.gd", "--", "--role=guest", "--port=%d" % port, "--mode=%s" % mode])
	_expect(guest_pid > 0, "guest process launches")
	return await _wait_for(func() -> bool: return net.players.size() == 2, "the guest to join")

## Accept every arena challenge through the on-screen prompt.
func _auto_accept_prompts() -> void:
	net.prompt_requested.connect(func(prompt_id: int, _kind: String, _from: int, _text: String) -> void:
		await process_frame
		var view: Control = shell._multiplayer._prompt_views.get(prompt_id)
		if is_instance_valid(view): view._answer(true))

func _collect_guest_report() -> void:
	await _wait_for(func() -> bool: return FileAccess.file_exists(RESULT_PATH), "the guest's report")
	await create_timer(0.3).timeout
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RESULT_PATH))
	for failure in report.get("failures", []):
		failures.append(String(failure))
	checks += int(report.get("checks", 0))
	if net.is_host():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(net._profiles.path()))

func _teleport_to(room_id: StringName) -> void:
	var state = runtime.session.state
	var room := runtime.catalog.get_definition(room_id) as RoomDefinition
	state.current_room_id = room_id
	state.room_state["current_location"] = {"room_id": String(room_id), "spawn_id": String(room.spawn_ids[0]), "position": [room.spawn_positions[String(room.spawn_ids[0])].x, room.spawn_positions[String(room.spawn_ids[0])].y], "facing": "down"}
	shell._show_room_from_state()

func _team_size(battle: Node, team: int) -> int:
	return (battle.controller.engine.snapshot().state.combatants as Array).filter(func(entry: Dictionary) -> bool: return int(entry.team) == team).size()

func _run_host_duo() -> void:
	shell._show_room_from_state()
	await _wait_for(_exploring, "the host room")
	if not await _open_and_launch_guest({"mode": "coop", "max_players": 2, "double_battles": true}):
		await _finish()
		return
	# The guest touches a trainer: we are asked to fight together.
	if not await _wait_for(func() -> bool: return not shell._multiplayer._prompt_views.is_empty(), "the double battle invite"):
		await _finish()
		return
	var prompt: Control = shell._multiplayer._prompt_views.values()[0]
	_expect(String(prompt.find_child("Message", true, false).text).contains("Fight together"), "the invite says what it is")
	prompt._answer(true)
	if not await _wait_for(func() -> bool: return shell.current_battle != null and shell.current_battle.net_role == &"ally", "joining as the partner"):
		await _finish()
		return
	var battle: Node = shell.current_battle
	await _wait_for(func() -> bool: return not battle.combatant_views.is_empty(), "the double battle views")
	_expect(battle.net_spec.has("actor_controllers"), "the partner fights from the double battle spec")
	_expect(_team_size(battle, 0) == runtime.session.state.party.size() * 2 and _team_size(battle, 1) % 2 == 0, "both parties against the doubled trainer team (%d vs %d): %s" % [_team_size(battle, 0), _team_size(battle, 1), (battle.controller.engine.snapshot().state.combatants as Array).map(func(entry: Dictionary) -> String: return "%s/%d/%d" % [entry.instance_id, entry.team, entry.slot_index])])
	_forfeit_when_my_turn(battle)
	await _wait_for(func() -> bool: return _exploring() and net.battle_lock.is_empty(), "returning from the double battle")
	_expect(runtime.session.state.applied_battle_ids.any(func(id: String) -> bool: return id.begins_with("ally:")), "the partner's side of the battle was settled")
	await _collect_guest_report()
	await _finish()

func _run_guest_duo() -> void:
	await create_timer(0.5).timeout
	shell._multiplayer.show_join_view()
	shell._multiplayer._on_join_requested("127.0.0.1", port, "Guesty", {"fresh": true, "gender": "female"})
	if not await _wait_for(func() -> bool: return _exploring() and net.is_guest(), "joining the duo game"):
		await _finish()
		return
	_expect(net.double_battles_enabled(), "the duo game has double battles")
	_teleport_to(TRAINER_ROOM)
	await _wait_for(_exploring, "the trainer room")
	await create_timer(0.5).timeout
	shell._begin_trainer_battle(TRAINER_ENCOUNTER, shell.current_room.player_position())
	if not await _wait_for(func() -> bool: return shell.current_battle != null and shell.current_battle.net_role == &"battler", "the double battle"):
		await _finish()
		return
	var battle: Node = shell.current_battle
	_expect(bool(battle.net_spec.get("double", false)) and battle.net_spec.has("actor_controllers"), "the leader runs a double battle")
	await _forfeit_when_my_turn(battle)
	await _wait_for(func() -> bool: return _exploring(), "returning after the double battle")
	await _finish()

func _run_host_versus() -> void:
	shell._show_room_from_state()
	await _wait_for(_exploring, "the host room")
	var real_room: StringName = shell.current_room.room.id
	var real_slot: int = runtime.session.save_slot
	if not await _open_and_launch_guest({"mode": "versus"}):
		await _finish()
		return
	var campaign := runtime.catalog.get_definition(&"base:campaign/standard_tower") as CampaignDefinition
	_expect(net.host_in_race() and runtime.session.state.current_room_id == campaign.starting_room_id, "the host races from the tower's door too")
	runtime.session.state.progression["floor_keys"] = 1
	var guest_id: int = net.other_player_ids()[0]
	await _wait_for(func() -> bool: return not net.player_location(guest_id).is_empty(), "the guest's location")
	await _wait_for(func() -> bool: return int(net._profiles.profile("Guesty").get("state", {}).get("progression", {}).get("floor_keys", 0)) == 3, "the guest's run to reach the host")
	_expect(int(runtime.session.state.progression.floor_keys) == 1, "a racer's keys are its own")
	await _collect_guest_report()
	# Closing the race brings the real campaign back.
	net.leave()
	await _wait_for(func() -> bool: return _exploring() and runtime.session.state.current_room_id == real_room, "the host's own campaign")
	_expect(not net.host_in_race() and runtime.session.save_slot == real_slot, "the host is back in its own save")
	await _finish()

func _run_guest_versus() -> void:
	await create_timer(0.5).timeout
	shell._multiplayer.show_join_view()
	shell._multiplayer._on_join_requested("127.0.0.1", port, "Guesty", {"slot": 1})
	if not await _wait_for(func() -> bool: return _exploring() and net.is_guest(), "joining the race"):
		await _finish()
		return
	var campaign := runtime.catalog.get_definition(&"base:campaign/standard_tower") as CampaignDefinition
	_expect(net.is_versus() and runtime.session.state.current_room_id == campaign.starting_room_id, "the guest races from the tower's door")
	_expect(shell._multiplayer.allow_interaction(&"floor_picker") and shell._multiplayer.allow_room_transition({"target_route": "lobby"}), "racers choose their own way and floors")
	await _wait_for(func() -> bool: return int(net.player_location(1).get("floor", -1)) >= 0, "the host's location")
	runtime.session.state.progression["floor_keys"] = 3
	await create_timer(2.5).timeout
	_expect(int(runtime.session.state.progression.floor_keys) == 3, "the host's keys never reach this racer")
	await _finish()

func _run_host_coop() -> void:
	if FileAccess.file_exists(RESULT_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RESULT_PATH))
	shell._show_room_from_state()
	await _wait_for(_exploring, "the host room")
	var start_room: StringName = shell.current_room.room.id
	_auto_accept_prompts()
	if not await _open_and_launch_guest():
		await _finish()
		return
	var guest_id: int = net.other_player_ids()[0]
	await _wait_for(func() -> bool: return _exploring() and shell.current_room._remote_avatars.has(guest_id), "the guest avatar beside the host")
	# The guest walks off on its own: the host stays where it is.
	await _wait_for(func() -> bool: return not shell.current_room._remote_avatars.has(guest_id), "the guest to leave the host's room")
	_expect(shell.current_room.room.id == start_room, "the host is not dragged along when a co-op guest changes room")
	# The guest fights a trainer: the host keeps exploring and sees it in the roster.
	if await _wait_for(func() -> bool: return net.player_battling(guest_id), "the guest's trainer battle"):
		_expect(shell.current_battle == null and _exploring(), "the host is not pulled into a co-op guest's battle")
		_expect(shell._multiplayer._roster_label.text.contains("⚔"), "the roster shows who is battling")
	await _wait_for(func() -> bool: return not net.player_battling(guest_id), "the guest's battle to end")
	# The host takes everyone to the lobby.
	var entered: Dictionary = runtime.enter_tower_lobby()
	_expect(entered.ok, "the host enters the lobby")
	shell._show_room_from_state()
	await _wait_for(func() -> bool: return _exploring() and shell.current_room._remote_avatars.has(guest_id), "the guest following into the lobby")
	# The in-game menu shows the multiplayer panel with the Minion Keeper.
	shell._show_campaign_menu()
	var panel: Node = shell.interaction_dialog.find_child("MultiplayerMenuPanel", true, false) if shell.interaction_dialog != null else null
	_expect(panel != null and panel.find_child("StorageButton", true, false) != null, "the in-game menu has a multiplayer panel with the Minion Keeper")
	shell._clear_dialog(true)
	# Arena: the guest challenges us.
	if not await _wait_for(func() -> bool: return shell.current_battle != null and shell.current_battle.net_role == &"pvp", "the arena battle"):
		await _finish()
		return
	_forfeit_when_my_turn(shell.current_battle)
	await _wait_for(func() -> bool: return _exploring() and net.battle_lock.is_empty(), "returning from the arena")
	await _collect_guest_report()
	await _finish()

func _run_host() -> void:
	if FileAccess.file_exists(RESULT_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RESULT_PATH))
	shell._show_room_from_state()
	await _wait_for(_exploring, "the host room")
	_auto_accept_prompts()
	if not await _open_and_launch_guest():
		await _finish()
		return
	var guest_id: int = net.other_player_ids()[0]
	await _wait_for(func() -> bool: return _exploring() and shell.current_room._remote_avatars.has(guest_id), "the guest avatar in the host room")
	if shell.current_room._remote_avatars.has(guest_id):
		var avatar: Node = shell.current_room._remote_avatars[guest_id]
		_expect(String(avatar.get_node("NameTag").text) == "Guesty", "the guest's name floats above its avatar")
	_expect(shell._multiplayer._roster_label.text.contains("Guesty"), "the HUD roster lists the guest")
	# Move the group: the guest must follow into the trainer room.
	var state = runtime.session.state
	state.current_room_id = TRAINER_ROOM
	var room := runtime.catalog.get_definition(TRAINER_ROOM) as RoomDefinition
	state.room_state["current_location"] = {"room_id": String(TRAINER_ROOM), "spawn_id": String(room.spawn_ids[0]), "position": [room.spawn_positions[String(room.spawn_ids[0])].x, room.spawn_positions[String(room.spawn_ids[0])].y], "facing": "down"}
	shell._show_room_from_state()
	# The guest now starts a trainer battle; we must be pulled in to watch it.
	if not await _wait_for(func() -> bool: return shell.current_battle != null and shell.current_battle.net_role == &"spectator", "spectating the guest's battle"):
		await _finish()
		return
	_expect(String(shell.current_battle.net_spec.get("kind", "")) == "trainer", "the spectated battle is the guest's trainer fight")
	var watched: Node = shell.current_battle
	# The guest may challenge us right after; the arena can start before we
	# even observe the room, so only wait for the spectator scene to close.
	await _wait_for(func() -> bool: return not is_instance_valid(watched) or shell.current_battle != watched, "the spectator view to close")
	_expect(runtime.session.state.current_room_id == TRAINER_ROOM, "the host stays in its own room after watching")
	# Arena: the guest challenges us (lobby picker equivalent).
	if not await _wait_for(func() -> bool: return shell.current_battle != null and shell.current_battle.net_role == &"pvp", "the arena battle"):
		await _finish()
		return
	var host_arena: Node = shell.current_battle
	_forfeit_when_my_turn(host_arena)
	await _wait_for(func() -> bool: return _exploring() and net.battle_lock.is_empty(), "returning from the arena")
	await _collect_guest_report()
	await _finish()

# --- Guest ----------------------------------------------------------------------------------

func _run_guest_coop() -> void:
	await create_timer(0.5).timeout
	shell._multiplayer.show_join_view()
	shell._multiplayer._on_join_requested("127.0.0.1", port, "Guesty", {"fresh": true, "gender": "female"})
	if not await _wait_for(func() -> bool: return _exploring() and net.is_guest(), "joining the host's world"):
		await _finish()
		return
	_expect(net.join_profile_status == "fresh", "a fresh start was chosen (%s)" % net.join_profile_status)
	_expect(runtime.session.state.party.size() == CampaignProgressionService.STARTERS.size(), "a fresh start plays with the starters")
	_expect(shell.current_room.room.id == net.host_room_id, "the guest starts beside the host")
	await _wait_for(func() -> bool: return shell.current_room._remote_avatars.has(1), "the host avatar")
	# Co-op: doors work for guests.
	shell._on_room_transition_requested({"target_room_id": "base:room/level_1_1_courtyard", "transition_id": 12})
	if not await _wait_for(func() -> bool: return _exploring() and shell.current_room.room.id == &"base:room/level_1_1_courtyard", "walking into the courtyard alone"):
		await _finish()
		return
	_expect(not shell.current_room._remote_avatars.has(1), "the host is not drawn in a room it is not in")
	# A trainer fight of our own, then a forfeit.
	var state = runtime.session.state
	var room := runtime.catalog.get_definition(TRAINER_ROOM) as RoomDefinition
	state.current_room_id = TRAINER_ROOM
	state.room_state["current_location"] = {"room_id": String(TRAINER_ROOM), "spawn_id": String(room.spawn_ids[0]), "position": [room.spawn_positions[String(room.spawn_ids[0])].x, room.spawn_positions[String(room.spawn_ids[0])].y], "facing": "down"}
	shell._show_room_from_state()
	await _wait_for(_exploring, "the trainer room")
	await create_timer(0.5).timeout
	shell._begin_trainer_battle(TRAINER_ENCOUNTER, shell.current_room.player_position())
	if not await _wait_for(func() -> bool: return shell.current_battle != null and shell.current_battle.net_role == &"", "a local trainer battle"):
		await _finish()
		return
	_expect(net.battle_lock.is_empty(), "a co-op trainer battle does not take the shared battle slot")
	await _forfeit_when_my_turn(shell.current_battle)
	await _wait_for(func() -> bool: return _exploring(), "returning after the forfeit")
	# The host goes to the lobby: we follow.
	if not await _wait_for(func() -> bool: return _exploring() and shell.current_room.room.id == &"base:room/main_tower_lobby", "following the host to the lobby"):
		await _finish()
		return
	_expect(String(runtime.session.state.safe_location.get("room_id", "")) == "base:room/main_tower_lobby", "the guest adopts the host's checkpoint on a floor change")
	# Guests cannot change the floor themselves.
	_expect(not shell._multiplayer.allow_interaction(&"floor_picker"), "only the host picks the floor")
	await _wait_for(func() -> bool: return not net.player_battling(1), "the host to be free")
	await create_timer(1.0).timeout
	var reply: Dictionary = await net.request_pvp(1, net.provide_pvp_team())
	_expect(reply.ok, "the arena challenge is accepted: %s" % reply.get("message", ""))
	if not await _wait_for(func() -> bool: return shell.current_battle != null and shell.current_battle.net_role == &"pvp", "the arena battle"):
		await _finish()
		return
	var arena: Node = shell.current_battle
	_forfeit_when_my_turn(arena)
	await _wait_for(func() -> bool: return _exploring() and net.battle_lock.is_empty(), "returning from the arena")
	await _finish()

func _run_guest() -> void:
	await create_timer(0.5).timeout
	shell._multiplayer.show_join_view()
	shell._multiplayer._on_join_requested("127.0.0.1", port, "Guesty", {"slot": 1})
	if not await _wait_for(func() -> bool: return _exploring() and net.is_guest(), "joining the host room"):
		await _finish()
		return
	_expect(shell.current_room.room.id == net.host_room_id, "the guest appears in the host's room")
	await _wait_for(func() -> bool: return shell.current_room._remote_avatars.has(1), "the host avatar")
	# Guests cannot lead: touching an exit is refused with a notice.
	shell._on_room_transition_requested({"target_room_id": "base:room/level_1_1_courtyard", "transition_id": 1})
	_expect(not shell._room_transition_active and shell.current_room.room.id == net.host_room_id, "a guest cannot take the group through a door")
	# Follow the host into the trainer room.
	if not await _wait_for(func() -> bool: return _exploring() and shell.current_room.room.id == TRAINER_ROOM, "following the host to the trainer room"):
		await _finish()
		return
	await create_timer(0.5).timeout
	shell._begin_trainer_battle(TRAINER_ENCOUNTER, shell.current_room.player_position())
	if not await _wait_for(func() -> bool: return shell.current_battle != null and shell.current_battle.net_role == &"battler", "the shared trainer battle"):
		await _finish()
		return
	await _forfeit_when_my_turn(shell.current_battle)
	await _wait_for(func() -> bool: return _exploring(), "returning after the forfeit")
	_expect(shell.current_room.room.id == net.host_room_id, "after a loss the guest is back with the host, not at its own checkpoint")
	await _wait_for(func() -> bool: return net.battle_lock.is_empty() and not net.player_battling(1), "the battle slot to clear and the host to stop watching")
	await create_timer(1.0).timeout
	var reply: Dictionary = await net.request_pvp(1, net.provide_pvp_team())
	_expect(reply.ok, "the arena challenge is accepted: %s" % reply.get("message", ""))
	if not await _wait_for(func() -> bool: return shell.current_battle != null and shell.current_battle.net_role == &"pvp", "the arena battle"):
		await _finish()
		return
	_expect(shell.current_battle._local_teams == [0], "the challenger fights as team 0")
	var arena: Node = shell.current_battle
	_forfeit_when_my_turn(arena)
	if not await _wait_for(func() -> bool: return _exploring() and net.battle_lock.is_empty(), "returning from the arena"):
		_expect(false, "arena diagnostics: battle=%s result=%s busy=%s transition=%s room=%s lock=%s decision=%s queue=%s log=%s" % [is_instance_valid(shell.current_battle), arena.controller.engine.get_result().winning_team if is_instance_valid(arena) else -9, arena.busy if is_instance_valid(arena) else "-", shell._room_transition_active, is_instance_valid(shell.current_room), net.battle_lock, arena.controller.engine.get_decision() if is_instance_valid(arena) else {}, arena._net_command_queue if is_instance_valid(arena) else [], net._command_log])
	await _finish()
