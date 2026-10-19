extends SceneTree

# Render original inspector sheets or selected palettes directly from textures.
const FONT := preload("res://content/base/fonts/BurbinCasual.ttf")
const SHADER := preload("res://src/presentation/shaders/minion_palette.gdshader")
const OUTPUT := "res://build/shiny-palettes"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var registry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/base/palettes/shiny_palettes.json"))
	var manifest: Array = []
	var root_ids: Array = registry.lines.keys()
	root_ids.sort()
	for root_id in root_ids:
		manifest.append({"root_id": root_id, "stages": registry.lines[root_id].stages})
	var choices: Dictionary = {}
	var selected := "--selected" in OS.get_cmdline_user_args()
	if selected:
		choices = registry.lines
	for group in 3:
		var lines: Array = []
		for index in manifest.size():
			if index % 3 == group: lines.append(manifest[index])
		for page in ceili(lines.size() / 12.0):
			var viewport := SubViewport.new()
			viewport.size = Vector2i(1440, 1000)
			viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			root.add_child(viewport)
			var backdrop := ColorRect.new()
			backdrop.size = Vector2(1440, 1000)
			backdrop.color = Color8(25, 30, 40)
			viewport.add_child(backdrop)
			_label(viewport, "%s — group %d / page %d" % ["SHINY ASSIGNMENTS" if selected else "ORIGINAL MINION LINES", group, page + 1], Vector2(20, 8), 28)
			for slot in mini(12, lines.size() - page * 12):
				var line: Dictionary = lines[page * 12 + slot]
				var at := Vector2(20 + slot % 3 * 475, 60 + slot / 3 * 230)
				var card := Panel.new()
				card.position = at
				card.size = Vector2(460, 218)
				var style := StyleBoxFlat.new()
				style.bg_color = Color8(46, 53, 66)
				style.set_corner_radius_all(6)
				card.add_theme_stylebox_override("panel", style)
				viewport.add_child(card)
				var choice: Dictionary = choices.get(line.root_id, {})
				_label(card, line.stages[0].name + (" — " + String(choice.palette_name) if selected else ""), Vector2(9, 6), 22)
				var stages: Array = line.stages
				for stage_index in stages.size():
					var stage: Dictionary = stages[stage_index]
					var texture := load("res://" + String(stage.texture)) as Texture2D
					assert(texture != null, "Missing artwork: %s" % stage.id)
					var cell_width := 440.0 / stages.size()
					var sprite := TextureRect.new()
					sprite.texture = texture
					sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
					sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
					sprite.position = Vector2(10 + stage_index * cell_width, 39)
					sprite.size = Vector2(cell_width - 8, 139)
					if selected:
						var material := ShaderMaterial.new()
						material.shader = SHADER
						for parameter in choice.parameters: material.set_shader_parameter(parameter, choice.parameters[parameter])
						sprite.material = material
					card.add_child(sprite)
					_label(card, stage.name, Vector2(10 + stage_index * cell_width, 181), 16)
			await process_frame
			await RenderingServer.frame_post_draw
			var path := "%s/%s-group-%d-page-%d.png" % [OUTPUT, "selected" if selected else "original", group, page + 1]
			assert(viewport.get_texture().get_image().save_png(path) == OK)
			viewport.queue_free()
			await process_frame
	print("Rendered all 62 evolution lines / 122 forms: %s" % ("selected" if selected else "original"))
	quit()

func _label(parent: Node, text: String, at: Vector2, font_size: int) -> void:
	var label := Label.new()
	label.text = text
	label.position = at
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color8(242, 239, 220))
	parent.add_child(label)
