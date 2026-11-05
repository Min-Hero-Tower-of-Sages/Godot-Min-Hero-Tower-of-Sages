extends "res://tests/user_mods_smoke.gd"

const ICE := &"tower_ice:floor/ice"
const LOBBY := &"base:room/main_tower_lobby"
const SHELL := preload("res://scenes/application_shell.tscn")
var shell: Node
var session: CampaignSession
var capture_dir := ""

func _run() -> void:
	await process_frame
	root.size = Vector2i(700, 525)
	var runtime := root.get_node("CampaignRuntime")
	catalog = runtime.catalog
	session = runtime.session
	var original_root := UserModRepository.root
	UserModRepository.root = "user://test_custom_floors_%d" % Time.get_ticks_usec()
	var saves := MemoryRepository.new()
	session.save_repository = saves
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="): capture_dir = argument.trim_prefix("--capture-dir=")
	var created: Dictionary = runtime.start_new_campaign(1, "Custom floor fixture", &"male")
	_check(created.ok and session.enter_tower_lobby().ok, "Set up an isolated lobby save")
	if session.state == null:
		_finish(original_root)
		return
	_check(CustomFloorDefinition.available(catalog, session.state).is_empty(), "Ice is opt-in")
	_check(session.set_mod_option("iceFloor", true).ok, "Enable built-in Ice Content")
	# Test side content from a Hard Mode save so it cannot accidentally try
	# to resolve a normal tower roster or reuse a normal hatchery pool.
	session.state.progression["floor_index"] = 32
	session.state.progression["unlocked_floor_indices"] = [0, 1, 31, 32]
	session.state.progression["highest_beaten_floor"] = 31
	session.state.progression["tower_mode"] = "hard"
	session.state.progression["map_unlocked_floor_indices"] = [1]
	var unlocked: Array = session.state.progression.unlocked_floor_indices.duplicate()
	shell = SHELL.instantiate()
	root.add_child(shell)
	shell._show_room_from_state()
	var lobby: CampaignRoomView = shell.current_room
	var contacts := lobby._room_interactions.filter(func(data: Dictionary) -> bool: return data.kind == &"side_hall_entry")
	_check(contacts.size() == 1, "Lobby has a real side door contact")
	if contacts.is_empty():
		_finish(original_root)
		return
	lobby._player.position = contacts[0]._zone_center - CustomFloorBuilder.PLAYER_FEET
	lobby._refresh_nearby_interactions()
	await create_timer(1.3).timeout
	_check(session.state.current_room_id == CustomFloorBuilder.HALL_ID, "Door contact enters the Side Hall")
	await _capture("01_side_hall")
	_use_room_feature(shell.current_room, &"custom_floor_picker")
	await create_timer(0.75).timeout
	var picker := shell.interaction_dialog as CampaignCustomFloorView
	_check(picker != null and not shell.current_room._controls_enabled, "Picker opens and captures movement")
	if picker == null:
		_finish(original_root)
		return
	await _capture("02_custom_floor_picker")
	var go := picker.find_child("CustomFloorGo", true, false) as BaseButton
	_check(go != null, "Ice Floor has a selectable row")
	if go != null: go.pressed.emit()
	await create_timer(1.3).timeout
	var room: CampaignRoomView = shell.current_room
	_check(room.room.custom_floor_id == ICE and shell.interaction_dialog == null, "Selecting Ice loads the real room")
	_check(not bool(session.state.progression.map_unlocked), "Custom floor does not inherit the prior floor map")
	_check(session.state.progression.unlocked_floor_indices == unlocked, "Custom entry preserves tower unlocks")
	_check(not session.set_mod_option("iceFloor", false).ok, "Cannot disable Ice while exploring it")
	await _capture("03_frozen_passage")
	await _check_puzzle(room)
	_check(session.enter_room(&"tower_ice:room/ice/sanctum").ok, "Enter the Ice Sage's room through its authored door")
	var denied := session.enter_room(&"tower_ice:room/ice/hatchery")
	_check(not denied.ok and denied.code == "locked_exit", "Hatchery requires beating the Ice Sage")
	var talk := session.interact(&"ice_sage")
	_check(talk.ok and String(talk.get("dialog_text", "")).begins_with("The ice"), "Ice Sage uses its authored dialogue")
	var prepared := session.prepare_battle(&"tower_ice:encounter/ice/sanctum/ice_sage")
	_check(prepared.ok, "Ice Sage prepares a real battle on a Hard Mode save: %s" % [prepared.get("message", "")])
	if not prepared.ok:
		_finish(original_root)
		return
	var result := BattleResult.new()
	result.battle_id = StringName(session.state.pending_battle.battle_id)
	result.winning_team = 0
	result.reason = &"victory"
	var finished := session.apply_battle_result(result)
	_check(finished.ok and session.enter_room(&"tower_ice:room/ice/hatchery").ok, "Winning opens the hatchery")
	_check(session.state.progression.unlocked_floor_indices == unlocked, "Ice Sage cannot advance the tower")
	shell._show_room_from_state()
	await _capture("04_ice_hatchery")
	var egg := session.interact(&"egg_2")
	_check(egg.ok and egg.minion.definition_id == &"ice_floor:minion/iunicorn1" and egg.level == 15, "Pick the exact minion and level authored for the egg")
	if egg.ok:
		saves.reject = true
		_check(not session.finish_egg_selection(egg.minion.instance_id).ok, "A failed save does not grant a minion")
		saves.reject = false
		_check(session.load(1).ok and int(session.state.progression.eggery_picks_remaining) == 1, "Reload rolls back an interrupted reveal")
		egg = session.interact(&"egg_2")
		_check(egg.ok and session.discard_latest_egg_minion(egg.minion.instance_id).ok, "Declining leaves the fixed reward available")
		egg = session.interact(&"egg_2")
		_check(egg.ok and session.finish_egg_selection(egg.minion.instance_id).ok, "Keeping an egg grants its minion")
	_use_room_feature(shell.current_room, &"custom_floor_return")
	await create_timer(1.3).timeout
	_check(session.state.current_room_id == CustomFloorBuilder.HALL_ID and session.enter_custom_floor(ICE).ok, "Return through the mounted hatchery exit and re-enter the Ice Floor")
	_check(int(session.state.progression.eggery_picks_remaining) == 0, "Returning cannot duplicate the reward")
	_check(session.enter_tower_lobby().ok and session.select_tower_floor(1).ok, "Normal tower remains selectable")
	_check(bool(session.state.progression.map_unlocked), "Returning to the tower restores the tower map")
	await _check_workshop()
	_finish(original_root)

