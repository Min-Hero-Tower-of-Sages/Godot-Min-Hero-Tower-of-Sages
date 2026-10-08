class_name BattleCombatantView
extends Node2D

const HEALTH_BACKGROUND := preload("res://content/base/art/battle/minions/battleScreenMenus_healthFillBar_background.png")
const HEALTH_FILL := preload("res://content/base/art/battle/battleScreenMenus_fillBar_healthFill.png")
const SHIELD_FILL := preload("res://content/base/art/battle/battleScreenMenus_fillBar_shieldFill.png")
const PLAYER_BADGE := preload("res://content/base/art/battle/battleScreenMenus_turnIndicator_player.png")
const ENEMY_BADGE := preload("res://content/base/art/battle/battleScreenMenus_turnIndicator_enemy.png")
const SELECTED_INDICATOR := preload("res://content/base/art/battle/battleScreenSelectedIndicator.png")
const BURBIN_FONT := preload("res://content/base/fonts/BurbinCasual.ttf")
const CONDITION_TINT_SHADER := preload("res://src/presentation/source_condition_tint.gdshader")
const SUPER_EFFECTIVE_POPUP := preload("res://content/base/art/battle/battlePopup_superEffective.png")
const NOT_EFFECTIVE_POPUP := preload("res://content/base/art/battle/battlePopup_notEffective.png")
const CRITICAL_POPUP := preload("res://content/base/art/battle/battlePopup_critical.png")
const REDIRECTED_POPUP := preload("res://content/base/art/battle/battlePopup_redirected.png")
const REFLECTED_DAMAGE_POPUP := preload("res://content/base/art/battle/visualMove_reflectedDamage.png")
const FROZEN_BADGE := preload("res://content/base/art/battle/visualMove_frozen.png")
const STUNNED_BADGE := preload("res://content/base/art/battle/visualMove_stunned.png")
const EXHAUSTED_BADGE := preload("res://content/base/art/battle/visualMove_exhausted.png")
const CHARGING_BADGE := preload("res://content/base/art/battle/visualMove_charging.png")
const STAT_INCREASE_BADGE := preload("res://content/base/art/battle/visualMove_statIncrease.png")
const STAT_DECREASE_BADGE := preload("res://content/base/art/battle/visualMove_statDecrease.png")
const BATTLE_MOD_SHIELD_TEXTURE := preload("res://content/base/art/battle/modStone_shield.png")
const GROUND_CRACK_TEXTURES: Array[Texture2D] = [
	preload("res://content/base/art/battle/groundCrack_1.png"),
	preload("res://content/base/art/battle/groundCrack_2.png"),
	preload("res://content/base/art/battle/groundCrack_3.png"),
	preload("res://content/base/art/battle/groundCrack_4.png"),
]
const GROUND_CRACK_X_OFFSETS: Array[float] = [50.0, 60.0, 66.0, 53.0]
const GROUND_CRACK_Y_OFFSETS: Array[float] = [30.0, 45.0, 44.0, 38.0]
const TELEPORT_PIECE_TEXTURES: Array[Texture2D] = [
	preload("res://content/base/art/battle/battleScreenIntro_teleportPiece1.png"),
	preload("res://content/base/art/battle/battleScreenIntro_teleportPiece2.png"),
	preload("res://content/base/art/battle/battleScreenIntro_teleportPiece3.png"),
	preload("res://content/base/art/battle/battleScreenIntro_teleportPiece4.png"),
	preload("res://content/base/art/battle/battleScreenIntro_teleportPiece5.png"),
	preload("res://content/base/art/battle/battleScreenIntro_teleportPiece6.png"),
	preload("res://content/base/art/battle/battleScreenIntro_teleportPiece7.png"),
]

const PLAYER_ANCHORS: Array[Vector2] = [
	Vector2(289, 294), Vector2(209, 381), Vector2(287, 497), Vector2(99, 314), Vector2(115, 473),
]
const ENEMY_ANCHORS: Array[Vector2] = [
	Vector2(424, 294), Vector2(520, 381), Vector2(450, 497), Vector2(614, 312), Vector2(618, 468),
]
## Multiplayer double battle: ten minions per side. Slots 0-4 form the front
## column (the starting player, or the original enemies), slots 5-9 the back
## column (the partner, or the duplicated enemies). Enemy anchors mirror these.
const DOUBLE_PLAYER_ANCHORS: Array[Vector2] = [
	Vector2(300, 262), Vector2(276, 322), Vector2(300, 382), Vector2(276, 442), Vector2(300, 502),
	Vector2(170, 247), Vector2(146, 307), Vector2(170, 367), Vector2(146, 427), Vector2(170, 487),
]
const DOUBLE_MIRROR_X := 713.0
const DOUBLE_SCALE := 0.68

var instance_id: StringName
var team: int
var slot_index: int
## Where this minion stands (and returns to after a lunge).
var home_anchor := Vector2.ZERO
var minion_definition: MinionDefinition
var minion_sprite: Sprite2D
var battle_mod_shield_sprite: Sprite2D
var minion_image: Image
var health_background_sprite: Sprite2D
var health_bar: TextureProgressBar
var health_fill_clip: Control
var health_fill_visual: TextureRect
var shield_bar: TextureProgressBar
var shield_fill_clip: Control
var shield_fill_visual: TextureRect
var turn_badge: TextureRect
var status_label: Label
var move_order_label: Label
var level_label: Label
var selected_indicator: Sprite2D
var teleport_animation_pieces: Array[Sprite2D] = []
var ground_damage_sprites: Dictionary = {}
var _ground_damage_tweens: Dictionary = {}
var buff_icon_nodes: Array[TextureRect] = []
var buff_icon_move_ids: Array[StringName] = []
var buff_tooltip: PanelContainer
var buff_tooltip_label: Label
var targetable := false
var target_selected := false
var state_cache: Dictionary = {}
var _health_tween: Tween
var _shield_tween: Tween
var _death_tween: Tween
var _battle_mod_shield_tween: Tween
var _teleport_tweens: Array[Tween] = []
var _health_target := 0.0
var _health_visual_target_x := 0.0
var _shield_target := 0.0
var _shield_visual_target_x := 0.0
var _death_started := false
var _move_lunge_tween: Tween
var _condition_tint_material: ShaderMaterial
var _condition_tint_tween: Tween

