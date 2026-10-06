class_name CampaignEggeryPresenter
extends Control

const BURBIN_FONT: Font = preload("res://content/base/fonts/BurbinCasual.ttf")

func present(result: Dictionary, presentation: MinionPresentationDefinition, actor_screen_position: Vector2, _viewport_size: Vector2) -> void:
	for child in get_children():
		child.queue_free()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var owned := result.get("minion") as OwnedMinionState
	var definition := result.get("definition") as MinionDefinition
	if owned == null or definition == null:
		return
	var background := SourceMenuArt.texture("eggery_minionDetailsBackground")
	if background == null:
		return
	var card_size := background.get_size()
	var card_position := actor_screen_position + Vector2(87.0, -184.0)
	# BaseEggery places the card at MainChar + (87,-184), without screen
	# clamping. Independent clamping detached it from its source speech bubble.
	var card := Control.new()
	card.position = card_position
	card.size = card_size
	card.scale = Vector2.ONE * 0.9
	card.modulate.a = 0.0
	add_child(card)
	create_tween().tween_property(card, "modulate:a", 1.0, 0.2)
	var background_rect := TextureRect.new()
	background_rect.texture = background
	background_rect.size = card_size
	background_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(background_rect)
	if presentation != null and not presentation.legacy_sprite_name.is_empty():
		var sprite_texture := _minion_sprite(presentation.legacy_sprite_name)
		if sprite_texture != null:
			var sprite := Sprite2D.new()
			sprite.texture = sprite_texture
			sprite.centered = false
			sprite.scale = Vector2(-0.85, 0.85)
			# EggeryMinionDetailsObject.AddMinionSprite uses scale .85, flips
			# horizontally, and positions from the source sprite's dimensions.
			var scaled_size := sprite_texture.get_size() * 0.85
			sprite.position = Vector2(83.0 + scaled_size.x * 0.5, 145.0 - scaled_size.y)
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			card.add_child(sprite)
	var level := Label.new()
	level.text = "lv. %d" % owned.level
	level.position = Vector2(14.0, 9.0)
	level.size = Vector2(75.0, 25.0)
	level.add_theme_font_override("font", BURBIN_FONT)
	level.add_theme_font_size_override("font_size", 16)
	level.add_theme_color_override("font_color", Color.hex(0x9faec4ff))
	level.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(level)
	var bonus_index := _egg_stat_bonus_index(owned.stat_bonus)
	var bonus_icon := SourceMenuArt.texture("hud_statBonus_%d" % bonus_index)
	if bonus_icon != null:
		var bonus := TextureRect.new()
		bonus.texture = bonus_icon
		bonus.position = Vector2(144.0, 144.0)
		bonus.size = bonus_icon.get_size()
		bonus.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(bonus)

static func accepted_egg_slots(accepted_slot: int) -> Array[int]:
	var slots: Array[int] = []
	for slot in range(9):
		if slot != accepted_slot:
			slots.append(slot)
	return slots

func _minion_sprite(sprite_name: StringName) -> Texture2D:
	var path := "res://content/base/art/battle/minions/%s.png" % String(sprite_name)
	if not ResourceLoader.exists(path):
		path = "res://content/base/art/battle/%s.png" % String(sprite_name)
	return load(path) as Texture2D if ResourceLoader.exists(path) else null

func _egg_stat_bonus_index(stat_bonus: StringName) -> int:
	match stat_bonus:
		&"health": return 0
		&"energy": return 1
		&"attack": return 2
		&"healing": return 3
		&"speed": return 4
		_: return 0
