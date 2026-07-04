from __future__ import annotations

from datetime import datetime
from pathlib import Path

try:
    from reportlab.lib import colors
    from reportlab.lib.enums import TA_CENTER, TA_LEFT
    from reportlab.lib.pagesizes import letter
    from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
    from reportlab.lib.units import inch
    from reportlab.platypus import Flowable, KeepTogether, Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle
except ImportError as exc:  # pragma: no cover - exercised only when dependency is missing.
    raise RuntimeError(
        "ReportLab is required to render PDF reports. Use the bundled Codex Python runtime or install reportlab."
    ) from exc


class ReportRenderError(ValueError):
    pass


STATUS_GREEN = colors.HexColor("#16a34a")
STATUS_AMBER = colors.HexColor("#d97706")
STATUS_RED = colors.HexColor("#dc2626")
INK = colors.HexColor("#0f172a")
MUTED = colors.HexColor("#64748b")
LINE = colors.HexColor("#e2e8f0")
PANEL = colors.HexColor("#f8fafc")


def validate_result(result: dict) -> None:
    if not isinstance(result, dict):
        raise ReportRenderError("Score result must be a JSON object.")
    for key in ("score", "max_score"):
        if key not in result:
            raise ReportRenderError(f"Score result is missing required field: {key}")
        try:
            int(result[key])
        except (TypeError, ValueError) as exc:
            raise ReportRenderError(f"Score result field must be numeric: {key}") from exc


def select_key_findings(breakdown: list[dict] | None, limit: int = 5) -> list[dict]:
    if not breakdown:
        return [{"name": "summary", "score": 0, "max": 0, "notes": "No category breakdown was available."}]

    normalized = [_normalize_item(item) for item in breakdown]
    groups = [
        [item for item in normalized if item["max"] > 0 and item["score"] == 0],
        [item for item in normalized if _ratio(item) < 0.5 and item["score"] != 0],
        [item for item in normalized if 0.5 <= _ratio(item) < 0.85],
        [item for item in normalized if _ratio(item) >= 0.85],
    ]

    selected: list[dict] = []
    seen: set[str] = set()
    for group in groups:
        for item in group:
            key = item["name"]
            if key in seen:
                continue
            selected.append(item)
            seen.add(key)
            if len(selected) >= limit:
                return selected
    return selected


