extends Control

## A question from another player (arena challenge, double battle invite),
## shown at the top of the screen over whatever is open. It does not block the
## game behind it; it answers "no" by itself when its time runs out.

signal answered(accepted: bool)

const PANEL_SIZE := Vector2(400.0, 112.0)

var _panel: Panel
var _timer_bar: ColorRect
var _seconds := 15.0
var _left := 15.0
var _done := false

func configure(text: String, accept_text: String, decline_text: String, seconds: float, accent: Color) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_seconds = seconds
	_left = seconds
	_panel = MultiplayerUi.panel(self, Vector2((MultiplayerUi.SCREEN_SIZE.x - PANEL_SIZE.x) * 0.5, -PANEL_SIZE.y), PANEL_SIZE)
	_panel.name = "PromptPanel"
	var stripe := ColorRect.new()
	stripe.color = accent
	stripe.position = Vector2(4.0, 4.0)
	stripe.size = Vector2(6.0, PANEL_SIZE.y - 8.0)
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(stripe)
	var message := MultiplayerUi.label(_panel, text, Vector2(22.0, 10.0), Vector2(PANEL_SIZE.x - 36.0, 44.0), 16, MultiplayerUi.INK)
	message.name = "Message"
	var accept := MultiplayerUi.button(_panel, accept_text, Vector2(PANEL_SIZE.x - 192.0, 60.0), Vector2(170.0, 34.0), _answer.bind(true), 16)
	accept.name = "AcceptButton"
	MultiplayerUi.button(_panel, decline_text, Vector2(22.0, 60.0), Vector2(150.0, 34.0), _answer.bind(false), 16).name = "DeclineButton"
	_timer_bar = ColorRect.new()
	_timer_bar.color = MultiplayerUi.GOLD
	_timer_bar.position = Vector2(14.0, PANEL_SIZE.y - 10.0)
	_timer_bar.size = Vector2(PANEL_SIZE.x - 28.0, 3.0)
	_timer_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_timer_bar)
	create_tween().tween_property(_panel, "position:y", 12.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _process(delta: float) -> void:
	if _done:
		return
	_left -= delta
	_timer_bar.size.x = (PANEL_SIZE.x - 28.0) * clampf(_left / _seconds, 0.0, 1.0)
	if _left <= 0.0:
		_answer(false)

func _answer(accepted: bool) -> void:
	if _done:
		return
	_done = true
	answered.emit(accepted)
	dismiss()

## Slide away (answered, expired, or withdrawn by the host).
func dismiss() -> void:
	_done = true
	if not is_instance_valid(_panel):
		queue_free()
		return
	var leave := create_tween()
	leave.tween_property(_panel, "position:y", -PANEL_SIZE.y - 10.0, 0.25)
	leave.tween_callback(queue_free)
