extends SceneTree

# Reproducible GPU preview: no generated artwork, texture edits or save writes.
const SHADER := preload("res://src/presentation/shaders/minion_palette.gdshader")
const FONT := preload("res://content/base/fonts/BurbinCasual.ttf")
const PALETTES := [
	{"name": "Original", "shift": 0.0},
	{"name": "Moonstone Blue", "shift": 0.50},
	{"name": "Amethyst Violet", "shift": 0.69},
	{"name": "Jade Teal", "shift": 0.35},
]
const LINES := [
	{"name": "Ticub / Tigertan", "sprites": ["res://content/base/art/battle/minions/normalTiger1.png", "res://content/base/art/battle/minions/normalTiger2.png"], "hue": 0.08},
	{"name": "Zapig / Tazorback", "sprites": ["res://content/base/art/battle/minions/energyBoar1.png", "res://content/base/art/battle/minions/energyBoar2.png"], "hue": 0.08},
	{"name": "Arkvian / Arkclaw", "sprites": ["res://content/base/art/source_symbols/1685_Utilities.SpriteHandler_HolyBirb1.png", "res://content/base/art/source_symbols/1686_Utilities.SpriteHandler_HolyBirb2.png"], "hue": 0.12},
]

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Run rendered: this preview uses the actual GPU palette shader.")
		quit(1)
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 1000)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var background := ColorRect.new()
	background.size = Vector2(1280, 1000)
	background.color = Color8(25, 30, 40)
	viewport.add_child(background)
	_label(viewport, "SHINY PALETTE SUGGESTIONS", Vector2(30, 17), Vector2(1220, 50), 34)
	_label(viewport, "Same original sprites. One shader. Shared settings across each evolution line.", Vector2(30, 68), Vector2(1220, 40), 21)
	for column in PALETTES.size():
		_label(viewport, PALETTES[column].name, Vector2(30 + column * 310, 115), Vector2(290, 40), 25)
	for row in LINES.size():
		var line: Dictionary = LINES[row]
		var y := 171.0 + row * 253.0
		for column in PALETTES.size():
			var x := 30.0 + column * 310.0
			var card := Panel.new()
			card.position = Vector2(x, y)
			card.size = Vector2(290, 234)
			var style := StyleBoxFlat.new()
			style.bg_color = Color8(46, 53, 66)
			style.border_color = Color8(97, 109, 125)
			style.set_border_width_all(1)
			style.set_corner_radius_all(9)
			card.add_theme_stylebox_override("panel", style)
			viewport.add_child(card)
			_label(card, line.name, Vector2(9, 8), Vector2(272, 32), 23)
			for stage in 2:
				var texture := load(line.sprites[stage]) as Texture2D
				assert(texture != null)
				var sprite := TextureRect.new()
				sprite.texture = texture
				sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				sprite.position = Vector2(8 + stage * 139, 48)
				sprite.size = Vector2(134, 156)
				if column > 0:
					var material := ShaderMaterial.new()
					material.shader = SHADER
					material.set_shader_parameter("hue_shift", PALETTES[column].shift)
					material.set_shader_parameter("source_hue", line.hue)
					sprite.material = material
				card.add_child(sprite)
			_label(card, "Stage 1                    Stage 2", Vector2(11, 202), Vector2(268, 25), 16)
	_label(viewport, "Palette candidates, not final assignments. No glow, no stat changes, no replacement artwork.", Vector2(30, 941), Vector2(1220, 35), 21)
	await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	assert(not image.is_empty())
	var result := image.save_png("res://build/shiny-palette-suggestions.png")
	assert(result == OK)
	print("Saved shader-generated palette preview: build/shiny-palette-suggestions.png")
	quit()

func _label(parent: Node, text: String, at: Vector2, dimensions: Vector2, font_size: int) -> void:
	var label := Label.new()
	label.text = text
	label.position = at
	label.size = dimensions
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color8(242, 239, 220))
	parent.add_child(label)
