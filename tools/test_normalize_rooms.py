import unittest
from xml.etree import ElementTree

import normalize_rooms


class NormalizeRoomsTests(unittest.TestCase):
    def test_stable_id_does_not_depend_on_numeric_symbol(self):
        self.assertEqual("base:room/level_1_1_a", normalize_rooms.stable_room_id("Utilities.LevelContainer_Level_1_1_A"))

    def test_xml_attributes_are_preserved_as_source_strings(self):
        element = ElementTree.fromstring('<room><item xPos="12.5" rotation="-90" /></room>')
        data = normalize_rooms.element_to_data(element)
        self.assertEqual("12.5", data["children"][0]["attributes"]["xPos"])
        self.assertEqual("-90", data["children"][0]["attributes"]["rotation"])


if __name__ == "__main__":
    unittest.main()
