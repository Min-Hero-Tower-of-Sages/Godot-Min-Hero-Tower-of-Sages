extends SceneTree

## Renders the multiplayer screens to PNGs for a visual check (needs a window,
## not --headless):
##   godot --path . --script res://tests/multiplayer_ui_capture.gd -- --out=C:/some/folder
## Saves the in-game menu (solo and hosting), the host and join panels, and
## the arena picker. Nothing is written to the real save slots.

const SHELL_SCENE := preload("res://scenes/application_shell.tscn")

class MemorySaveRepository extends SaveRepository:
	var saved: Dictionary = {}
	func save_slot(slot: int, payload: Dictionary) -> Dictionary:
		saved[slot] = payload.duplicate(true)
		return {"ok": true}
	func load_slot(slot: int) -> Dictionary:
		return {"ok": true, "state": saved[slot].duplicate(true)} if saved.has(slot) else {"ok": false, "code": "not_found"}

var out_dir := "user://multiplayer_ui_capture"
var shell: Control
var net: Node

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): out_dir = argument.trim_prefix("--out=")
	_run.call_deferred()

func _settle(seconds: float = 0.9) -> void:
	await create_timer(seconds).timeout
	await process_frame
	await process_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(out_dir)
	image.save_png("%s/%s.png" % [out_dir, name])
	print("saved ", name)

func _run() -> void:
	await process_frame
	var runtime := root.get_node("CampaignRuntime")
	net = root.get_node("NetSession")
	runtime.session.save_repository = MemorySaveRepository.new()
	runtime.start_new_campaign(1, "Vala", &"female")
	runtime.start_new_campaign(2, "Ryder", &"male")
	runtime.load_campaign(1)
	for key in ["move_select_tutorial_seen", "battle_basics_tutorial_seen", "energy_tutorial_seen", "type_effectiveness_tutorial_seen", "focus_targets_tutorial_seen", "key_keepers_tutorial_seen"]:
		runtime.session.state.progression[key] = true
	shell = SHELL_SCENE.instantiate()
	root.add_child(shell)
	await process_frame
	shell._show_room_from_state()
	await _settle(1.5)
	shell._show_campaign_menu()
	await _settle()
	await _shot("1_menu_solo")
	shell._multiplayer.show_host_view()
	await _settle()
	await _shot("2_host_view_closed")
	net.host(27000 + randi() % 1000, "Vala")
	net.players[2] = {"name": "Ryder", "gender": "male", "color": 1, "battling": true}
	net.players[3] = {"name": "Mika", "gender": "female", "color": 2, "battling": false}
	await _settle(0.3)
	await _shot("3_host_view_open")
	shell._clear_dialog(true)
	shell._show_campaign_menu()
	await _settle()
	await _shot("4_menu_hosting")
	shell._multiplayer.show_arena_picker()
	await _settle()
	await _shot("5_arena_picker")
	shell._clear_dialog(true)
	shell._multiplayer._on_prompt_requested(99, "pvp", 2, "Ryder challenges you to an arena battle!")
	await _settle(0.6)
	await _shot("7_prompt")
	shell._multiplayer._on_prompt_closed(99)
	net._profiles.store("Ryder", {"party": [{}]})
	net._profiles.store("OldFriend", {"party": [{}]})
	shell._multiplayer.show_profiles_view()
	await _settle()
	await _shot("8_saved_players")
	shell._clear_dialog(true)
	var state = runtime.session.state
	state.progression["map_unlocked"] = true
	net.players[2]["where"] = {"floor": 0, "lobby": false, "room": "base:room/level_1_1_courtyard"}
	net.players[3]["where"] = {"floor": 0, "lobby": false, "room": "base:room/level_1_1_courtyard"}
	shell._show_floor_map()
	await _settle(1.2)
	await _shot("9_floor_map")
	shell._clear_dialog(true)
	runtime.enter_tower_lobby()
	state = runtime.session.state
	state.progression["unlocked_floor_indices"] = [0, 1, 2]
	net.players[3]["where"] = {"floor": 1, "lobby": false, "room": ""}
	shell._show_room_from_state()
	await _settle(1.0)
	shell._show_floor_picker()
	await _settle(1.5)
	await _shot("10_floor_select")
	shell._clear_dialog(true)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(net._profiles.path()))
	net.players.erase(2)
	net.players.erase(3)
	net.leave()
	await _settle(0.5)
	await _capture_double_battle(runtime)
	shell._show_title_screen()
	await _settle(0.5)
	shell._show_save_slots()
	await _settle(7.0)
	await _shot("12_title_join_button")
	shell._multiplayer.show_join_view()
	await _settle()
	await _shot("6_join_view")
	quit(0)

## A double battle as the leader sees it (offline, so it just waits on turns).
func _capture_double_battle(runtime: Node) -> void:
	runtime.load_campaign(2)
	for key in ["move_select_tutorial_seen", "battle_basics_tutorial_seen", "energy_tutorial_seen", "type_effectiveness_tutorial_seen", "focus_targets_tutorial_seen", "key_keepers_tutorial_seen"]:
		runtime.session.state.progression[key] = true
	runtime.session.state.current_room_id = &"base:room/level_1_1_a"
	# Fill both parties so the screenshot shows the dense ten-place layout.
	var state = runtime.session.state
	while state.party.size() < 5:
		var extra: OwnedMinionState = OwnedMinionState.from_dictionary(state.party[state.party.size() % 2].to_dictionary())
		extra.instance_id = StringName("capture-%d" % state.party.size())
		state.party.append(extra)
	runtime.prepare_trainer_battle(&"base:encounter/grass_floor1_room1_normal", Vector2.ZERO)
	var partner := CampaignProgressionService.party_setup_combatants(state, runtime.catalog)
	var built := MultiplayerDoubleBattle.build_setup(runtime.prepared_battle_setup, partner.combatants, 2)
	runtime.prepared_battle_setup = built.setup
	if is_instance_valid(shell.current_room):
		shell.current_room.queue_free()
	shell.room_hud.visible = false
	var battle: Node = load("res://scenes/main.tscn").instantiate()
	shell.screen_host.add_child(battle)
	battle.call("share_campaign_battle", "capture", {"actor_controllers": built.actor_controllers, "double": true, "double_teams": built.double_teams})
	battle.call("begin_campaign_battle")
	await _settle(4.0)
	await _shot("11_double_battle")
	battle.queue_free()
