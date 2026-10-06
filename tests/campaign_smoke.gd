extends SceneTree

const TestRunner = preload("res://tests/test_runner.gd")

func _initialize() -> void:
	var runner := TestRunner.new()
	if not runner.has_method("_test_campaign_catalog_and_progression") or not runner.has_method("_test_save_validation"):
		push_error("focused campaign tests did not compile")
		runner.free()
		quit(1)
		return
	runner._test_save_validation()
	runner._test_campaign_catalog_and_progression()
	if runner.failures.is_empty():
		print("PASS: %d campaign/save checks" % runner.checks)
		runner.free()
		quit(0)
		return
	for failure in runner.failures:
		push_error(failure)
	print("FAIL: %d of %d campaign/save checks" % [runner.failures.size(), runner.checks])
	runner.free()
	quit(1)
