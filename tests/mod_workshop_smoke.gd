extends "res://tests/user_mods_smoke.gd"

## Exercises the real title -> editor -> sandbox -> editor flow, with scratch
## mods and an in-memory save repository. Optional rendered captures:
## godot --path . -s tests/mod_workshop_smoke.gd -- --capture-dir=res://build/workshop

const SHELL := preload("res://scenes/application_shell.tscn")
var shell: Control
var view: ModWorkshopView
var capture_dir := ""

func _run() -> void:
	await process_frame
	root.size = Vector2i(700, 525)
	var runtime := root.get_node("CampaignRuntime")
	catalog = runtime.catalog
	var original_root := UserModRepository.root
	UserModRepository.root = "user://test_workshop_%d" % Time.get_ticks_usec()
	runtime.session.save_repository = MemoryRepository.new()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="): capture_dir = argument.trim_prefix("--capture-dir=")
	_check(UserModRepository.write(JSON.parse_string(FileAccess.get_file_as_string(EXAMPLE))).ok, "Install Workshop fixture")
	shell = SHELL.instantiate()
	root.add_child(shell)
	shell._build_title_screen(true)
	shell._show_save_slots()
	await process_frame
	var entry := shell.current_screen.find_child("ModWorkshopButton", true, false) as Button
	_check(entry != null, "Title save list has a Workshop entry")
	if entry == null:
		_finish(original_root)
		return
	entry.pressed.emit()
	await process_frame
	view = shell.interaction_dialog as ModWorkshopView
	_check(view != null, "Title entry opens the Workshop")
	if view == null:
		_finish(original_root)
		return
	await _capture("01_mod_list")
	view._edit("frost_pack", "Info")
	for tab in ModWorkshopView.TABS:
		view._tab = tab
		view._build_editor()
		await process_frame
		await process_frame
		_check(view._panel.size.x <= 700 and view._panel.size.y <= 525, "%s tab fits the game viewport: %s" % [tab, view._panel.size])
		_check_no_overflow(tab)
		await _capture("02_%s" % tab.to_lower())
		_check_previews(tab)
		await _capture_scrolled("02_%s" % tab.to_lower())
	_check_editor_changes()
	await process_frame
	await _check_visual_helpers()
	await _check_skill_editor()
	await _check_room_editor()
	_check(view._save_now(), "Save editor changes")
	var saved := UserModRepository.read("frost_pack")
	_check(saved.ok and saved.manifest.minion_patches.is_empty(), "Removing a patch persists to the actual source list")
	_check(saved.ok and saved.manifest.moves.size() == 2 and saved.manifest.minions.size() == 3, "Created minions and moves persist")
	view._leave_editor()
	view._edit("frost_pack", "Rooms")
	await process_frame
	_check(view._manifest.rooms.size() == 2, "Room changes survive reopening")
	var checked := UserModService.check(catalog, view._manifest)
	_check(checked.errors.is_empty(), "Workshop output builds: %s" % "; ".join(checked.errors))
	view._tab = "Test"
	view._build_editor()
	await process_frame
	var before := (runtime.session.save_repository as MemoryRepository).payloads.duplicate(true)
	_press(view, "Start test battle")
	for _frame in 300:
		await create_timer(0.05).timeout
		if shell.current_battle != null and shell.current_battle.controller != null and not shell._room_transition_active and not shell.current_battle.busy: break
	var battle: Node = shell.current_battle
	_check(battle != null and battle.controller != null, "Start a real sandbox battle from the Workshop")
	if battle == null and is_instance_valid(shell.interaction_dialog):
		for label in shell.interaction_dialog.find_children("*", "Label", true, false): print("Workshop status: ", label.text)
	if battle != null:
		_check(not battle.campaign_mode and battle._recording.is_empty(), "Sandbox has no campaign settlement or history recording")
		_check(battle.catalog.has_definition(&"frost_pack:minion/frostcub_1"), "Sandbox uses the modded catalog")
		await _capture("03_sandbox")
		var leave := battle.find_child("SandboxLeaveButton", true, false) as Button
		_check(leave != null, "Sandbox provides Back to Workshop")
		if leave != null: leave.pressed.emit()
		for _frame in 160:
			await create_timer(0.05).timeout
			if shell.current_battle == null and shell.interaction_dialog is ModWorkshopView and not shell._room_transition_active: break
		view = shell.interaction_dialog as ModWorkshopView
		_check(view != null and view._mod_id == "frost_pack" and view._tab == "Test", "Leaving the sandbox resumes the same mod and Test tab")
		_check(UserModService.active_ids().is_empty(), "Returning to editing removes sandbox mod layers")
	_check((runtime.session.save_repository as MemoryRepository).payloads == before, "Sandbox never writes a campaign save")
	_finish(original_root)

