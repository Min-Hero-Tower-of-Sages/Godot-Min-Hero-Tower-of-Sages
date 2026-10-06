extends SceneTree

class MemorySession extends CampaignSession:
	var reject_save := false
	func _save_candidate(_candidate) -> Dictionary:
		return {"ok": not reject_save, "message": "Fixture save rejected"}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var runtime := root.get_node("CampaignRuntime")
	var original_session: CampaignSession = runtime.session
	var session := MemorySession.new()
	session.catalog = runtime.catalog
	session.campaign = session.catalog.get_definition(&"base:campaign/standard_tower") as CampaignDefinition
	session.state = CampaignState.new()
	session.state.campaign_id = session.campaign.id
	session.state.character = {"name": "Transition fixture", "gender": "male"}
	var starter := OwnedMinionState.new()
	starter.instance_id = &"transition-starter"
	starter.definition_id = &"base:minion/fire_pig_1"
	starter.level = 5
	starter.experience = 5300
	starter.learned_move_ids.assign((session.catalog.get_definition(starter.definition_id) as MinionDefinition).initial_move_ids)
	session.state.party.append(starter)
	var encounter_id := &"base:encounter/grass_floor1_room1_normal"
	for definition in session.catalog._by_id.values():
		if definition is RoomDefinition and encounter_id in definition.encounter_ids:
			session.state.current_room_id = definition.id
	runtime.session = session
	var shell := (load("res://scenes/application_shell.tscn") as PackedScene).instantiate()
	root.add_child(shell)
	shell.call("_show_room_from_state")
	var old_room: CampaignRoomView = shell.current_room
	old_room.set_physics_process(false)
	# Failed preparation must leave exploration usable, with no curtain/pending
	# scene. All persistence is intercepted by this in-memory session.
	session.reject_save = true
	shell.call("_begin_trainer_battle", encounter_id, old_room.player_position())
	assert(not shell._room_transition_active and shell.current_battle == null and old_room._controls_enabled)
	session.reject_save = false
	shell.call("_begin_trainer_battle", encounter_id, old_room.player_position())
	var battle: Control = shell.current_battle
	assert(battle != null and not battle.visible and shell.current_room == old_room)
	assert(shell._room_transition_active and not old_room._controls_enabled)
	assert(battle.audio_controller.music_owner == shell._campaign_audio)
	shell.call("_begin_trainer_battle", encounter_id, old_room.player_position())
	assert(shell.current_battle == battle, "Duplicate activation must not create a second battle")
	shell.call("_show_campaign_menu")
	assert(shell.interaction_dialog == null, "Room menus must stay blocked under the scene curtain")
	await create_timer(0.2).timeout
	assert(shell._campaign_audio.current_music_id == "forestTrack", "Battle track started before the source one-second delay")
	assert(shell.current_room == old_room and not battle.visible)
	assert(shell.room_transition_curtain.color.a > 0 and shell.room_transition_curtain.color.a < 1)
	await _capture("entry_fade")
	await create_timer(0.38).timeout
	assert(shell.current_room == null and battle.visible and shell.room_transition_curtain.color.a > 0.99)
	assert(battle.campaign_mode and not battle.combatant_views.is_empty(), "Hidden battle must already be initializing its spawn visuals")
	await _capture("entry_black")
	await create_timer(0.3).timeout
	assert(shell.room_transition_curtain.color.a > 0 and shell.room_transition_curtain.color.a < 1)
	await _capture("entry_reveal")
	await create_timer(0.45).timeout
	assert(not shell._room_transition_active and not shell.room_transition_curtain.visible)
	assert(battle.busy and not battle.move_panel.visible, "Scene reveal must not bypass battle intro/decision gating")
	assert(shell._campaign_audio.current_music_id == "battleTrack" and shell._campaign_audio.music_player.playing)
	assert(not battle.audio_controller.music_player.playing, "Battle must not compete with the persistent music player")
	await _capture("entry_finished")
	assert(runtime.cancel_unstarted_battle().ok)
	# Forfeit settlement owns checkpoint/healing; shell must only fade and return.
	shell.call("_on_campaign_forfeit_return_requested")
	await create_timer(0.2).timeout
	assert(shell.current_battle == battle and shell.current_room == null)
	assert(shell.room_transition_curtain.color.a > 0 and shell.room_transition_curtain.color.a < 1)
	await create_timer(0.38).timeout
	assert(shell.current_battle == null and shell.current_room != null)
	assert(shell.room_transition_curtain.color.a > 0.99 and not shell.current_room._controls_enabled)
	await create_timer(0.3).timeout
	assert(not shell.current_room._controls_enabled and shell.room_transition_curtain.color.a < 1)
	shell.call("_clear_dialog")
	assert(not shell.current_room._controls_enabled, "Closing a dialog must not unlock movement mid-reveal")
	await create_timer(0.45).timeout
	assert(not shell._room_transition_active and shell.current_room._controls_enabled)
	assert(not shell.room_transition_curtain.visible and shell._trainer_return_location.is_empty())
	assert(shell._campaign_audio.current_music_id == "forestTrack" and shell._campaign_audio.music_player.playing, "Forfeit did not restore room music")
	# Exercise the final loss handoff with the real loss blackout already opaque.
	runtime.session.state.safe_location = {"room_id": String(runtime.session.state.current_room_id), "position": shell.current_room.player_position(), "spawn_id": "start"}
	assert(runtime.prepare_trainer_battle(encounter_id, shell.current_room.player_position()).ok)
	var loss_battle := (load("res://scenes/main.tscn") as PackedScene).instantiate() as Control
	shell.screen_host.add_child(loss_battle)
	shell.current_battle = loss_battle
	loss_battle.defeat_transition_layer.visible = true
	loss_battle.defeat_black.modulate.a = 1.0
	loss_battle.defeat_message.visible = true
	shell.current_room.queue_free()
	shell.current_room = null
	shell.room_hud.visible = false
	var loss_result := BattleResult.new()
	loss_result.battle_id = StringName(runtime.session.state.pending_battle.battle_id)
	loss_result.winning_team = 1
	loss_result.reason = &"elimination"
	loss_result.participants = [{"instance_id": String(runtime.session.state.party[0].instance_id), "team": 0, "persistent_changes": {"health": 0, "energy": 0}}]
	assert(runtime.settle_campaign_battle(loss_result).ok)
	assert(not runtime.session.state.pending_defeat_return.is_empty() and runtime.session.state.party[0].persistent_energy == 0)
	session.reject_save = true
	shell.call("_on_campaign_defeat_return_requested")
	assert(shell.current_battle == loss_battle and shell.interaction_dialog != null and not shell._room_transition_active)
	assert(not runtime.session.state.pending_defeat_return.is_empty() and runtime.session.state.party[0].persistent_energy == 0, "Rejected return mutated committed loss resources")
	session.reject_save = false
	var retry_buttons: Array[Node] = shell.interaction_dialog.find_children("", "Button", true, false)
	assert(not retry_buttons.is_empty())
	retry_buttons[0].pressed.emit()
	await process_frame
	assert(runtime.session.state.pending_defeat_return.is_empty() and runtime.session.state.party[0].persistent_energy > 0)
	await create_timer(0.2).timeout
	assert(shell.current_battle == loss_battle and loss_battle.defeat_message.visible)
	await create_timer(0.38).timeout
	assert(shell.current_battle == null and shell.current_room != null and shell.room_transition_curtain.color.a > 0.99)
	await create_timer(0.3).timeout
	assert(not shell.current_room._controls_enabled and shell.room_transition_curtain.color.a > 0.0 and shell.room_transition_curtain.color.a < 1.0)
	await _capture("defeat_reveal")
	await create_timer(0.45).timeout
	assert(shell.current_room._controls_enabled and not shell._room_transition_active and not shell.room_transition_curtain.visible)
	# Isolate the victory scene handoff after a rematch-style finish. Rewards
	# and progression settlement are covered by their own native fixtures; this
	# checks the old scene, curtain, return position and persistent music lifetime.
	shell.call("_begin_trainer_battle", encounter_id, shell.current_room.player_position())
	await create_timer(1.35).timeout
	var victory_battle: Control = shell.current_battle
	assert(victory_battle != null and shell._campaign_audio.current_music_id == "battleTrack")
	assert(runtime.cancel_unstarted_battle().ok)
	shell._trainer_return_location["first_visit"] = false
	victory_battle.campaign_settlement = {"ok": true, "first_clear_rewards": {}}
	shell.call("_on_campaign_return_requested")
	await create_timer(0.2).timeout
	assert(shell.current_battle == victory_battle and shell.current_room == null)
	assert(shell.room_transition_curtain.color.a > 0.0 and shell.room_transition_curtain.color.a < 1.0)
	await create_timer(0.38).timeout
	assert(shell.current_battle == null and shell.current_room != null)
	assert(shell.room_transition_curtain.color.a > 0.99 and not shell.current_room._controls_enabled)
	assert(shell._campaign_audio.current_music_id == "forestTrack" and shell._campaign_audio.music_player.playing)
	await create_timer(0.3).timeout
	await _capture("victory_reveal")
	assert(not shell.current_room._controls_enabled and shell.room_transition_curtain.color.a < 1.0)
	await create_timer(0.45).timeout
	assert(shell.current_room._controls_enabled and not shell._room_transition_active and not shell.room_transition_curtain.visible)
	shell.queue_free()
	await process_frame
	runtime.session = original_session
	print("PASS: trainer entry, victory, forfeit and defeat 0.5/0.2/0.5 fades, shared music/delayed battle cue, hidden spawns, retained loss message, input guards and failed-save recovery")
	quit(0)

func _capture(suffix: String) -> void:
	if "--capture-transitions" not in OS.get_cmdline_user_args():
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://development/campaign_transition_%s.png" % suffix)
