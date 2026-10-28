class_name CampaignGemPortrait
extends Control

const CORNERS := ["gemCornerRed", "gemCornerPurple", "gemCornerOrange", "gemCornerYellow", "gemCornerBlue"]

func configure(gem: Dictionary) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tier := clampi(int(gem.get("tier", 1)), 1, 11)
	var shape_texture := SourceMenuArt.texture("gemTier%d_shape" % tier)
	var mask_texture := SourceMenuArt.texture("gemTier%d_mask" % tier)
	if shape_texture == null or mask_texture == null:
		return
	size = shape_texture.get_size()
	var mask := Sprite2D.new()
	mask.texture = mask_texture
	mask.centered = false
	mask.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	add_child(mask)
	var raw_stats: Array = gem.get("raw_stats", [1, 0, 0, 0, 0])
	var total := 0.0
	for value in raw_stats:
		total += maxf(0.0, float(value))
	var facets: Array = gem.get("facet_positions", [])
	var accumulated := 0.0
	var facet_index := 0
	for stat_index in mini(raw_stats.size(), 5):
		accumulated += maxf(0.0, float(raw_stats[stat_index])) / maxf(total, 0.0001) * 12.0
		while facet_index < mini(12, ceili(accumulated)):
			var corner := Sprite2D.new()
			corner.texture = SourceMenuArt.texture(CORNERS[stat_index])
			corner.centered = false
			corner.position = shape_texture.get_size() * 0.5
			corner.rotation_degrees = float(facets[facet_index]) if facet_index < facets.size() else float(facet_index * 30)
			mask.add_child(corner)
			facet_index += 1
	var outline := Sprite2D.new()
	outline.texture = shape_texture
	outline.centered = false
	mask.add_child(outline)
	if CampaignSkillGemService.is_skill(gem):
		var icon := SourceMenuArt.image(self, String(gem.get("skill_icon", "")), Vector2(14, 12))
		if icon != null:
			icon.name = "SkillGemIcon"
			icon.scale = Vector2.ONE * 0.38
			icon.modulate.a = 0.95
		if icon == null:
			var unknown := Label.new()
			unknown.text = "?"
			unknown.position = Vector2(17, 7)
			unknown.add_theme_font_override("font", preload("res://content/base/fonts/BurbinCasual.ttf"))
			unknown.add_theme_font_size_override("font_size", 25)
			unknown.add_theme_color_override("font_outline_color", Color8(25, 28, 37))
			unknown.add_theme_constant_override("outline_size", 4)
			unknown.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(unknown)
		var rank := Label.new()
		rank.name = "SkillGemLevel"
		rank.text = str(int(gem.get("skill_level", 1)))
		rank.position = Vector2(35, 31)
		rank.add_theme_font_override("font", preload("res://content/base/fonts/BurbinCasual.ttf"))
		rank.add_theme_font_size_override("font_size", 16)
		rank.add_theme_color_override("font_color", Color8(255, 238, 154))
		rank.add_theme_color_override("font_outline_color", Color8(25, 28, 37))
		rank.add_theme_constant_override("outline_size", 5)
		rank.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(rank)
