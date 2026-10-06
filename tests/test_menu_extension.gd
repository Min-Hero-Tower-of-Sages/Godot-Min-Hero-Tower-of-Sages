extends SceneTree

const MenuPack: ContentPackDefinition = preload("res://tests/fixtures/menu_extension_pack.tres")

var failures: Array[String] = []
var received_route: StringName = &""
var received_payload: Dictionary = {}

func _initialize() -> void:
	var catalog := ContentCatalog.new()
	catalog.packs = [MenuPack]
	var validation_errors := catalog.rebuild_index()
	_expect(validation_errors.is_empty(), "the test-only menu pack should pass catalog validation: %s" % " | ".join(validation_errors))
	var menus := catalog.get_menu_definitions()
	_expect(menus.size() == 1 and menus[0].id == &"tests:menu/extension_probe", "catalog lookup should expose a deterministic sorted list of menus")
	var definition := catalog.get_definition(&"tests:menu/extension_probe") as MenuDefinition
	if definition != null:
		var instance := (load(definition.scene_path) as PackedScene).instantiate() as MenuExtensionScreen
		_expect(instance != null, "a valid catalog menu scene must instantiate the required base screen")
		if instance != null:
			instance.route_requested.connect(_capture_route)
			instance.configure_menu(definition, {"fixture": "catalog-context"})
			_expect(instance.received_context.get("fixture", "") == "catalog-context", "the scene contract must deliver a deep-copied context to configure_menu")
			instance.request_test_route(&"tests:menu/extension_probe", {"source": "fixture"})
			_expect(received_route == &"tests:menu/extension_probe" and received_payload.get("source", "") == "fixture", "the scene contract must relay route requests with their payload")
			instance.free()
	var invalid := MenuDefinition.new()
	invalid.id = &"tests:menu/missing_scene"
	invalid.display_name = "Missing Scene"
	invalid.scene_path = "res://tests/fixtures/does_not_exist.tscn"
	_expect(not invalid.validation_errors().is_empty(), "missing authored scenes should produce deterministic validation errors")
	if failures.is_empty():
		print("PASS: menu extension contract")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("FAIL: %d menu extension checks" % failures.size())
		quit(1)

func _capture_route(route_id: StringName, payload: Dictionary) -> void:
	received_route = route_id
	received_payload = payload.duplicate(true)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
