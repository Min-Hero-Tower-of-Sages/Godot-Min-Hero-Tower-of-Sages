class_name BattleRewardPresenter
extends Control

signal sequence_finished

const KEY_ICON := preload("res://content/base/art/source_symbols/490.png")
const ICONS := {
	"key": "hud_inGame_key",
	"money": "hud_inGame_money",
	"gem": "hud_inGame_gem",
	"seal": "hud_inGame_sageSeal_6",
}

var _settlement: Dictionary = {}
var _active := false
var _sequence_id := 0
var _active_tweens: Array[Tween] = []
var _presented_nodes: Array[CanvasItem] = []
var _player_screen_position := Vector2.ZERO
var _floor_index := 0
var _current_sage_seals := -1
var _audio_controller: BattleAudioController

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 1250
	visible = false

func configure(settlement: Dictionary, floor_index: int = -1, audio_controller: BattleAudioController = null, current_sage_seals: int = -1) -> void:
	_settlement = settlement.duplicate(true)
	if floor_index >= 0:
		_floor_index = floor_index
	if current_sage_seals >= 0:
		_current_sage_seals = current_sage_seals
	if audio_controller != null:
		_audio_controller = audio_controller

func start(settlement: Dictionary = {}, player_screen_position: Vector2 = Vector2.ZERO, floor_index: int = -1, audio_controller: BattleAudioController = null, current_sage_seals: int = -1) -> void:
	cancel()
	if not settlement.is_empty():
		configure(settlement, floor_index, audio_controller, current_sage_seals)
	_player_screen_position = player_screen_position
	_sequence_id += 1
	_active = true
	visible = true
	_play_sequence(_sequence_id)

func cancel() -> void:
	_sequence_id += 1
	_active = false
	for tween in _active_tweens:
		if tween != null and tween.is_running():
			tween.kill()
	_active_tweens.clear()
	for node in _presented_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_presented_nodes.clear()
	visible = false

func _play_sequence(sequence_id: int) -> void:
	var rewards: Dictionary = _settlement.get("first_clear_rewards", {})
	var items := _source_reward_items(rewards)
	var lasts := 0.0
	for item in items:
		if not _is_current(sequence_id):
			return
		var start_after := float(item.get("start_after", 0.0))
		lasts = maxf(lasts, start_after + (2.7 if String(item.kind) == "seal" else 2.2))
		_spawn_item(item, sequence_id)
	await get_tree().create_timer(lasts).timeout
	if not _is_current(sequence_id):
		return
	for node in _presented_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_presented_nodes.clear()
	_active_tweens.clear()
	_active = false
	visible = false
	sequence_finished.emit()

func _spawn_item(item: Dictionary, sequence_id: int) -> void:
	var kind := String(item.get("kind", ""))
	var texture_name := String(ICONS.get(kind, ""))
	if kind == "seal":
		texture_name = "sageSeal_%d_%d" % [int(_floor_index / 5) + 1, _floor_index % 5 + 1]
	var texture := KEY_ICON if kind == "key" else SourceMenuArt.texture(texture_name)
	if texture == null and kind == "seal":
		# MainChar computes this source family as floor/5 + 1, floor%5 + 1,
		# but the recovered atlas omits some variants (e.g. sageSeal_1_5).
		# Keep the exact request when present and use the numbered HUD seal only
		# for those missing recovered source symbols.
		var seal_index := _current_sage_seals
		if seal_index < 1:
			seal_index = int(_settlement.get("first_clear_rewards", {}).get("sage_seals", 1))
		texture = SourceMenuArt.texture("hud_inGame_sageSeal_%d" % clampi(seal_index, 1, 7))
	if texture == null:
		return
	var icon := TextureRect.new()
	icon.name = "SourceReward_%s" % kind
	icon.texture = texture
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.size = texture.get_size()
	icon.position = _player_screen_position
	icon.modulate.a = 0.0
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(icon)
	_presented_nodes.append(icon)
	var start_after := float(item.get("start_after", 0.0))
	var float_to := _player_screen_position.y - 50.0
	var intro := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_active_tweens.append(intro)
	intro.tween_property(icon, "modulate:a", 1.0, 1.0).set_delay(start_after + 0.2)
	intro.tween_property(icon, "position:y", float_to, 1.0).set_delay(start_after + 0.2)
	var outro := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_active_tweens.append(outro)
	var fade_start := start_after + (2.2 if kind == "seal" else 1.7)
	outro.tween_property(icon, "modulate:a", 0.0, 0.5).set_delay(fade_start)
	if kind == "seal":
		var background_texture := SourceMenuArt.texture("sageSeal_background")
		if background_texture != null:
			var background := TextureRect.new()
			background.name = "SourceRewardSealBackground"
			background.texture = background_texture
			background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			background.size = background_texture.get_size()
			background.position = _player_screen_position
			background.modulate.a = 0.0
			background.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(background)
			move_child(background, icon.get_index())
			_presented_nodes.append(background)
			var seal_intro := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			_active_tweens.append(seal_intro)
			seal_intro.tween_property(background, "modulate:a", 1.0, 1.0).set_delay(start_after + 0.2)
			seal_intro.tween_property(background, "position:y", float_to, 1.0).set_delay(start_after + 0.2)
			var seal_outro := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			_active_tweens.append(seal_outro)
			seal_outro.tween_property(background, "modulate:a", 0.0, 0.5).set_delay(fade_start)
	if _audio_controller != null:
		_play_source_sound(kind, start_after, sequence_id)

