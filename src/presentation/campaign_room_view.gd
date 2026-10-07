class_name CampaignRoomView
extends Node2D

## A source-driven exploration viewport. The owner should call configure(), then
## handle transition_requested / interaction_requested in its campaign flow.
signal transition_requested(exit_data: Dictionary)
signal interaction_requested(interaction: Dictionary)

const COLL_RECT_BASE_SIZE := Vector2(100.0, 50.0)
const PLAYER_COLLISION_SIZE := Vector2(45.0, 25.0)
const PLAYER_COLLISION_TOP_LEFT := Vector2(14.0, 70.0)
const TRANSITION_MARKER_BASE_SIZE := Vector2(67.0, 67.0)
const BUTTON_ZONE_BASE_SIZE := Vector2(100.0, 100.0)
const SOURCE_MOVEMENT_STEP := 11.0
const SOURCE_MOVEMENT_TICK := 1.0 / 30.0
const LOBBY_TITAN_SLOT := 1000
const STANDARD_TOWER_FLOOR_COUNT := 31 # StaticData.NUM_OF_FLOORS_IN_THE_STANDARD_TOWER
const ROOM_ART_DIRECTORY := "res://content/base/art/rooms/"
const ROOM_DEPTH_REFERENCE := preload("res://content/base/room_payloads/floor_1_room_a_payload.tres")
const ACTION_INDICATOR := preload("res://src/presentation/source_action_indicator.gd")
const REMOTE_AVATAR := preload("res://src/presentation/remote_player_avatar.gd")
const LOBBY_ROOM_ID := &"base:room/main_tower_lobby"
## Multiplayer arena: the lobby's right-hand side door (the unused Ice Floor
## entrance). The zone starts at x 2985, just past the wall line (x 2970) and
## inside the door frame (x 2966-3016), and spans the whole open stretch of
## that wall (y 1035-1368), so it fires on stepping into the doorway and never
## from the room in front of it.
const ARENA_ZONE_CENTER := Vector2(3020.0, 1201.0)
const ARENA_ZONE_HALF_EXTENTS := Vector2(35.0, 167.0)

var room: RoomDefinition
var _world: Node2D
var _art: Node2D
var _foreground_art: Node2D
var _collision: StaticBody2D
var _trigger_root: Node2D
var _player: CharacterBody2D
var _player_sprite: AnimatedSprite2D
var _camera: Camera2D
var _title: Label
var _prompt: Control
var _player_gender: StringName = &"male"
var _facing_pose: StringName = &"front"
var _facing_left := false
var _walking := false
var _remote_avatars: Dictionary = {}
var _local_name_tag: Label
var _movement_accumulator := 0.0
var _nearby_interactions: Array[Dictionary] = []
var _room_interactions: Array[Dictionary] = []
var _room_transitions: Array[Dictionary] = []
var _interaction_zones: Dictionary = {}
var _speech_bubble_positions: Dictionary = {}
var _height_layer_pairs: Array[Dictionary] = []
var _egg_sprites_by_slot: Dictionary = {}
var _sinking_egg_slots: Dictionary = {}
var _chest_sprites_by_id: Dictionary = {}
var _automatic_contact_ids: Dictionary = {}
var _transition_locked := false
var _controls_enabled := true
var _campaign_context: Dictionary = {}

## Configure from a room resource and the already-resolved source-space spawn.
## `spawn_position` is in the original Flash level's top-left-origin coordinates.
func configure(room_definition: RoomDefinition, spawn_id: StringName, spawn_position: Vector2, character: Dictionary = {}, campaign_context: Dictionary = {}) -> bool:
	if room_definition == null:
		push_error("CampaignRoomView requires a RoomDefinition")
		return false
	var payload := room_definition.ensure_payload(ROOM_DEPTH_REFERENCE.source_height_thresholds)
	if payload == null or payload.dimensions.x <= 0.0 or payload.dimensions.y <= 0.0:
		push_error("CampaignRoomView received an invalid RoomPayloadDefinition")
		return false
	_create_hud()
	_prompt.reset_contact()
	room = room_definition
	_campaign_context = campaign_context.duplicate(true)
	_clear_world()
	_nearby_interactions.clear()
	_room_interactions.clear()
	_room_transitions.clear()
	_interaction_zones.clear()
	_speech_bubble_positions.clear()
	_height_layer_pairs.clear()
	_egg_sprites_by_slot.clear()
	_sinking_egg_slots.clear()
	_chest_sprites_by_id.clear()
	_automatic_contact_ids.clear()
	_build_world(payload, character, _campaign_context)
	_build_collisions(payload)
	_build_transition_triggers(payload)
	_build_interaction_triggers(payload)
	_player.position = spawn_position
	_apply_spawn_facing(spawn_id)
	if not String(_campaign_context.get("restore_facing", "")).is_empty():
		restore_player_facing(StringName(_campaign_context.restore_facing))
	_update_height_layers()
	_refresh_nearby_interactions(false)
	_camera.limit_left = 0
	_camera.limit_top = 0
	_camera.limit_right = ceili(payload.dimensions.x)
	_camera.limit_bottom = ceili(payload.dimensions.y)
	_title.text = room_definition.display_name
	_title.visible = false
	_prompt.visible = false
	_transition_locked = false
	# The ID remains available for callers/debugging without guessing from position.
	_player.set_meta("spawn_id", spawn_id)
	set_meta("spawn_id", spawn_id)
	_player.set_meta("gender", String(character.get("gender", "male")).to_lower())
	return true

func player_position() -> Vector2:
	return _player.position if _player != null else Vector2.ZERO

func player_facing() -> StringName:
	if _facing_pose == &"back":
		return &"up"
	if _facing_pose == &"side":
		return &"left" if _facing_left else &"right"
	return &"down"

## Pose snapshot sent to other players (see NetSession.update_local_presence).
func player_presence() -> Dictionary:
	return {"pose": String(_facing_pose), "walking": _walking and _controls_enabled, "left": _facing_left}

## Re-arm exits after the shell declined a transition (multiplayer guests).
func release_transition_lock() -> void:
	_transition_locked = false

func restore_player_facing(direction: StringName) -> void:
	match direction:
		&"up": _set_player_pose(&"back", false, false)
		&"down": _set_player_pose(&"front", false, false)
		&"left": _set_player_pose(&"side", false, true)
		&"right": _set_player_pose(&"side", false, false)

func player_screen_position() -> Vector2:
	return get_viewport().get_canvas_transform() * _player.global_position if _player != null else Vector2.ZERO

func update_campaign_progression(progression: Dictionary) -> void:
	_campaign_context["progression"] = progression.duplicate(true)
	# EggeryExitBlockade stops being solid once the hatchery choice is finished.
	# Update the live room as well as newly loaded rooms; eggs keep sinking here.
	if _collision != null:
		for shape in _collision.get_children():
			if shape is CollisionShape2D and bool(shape.get_meta("eggery_exit_blockade", false)):
				shape.set_deferred("disabled", int(progression.get("eggery_picks_remaining", 0)) <= 0)

func dialogue_layout_for_zone(zone_id: int) -> Dictionary:
	var bubble: Dictionary = _speech_bubble_positions.get(zone_id, {})
	if bubble.is_empty():
		return {"position": Vector2(226.0, 420.0), "scale": Vector2.ONE}
	var world_position: Vector2 = _world.to_global(bubble.position)
	return {"position": get_viewport().get_canvas_transform() * world_position, "scale": bubble.scale}

