extends Control

## TopDownMovementScreen.PlayFuseSageSealsTogether, all six standard families.
const TOTAL_SECONDS := 4.95
const PIECE_POSITIONS := [Vector2(287, 141), Vector2(301, 201), Vector2(367, 148), Vector2(367, 207)]
const MEDALLIONS := ["menus_plantMedallion", "menus_fireMedallion", "menus_electricMedallion", "menus_undeadMedallion", "menus_plantWizardMedallion", "menus_undeadWizardMedallion"]
var _timeline: Tween
var active := false
var _on_complete: Callable

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 1400
	mouse_filter = Control.MOUSE_FILTER_STOP
	hide()

func play(family: int, audio: BattleAudioController, on_complete: Callable) -> bool:
	cancel()
	if family < 1 or family > MEDALLIONS.size():
		return false
	var textures: Array[Texture2D] = []
	var piece_count := 4 if family >= 5 else 3
	for index in piece_count:
		var texture := SourceMenuArt.texture("sageSeal_%d_%d" % [family, index + 1])
		if texture == null:
			return false
		textures.append(texture)
	var medallion_texture := SourceMenuArt.texture(MEDALLIONS[family - 1])
	if medallion_texture == null:
		return false
	active = true
	_on_complete = on_complete
	show()
	var flash := ColorRect.new()
	flash.name = "SourceSealFlash"
	flash.size = Vector2(700, 525)
	flash.color = Color.WHITE
	flash.modulate.a = 0.0
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash)
	_timeline = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_timeline.tween_property(flash, "modulate:a", 0.5, 0.5).set_delay(1.3)
	_timeline.tween_property(flash, "modulate:a", 1.0, 0.15).set_delay(2.7)
	_timeline.tween_property(flash, "modulate:a", 0.3, 0.15).set_delay(2.85)
	_timeline.tween_property(flash, "modulate:a", 0.0, 1.5).set_delay(3.0)
	for index in piece_count:
		var piece := _image("SourceSealPiece%d" % (index + 1), textures[index], PIECE_POSITIONS[index])
		_timeline.tween_property(piece, "modulate:a", 1.0, 0.5).set_delay(1.8)
		_timeline.tween_property(piece, "position", Vector2(323, 167), 0.15).set_delay(2.7)
		_timeline.tween_property(piece, "modulate:a", 0.0, 0.05).set_delay(2.85)
	var medallion := _image("SourceSealMedallion", medallion_texture, Vector2(323, 167))
	_timeline.tween_property(medallion, "modulate:a", 1.0, 0.15).set_delay(2.7)
	_timeline.tween_property(medallion, "modulate:a", 0.0, 1.8).set_delay(2.85)
	_timeline.tween_property(medallion, "position:y", 157.0, 1.8).set_delay(2.85)
	if audio != null:
		_timeline.tween_callback(audio.play_sound.bind("battle_levelUp", 0.25)).set_delay(2.7)
	_timeline.tween_callback(_finish).set_delay(TOTAL_SECONDS)
	return true

func _image(node_name: String, texture: Texture2D, at: Vector2) -> TextureRect:
	var image := TextureRect.new()
	image.name = node_name
	image.texture = texture
	image.size = texture.get_size()
	image.position = at
	image.modulate.a = 0.0
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(image)
	return image

func _finish() -> void:
	var completion := _on_complete
	_on_complete = Callable()
	active = false
	hide()
	for child in get_children():
		child.queue_free()
	if completion.is_valid():
		completion.call()

func cancel() -> void:
	if _timeline != null and _timeline.is_running():
		_timeline.kill()
	active = false
	_on_complete = Callable()
	hide()
	for child in get_children():
		remove_child(child)
		child.queue_free()