func _check_editor_changes() -> void:
	# The example's patch only specifies attack; opening it must preserve the
	# real values of all fields that the author has not changed.
	view._tab = "Changes"
	view._build_editor()
	var base := catalog.get_definition(&"base:minion/anteater_1") as MinionDefinition
	_check(int(view._manifest.minion_patches[0].stats.health) == base.base_health, "Partial stat patches show original health")
	_press(view, "Remove")
	_press(view, "Remove")
	_check(view._manifest.minion_patches.is_empty(), "Changes removal removes the minion patch")
	view._new_move()
	_choose("base:move/claw/tier1")
	view._tab = "Moves"
	view._build_editor()
	_check(view._manifest.moves.size() == 2, "Create a new move family through the picker")
	view._new_minion()
	_choose("base:minion/tiger_1")
	view._tab = "Minions"
	view._build_editor()
	_check(view._manifest.minions.size() == 3, "Create a new minion through the picker")
	view._tab = "Types"
	view._build_editor()
	_press(view, "New type")
	_check(view._manifest.types.size() == 2, "Create a custom type")
	view._set_matchup(String(view._manifest.types[-1].id), "base:type/fire", "weak")
	_press(view, "Existing matchups")
	view._tab = "Rooms"
	view._build_editor()
	view._new_room_edit()
	_choose("base:room/level_1_1_h2")
	view._new_room_edit()
	_choose("base:room/level_1_1_eggery")
	_check(view._manifest.rooms.size() == 2, "Copy doors, trainers, hatchery and service interactions into room forms")
	view._new_trainer()
	_choose("base:encounter/grass_floor1_room2_normal")
	view._tab = "Trainers"
	view._build_editor()
	view._tab = "Hatchery"
	view._build_editor()
	view._new_hatchery_rule()
	_check(view._manifest.hatchery.size() == 2, "Add a hatchery rule")
	# Undo the extra rule: the copied Floor 2 minion does not need to become a
	# permanent part of the fixture's example content.
	view._manifest.hatchery.pop_back()
	view._changed()

## Form content must never be wider than the scroll area that holds it.
func _check_no_overflow(caption: String) -> void:
	for scroll in view.find_children("*", "ScrollContainer", true, false):
		if scroll.is_queued_for_deletion() or not scroll.is_visible_in_tree(): continue
		for child in scroll.get_children():
			if child is Control and child.get_combined_minimum_size().x > scroll.size.x + 2.0:
				_check(false, "%s: content (%d wide) overflows its %d wide scroll area" % [caption, child.get_combined_minimum_size().x, scroll.size.x])
	_check(view._body.get_combined_minimum_size().x <= view._panel.size.x, "%s: the editor body is wider than its panel (%d)" % [caption, view._body.get_combined_minimum_size().x])

func _find_all(node: Node, script: Script, found: Array = []) -> Array:
	for child in node.get_children():
		if is_instance_of(child, script) and not child.is_queued_for_deletion(): found.append(child)
		_find_all(child, script, found)
	return found

func _find_one(script: Script) -> Node:
	var found := _find_all(view, script)
	return found[0] if not found.is_empty() else null

