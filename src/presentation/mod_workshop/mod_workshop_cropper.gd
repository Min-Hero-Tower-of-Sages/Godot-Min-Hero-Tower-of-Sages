class_name ModWorkshopCropper
extends Control

## Frames an imported picture before it goes into a mod: drag to move it,
## scroll or use the slider to zoom in and out, mirror it, then keep what is
## inside the frame. Zooming out past the picture's edges leaves transparent
## space, so small art can be centred with room around it.

signal cropped(image: Image)

const CANVAS := Vector2(330, 330)
const MAX_SOURCE := 4096
## Zoom slider range, in powers of two around "whole picture fits the frame".
const ZOOM_MIN := -2.0
const ZOOM_MAX := 3.0

var _source: Image
var _source_texture: ImageTexture
## Output: `fixed_size` for badges; otherwise a square of the cropped area's
## own resolution, capped at `max_side`.
var _fixed_size := Vector2i.ZERO
var _max_side := 512
var _frame := Rect2()
var _fit_scale := 1.0
var _zoom := 0.0
var _offset := Vector2.ZERO ## Picture centre, relative to the frame centre, in canvas pixels.
var _mirror := false
var _dragging := false
var _canvas: Control
var _zoom_slider: HSlider
var _preview: TextureRect
var _size_note: Label
var _preview_timer: Timer

## `aspect`: the frame's width / height. `fixed_size` (optional) forces the
## output size, e.g. a type badge.
func open(title: String, image: Image, aspect: float = 1.0, fixed_size := Vector2i.ZERO, max_side := 512) -> void:
	_source = image
	if _source.is_compressed(): _source.decompress()
	_source.convert(Image.FORMAT_RGBA8)
	_source_texture = ImageTexture.create_from_image(_source)
	_fixed_size = fixed_size
	_max_side = max_side
	var frame_size := Vector2(CANVAS.x - 40, (CANVAS.x - 40) / aspect)
	if frame_size.y > CANVAS.y - 40: frame_size = Vector2((CANVAS.y - 40) * aspect, CANVAS.y - 40)
	_frame = Rect2((CANVAS - frame_size) * 0.5, frame_size)
	_fit_scale = minf(frame_size.x / _source.get_width(), frame_size.y / _source.get_height())
	_build(title)
	_refresh()

static func load_picture(path: String) -> Dictionary:
	var image := Image.load_from_file(path)
	if image == null or image.is_empty(): return {"ok": false, "message": "That file is not a readable image."}
	if image.get_width() > MAX_SOURCE or image.get_height() > MAX_SOURCE:
		return {"ok": false, "message": "Pictures can be at most %d x %d pixels before cropping." % [MAX_SOURCE, MAX_SOURCE]}
	return {"ok": true, "image": image}

