extends SceneTree

var _checks := 0
var _failures := PackedStringArray()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var view_script: Script = load("res://src/presentation/campaign_room_view.gd")
	var room_definition: Resource = load("res://content/base/rooms/floor_1_room_a.tres")
	var view: Variant = view_script.new()
	get_root().add_child(view)
	await process_frame
	_check(view.configure(room_definition, &"start", Vector2(200.0, 400.0), {"gender": "female"}), "room configures from imported payload")
	await physics_frame
	var before: Vector2 = view.player_position()
	view._try_move_axis(Vector2(11.0, 0.0))
	_check(is_equal_approx(view.player_position().x, before.x + 11.0), "room movement preserves one source tick on an open axis")
	_check(view._height_layer_pairs.size() > 0, "source height-aware sprites create foreground layer pairs")
	var frames: SpriteFrames = view._player_sprite.sprite_frames
	_check(frames.get_frame_count(&"front") == 10, "female front walk cycle imports all ten recovered frames")
	view._set_player_pose(&"side", true, true)
	_check(view._player_sprite.animation == &"side" and view._player_sprite.flip_h, "left-facing movement uses the mirrored source side cycle")
	var source_rooms: Array[RoomDefinition] = SourceRoomGraphBuilder.load_rooms("res://content/base/campaigns/floor_1_room_graph.json")
	var entry_room: RoomDefinition
	for candidate in source_rooms:
		if candidate.id == &"base:room/level_1_1_entryhallway":
			entry_room = candidate
			break
	_check(entry_room != null and entry_room.spawn_positions.get("start", Vector2.ZERO) == Vector2(397.0, 670.0), "entry-hall start must follow entryObject0_up's source-adjusted player destination")
	if entry_room != null:
		_check(view.configure(entry_room, &"start", entry_room.spawn_positions["start"]), "entry hall configures at the source-backed initial spawn")
		await physics_frame
		for displacement in [Vector2(11.0, 0.0), Vector2(-11.0, 0.0), Vector2(0.0, 11.0), Vector2(0.0, -11.0)]:
			var spawn_before: Vector2 = view.player_position()
			view._try_move_axis(displacement)
			_check(view.player_position() == spawn_before + displacement, "the corrected entry spawn must permit movement in each open direction")
			view._player.position = spawn_before
	var probe := RoomDefinition.new()
	probe.id = &"debug:room/collision"
	probe.payload = RoomPayloadDefinition.new()
	probe.payload.dimensions = Vector2(700, 525)
	probe.payload.objects.append({"spriteName": "collRect", "xPos": 300.0, "yPos": 100.0, "xScale": 1.0, "yScale": 5.0})
	var start := Vector2(260, 210) - CustomFloorBuilder.PLAYER_FEET
	_check(view.configure(probe, &"start", start), "configure a room with a wall")
	await physics_frame
	await physics_frame
	view._try_move_axis(Vector2(60, 0))
	_check(view.player_position() == start, "A wall blocks normal movement")
	view.set_debug_exploration(true, {})
	view._try_move_axis(Vector2(60, 0))
	_check(view.player_position() == start + Vector2(60, 0) and view.safe_save_position() == start, "No Clip moves through the wall while retaining a safe save position")
	view.set_debug_exploration(false, {})
	_check(view.player_position() == start, "Disabling No Clip returns the player from inside a wall")
	view.queue_free()
	await process_frame
	if _failures.is_empty():
		print("PASS: %d room runtime checks" % _checks)
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("FAIL: %d of %d room runtime checks" % [_failures.size(), _checks])
	quit(1)

func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(description)