func _check_skill_editor() -> void:
	view._open_tab("Skills")
	await process_frame
	await process_frame
	var tree: Dictionary = view._manifest.talent_trees[0]
	var grid := _find_one(ModWorkshopTreeGrid) as ModWorkshopTreeGrid
	_check(grid != null and grid.nodes == tree.nodes, "Skills tab shows the tree's grid")
	if grid == null: return
	var before: int = tree.nodes.size()
	grid.cell_pressed.emit(Vector2i(2, 3))
	_choose("base:move/claw/tier1")
	var added: Dictionary = view._skills.skill_at(tree, Vector2i(2, 3))
	_check(tree.nodes.size() == before + 1 and not added.is_empty() and added.moves.size() >= 2 and added.moves.size() <= 5, "Pressing an empty box adds a skill with the move's ranks: %s" % [added])
	var scroller: Node = grid.get_parent()
	while scroller != null and not scroller is ScrollContainer: scroller = scroller.get_parent()
	grid.cell_pressed.emit(Vector2i(1, 1))
	await process_frame
	await process_frame
	if scroller != null: (scroller as ScrollContainer).scroll_vertical = int(grid.position.y + 120)
	await process_frame
	await _capture("04_skill_grid")
	grid.skill_moved.emit(Vector2i(2, 3), Vector2i(0, 2))
	_check(not view._skills.skill_at(tree, Vector2i(0, 2)).is_empty() and view._skills.skill_at(tree, Vector2i(2, 3)).is_empty(), "Dragging a skill moves it")
	grid.skill_moved.emit(Vector2i(0, 2), Vector2i(1, 2))
	_check(not view._skills.skill_at(tree, Vector2i(1, 2)).is_empty() and not view._skills.skill_at(tree, Vector2i(0, 2)).is_empty(), "Dropping a skill on another swaps them")
	for node in tree.nodes:
		if int(node.row) == 2: node["requires"] = ["0_0", "1_0", "1_1"]
	view._skills.prune(tree)
	for node in tree.nodes:
		if int(node.row) == 0: _check((node.requires as Array).is_empty(), "First-row skills never require anything")
		if int(node.row) == 2: _check(node.requires.size() == 3, "Requirements from earlier rows survive pruning")
	view._skills.move_skill(tree, Vector2i(1, 2), Vector2i(1, 0))
	for node in tree.nodes:
		if int(node.row) == 0 and int(node.column) == 1: _check((node.requires as Array).is_empty(), "A skill moved up drops requirements that are no longer earlier")
	var checked := UserModService.check(catalog, view._manifest)
	_check(checked.errors.is_empty(), "Edited skill tree builds: %s" % "; ".join(checked.errors))
	view._skills.remove_skill(tree, Vector2i(1, 0))
	for node in tree.nodes: _check("1_0" not in node.requires, "Removing a skill removes requirements on it")
	var trees_before: int = view._manifest.talent_trees.size()
	view._skills.new_blank()
	_check(view._manifest.talent_trees.size() == trees_before + 1 and view._manifest.talent_trees[-1].nodes.is_empty(), "Create a blank skill tree")
	view._skills.new_from_existing()
	_choose("base:talent_tree/tiger_speed")
	_check(view._manifest.talent_trees.size() == trees_before + 2 and view._manifest.talent_trees[-1].nodes.size() == (catalog.get_definition(&"base:talent_tree/tiger_speed") as TalentTreeDefinition).nodes.size(), "Copy a recovered tree into the mod")
	var copy: Dictionary = view._manifest.talent_trees[-1]
	view._manifest.minions[0].talent_trees = ["base:talent_tree/tiger_speed", "base:talent_tree/tiger_gaurd", copy.id]
	checked = UserModService.check(catalog, view._manifest)
	_check(checked.errors.is_empty(), "A copied tree can be given to a minion: %s" % "; ".join(checked.errors))
	view._selection["talent_trees"] = view._manifest.talent_trees.size() - 1
	view._build_editor()
	_press(view, "Remove")
	_press(view, "Remove")
	_check(view._manifest.talent_trees.size() == trees_before + 1 and copy.id not in view._manifest.minions[0].talent_trees, "Removing a tree also takes it off minions")
	# Put the fixture back the way the rest of the test expects it.
	view._manifest.minions[0].talent_trees = ["base:talent_tree/tiger_speed", "base:talent_tree/tiger_gaurd", "frost_pack:talent_tree/frost_arts"]
	view._manifest.talent_trees.pop_back()
	view._changed()

