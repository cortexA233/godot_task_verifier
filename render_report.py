import argparse
import json
import sys
from pathlib import Path

from report_renderer import ReportRenderError, render_pdf_report


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Render a RoboBlast verifier score JSON as a PDF report.")
    parser.add_argument("score_json", type=Path, help="Path to verifier score JSON.")
    parser.add_argument("output_pdf", type=Path, help="Path to write the PDF report.")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        result = json.loads(args.score_json.read_text(encoding="utf-8"))
        render_pdf_report(result, args.output_pdf, args.score_json)
    except FileNotFoundError:
        print(f"Score JSON not found: {args.score_json}", file=sys.stderr)
        return 2
    except json.JSONDecodeError as exc:
        print(f"Invalid score JSON: {exc}", file=sys.stderr)
        return 2
    except (ReportRenderError, RuntimeError) as exc:
        print(f"Could not render PDF report: {exc}", file=sys.stderr)
        return 2
    print(f"Wrote PDF report: {args.output_pdf}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
