class_name BattleHistoryController
extends Node

## Shell glue for battle replays: opens the "Battle replays" list (from the
## title screen or the in-game menu) and plays a replay full screen, then
## comes back to where the player was (the title screen or their room).

const HISTORY_VIEW := preload("res://src/presentation/battle_history_view.gd")
const BATTLE_SCENE: PackedScene = preload("res://scenes/main.tscn")

var shell: Control
var repository := BattleHistoryRepository.new()
## Where the list was opened from: the room's menu, or the title screen.
var _from_game := false

func show_history(from_game: bool) -> void:
	_from_game = from_game
	shell._clear_dialog()
	var view: Control = HISTORY_VIEW.new()
	shell.interaction_dialog = view
	shell._attach_interaction_dialog()
	view.configure(repository)
	view.closed.connect(_close_history)
	view.watch_requested.connect(watch)
	if from_game:
		shell._adopt_source_menu_backdrop(view)
	SourceMenuTransition.enter(view)

func _close_history() -> void:
	if _from_game:
		shell._close_source_menu(shell._show_campaign_menu)
	else:
		shell._clear_dialog()

## Play a replay over the current screen, then return to it.
func watch(replay: Dictionary) -> void:
	if shell._room_transition_active or shell.current_battle != null:
		return
	var from_game: bool = _from_game and is_instance_valid(shell.current_room)
	shell._clear_dialog(true)
	shell._room_transition_active = true
	if is_instance_valid(shell.current_room):
		shell.current_room.set_controls_enabled(false)
	var battle: Node = BATTLE_SCENE.instantiate()
	battle.settings_service = shell._settings
	battle.visible = false
	shell.current_battle = battle
	battle.audio_controller.music_owner = shell._campaign_audio
	battle.network_battle_finished.connect(_on_replay_finished.bind(battle, from_game), CONNECT_ONE_SHOT)
	shell._campaign_audio.fade_music_to(0.0, 0.5)
	await shell._fade_campaign_screen_out()
	if from_game:
		shell.current_room.queue_free()
		shell.current_room = null
		shell.room_hud.visible = false
	else:
		shell._clear_game_screen()
	shell.screen_host.add_child(battle)
	battle.call("begin_replay", replay)
	battle.visible = true
	await shell._finish_campaign_screen_transition()

func _on_replay_finished(battle: Node, from_game: bool) -> void:
	while shell._room_transition_active:
		await get_tree().process_frame
	shell._room_transition_active = true
	await shell._fade_campaign_screen_out()
	if is_instance_valid(battle):
		battle.queue_free()
	shell.current_battle = null
	if from_game and shell.runtime.session.state != null:
		shell._show_room_from_state()
	else:
		shell._campaign_audio.play_music("titleTrack", 1.0, 1.0)
		shell._build_title_screen(true)
		shell._show_save_slots()
	await shell._finish_campaign_screen_transition()
	# Back where the list was opened: show it again.
	show_history(from_game)