func _build(title: String) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 50
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0, 0, 0, 0.6)
	add_child(shade)
	var panel := PanelContainer.new()
	panel.position = Vector2(55, 26)
	panel.size = Vector2(590, 470)
	add_child(panel)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	panel.add_child(rows)
	var heading := Label.new()
	heading.text = title
	heading.uppercase = true
	heading.theme_type_variation = &"HeaderLabel"
	rows.add_child(heading)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 12)
	rows.add_child(columns)
	var well := PanelContainer.new()
	well.add_theme_stylebox_override("panel", ModWorkshopForm.inset_style())
	well.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	columns.add_child(well)
	_canvas = Control.new()
	_canvas.name = "CropCanvas"
	_canvas.custom_minimum_size = CANVAS
	_canvas.clip_contents = true
	_canvas.mouse_default_cursor_shape = Control.CURSOR_MOVE
	_canvas.draw.connect(_draw_canvas)
	_canvas.gui_input.connect(_canvas_input)
	well.add_child(_canvas)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 6)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(side)
	_caption("Result", side)
	var preview_well := PanelContainer.new()
	preview_well.add_theme_stylebox_override("panel", ModWorkshopForm.card_style())
	side.add_child(preview_well)
	_preview = TextureRect.new()
	_preview.custom_minimum_size = Vector2(150, 150) if _fixed_size == Vector2i.ZERO else Vector2(150, 150.0 * _fixed_size.y / maxf(1.0, _fixed_size.x))
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview_well.add_child(_preview)
	_size_note = Label.new()
	_size_note.add_theme_font_size_override("font_size", 12)
	_size_note.add_theme_color_override("font_color", ModWorkshopForm.MUTED)
	side.add_child(_size_note)
	_caption("Zoom", side)
	var zoom_row := HBoxContainer.new()
	side.add_child(zoom_row)
	_small_button("-", func() -> void: _set_zoom(_zoom - 0.25), zoom_row)
	_zoom_slider = HSlider.new()
	_zoom_slider.name = "ZoomSlider"
	_zoom_slider.min_value = ZOOM_MIN
	_zoom_slider.max_value = ZOOM_MAX
	_zoom_slider.step = 0.01
	_zoom_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_zoom_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_zoom_slider.value_changed.connect(func(value: float) -> void: _set_zoom(value))
	zoom_row.add_child(_zoom_slider)
	_small_button("+", func() -> void: _set_zoom(_zoom + 0.25), zoom_row)
	var quick := HFlowContainer.new()
	quick.add_theme_constant_override("h_separation", 4)
	quick.add_theme_constant_override("v_separation", 4)
	side.add_child(quick)
	_small_button("Fit", func() -> void:
		_offset = Vector2.ZERO
		_set_zoom(0.0), quick).tooltip_text = "Show the whole picture inside the frame"
	_small_button("Fill", func() -> void:
		_offset = Vector2.ZERO
		var fill := maxf(_frame.size.x / _source.get_width(), _frame.size.y / _source.get_height())
		_set_zoom(log(fill / _fit_scale) / log(2.0)), quick).tooltip_text = "Zoom until the picture covers the whole frame"
	_small_button("Centre", func() -> void:
		_offset = Vector2.ZERO
		_refresh(), quick)
	var mirror := CheckBox.new()
	mirror.text = "Mirror"
	mirror.tooltip_text = "Flip left-right (minion art faces right in battle)"
	mirror.toggled.connect(func(value: bool) -> void:
		_mirror = value
		_refresh())
	side.add_child(mirror)
	var hint := Label.new()
	hint.text = "Drag the picture to move it. Scroll or use the slider to zoom; zooming out leaves see-through space around it."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = 150
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", ModWorkshopForm.MUTED)
	side.add_child(hint)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 6)
	rows.add_child(buttons)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(queue_free)
	buttons.add_child(cancel)
	var keep := Button.new()
	keep.text = "Use this picture"
	keep.theme_type_variation = &"GreenButton"
	keep.pressed.connect(func() -> void:
		cropped.emit(result())
		queue_free())
	buttons.add_child(keep)
	_preview_timer = Timer.new()
	_preview_timer.one_shot = true
	_preview_timer.wait_time = 0.06
	_preview_timer.timeout.connect(_update_preview)
	add_child(_preview_timer)

func _caption(text: String, parent: Control) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", ModWorkshopForm.GOLD)
	parent.add_child(label)

func _small_button(text: String, callback: Callable, parent: Control) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _scale() -> float:
	return _fit_scale * pow(2.0, _zoom)

## The picture's rectangle on the canvas.
func _picture_rect() -> Rect2:
	var shown := Vector2(_source.get_width(), _source.get_height()) * _scale()
	return Rect2(_frame.get_center() + _offset - shown * 0.5, shown)

func _set_zoom(value: float, anchor: Vector2 = Vector2.INF) -> void:
	var before := _scale()
	_zoom = clampf(value, ZOOM_MIN, ZOOM_MAX)
	# Zoom around the pointer (or the frame centre): keep that point still.
	var pivot := _frame.get_center() if anchor == Vector2.INF else anchor
	var centre := _frame.get_center() + _offset
	_offset = pivot + (centre - pivot) * (_scale() / before) - _frame.get_center()
	_refresh()

func _refresh() -> void:
	if _zoom_slider != null: _zoom_slider.set_value_no_signal(_zoom)
	if _canvas != null: _canvas.queue_redraw()
	if _preview_timer != null and _preview_timer.is_inside_tree(): _preview_timer.start()
	else: _update_preview()