def render_pdf_report(result: dict, output_path: Path, source_json_path: Path | None = None) -> None:
    validate_result(result)
    output_path = Path(output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    score = int(result["score"])
    max_score = int(result["max_score"])
    passed = bool(result.get("passed", score >= 85))
    threshold = int(result.get("pass_threshold", 85))
    floor_failures = [str(item) for item in result.get("category_floor_failures", [])]
    suspect = bool(result.get("suspect", False))
    suspect_reasons = [str(reason) for reason in result.get("suspect_reasons", [])]
    if passed:
        status_line = "Passing threshold met."
    elif score >= threshold and floor_failures:
        status_line = "Score meets the threshold but category pass floors failed: " + "; ".join(floor_failures) + "."
    else:
        status_line = "Below passing threshold."
    review_line = ""
    if suspect:
        reasons_text = "; ".join(suspect_reasons) if suspect_reasons else "anti-cheat signals observed"
        review_line = "Flagged for manual review: " + reasons_text + "."
    breakdown = [_normalize_item(item) for item in result.get("breakdown", [])]
    score_sections = _normalize_score_sections(result.get("score_sections", []))
    auxiliary_score_sections = _normalize_score_sections(result.get("auxiliary_score_sections", []))
    findings = select_key_findings(breakdown, limit=5)

    styles = _styles()
    doc = SimpleDocTemplate(
        str(output_path),
        pagesize=letter,
        rightMargin=0.55 * inch,
        leftMargin=0.55 * inch,
        topMargin=0.5 * inch,
        bottomMargin=0.45 * inch,
        title="RoboBlast Grenade Verifier Score Report",
    )

    story = [
        _header_table(result, score, max_score, passed, source_json_path, styles),
        Spacer(1, 0.18 * inch),
        _score_summary_table(score, max_score, passed, styles, status_line, review_line),
        Spacer(1, 0.18 * inch),
    ]
    if score_sections:
        story.extend(
            [
                Paragraph("Score Sections", styles["section"]),
                Spacer(1, 0.06 * inch),
                _score_sections_table(score_sections, styles),
                Spacer(1, 0.18 * inch),
            ]
        )
    if auxiliary_score_sections:
        story.extend(
            [
                Paragraph("Auxiliary Visual Scores", styles["section"]),
                Spacer(1, 0.04 * inch),
                Paragraph("These visual analysis scores are not counted in 100-point score.", styles["muted"]),
                Spacer(1, 0.06 * inch),
                _score_sections_table(auxiliary_score_sections, styles),
                Spacer(1, 0.18 * inch),
            ]
        )
    story.extend(
        [
        Paragraph("Category Scores", styles["section"]),
        Spacer(1, 0.06 * inch),
        _category_table(breakdown, styles),
        Spacer(1, 0.18 * inch),
        Paragraph("Key Findings", styles["section"]),
        Spacer(1, 0.06 * inch),
        _findings_table(findings, styles),
        Spacer(1, 0.18 * inch),
        *_detail_analysis_flowables(breakdown, styles),
        ]
    )

    doc.build(story)


class ScorePill(Flowable):
    def __init__(self, score: int, max_score: int, passed: bool, width: float = 160, height: float = 108):
        super().__init__()
        self.score = score
        self.max_score = max_score
        self.passed = passed
        self.width = width
        self.height = height

    def draw(self) -> None:
        status_color = _status_color(self.score, self.max_score, self.passed)
        self.canv.setFillColor(PANEL)
        self.canv.setStrokeColor(LINE)
        self.canv.roundRect(0, 0, self.width, self.height, 8, fill=1, stroke=1)
        self.canv.setFillColor(status_color)
        self.canv.roundRect(12, self.height - 31, 54, 18, 5, fill=1, stroke=0)
        self.canv.setFillColor(colors.white)
        self.canv.setFont("Helvetica-Bold", 8)
        self.canv.drawCentredString(39, self.height - 25, "PASS" if self.passed else "FAIL")
        self.canv.setFillColor(INK)
        self.canv.setFont("Helvetica-Bold", 34)
        self.canv.drawString(13, 36, str(self.score))
        self.canv.setFillColor(MUTED)
        self.canv.setFont("Helvetica", 12)
        self.canv.drawString(76, 44, f"/ {self.max_score}")
        self.canv.setFont("Helvetica", 8)
        self.canv.drawString(14, 20, "Total benchmark score")


class BarFlowable(Flowable):
    def __init__(self, score: int, max_score: int, width: float = 170, height: float = 10):
        super().__init__()
        self.score = score
        self.max_score = max_score
        self.width = width
        self.height = height

    def draw(self) -> None:
        ratio = 0 if self.max_score <= 0 else max(0, min(1, self.score / self.max_score))
        self.canv.setFillColor(colors.HexColor("#e5e7eb"))
        self.canv.roundRect(0, 1, self.width, self.height - 2, 4, fill=1, stroke=0)
        if ratio > 0:
            self.canv.setFillColor(_bar_color(ratio))
            self.canv.roundRect(0, 1, self.width * ratio, self.height - 2, 4, fill=1, stroke=0)


def _styles() -> dict[str, ParagraphStyle]:
    base = getSampleStyleSheet()
    return {
        "title": ParagraphStyle(
            "title",
            parent=base["Title"],
            fontName="Helvetica-Bold",
            fontSize=18,
            leading=21,
            textColor=INK,
            alignment=TA_LEFT,
            spaceAfter=2,
        ),
        "subtitle": ParagraphStyle(
            "subtitle",
            parent=base["Normal"],
            fontName="Helvetica",
            fontSize=8.5,
            leading=11,
            textColor=MUTED,
        ),
        "section": ParagraphStyle(
            "section",
            parent=base["Heading2"],
            fontName="Helvetica-Bold",
            fontSize=11,
            leading=13,
            textColor=INK,
            spaceAfter=0,
        ),
        "cell": ParagraphStyle(
            "cell",
            parent=base["Normal"],
            fontName="Helvetica",
            fontSize=8,
            leading=10,
            textColor=INK,
        ),
        "cell_bold": ParagraphStyle(
            "cell_bold",
            parent=base["Normal"],
            fontName="Helvetica-Bold",
            fontSize=8,
            leading=10,
            textColor=INK,
        ),
        "muted": ParagraphStyle(
            "muted",
            parent=base["Normal"],
            fontName="Helvetica",
            fontSize=7.5,
            leading=9.5,
            textColor=MUTED,
        ),
        "finding": ParagraphStyle(
            "finding",
            parent=base["Normal"],
            fontName="Helvetica",
            fontSize=8,
            leading=10,
            textColor=INK,
        ),
        "finding_title": ParagraphStyle(
            "finding_title",
            parent=base["Normal"],
            fontName="Helvetica-Bold",
            fontSize=8.5,
            leading=10,
            textColor=INK,
        ),
        "center": ParagraphStyle(
            "center",
            parent=base["Normal"],
            fontName="Helvetica-Bold",
            fontSize=8,
            leading=10,
            textColor=INK,
            alignment=TA_CENTER,
        ),
        "detail_title": ParagraphStyle(
            "detail_title",
            parent=base["Normal"],
            fontName="Helvetica-Bold",
            fontSize=8.4,
            leading=9.4,
            textColor=INK,
            spaceBefore=1,
            spaceAfter=2,
        ),
        "detail_cell": ParagraphStyle(
            "detail_cell",
            parent=base["Normal"],
            fontName="Helvetica",
            fontSize=7.4,
            leading=8.4,
            textColor=INK,
        ),
        "detail_status": ParagraphStyle(
            "detail_status",
            parent=base["Normal"],
            fontName="Helvetica-Bold",
            fontSize=7.2,
            leading=8.2,
            textColor=INK,
        ),
    }


def _header_table(result: dict, score: int, max_score: int, passed: bool, source_json_path: Path | None, styles: dict) -> Table:
    status_text = "PASS" if passed else "FAIL"
    source = str(source_json_path) if source_json_path else "in-memory result"
    generated = datetime.now().astimezone().strftime("%Y-%m-%d %H:%M %Z")
    metadata = (
        f"Status: {status_text}<br/>"
        f"Godot: {_escape(str(result.get('godot_version', 'unknown')))}<br/>"
        f"Generated: {generated}<br/>"
        f"Source: {_escape(_compact_path(source, 58))}"
    )
    table = Table(
        [
            [
                Paragraph("RoboBlast Grenade Verifier", styles["title"]),
                Paragraph(metadata, styles["subtitle"]),
            ],
            [
                Paragraph("Executive score report for deterministic grenade weapon benchmark output.", styles["subtitle"]),
                Paragraph(f"{score}/{max_score}", styles["center"]),
            ],
        ],
        colWidths=[4.6 * inch, 2.1 * inch],
    )
    table.setStyle(
        TableStyle(
            [
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("ALIGN", (1, 0), (1, -1), "RIGHT"),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 2),
                ("TOPPADDING", (0, 0), (-1, -1), 0),
            ]
        )
    )
    return table