func _check_puzzle(room: CampaignRoomView) -> void:
	var foot := CustomFloorBuilder.PLAYER_FEET
	room.set_controls_enabled(true)
	# Drive through the same input actions as keyboard movement.
	Input.action_press(&"move_right")
	for _index in 20: await physics_frame
	Input.action_release(&"move_right")
	var release_x := (room._player.position + foot).x
	for _index in 44: await physics_frame
	_check(release_x < 416 and (room._player.position + foot).x > 544, "Ice keeps moving after input release, then the pad jumps the gap")
	var steps := 0
	Input.action_press(&"move_left")
	while (room._player.position + foot).x > 352 and steps < 90:
		await physics_frame
		steps += 1
	Input.action_release(&"move_left")
	_check((room._player.position + foot).x < 416, "Return pad jumps back across the gap")
	room._player.position = Vector2(413, 352) - foot
	room._puzzle_jump_ticks = 0
	room._try_move_axis(Vector2(11, 0))
	_check(is_equal_approx((room._player.position + foot).x, 413.0), "The gap cannot be walked across")
	room._player.position = Vector2(760, 355) - foot
	room._puzzle_last_tile = -1
	room._puzzle_force = Vector2.ZERO
	room._puzzle_movement_tick(Vector2.LEFT)
	_check((room._player.position + foot).x > 760, "Arrow overrides opposite input")
	for _index in 12: room._puzzle_movement_tick(Vector2.ZERO)
	_check((room._player.position + foot).x >= 808 and room._puzzle_force == Vector2.ZERO, "Slow tile brakes forced travel")

func _use_room_feature(room: CampaignRoomView, kind: StringName) -> void:
	for interaction in room._room_interactions:
		if interaction.kind != kind: continue
		room._player.position = interaction._zone_center - CustomFloorBuilder.PLAYER_FEET
		var event := InputEventAction.new()
		event.action = &"interact"
		event.pressed = true
		room._unhandled_input(event)
		return
	_check(false, "No interaction zone for %s" % kind)

