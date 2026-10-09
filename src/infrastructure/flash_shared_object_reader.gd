class_name FlashSharedObjectReader
extends RefCounted

## Read-only, bounded AMF decoder. Never instantiates ActionScript classes.
## Min Hero saves flatten their fields, so compound/externalizable values are
## rejected instead of evaluating code or accepting cyclic object graphs.
const MAX_BYTES := 8 * 1024 * 1024
const MAX_FIELDS := 50000
var _stream := StreamPeerBuffer.new()
var _strings: Array[String] = []
var _error := ""

func read_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "message": "Cannot read the selected Flash save."}
	if file.get_length() > MAX_BYTES:
		return {"ok": false, "message": "Flash save exceeds the 8 MiB safety limit."}
	var bytes := file.get_buffer(file.get_length())
	file.close()
	return decode(bytes)

func decode(bytes: PackedByteArray) -> Dictionary:
	_error = ""
	_strings.clear()
	_stream.data_array = bytes
	_stream.big_endian = true
	_stream.seek(0)
	if bytes.size() < 24 or bytes.size() > MAX_BYTES:
		return {"ok": false, "message": "Invalid Flash SharedObject size."}
	if _uint(2) != 0x00bf:
		return {"ok": false, "message": "Choose a .sol Flash SharedObject file."}
	var declared := _uint(4)
	if declared != bytes.size() - 6:
		return {"ok": false, "message": "Flash save is truncated or its length is invalid."}
	if _text(4) != "TCSO" or _uint(2) != 4 or _uint(4) != 0:
		return {"ok": false, "message": "Invalid SharedObject header."}
	var name := _text(_uint(2))
	var encoding := _uint(4)
	if encoding not in [0, 3]:
		return {"ok": false, "message": "Unsupported Flash object encoding."}
	var fields: Dictionary = {}
	while _remaining() > 0 and _error.is_empty():
		if fields.size() >= MAX_FIELDS:
			_error = "Too many Flash save fields."
			break
		var key := _string3() if encoding == 3 else _text(_uint(2))
		if key.is_empty() or fields.has(key):
			_error = "Empty or duplicate Flash save field."
			break
		fields[key] = _value3() if encoding == 3 else _value0()
		if _uint(1) != 0:
			_error = "Invalid Flash save field terminator."
	if not _error.is_empty():
		return {"ok": false, "message": _error}
	return {"ok": true, "name": name, "data": fields, "encoding": encoding}

func _value3() -> Variant:
	var marker := _uint(1)
	match marker:
		0, 1: return null
		2: return false
		3: return true
		4:
			var value := _u29()
			return value - 0x20000000 if value & 0x10000000 else value
		5: return _double()
		6: return _string3()
	_error = "Unsupported compound AMF3 value (%d); expected a flat Min Hero save." % marker
	return null

func _value0() -> Variant:
	var marker := _uint(1)
	match marker:
		0: return _double()
		1:
			var value := _uint(1)
			if value > 1: _error = "Invalid AMF boolean."
			return value == 1
		2: return _text(_uint(2))
		5, 6: return null
		12: return _text(_uint(4))
		17: return _value3()
	_error = "Unsupported compound AMF0 value (%d); expected a flat Min Hero save." % marker
	return null

func _string3() -> String:
	var header := _u29()
	if not header & 1:
		var index := header >> 1
		if index >= _strings.size():
			_error = "Invalid AMF string reference."
			return ""
		return _strings[index]
	var value := _text(header >> 1)
	if not value.is_empty(): _strings.append(value)
	return value

func _u29() -> int:
	var value := 0
	for index in 4:
		var byte := _uint(1)
		if index == 3: return (value << 8) | byte
		value = (value << 7) | (byte & 127)
		if byte < 128: return value
	return value

func _double() -> float:
	if _remaining() < 8:
		_error = "Truncated Flash save number."
		return 0.0
	var value := _stream.get_double()
	if not is_finite(value): _error = "Non-finite Flash save number."
	return value

func _uint(length: int) -> int:
	if _remaining() < length:
		_error = "Truncated Flash save."
		return 0
	match length:
		1: return _stream.get_u8()
		2: return _stream.get_u16()
		4: return _stream.get_u32()
	return 0

func _text(length: int) -> String:
	if length < 0 or length > _remaining():
		_error = "Truncated Flash save string."
		return ""
	return (_stream.get_data(length)[1] as PackedByteArray).get_string_from_utf8()

func _remaining() -> int:
	return _stream.get_size() - _stream.get_position()
