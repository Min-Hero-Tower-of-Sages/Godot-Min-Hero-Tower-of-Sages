extends Sprite2D

## InterfaceBar.as uses the original fill bitmap as its alpha mask. Keep the
## bitmap's rounded shape and slide the fill; do not crop or scale its gradient.
var fill: Sprite2D
var travel_width := 0.0
var ratio := 1.0

func configure(fill_texture: Texture2D, end_cap: Texture2D, value: float) -> void:
	texture = fill_texture
	centered = false
	clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	travel_width = float(fill_texture.get_width()) - (float(end_cap.get_width()) if end_cap != null else 0.0)
	fill = Sprite2D.new()
	fill.name = "Fill"
	fill.texture = fill_texture
	fill.centered = false
	add_child(fill)
	set_ratio(value)

func set_ratio(value: float) -> void:
	ratio = clampf(value, 0.0, 1.0)
	fill.position.x = travel_width * (ratio - 1.0)
	visible = ratio > 0.0
