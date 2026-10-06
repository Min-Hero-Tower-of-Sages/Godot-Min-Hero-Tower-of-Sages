extends TextureRect

## TutorialPopup.as: center-pivot 1 -> 1.1 -> 1 pulse, .2s pause.
func configure(symbol: String) -> void:
	texture = SourceMenuArt.texture(symbol)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if texture == null:
		return
	size = texture.get_size()
	pivot_offset = size * 0.5
	var pulse := create_tween().set_loops().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	pulse.tween_property(self, "scale", Vector2.ONE * 1.1, 0.5)
	pulse.tween_property(self, "scale", Vector2.ONE, 0.5)
	pulse.tween_interval(0.2)