def _score_summary_table(
    score: int,
    max_score: int,
    passed: bool,
    styles: dict,
    status_line: str = "",
    review_line: str = "",
) -> Table:
    ratio = 0 if max_score <= 0 else score / max_score
    if not status_line:
        status_line = "Passing threshold met." if passed else "Below passing threshold."
    summary = (
        f"<b>{status_line}</b><br/>"
        f"The PDF mirrors the verifier JSON result. Category bars below show which behaviors were observed "
        f"at runtime and which remain incomplete."
    )
    if review_line:
        summary += f"<br/><b>{review_line}</b>"
    table = Table(
        [[ScorePill(score, max_score, passed), Paragraph(summary, styles["cell"])]],
        colWidths=[2.05 * inch, 4.65 * inch],
        rowHeights=[1.5 * inch],
    )
    border_color = _bar_color(ratio)
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, -1), colors.white),
                ("BOX", (0, 0), (-1, -1), 0.8, LINE),
                ("LINEBEFORE", (1, 0), (1, 0), 2, border_color),
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ("LEFTPADDING", (0, 0), (-1, -1), 10),
                ("RIGHTPADDING", (0, 0), (-1, -1), 10),
                ("TOPPADDING", (0, 0), (-1, -1), 8),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 8),
            ]
        )
    )
    return table


