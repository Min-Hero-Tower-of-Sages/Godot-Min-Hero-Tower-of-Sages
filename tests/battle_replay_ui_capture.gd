extends "res://tests/battle_replay_smoke.gd"

## Renders the battle replay screens and the multiplayer disconnect screens to
## PNGs for a visual check (needs a window, not --headless):
##   godot --path . --script res://tests/battle_replay_ui_capture.gd -- --out=C:/some/folder
## The replay list uses its own folder; real saves and history are untouched.

const SHELL_SCENE := preload("res://scenes/application_shell.tscn")
const CAPTURE_HISTORY := "user://battle_replay_capture"

var out_dir := "user://battle_replay_capture_shots"
var shell: Control

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): out_dir = argument.trim_prefix("--out=")
	_run.call_deferred()

func _settle(seconds: float = 0.9) -> void:
	await create_timer(seconds, true, false, true).timeout
	await process_frame
	await process_frame

func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.get_texture().get_image().save_png("%s/%s.png" % [out_dir, shot_name])
	print("saved ", shot_name)

func _run() -> void:
	await process_frame
	var runtime := root.get_node("CampaignRuntime")
	var net := root.get_node("NetSession")
	runtime.session.save_repository = MemorySaveRepository.new()
	runtime.start_new_campaign(1, "Vala", &"female")
	runtime.load_campaign(1)
	for key in ["move_select_tutorial_seen", "battle_basics_tutorial_seen", "energy_tutorial_seen", "type_effectiveness_tutorial_seen", "focus_targets_tutorial_seen", "key_keepers_tutorial_seen"]:
		runtime.session.state.progression[key] = true
	var state = runtime.session.state
	while state.party.size() < 5:
		var extra: OwnedMinionState = OwnedMinionState.from_dictionary(state.party[state.party.size() % 2].to_dictionary())
		extra.instance_id = StringName("capture-%d" % state.party.size())
		state.party.append(extra)
	# A few recorded fights for the list.
	var history := BattleHistoryRepository.new(CAPTURE_HISTORY)
	for id_entry in history.list():
		history.remove(String(id_entry.id))
	var fights: Array[Dictionary] = []
	for pick in [["base:encounter/grass_floor1_room5_expert", 9, "Bramble"], ["base:encounter/floor12_trainer_5_expert", 30, "Ivy the Expert"], ["base:encounter/grass_floor3_trainer_5_expert", 12, "Rocco"]]:
		var encounter := runtime.catalog.get_definition(StringName(pick[0])) as EncounterDefinition
		var fought := _record_battle(runtime, encounter, int(pick[1]), 11 + fights.size())
		if fought.is_empty():
			continue
		fought.names[1] = pick[2]
		fought["floor"] = fights.size() * 4
		fights.append(fought)
	var arena: Dictionary = fights[0].duplicate(true)
	arena.kind = "pvp"
	arena.names = {0: "Ryder", 1: "Vala"}
	arena.pov = 1
	history.add(arena, true)
	for fought in fights:
		history.add(fought)
	var entries := history.list()
	history.set_kept(String(entries[entries.size() - 1].id), true)
	for owned in state.party:
		owned.level = 4
	shell = SHELL_SCENE.instantiate()
	root.add_child(shell)
	shell._battle_history.repository = history
	await process_frame
	shell._show_save_slots()
	await _settle(7.0)
	await _shot("1_title_buttons")
	shell._battle_history.show_history(false)
	await _settle()
	await _shot("2_history_from_title")
	var view: Control = shell.interaction_dialog
	view.find_child("CodeField", true, false).text = "MHR1-not-a-real-code"
	view.call("_watch_code")
	await _settle(0.2)
	await _shot("3_history_bad_code")
	shell._clear_dialog(true)
	shell._show_room_from_state()
	await _settle(1.5)
	shell._show_campaign_menu()
	await _settle()
	await _shot("4_menu_solo")
	shell._battle_history.show_history(true)
	await _settle()
	await _shot("5_history_from_game")
	shell._clear_dialog(true)
	net.host(27000 + randi() % 1000, "Vala")
	net.players[2] = {"name": "Ryder", "gender": "male", "color": 1, "battling": true}
	net.players[3] = {"name": "Mika", "gender": "female", "color": 2, "battling": false}
	net.players[4] = {"name": "Jun", "gender": "male", "color": 3, "battling": false}
	await _settle(0.3)
	shell._show_campaign_menu()
	await _settle()
	await _shot("6_menu_hosting")
	shell._clear_dialog(true)
	net.players.erase(2)
	net.players.erase(3)
	net.players.erase(4)
	net.leave()
	await _settle(0.3)
	# Watch the longest recording from the room.
	var longest: Dictionary = fights[0]
	for fought in fights:
		if (fought.commands as Array).size() > (longest.commands as Array).size():
			longest = fought
	shell._battle_history._from_game = true
	shell._battle_history.watch(longest)
	await _settle(7.0)
	await _shot("7_replay_playing")
	var battle: Node = shell.current_battle
	var hud: Control = battle.get_node("ReplayHud")
	(hud.find_child("PauseButton", true, false) as Button).pressed.emit()
	(hud.find_child("Speed4", true, false) as Button).pressed.emit()
	hud.show_notice("Recorded on another version of the game: it may play out differently.")
	await _settle(0.3)
	await _shot("8_replay_paused_x4")
	(hud.find_child("PauseButton", true, false) as Button).pressed.emit()
	var deadline := Time.get_ticks_msec() + 180000
	while Time.get_ticks_msec() < deadline and hud.get_node_or_null("ReplayEnd") == null:
		await create_timer(0.25, true, false, true).timeout
	await _settle(0.5)
	await _shot("9_replay_end")
	(hud.find_child("CopyCodeButton", true, false) as Button).pressed.emit()
	await _settle(0.2)
	await _shot("10_replay_code_copied")
	battle.call("_show_battle_ended_card", "Ryder disconnected.")
	await _settle(0.5)
	await _shot("11_battle_ended_card")
	(hud.find_child("ExitButton", true, false) as Button).pressed.emit()
	await _settle(3.0)
	await _shot("12_back_to_history")
	shell._clear_dialog(true)
	# The disconnect screens a guest sees.
	for kind in ["lost", "closed"]:
		net.players[1] = {"name": "Ryder", "gender": "male", "color": 1}
		net.last_disconnect_kind = kind
		shell._multiplayer._on_disconnected("The connection to Ryder's game was lost." if kind == "lost" else "Ryder closed their game.")
		await _settle(1.5)
		await _shot("13_disconnect_%s" % kind)
		shell._clear_dialog(true)
		net.players.clear()
	for id_entry in history.list():
		history.remove(String(id_entry.id))
	DirAccess.remove_absolute(CAPTURE_HISTORY.path_join("index.json"))
	DirAccess.remove_absolute(CAPTURE_HISTORY)
	quit(0)