func _check_workshop() -> void:
	var manifest := {"format": 1, "id": "floor_fixture", "name": "Workshop Floor", "version": "1"}
	_check(UserModRepository.write(manifest).ok, "Create a Workshop mod")
	var view := ModWorkshopView.new()
	var canvas := CanvasLayer.new()
	canvas.layer = 20
	root.add_child(canvas)
	canvas.add_child(view)
	view.catalog = catalog
	view._edit("floor_fixture", "Floors")
	var editor := view._floors_tab
	editor._new_floor()
	await process_frame
	editor._new_room()
	await process_frame
	var map := editor._map
	_check(map.is_node_connected("entrance", 0, "room_1", 0) and map.is_node_connected("room_1", 0, "entrance", 0), "The floor map displays both directions of authored doors")
	var room_card := map.get_node("room_1") as GraphNode
	var before_drag := room_card.position_offset
	var title_position := room_card.get_global_transform_with_canvas() * Vector2(58, 12)
	await _drag_mouse(title_position, title_position + Vector2(14, 70))
	var moved_to := room_card.position_offset
	_check(moved_to != before_drag and editor._room.id == "room_1", "Dragging a map card with the mouse moves and selects it")
	_check(view._save_now(), "Moving a room on the floor map autosaves")
	view._edit("floor_fixture", "Floors")
	await process_frame
	editor = view._floors_tab
	map = editor._map
	_check((map.get_node("room_1") as GraphNode).position_offset == moved_to, "Map position survives reopening the Workshop mod")
	await _capture("05_custom_floor_map")
	map.node_selected.emit(map.get_node("room_1"))
	editor._new_room()
	await process_frame
	map = editor._map
	var source_card := map.get_node("entrance") as GraphNode
	var destination_card := map.get_node("room_2") as GraphNode
	var output := source_card.get_global_transform_with_canvas() * source_card.get_output_port_position(0)
	var input := destination_card.get_global_transform_with_canvas() * destination_card.get_input_port_position(0)
	await _drag_mouse(output, input)
	_check(map.is_node_connected("entrance", 0, "room_2", 0) and not map.is_node_connected("room_2", 0, "entrance", 0), "Drawing a map wire adds a one-way door")
	map.room_activated.emit("room_1")
	await process_frame
	_check(not editor._show_map and editor._room.id == "room_1", "Opening a map room shows its blueprint")
	editor._place_feature("return")
	editor._add_feature({"id": "prize", "kind": "egg", "x": 560, "y": 310, "minion": "base:minion/fire_pig_1", "level": 7})
	var art := Image.create_empty(780, 560, false, Image.FORMAT_RGBA8)
	art.fill(Color8(83, 92, 128))
	var imported := UserModRepository.import_image("floor_fixture", art, "test mural", true)
	_check(imported.ok, "Import room art larger than the minion sprite limit")
	if imported.ok:
		editor._place_object("mod_art:floor_fixture/" + String(imported.path).get_file(), Vector2(420, 290))
	editor._brush = "puzzle_arrow"
	editor._brush_settings.rotation = 90
	editor._stamp_tile(Vector2(192, 256))
	editor._brush = ""
	editor._rebuild_inspector()
	_check(view._save_now(), "Workshop writes custom rooms, puzzle tiles and imported art")
	await _capture("05_workshop_floors")
	var checked := UserModService.check(catalog, view._manifest)
	_check(checked.errors.is_empty(), "Workshop's Check accepts the authored floor: %s" % [checked.errors])
	var shared := UserModRepository.export_zip("floor_fixture", UserModRepository.root)
	_check(shared.ok, "Export custom floor with its PNG")
	if shared.ok:
		var decoded := UserModRepository.decode_zip(shared.path)
		_check(decoded.ok and decoded.files.size() == 1 and decoded.manifest.floors.size() == 1, "ZIP contains floor data and the imported PNG")
		if decoded.ok: _check(UserModRepository.install_bundle(decoded, true).ok, "Reinstall the exported floor")
	canvas.queue_free()
	await process_frame
	_check(session.enter_tower_lobby().ok and session.set_user_mod("floor_fixture", true).ok and session.enter_side_hall().ok, "Enable the Workshop floor on an existing save")
	var available := CustomFloorDefinition.available(catalog, session.state)
	var floor_id := &"floor_fixture:floor/new_floor"
	_check(available.any(func(floor: CustomFloorDefinition) -> bool: return floor.id == floor_id), "Player-made floor appears in the selector")
	_check(session.enter_custom_floor(floor_id).ok, "Load the authored floor")
	_check(not session.set_user_mod("floor_fixture", false).ok, "An active floor cannot be removed from under the player")
	var room_id := &"floor_fixture:room/new_floor/room_1"
	_check(session.enter_room(room_id).ok, "Workshop-created link is playable")
	var preview := session.interact(&"prize")
	_check(preview.ok and preview.minion.definition_id == &"base:minion/fire_pig_1" and preview.level == 7, "Custom floor hatchery uses the selected minion")
	_check(session.load(1).ok and session.state.current_room_id == room_id, "Reload a save inside an authored room")
	var updated: Dictionary = UserModRepository.read("floor_fixture").manifest
	updated.floors.clear()
	_check(UserModRepository.write(updated).ok and session.load(1).ok and session.state.current_room_id == CustomFloorBuilder.HALL_ID, "An updated mod with its floor removed returns the player safely to the Side Hall")

func _drag_mouse(origin: Vector2, destination: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = origin
	press.pressed = true
	root.push_input(press, true)
	await process_frame
	var motion := InputEventMouseMotion.new()
	motion.position = destination
	motion.relative = destination - origin
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion, true)
	await process_frame
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = destination
	root.push_input(release, true)
	await process_frame

func _capture(name: String) -> void:
	if capture_dir.is_empty() or DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(capture_dir)
	root.get_texture().get_image().save_png(capture_dir.path_join(name + ".png"))

func _finish(original_root: String) -> void:
	if is_instance_valid(shell): shell.queue_free()
	UserModService.deactivate(catalog)
	UserModRepository._remove_tree(UserModRepository.root)
	UserModRepository.root = original_root
	for failure in failures: push_error(failure)
	print("PASS: custom floors, puzzle movement, fixed rewards, Workshop authoring, art sharing and save reload" if failures.is_empty() else "FAIL: custom floors (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)
