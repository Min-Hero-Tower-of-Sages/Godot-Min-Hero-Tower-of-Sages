class_name MenuExtensionScreen
extends Control

## Contract for catalog-authored screens. The shell owns routing and passes
## menu-specific state through configure_menu; extensions request another
## menu by stable content ID or request one of the shell's built-in routes.
signal route_requested(route_id: StringName, payload: Dictionary)

func configure_menu(_definition: MenuDefinition, _context: Dictionary = {}) -> void:
	pass
