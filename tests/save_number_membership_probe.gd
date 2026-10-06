extends SceneTree

func _initialize() -> void:
	var decoded: Variant = JSON.parse_string("[0, 1]")
	print("JSON numeric type: ", typeof(decoded[0]), "; int membership: ", 0 in decoded, "; scalar equality: ", decoded[0] == 0)
	quit(0)
