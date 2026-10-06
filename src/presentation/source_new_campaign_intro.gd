extends Control
## Recovered MainMenuScreen's new-save cinematic. Own every scheduled cue so
## Skip cannot leave delayed callbacks that act on the subsequently loaded room.
signal completed

const FONT: Font = preload("res://content/base/fonts/BurbinCasual.ttf")
const GLOW_SHADER: Shader = preload("res://src/presentation/source_title_glow.gdshader")
const STORY := [
	"Thousands apply to train at the Tower of Sages.",
	"Only a few are ever chosen.",
	"But all dream of training Titans...",
	"This is the story of one who was chosen.",
]

var _audio: BattleAudioController
var _timelines: Array[Tween] = []
var _finished := false
var _skip: TextureButton
var _skip_revealed := false
var _glows: Array[TextureRect] = []
var _story_viewport: SubViewport
var _story_canvas: Control
var _story_words: Array[Sprite2D] = []

static func mask_glow(art: TextureRect, mask_y: float, inverted: bool = true) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = GLOW_SHADER
	material.set_shader_parameter("reveal_mask", SourceMenuArt.texture("mainMenu_doorAnimationMask1"))
	material.set_shader_parameter("art_origin", art.position)
	material.set_shader_parameter("mask_y", mask_y)
	material.set_shader_parameter("mask_x", 155.0 if inverted else 154.0)
	material.set_shader_parameter("inverted", inverted)
	art.material = material
	return material

func start(audio: BattleAudioController, background_y: float = -448.0) -> void:
	_audio = audio
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(black)
	var zoom := Control.new()
	zoom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(zoom)
	var door_y := background_y + 678.0
	var left := SourceMenuArt.image(zoom, "mainMenu_titleScreen_doorLeft", Vector2(164.0, door_y))
	var right := SourceMenuArt.image(zoom, "mainMenu_titleScreen_doorRight", Vector2(349.0, door_y))
	for side in 2:
		var glow := SourceMenuArt.image(zoom, "mainMenu_titleScreen_door%s_glow" % ("Left" if side == 0 else "Right"), Vector2(164.0 if side == 0 else 349.0, 230.0))
		if glow == null:
			continue
		_glows.append(glow)
		glow.modulate.a = 0.5
		var material := mask_glow(glow, 646.0)
		var reveal := _timeline(3.4)
		reveal.tween_method(func(value: float) -> void: material.set_shader_parameter("mask_y", value), 646.0, 261.0, 4.5)
		var opening := _timeline(8.1)
		opening.tween_property(glow, "modulate:a", 1.0, 0.3)
		opening.tween_interval(1.0)
		opening.tween_property(glow, "position:x", glow.position.x + (-188.0 if side == 0 else 188.0), 6.3)
		opening.parallel().tween_property(glow, "modulate:a", 0.4, 6.3)
	var background := SourceMenuArt.image(zoom, "mainMenu_titleScreen_background", Vector2(-30.0, background_y))
	# Only the stone and door leaves scroll in the original, not the glow masks.
	if background_y > -448.0:
		var remaining := (background_y + 448.0) / 45.0
		_property(background, "position:y", -448.0, remaining, 0.0, Tween.TRANS_LINEAR)
		_property(left, "position:y", 230.0, remaining, 0.0, Tween.TRANS_LINEAR)
		_property(right, "position:y", 230.0, remaining, 0.0, Tween.TRANS_LINEAR)
	var outer := SourceMenuArt.image(self, "mainMenu_titleScreen_doorCracksGlow", Vector2(155.0, 222.0))
	if outer != null:
		_glows.append(outer)
		var outer_material := mask_glow(outer, 107.0, false)
		var reveal_outer := _timeline(2.9)
		reveal_outer.tween_method(func(value: float) -> void: outer_material.set_shader_parameter("mask_y", value), 107.0, 524.0, 10.0)
		_property(outer, "modulate:a", 0.0, 2.8, 8.1)
	for item in [left, right, background]:
		if item != null:
			_shake(item, 0.7, [18, 18, 12, 8, 5, 4, 3, 2, 1], 0.1)
	_property(left, "position:x", -24.0, 6.3, 9.4)
	_property(right, "position:x", 537.0, 6.3, 9.4)
	var approach := _shake(zoom, 9.4, [3, 2, 1], 0.1)
	for index in 16:
		approach.tween_property(zoom, "position:x", 1.0, 0.15)
		approach.tween_property(zoom, "position:x", 0.0, 0.15)
	approach.tween_interval(0.1)
	approach.tween_property(zoom, "scale", Vector2(2.0, 2.0), 30.2)
	approach.parallel().tween_property(zoom, "position", Vector2(-348.0, -490.0), 30.2)
	var darkness := ColorRect.new()
	darkness.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	darkness.color = Color.BLACK
	darkness.modulate.a = 0.0
	darkness.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(darkness)
	_property(darkness, "modulate:a", 1.0, 4.0, 16.2)
	_at(20.7, approach.kill)
	# Bake glyphs once, before the story appears. Live Label transforms can
	# re-shape/snap during tiny y/scale changes even with distance-field fonts.
	# Animate fixed, linearly filtered quads instead, preserving source timing.
	_story_viewport = SubViewport.new()
	_story_viewport.name = "StoryGlyphAtlas"
	_story_viewport.size = Vector2i(1024, 256)
	_story_viewport.transparent_bg = true
	_story_viewport.disable_3d = true
	_story_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_story_viewport)
	_story_canvas = Control.new()
	_story_canvas.scale = Vector2(2.0, 2.0)
	_story_viewport.add_child(_story_canvas)
	for row in STORY.size():
		_story_line(STORY[row], row)
	_skip = SourceMenuArt.button(self, "menu_skipIntroButton", Vector2(625.0, 489.0), finish)
	if _skip != null:
		_skip.name = "SkipIntro"
		_skip.modulate.a = 0.0
		_skip.disabled = true
	_audio.fade_music_to(0.2, 2.0)
	_at(15.2, func() -> void: _audio.fade_music_to(0.7, 4.0))
	_at(36.9, func() -> void: _audio.fade_music_to(0.0, 4.0))
	for index in 6:
		_sound("doorEntryHum", 0.35, 2.5 + 1.15 * index)
	_sound("doorEntryHum_fadeout", 0.35, 9.4)
	_sound("battle_earthquake2", 1.0, 0.2)
	_sound("battle_whoosh_magic2", 1.0, 8.1)
	_sound("battle_earthquake2", 0.5, 9.1)
	for delay in [9.55, 10.1, 10.75]:
		_sound("battle_earthquake2", 0.4, delay)
	_at(41.2, finish)