func _source_reward_items(rewards: Dictionary) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	if rewards.is_empty():
		return items
	var has_key := int(rewards.get("floor_keys", 0)) > 0 or int(rewards.get("eggery_keys", 0)) > 0
	var has_money := float(rewards.get("money", 0.0)) > 0.0
	# The upgrade adds money on every first clear, but OpenVictoryMenus sets
	# MainChar.m_hasEarnedMoney only for normal trainers. Otherwise an upgrade
	# incorrectly replaces the hard/expert gem or boss seal with a coin pickup.
	if rewards.has("source_trainer_type"):
		has_money = has_money and String(rewards.source_trainer_type) == "TrainerType.NORMAL_TRAINER"
	var gems: Array = rewards.get("gems", [])
	# A completed Gym seal is assembled before dialogue, not floated as a
	# regular boss's piece. Keep piece feedback separate from total owned seals.
	var seals := int(rewards.get("sage_seal_pieces", 0))
	# These are the ordered branches in MainChar.FinishActivate. Their pickups
	# overlap: the second icon starts 0.7s later (or 1.9s for seal then key).
	if has_key and has_money:
		items.append({"kind": "key", "start_after": 0.0})
		items.append({"kind": "money", "start_after": 0.7})
	elif has_key and seals > 0:
		if _floor_index < 31:
			items.append({"kind": "seal", "start_after": 0.0})
		items.append({"kind": "key", "start_after": 1.9})
	elif has_key and not gems.is_empty():
		items.append({"kind": "key", "start_after": 0.0})
		items.append({"kind": "gem", "start_after": 0.7})
	elif seals > 0 and not gems.is_empty():
		items.append({"kind": "seal", "start_after": 0.0})
		items.append({"kind": "gem", "start_after": 0.7})
	elif has_key:
		items.append({"kind": "key", "start_after": 0.0})
	elif has_money:
		items.append({"kind": "money", "start_after": 0.0})
	elif not gems.is_empty():
		items.append({"kind": "gem", "start_after": 0.0})
	elif seals > 0 and _floor_index < 31:
		items.append({"kind": "seal", "start_after": 0.0})
	return items

func _play_source_sound(kind: String, delay: float, sequence_id: int) -> void:
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	if not _is_current(sequence_id) or _audio_controller == null:
		return
	match kind:
		"key": _audio_controller.play_sound("tower_keyPickup", 0.5)
		"money": _audio_controller.play_sound("tower_moneyPickup", 1.0)
		"gem", "seal": _audio_controller.play_sound("tower_gemPickup", 0.6)

func _is_current(sequence_id: int) -> bool:
	return _active and sequence_id == _sequence_id
