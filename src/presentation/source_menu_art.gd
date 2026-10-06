class_name SourceMenuArt
extends RefCounted

const SYMBOLS_PATH := "res://content/base/art/source_symbols/symbols.json"
const INTERFACE_BAR := preload("res://src/presentation/source_interface_bar.gd")
static var _paths: Dictionary = {}
static var _symbols_loaded := false

static func texture(symbol: String) -> Texture2D:
	if not _symbols_loaded:
		_symbols_loaded = true
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SYMBOLS_PATH))
		if parsed is Dictionary:
			_paths = parsed
		else:
			push_error("Packaged artwork symbol map is missing or invalid: %s" % SYMBOLS_PATH)
	var path := String(_paths.get(symbol, ""))
	# Explicit aliases survive exported PNG remaps and shared numeric Embed
	# names. No directory scan or recovered ActionScript is needed at runtime.
	return load(path) as Texture2D if not path.is_empty() else null

static func image(parent: Node, symbol: String, at: Vector2) -> TextureRect:
	var art := texture(symbol)
	if art == null:
		return null
	var rect := TextureRect.new()
	rect.texture = art
	rect.position = at
	rect.size = art.get_size()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)
	return rect

static func button(parent: Node, symbol: String, at: Vector2, action: Callable) -> TextureButton:
	var art := texture(symbol)
	if art == null:
		return null
	var control := TextureButton.new()
	control.texture_normal = art
	control.texture_hover = art
	control.texture_pressed = art
	control.position = at
	control.size = art.get_size()
	control.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	parent.add_child(control)
	preload("res://src/presentation/source_menu_button_audio.gd").bind_button(control)
	control.pressed.connect(action)
	return control

static func bar(parent: Node, symbol: String, at: Vector2, ratio: float, cap_symbol: String = "") -> Sprite2D:
	var fill_texture := texture(symbol)
	if fill_texture == null:
		return null
	var mask := INTERFACE_BAR.new()
	mask.name = "SourceBar_%s" % symbol
	mask.position = at
	mask.configure(fill_texture, texture(cap_symbol) if not cap_symbol.is_empty() else null, ratio)
	parent.add_child(mask)
	return mask