func _update_preview() -> void:
	var image := result()
	_preview.texture = ImageTexture.create_from_image(image)
	_size_note.text = "%d x %d pixels" % [image.get_width(), image.get_height()]

func _canvas_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			_dragging = event.pressed
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP: _set_zoom(_zoom + 0.15, event.position)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN: _set_zoom(_zoom - 0.15, event.position)
		_canvas.accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_offset += event.relative
		_refresh()
		_canvas.accept_event()
	elif event is InputEventMagnifyGesture:
		_set_zoom(_zoom + log(event.factor) / log(2.0), event.position)

func _draw_canvas() -> void:
	# Checkerboard, so transparent areas read as transparent.
	var cell := 12.0
	for y in int(ceil(CANVAS.y / cell)):
		for x in int(ceil(CANVAS.x / cell)):
			_canvas.draw_rect(Rect2(x * cell, y * cell, cell, cell), Color8(58, 63, 72) if (x + y) % 2 == 0 else Color8(48, 52, 59))
	var shown := _picture_rect()
	if _mirror: _canvas.draw_texture_rect(_source_texture, Rect2(shown.position + Vector2(shown.size.x, 0), Vector2(-shown.size.x, shown.size.y)), false)
	else: _canvas.draw_texture_rect(_source_texture, shown, false)
	# Dim everything outside the frame.
	var dim := Color(0.05, 0.06, 0.08, 0.62)
	_canvas.draw_rect(Rect2(0, 0, CANVAS.x, _frame.position.y), dim)
	_canvas.draw_rect(Rect2(0, _frame.end.y, CANVAS.x, CANVAS.y - _frame.end.y), dim)
	_canvas.draw_rect(Rect2(0, _frame.position.y, _frame.position.x, _frame.size.y), dim)
	_canvas.draw_rect(Rect2(_frame.end.x, _frame.position.y, CANVAS.x - _frame.end.x, _frame.size.y), dim)
	for third in [1.0 / 3.0, 2.0 / 3.0]:
		var x: float = _frame.position.x + _frame.size.x * third
		var y: float = _frame.position.y + _frame.size.y * third
		_canvas.draw_line(Vector2(x, _frame.position.y), Vector2(x, _frame.end.y), Color(1, 1, 1, 0.18))
		_canvas.draw_line(Vector2(_frame.position.x, y), Vector2(_frame.end.x, y), Color(1, 1, 1, 0.18))
	_canvas.draw_rect(_frame.grow(1), ModWorkshopForm.DEEP, false, 2.0)
	_canvas.draw_rect(_frame, Color.WHITE, false, 2.0)

## The framed area as an image: transparent where the frame reaches past the
## picture, mirrored if asked.
func result() -> Image:
	var scale := _scale()
	var shown := _picture_rect()
	# The frame in source pixels.
	var source_rect := Rect2((_frame.position - shown.position) / scale, _frame.size / scale)
	var out_size := _fixed_size
	if out_size == Vector2i.ZERO:
		var side := clampi(roundi(source_rect.size.x), 16, _max_side)
		out_size = Vector2i(side, roundi(side * _frame.size.y / _frame.size.x))
	var canvas := Image.create_empty(out_size.x, out_size.y, false, Image.FORMAT_RGBA8)
	var per_pixel := float(out_size.x) / source_rect.size.x
	var inside := source_rect.intersection(Rect2(Vector2.ZERO, Vector2(_source.get_size())))
	if inside.size.x >= 0.5 and inside.size.y >= 0.5:
		var from := Rect2i(Vector2i(inside.position.floor()), Vector2i.ZERO)
		from.end = Vector2i(inside.end.ceil()).min(_source.get_size())
		var piece := _source.get_region(from)
		var piece_size := (Vector2(from.size) * per_pixel).round()
		piece.resize(maxi(1, int(piece_size.x)), maxi(1, int(piece_size.y)), Image.INTERPOLATE_LANCZOS if per_pixel < 1.0 else Image.INTERPOLATE_BILINEAR)
		var at := Vector2i(((Vector2(from.position) - source_rect.position) * per_pixel).round())
		canvas.blit_rect(piece, Rect2i(Vector2i.ZERO, piece.get_size()), at)
	if _mirror: canvas.flip_x()
	return canvas

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		queue_free()
