import tempfile
import unittest
from pathlib import Path

import reference_inventory


class ReferenceInventoryTests(unittest.TestCase):
    def test_reads_loose_git_ref_without_mutating_repository(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / ".git" / "refs" / "heads").mkdir(parents=True)
            (root / ".git" / "HEAD").write_text("ref: refs/heads/main\n", encoding="utf-8")
            (root / ".git" / "refs" / "heads" / "main").write_text("abc123\n", encoding="utf-8")
            self.assertEqual("abc123", reference_inventory.git_revision_from_files(root))

    def test_classifies_known_subsystems(self):
        self.assertEqual("room", reference_inventory.classify(Path("scripts/TopDown/Levels/Lobby.as")))
        self.assertEqual("move", reference_inventory.classify(Path("scripts/Minions/MinionMove/Move.as")))


if __name__ == "__main__":
    unittest.main()