func _check_room_editor() -> void:
	view._selection.erase("room")
	view._open_tab("Rooms")
	await process_frame
	await process_frame
	var rooms: ModWorkshopRooms = view._rooms_tab
	for floor_index in 31:
		_check(rooms.unreachable(floor_index).is_empty(), "Every minimap room of floor %d is reachable in the recovered tower: %s" % [floor_index + 1, rooms.unreachable(floor_index).keys()])
	var map := _find_one(ModWorkshopFloorMap) as ModWorkshopFloorMap
	_check(map != null, "Rooms tab opens on the floor map")
	if map == null: return
	map.room_pressed.emit("base:room/level_1_1_a")
	await process_frame
	await _capture("05_floor_map")
	var rooms_before: int = view._manifest.rooms.size()
	map.room_activated.emit("base:room/level_1_1_a")
	await process_frame
	await process_frame
	var blueprint := _find_one(ModWorkshopRoomBlueprint) as ModWorkshopRoomBlueprint
	_check_no_overflow("Room blueprint")
	_check(blueprint != null and blueprint.has_door(1) and blueprint.has_door(2), "Room view draws the room's doors")
	_check(blueprint != null and blueprint.arrivals.has("entry-1"), "Room view draws arrival points")
	if blueprint == null: return
	_check(view._manifest.rooms.size() == rooms_before, "Opening a room does not edit it")
	blueprint.element_pressed.emit("door", 1)
	await process_frame
	await _capture("06_room_blueprint")
	var original: Vector2 = blueprint.arrivals["entry-1"]
	blueprint.arrivals["entry-1"] = original + Vector2(40, -30)
	blueprint.arrival_moved.emit("entry-1", original + Vector2(40, -30))
	var edited: Dictionary = {}
	for record in view._manifest.rooms:
		if String(record.target) == "base:room/level_1_1_a": edited = record
	_check(not edited.is_empty() and edited.spawns.size() == 1 and is_equal_approx(float(edited.spawns[0].x), original.x + 40.0), "Dragging an arrival point creates the room edit")
	var checked := UserModService.check(catalog, view._manifest)
	_check(checked.errors.is_empty(), "Moved arrival point builds: %s" % "; ".join(checked.errors))
	_check(view._save_now(), "Save the moved arrival point")
	UserModService.activate(catalog, [{"id": "frost_pack"}])
	var live := catalog.get_definition(&"base:room/level_1_1_a") as RoomDefinition
	_check(live != null and live.spawn_positions["entry-1"] == original + Vector2(40, -30), "The moved arrival point is used in game")
	UserModService.deactivate(catalog)
	edited["spawns"][0]["x"] = -5
	_check(not UserModService.check(catalog, view._manifest).errors.is_empty(), "An arrival point outside the room is refused")
	edited["spawns"].clear()
	await _check_room_objects(rooms, blueprint, edited)
	# Send door 1 of this room somewhere else: its old destination can no longer be reached from here.
	var door: Dictionary = {}
	for exit_edit in edited.exits:
		if int(exit_edit.transition_id) == 1: door = exit_edit
	var old_target := String(door.target_room_id)
	var old_spawn := String(door.target_spawn_id)
	door["target_room_id"] = "base:room/level_1_1_h2"
	door["target_spawn_id"] = String((catalog.get_definition(&"base:room/level_1_1_h2") as RoomDefinition).spawn_ids[0])
	_check(rooms.effective_exits(catalog.get_definition(&"base:room/level_1_1_a"))[0].edited, "A rerouted door is reported as changed")
	door["target_room_id"] = old_target
	door["target_spawn_id"] = old_spawn
	view._selection.erase("room")
	view._manifest.rooms.erase(edited)
	view._changed()