func play_source_move_lunge() -> void:
	if _move_lunge_tween != null and _move_lunge_tween.is_running():
		_move_lunge_tween.kill()
	var anchor_x := home_anchor.x
	position.x = anchor_x
	_move_lunge_tween = create_tween()
	_move_lunge_tween.tween_property(self, "position:x", anchor_x + (20.0 if team == 0 else -20.0), 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_move_lunge_tween.tween_property(self, "position:x", anchor_x, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

static func legacy_anchor(team_index: int, slot: int) -> Vector2:
	if slot < 0 or slot >= 5:
		return Vector2.ZERO
	return PLAYER_ANCHORS[slot] if team_index == 0 else ENEMY_ANCHORS[slot]

static func double_anchor(team_index: int, slot: int) -> Vector2:
	if slot < 0 or slot >= DOUBLE_PLAYER_ANCHORS.size():
		return Vector2.ZERO
	var anchor := DOUBLE_PLAYER_ANCHORS[slot]
	return anchor if team_index == 0 else Vector2(DOUBLE_MIRROR_X - anchor.x, anchor.y)

func setup(combatant_data: Dictionary, definition: MinionDefinition, sprite_texture: Texture2D) -> void:
	instance_id = StringName(combatant_data.get("instance_id", ""))
	team = int(combatant_data.get("team", 0))
	slot_index = int(combatant_data.get("slot_index", 0))
	minion_definition = definition
	if bool(combatant_data.get("double_layout", false)):
		home_anchor = double_anchor(team, slot_index)
		scale = Vector2.ONE * DOUBLE_SCALE
	else:
		home_anchor = legacy_anchor(team, slot_index)
	position = home_anchor
	z_index = int(position.y)

	minion_sprite = Sprite2D.new()
	_condition_tint_material = ShaderMaterial.new()
	_condition_tint_material.shader = CONDITION_TINT_SHADER
	_condition_tint_material.set_shader_parameter("rgb_multiplier", Vector3.ONE)
	_condition_tint_material.set_shader_parameter("rgb_offset", Vector3.ZERO)
	minion_sprite.material = _condition_tint_material
	minion_sprite.texture = sprite_texture
	minion_image = sprite_texture.get_image()
	minion_sprite.flip_h = team == 0
	minion_sprite.position = Vector2(0.0, -sprite_texture.get_height() * 0.5)
	add_child(minion_sprite)
	battle_mod_shield_sprite = Sprite2D.new()
	battle_mod_shield_sprite.texture = BATTLE_MOD_SHIELD_TEXTURE
	battle_mod_shield_sprite.centered = false
	battle_mod_shield_sprite.position = Vector2(-float(BATTLE_MOD_SHIELD_TEXTURE.get_height()) * 0.5, -float(BATTLE_MOD_SHIELD_TEXTURE.get_height()) + 10.0)
	battle_mod_shield_sprite.z_index = 2
	battle_mod_shield_sprite.visible = false
	add_child(battle_mod_shield_sprite)
	_create_teleport_pieces()
	var sprite_height := float(sprite_texture.get_height())
	health_background_sprite = Sprite2D.new()
	health_background_sprite.texture = HEALTH_BACKGROUND
	health_background_sprite.centered = false
	health_background_sprite.position = Vector2(-HEALTH_BACKGROUND.get_width() * 0.5, -sprite_height - 30.0)
	add_child(health_background_sprite)

	health_bar = TextureProgressBar.new()
	health_bar.texture_progress = HEALTH_FILL
	health_bar.min_value = 0.0
	health_bar.max_value = maxf(1.0, float(combatant_data.get("max_health", 1)))
	health_bar.value = float(combatant_data.get("health", health_bar.max_value))
	health_bar.fill_mode = TextureProgressBar.FILL_LEFT_TO_RIGHT
	health_bar.size = Vector2(HEALTH_FILL.get_width(), HEALTH_FILL.get_height())
	health_bar.position = Vector2(-HEALTH_BACKGROUND.get_width() * 0.5 + 4.0, -sprite_height - 27.0)
	health_bar.add_theme_stylebox_override("background", StyleBoxEmpty.new())
	health_bar.add_theme_stylebox_override("fill", StyleBoxEmpty.new())
	# Retain Range as the animated value, while drawing the source's full fill
	# sliding behind a fixed-width mask. TextureProgressBar clips the fill from
	# the left and makes small-HP changes appear to jump by large pixel steps.
	health_bar.modulate.a = 0.0
	# Invisible value holder: it must not take the mouse (and its arrow cursor)
	# from the battle, which handles health bar clicks itself.
	health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(health_bar)
	health_fill_clip = Control.new()
	health_fill_clip.name = "HealthFillClip"
	health_fill_clip.position = health_bar.position
	health_fill_clip.size = HEALTH_FILL.get_size()
	health_fill_clip.clip_contents = true
	health_fill_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(health_fill_clip)
	health_fill_visual = TextureRect.new()
	health_fill_visual.texture = HEALTH_FILL
	health_fill_visual.size = HEALTH_FILL.get_size()
	health_fill_visual.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	health_fill_visual.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	health_fill_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	health_fill_clip.add_child(health_fill_visual)
	_update_health_fill_visual(health_bar.value)

	# The reference overlays shield and health at the same coordinates.
	shield_bar = TextureProgressBar.new()
	shield_bar.texture_progress = SHIELD_FILL
	shield_bar.min_value = 0.0
	shield_bar.max_value = maxf(1.0, float(combatant_data.get("max_shield", 0)))
	shield_bar.value = float(combatant_data.get("shield", 0))
	shield_bar.fill_mode = TextureProgressBar.FILL_LEFT_TO_RIGHT
	shield_bar.size = Vector2(SHIELD_FILL.get_width(), SHIELD_FILL.get_height())
	shield_bar.position = health_bar.position
	shield_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shield_bar.modulate.a = 0.0
	add_child(shield_bar)
	shield_fill_clip = Control.new()
	shield_fill_clip.name = "ShieldFillClip"
	shield_fill_clip.position = shield_bar.position
	shield_fill_clip.size = SHIELD_FILL.get_size()
	shield_fill_clip.clip_contents = true
	shield_fill_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shield_fill_clip)
	shield_fill_visual = TextureRect.new()
	shield_fill_visual.texture = SHIELD_FILL
	shield_fill_visual.size = SHIELD_FILL.get_size()
	shield_fill_visual.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shield_fill_visual.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	shield_fill_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shield_fill_clip.add_child(shield_fill_visual)

	turn_badge = TextureRect.new()
	turn_badge.texture = PLAYER_BADGE if team == 0 else ENEMY_BADGE
	turn_badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	turn_badge.position = Vector2(-58.0, -sprite_height - 38.0)
	turn_badge.size = turn_badge.texture.get_size()
	turn_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(turn_badge)

	move_order_label = Label.new()
	move_order_label.text = ""
	move_order_label.position = turn_badge.position
	move_order_label.size = turn_badge.size
	move_order_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	move_order_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	move_order_label.add_theme_font_size_override("font_size", 12)
	move_order_label.add_theme_color_override("font_color", Color(0.12, 0.12, 0.16, 1.0))
	add_child(move_order_label)

	level_label = Label.new()
	level_label.text = "lv. %d" % int(combatant_data.get("level", 1))
	level_label.position = Vector2(-21.0, -sprite_height - 17.0)
	level_label.size = Vector2(45.0, 16.0)
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_label.add_theme_font_override("font", BURBIN_FONT)
	level_label.add_theme_font_size_override("font_size", 9)
	level_label.add_theme_color_override("font_color", Color8(235, 234, 235))
	level_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	level_label.add_theme_constant_override("shadow_offset_x", 1)
	level_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(level_label)

	selected_indicator = Sprite2D.new()
	selected_indicator.texture = SELECTED_INDICATOR
	selected_indicator.centered = false
	selected_indicator.position = Vector2(-28.0, -sprite_height - 60.0)
	selected_indicator.visible = false
	add_child(selected_indicator)

	status_label = Label.new()
	status_label.position = Vector2(-45.0, 2.0)
	status_label.size = Vector2(90.0, 14.0)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 8)
	status_label.add_theme_color_override("font_color", Color(1.0, 0.87, 0.55, 1.0))
	status_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	status_label.add_theme_constant_override("shadow_offset_x", 1)
	status_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(status_label)
	_create_buff_tooltip()
	update_from_state(combatant_data)
	if not _death_started:
		_play_teleport_in()

