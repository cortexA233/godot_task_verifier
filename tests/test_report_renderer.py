import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

import report_renderer


LONG_EXPLOSION_NOTE = (
    "first nearby target was not damaged; second nearby target was not damaged; "
    "out-of-range target safety not credited because no detonation was observed; "
    "player safety not credited because no detonation was observed; no runtime detonation effects observed"
)


def sample_result() -> dict:
    return {
        "score": 35,
        "max_score": 100,
        "passed": False,
        "godot_version": "4.6-stable (official)",
        "breakdown": [
            {
                "name": "weapon_controls",
                "score": 10,
                "max": 15,
                "notes": "swap_weapons input exists; attack after weapon switch did not create observable runtime nodes",
            },
            {
                "name": "hud_feedback",
                "score": 10,
                "max": 10,
                "notes": "player has visible UI controls; UI control state changed after weapon switch",
            },
            {
                "name": "trajectory_preview",
                "score": 6,
                "max": 30,
                "notes": "visible aiming aid appeared; aim feedback did not update or match projectile direction",
            },
            {
                "name": "projectile_physics",
                "score": 4,
                "max": 15,
                "notes": "grenade attack spawned a nearby 3D node; no spawned node showed clear arc motion; projectile overlapped player body",
                "details": [
                    {
                        "label": "Projectile spawned",
                        "score": 4,
                        "max": 4,
                        "status": "earned",
                        "notes": "grenade attack spawned a nearby 3D node",
                    },
                    {
                        "label": "Arcing motion",
                        "score": 0,
                        "max": 8,
                        "status": "missed",
                        "notes": "no spawned node showed clear arc motion",
                    },
                    {
                        "label": "Player-safe path",
                        "score": 0,
                        "max": 3,
                        "status": "missed",
                        "notes": "projectile overlapped player body",
                    },
                ],
            },
            {
                "name": "explosion_gameplay",
                "score": 0,
                "max": 20,
                "notes": LONG_EXPLOSION_NOTE,
            },
            {
                "name": "visual_audio_polish",
                "score": 5,
                "max": 5,
                "notes": "visible and audio effects appeared",
            },
        ],
        "artifacts": {"log": "score.log", "screenshots": []},
    }


def extract_pdf_text(path: Path) -> str:
    from pypdf import PdfReader

    reader = PdfReader(path)
    return "\n".join(page.extract_text() or "" for page in reader.pages)


class ReportRendererTests(unittest.TestCase):
    def test_render_pdf_report_writes_pdf_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / "report.pdf"

            report_renderer.render_pdf_report(sample_result(), output, Path("score.json"))

            self.assertTrue(output.exists())
            self.assertGreater(output.stat().st_size, 1000)
            self.assertEqual(output.read_bytes()[:4], b"%PDF")

    def test_select_key_findings_prioritizes_zero_scores(self):
        findings = report_renderer.select_key_findings(sample_result()["breakdown"], limit=3)

        self.assertEqual([finding["name"] for finding in findings[:2]], ["explosion_gameplay", "trajectory_preview"])
        self.assertEqual(findings[0]["score"], 0)
        self.assertEqual(findings[0]["notes"], LONG_EXPLOSION_NOTE)

    def test_pdf_report_includes_detailed_item_analysis(self):
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / "report.pdf"

            report_renderer.render_pdf_report(sample_result(), output, Path("score.json"))

            pdf_text = extract_pdf_text(output)
            self.assertIn("Detailed Item Analysis", pdf_text)
            self.assertIn("Projectile Physics Detail", pdf_text)
            self.assertIn("Earned 4/4", pdf_text)
            self.assertIn("Missed 0/8", pdf_text)
            self.assertIn("no spawned node showed clear arc motion", pdf_text)

    def test_pdf_report_shows_suspect_and_floor_review_lines(self):
        result = sample_result()
        result["score"] = 90
        result["passed"] = False
        result["pass_threshold"] = 85
        result["category_floor_failures"] = ["explosion_gameplay below pass floor 10"]
        result["suspect"] = True
        result["suspect_reasons"] = ["global damage sweep detected across explosion trials"]

        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / "report.pdf"

            report_renderer.render_pdf_report(result, output, Path("score.json"))

            pdf_text = extract_pdf_text(output)
            self.assertIn("category pass floors failed", pdf_text)
            self.assertIn("Flagged for manual review", pdf_text)
            self.assertIn("global damage sweep", pdf_text)

    def test_render_report_cli_writes_pdf(self):
        import render_report

        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            source = tmp_path / "score.json"
            output = tmp_path / "report.pdf"
            source.write_text(json.dumps(sample_result()), encoding="utf-8")

            exit_code = render_report.main([str(source), str(output)])

            self.assertEqual(exit_code, 0)
            self.assertTrue(output.exists())
            self.assertEqual(output.read_bytes()[:4], b"%PDF")


if __name__ == "__main__":
    unittest.main()
