extends Control

const FONT := preload("res://content/base/fonts/BurbinCasual.ttf")

func configure(old_definition: MinionDefinition, old_texture: Texture2D, new_texture: Texture2D) -> void:
	# EvolvingPopup is attached at (0,0), without a screen-wide tinted panel.
	name = "ProgressionModal"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 20
	var panel := Control.new()
	panel.name = "Panel"
	panel.size = Vector2(381, 280)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	SourceMenuArt.image(panel, "battleScreenMenus_evolution_popUp", Vector2(9, 5))
	var close := SourceMenuArt.button(panel, "battleScreenMenus_evolution_closeButton", Vector2(323, 7), func() -> void: set_meta("skip_evolution", true))
	close.name = "CloseButton"
	var message := Label.new()
	message.name = "Message"
	message.position = Vector2(33, 246)
	message.size = Vector2(350, 30)
	message.text = "%s is growing..." % old_definition.display_name
	message.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	message.add_theme_font_override("font", FONT)
	message.add_theme_font_size_override("font_size", 17)
	message.add_theme_color_override("font_color", Color.hex(0xf9f9f9ff))
	message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(message)
	var new_sprite := _sprite(new_texture, "NewSprite")
	panel.add_child(new_sprite)
	# The recovered bitmap covers the new form while it is on the left.
	SourceMenuArt.image(panel, "battleScreenMenus_evolution_mask", Vector2(13, 7)).name = "NewCover"
	var mask := Sprite2D.new()
	mask.name = "OldMask"
	mask.texture = SourceMenuArt.texture("battleScreenMenus_evolution_mask")
	mask.centered = false
	mask.position = Vector2(13, 7)
	mask.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	panel.add_child(mask)
	var old_sprite := _sprite(old_texture, "OldSprite")
	old_sprite.position -= mask.position
	mask.add_child(old_sprite)

func _sprite(texture: Texture2D, sprite_name: String) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.name = sprite_name
	sprite.texture = texture
	sprite.centered = false
	sprite.position = Vector2(96 - texture.get_width() * 0.5, 169 - texture.get_height())
	return sprite
