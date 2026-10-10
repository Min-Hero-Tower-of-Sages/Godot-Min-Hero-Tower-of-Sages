extends SceneTree

## Player-report coverage. Campaign writes use memory, never actual slots.
class MemoryRepository extends SaveRepository:
	var payload: Dictionary = {}
	func save_slot(_slot: int, data: Dictionary) -> Dictionary:
		payload = data.duplicate(true)
		return {"ok": true}
	func load_slot(_slot: int) -> Dictionary:
		return {"ok": true, "state": payload.duplicate(true)}

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _run() -> void:
	await process_frame
	var catalog: ContentCatalog = root.get_node("CampaignRuntime").catalog
	var fields := {
		"m_currFloorOfTower": 33, "m_currMoney": 100,
		"m_hasBeatenFloor32": true, "m_hasBeatenFloor1": true, "m_isMapUnlocked2": true,
		"m_minionsOwned0": true, "m_minionsSeen4": true,
		"m_isMod_holyBirb1": true, "m_minionsOwned102": true,
		"minion0": true, "minion0dexID": 1, "minion0exp": 60000,
		"minion0currHealth": 7,
	}
	var converted := FlashSaveImportService.new().convert_fields(fields, catalog)
	_check(converted.ok, "Cannot build imported fixture: %s" % converted.get("message", ""))
	if not converted.ok:
		quit(1)
		return
	var session := CampaignSession.new()
	session.catalog = catalog
	session.campaign = catalog.get_definition(&"base:campaign/standard_tower") as CampaignDefinition
	session.state = CampaignState.new()
	session.state.load_dictionary(converted.state)
	session.save_repository = MemoryRepository.new()
	session.save_slot = 1
	var ticub_id := ""
	var seen_id := ""
	for pack in catalog.packs:
		for definition in pack.definitions:
			if definition is MinionDefinition and definition.source_mod == &"base":
				if definition.legacy_numeric_id == 0: ticub_id = String(definition.id)
				if definition.legacy_numeric_id == 4: seen_id = String(definition.id)
	_check(not ticub_id.is_empty() and ticub_id in session.state.progression.owned_minion_ids, "Historic unevolved Ticub ownership lost")
	_check(seen_id in session.state.progression.seen_minion_ids and seen_id not in session.state.progression.owned_minion_ids, "Seen-only history confused with ownership")
	_check("arkvian:minion/holybird1" in session.state.progression.owned_minion_ids, "Enabled-mod historical Dex ID lost")
	# Repair an already-imported v2 slot without healing its new port damage.
	session.state.progression.flash_import.version = 2
	session.state.progression.owned_minion_ids = ["base:minion/fire_pig_1"]
	session.state.party[0].persistent_health = 7
	_check(session.save().ok and session.load(1).ok, "Cannot repair existing imported slot")
	_check(session.state.progression.flash_import.version == 3 and session.state.party[0].persistent_health == 7, "v3 repair healed previously repaired party")
	_check(ticub_id in session.state.progression.owned_minion_ids and "base:minion/fire_pig_1" in session.state.progression.owned_minion_ids, "Repair overwrote port collection history")
	_check(session.select_tower_floor(33).ok and session.state.progression.map_unlocked, "Hard map not restored from normal-floor Flash flag")
	_check(session.enter_tower_lobby().ok and session.select_tower_floor(2).ok and session.state.progression.map_unlocked, "Normal map lost after leaving/re-entering")
	# Sponsor slots are local; all four slots work at max level, including removal.
	var owned: OwnedMinionState = session.state.party[0]
	var definition := catalog.get_definition(owned.definition_id) as MinionDefinition
	for socket in 4:
		var gem := CampaignGemFactory.create_random(2)
		gem.instance_id = "followup-gem-%d" % socket
		session.state.owned_gems.append(gem)
		_check(CampaignGemEquipmentService.slot_is_available(owned, definition, socket), "Max-level socket %d locked" % socket)
		_check(CampaignGemEquipmentService.equip_gem(session.state, catalog, StringName(gem.instance_id), owned.instance_id, socket).ok, "Cannot equip socket %d" % socket)
		_check(CampaignGemEquipmentService.unequip_gem(session.state, catalog, owned.instance_id, socket).ok, "Cannot remove socket %d" % socket)
	var sponsor_definition := MinionDefinition.new()
	sponsor_definition.gem_slots = 2
	sponsor_definition.locked_gem_slots = 1
	owned.level = 5
	_check(not CampaignGemEquipmentService.slot_is_available(owned, sponsor_definition, 2) and CampaignGemEquipmentService.slot_is_available(owned, sponsor_definition, 3), "Sponsor/evolution restrictions confused")
	owned.level = 60
	# A deterministic contact zone verifies arrival, escape, reuse and cancel.
	var room := catalog.get_definition(session.state.current_room_id) as RoomDefinition
	var room_view := CampaignRoomView.new()
	root.add_child(room_view)
	_check(room_view.configure(room, &"start", Vector2(1000, 1000), {}, {"progression": session.state.progression}), "Cannot render room fixture")
	room_view._room_transitions.clear()
	var area := room_view._make_trigger("FixturePortal", Vector2(1000, 1000), Vector2(67, 67), Vector2.ONE, 0)
	var exit := {"_contact_guard_id": "fixture", "source_teleport": true}
	room_view._room_transitions.append({"area": area, "exit": exit})
	var transitions := [0]
	room_view.transition_requested.connect(func(_exit: Dictionary) -> void: transitions[0] += 1)
	room_view._player.position = area.position - CampaignRoomView.PLAYER_COLLISION_TOP_LEFT - CampaignRoomView.PLAYER_COLLISION_SIZE * 0.5
	room_view.release_transition_lock()
	room_view._check_transition_contacts()
	_check(transitions[0] == 0, "Arrival portal immediately reactivated")
	room_view._player.position.x += 200
	room_view._check_transition_contacts()
	room_view._player.position.x -= 200
	room_view._check_transition_contacts()
	_check(transitions[0] == 1, "Portal did not rearm after walking away")
	room_view.release_transition_lock()
	room_view._check_transition_contacts()
	_check(transitions[0] == 1, "Cancelled exit immediately reopened")
	room_view.queue_free()
	# All ten visible number tabs dispatch directly, and replacement cards fit.
	var storage := CampaignStorageMenuView.new()
	root.add_child(storage)
	storage.configure(session, func(host: Control, _owned: OwnedMinionState, _callback: Callable) -> void:
		var card := ColorRect.new()
		card.size = Vector2(323, 76)
		host.add_child(card))
	var tabs := 0
	for child in storage._menu.get_children():
		if child is Button and String(child.name).begins_with("StorageBoxTab"):
			tabs += 1
			_check(child.visible and child.z_index > 2 and child.focus_mode == Control.FOCUS_NONE, "Storage tab hidden or covered")
	_check(tabs == 10, "Missing storage number tabs")
	storage._menu.get_node("StorageBoxTab3").pressed.emit()
	_check(storage._box_page == 2, "Number tab does not select box")
	storage._party_slot_picker_id = owned.instance_id
	storage._render()
	var replacement := storage._menu.get_node("StoragePartyReplacement")
	_check(replacement.get_child(0) is ColorRect and replacement.get_child(0).color.a > 0.6, "Replacement popup does not obscure underlying controls")
	for child in replacement.get_children():
		if child is Control and child.size == Vector2(323, 76):
			_check(child.position.y == 77, "Replacement card uses overlapping spacing")
	storage.queue_free()
	var tooltip_host := Control.new()
	tooltip_host.position = Vector2(30, 10)
	tooltip_host.scale = Vector2.ONE * 1.5
	root.add_child(tooltip_host)
	var tooltip := preload("res://src/presentation/source_gem_tooltip.gd").new()
	tooltip_host.add_child(tooltip)
	tooltip.show_gem(session.state.owned_gems[0])
	await process_frame
	tooltip.set_process(false)
	var viewport_size: Vector2 = root.get_visible_rect().size
	for point in [Vector2(0, 0), viewport_size - Vector2.ONE]:
		tooltip._place_at_canvas_point(point)
		var bounds: Rect2 = tooltip.get_global_rect()
		_check(bounds.position.x >= 7 and bounds.position.y >= 7 and bounds.end.x <= viewport_size.x - 7 and bounds.end.y <= viewport_size.y - 7, "Scaled gem tooltip trails off screen")
	tooltip_host.queue_free()
	# The actual campaign shell requires a decision before changing floor state.
	var runtime := root.get_node("CampaignRuntime")
	var previous_session: CampaignSession = runtime.session
	runtime.session = session
	var shell := preload("res://scenes/application_shell.tscn").instantiate()
	root.add_child(shell)
	shell._show_room_from_state()
	var leave := {"target_route": "lobby"}
	shell._on_room_transition_requested(leave)
	_check(not session.state.progression.in_tower_lobby and shell.interaction_dialog != null and not shell._room_transition_active, "Floor exit committed without confirmation")
	_check(shell._source_dialogue_yes.is_valid() and shell._source_dialogue_no.is_valid(), "Floor exit has no Yes/No controls")
	shell._source_dialogue_no.call()
	_check(not session.state.progression.in_tower_lobby and shell.current_room._controls_enabled, "Declining exit changes floor or blocks movement")
	shell._on_room_transition_requested(leave)
	shell._source_dialogue_yes.call()
	await create_timer(1.3).timeout
	_check(session.state.progression.in_tower_lobby and shell.current_room.room.id == &"base:room/main_tower_lobby" and shell.current_room._controls_enabled, "Confirmed exit failed to fade back to lobby")
	shell.queue_free()
	runtime.session = previous_session
	await process_frame
	# Actual Destabilize dispatch must move the field, not only create a tween.
	var main := preload("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.catalog = catalog
	main.start_overlay.hide()
	_check(main.cooldown_tip.get_node("CooldownText").autowrap_mode == TextServer.AUTOWRAP_WORD_SMART and main.cooldown_tip.size.x == 220, "Cooldown warning text expands beyond its banner")
	var move := catalog.get_definition(&"base:move/destabilize/tier1") as MoveDefinition
	_check(main._resolved_visual_id(move) == 55, "Destabilize visual alias not resolved")
	var before: float = main.arena_floor.position.x
	var event := BattleEvent.new(0, &"move_used", &"", &"", {"move_id": String(move.id), "hit": true})
	main._animate_event(event)
	await create_timer(0.15).timeout
	_check(absf(main.arena_floor.position.x - before) > 1, "Destabilize field does not actually shake")
	await create_timer(2.6).timeout
	_check(is_equal_approx(main.arena_floor.position.x, before), "Destabilize leaves field displaced")
	main.queue_free()
	await process_frame
	print("%s: imported collection/map repair, sockets, portal escape, storage controls/overlay, Destabilize (%d checks)" % ["PASS" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)