def _category_table(breakdown: list[dict], styles: dict) -> Table:
    if not breakdown:
        rows = [[Paragraph("No category breakdown was available.", styles["cell"])]]
        table = Table(rows, colWidths=[6.7 * inch])
        table.setStyle(TableStyle([("BOX", (0, 0), (-1, -1), 0.5, LINE), ("PADDING", (0, 0), (-1, -1), 8)]))
        return table

    rows = [[Paragraph("Category", styles["cell_bold"]), Paragraph("Score", styles["cell_bold"]), Paragraph("Observed", styles["cell_bold"])]]
    for item in breakdown:
        rows.append(
            [
                Paragraph(_label(item["name"]), styles["cell_bold"]),
                Paragraph(f'{item["score"]}/{item["max"]}', styles["cell"]),
                BarFlowable(item["score"], item["max"], width=265),
            ]
        )
    table = Table(rows, colWidths=[2.1 * inch, 0.72 * inch, 3.88 * inch], repeatRows=1)
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), PANEL),
                ("TEXTCOLOR", (0, 0), (-1, 0), INK),
                ("BOX", (0, 0), (-1, -1), 0.5, LINE),
                ("INNERGRID", (0, 0), (-1, -1), 0.25, LINE),
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ("LEFTPADDING", (0, 0), (-1, -1), 7),
                ("RIGHTPADDING", (0, 0), (-1, -1), 7),
                ("TOPPADDING", (0, 0), (-1, -1), 5),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
            ]
        )
    )
    return table


def _score_sections_table(score_sections: list[dict], styles: dict) -> Table:
    rows = [
        [
            Paragraph("Section", styles["cell_bold"]),
            Paragraph("Score", styles["cell_bold"]),
            Paragraph("Observed", styles["cell_bold"]),
            Paragraph("Categories", styles["cell_bold"]),
        ]
    ]
    for section in score_sections:
        rows.append(
            [
                Paragraph(_escape(section["label"]), styles["cell_bold"]),
                Paragraph(f'{section["score"]}/{section["max"]}', styles["cell"]),
                BarFlowable(section["score"], section["max"], width=185),
                Paragraph(_escape(", ".join(_label(category) for category in section["categories"])), styles["cell"]),
            ]
        )
    table = Table(rows, colWidths=[1.25 * inch, 0.7 * inch, 2.75 * inch, 2.0 * inch], repeatRows=1)
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), PANEL),
                ("BOX", (0, 0), (-1, -1), 0.5, LINE),
                ("INNERGRID", (0, 0), (-1, -1), 0.25, LINE),
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ("LEFTPADDING", (0, 0), (-1, -1), 7),
                ("RIGHTPADDING", (0, 0), (-1, -1), 7),
                ("TOPPADDING", (0, 0), (-1, -1), 5),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
            ]
        )
    )
    return table


def _findings_table(findings: list[dict], styles: dict) -> Table:
    rows = []
    for index, item in enumerate(findings, start=1):
        title = f'{index}. {_label(item["name"])} ({item["score"]}/{item["max"]})'
        rows.append(
            [
                Paragraph(title, styles["finding_title"]),
                Paragraph(_escape(item["notes"]), styles["finding"]),
            ]
        )
    table = Table(rows, colWidths=[1.85 * inch, 4.85 * inch])
    table.setStyle(
        TableStyle(
            [
                ("BOX", (0, 0), (-1, -1), 0.5, LINE),
                ("INNERGRID", (0, 0), (-1, -1), 0.25, LINE),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 7),
                ("RIGHTPADDING", (0, 0), (-1, -1), 7),
                ("TOPPADDING", (0, 0), (-1, -1), 6),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
                ("BACKGROUND", (0, 0), (0, -1), PANEL),
            ]
        )
    )
    return table


def _detail_analysis_flowables(breakdown: list[dict], styles: dict) -> list:
    if not breakdown:
        return [
            Paragraph("Detailed Item Analysis", styles["section"]),
            Spacer(1, 0.06 * inch),
            Paragraph("No category breakdown was available.", styles["cell"]),
        ]

    flowables: list = []
    for index, item in enumerate(breakdown):
        title = (
            Paragraph(
                f'{_label(item["name"])} Detail ({item["score"]}/{item["max"]})',
                styles["detail_title"],
            )
        )
        rows = [
            [
                Paragraph("Result", styles["cell_bold"]),
                Paragraph("Check", styles["cell_bold"]),
                Paragraph("Evidence", styles["cell_bold"]),
            ]
        ]
        for detail in item["details"]:
            rows.append(
                [
                    Paragraph(_escape(_detail_result_label(detail)), styles["detail_status"]),
                    Paragraph(_escape(detail["label"]), styles["detail_cell"]),
                    Paragraph(_escape(detail["notes"]), styles["detail_cell"]),
                ]
            )
        table = Table(rows, colWidths=[1.0 * inch, 1.7 * inch, 4.0 * inch], repeatRows=1)
        table.setStyle(
            TableStyle(
                [
                    ("BACKGROUND", (0, 0), (-1, 0), PANEL),
                    ("BOX", (0, 0), (-1, -1), 0.5, LINE),
                    ("INNERGRID", (0, 0), (-1, -1), 0.25, LINE),
                    ("VALIGN", (0, 0), (-1, -1), "TOP"),
                    ("LEFTPADDING", (0, 0), (-1, -1), 6),
                    ("RIGHTPADDING", (0, 0), (-1, -1), 6),
                    ("TOPPADDING", (0, 0), (-1, -1), 3),
                    ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
                ]
            )
        )
        block = [title, table, Spacer(1, 0.045 * inch)]
        if index == 0:
            block = [Paragraph("Detailed Item Analysis", styles["section"]), Spacer(1, 0.06 * inch), *block]
        flowables.append(KeepTogether(block))
    return flowables


