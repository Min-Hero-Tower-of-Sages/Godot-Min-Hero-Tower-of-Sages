class_name ModWorkshopWeightBar
extends Control

## A stacked bar showing how likely each egg is. `segments`:
## [{"label": String, "weight": float, "color": Color, "texture": Texture2D}].

var segments: Array = []

func _init() -> void:
	custom_minimum_size = Vector2(0, 46)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_PASS

func _total() -> float:
	var total := 0.0
	for segment in segments: total += maxf(0.0, float(segment.weight))
	return total

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color8(19, 21, 23))
	var total := _total()
	if total <= 0.0: return
	var font := ModWorkshopForm.FONT
	var x := 0.0
	for segment in segments:
		var width := size.x * maxf(0.0, float(segment.weight)) / total
		if width <= 0.0: continue
		var rect := Rect2(x, 0, width, size.y)
		var color: Color = segment.color
		draw_rect(rect.grow(-1), color)
		var texture := segment.get("texture") as Texture2D
		var icon := minf(size.y - 14.0, width - 4.0)
		if texture != null and icon >= 16.0:
			draw_texture_rect(texture, Rect2(x + (width - icon) * 0.5, 2, icon, icon), false)
		var percent := "%d%%" % roundi(100.0 * float(segment.weight) / total)
		if width >= 26.0:
			draw_string(font, Vector2(x, size.y - 3), percent, HORIZONTAL_ALIGNMENT_CENTER, width, 12, Color8(18, 19, 22))
		x += width

func _get_tooltip(at_position: Vector2) -> String:
	var total := _total()
	if total <= 0.0: return ""
	var x := 0.0
	for segment in segments:
		var width := size.x * maxf(0.0, float(segment.weight)) / total
		if at_position.x >= x and at_position.x < x + width:
			return "%s: %d%%" % [segment.label, roundi(100.0 * float(segment.weight) / total)]
		x += width
	return ""