## Moving, duplicating, removing and adding room objects, undo/redo, the art
## palette, and that the game builds the edited room from a copy of its payload.
func _check_room_objects(rooms: ModWorkshopRooms, blueprint: ModWorkshopRoomBlueprint, edited: Dictionary) -> void:
	var art_key := -1
	var wall_key := -1
	for item in blueprint._objects:
		if art_key < 0 and item.kind == "art" and UserModBuilder.object_addable(String(item.sprite)) and not String(item.sprite).contains("Tile"): art_key = int(item.key)
		if wall_key < 0 and item.kind == "wall" and item.editable: wall_key = int(item.key)
	_check(art_key >= 0 and wall_key >= 0, "The blueprint offers movable art and walls")
	if art_key < 0 or wall_key < 0: return
	var art_start: Vector2 = blueprint.object_info(art_key).position
	blueprint.select_objects([art_key])
	blueprint._shift_selection(Vector2(30, 0))
	blueprint.objects_moved.emit([art_key], Vector2(30, 0), true)
	var move_edit: Dictionary = rooms._object_edit(edited, art_key, false)
	_check(not move_edit.is_empty() and is_equal_approx(float(move_edit.x), roundf(art_start.x + 30.0)), "Dragging art records its new position")
	rooms.duplicate_objects([art_key])
	_check(edited.objects.any(func(edit: Dictionary) -> bool: return edit.has("add")), "Duplicating art adds a placed copy")
	rooms.remove_objects([wall_key])
	_check(bool(rooms._object_edit(edited, wall_key, false).get("remove", false)), "Removing a wall marks it removed")
	rooms.undo()
	_check(rooms._object_edit(edited, wall_key, false).is_empty(), "Undo brings the wall back")
	rooms.redo()
	_check(bool(rooms._object_edit(edited, wall_key, false).get("remove", false)), "Redo removes it again")
	rooms._open_palette()
	await process_frame
	var tiles := view._overlay.find_children("*", "Button", true, false).size() if is_instance_valid(view._overlay) else 0
	_check(tiles > 30, "The art palette offers room art (%d buttons)" % tiles)
	await _capture("07_object_palette")
	view._close_overlay()
	rooms.add_object("collRect")
	blueprint.select_objects(view._selection.get("room_objects", []))
	await process_frame
	await _capture("08_room_objects")
	# Focus mode: the room editor takes the whole screen and its panel can be hidden.
	var rooms_tab: ModWorkshopRooms = view._rooms_tab
	_check(view.room_focus(), "Rooms open in focus mode by default")
	view._selection["room_focus"] = false
	view._build_editor()
	await process_frame
	await process_frame
	var normal_size := (_find_one(ModWorkshopRoomBlueprint) as ModWorkshopRoomBlueprint).size
	await _capture("08b_room_framed")
	view._selection["room_focus"] = true
	view._build_editor()
	await process_frame
	await process_frame
	blueprint = _find_one(ModWorkshopRoomBlueprint) as ModWorkshopRoomBlueprint
	_check(view.room_focus() and blueprint.size.y > normal_size.y + 40.0, "Focus mode gives the blueprint more height: %s -> %s" % [normal_size, blueprint.size])
	_check_no_overflow("Focused room editor")
	# The dock is anchored to the right edge: content wider than it pushes the
	# dock (and its scroll area) off screen instead of overflowing the scroll.
	var inspector_width: float = view._rooms_tab._inspector_box.get_combined_minimum_size().x
	_check(inspector_width <= ModWorkshopRooms.INSPECTOR_WIDTH, "Room side panel content fits its %d px panel (%d)" % [ModWorkshopRooms.INSPECTOR_WIDTH, inspector_width])
	await _capture("09_room_focus")
	var panel_content := rooms_tab._inspector_box.get_combined_minimum_size().x
	_check(panel_content <= rooms_tab._inspector_scroll.size.x, "The room side panel's content fits its width: %s > %s" % [panel_content, rooms_tab._inspector_scroll.size.x])
	blueprint.panel_toggle_requested.emit()
	await process_frame
	_check(is_equal_approx(blueprint.inset_right, 0.0) and not rooms_tab._inspector_scroll.get_parent().visible, "The side panel can be hidden")
	await _capture("10_room_focus_no_panel")
	blueprint.panel_toggle_requested.emit()
	view._build_editor()
	await process_frame
	blueprint = _find_one(ModWorkshopRoomBlueprint) as ModWorkshopRoomBlueprint
	var checked := UserModService.check(catalog, view._manifest)
	_check(checked.errors.is_empty(), "Edited room objects build: %s" % "; ".join(checked.errors))
	var source := catalog.get_definition(&"base:room/level_1_1_a") as RoomDefinition
	var original_count := source.payload.objects.size()
	var original_wall: String = String(source.payload.objects[wall_key].spriteName)
	_check(view._save_now(), "Save room object edits")
	UserModService.activate(catalog, [{"id": "frost_pack"}])
	var live := catalog.get_definition(&"base:room/level_1_1_a") as RoomDefinition
	_check(live.payload.objects.size() == original_count + 2, "Added objects are part of the played room")
	_check(String(live.payload.objects[wall_key].spriteName).is_empty(), "A removed wall is gone in game")
	_check(is_equal_approx(float(live.payload.objects[art_key].xPos), roundf(art_start.x + 30.0)), "Moved art is moved in game")
	UserModService.deactivate(catalog)
	var restored := catalog.get_definition(&"base:room/level_1_1_a") as RoomDefinition
	_check(restored.payload.objects.size() == original_count and String(restored.payload.objects[wall_key].spriteName) == original_wall, "Turning the mod off restores the shared room payload")
	var door_index := -1
	for index in original_count:
		if String(source.payload.objects[index].get("spriteName", "")).begins_with("roomTransitionObject"): door_index = index
	edited.objects.append({"index": door_index, "x": 10})
	_check(not UserModService.check(catalog, view._manifest).errors.is_empty(), "Moving a door marker is refused")
	edited.objects.pop_back()
	edited.objects.append({"add": "room_goldChest", "x": 10, "y": 10})
	_check(not UserModService.check(catalog, view._manifest).errors.is_empty(), "Placing a new chest is refused")
	edited.objects.clear()
	view._selection["room_objects"] = []

