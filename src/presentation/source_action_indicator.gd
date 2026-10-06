extends Control

## ActionAvailbleIcon.as: three-second initial reminder, then the source
## up/down key pulse with a two-second pause between presses.
var _up: TextureRect
var _down: TextureRect
var _current_zone := ""
var _initial_delay: Tween
var _pulse: Tween

func configure(up_symbol: String = "tutorial_pressSpacekey_up", down_symbol: String = "tutorial_pressSpacekey_down") -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_up = SourceMenuArt.image(self, up_symbol, Vector2.ZERO)
	_down = SourceMenuArt.image(self, down_symbol, Vector2.ZERO)
	if _up != null:
		size = _up.texture.get_size()
	if _down != null:
		_down.modulate.a = 0.0
	hide()

func reset_contact() -> void:
	if _initial_delay != null and _initial_delay.is_running():
		_initial_delay.kill()
	if _pulse != null and _pulse.is_running():
		_pulse.kill()
	_current_zone = ""
	if _up != null:
		_up.modulate.a = 1.0
	if _down != null:
		_down.modulate.a = 0.0
	hide()

func set_contact(zone: String, available: bool) -> void:
	visible = available and not zone.is_empty() and _up != null and _down != null
	if not available or zone.is_empty() or zone == _current_zone or _up == null or _down == null:
		return
	reset_contact()
	show()
	_current_zone = zone
	_initial_delay = create_tween()
	_initial_delay.tween_interval(3.0)
	_initial_delay.tween_callback(_start_pulse)

func _start_pulse() -> void:
	_pulse = create_tween().set_loops().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_pulse.tween_property(_down, "modulate:a", 0.0, 0.1)
	_pulse.parallel().tween_property(_up, "modulate:a", 1.0, 0.1)
	_pulse.tween_property(_down, "modulate:a", 1.0, 0.1)
	_pulse.parallel().tween_property(_up, "modulate:a", 0.0, 0.1)
	_pulse.tween_interval(0.3)
	_pulse.tween_property(_down, "modulate:a", 0.0, 0.1)
	_pulse.parallel().tween_property(_up, "modulate:a", 1.0, 0.1)
	_pulse.tween_interval(2.0)
