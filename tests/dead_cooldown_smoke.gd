extends SceneTree

const TEST_RUNNER := preload("res://tests/test_runner.gd")

func _initialize() -> void:
	var runner: Node = TEST_RUNNER.new()
	runner.call("_test_defeated_cooldowns_do_not_tick")
	var failures: Array = runner.get("failures")
	var checks := int(runner.get("checks"))
	runner.free()
	if failures.is_empty():
		print("PASS: defeated cooldown preservation (%d check)" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error(String(failure))
		print("FAIL: defeated cooldown preservation (%d checks)" % checks)
		quit(1)
