import re
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

    def test_pass_threshold_is_consistent_across_code_and_docs(self):
        score_board = (
            ROOT / "verifier_godot" / "__verifier__" / "score_board.gd"
        ).read_text(encoding="utf-8")
        match = re.search(r"PASS_THRESHOLD := (\d+)", score_board)
        self.assertIsNotNone(match, "score_board.gd must define the pass threshold")
        threshold = match.group(1)

        expected_phrase = f"score >= {threshold}"
        documents = [
            ROOT / "report_renderer.py",
            ROOT / "BENCHMARK.md",
            ROOT / "README.md",
            ROOT / "probe_matrix.md",
            ROOT / "evaluation" / "writeup.html",
        ]
        missing = [
            str(path.relative_to(ROOT))
            for path in documents
            if expected_phrase not in path.read_text(encoding="utf-8")
        ]
        self.assertEqual(
            [],
            missing,
            f"These files must state the pass threshold as '{expected_phrase}'",
        )

        stray_pattern = re.compile(r"score >= (\d+)")
        contradictions = []
        for path in documents:
            text = path.read_text(encoding="utf-8")
            for found in stray_pattern.findall(text):
                if found != threshold:
                    contradictions.append(
                        f"{path.relative_to(ROOT)}: score >= {found}"
                    )
        self.assertEqual(
            [],
            contradictions,
            "Documents must not state a conflicting pass threshold",
        )


if __name__ == "__main__":
    unittest.main()
