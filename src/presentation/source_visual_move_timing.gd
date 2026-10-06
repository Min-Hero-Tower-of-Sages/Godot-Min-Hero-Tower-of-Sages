extends RefCounted

## Recovered visual classes' m_moveTime setters. Cleanup is an instance-level
## deadline, not the longest independently scheduled sprite tween.
static func move_time(profile: Dictionary) -> float:
	var count := int(profile.get("count", 1))
	var stagger := count * float(profile.get("delay", 0.0))
	match String(profile.get("family", "")):
		"test_white_flash":
			return float(profile.get("duration", 0.4))
		"screen_shake":
			var shakes := maxi(1, int(profile.get("shake_count", 5)))
			return (0.05 + float(profile.get("intensity", 0.05)) * shakes * 0.5) * shakes + 0.15
		"burn_at_target":
			return 1.2
		"rotate_into_target":
			return float(profile.impact_speed) + stagger + 0.15
		"fall_from_top":
			return float(profile.impact_speed) + stagger + 0.15 + float(profile.get("random_start_in_game", 0.0))
		"fall_onto_target":
			var hang := float(profile.get("pre_impact_bounces", 0)) * float(profile.up_down_speed) * 2.0 + 0.2
			return hang + float(profile.impact_speed) + stagger + 0.15
		"rise_out_of_target":
			return float(profile.final_hang_time) + float(profile.rise_speed) + stagger + 0.15
		"fade_through_target":
			return float(profile.final_hang_time) + float(profile.movement_speed) + stagger + 0.15
		"orbit_into_target":
			return float(profile.final_hang_time) + float(profile.hang_time) + float(profile.movement_speed) + (0.0 if bool(profile.get("all_enter_at_same_time", false)) else stagger) - 0.2
	return -1.0
