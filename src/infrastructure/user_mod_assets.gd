class_name UserModAssets
extends RefCounted

## Runtime textures for player mods. A sprite is registered under the same
## res:// path the game already uses for battle art, so every view that loads
## minion art by sprite name finds it without knowing about mods.

const MINION_ART := "res://content/base/art/battle/minions/%s.png"
const FONT := preload("res://content/base/fonts/BurbinCasual.ttf")
static var _textures: Array[Texture2D] = []
static var _menu_overrides: Dictionary = {}

static func clear() -> void:
	_textures.clear()
	_menu_overrides.clear()

## SourceMenuArt consults this before the packaged symbol map.
static func menu_texture(symbol: String) -> Texture2D:
	return _menu_overrides.get(symbol) as Texture2D

## Check art without registering any runtime textures (the Workshop uses this
## during Check mod, while the catalog is temporarily assembled).
static func validation_errors(mod_id: String, sprites: Dictionary, badges: Dictionary, prior_sprites: PackedStringArray = []) -> PackedStringArray:
	var errors := PackedStringArray()
	var files := PackedStringArray()
	for request in sprites.values():
		var path := String(request.get("file", ""))
		if not path.is_empty(): files.append(path)
		elif not sprites.has(String(request.get("from", ""))) and not String(request.get("from", "")) in prior_sprites and not ResourceLoader.exists(MINION_ART % String(request.get("from", ""))):
			errors.append("%s: copied minion art %s is missing" % [mod_id, request.get("from", "")])
	for info in badges.values():
		for key in ["badge", "move_badge"]:
			if not String(info.get(key, "")).is_empty(): files.append(String(info[key]))
	for path in files:
		var image := _mod_image(mod_id, path)
		if image == null: errors.append("%s: image %s is missing or is not a readable PNG" % [mod_id, path])
		elif image.get_width() > 512 or image.get_height() > 512: errors.append("%s: image %s must be at most 512 x 512 pixels" % [mod_id, path])
	return errors

static func install_sprite(mod_id: String, virtual_name: String, request: Dictionary) -> String:
	var image: Image
	if not String(request.get("file", "")).is_empty():
		var bytes := UserModRepository.read_file(mod_id, String(request.file))
		image = Image.new()
		if bytes.is_empty() or image.load_png_from_buffer(bytes) != OK:
			return "%s: sprite %s could not be read" % [mod_id, request.file]
	else:
		var source := load(MINION_ART % String(request.get("from", ""))) as Texture2D
		if source == null: return "%s: sprite %s does not exist" % [mod_id, request.get("from", "")]
		image = source.get_image()
		if image == null: return "%s: sprite %s could not be copied" % [mod_id, request.get("from", "")]
		image = image.duplicate() as Image
	if image.is_compressed(): image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	recolor(image, float(request.get("hue_shift", 0.0)), float(request.get("saturation", 1.0)), float(request.get("value", 1.0)))
	var texture := ImageTexture.create_from_image(image)
	texture.take_over_path(MINION_ART % virtual_name)
	_textures.append(texture)
	return ""

static func recolor(image: Image, hue_shift: float, saturation: float, value: float) -> void:
	if is_zero_approx(hue_shift) and is_equal_approx(saturation, 1.0) and is_equal_approx(value, 1.0): return
	for y in image.get_height():
		for x in image.get_width():
			var color := image.get_pixel(x, y)
			if color.a <= 0.0: continue
			var shifted := Color.from_hsv(fposmod(color.h + hue_shift, 1.0), clampf(color.s * saturation, 0.0, 1.0), clampf(color.v * value, 0.0, 1.0), color.a)
			image.set_pixel(x, y, shifted)

## Badges in the shape and size of the recovered type art, with the name
## drawn in, unless the mod supplies its own PNGs.
static func install_type_badges(mod_id: String, type_id: String, info: Dictionary) -> void:
	var key := type_id.get_file()
	var name := String(info.name).to_upper()
	var color: Color = info.color
	var badge := _mod_image(mod_id, String(info.get("badge", "")))
	if badge == null: badge = _badge(_size_of("menus_minionType_fire", Vector2i(80, 20)), color, name, false)
	var move_badge := _mod_image(mod_id, String(info.get("move_badge", "")))
	if move_badge == null: move_badge = _badge(_size_of("moveDescription_type_fire", Vector2i(110, 20)), color, name, true)
	for entry in [["menus_minionType_%s" % key, badge], ["moveDescription_type_%s" % key, move_badge]]:
		var texture := ImageTexture.create_from_image(entry[1])
		_textures.append(texture)
		_menu_overrides[entry[0]] = texture

