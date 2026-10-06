extends MenuExtensionScreen

var received_context: Dictionary = {}

func configure_menu(_definition: MenuDefinition, context: Dictionary = {}) -> void:
	received_context = context.duplicate(true)

func request_test_route(route_id: StringName, payload: Dictionary = {}) -> void:
	route_requested.emit(route_id, payload)