func _create_teleport_pieces() -> void:
	for texture in TELEPORT_PIECE_TEXTURES:
		var piece := Sprite2D.new()
		piece.texture = texture
		piece.centered = false
		piece.position = Vector2(-float(texture.get_width()) * 0.5, -float(texture.get_height()) * 1.4)
		piece.modulate.a = 0.0
		piece.visible = false
		add_child(piece)
		teleport_animation_pieces.append(piece)

func bring_in_ground_damage(crack_index: int) -> void:
	if crack_index < 0 or crack_index >= GROUND_CRACK_TEXTURES.size():
		return
	var crack := ground_damage_sprites.get(crack_index) as Sprite2D
	if crack == null:
		crack = Sprite2D.new()
		crack.texture = GROUND_CRACK_TEXTURES[crack_index]
		crack.centered = false
		crack.position = Vector2(
			GROUND_CRACK_X_OFFSETS[crack_index] * (1.0 if team == 0 else -1.0),
			-GROUND_CRACK_Y_OFFSETS[crack_index]
		)
		crack.scale.x = -1.0 if team == 0 else 1.0
		crack.z_index = -1
		crack.modulate.a = 0.0
		add_child(crack)
		ground_damage_sprites[crack_index] = crack
	var current_tween := _ground_damage_tweens.get(crack_index) as Tween
	if (current_tween != null and current_tween.is_running()) or crack.modulate.a >= 1.0:
		return
	var tween := create_tween()
	tween.tween_property(crack, "modulate:a", 1.0, 0.7).set_delay(0.15)
	_ground_damage_tweens[crack_index] = tween