static func _mod_image(mod_id: String, relative: String) -> Image:
	if relative.is_empty(): return null
	var image := Image.new()
	var bytes := UserModRepository.read_file(mod_id, relative)
	return image if not bytes.is_empty() and image.load_png_from_buffer(bytes) == OK else null

static func _size_of(symbol: String, fallback: Vector2i) -> Vector2i:
	var path := String(_symbol_paths().get(symbol, ""))
	var texture := load(path) as Texture2D if not path.is_empty() else null
	return Vector2i(texture.get_size()) if texture != null else fallback

static var _paths: Dictionary = {}
static func _symbol_paths() -> Dictionary:
	if _paths.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SourceMenuArt.SYMBOLS_PATH))
		if parsed is Dictionary: _paths = parsed
	return _paths

static func _badge(dimensions: Vector2i, color: Color, text: String, fading: bool) -> Image:
	var image := Image.create(dimensions.x, dimensions.y, false, Image.FORMAT_RGBA8)
	var dark := color.darkened(0.55)
	for y in dimensions.y:
		var shade := color.lightened(0.25).lerp(color.darkened(0.2), float(y) / maxf(1.0, dimensions.y - 1.0))
		for x in dimensions.x:
			var alpha := 1.0 if not fading else clampf(float(x) / (dimensions.x * 0.55), 0.0, 1.0)
			var border := x == 0 or y == 0 or x == dimensions.x - 1 or y == dimensions.y - 1
			if not fading and border and (x == 0 or x == dimensions.x - 1) and (y == 0 or y == dimensions.y - 1): continue
			image.set_pixel(x, y, Color(dark if border and not fading else shade, alpha))
	var font_size := maxi(8, dimensions.y - 6)
	var width := _text_width(text, font_size)
	var origin := Vector2(dimensions.x - width - 6.0 if fading else (dimensions.x - width) * 0.5, (dimensions.y - font_size) * 0.5)
	for offset in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1), Vector2(1, 1)]:
		_draw_text(image, text, font_size, origin + offset, dark.darkened(0.4))
	_draw_text(image, text, font_size, origin, Color.WHITE)
	return image

static func _text_width(text: String, font_size: int) -> float:
	return FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x

## Blits glyphs from the font's rasterized cache. This works without a
## rendering viewport, so badges exist before any scene is drawn (and headless).
static func _draw_text(image: Image, text: String, font_size: int, origin: Vector2, color: Color) -> void:
	var server := TextServerManager.get_primary_interface()
	var rid: RID = FONT.get_rids()[0]
	var size := Vector2i(font_size, 0)
	var pen := origin + Vector2(0, server.font_get_ascent(rid, font_size))
	for character in text:
		var glyph := server.font_get_glyph_index(rid, font_size, character.unicode_at(0), 0)
		server.font_render_glyph(rid, size, glyph)
		var uv := server.font_get_glyph_uv_rect(rid, size, glyph)
		if uv.size.x > 0.0 and uv.size.y > 0.0:
			var atlas := server.font_get_texture_image(rid, size, server.font_get_glyph_texture_idx(rid, size, glyph))
			if atlas != null:
				if atlas.is_compressed(): atlas.decompress()
				var offset := server.font_get_glyph_offset(rid, size, glyph)
				var glyph_size := server.font_get_glyph_size(rid, size, glyph)
				var scale := glyph_size / uv.size
				for v in int(uv.size.y):
					for u in int(uv.size.x):
						var coverage := atlas.get_pixel(int(uv.position.x) + u, int(uv.position.y) + v).a
						if coverage <= 0.0: continue
						var target := Vector2i((pen + offset + Vector2(u, v) * scale).round())
						if target.x < 0 or target.y < 0 or target.x >= image.get_width() or target.y >= image.get_height(): continue
						var under := image.get_pixel(target.x, target.y)
						var blended := under.lerp(Color(color, under.a), coverage)
						blended.a = maxf(under.a, coverage * color.a)
						image.set_pixel(target.x, target.y, blended)
		pen.x += server.font_get_glyph_advance(rid, font_size, glyph).x
