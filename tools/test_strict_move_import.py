import unittest

import strict_move_import as importer


class StrictMoveImportTests(unittest.TestCase):
    def test_actionscript_int_truncates_toward_zero(self):
        self.assertEqual(6, importer.as_int(10 * 0.66))
        self.assertEqual(-6, importer.as_int(-10 * 0.66))

    def test_defaults_match_base_minion_move(self):
        move = importer.default_move()
        self.assertEqual(100, move["accuracy"])
        self.assertEqual(3, move["over_time_turns"])
        self.assertEqual(1, move["energy_used"])
        self.assertEqual("moveIcon_needleBarrage", move["icon"])

    def test_copy_is_shallow_for_actionscript_vectors(self):
        source = importer.default_move()
        copied = source.copy()
        copied["buff_stats"].append(3)
        self.assertEqual([3], source["buff_stats"])

    def test_only_group_reflect_is_an_expected_unconstructed_identity(self):
        self.assertEqual({135, 136, 137, 138, 139}, importer.EXPECTED_UNCONSTRUCTED_IDS)

    def test_effect_order_preserves_energy_before_accuracy_and_actor_after_targets(self):
        move = importer.default_move()
        move.update(id="base:move/test/tier1", energy_percent_restored=20, damage=5, healing=4,
                    self_damage=3, buff_stats=[1], buff_self=True, buff_stages=2)
        effects = importer.normalize_effects(move, {1: "base:stat/attack"})
        self.assertEqual(["energy", "damage", "heal", "self_damage", "stat_stage"], [effect["kind_name"] for effect in effects])
        self.assertEqual("before_accuracy", next(name for name, value in importer.PHASE.items() if value == effects[0]["phase"]))
        self.assertEqual("actor_after_targets", next(name for name, value in importer.PHASE.items() if value == effects[-1]["phase"]))

    def test_passive_critical_chance_is_not_dropped(self):
        move = importer.default_move()
        move.update(id="base:move/focus/tier1", is_passive=True, extra_crit_chance=5)
        effects = importer.normalize_effects(move, {})
        self.assertEqual(["critical_chance"], [effect["kind_name"] for effect in effects])


if __name__ == "__main__":
    unittest.main()