func _create_buff_tooltip() -> void:
	buff_tooltip = PanelContainer.new()
	buff_tooltip.visible = false
	buff_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	buff_tooltip.z_index = 1100
	var tooltip_style := StyleBoxFlat.new()
	tooltip_style.bg_color = Color8(94, 100, 116, 242)
	tooltip_style.border_color = Color8(229, 230, 232, 217)
	tooltip_style.set_border_width_all(1)
	tooltip_style.set_corner_radius_all(3)
	tooltip_style.content_margin_left = 5.0
	tooltip_style.content_margin_right = 5.0
	tooltip_style.content_margin_top = 2.0
	tooltip_style.content_margin_bottom = 2.0
	buff_tooltip.add_theme_stylebox_override("panel", tooltip_style)
	buff_tooltip_label = Label.new()
	buff_tooltip_label.add_theme_font_override("font", BURBIN_FONT)
	buff_tooltip_label.add_theme_font_size_override("font_size", 12)
	buff_tooltip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	buff_tooltip.add_child(buff_tooltip_label)
	add_child(buff_tooltip)

func set_buff_icons(moves: Array) -> void:
	var next_moves: Array[MoveDefinition] = []
	var next_ids: Array[StringName] = []
	for raw_move in moves:
		if not raw_move is MoveDefinition:
			continue
		var move := raw_move as MoveDefinition
		var icon_name := String(move.buff_icon_name)
		if icon_name.is_empty():
			continue
		var icon_path := "res://content/base/art/battle/%s.png" % icon_name
		if not ResourceLoader.exists(icon_path):
			continue
		var icon_texture := load(icon_path) as Texture2D
		if icon_texture == null:
			continue
		next_moves.append(move)
		next_ids.append(move.id)
	if next_ids == buff_icon_move_ids:
		return
	for icon in buff_icon_nodes:
		remove_child(icon)
		icon.queue_free()
	buff_icon_nodes.clear()
	buff_icon_move_ids = next_ids
	var sprite_size := minion_sprite.texture.get_size() if minion_sprite != null and minion_sprite.texture != null else Vector2.ZERO
	for index in next_moves.size():
		var move := next_moves[index]
		var icon_path := "res://content/base/art/battle/%s.png" % String(move.buff_icon_name)
		var icon_texture := load(icon_path) as Texture2D
		if icon_texture == null:
			continue
		var icon := TextureRect.new()
		icon.texture = icon_texture
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.size = icon_texture.get_size() * 0.5
		icon.mouse_filter = Control.MOUSE_FILTER_PASS
		icon.position = Vector2(
			-sprite_size.x * 0.5 - icon.size.x if team == 0 else sprite_size.x * 0.5,
			-sprite_size.y + index * icon.size.y
		)
		var tooltip_data := _buff_tooltip_data(move)
		icon.mouse_entered.connect(_show_buff_tooltip.bind(icon, String(tooltip_data.text), tooltip_data.color))
		icon.mouse_exited.connect(_hide_buff_tooltip)
		add_child(icon)
		buff_icon_nodes.append(icon)

func _process(_delta: float) -> void:
	if buff_tooltip != null and buff_tooltip.visible:
		var mouse_position := get_local_mouse_position()
		buff_tooltip.position = mouse_position + Vector2(-buff_tooltip.size.x * 0.5 + 5.0, -24.0)

func _show_buff_tooltip(_icon: TextureRect, text: String, color: Color) -> void:
	if buff_tooltip == null or buff_tooltip_label == null:
		return
	buff_tooltip_label.text = text
	buff_tooltip_label.add_theme_color_override("font_color", color)
	buff_tooltip.size = buff_tooltip.get_combined_minimum_size()
	var mouse_position := get_local_mouse_position()
	buff_tooltip.position = mouse_position + Vector2(-buff_tooltip.size.x * 0.5 + 5.0, -24.0)
	buff_tooltip.visible = true
	buff_tooltip.move_to_front()
	set_process(true)

func _hide_buff_tooltip() -> void:
	if buff_tooltip != null:
		buff_tooltip.visible = false
	set_process(false)

func _buff_tooltip_data(move: MoveDefinition) -> Dictionary:
	var periodic_damage := _first_buff_effect(move, EffectDefinition.Kind.PERIODIC_DAMAGE)
	if periodic_damage != null:
		return {"text": _buff_amount_range(periodic_damage) + " damage", "color": Color8(255, 113, 51)}
	var periodic_heal := _first_buff_effect(move, EffectDefinition.Kind.PERIODIC_HEAL)
	if periodic_heal != null:
		return {"text": _buff_amount_range(periodic_heal) + " healing", "color": Color8(130, 222, 118)}
	var stat_effect := _first_buff_effect(move, EffectDefinition.Kind.STAT_PERCENT)
	if (move.is_passive or move.is_global_passive) and stat_effect != null:
		var stat_name := String(stat_effect.stat_type_id).get_slice("/", 1)
		return {"text": "+%d%% %s" % [stat_effect.amount, stat_name], "color": Color8(255, 245, 104)}
	var armor_effect := _first_buff_effect(move, EffectDefinition.Kind.ARMOR)
	if armor_effect != null:
		return {"text": "%+d%% armor" % armor_effect.amount, "color": Color8(255, 245, 104) if armor_effect.amount >= 0 else Color8(229, 125, 255)}
	var critical_effect := _first_buff_effect(move, EffectDefinition.Kind.CRITICAL_CHANCE)
	if critical_effect != null:
		return {"text": "+%d%% crit" % critical_effect.amount, "color": Color8(255, 245, 104)}
	var reflect_effect := _first_buff_effect(move, EffectDefinition.Kind.REFLECT)
	if reflect_effect != null:
		return {"text": "%+d%% reflect" % reflect_effect.amount, "color": Color8(255, 245, 104)}
	var redirect_effect := _first_buff_effect(move, EffectDefinition.Kind.REDIRECT_DAMAGE)
	if redirect_effect != null:
		return {"text": "+%d%% redirect" % redirect_effect.amount, "color": Color8(255, 235, 168)}
	return {"text": move.display_name, "color": Color8(235, 234, 235)}