func _ready() -> void:
	_create_hud()

func _process(_delta: float) -> void:
	_sync_remote_avatars()

func _sync_remote_avatars() -> void:
	var net: Node = get_node_or_null("/root/NetSession")
	var active: bool = net != null and net.is_active() and room != null and _world != null
	if is_instance_valid(_local_name_tag):
		_local_name_tag.visible = active
		if active:
			_local_name_tag.text = net.local_name
			_local_name_tag.add_theme_color_override("font_color", net.player_color(net.local_peer_id()))
	var seen: Dictionary = {}
	if active:
		for peer_id in net.other_player_ids():
			var presence: Dictionary = net.presence_of(peer_id)
			if presence.is_empty() or presence.room != room.id:
				continue
			seen[peer_id] = true
			var avatar = _remote_avatars.get(peer_id)
			if not is_instance_valid(avatar):
				avatar = REMOTE_AVATAR.new()
				avatar.name = "RemotePlayer_%d" % peer_id
				_world.add_child(avatar)
				# Draw beside the local player: above floor art, below foreground.
				_world.move_child(avatar, _player.get_index())
				_remote_avatars[peer_id] = avatar
			var info: Dictionary = net.players.get(peer_id, {})
			avatar.configure(peer_id, net.player_name(peer_id), StringName(info.get("gender", "male")), net.player_color(peer_id))
			avatar.apply_presence(presence)
	for peer_id in _remote_avatars.keys():
		if not seen.has(peer_id):
			if is_instance_valid(_remote_avatars[peer_id]):
				_remote_avatars[peer_id].queue_free()
			_remote_avatars.erase(peer_id)

func _physics_process(delta: float) -> void:
	if _player == null or not _controls_enabled:
		return
	_movement_accumulator += delta
	while _movement_accumulator >= SOURCE_MOVEMENT_TICK:
		_source_movement_tick()
		_movement_accumulator -= SOURCE_MOVEMENT_TICK

func _source_movement_tick() -> void:
	if _transition_locked:
		_set_player_pose(_facing_pose, false, _facing_left)
		return
	var left := _movement_pressed(&"move_left", KEY_A, KEY_LEFT)
	var right := _movement_pressed(&"move_right", KEY_D, KEY_RIGHT)
	var up := _movement_pressed(&"move_up", KEY_W, KEY_UP)
	var down := _movement_pressed(&"move_down", KEY_S, KEY_DOWN)
	# The source controller returns early when either opposing pair is held.
	if left and right:
		_set_player_pose(&"side", false, true)
		return
	if up and down:
		_set_player_pose(&"back", false, false)
		return
	var moving := left or right or up or down
	var upgrades: Dictionary = _campaign_context.get("progression", {}).get("star_upgrades", {})
	var movement_step := SOURCE_MOVEMENT_STEP * (1.0 + 0.1 * maxi(0, int(upgrades.get("movement_speed", 0))))
	# Source order is horizontal first, then vertical; diagonals are not normalized.
	if left:
		_try_move_axis(Vector2(-movement_step, 0.0))
	if right:
		_try_move_axis(Vector2(movement_step, 0.0))
	if up:
		_try_move_axis(Vector2(0.0, -movement_step))
	if down:
		_try_move_axis(Vector2(0.0, movement_step))
	# MainChar has only front/back/side walk cycles. Apply one pose after both
	# axes move; the old two-pose sequence restarted/overwrote the first cycle.
	if down:
		_set_player_pose(&"front", true, false)
	elif up:
		_set_player_pose(&"back", true, false)
	elif left:
		_set_player_pose(&"side", true, true)
	elif right:
		_set_player_pose(&"side", true, false)
	else:
		_set_player_pose(_facing_pose, false, _facing_left)
	_update_height_layers()
	_refresh_nearby_interactions()
	if moving:
		_check_transition_contacts()

func _apply_spawn_facing(spawn_id: StringName) -> void:
	var direction := String(room.spawn_directions.get(String(spawn_id), ""))
	match direction:
		"up": _set_player_pose(&"back", false, false)
		"down": _set_player_pose(&"front", false, false)
		"left": _set_player_pose(&"side", false, true)
		"right": _set_player_pose(&"side", false, false)

func _movement_pressed(action: StringName, primary_key: Key, secondary_key: Key) -> bool:
	return Input.is_action_pressed(action) or Input.is_key_pressed(primary_key) or Input.is_key_pressed(secondary_key)

func _try_move_axis(displacement: Vector2) -> void:
	if not _controls_enabled:
		return
	# The Flash controller advanced an axis, tested its wall box, then restored
	# that whole axis on overlap. A sweep preserves that rollback behavior.
	if not _player.test_move(_player.transform, displacement):
		_player.position += displacement
	else:
		for shape in _collision.get_children():
			if shape is CollisionShape2D and not shape.disabled and bool(shape.get_meta("eggery_exit_blockade", false)):
				var rectangle := shape.shape as RectangleShape2D
				# Translate the wall back instead of advancing the blocked player.
				if _source_zone_overlaps_player(shape.position - displacement, rectangle.size * 0.5, shape.rotation):
					interaction_requested.emit({"kind": &"eggery_exit_blocked"})
					return

func _unhandled_input(event: InputEvent) -> void:
	if not _controls_enabled:
		return
	# Space/Enter are the source actions; configured E remains an alternate.
	# Check the action as well as physical-key events with a zero keycode.
	if not event.is_action_pressed("interact") and not event.is_action_pressed("ui_accept") and not (event is InputEventKey and event.pressed and (event.keycode == KEY_E or event.physical_keycode == KEY_E)):
		return
	# Space can arrive before physics has delivered an area's enter/exit
	# signal. Use the current source rectangle, not a stale overlap list.
	_refresh_nearby_interactions(false)
	if _nearby_interactions.is_empty():
		return
	_nearby_interactions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _player.position.distance_squared_to(a.position) < _player.position.distance_squared_to(b.position)
	)
	interaction_requested.emit(_nearby_interactions[0].interaction.duplicate(true))
	get_viewport().set_input_as_handled()

func set_controls_enabled(enabled: bool) -> void:
	_controls_enabled = enabled
	if enabled:
		_refresh_nearby_interactions(false)
	if _prompt != null:
		_update_action_indicator()
	if not enabled:
		_movement_accumulator = 0.0
		if _player != null:
			_set_player_pose(_facing_pose, false, _facing_left)