def _normalize_item(item: dict) -> dict:
    name = str(item.get("name", "unknown"))
    score = _safe_int(item.get("score", 0))
    max_score = _safe_int(item.get("max", item.get("max_score", 0)))
    notes = str(item.get("notes", ""))
    raw_details = item.get("details", [])
    details = _normalize_details(raw_details, notes)
    return {"name": name, "score": score, "max": max_score, "notes": notes, "details": details}


def _normalize_score_sections(raw_sections) -> list[dict]:
    if not isinstance(raw_sections, list):
        return []
    sections: list[dict] = []
    for raw_section in raw_sections:
        if not isinstance(raw_section, dict):
            continue
        name = str(raw_section.get("name", "section"))
        label = str(raw_section.get("label", _label(name)))
        categories = raw_section.get("categories", [])
        if not isinstance(categories, list):
            categories = []
        sections.append(
            {
                "name": name,
                "label": label,
                "score": _safe_int(raw_section.get("score", 0)),
                "max": _safe_int(raw_section.get("max", raw_section.get("max_score", 0))),
                "used_for_score": bool(raw_section.get("used_for_score", True)),
                "notes": str(raw_section.get("notes", "")),
                "categories": [str(category) for category in categories],
            }
        )
    return sections


def _normalize_details(raw_details, notes: str) -> list[dict]:
    if isinstance(raw_details, list) and raw_details:
        return [_normalize_detail(detail) for detail in raw_details if isinstance(detail, dict)]
    if not notes:
        return [{"label": "Summary", "score": 0, "max": 0, "status": "observed", "notes": "No notes were recorded."}]
    return [
        {"label": f"Observation {index}", "score": 0, "max": 0, "status": "observed", "notes": part.strip()}
        for index, part in enumerate(notes.split(";"), start=1)
        if part.strip()
    ]


def _normalize_detail(detail: dict) -> dict:
    label = str(detail.get("label", detail.get("name", "Check")))
    score = _safe_int(detail.get("score", detail.get("points", 0)))
    max_score = _safe_int(detail.get("max", detail.get("max_score", 0)))
    status = str(detail.get("status", "")).strip().lower()
    if not status:
        if max_score <= 0:
            status = "observed"
        elif score >= max_score:
            status = "earned"
        elif score <= 0:
            status = "missed"
        else:
            status = "partial"
    return {
        "label": label,
        "score": score,
        "max": max_score,
        "status": status,
        "notes": str(detail.get("notes", detail.get("evidence", ""))),
    }


def _detail_result_label(detail: dict) -> str:
    status = str(detail["status"]).title()
    if detail["max"] <= 0:
        return status
    return f'{status} {detail["score"]}/{detail["max"]}'


def _safe_int(value) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


def _ratio(item: dict) -> float:
    if item["max"] <= 0:
        return 0.0
    return item["score"] / item["max"]


def _status_color(score: int, max_score: int, passed: bool):
    if passed:
        return STATUS_GREEN
    ratio = 0 if max_score <= 0 else score / max_score
    return STATUS_AMBER if ratio >= 0.5 else STATUS_RED


def _bar_color(ratio: float):
    if ratio >= 0.85:
        return STATUS_GREEN
    if ratio >= 0.5:
        return STATUS_AMBER
    return STATUS_RED


def _label(name: str) -> str:
    return str(name).replace("_", " ").title()


def _escape(text: str) -> str:
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def _compact_path(path: str, max_length: int) -> str:
    if len(path) <= max_length:
        return path
    return "..." + path[-(max_length - 3) :]
