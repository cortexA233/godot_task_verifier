import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class RepositoryConsistencyTests(unittest.TestCase):
    def test_repository_does_not_reference_godot_47(self):
        skipped_dirs = {
            ".git",
            ".godot",
            ".worktrees",
            "__pycache__",
            "artifacts",
            "tmp",
        }
        offenders = []

        for path in ROOT.rglob("*"):
            if not path.is_file():
                continue
            if any(part in skipped_dirs for part in path.relative_to(ROOT).parts):
                continue
            try:
                text = path.read_text(encoding="utf-8")
            except UnicodeDecodeError:
                continue
            forbidden_version = "4" + ".7"
            forbidden_path = "Godot_v4" + ".7"
            if forbidden_version in text or forbidden_path in text:
                offenders.append(str(path.relative_to(ROOT)))

        self.assertEqual([], offenders)


if __name__ == "__main__":
    unittest.main()