func sink_egg(slot: int) -> Tween:
	if _sinking_egg_slots.has(slot):
		return null
	var egg_sprites: Array = _egg_sprites_by_slot.get(slot, [])
	if egg_sprites.is_empty():
		return null
	_sinking_egg_slots[slot] = true
	# A selected egg becomes unusable immediately, while its source animation
	# continues. Keep the room alive: another egg may be inspected during it.
	for index in range(_room_interactions.size() - 1, -1, -1):
		var interaction: Dictionary = _room_interactions[index]
		if StringName(interaction.get("kind", "")) == &"egg_pick" and int(interaction.get("source_zone_id", -1)) == slot:
			_room_interactions.remove_at(index)
	_refresh_nearby_interactions(false)
	var is_titan := slot == LOBBY_TITAN_SLOT
	var distance := 330.0 if is_titan else 180.0
	var duration := 10.5 if is_titan else 5.5
	_play_room_source_sound("tower_eggsGoingIntoTheGround", 0.04 if is_titan else 0.02)
	var tween := create_tween()
	tween.set_parallel(true)
	for sprite_variant in egg_sprites:
		var sprite := sprite_variant as Sprite2D
		if sprite == null or not is_instance_valid(sprite):
			continue
		# Flash moves the egg in its layer's vertical axis, not the bitmap's
		# scaled/rotated local axis. The mask must remain at its authored position.
		var mask := sprite.get_parent() as Node2D
		var local_sink := mask.transform.basis_xform_inv(Vector2(0.0, distance))
		tween.tween_property(sprite, "position", sprite.position + local_sink, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	for pair_index in range(_height_layer_pairs.size()):
		var pair: Dictionary = _height_layer_pairs[pair_index]
		if int(pair.get("egg_slot", -1)) != slot:
			continue
		var activation := float(pair.get("activation", 0.0))
		tween.tween_method(_set_height_layer_activation.bind(pair_index), activation, activation + distance, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	return tween

func play_source_healstone(interaction_id: StringName) -> void:
	var stone_position := player_position()
	for index in range(_room_interactions.size() - 1, -1, -1):
		if StringName(_room_interactions[index].get("id", "")) == interaction_id:
			stone_position = _room_interactions[index].get("_zone_center", stone_position)
			_room_interactions.remove_at(index)
	# HealStone.m_hasHealed stays true until AddSprite on the next room load.
	# Consume only after the session has saved successfully; failed saves retry.
	_refresh_nearby_interactions(false)
	var stone: Sprite2D
	var closest_distance := INF
	for child in _art.get_children():
		if child is Sprite2D and String(child.get_meta("source_sprite_name", "")) == "generalRoom_healStone":
			var candidate := child as Sprite2D
			var distance := candidate.position.distance_squared_to(stone_position)
			if distance < closest_distance:
				closest_distance = distance
				stone = candidate
	if stone != null:
		var glow := _healing_sprite(stone, "generalRoom_healStone_glow", Vector2(-45, -42))
		if glow != null:
			var glow_tween := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			glow_tween.tween_property(glow, "modulate:a", 1.0, 0.4)
			glow_tween.tween_interval(0.2)
			glow_tween.tween_property(glow, "modulate:a", 0.0, 2.0)
			glow_tween.tween_callback(glow.queue_free)
	_play_room_source_sound("tower_healstone", 0.2)
	var crosses := _healing_sprite(_player, "generalRoom_healAnimation_crosses", Vector2.ZERO)
	if crosses != null:
		create_tween().tween_property(crosses, "position:y", -100.0, 2.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		var cross_tween := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		cross_tween.tween_property(crosses, "modulate:a", 1.0, 0.4)
		cross_tween.tween_interval(0.2)
		cross_tween.tween_property(crosses, "modulate:a", 0.0, 2.0)
		cross_tween.tween_interval(0.1)
		cross_tween.tween_callback(crosses.queue_free)
	var healed := _healing_sprite(_player, "generalRoom_healAnimation_healed", Vector2(-6, -28))
	if healed != null:
		var healed_tween := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		healed_tween.tween_property(healed, "modulate:a", 1.0, 0.4)
		healed_tween.tween_interval(1.2)
		healed_tween.tween_property(healed, "modulate:a", 0.0, 1.0)
		healed_tween.tween_callback(healed.queue_free)

func _healing_sprite(parent: Node2D, symbol: String, at: Vector2) -> Sprite2D:
	var texture := SourceMenuArt.texture(symbol)
	if texture == null:
		push_warning("Missing source healing sprite: %s" % symbol)
		return null
	var sprite := Sprite2D.new()
	sprite.name = symbol
	sprite.texture = texture
	sprite.centered = false
	sprite.position = at
	sprite.modulate.a = 0.0
	if parent == _player:
		sprite.z_index = 2 # Above the player's AnimatedSprite2D, as in MainChar.
	parent.add_child(sprite)
	return sprite

func animate_source_chest_open(source_index: int, chest_kind: String) -> Tween:
	var chest_id := _chest_id(chest_kind, source_index)
	# GoldChest/GemChest mark themselves used immediately; their fade and the
	# player's pickup animation continue while exploration remains active.
	for index in range(_room_interactions.size() - 1, -1, -1):
		if String(_room_interactions[index].get("id", "")) == chest_id:
			_room_interactions.remove_at(index)
	for index in range(_nearby_interactions.size() - 1, -1, -1):
		if String(_nearby_interactions[index].interaction.get("id", "")) == chest_id:
			_nearby_interactions.remove_at(index)
	_automatic_contact_ids.erase(chest_id)
	var chest_area := _trigger_root.get_node_or_null("Interaction_%s" % chest_id) as Area2D
	if chest_area != null:
		chest_area.set_deferred("monitoring", false)
		chest_area.set_meta("claimed", true)
	var chest_sprites: Array = _chest_sprites_by_id.get(chest_id, [])
	if chest_sprites.is_empty():
		return null
	_play_room_source_sound("tower_openingChest", 0.5)
	_play_room_source_sound("tower_gemPickup" if chest_kind == "gem" else "tower_moneyPickup", 0.6 if chest_kind == "gem" else 1.0)
	var icon_path := "res://content/base/art/source_symbols/1275_Utilities.SpriteHandler_hud_inGame_gem.png" if chest_kind == "gem" else "res://content/base/art/source_symbols/1191_Utilities.SpriteHandler_hud_inGame_money.png"
	if ResourceLoader.exists(icon_path) and _player != null and _world != null:
		var icon_texture := load(icon_path) as Texture2D
		if icon_texture != null:
			var pickup := Sprite2D.new()
			pickup.name = "ChestPickup_%s" % chest_kind
			pickup.texture = icon_texture
			pickup.centered = false
			pickup.position = _player.position
			pickup.z_index = 10
			pickup.modulate.a = 0.0
			_world.add_child(pickup)
			var fade := create_tween()
			fade.tween_interval(0.2)
			fade.tween_property(pickup, "modulate:a", 1.0, 1.0)
			fade.tween_interval(0.5)
			fade.tween_property(pickup, "modulate:a", 0.0, 0.5)
			fade.finished.connect(pickup.queue_free)
			var rise := create_tween()
			rise.tween_interval(0.2)
			rise.tween_property(pickup, "position:y", pickup.position.y - 50.0, 1.0)
	var chest_tween := create_tween()
	chest_tween.set_parallel(true)
	for sprite_variant in chest_sprites:
		var sprite := sprite_variant as Sprite2D
		if sprite == null or not is_instance_valid(sprite):
			continue
		chest_tween.tween_property(sprite, "modulate:a", 0.0, 0.3)
	return chest_tween

func _set_height_layer_activation(value: float, pair_index: int) -> void:
	if pair_index < 0 or pair_index >= _height_layer_pairs.size():
		return
	var pair: Dictionary = _height_layer_pairs[pair_index]
	pair["activation"] = value
	_height_layer_pairs[pair_index] = pair

func animate_source_door_unlock(door: StringName) -> Tween:
	# Open the wall immediately after a successful save, without reloading the
	# room. VisualsForBossDoor/BossToEggeryDoorVisuals fade the locked art for 1s.
	for shape in _collision.get_children():
		if shape is CollisionShape2D and StringName(shape.get_meta("door_kind", "")) == door:
			shape.set_deferred("disabled", true)
	var interaction_kind := &"unlock_boss_door" if door == &"boss" else &"unlock_eggery_door"
	for index in range(_room_interactions.size() - 1, -1, -1):
		if StringName(_room_interactions[index].get("kind", "")) == interaction_kind:
			_room_interactions.remove_at(index)
	_refresh_nearby_interactions(false)
	_play_room_source_sound("tower_doorUnlock", 1.0)
	var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var found_overlay := false
	for sprite in _art.get_children():
		if sprite is Sprite2D and StringName(sprite.get_meta("door_kind", "")) == door:
			found_overlay = true
			tween.tween_property(sprite, "modulate:a", 0.0, 1.0)
	if not found_overlay:
		tween.tween_interval(1.0)
	return tween

func _play_room_source_sound(sound_id: String, volume: float) -> void:
	var sound_paths := {
		"tower_eggsGoingIntoTheGround": "res://content/base/audio/tower_eggsGoingIntoTheGround.mp3",
		"tower_openingChest": "res://content/base/audio/tower_openingChest.mp3",
		"tower_gemPickup": "res://content/base/audio/tower_gemPickup.mp3",
		"tower_moneyPickup": "res://content/base/audio/tower_moneyPickup.mp3",
		"tower_healstone": "res://content/base/audio/tower_healstone.mp3",
		"tower_doorUnlock": "res://content/base/audio/tower_doorUnlock.mp3",
	}
	var path := String(sound_paths.get(sound_id, ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	var stream := load(path) as AudioStream
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.name = "RoomSound_%s" % sound_id
	player.bus = &"SFX"
	player.stream = stream
	player.volume_db = linear_to_db(maxf(volume, 0.0001))
	player.finished.connect(player.queue_free)
	add_child(player)
	player.play()

func _clear_world() -> void:
	if _world != null and is_instance_valid(_world):
		remove_child(_world)
		_world.queue_free()
	_remote_avatars.clear()
	_world = Node2D.new()
	_world.name = "World"
	_world.y_sort_enabled = false
	add_child(_world)
	_art = Node2D.new()
	_art.name = "SourceArt"
	_world.add_child(_art)
	_collision = StaticBody2D.new()
	_collision.name = "RoomCollision"
	_collision.collision_layer = 1
	_collision.collision_mask = 0
	_world.add_child(_collision)
	_trigger_root = Node2D.new()
	_trigger_root.name = "RoomTriggers"
	_world.add_child(_trigger_root)
	_player = CharacterBody2D.new()
	_player.name = "Player"
	_player.collision_layer = 1
	_player.collision_mask = 1
	_world.add_child(_player)
	_player.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	var body_shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = PLAYER_COLLISION_SIZE
	body_shape.shape = rectangle
	body_shape.position = PLAYER_COLLISION_TOP_LEFT + PLAYER_COLLISION_SIZE * 0.5
	_player.add_child(body_shape)
	_player_sprite = AnimatedSprite2D.new()
	_player_sprite.name = "CharacterSprite"
	_player.add_child(_player_sprite)
	_local_name_tag = REMOTE_AVATAR.make_name_tag()
	_local_name_tag.visible = false
	_player.add_child(_local_name_tag)
	_foreground_art = Node2D.new()
	_foreground_art.name = "SourceForegroundArt"
	_foreground_art.z_index = 2
	_world.add_child(_foreground_art)
	_camera = Camera2D.new()
	_camera.name = "RoomCamera"
	_camera.position_smoothing_enabled = false
	_camera.enabled = true
	# Source anchor: x=318,y=217.5 in a 700x525 viewport.
	_camera.offset = Vector2(32.0, 45.0)
	_player.add_child(_camera)

func _build_world(payload: Variant, character: Dictionary, campaign_context: Dictionary) -> void:
	var objects: Array = payload.objects
	var height_thresholds: Dictionary = payload.source_height_thresholds
	var progression: Dictionary = campaign_context.get("progression", {})
	var current_floor_index := int(progression.get("floor_index", room.minimap_metadata.get("floor_index", 0)))
	var expert_glow_enabled := current_floor_index >= STANDARD_TOWER_FLOOR_COUNT
	var taken_egg_slots: Array = progression.get("eggery_taken_slots", [])
	var claimed_chest_slots: Array = _campaign_context.get("room_state", {}).get("claimed_chest_slots", [])
	for index in range(objects.size()):
		var attributes: Dictionary = objects[index]
		var sprite_name := String(attributes.get("spriteName", "")).strip_edges()
		if _is_semantic_marker(sprite_name) or sprite_name.is_empty():
			continue
		if sprite_name in ["generalRoom_topTorch", "generalRoom_sideTorch", "generalRoom_bottomTorch"]:
			_add_source_room_animation(sprite_name, 7 if sprite_name == "generalRoom_topTorch" else 6, attributes, index)
			continue
		if sprite_name == "eggery_fireplace":
			var fire_attributes := attributes.duplicate(true)
			fire_attributes["xPos"] = float(attributes.get("xPos", 0.0)) + 95.0
			fire_attributes["yPos"] = float(attributes.get("yPos", 0.0)) + 59.0
			_add_source_room_animation("eggery_fireplaceFire", 7, fire_attributes, index)
		if sprite_name in ["room_goldChest", "room_gemChest"]:
			var chest_kind := "gold" if sprite_name == "room_goldChest" else "gem"
			var chest_id := _chest_id(chest_kind, index)
			if chest_id in claimed_chest_slots or not CampaignChestPolicy.spawned(room.id, chest_kind, index, progression):
				continue
		if sprite_name == "room_expertTeleporter_glow" and not expert_glow_enabled:
			continue
		if sprite_name == "regularDoor" and bool(progression.get("boss_door_unlocked", false)):
			continue
		if sprite_name == "regularDoor_eggery" and bool(progression.get("eggery_door_unlocked", false)):
			continue
		var egg_slot_suffix := sprite_name.trim_prefix("eggery_egg")
		if sprite_name.begins_with("eggery_egg") and egg_slot_suffix.is_valid_int() and int(egg_slot_suffix) in taken_egg_slots:
			continue
		var texture_name := _art_texture_name(sprite_name)
		var texture_path := ROOM_ART_DIRECTORY + texture_name + ".png"
		var texture := load(texture_path) as Texture2D if ResourceLoader.exists(texture_path) else SourceMenuArt.texture(texture_name)
		if texture == null:
			continue
		var egg_slot := _egg_slot_from_sprite_name(sprite_name)
		var sprite := _make_source_art_sprite(texture, "SourceObject_%03d" % index, attributes, egg_slot >= 0, _art)
		var displayed_sprite: Sprite2D = sprite.get_child(0) as Sprite2D if egg_slot >= 0 else sprite
		if sprite_name in ["room_goldChest", "room_gemChest"]:
			var chest_kind := "gold" if sprite_name == "room_goldChest" else "gem"
			var chest_id := _chest_id(chest_kind, index)
			if not _chest_sprites_by_id.has(chest_id):
				_chest_sprites_by_id[chest_id] = []
			_chest_sprites_by_id[chest_id].append(sprite)
		if egg_slot >= 0:
			if not _egg_sprites_by_slot.has(egg_slot):
				_egg_sprites_by_slot[egg_slot] = []
			_egg_sprites_by_slot[egg_slot].append(displayed_sprite)
		if sprite_name == "generalRoom_specialDoor_open" and not bool(progression.get("boss_door_unlocked", false)):
			_add_locked_door_overlay(attributes, "generalRoom_specialDoor_locked", index)
		elif sprite_name == "generalRoom_eggeryDoor_open" and not bool(progression.get("eggery_door_unlocked", false)):
			var eggery_lock_art := "generalRoom_eggeryDoor_locked_sixKeys" if expert_glow_enabled else "generalRoom_eggeryDoor_locked"
			_add_locked_door_overlay(attributes, eggery_lock_art, index)
		var height_key := sprite_name if height_thresholds.has(sprite_name) else texture_name
		var depth_activation: Variant = height_thresholds.get(height_key)
		if sprite_name in ["room_goldChest", "room_gemChest"]:
			depth_activation = 8.0 # AddGoldChestCollObject/AddGemChestCollObject.
		# BaseTopDownLevel routes each source egg through AddEggVisualObject(..., 40, ...);
		# that explicit source threshold is missing from the extracted room table.
		if egg_slot >= 0:
			depth_activation = 40.0
		elif sprite_name == "eggery_eggPit_front":
			depth_activation = 40.0
		# Source AddExpertVisualObjectGlow creates a bottom copy plus a height copy
		# with activation height 0; visibility is enabled only on floors beyond the
		# 31-floor standard tower (ExpertRoomVisualObjectGlow.AddSprite).
		if sprite_name == "room_expertTeleporter_glow":
			depth_activation = 0.0
		# The extracted room-height table omitted the eight podium statues. Their
		# source AddObject rules use -38; the podium itself independently uses 25.
		# Reusing the podium threshold made statue art disappear behind its podium
		# whenever the player crossed the podium's depth line.
		if depth_activation == null and sprite_name in [
			"generalRoom_plantMedallionStatue",
			"generalRoom_fireMedallionStatue",
			"generalRoom_electricMedallionStatue",
			"generalRoom_undeadMedallionStatue",
			"generalRoom_plantGymStatue",
			"generalRoom_fireGymStatue",
			"generalRoom_electricGymStatue",
			"generalRoom_undeadGymStatue",
		]:
			depth_activation = -38
		# VisualsForEgg height activation is a source-coded 40 and sinks alongside
		# the egg; keep the pair even if a payload lacks an extracted threshold.
		if depth_activation != null or egg_slot >= 0:
			var overlay_attributes := attributes.duplicate(true)
			var overlay := _make_source_art_sprite(texture, "SourceForeground_%03d" % index, overlay_attributes, egg_slot >= 0, _foreground_art)
			if sprite_name in ["room_goldChest", "room_gemChest"]:
				var chest_kind := "gold" if sprite_name == "room_goldChest" else "gem"
				_chest_sprites_by_id[_chest_id(chest_kind, index)].append(overlay)
			if egg_slot >= 0:
				_egg_sprites_by_slot[egg_slot].append(overlay.get_child(0) as Sprite2D)
			_height_layer_pairs.append({
				"base": sprite,
				"foreground": overlay,
				"activation": float(depth_activation) if depth_activation != null else 0.0,
				"egg_slot": egg_slot,
			})
	# VisualsForEgg starts every remaining display underground once the tower's
	# minion-pick allowance is exhausted; already-claimed slots were filtered
	# above, while the untouched eggs still sink out of view.
	if int(progression.get("eggery_picks_remaining", 0)) <= 0:
		for slot in _egg_sprites_by_slot:
			if int(slot) == LOBBY_TITAN_SLOT:
				continue
			var egg_variants: Array = _egg_sprites_by_slot[slot]
			for sprite_variant in egg_variants:
				var egg_sprite := sprite_variant as Sprite2D
				if egg_sprite != null:
					var mask := egg_sprite.get_parent() as Node2D
					egg_sprite.position += mask.transform.basis_xform_inv(Vector2(0.0, 180.0))
	if bool(campaign_context.get("lobby_titan_owned", false)):
		for sprite in _egg_sprites_by_slot.get(LOBBY_TITAN_SLOT, []):
			(sprite as Sprite2D).position.y += 330.0

	var gender := String(character.get("gender", "male")).to_lower()
	_player_gender = StringName("female" if gender == "female" else "male")
	_player_sprite.centered = false
	_player_sprite.sprite_frames = create_player_frames(_player_gender)
	_player_sprite.z_index = 1
	_set_player_pose(&"front", false, false)

func _add_source_room_animation(symbol: String, frame_count: int, attributes: Dictionary, source_index: int) -> void:
	var frames := SpriteFrames.new()
	frames.set_animation_speed(&"default", 15.0) # FireTorch.Update: every second 30 Hz tick.
	for frame_number in range(1, frame_count + 1):
		var texture := SourceMenuArt.texture("%s%d" % [symbol, frame_number])
		if texture == null:
			push_warning("Missing source room animation frame: %s%d" % [symbol, frame_number])
			return
		frames.add_frame(&"default", texture)
	var animation := AnimatedSprite2D.new()
	animation.name = "SourceAnimation_%03d" % source_index
	animation.sprite_frames = frames
	animation.centered = false
	animation.position = _source_position(attributes)
	animation.scale = _source_scale(attributes)
	animation.rotation_degrees = _source_rotation(attributes)
	_art.add_child(animation)
	animation.play()

func _egg_slot_from_sprite_name(sprite_name: String) -> int:
	if sprite_name == "generalRoom_titanEgg":
		return LOBBY_TITAN_SLOT
	if not sprite_name.begins_with("eggery_egg"):
		return -1
	var suffix := sprite_name.trim_prefix("eggery_egg")
	return int(suffix) if suffix.is_valid_int() else -1

func _make_source_art_sprite(texture: Texture2D, node_name: String, attributes: Dictionary, use_egg_mask: bool, parent: Node2D) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.name = node_name
	sprite.set_meta("source_sprite_name", String(attributes.get("spriteName", "")))
	sprite.texture = texture
	# SpriteHandler's bitmaps begin at local (0,0), so source coordinates are
	# top-left origins. VisualsForEgg keeps this egg-shaped sprite fixed as an
	# alpha mask while the visible egg and its foreground copy sink behind it.
	sprite.centered = false
	sprite.position = _source_position(attributes)
	sprite.scale = _source_scale(attributes)
	sprite.rotation_degrees = _source_rotation(attributes)
	sprite.z_index = 0
	if use_egg_mask:
		sprite.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
		var displayed_sprite := Sprite2D.new()
		displayed_sprite.name = "VisibleEgg"
		displayed_sprite.texture = texture
		displayed_sprite.centered = false
		displayed_sprite.position = Vector2.ZERO
		sprite.add_child(displayed_sprite)
	parent.add_child(sprite)
	return sprite

func _add_locked_door_overlay(attributes: Dictionary, texture_name: String, source_index: int) -> void:
	var texture_path := ROOM_ART_DIRECTORY + texture_name + ".png"
	if not ResourceLoader.exists(texture_path):
		return
	var texture := load(texture_path) as Texture2D
	if texture == null:
		return
	var overlay := Sprite2D.new()
	overlay.name = "LockedDoorOverlay_%03d" % source_index
	overlay.set_meta("door_kind", &"eggery" if texture_name.contains("eggeryDoor") else &"boss")
	overlay.texture = texture
	overlay.centered = false
	overlay.position = _source_position(attributes)
	overlay.scale = _source_scale(attributes)
	overlay.rotation_degrees = _source_rotation(attributes)
	_art.add_child(overlay)

func _build_collisions(payload: Variant) -> void:
	var objects: Array = payload.objects
	for index in range(objects.size()):
		var attributes: Dictionary = objects[index]
		var sprite_name := String(attributes.get("spriteName", "")).strip_edges()
		var source_door_locked := (sprite_name == "regularDoor" and not _boss_door_unlocked()) or (sprite_name == "regularDoor_eggery" and not _eggery_door_unlocked())
		if sprite_name == "wallRect_courtyardExit" and bool(_campaign_context.get("progression", {}).get("grand_sage_met", false)):
			continue
		if sprite_name == "wallRect_eggeryExit" and int(_campaign_context.get("progression", {}).get("eggery_picks_remaining", 0)) <= 0:
			continue
		if sprite_name not in ["collRect", "wallRect_courtyardExit", "wallRect_eggeryExit"] and not source_door_locked:
			continue
		var body_shape := CollisionShape2D.new()
		body_shape.name = "SourceCollision_%03d" % index
		if sprite_name == "wallRect_eggeryExit":
			body_shape.set_meta("eggery_exit_blockade", true)
		if source_door_locked:
			body_shape.set_meta("door_kind", &"eggery" if sprite_name == "regularDoor_eggery" else &"boss")
		var rectangle := RectangleShape2D.new()
		var scale := _source_scale(attributes).abs()
		var base_size := Vector2(100.0, 300.0) if source_door_locked else COLL_RECT_BASE_SIZE
		rectangle.size = base_size * scale
		body_shape.shape = rectangle
		var signed_scale := _source_scale(attributes)
		var angle := _source_rotation(attributes)
		var local_center := base_size * signed_scale * 0.5
		body_shape.position = _source_position(attributes) + local_center.rotated(deg_to_rad(angle))
		body_shape.rotation_degrees = angle
		_collision.add_child(body_shape)

func _build_transition_triggers(payload: Variant) -> void:
	var marker_positions: Dictionary = {}
	var external_marker_positions: Dictionary = {}
	for attributes in payload.objects:
		var sprite_name := String(attributes.get("spriteName", "")).strip_edges()
		var normalized_name := sprite_name.trim_prefix("teleport_").trim_prefix("telport_")
		if not normalized_name.begins_with("roomTransitionObject") and normalized_name != "expert_roomTransitionObject" and normalized_name != "roomTransition_startingRoomToLobby":
			continue
		var marker_data := {"position": _source_position(attributes), "scale": _source_scale(attributes), "rotation": _source_rotation(attributes), "teleport": normalized_name != sprite_name or normalized_name == "expert_roomTransitionObject"}
		var suffix := normalized_name.trim_prefix("roomTransitionObject")
		if normalized_name == "expert_roomTransitionObject":
			marker_positions[99] = marker_data
			continue
		if suffix.is_valid_int():
			marker_positions[int(suffix)] = marker_data
		else:
			external_marker_positions[sprite_name] = marker_data
	for exit_data in room.exits:
		var transition_id := int(exit_data.get("transition_id", -1))
		# Keep gated portals alive: opening their door changes progression in
		# this room, without reconstructing the room or its authored contacts.
		if not marker_positions.has(transition_id):
			continue # Only authored exits with a corresponding source marker are active.
		var marker: Dictionary = marker_positions[transition_id]
		var live_exit := exit_data.duplicate(true)
		live_exit["source_teleport"] = bool(marker.get("teleport", false))
		var zone := _make_trigger("Transition_%d" % transition_id, marker.position, TRANSITION_MARKER_BASE_SIZE, marker.scale, marker.rotation)
		zone.body_entered.connect(_on_transition_entered.bind(live_exit))
		_room_transitions.append({"area": zone, "exit": live_exit})
	for external_transition in room.external_transitions:
		var source_sprite := String(external_transition.get("source_sprite", ""))
		if source_sprite.is_empty() or not external_marker_positions.has(source_sprite):
			continue
		var external_marker: Dictionary = external_marker_positions[source_sprite]
		var external_transition_id := int(external_transition.get("transition_id", -1))
		var zone := _make_trigger("ExternalTransition_%d" % external_transition_id, external_marker.position, TRANSITION_MARKER_BASE_SIZE, external_marker.scale, external_marker.rotation)
		zone.body_entered.connect(_on_transition_entered.bind(external_transition.duplicate(true)))
		_room_transitions.append({"area": zone, "exit": external_transition.duplicate(true)})

func _route_is_available(route: Dictionary) -> bool:
	var progression: Dictionary = _campaign_context.get("progression", {})
	var required_flag := String(route.get("requires_progression_flag", ""))
	if not required_flag.is_empty() and not bool(progression.get(required_flag, false)):
		return false
	var required_mode := String(route.get("requires_tower_mode", ""))
	var tower_mode := String(_campaign_context.get("tower_mode", "standard"))
	return required_mode.is_empty() or required_mode == tower_mode

func _build_interaction_triggers(payload: Variant) -> void:
	for attributes in payload.objects:
		var sprite_name := String(attributes.get("spriteName", "")).strip_edges()
		if sprite_name.begins_with("menus_speechBubble"):
			var bubble_suffix := sprite_name.trim_prefix("menus_speechBubble")
			var bubble_zone_id := 0 if bubble_suffix.is_empty() else int(bubble_suffix) if bubble_suffix.is_valid_int() else -1
			if bubble_zone_id >= 0:
				_speech_bubble_positions[bubble_zone_id] = {"position": _source_position(attributes), "scale": _source_scale(attributes)}
		if not sprite_name.begins_with("buttonZoneObject"):
			continue
		var suffix := sprite_name.trim_prefix("buttonZoneObject")
		var zone_id := 0 if suffix.is_empty() else int(suffix) if suffix.is_valid_int() else -1
		if zone_id >= 0:
			_interaction_zones[zone_id] = {"position": _source_position(attributes), "scale": _source_scale(attributes), "rotation": _source_rotation(attributes)}
	for interaction in room.interactions:
		if not _route_is_available(interaction):
			continue
		var kind := StringName(interaction.get("kind", ""))
		var progression: Dictionary = _campaign_context.get("progression", {})
		if kind == &"unlock_boss_door" and _boss_door_unlocked():
			continue
		if kind == &"unlock_eggery_door" and _eggery_door_unlocked():
			continue
		if kind == &"egg_pick" and (int(progression.get("eggery_picks_remaining", 0)) <= 0 or int(interaction.get("source_zone_id", -1)) in progression.get("eggery_taken_slots", [])):
			continue
		var zone_index := int(interaction.get("source_zone_id", -1))
		var zone_data: Dictionary
		if _interaction_zones.has(zone_index):
			zone_data = _interaction_zones[zone_index]
		else:
			zone_data = {"position": interaction.get("source_position", Vector2.ZERO), "scale": interaction.get("source_scale", Vector2.ONE), "rotation": 0.0}
		var zone_size := TRANSITION_MARKER_BASE_SIZE if StringName(interaction.get("kind", "")) == &"floor_picker" else BUTTON_ZONE_BASE_SIZE
		var interaction_copy: Dictionary = interaction.duplicate(true)
		if StringName(interaction_copy.get("kind", "")) == &"heal_party":
			interaction_copy["trigger_on_enter"] = true
		var local_center := Vector2(zone_size.x * zone_data.scale.x * 0.5, zone_size.y * zone_data.scale.y * 0.5)
		interaction_copy["source_position"] = zone_data.position + local_center.rotated(deg_to_rad(float(zone_data.rotation)))
		interaction_copy["_zone_center"] = interaction_copy["source_position"]
		interaction_copy["_zone_half_extents"] = zone_size * zone_data.scale.abs() * 0.5
		interaction_copy["_zone_rotation"] = float(zone_data.rotation)
		_room_interactions.append(interaction_copy)
		var area := _make_trigger("Interaction_%s" % String(interaction.get("id", "unknown")), zone_data.position, zone_size, zone_data.scale, zone_data.rotation)
		area.body_entered.connect(_on_interaction_entered.bind(interaction_copy))
		area.body_exited.connect(_on_interaction_exited.bind(interaction_copy))
	# Both chest types are source collision objects: walking into one opens it.
	for index in range(payload.objects.size()):
		var attributes: Dictionary = payload.objects[index]
		var sprite_name := String(attributes.get("spriteName", "")).strip_edges()
		if sprite_name not in ["room_goldChest", "room_gemChest"]:
			continue
		var progression: Dictionary = _campaign_context.get("progression", {})
		var chest_kind := "gold" if sprite_name == "room_goldChest" else "gem"
		var chest_id := _chest_id(chest_kind, index)
		if chest_id in _campaign_context.get("room_state", {}).get("claimed_chest_slots", []):
			continue
		if not CampaignChestPolicy.spawned(room.id, chest_kind, index, progression):
			continue
		var chest_texture := load(ROOM_ART_DIRECTORY + sprite_name + ".png") as Texture2D
		if chest_texture == null:
			continue
		var chest_size := chest_texture.get_size()
		var chest_scale := _source_scale(attributes)
		var chest_rotation := float(_source_rotation(attributes))
		var chest_center := _source_position(attributes) + (chest_size * chest_scale * 0.5).rotated(deg_to_rad(chest_rotation))
		var chest_interaction := {
			"id": StringName(chest_id),
			"kind": &"claim_room_chest" if chest_kind == "gold" else &"claim_room_gem_chest",
			"chest_kind": chest_kind,
			"source_object_index": index,
			"source_position": chest_center,
			"_zone_center": chest_center,
			"_zone_half_extents": chest_size * chest_scale.abs() * 0.5,
			"_zone_rotation": chest_rotation,
			"trigger_on_enter": true,
		}
		_room_interactions.append(chest_interaction)
		var chest_area := _make_trigger("Interaction_%s" % chest_id, _source_position(attributes), chest_size, chest_scale, chest_rotation)
		chest_area.body_entered.connect(_on_interaction_entered.bind(chest_interaction))
		chest_area.body_exited.connect(_on_interaction_exited.bind(chest_interaction))

	var net: Node = get_node_or_null("/root/NetSession")
	if room.id == LOBBY_ROOM_ID and net != null and net.is_active():
		_room_interactions.append({
			"id": &"multiplayer-arena",
			"kind": &"pvp_arena",
			"source_position": ARENA_ZONE_CENTER,
			"_zone_center": ARENA_ZONE_CENTER,
			"_zone_half_extents": ARENA_ZONE_HALF_EXTENTS,
			"_zone_rotation": 0.0,
			"trigger_on_enter": true,
		})

func _chest_id(chest_kind: String, source_index: int) -> String:
	return "chest-%s-%d" % [chest_kind, source_index]

func _make_trigger(trigger_name: String, origin: Vector2, base_size: Vector2, source_scale: Vector2, rotation_degrees: float = 0.0) -> Area2D:
	var area := Area2D.new()
	area.name = trigger_name
	area.collision_layer = 0
	area.collision_mask = 1
	area.monitoring = true
	var local_center := Vector2(base_size.x * source_scale.x * 0.5, base_size.y * source_scale.y * 0.5)
	area.position = origin + local_center.rotated(deg_to_rad(rotation_degrees))
	area.rotation_degrees = rotation_degrees
	_trigger_root.add_child(area)
	var shape_node := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = base_size * source_scale.abs()
	shape_node.shape = rectangle
	area.add_child(shape_node)
	return area

func _on_transition_entered(body: Node2D, exit_data: Dictionary) -> void:
	if body != _player or _transition_locked or not _controls_enabled or not _route_is_available(exit_data):
		return
	_transition_locked = true
	transition_requested.emit(exit_data.duplicate(true))

func _check_transition_contacts() -> void:
	# Source checks level contacts each movement tick, not only on entry. An
	# Area2D entry during dialogue/fade can be ignored while controls are locked;
	# retry the live overlap on movement so doors remain usable at close range.
	if _transition_locked or not _controls_enabled:
		return
	for transition in _room_transitions:
		if not _route_is_available(transition.exit):
			continue
		var area := transition.area as Area2D
		if not is_instance_valid(area):
			continue
		var shape := area.get_child(0) as CollisionShape2D
		var rectangle := shape.shape as RectangleShape2D
		if _source_zone_overlaps_player(area.position, rectangle.size * 0.5, area.rotation):
			_on_transition_entered(_player, transition.exit)
			return

func _source_zone_overlaps_player(center: Vector2, half_extents: Vector2, rotation: float) -> bool:
	# RectDisplayObjectCollision compares stage-space getRect bounds. Keep
	# authored rotated/mirrored zones consistent with that AABB behavior.
	var player_center := _player.position + PLAYER_COLLISION_TOP_LEFT + PLAYER_COLLISION_SIZE * 0.5
	var world_half_extents := Vector2(
		absf(cos(rotation)) * half_extents.x + absf(sin(rotation)) * half_extents.y,
		absf(sin(rotation)) * half_extents.x + absf(cos(rotation)) * half_extents.y
	)
	var distance := (player_center - center).abs()
	var contact_extent := world_half_extents + PLAYER_COLLISION_SIZE * 0.5
	return distance.x <= contact_extent.x and distance.y <= contact_extent.y

func _on_interaction_entered(body: Node2D, interaction: Dictionary) -> void:
	if body != _player or not _controls_enabled:
		return
	if bool(interaction.get("trigger_on_enter", false)):
		# Geometry-based movement contacts below own auto claims, including
		# overlaps that began while a dialogue had temporarily locked controls.
		return
	_nearby_interactions.append({"interaction": interaction, "position": interaction.get("source_position", _player.position)})
	_update_action_indicator()

func _on_interaction_exited(body: Node2D, interaction: Dictionary) -> void:
	if body != _player:
		return
	for index in range(_nearby_interactions.size() - 1, -1, -1):
		if StringName(_nearby_interactions[index].interaction.get("id", "")) == StringName(interaction.get("id", "")):
			_nearby_interactions.remove_at(index)
	_update_action_indicator()

func _refresh_nearby_interactions(allow_automatic: bool = true) -> void:
	if _player == null:
		return
	var overlapping: Array[Dictionary] = []
	var automatic_contacts: Dictionary = {}
	var automatic_pending: Array[Dictionary] = []
	for interaction in _room_interactions:
		var center: Vector2 = interaction.get("_zone_center", Vector2.ZERO)
		var half_extents: Vector2 = interaction.get("_zone_half_extents", BUTTON_ZONE_BASE_SIZE * 0.5)
		var rotation := deg_to_rad(float(interaction.get("_zone_rotation", 0.0)))
		if _source_zone_overlaps_player(center, half_extents, rotation):
			if bool(interaction.get("trigger_on_enter", false)):
				var contact_id := String(interaction.get("id", ""))
				automatic_contacts[contact_id] = true
				if not _automatic_contact_ids.has(contact_id):
					automatic_pending.append(interaction)
				continue
			overlapping.append({"interaction": interaction, "position": center})
	for contact_id in _automatic_contact_ids.keys():
		if not automatic_contacts.has(contact_id):
			_automatic_contact_ids.erase(contact_id)
	_nearby_interactions = overlapping
	_update_action_indicator()
	if allow_automatic and _controls_enabled and not automatic_pending.is_empty():
		var interaction: Dictionary = automatic_pending[0]
		_automatic_contact_ids[String(interaction.id)] = true
		interaction_requested.emit(interaction.duplicate(true))

func _create_hud() -> void:
	if _title != null and is_instance_valid(_title):
		return
	var layer := CanvasLayer.new()
	layer.name = "RoomHUD"
	add_child(layer)
	_title = Label.new()
	_title.name = "RoomTitle"
	_title.position = Vector2(14, 10)
	_title.add_theme_color_override("font_color", Color(1, 1, 1, 0.88))
	_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_title.add_theme_constant_override("shadow_offset_x", 1)
	_title.add_theme_constant_override("shadow_offset_y", 1)
	_title.visible = false
	layer.add_child(_title)
	_prompt = ACTION_INDICATOR.new()
	_prompt.name = "InteractionPrompt"
	_prompt.position = Vector2(0, 465)
	layer.add_child(_prompt)
	_prompt.configure()

func _update_action_indicator() -> void:
	if _prompt == null:
		return
	var zone := ""
	if not _nearby_interactions.is_empty():
		zone = str(_nearby_interactions[0].interaction.get("source_zone_id", _nearby_interactions[0].interaction.get("id", "")))
	_prompt.set_contact(zone, _controls_enabled and not _nearby_interactions.is_empty())

func _set_player_pose(pose: StringName, walking: bool, face_left: bool) -> void:
	_facing_pose = pose
	_facing_left = face_left
	_walking = walking
	var animation_name := pose if walking else StringName("idle_%s" % String(pose))
	if _player_sprite.sprite_frames != null and _player_sprite.sprite_frames.has_animation(animation_name):
		if _player_sprite.animation != animation_name or not _player_sprite.is_playing():
			_player_sprite.play(animation_name)
	_player_sprite.flip_h = face_left
	_player_sprite.position = player_sprite_offset(_player_gender, pose, walking, face_left)

static func player_sprite_offset(gender: StringName, pose: StringName, walking: bool, face_left: bool) -> Vector2:
	if gender == &"male":
		match pose:
			&"back": return Vector2.ZERO
			&"side": return Vector2(8.0 if face_left else 7.0, 7.0)
			_: return Vector2(3.0, 2.0)
	match pose:
		&"back": return Vector2(0.0, 7.0 if walking else 4.0)
		&"side": return Vector2(-7.0, 7.0)
		_: return Vector2(3.0, 5.0) if walking else Vector2(4.0, 8.0)

static func create_player_frames(gender: StringName) -> SpriteFrames:
	var frames := SpriteFrames.new()
	if frames.has_animation(&"default"):
		frames.remove_animation(&"default")
	for pose in [&"front", &"back", &"side"]:
		frames.add_animation(pose)
		frames.set_animation_speed(pose, 15.0)
		frames.set_animation_loop(pose, true)
		for frame_index in range(1, 11):
			var frame_path := ROOM_ART_DIRECTORY + "mainCharacter_%s_%s_%d.png" % [String(gender), String(pose), frame_index]
			if ResourceLoader.exists(frame_path):
				var frame_texture := load(frame_path) as Texture2D
				if frame_texture != null:
					frames.add_frame(pose, frame_texture)
		var idle_pose := StringName("idle_%s" % String(pose))
		frames.add_animation(idle_pose)
		frames.set_animation_loop(idle_pose, false)
		frames.set_animation_speed(idle_pose, 1.0)
		var still_path := ROOM_ART_DIRECTORY + "mainCharacter_%s_%s_still.png" % [String(gender), String(pose)]
		if ResourceLoader.exists(still_path):
			var still_texture := load(still_path) as Texture2D
			if still_texture != null:
				frames.add_frame(idle_pose, still_texture)
		if frames.get_frame_count(pose) == 0 and frames.get_frame_count(idle_pose) > 0:
			frames.add_frame(pose, frames.get_frame_texture(idle_pose, 0))
	return frames

func _update_height_layers() -> void:
	if _player == null:
		return
	var player_bottom := _player.global_position.y + PLAYER_COLLISION_TOP_LEFT.y + PLAYER_COLLISION_SIZE.y
	for pair in _height_layer_pairs:
		var base_sprite := pair.base as Sprite2D
		var foreground_sprite := pair.foreground as Sprite2D
		if base_sprite == null or foreground_sprite == null:
			continue
		# The source evaluates the top object's live sprite rectangle. Eggs wrap
		# the moving bitmap in a fixed clipping mask, so use its visible child.
		var height_reference := foreground_sprite
		if int(pair.get("egg_slot", -1)) >= 0 and foreground_sprite.get_child_count() > 0:
			var egg_child := foreground_sprite.get_child(0) as Sprite2D
			if egg_child != null:
				height_reference = egg_child
		var rect := height_reference.get_rect()
		var rect_corners := [rect.position, rect.position + Vector2(rect.size.x, 0.0), rect.position + rect.size, rect.position + Vector2(0.0, rect.size.y)]
		var source_bottom := -INF
		for corner in rect_corners:
			source_bottom = maxf(source_bottom, height_reference.to_global(corner).y)
		var actor_has_passed_overlay_threshold := player_bottom > source_bottom - float(pair.activation)
		base_sprite.visible = actor_has_passed_overlay_threshold
		foreground_sprite.visible = not actor_has_passed_overlay_threshold

func _is_semantic_marker(sprite_name: String) -> bool:
	return sprite_name == "collRect" \
		or sprite_name == "regularDoor" \
		or sprite_name == "regularDoor_eggery" \
		or sprite_name.begins_with("menus_speechBubble") \
		or sprite_name.begins_with("roomTransitionObject") \
		or sprite_name.begins_with("teleport_roomTransitionObject") \
		or sprite_name.begins_with("telport_roomTransitionObject") \
		or sprite_name == "roomTransition_startingRoomToLobby" \
		or sprite_name.begins_with("entryObject") \
		or sprite_name.begins_with("expert_entryObject") \
		or sprite_name.begins_with("expert_roomTransitionObject") \
		or sprite_name.begins_with("buttonZoneObject") \
		or sprite_name.begins_with("sound") \
		or sprite_name.to_lower().contains("music") \
		or sprite_name.begins_with("wallRect_")

func _art_texture_name(sprite_name: String) -> String:
	# Nest pieces share the egg prefix but are distinct bitmaps. Only numbered
	# egg instances map to SpriteHandler's shared egg bitmap.
	if sprite_name.begins_with("eggery_egg") and sprite_name.trim_prefix("eggery_egg").is_valid_int():
		return "eggery_egg"
	if sprite_name == "regularDoor_eggery":
		return "regularDoor"
	return sprite_name

func _boss_door_unlocked() -> bool:
	return bool(_campaign_context.get("progression", {}).get("boss_door_unlocked", false))

func _eggery_door_unlocked() -> bool:
	return bool(_campaign_context.get("progression", {}).get("eggery_door_unlocked", false))

func _source_position(attributes: Dictionary) -> Vector2:
	return Vector2(float(attributes.get("xPos", 0.0)), float(attributes.get("yPos", 0.0)))

func _source_scale(attributes: Dictionary) -> Vector2:
	return Vector2(float(attributes.get("xScale", 1.0)), float(attributes.get("yScale", 1.0)))

func _source_rotation(attributes: Dictionary) -> float:
	return float(attributes.get("rotation", 0.0))
