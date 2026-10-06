extends SceneTree

class MemorySession extends CampaignSession:
	var saves := 0
	func _save_candidate(_candidate) -> Dictionary:
		saves += 1
		return {"ok": true}

var failures: Array[String] = []
var contacts: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var room := RoomDefinition.new()
	room.id = &"base:room/contact_parity_fixture"
	room.display_name = "Contact fixture"
	room.spawn_ids = [&"start"]
	room.spawn_positions = {"start": Vector2(300, 300)}
	room.payload = RoomPayloadDefinition.new()
	room.payload.source_room_id = room.id
	room.payload.dimensions = Vector2(1000, 1000)
	room.payload.objects = [
		{"spriteName": "room_goldChest", "xPos": 500, "yPos": 500, "xScale": -1.25, "yScale": 0.75, "rotation": 90},
		{"spriteName": "room_gemChest", "xPos": 700, "yPos": 500, "xScale": 1.5, "yScale": 1.0, "rotation": 0},
		{"spriteName": "regularDoor", "xPos": 100, "yPos": 100, "xScale": 0.25, "yScale": 0.2, "rotation": 90},
		{"spriteName": "buttonZoneObject2", "xPos": 100, "yPos": 100, "xScale": 0.5, "yScale": 1.0},
		{"spriteName": "roomTransitionObject0", "xPos": 800, "yPos": 200, "xScale": 0.5, "yScale": 1.0},
	]
	room.interactions = [{"id": &"fixture-door", "kind": &"unlock_boss_door", "source_zone_id": 2}]
	room.exits = [{"transition_id": 0, "target_room_id": room.id, "target_spawn_id": &"start", "requires_progression_flag": "boss_door_unlocked"}]
	var progression := {"sage_seals": 4, "floor_index": 0}
	for seed in 1000:
		progression["chest_seed"] = seed
		if CampaignChestPolicy.spawned(room.id, "gold", 0, progression) and CampaignChestPolicy.spawned(room.id, "gem", 1, progression):
			break
	var view := CampaignRoomView.new()
	root.add_child(view)
	view.set_physics_process(false)
	view.interaction_requested.connect(func(interaction: Dictionary) -> void: contacts.append(interaction))
	_check(view.configure(room, &"start", Vector2(300, 300), {}, {"progression": progression}), "Source fixture must construct")
	view.set_physics_process(false)
	_check(view._chest_sprites_by_id.size() == 2, "Both rolled chests must render")
	var gold: Dictionary = {}
	for interaction in view._room_interactions:
		if interaction.id == &"chest-gold-0":
			gold = interaction
	_check(not gold.is_empty(), "Gold chest art must have a matching claim contact")
	if not gold.is_empty():
		_check((gold._zone_half_extents as Vector2).is_equal_approx(Vector2(89 * 1.25, 78 * 0.75) * 0.5), "Chest contact must use bitmap dimensions and source scale")
		var expected_center := Vector2(500, 500) + (Vector2(89, 78) * Vector2(-1.25, 0.75) * 0.5).rotated(PI * 0.5)
		_check((gold._zone_center as Vector2).is_equal_approx(expected_center), "Mirrored/rotated chest contact center must match the displayed bitmap")
		view._player.position = expected_center - view.PLAYER_COLLISION_TOP_LEFT - view.PLAYER_COLLISION_SIZE * 0.5
		view.set_controls_enabled(false)
		view._refresh_nearby_interactions()
		_check(contacts.is_empty(), "Locked controls must not claim a chest")
		view.set_controls_enabled(true)
		view._refresh_nearby_interactions()
		view._refresh_nearby_interactions()
		_check(contacts.size() == 1 and contacts[0].id == &"chest-gold-0", "Held chest contact must emit once even if its handler failed")
		view._player.position = Vector2(300, 300)
		view._refresh_nearby_interactions()
		view._player.position = expected_center - view.PLAYER_COLLISION_TOP_LEFT - view.PLAYER_COLLISION_SIZE * 0.5
		view._refresh_nearby_interactions()
		_check(contacts.size() == 2, "Leaving/re-entering a chest contact must permit a retry")
	var door := view._collision.get_node("SourceCollision_002") as CollisionShape2D
	_check((door.shape as RectangleShape2D).size.is_equal_approx(Vector2(25, 60)), "Locked door must use the source 100x300 marker")
	_check(door.position.is_equal_approx(Vector2(70, 112.5)), "Rotated locked-door collider must have the source center")
	contacts.clear()
	view._nearby_interactions.clear()
	view._player.position = Vector2(110, 70)
	var space := InputEventKey.new()
	space.pressed = true
	space.keycode = KEY_SPACE
	view._unhandled_input(space)
	_check(contacts.size() == 1 and contacts[0].id == &"fixture-door", "Space must find a current door contact before area signals update")
	var transitions: Array[Dictionary] = []
	view.transition_requested.connect(func(exit_data: Dictionary) -> void: transitions.append(exit_data))
	var transition_area := view._room_transitions[0].area as Area2D
	view._player.position = transition_area.position - view.PLAYER_COLLISION_TOP_LEFT - view.PLAYER_COLLISION_SIZE * 0.5
	view._check_transition_contacts()
	_check(transitions.is_empty(), "A locked door must retain its portal but not allow entry")
	view._on_transition_entered(view._player, room.exits[0])
	_check(transitions.is_empty(), "Area entry must not bypass the live door gate")
	progression["boss_door_unlocked"] = true
	view.update_campaign_progression(progression)
	view._check_transition_contacts()
	_check(transitions.size() == 1, "Close-range transition must not wait for a physics overlap refresh")
	var unlock := view.animate_source_door_unlock(&"boss")
	await process_frame
	_check(door.disabled, "Unlocking must disable the live collider without reconstructing the room")
	for interaction in view._room_interactions:
		_check(interaction.get("kind", &"") != &"unlock_boss_door", "Opened doors must not remain actionable")
	_check(view._prompt.get("_up") != null and view._prompt.get("_down") != null, "Interaction reminder must resolve both original key bitmaps")
	unlock.custom_step(1.1)
	var fixture_catalog := ContentCatalog.new()
	fixture_catalog._by_id[room.id] = room
	var session := MemorySession.new()
	session.catalog = fixture_catalog
	session.state = CampaignState.new()
	session.state.current_room_id = room.id
	session.state.progression.merge(progression, true)
	var claimed := session.claim_room_chest({"id": &"chest-gold-0", "source_object_index": 0})
	_check(bool(claimed.get("ok", false)) and session.saves == 1, "Rendered chest and claim operation must share the spawn decision")
	var duplicate := session.claim_room_chest({"id": &"chest-gold-0", "source_object_index": 0})
	_check(duplicate.get("kind", &"") == &"chest_already_claimed" and session.saves == 1, "A claimed chest must not award twice")
	view.animate_source_chest_open(0, "gold")
	await create_timer(0.35).timeout
	view.configure(room, &"start", Vector2(300, 300), {}, {"progression": {"sage_seals": 0}})
	view.set_physics_process(false)
	_check(view._chest_sprites_by_id.is_empty(), "No chest art may appear before the first Sage Seal")
	_check(not CampaignChestPolicy.spawned(room.id, "gem", 1, {"sage_seals": 3}), "Gem chests must remain absent until four seals")
	view.queue_free()
	await process_frame
	if failures.is_empty():
		print("PASS: source chest/door transforms, held-contact retry guard, Space/portal freshness, claim eligibility and seal gating")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _check(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)
