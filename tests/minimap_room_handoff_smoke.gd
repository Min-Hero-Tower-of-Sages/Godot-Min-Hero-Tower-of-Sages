extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var catalog: ContentCatalog = root.get_node("CampaignRuntime").catalog
	var campaign := catalog.get_definition(&"base:campaign/standard_tower") as CampaignDefinition
	var state := CampaignState.new()
	var map := CampaignMinimapView.new()
	root.add_child(map)
	var rooms_checked := 0
	var floors: Array = [9] if "--click-only" in OS.get_cmdline_user_args() else [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
	for floor_index in floors:
		var floor_data: Dictionary = campaign.floors[floor_index]
		var room := catalog.get_definition(StringName(floor_data.room_ids[0])) as RoomDefinition
		state.current_room_id = room.id
		state.progression["floor_index"] = floor_index
		map.configure(catalog, state, campaign, true)
		var map_root := map._map_root
		var room_tween := map._room_transition
		# Transactional state copies and settings refreshes must not restart entry.
		map.configure(catalog, state, campaign, true)
		assert(map._map_root == map_root and map._room_transition == room_tween)
		await create_timer(0.7).timeout
		for room_id in floor_data.room_ids:
			var next_room := catalog.get_definition(StringName(room_id)) as RoomDefinition
			var source_index := int(next_room.minimap_metadata.get("room_index", -1))
			var current_entry: Dictionary = {}
			for entry in map._map_piece_nodes:
				if int(entry.room_index) == source_index:
					current_entry = entry
					break
			if current_entry.is_empty():
				continue
			var old_colour: Color = current_entry.node.modulate
			state.current_room_id = next_room.id
			map.configure(catalog, state, campaign, true)
			assert(map._map_root == map_root, "Same-floor room change rebuilt the map")
			assert(current_entry.node.modulate == old_colour, "Room highlight changed before source delay")
			await create_timer(0.65).timeout
			assert(current_entry.node.modulate.is_equal_approx(Color8(51, 153, 255)))
			var expected_scale := float(current_entry.override_scale) if float(current_entry.override_scale) != -99.0 else map._base_map_scale
			assert(map._map_scaler.scale.is_equal_approx(Vector2.ONE * expected_scale))
			for entry in map._map_piece_nodes:
				assert(is_equal_approx(entry.node.modulate.a, 1.0 if entry.group_id == current_entry.group_id else 0.0))
				assert(entry.node.mouse_filter == Control.MOUSE_FILTER_IGNORE)
			rooms_checked += 1
			# One full handoff per floor, including authored group/scale rules.
			if next_room.id != room.id:
				break
	assert(rooms_checked >= floors.size())
	var requested := [0]
	map.open_requested.connect(func() -> void: requested[0] += 1)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = map._map_root.global_position + Vector2(10, 10)
	root.push_input(click)
	await process_frame
	assert(requested[0] == 1, "Embedded map artwork swallowed its open click")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = click.position
	root.push_input(release)
	var visible_piece: TextureRect
	for entry in map._map_piece_nodes:
		if entry.node.modulate.is_equal_approx(Color8(51, 153, 255)):
			visible_piece = entry.node
			break
	assert(visible_piece != null)
	var motion := InputEventMouseMotion.new()
	motion.position = visible_piece.get_global_rect().get_center()
	motion.global_position = motion.position
	root.push_input(motion, true)
	var artwork_click := InputEventMouseButton.new()
	artwork_click.button_index = MOUSE_BUTTON_LEFT
	artwork_click.position = motion.position
	artwork_click.global_position = motion.position
	artwork_click.pressed = true
	root.push_input(artwork_click, true)
	await process_frame
	assert(requested[0] == 2, "Clicking the visible current-room bitmap must open the map, not stop at its scaler")
	map.queue_free()
	await process_frame
	print("PASS: ten-floor retained minimap, delayed room/group/scale handoff, refresh stability and embedded mouse routing (%d room entries)" % rooms_checked)
	quit()