## Pictures on references, the in-game move card, the rich picker and the
## picture framing overlay.
func _check_visual_helpers() -> void:
	view._selection["moves"] = 0
	view._open_tab("Moves")
	await process_frame
	await process_frame
	var buttons := view.find_children("*", "Button", true, false)
	_check(buttons.any(func(button: Button) -> bool: return button.text == "* Frost" and button.icon != null), "Type references show the type badge")
	_check(buttons.any(func(button: Button) -> bool: return button.text.begins_with("Burn") and button.icon != null), "Move references show the move icon")
	var own := view.move_definition("frost_pack:move/frost_bite/tier1")
	_check(own != null and own.display_name == "Frost Bite" and String(own.type_id) == "frost_pack:type/frost", "The mod's own moves resolve for the hover card")
	var claw := catalog.get_definition(&"base:move/claw/tier1") as MoveDefinition
	var claw_cost := claw.energy_cost
	var patched: Dictionary = UserModBuilder.preview_moves({"id": "preview_check", "move_patches": [{"target": "base:move/claw/tier1", "energy_cost": 42}]}, catalog)
	_check(patched.has("base:move/claw/tier1") and patched["base:move/claw/tier1"].energy_cost == 42 and claw.energy_cost == claw_cost, "Changed moves preview as a copy without touching the game's move")
	view._open_picker("move", func(_id: String) -> void: pass)
	await process_frame
	var picker := view._picker
	var rows: Array = picker.find_children("*", "Button", true, false).filter(func(row: Button) -> bool: return row.has_meta(&"id"))
	_check(rows.size() > 100, "Move picker lists the game's moves (%d)" % rows.size())
	var claw_row: Button = null
	for row in rows: if row.get_meta(&"id") == "base:move/claw/tier1": claw_row = row
	_check(claw_row != null and claw_row.find_children("*", "TextureRect", true, false).size() >= 2, "Picker rows show the move icon and its type badge")
	picker._filter.text = "fire"
	picker._refresh()
	var shown := rows.filter(func(row: Button) -> bool: return row.visible).size()
	_check(shown > 0 and shown < rows.size(), "Picker search matches type names (%d shown)" % shown)
	await _capture("11_move_picker")
	picker._filter.text = ""
	picker._refresh()
	if claw_row != null:
		await process_frame
		await process_frame
		(claw_row.get_parent().get_parent() as ScrollContainer).ensure_control_visible(claw_row)
		await process_frame
		await process_frame
		var motion := InputEventMouseMotion.new()
		motion.position = claw_row.get_global_rect().get_center()
		motion.global_position = motion.position
		root.push_input(motion)
		# Checked at once: afterwards Godot re-syncs hover with the real OS
		# cursor, which sits outside this test window.
		_check(view._move_tip.visible and view._tip_owner == claw_row and view._move_tip.title.text == claw.display_name, "Hovering a move shows the in-game move card")
		view.show_move_tip(view, "base:move/claw/tier1")
		await process_frame
		await _capture("12_move_hover")
	picker.queue_free()
	await process_frame
	view._move_tip.visible = false
	# Framing: a 300 x 200 picture, red on the right, blue on the left.
	var picture := Image.create_empty(300, 200, false, Image.FORMAT_RGBA8)
	picture.fill(Color.RED)
	picture.fill_rect(Rect2i(0, 0, 150, 200), Color.BLUE)
	var cropper := ModWorkshopCropper.new()
	view.add_child(cropper)
	cropper.open("Frame your minion", picture, 1.0)
	var framed := cropper.result()
	_check(framed.get_size() == Vector2i(300, 300), "Fitting keeps the picture's own resolution in a square: %s" % framed.get_size())
	_check(framed.get_pixel(150, 10).a < 0.1 and framed.get_pixel(250, 150).is_equal_approx(Color.RED), "Space around a fitted picture is transparent")
	cropper._mirror = true
	_check(cropper.result().get_pixel(30, 150).is_equal_approx(Color.RED), "Mirror flips the picture")
	cropper._mirror = false
	cropper._set_zoom(1.0)
	_check(cropper.result().get_size().x <= 160 and cropper.result().get_pixel(5, 5).a > 0.9, "Zooming in crops to a smaller, fully covered square: %s" % cropper.result().get_size())
	cropper._set_zoom(-1.0)
	_check(cropper.result().get_size().x <= 512, "Zooming out stays within the 512 pixel limit")
	cropper._set_zoom(0.4)
	cropper._offset = Vector2(40, 0)
	cropper._refresh()
	cropper._update_preview()
	await process_frame
	await _capture("13_cropper")
	cropper.queue_free()
	var badge := ModWorkshopCropper.new()
	view.add_child(badge)
	badge.open("Frame your badge", picture, 78.0 / 24.0, Vector2i(78, 24))
	_check(badge.result().get_size() == Vector2i(78, 24), "Badges come out at the game's badge size")
	badge.queue_free()
	await process_frame