func _process(_delta: float) -> void:
	for glow in _glows:
		(glow.material as ShaderMaterial).set_shader_parameter("art_origin", glow.position)

func _input(event: InputEvent) -> void:
	if _finished or _skip == null or _skip_revealed:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_skip_revealed = true
		var reveal := _timeline(0.0)
		reveal.tween_property(_skip, "modulate:a", 1.0, 0.5)
		reveal.tween_callback(func() -> void: _skip.disabled = false)

func _story_line(line: String, row: int) -> void:
	var x := 143.0
	var words := line.split(" ")
	for index in words.size():
		var width := FONT.get_string_size(words[index], HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		var baked_label := Label.new()
		baked_label.text = words[index]
		baked_label.position = Vector2(x - 143.0 + 2.0, row * 32.0 + 2.0)
		baked_label.add_theme_font_override("font", FONT)
		baked_label.add_theme_font_size_override("font_size", 20)
		baked_label.add_theme_color_override("font_color", Color.hex(0xe5e6e8ff))
		_story_canvas.add_child(baked_label)
		var word := Sprite2D.new()
		word.name = "StoryWord_%d_%d" % [row, index]
		word.texture = _story_viewport.get_texture()
		word.centered = false
		word.region_enabled = true
		word.region_filter_clip_enabled = true
		word.region_rect = Rect2(Vector2(x - 143.0, row * 32.0) * 2.0, Vector2(width + 4.0, 32.0) * 2.0)
		word.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		var destination := Vector2(x - 2.0, 177.0 + 30.0 * row)
		word.position = destination + Vector2(10.0 + index * 5.0, 0.0)
		word.scale = Vector2(0.5, 0.425)
		word.modulate.a = 0.0
		add_child(word)
		_story_words.append(word)
		x += width + 4.0
		var entrance := _timeline(19.5 + row * 3.6 + index * 0.07)
		entrance.tween_property(word, "modulate:a", 1.0, 1.2)
		entrance.parallel().tween_property(word, "scale:y", 0.5, 1.2)
		entrance.parallel().tween_property(word, "position", destination, 1.2)
		var leaving := _timeline(27.0 + row * 3.9)
		leaving.tween_property(word, "modulate:a", 0.0, 3.7)
		leaving.parallel().tween_property(word, "scale:y", 0.425, 3.7)
		leaving.parallel().tween_property(word, "position:y", destination.y - 3.0, 3.7)

func _timeline(delay: float) -> Tween:
	var tween := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_timelines.append(tween)
	if delay > 0.0:
		tween.tween_interval(delay)
	return tween

func _property(target: Object, key: String, value: Variant, duration: float, delay: float, transition: Tween.TransitionType = Tween.TRANS_QUAD) -> void:
	if target != null:
		_timeline(delay).set_trans(transition).tween_property(target, key, value, duration)

func _at(delay: float, callback: Callable) -> void:
	_timeline(delay).tween_callback(callback)

func _sound(sound_id: String, volume: float, delay: float) -> void:
	_at(delay, func() -> void: _audio.play_sound(sound_id, volume))

func _shake(item: Control, delay: float, amounts: Array, duration: float) -> Tween:
	var tween := _timeline(delay)
	var origin := item.position.x
	for amount in amounts:
		tween.tween_property(item, "position:x", origin + float(amount), duration)
		tween.tween_property(item, "position:x", origin, duration)
	return tween

func finish() -> void:
	if _finished:
		return
	_finished = true
	set_process_input(false)
	for tween in _timelines:
		if tween.is_valid():
			tween.kill()
	_timelines.clear()
	if _skip != null:
		_skip.disabled = true
	# Intro sounds use the persistent audio owner; stop only these cues on Skip.
	for child in _audio.get_children():
		if child is AudioStreamPlayer and String(child.name).begins_with("doorEntryHum"):
			(child as AudioStreamPlayer).stop()
			child.queue_free()
	_audio.fade_music_to(0.1, 0.8)
	completed.emit()
