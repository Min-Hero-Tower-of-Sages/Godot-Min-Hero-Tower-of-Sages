import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

import strict_content_import as importer


class StrictContentImportTests(unittest.TestCase):
    def test_splits_mixed_references_and_quoted_commas(self):
        self.assertEqual(['"A, B"', 'MinionMoveID.pound_t1', '3'], importer.split_arguments('"A, B", MinionMoveID.pound_t1, 3'))

    def test_base_move_identity_has_explicit_tier(self):
        self.assertEqual("base:move/icy_blast/tier1", importer.move_id("MinionMoveID.icy_blast_t1", Path("source.as"), 7))

    def test_mod_move_identity_is_pack_scoped(self):
        expression = 'Singleton.staticData.ModToMoveID["iHorn_t1"]'
        self.assertEqual("ice_floor:move/ihorn/tier1", importer.move_id(expression, Path("source.as"), 8))

    def test_unknown_expression_is_an_error(self):
        with self.assertRaises(importer.ImportProblem):
            importer.literal("someFallbackValue", {}, Path("source.as"), 9)

    def test_holy_light_typo_is_an_audited_exact_correction(self):
        corrections = []
        result = importer.move_id("MinionMoveID.holyLight_t1", Path("source.as"), 10, corrections)
        self.assertEqual("base:move/holy_light/tier1", result)
        self.assertEqual(1, len(corrections))
        self.assertEqual("MinionMoveID.holyLight_t1", corrections[0]["expression"])

    def test_ice_floor_mud_blast_lookup_resolves_to_existing_base_move(self):
        corrections = []
        expression = 'Singleton.staticData.ModToMoveID["mud_blast_t4"]'
        result = importer.move_id(expression, Path("source.as"), 11, corrections)
        self.assertEqual("base:move/mud_blast/tier4", result)
        self.assertEqual("base:move/mud_blast/tier4", corrections[0]["corrected_id"])

    def test_corrections_do_not_enable_fuzzy_aliases(self):
        corrections = []
        result = importer.move_id("MinionMoveID.HolyLight_t1", Path("source.as"), 12, corrections)
        self.assertEqual("base:move/holylight/tier1", result)
        self.assertNotEqual("base:move/holy_light/tier1", result)
        self.assertEqual([], corrections)

    def test_type_chart_accepts_consistent_duplicates_and_thaw(self):
        source = '''
this.m_typeEffectivenessArray[MinionType.TYPE_FIRE][MinionType.TYPE_ICE] = this.SUPER_EFFECTIVE_MODIFIER;
this.m_typeEffectivenessArray[MinionType.TYPE_FIRE][MinionType.TYPE_ICE] = this.SUPER_EFFECTIVE_MODIFIER;
this.m_typeEffectivenessArray[MinionType.TYPE_UNDEAD][tempModType] = this.NOT_EFFECTIVE_MODIFIER;
'''
        with TemporaryDirectory() as directory:
            scripts = Path(directory)
            path = scripts / "PresistentData" / "StaticData.as"
            path.parent.mkdir(parents=True)
            path.write_text(source, encoding="utf-8")
            chart = importer.import_type_chart(scripts, expected_raw=3, expected_unique=2)
            self.assertEqual(1.5, chart["multipliers"]["base:type/fire>base:type/ice"])
            self.assertEqual(0.66666666667, chart["multipliers"]["base:type/undead>ice_floor:type/thaw"])

    def test_type_chart_rejects_conflicting_duplicate(self):
        source = '''
this.m_typeEffectivenessArray[MinionType.TYPE_FIRE][MinionType.TYPE_ICE] = this.SUPER_EFFECTIVE_MODIFIER;
this.m_typeEffectivenessArray[MinionType.TYPE_FIRE][MinionType.TYPE_ICE] = this.NOT_EFFECTIVE_MODIFIER;
'''
        with TemporaryDirectory() as directory:
            scripts = Path(directory)
            path = scripts / "PresistentData" / "StaticData.as"
            path.parent.mkdir(parents=True)
            path.write_text(source, encoding="utf-8")
            with self.assertRaisesRegex(importer.ImportProblem, "conflicting duplicate"):
                importer.import_type_chart(scripts)


if __name__ == "__main__":
    unittest.main()
