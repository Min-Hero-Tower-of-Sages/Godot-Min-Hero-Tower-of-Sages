class_name LegacyMoveRolls
extends RefCounted

const BattleRngType = preload("res://src/domain/battle/battle_rng.gd")

var buff_debuff: float
var miss: float
var stun: float
var freeze: float

static func draw(rng: BattleRngType) -> LegacyMoveRolls:
	var rolls := LegacyMoveRolls.new()
	# Exact order from BaseMoveSystem.LoadUpTheQueueAndPlayMoves.
	rolls.buff_debuff = rng.next_percent_value()
	rolls.miss = rng.next_percent_value()
	rolls.stun = rng.next_percent_value()
	rolls.freeze = rng.next_percent_value()
	return rolls

func hits(accuracy_percent: int) -> bool:
	# Legacy misses only when accuracy < roll, so equality is a hit.
	return not float(accuracy_percent) < miss

func applies_buff(chance_percent: int) -> bool:
	return buff_debuff < float(chance_percent)

func applies_stun(chance_percent: int) -> bool:
	return float(chance_percent) > stun

func applies_freeze(chance_percent: int) -> bool:
	return float(chance_percent) > freeze
