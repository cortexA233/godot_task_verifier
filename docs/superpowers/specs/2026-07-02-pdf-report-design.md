# PDF Score Report Design

## Context

The RoboBlast grenade verifier currently produces a machine-readable JSON result with a 0-100 score, a pass/fail boolean, Godot version metadata, artifact paths, and per-category breakdown notes. That JSON is the source of truth for benchmark automation, but it is not pleasant for humans to review quickly.

This feature adds a polished one-page PDF report that renders the same score JSON as an executive summary. The PDF is a presentation layer only; it does not change scoring, pass/fail thresholds, or verifier behavior.

## Goals

- Generate a one-page executive PDF report from any verifier score JSON.
- Show the total score, maximum score, pass/fail status, Godot version, and generation timestamp.
- Visualize category scores with aligned horizontal bars.
- Highlight the most important findings, prioritizing zero-score and low-score categories.
- Support both direct rendering from an existing JSON file and automatic PDF creation from `run_grader.py`.
- Keep JSON output unchanged for machine consumers.

## Non-Goals

- No multi-page audit report in this iteration.
- No screenshot or pixel-diff evidence embedding.
- No changes to score weights or Godot verifier probes.
- No web dashboard or interactive report.
- No dependence on candidate project source files after JSON has been produced.

## User-Facing Interface

Two entry points will be supported:

1. Standalone rendering:

```powershell
python C:\recent_project\roboblast-grenade-verifier\render_report.py `
  C:\recent_project\roboblast-grenade-verifier\artifacts\score.json `
  C:\recent_project\roboblast-grenade-verifier\artifacts\score-report.pdf
```

2. Integrated grading:

```powershell
python C:\recent_project\roboblast-grenade-verifier\run_grader.py `
  --project C:\path\to\candidate-project `
  --godot "C:\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64_console.exe" `
  --out C:\recent_project\roboblast-grenade-verifier\artifacts\score.json `
  --pdf-report C:\recent_project\roboblast-grenade-verifier\artifacts\score-report.pdf
```

## Visual Design

The chosen direction is "Executive Summary":

- Single-page printable layout.
- Large total score panel near the top.
- Clear pass/fail badge.
- Compact metadata row for Godot version, JSON source, and generated timestamp.
- Category score bars in the middle of the page.
- Three to five key findings at the bottom.
- Status colors:
  - Green for pass/high score.
  - Amber for partial or mid-range categories.
  - Red for fail/zero-score or severe gaps.
- Conservative typography and spacing so the page remains readable when printed or viewed in a PDF preview.

## Architecture

### `report_renderer.py`

New module responsible for converting a parsed result dictionary into a PDF.

Responsibilities:

- Validate the minimal expected result shape.
- Normalize missing optional fields.
- Select the most important findings from `breakdown`.
- Draw the page using ReportLab.
- Keep layout constants local and easy to adjust.

Proposed public function:

```python
def render_pdf_report(result: dict, output_path: Path, source_json_path: Path | None = None) -> None:
    ...
```

### `render_report.py`

New standalone CLI wrapper.

Responsibilities:

- Read a score JSON file.
- Call `render_pdf_report`.
- Print the output path on success.
- Return a non-zero exit code with a clear message on invalid input.

### `run_grader.py`

Existing grader CLI gains one optional argument:

```text
--pdf-report PATH
```

When provided, `run_grader.py` writes the JSON result as it does today, then renders a PDF from that same in-memory result. If PDF rendering fails after JSON was produced, the grader should return a non-zero infrastructure-style error so automation does not silently lose the human report.

## Data Flow

```text
candidate project
  -> run_grader.py
  -> temporary Godot project copy
  -> headless Godot verifier
  -> score JSON result
  -> optional report_renderer.py
  -> PDF summary
```

Standalone mode starts from the existing score JSON:

```text
score JSON
  -> render_report.py
  -> report_renderer.py
  -> PDF summary
```

## Findings Selection

The PDF should not dump every note verbatim if that makes the page crowded. It will select key findings in this order:

1. Categories with score `0`.
2. Categories below 50 percent of their maximum.
3. Categories below 85 percent of their maximum.
4. Remaining categories only if fewer than three findings were selected.

Each finding will include the category name, `score/max`, and a shortened note. Long notes are wrapped and truncated to preserve the one-page layout.

## Error Handling

- Missing JSON file: fail with a clear CLI error.
- Invalid JSON: fail with a clear CLI error.
- Missing `breakdown`: render the total score metadata and show a single finding noting that no category breakdown was available.
- Missing score fields: treat as invalid input for standalone rendering.
- PDF rendering exception in integrated mode: write/keep the JSON, then return a non-zero exit code and include the rendering error in stderr.

## Testing

Add or extend Python unittest coverage for:

- `report_renderer.py` creates a non-empty PDF from a representative score JSON.
- The generated PDF begins with the `%PDF` header.
- Key low-score findings are selected before high-score findings.
- `render_report.py` exits successfully and writes a PDF for a valid JSON file.
- `run_grader.py --pdf-report` calls the rendering path when the grader succeeds.

Manual verification:

- Generate a PDF from `artifacts/final-ablated-score.json`.
- Render the PDF to PNG using Poppler.
- Inspect the PNG for clipped text, overlapping elements, unreadable bars, and reasonable visual hierarchy.

## Acceptance Criteria

- Existing JSON-only grader behavior still works.
- `render_report.py input.json output.pdf` produces a readable one-page PDF.
- `run_grader.py --pdf-report output.pdf` produces both JSON and PDF.
- The PDF visually presents total score, pass/fail, metadata, category bars, and key findings.
- Unit tests pass.
- A rendered PNG inspection confirms the PDF layout is legible.
