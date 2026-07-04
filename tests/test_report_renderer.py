import json
import struct
import sys
import tempfile
import unittest
import zlib
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
        "score_sections": [
            {
                "name": "logic",
                "label": "Logic Score",
                "score": 35,
                "max": 100,
                "categories": [
                    "weapon_controls",
                    "hud_feedback",
                    "trajectory_preview",
                    "projectile_physics",
                    "explosion_gameplay",
                    "visual_audio_polish",
                ],
            },
        ],
        "auxiliary_score_sections": [
            {
                "name": "screenshot_visual",
                "label": "Screenshot Visual Analysis",
                "score": 6,
                "max": 10,
                "used_for_score": False,
                "notes": "projectile visible in rendered screenshot frames; projectile footprint too small in debug_arena",
                "categories": ["debug_arena", "main_scene"],
            },
        ],
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


def tiny_png(red: int, green: int, blue: int) -> bytes:
    def chunk(kind: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + kind
            + data
            + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
        )

    header = struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0)
    pixels = zlib.compress(b"\x00" + bytes([red, green, blue]))
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", pixels) + chunk(b"IEND", b"")


def extract_pdf_text(path: Path) -> str:
    from pypdf import PdfReader

    reader = PdfReader(path)
    return "\n".join(page.extract_text() or "" for page in reader.pages)


def extract_first_page_text(path: Path) -> str:
    from pypdf import PdfReader

    return PdfReader(path).pages[0].extract_text() or ""


def count_pdf_images(path: Path) -> int:
    from pypdf import PdfReader

    total = 0
    for page in PdfReader(path).pages:
        resources = page.get("/Resources", {})
        xobjects = resources.get("/XObject", {})
        for xobject in xobjects.values():
            resolved = xobject.get_object()
            if resolved.get("/Subtype") == "/Image":
                total += 1
    return total


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

    def test_pdf_report_keeps_formal_logic_score_at_one_hundred_points(self):
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / "report.pdf"

            report_renderer.render_pdf_report(sample_result(), output, Path("score.json"))

            pdf_text = extract_pdf_text(output)
            self.assertIn("Score Sections", pdf_text)
            self.assertIn("Logic Score", pdf_text)
            self.assertIn("35/100", pdf_text)
            self.assertNotIn("Visual Score\n5/5", pdf_text)

    def test_pdf_report_shows_auxiliary_screenshot_visual_score_separately(self):
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / "report.pdf"

            report_renderer.render_pdf_report(sample_result(), output, Path("score.json"))

            pdf_text = extract_pdf_text(output)
            self.assertIn("Auxiliary Visual Scores", pdf_text)
            self.assertIn("Screenshot Visual", pdf_text)
            self.assertIn("Analysis", pdf_text)
            self.assertIn("6/10", pdf_text)
            self.assertIn("not counted in 100-point score", pdf_text)

    def test_pdf_report_promotes_screenshot_visual_score_on_first_page(self):
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / "report.pdf"

            report_renderer.render_pdf_report(sample_result(), output, Path("score.json"))

            first_page_text = extract_first_page_text(output)
            self.assertIn("Screenshot visual score", first_page_text)
            self.assertIn("6/10", first_page_text)
            self.assertIn("Auxiliary only", first_page_text)

    def test_pdf_report_embeds_representative_screenshot_evidence(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            debug_image = tmp_path / "screenshot-probe" / "debug_arena" / "attack_010.png"
            main_image = tmp_path / "screenshot-probe" / "main_scene" / "attack_020.png"
            debug_image.parent.mkdir(parents=True)
            main_image.parent.mkdir(parents=True)
            debug_image.write_bytes(tiny_png(255, 0, 0))
            main_image.write_bytes(tiny_png(0, 64, 255))
            output = tmp_path / "report.pdf"
            result = sample_result()
            result["artifacts"]["screenshots"] = [str(debug_image), str(main_image)]

            report_renderer.render_pdf_report(result, output, tmp_path / "score.json")

            pdf_text = extract_pdf_text(output)
            self.assertIn("Screenshot Evidence", pdf_text)
            self.assertIn("debug_arena / attack_010", pdf_text)
            self.assertIn("main_scene / attack_020", pdf_text)
            self.assertGreaterEqual(count_pdf_images(output), 2)

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
