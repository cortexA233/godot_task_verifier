# PDF Score Report Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a one-page executive PDF report for RoboBlast verifier score JSON, available as both a standalone renderer and `run_grader.py --pdf-report`.

**Architecture:** Keep scoring JSON as the source of truth. Add a focused `report_renderer.py` module that renders a parsed result dictionary with ReportLab, a small `render_report.py` CLI wrapper, and a thin `run_grader.py` integration that calls the renderer after JSON output is written.

**Tech Stack:** Python stdlib, ReportLab from the bundled Codex runtime, unittest, Poppler `pdftoppm` for visual verification.

---

### Task 1: Add PDF Renderer Tests

**Files:**
- Create: `C:\recent_project\roboblast-grenade-verifier\tests\test_report_renderer.py`
- Create later: `C:\recent_project\roboblast-grenade-verifier\report_renderer.py`

- [ ] **Step 1: Write failing renderer tests**

Create tests that import `report_renderer`, build representative score data, render a PDF to a temporary path, and assert the file exists, starts with `%PDF`, and key finding selection prioritizes low scores.

- [ ] **Step 2: Run tests to verify failure**

Run:

```powershell
python -m unittest tests.test_report_renderer -v
```

Expected: FAIL because `report_renderer` does not exist yet.

- [ ] **Step 3: Implement minimal renderer**

Create `report_renderer.py` with:

- `ReportRenderError`
- `validate_result(result)`
- `select_key_findings(breakdown, limit=5)`
- `render_pdf_report(result, output_path, source_json_path=None)`

- [ ] **Step 4: Run tests to verify pass**

Run:

```powershell
python -m unittest tests.test_report_renderer -v
```

Expected: PASS.

### Task 2: Add Standalone CLI

**Files:**
- Create: `C:\recent_project\roboblast-grenade-verifier\render_report.py`
- Modify: `C:\recent_project\roboblast-grenade-verifier\tests\test_report_renderer.py`

- [ ] **Step 1: Write failing CLI test**

Add a unittest that invokes `render_report.main([input_json, output_pdf])`, verifies exit code `0`, verifies the PDF exists, and checks `%PDF`.

- [ ] **Step 2: Run test to verify failure**

Run:

```powershell
python -m unittest tests.test_report_renderer -v
```

Expected: FAIL because `render_report.py` does not exist yet.

- [ ] **Step 3: Implement CLI**

Create `render_report.py` that reads JSON, calls `render_pdf_report`, prints the output path, and returns `2` for missing/invalid input.

- [ ] **Step 4: Run tests to verify pass**

Run:

```powershell
python -m unittest tests.test_report_renderer -v
```

Expected: PASS.

### Task 3: Integrate With `run_grader.py`

**Files:**
- Modify: `C:\recent_project\roboblast-grenade-verifier\run_grader.py`
- Modify: `C:\recent_project\roboblast-grenade-verifier\tests\test_run_grader.py`

- [ ] **Step 1: Write failing grader integration test**

Add a unittest that uses the existing fake Godot path, passes `--pdf-report`, and verifies both JSON and PDF are written.

- [ ] **Step 2: Run test to verify failure**

Run:

```powershell
python -m unittest tests.test_run_grader tests.test_report_renderer -v
```

Expected: FAIL because `--pdf-report` is not accepted yet.

- [ ] **Step 3: Add `--pdf-report` option**

Modify `build_parser()` to add `--pdf-report`, and after `write_result(result, args.out)` call `render_pdf_report(result, args.pdf_report, args.out)` when provided.

- [ ] **Step 4: Run tests to verify pass**

Run:

```powershell
python -m unittest tests.test_run_grader tests.test_report_renderer -v
```

Expected: PASS.

### Task 4: Update Documentation

**Files:**
- Modify: `C:\recent_project\roboblast-grenade-verifier\README.md`

- [ ] **Step 1: Add PDF usage docs**

Document both:

```powershell
python C:\recent_project\roboblast-grenade-verifier\render_report.py input.json output.pdf
```

and:

```powershell
python C:\recent_project\roboblast-grenade-verifier\run_grader.py --project ... --godot ... --out score.json --pdf-report score-report.pdf
```

- [ ] **Step 2: Run tests**

Run:

```powershell
python -m unittest discover -s tests -v
```

Expected: PASS.

### Task 5: Generate And Visually Verify Report

**Files:**
- Output: `C:\recent_project\roboblast-grenade-verifier\artifacts\score-report.pdf`
- Output: `C:\recent_project\roboblast-grenade-verifier\tmp\pdfs\score-report-1.png`

- [ ] **Step 1: Render sample PDF**

Run:

```powershell
python C:\recent_project\roboblast-grenade-verifier\render_report.py C:\recent_project\roboblast-grenade-verifier\artifacts\score.json C:\recent_project\roboblast-grenade-verifier\artifacts\score-report.pdf
```

Expected: PDF written.

- [ ] **Step 2: Render PDF page to PNG**

Run Poppler:

```powershell
pdftoppm -png C:\recent_project\roboblast-grenade-verifier\artifacts\score-report.pdf C:\recent_project\roboblast-grenade-verifier\tmp\pdfs\score-report
```

Expected: `score-report-1.png` exists.

- [ ] **Step 3: Inspect PNG**

Open the PNG and verify no clipped text, overlapping bars, unreadable metadata, or broken layout.

- [ ] **Step 4: Final full verification**

Run:

```powershell
python -m unittest discover -s tests -v
python C:\recent_project\roboblast-grenade-verifier\run_grader.py --project C:\recent_project\godot-4-3d-third-person-controller --godot "C:\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64_console.exe" --out C:\recent_project\roboblast-grenade-verifier\artifacts\score-with-report.json --pdf-report C:\recent_project\roboblast-grenade-verifier\artifacts\score-with-report.pdf
```

Expected: tests pass; grader writes JSON and PDF.
