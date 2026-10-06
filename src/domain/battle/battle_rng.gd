class_name BattleRng
extends RefCounted

const MASK_31 := 0x7fffffff
var _state: int
var _scripted: Array[int] = []
var _script_index: int = 0

func _init(p_seed: int = 1, scripted_values: Array[int] = []) -> void:
	_state = p_seed & MASK_31
	if _state == 0: _state = 1
	_scripted = scripted_values.duplicate()

func next_int(max_exclusive: int) -> int:
	assert(max_exclusive > 0)
	if _script_index < _scripted.size():
		var value := _scripted[_script_index]
		_script_index += 1
		return posmod(value, max_exclusive)
	_state = (1103515245 * _state + 12345) & MASK_31
	return _state % max_exclusive

func roll_percent(chance: int) -> bool:
	return next_int(100) < clampi(chance, 0, 100)

func next_unit() -> float:
	# Six decimal places are enough to force every relevant legacy boundary in
	# deterministic fixtures. Scripted values use the same 0..999999 scale.
	return float(next_int(1_000_000)) / 1_000_000.0

func next_percent_value() -> float:
	return next_unit() * 100.0

func snapshot() -> Dictionary:
	return {"state": _state, "script_index": _script_index, "scripted": _scripted.duplicate()}

func restore(data: Dictionary) -> void:
	_state = int(data.state)
	_script_index = int(data.script_index)
	_scripted.assign(data.scripted)