func _choose(id: String) -> void:
	var picker := view._picker
	var offered := is_instance_valid(picker) and picker.has_entry(id)
	_check(offered, "Picker offers %s" % id)
	if offered: picker._choose(id)

func _press(parent: Node, caption: String) -> void:
	for button in parent.find_children("*", "Button", true, false):
		if button.text == caption and not button.is_queued_for_deletion():
			button.pressed.emit()
			return
	_check(false, "Button exists: %s" % caption)

## The visual previews each tab promises are present (not just compiled).
func _check_previews(tab: String) -> void:
	var texts: Array[String] = []
	for label in view.find_children("*", "Label", true, false): texts.append((label as Label).text)
	match tab:
		"Minions":
			_check(not view.find_children("*", "ModWorkshopGrowthChart", true, false).is_empty() or _has_growth_chart(), "Minions tab shows the level preview chart")
			_check(texts.has("Evolution line"), "Minions tab shows the evolution line")
		"Moves": _check(texts.has("Power preview") and texts.any(func(text: String) -> bool: return text.begins_with("1. Damage")), "Moves tab shows damage estimates")
		"Changes": _check(texts.has("What this change does"), "Changes tab lists what a patch changes")
		"Test": _check(texts.has("Matchup") and texts.has("VS"), "Test tab shows both teams")

func _has_growth_chart() -> bool:
	for node in view.find_children("*", "Control", true, false):
		if node is ModWorkshopGrowthChart: return true
	return false

## Further captures down the editor's scroll area, for reviewing long forms.
func _capture_scrolled(caption: String) -> void:
	if capture_dir.is_empty() or DisplayServer.get_name() == "headless": return
	var scrolls := view.find_children("*", "ScrollContainer", true, false)
	if scrolls.is_empty(): return
	var scroll := scrolls[0] as ScrollContainer
	for candidate in scrolls:
		var bar := (candidate as ScrollContainer).get_v_scroll_bar()
		if bar.max_value - bar.page > scroll.get_v_scroll_bar().max_value - scroll.get_v_scroll_bar().page: scroll = candidate
	for page in range(1, 6):
		var bar := scroll.get_v_scroll_bar()
		if scroll.scroll_vertical >= int(bar.max_value - bar.page) - 1: return
		scroll.scroll_vertical += int(scroll.size.y * 0.85)
		await process_frame
		await _capture("%s_%d" % [caption, page])
	scroll.scroll_vertical = 0

func _capture(caption: String) -> void:
	if capture_dir.is_empty() or DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(capture_dir)
	root.get_texture().get_image().save_png(capture_dir.path_join(caption + ".png"))

func _finish(original_root: String) -> void:
	if is_instance_valid(shell): shell.free()
	UserModService.deactivate(catalog)
	UserModRepository._remove_tree(UserModRepository.root)
	UserModRepository.root = original_root
	for failure in failures: push_error(failure)
	print("PASS: Workshop title entry, all editor tabs, patch removal, content creation, persistence and sandbox return" if failures.is_empty() else "FAIL: Workshop (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)