func _first_buff_effect(move: MoveDefinition, kind: EffectDefinition.Kind) -> EffectDefinition:
	for effect in move.effects:
		if effect != null and effect.kind == kind:
			return effect
	return null

func _buff_amount_range(effect: EffectDefinition) -> String:
	if effect.random_bonus > 0:
		return "%d-%d" % [effect.amount, effect.amount + effect.random_bonus]
	return str(effect.amount)

func update_from_state(state: Dictionary, animate_bars: bool = false) -> void:
	if health_bar == null:
		return
	var is_initial_state := state_cache.is_empty()
	var had_battle_mod_shield := bool(state_cache.get("battle_mod_shield_active", false))
	state_cache = state.duplicate(true)
	var has_battle_mod_shield := bool(state.get("battle_mod_shield_active", false))
	if battle_mod_shield_sprite != null and (is_initial_state or had_battle_mod_shield != has_battle_mod_shield):
		_set_battle_mod_shield(has_battle_mod_shield, not is_initial_state)
	health_bar.max_value = maxf(1.0, float(state.get("max_health", 1)))
	var new_health := float(state.get("health", health_bar.max_value))
	var new_health_fill_x := _health_fill_x_for(new_health)
	if animate_bars or (_health_tween != null and _health_tween.is_running()):
		if not is_equal_approx(_health_visual_target_x, new_health_fill_x):
			if _health_tween != null and _health_tween.is_running():
				_health_tween.kill()
			health_fill_visual.visible = new_health > 0.0 or not is_equal_approx(health_fill_visual.position.x, _health_fill_x_for(0.0))
			_health_tween = create_tween()
			_health_tween.tween_property(health_fill_visual, "position:x", new_health_fill_x, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			_health_tween.tween_callback(_finish_health_animation)
	else:
		health_fill_visual.position.x = new_health_fill_x
		health_fill_visual.visible = new_health > 0.0
	health_bar.value = new_health
	_health_target = new_health
	_health_visual_target_x = new_health_fill_x
	shield_bar.max_value = maxf(1.0, float(state.get("max_shield", 0)))
	var new_shield := float(state.get("shield", 0))
	var new_shield_fill_x := (SHIELD_FILL.get_width() - 5.0) * (clampf(new_shield / shield_bar.max_value, 0.0, 1.0) - 1.0)
	if animate_bars or (_shield_tween != null and _shield_tween.is_running()):
		if not is_equal_approx(_shield_visual_target_x, new_shield_fill_x):
			if _shield_tween != null and _shield_tween.is_running():
				_shield_tween.kill()
			shield_fill_visual.visible = new_shield > 0.0 or _shield_target > 0.0
			_shield_tween = create_tween()
			_shield_tween.tween_property(shield_fill_visual, "position:x", new_shield_fill_x, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			_shield_tween.tween_callback(_finish_shield_animation)
	else:
		shield_fill_visual.position.x = new_shield_fill_x
		shield_fill_visual.visible = new_shield > 0.0
	shield_bar.value = new_shield
	_shield_target = new_shield
	_shield_visual_target_x = new_shield_fill_x
	shield_bar.visible = shield_fill_visual.visible
	var conditions: Array[String] = []
	if bool(state.get("frozen", false)): conditions.append("Frozen")
	if bool(state.get("stunned", false)): conditions.append("Stunned")
	if int(state.get("current_charge", 0)) > 0: conditions.append("Charging")
	if int(state.get("current_exhaust", 0)) > 0: conditions.append("Exhausted")
	if int(state.get("shield", 0)) > 0: conditions.append("Shield %d" % int(state.shield))
	var is_defeated := bool(state.get("defeated", false)) or new_health <= 0.0
	if is_defeated and not _death_started:
		_death_started = true
		if is_initial_state:
			visible = false
		else:
			_play_death_animation()
	elif not is_defeated and _death_started:
		_death_started = false
		if _death_tween != null and _death_tween.is_running():
			_death_tween.kill()
		visible = true
		modulate.a = 1.0
		_play_teleport_in()
	status_label.text = " • ".join(conditions)
	status_label.visible = not is_defeated and not conditions.is_empty()

func set_move_order_position(order_position: int) -> void:
	if move_order_label != null:
		move_order_label.text = str(order_position) if order_position > 0 else ""

func set_campaign_level_display(level: int) -> void:
	if level_label != null:
		level_label.text = "lv. %d" % level

func apply_campaign_level_up(previous_stats: Dictionary, next_stats: Dictionary) -> void:
	if health_bar == null:
		return
	var old_max_health := int(previous_stats.get("health", health_bar.max_value))
	var new_max_health := maxi(1, int(next_stats.get("health", health_bar.max_value)))
	var health_increase := maxi(0, new_max_health - old_max_health)
	if _health_tween != null and _health_tween.is_running():
		_health_tween.kill()
	health_bar.max_value = new_max_health
	if health_increase > 0:
		_health_target = minf(new_max_health, health_bar.value + health_increase)
		_health_visual_target_x = _health_fill_x_for(_health_target)
		_health_tween = create_tween()
		_health_tween.tween_property(health_fill_visual, "position:x", _health_visual_target_x, 0.3)
		health_bar.value = _health_target
	else:
		_update_health_fill_visual(health_bar.value)

func apply_campaign_evolution(definition: MinionDefinition, sprite_texture: Texture2D, max_health: int, max_energy: int, persistent_health: int, persistent_energy: int) -> void:
	if definition == null or sprite_texture == null or minion_sprite == null:
		return
	minion_definition = definition
	minion_image = sprite_texture.get_image()
	minion_sprite.texture = sprite_texture
	minion_sprite.position.y = -float(sprite_texture.get_height()) * 0.5
	var sprite_height := float(sprite_texture.get_height())
	if health_background_sprite != null:
		health_background_sprite.position.y = -sprite_height - 30.0
	if health_bar != null:
		health_bar.position.y = -sprite_height - 27.0
		health_bar.max_value = maxf(1.0, float(max_health))
		health_bar.value = float(maxi(0, persistent_health)) if persistent_health >= 0 else float(max_health)
		_health_target = health_bar.value
		if health_fill_clip != null:
			health_fill_clip.position = health_bar.position
		_update_health_fill_visual(health_bar.value)
	if shield_bar != null and health_bar != null:
		shield_bar.position = health_bar.position
		shield_fill_clip.position = shield_bar.position
	if turn_badge != null:
		turn_badge.position.y = -sprite_height - 38.0
	if move_order_label != null and turn_badge != null:
		move_order_label.position = turn_badge.position
	if level_label != null:
		level_label.position.y = -sprite_height - 17.0
	if selected_indicator != null:
		selected_indicator.position.y = -sprite_height - 60.0
	if max_energy >= 0:
		state_cache["max_energy"] = max_energy
		state_cache["energy"] = float(maxi(0, persistent_energy)) if persistent_energy >= 0 else float(max_energy)

## Hidden until the battle intro calls its turn to teleport in.
func hold_for_entry() -> void:
	for tween in _teleport_tweens:
		if tween != null and tween.is_running():
			tween.kill()
	_teleport_tweens.clear()
	for piece in teleport_animation_pieces:
		piece.visible = false
	visible = false

func play_extra_minion_spawn_animation() -> void:
	_play_teleport_in()

func _play_teleport_in() -> void:
	if minion_sprite == null or teleport_animation_pieces.is_empty():
		return
	visible = true
	modulate.a = 1.0
	for tween in _teleport_tweens:
		if tween != null and tween.is_running():
			tween.kill()
	_teleport_tweens.clear()
	for index in teleport_animation_pieces.size():
		var piece := teleport_animation_pieces[index]
		var angle := deg_to_rad(51.0 * index)
		piece.position = Vector2(
			-float(piece.texture.get_width()) * 0.5 + 80.0 * cos(angle),
			-float(piece.texture.get_height()) * 1.4 - 80.0 * sin(angle)
		)
		piece.visible = true
		piece.modulate.a = 0.0
		var piece_tween := create_tween()
		piece_tween.set_parallel(true)
		piece_tween.tween_property(piece, "position", Vector2(-float(piece.texture.get_width()) * 0.5, -float(piece.texture.get_height()) * 1.4), 0.8)
		piece_tween.tween_property(piece, "modulate:a", 0.4, 0.8)
		piece_tween.chain().tween_property(piece, "modulate:a", 0.0, 0.2 + index * 0.15)
		_teleport_tweens.append(piece_tween)
	minion_sprite.modulate.a = 0.0
	var sprite_tween := create_tween()
	sprite_tween.tween_property(minion_sprite, "modulate:a", 1.0, 0.5).set_delay(0.5)
	_teleport_tweens.append(sprite_tween)
	if battle_mod_shield_sprite != null and bool(state_cache.get("battle_mod_shield_active", false)):
		if _battle_mod_shield_tween != null and _battle_mod_shield_tween.is_running():
			_battle_mod_shield_tween.kill()
		var shield_height := float(BATTLE_MOD_SHIELD_TEXTURE.get_height())
		battle_mod_shield_sprite.visible = true
		battle_mod_shield_sprite.position.y = -shield_height - 30.0
		battle_mod_shield_sprite.modulate.a = 0.0
		_battle_mod_shield_tween = create_tween().set_parallel(true)
		_battle_mod_shield_tween.tween_property(battle_mod_shield_sprite, "position:y", -shield_height + 10.0, 0.8).set_delay(0.5)
		_battle_mod_shield_tween.tween_property(battle_mod_shield_sprite, "modulate:a", 1.0, 0.8).set_delay(0.5)
	var interface_items: Array[CanvasItem] = [health_background_sprite, health_fill_clip, shield_fill_clip, turn_badge, move_order_label, level_label, status_label]
	for item in interface_items:
		if item == null:
			continue
		item.modulate.a = 0.0
		var interface_tween := create_tween()
		interface_tween.tween_property(item, "modulate:a", 1.0, 0.5).set_delay(0.8)
		_teleport_tweens.append(interface_tween)

func _set_battle_mod_shield(active: bool, animate: bool) -> void:
	if battle_mod_shield_sprite == null:
		return
	if _battle_mod_shield_tween != null and _battle_mod_shield_tween.is_running():
		_battle_mod_shield_tween.kill()
	var shield_height := float(BATTLE_MOD_SHIELD_TEXTURE.get_height())
	var resting_y := -shield_height + 10.0
	if not animate:
		battle_mod_shield_sprite.visible = active
		battle_mod_shield_sprite.position.y = resting_y
		battle_mod_shield_sprite.modulate.a = 1.0
		return
	if active:
		battle_mod_shield_sprite.visible = true
		battle_mod_shield_sprite.position.y = -shield_height - 30.0
		battle_mod_shield_sprite.modulate.a = 0.0
		_battle_mod_shield_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_battle_mod_shield_tween.tween_property(battle_mod_shield_sprite, "position:y", resting_y, 0.8)
		_battle_mod_shield_tween.tween_property(battle_mod_shield_sprite, "modulate:a", 1.0, 0.8)
	else:
		_battle_mod_shield_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_battle_mod_shield_tween.tween_property(battle_mod_shield_sprite, "position:y", -shield_height - 30.0, 0.8)
		_battle_mod_shield_tween.tween_property(battle_mod_shield_sprite, "modulate:a", 0.0, 0.8)
		_battle_mod_shield_tween.chain().tween_callback(func() -> void: battle_mod_shield_sprite.visible = false)

func defer_battle_mod_shield_entry() -> void:
	# The engine has already selected first-round shields. Hide their visual
	# until StartRound after the intro, without changing engine targetability.
	if _battle_mod_shield_tween != null and _battle_mod_shield_tween.is_running():
		_battle_mod_shield_tween.kill()
	state_cache["battle_mod_shield_active"] = false
	battle_mod_shield_sprite.visible = false
	battle_mod_shield_sprite.modulate.a = 0.0

func _play_death_animation() -> void:
	visible = true
	_death_tween = create_tween()
	_death_tween.tween_interval(1.2)
	_death_tween.tween_property(self, "modulate:a", 0.0, 0.5)

func restore_replaced_minion_for_finish() -> void:
	# BattleScreen.ResetExtraMinionsForBattleMod restores the defeated owned
	# minion at alpha .5 before experience/stat/talent/evolution presentation.
	if _death_tween != null and _death_tween.is_running():
		_death_tween.kill()
	_cancel_teleport_for_finish()
	visible = true
	modulate.a = 0.5
	set_target_state(false, false)
	set_move_order_position(0)
	set_buff_icons([])

func begin_finish_presentation() -> void:
	_cancel_teleport_for_finish()
	var interface_fade := create_tween().set_parallel(true)
	for item in [health_background_sprite, health_fill_clip, shield_fill_clip, turn_badge, move_order_label, level_label]:
		interface_fade.tween_property(item, "modulate:a", 0.0, 0.3)
	set_target_state(false, false)
	if bool(state_cache.get("defeated", false)) or int(state_cache.get("health", 0)) <= 0:
		if _death_tween != null and _death_tween.is_running():
			_death_tween.kill()
		visible = true
		var ghost := create_tween()
		ghost.tween_interval(0.4)
		ghost.tween_property(self, "modulate:a", 0.5, 0.3)

func _cancel_teleport_for_finish() -> void:
	# A timer/replacement can finish combat before its delayed interface entry.
	# Those old spawn tweens must not bring combat HUD back over the XP screen.
	for tween in _teleport_tweens:
		if tween != null and tween.is_running(): tween.kill()
	_teleport_tweens.clear()
	for piece in teleport_animation_pieces:
		piece.visible = false
	minion_sprite.modulate.a = 1.0

func _finish_shield_animation() -> void:
	if is_zero_approx(_shield_target):
		shield_bar.visible = false
		shield_fill_visual.visible = false

func _update_health_fill_visual(value: float) -> void:
	if health_fill_visual == null or health_bar == null:
		return
	var fill_x := _health_fill_x_for(value)
	health_fill_visual.position.x = fill_x
	health_fill_visual.visible = value > 0.0
	_health_visual_target_x = fill_x

func _health_fill_x_for(value: float) -> float:
	var fraction := clampf(value / maxf(1.0, health_bar.max_value), 0.0, 1.0)
	return (HEALTH_FILL.get_width() - 5.0) * (fraction - 1.0)

func _finish_health_animation() -> void:
	if is_zero_approx(_health_target):
		health_fill_visual.visible = false

func apply_event_values(values: Dictionary) -> void:
	# Keep the previous cache intact until update_from_state compares shield and
	# death transitions. Mutating state_cache first made those event changes look
	# like no-ops and could also snap an active health/shield tween.
	var next_state := state_cache.duplicate(true)
	for key in values:
		next_state[key] = values[key]
	update_from_state(next_state, true)

func set_target_state(is_targetable: bool, is_selected: bool) -> void:
	targetable = is_targetable
	target_selected = is_selected
	if selected_indicator != null:
		selected_indicator.visible = is_selected

## The health bar (with a little slack, it is thin) under `canvas_point`:
## clicking it opens the minion's stats.
func health_bar_contains_canvas_point(canvas_point: Vector2) -> bool:
	if health_background_sprite == null or health_background_sprite.texture == null or not visible or modulate.a <= 0.05:
		return false
	var local_point: Vector2 = health_background_sprite.get_global_transform_with_canvas().affine_inverse() * canvas_point
	return Rect2(Vector2.ZERO, health_background_sprite.texture.get_size()).grow(4.0).has_point(local_point)

func contains_canvas_point(canvas_point: Vector2) -> bool:
	if minion_sprite == null or minion_sprite.texture == null:
		return false
	var local_point: Vector2 = minion_sprite.get_global_transform_with_canvas().affine_inverse() * canvas_point
	var size := minion_sprite.texture.get_size()
	var pixel := Vector2i(floori(local_point.x + size.x * 0.5), floori(local_point.y + size.y * 0.5))
	if pixel.x < 0 or pixel.y < 0 or pixel.x >= size.x or pixel.y >= size.y:
		return false
	if minion_image == null or minion_image.is_empty():
		return true
	if minion_sprite.flip_h:
		pixel.x = int(size.x) - pixel.x - 1
	return minion_image.get_pixelv(pixel).a > 0.1

func show_status_badge(texture: Texture2D, badge_text: String = "") -> void:
	if texture == null:
		return
	var badge_root := Node2D.new()
	badge_root.name = texture.resource_path.get_file().get_basename()
	badge_root.position = Vector2(-texture.get_width() * 0.5, -_sprite_height() - 50.0)
	badge_root.z_index = 100
	badge_root.modulate.a = 0.0
	add_child(badge_root)
	var badge := Sprite2D.new()
	badge.texture = texture
	badge.centered = false
	badge_root.add_child(badge)
	if not badge_text.is_empty():
		var stat_label := Label.new()
		stat_label.text = badge_text
		stat_label.position = Vector2(28.0, 0.0)
		stat_label.size = Vector2(100.0, float(texture.get_height()))
		stat_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		stat_label.add_theme_font_override("font", BURBIN_FONT)
		stat_label.add_theme_font_size_override("font_size", 20)
		stat_label.add_theme_color_override("font_color", Color8(229, 230, 232))
		stat_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge_root.add_child(stat_label)
	var fade := create_tween()
	fade.tween_property(badge_root, "modulate:a", 1.0, 0.2)
	fade.tween_interval(0.4)
	fade.tween_property(badge_root, "modulate:a", 0.0, 0.2)
	fade.tween_callback(badge_root.queue_free)
	var rise := create_tween()
	rise.tween_property(badge_root, "position:y", badge_root.position.y - 50.0, 0.8)

func play_source_condition_tint(kind: StringName) -> void:
	if _condition_tint_material == null:
		return
	if _condition_tint_tween != null and _condition_tint_tween.is_running():
		_condition_tint_tween.kill()
	var multiplier := Vector3.ONE
	var offset := Vector3.ZERO
	if kind in [&"frozen", &"stunned"]:
		var tint := Color.hex(0x3399ffff if kind == &"frozen" else 0xffff66ff)
		multiplier = Vector3.ONE * 0.5
		offset = Vector3(tint.r, tint.g, tint.b) * 0.5
	_condition_tint_tween = create_tween().set_parallel(true)
	var current_multiplier: Vector3 = _condition_tint_material.get_shader_parameter("rgb_multiplier")
	var current_offset: Vector3 = _condition_tint_material.get_shader_parameter("rgb_offset")
	_condition_tint_tween.tween_method(_set_condition_multiplier, current_multiplier, multiplier, 1.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_condition_tint_tween.tween_method(_set_condition_offset, current_offset, offset, 1.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _set_condition_multiplier(value: Vector3) -> void:
	_condition_tint_material.set_shader_parameter("rgb_multiplier", value)

func _set_condition_offset(value: Vector3) -> void:
	_condition_tint_material.set_shader_parameter("rgb_offset", value)

func show_impact_feedback(effectiveness: float, critical: bool) -> void:
	if effectiveness > 1.4:
		_spawn_feedback_popup(SUPER_EFFECTIVE_POPUP, Vector2(-65.0, -_sprite_height() - 80.0))
	elif effectiveness < 0.7:
		_spawn_feedback_popup(NOT_EFFECTIVE_POPUP, Vector2(-63.0, -_sprite_height() - 80.0))
	if critical:
		_spawn_feedback_popup(CRITICAL_POPUP, Vector2(-62.0, -_sprite_height() - 35.0))

func show_redirection_feedback() -> void:
	_spawn_feedback_popup(REDIRECTED_POPUP, Vector2(-41.0, -_sprite_height() - 70.0), 20.0)

func show_reflected_damage_feedback() -> void:
	if minion_sprite == null or REFLECTED_DAMAGE_POPUP == null:
		return
	var popup := Sprite2D.new()
	popup.name = "ReflectedDamageCallout"
	popup.texture = REFLECTED_DAMAGE_POPUP
	popup.centered = false
	popup.position = Vector2(-float(REFLECTED_DAMAGE_POPUP.get_width()) * 0.5, -_sprite_height() - 100.0)
	popup.modulate.a = 0.0
	popup.z_index = 102
	add_child(popup)
	var fade := create_tween()
	fade.tween_property(popup, "modulate:a", 1.0, 0.2)
	fade.tween_interval(0.4)
	fade.tween_property(popup, "modulate:a", 0.0, 0.2)
	fade.tween_callback(popup.queue_free)
	var drift := create_tween()
	drift.tween_property(popup, "position:x", popup.position.x - 30.0, 0.8)

func _sprite_height() -> float:
	return float(minion_sprite.texture.get_height()) if minion_sprite != null and minion_sprite.texture != null else 0.0

func _spawn_feedback_popup(texture: Texture2D, popup_position: Vector2, lift_distance: float = 50.0) -> void:
	var popup := Sprite2D.new()
	popup.texture = texture
	# Popup offsets are authored from the sprite's top-left corner so that all
	# recovered callouts share the same horizontal center above the combatant.
	popup.centered = false
	popup.position = popup_position
	popup.modulate.a = 0.0
	popup.z_index = 100
	add_child(popup)
	var fade := create_tween()
	fade.tween_property(popup, "modulate:a", 1.0, 0.5)
	fade.tween_interval(0.5)
	fade.tween_property(popup, "modulate:a", 0.0, 0.2)
	fade.tween_callback(popup.queue_free)
	var lift := create_tween()
	lift.tween_property(popup, "position:y", popup.position.y - lift_distance, 1.2)
