extends CanvasLayer

var shade: ColorRect
var _fade: Tween
var _target := 0.0
var _request_serial := 0

func _ready() -> void:
	layer = 9
	shade = ColorRect.new()
	shade.name = "SourceMenuWorldShade"
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0, 0, 0, 0)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.visible = false
	add_child(shade)

func open_menu(view: Control) -> void:
	_request_serial += 1
	_suppress_local_shades(view)
	if not view.child_entered_tree.is_connected(_suppress_local_shades):
		view.child_entered_tree.connect(_suppress_local_shades)
	view.set_meta("source_shared_menu_backdrop", true)
	_fade_to(0.65)

func close_menu() -> void:
	_request_serial += 1
	_fade_to(0.0)

func request_close_menu() -> void:
	_request_serial += 1
	_commit_close_request.call_deferred(_request_serial)

func _commit_close_request(serial: int) -> void:
	if serial == _request_serial:
		_fade_to(0.0)

func reset() -> void:
	_request_serial += 1
	if is_instance_valid(_fade):
		_fade.kill()
	_target = 0.0
	shade.color.a = 0.0
	shade.hide()

func _fade_to(target: float) -> void:
	if is_equal_approx(_target, target):
		return
	_target = target
	if is_instance_valid(_fade):
		_fade.kill()
	shade.show()
	_fade = create_tween()
	_fade.tween_property(shade, "color:a", target, 1.0)
	if target == 0.0:
		_fade.tween_callback(shade.hide)

func _suppress_local_shades(node: Node) -> void:
	# Retain each screen's input-blocking rectangle, but do not multiply world
	# opacity. Rebuilt menu pages are covered by child_entered_tree too.
	if node is ColorRect and not bool(node.get_meta("source_local_menu_overlay", false)) and node.color.r == 0.0 and node.color.g == 0.0 and node.color.b == 0.0:
		node.color.a = 0.0
	for child in node.get_children():
		_suppress_local_shades(child)
