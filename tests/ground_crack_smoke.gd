extends SceneTree

const COMBATANT_VIEW_SCRIPT := preload("res://src/presentation/battle_combatant_view.gd")
const MAIN_SCRIPT := preload("res://src/presentation/main.gd")

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	var player := COMBATANT_VIEW_SCRIPT.new() as BattleCombatantView
	player.team = 0
	player.position = Vector2(289.0, 294.0)
	root.add_child(player)
	player.bring_in_ground_damage(0)
	var player_crack := player.ground_damage_sprites.get(0) as Sprite2D
	_check(player_crack != null and player_crack.texture != null and player_crack.centered == false and player_crack.global_position == Vector2(339.0, 264.0) and is_equal_approx(player_crack.scale.x, -1.0) and player_crack.z_index == -1 and is_zero_approx(player_crack.modulate.a), "player ground cracks must use the source slot offset, mirroring, behind-minion depth, and hidden initial alpha")
	_check(int(MAIN_SCRIPT.source_ground_damage_index_for_family("fade_through_target")) == 0 and int(MAIN_SCRIPT.source_ground_damage_index_for_family("burn_at_target")) == 1 and int(MAIN_SCRIPT.source_ground_damage_index_for_family("fall_onto_target")) == 2 and int(MAIN_SCRIPT.source_ground_damage_index_for_family("fall_from_top")) == 2 and int(MAIN_SCRIPT.source_ground_damage_index_for_family("orbit_into_target")) == 3 and int(MAIN_SCRIPT.source_ground_damage_index_for_family("rotate_into_target")) == 3 and int(MAIN_SCRIPT.source_ground_damage_index_for_family("projectile")) == -1, "the six source animation families must select their exact crack sprites")
	player.bring_in_ground_damage(0)
	_check(player.ground_damage_sprites.size() == 1 and player._ground_damage_tweens.size() == 1, "repeated hits must reuse a slot's crack sprite and fade tween")
	var enemy := COMBATANT_VIEW_SCRIPT.new() as BattleCombatantView
	enemy.team = 1
	enemy.position = Vector2(424.0, 294.0)
	root.add_child(enemy)
	enemy.bring_in_ground_damage(3)
	var enemy_crack := enemy.ground_damage_sprites.get(3) as Sprite2D
	_check(enemy_crack != null and enemy_crack.global_position == Vector2(371.0, 256.0) and is_equal_approx(enemy_crack.scale.x, 1.0), "enemy ground cracks must use the opposite source slot offset without player-side mirroring")
	await create_timer(1.0).timeout
	_check(player_crack != null and is_equal_approx(player_crack.modulate.a, 1.0) and enemy_crack != null and is_equal_approx(enemy_crack.modulate.a, 1.0), "ground cracks must fade in after the source delay and persist at full opacity")
	player.queue_free()
	enemy.queue_free()
	await process_frame
	if failures.is_empty():
		print("PASS: source ground-crack overlays (%d checks)" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("FAIL: %d of %d ground-crack checks" % [failures.size(), checks])
		quit(1)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
