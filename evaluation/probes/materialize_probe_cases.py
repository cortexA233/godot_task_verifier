"""Materialize runnable anti-cheat probe candidate projects.

Probe cases are stored as compact overlays in ``cases/<probe-name>``. This
script copies a full base Godot candidate project, then applies each overlay so
the generated directories can be passed directly to ``run_grader.py``.
"""

from __future__ import annotations

import argparse
import shutil
from pathlib import Path


ROOT = Path(__file__).resolve().parent
CASES_DIR = ROOT / "cases"
DEFAULT_EXCLUDED_DIRS = {
    ".git",
    ".godot",
    ".codex",
    ".claude",
    ".superpowers",
    "__pycache__",
    "artifacts",
    "output",
    "tmp",
}
DEFAULT_EXCLUDED_FILES = {
    "skills-lock.json",
}


def case_names() -> list[str]:
    return sorted(path.name for path in CASES_DIR.iterdir() if path.is_dir())


def copy_base_project(base_project: Path, destination: Path) -> None:
    def ignore(_directory: str, names: list[str]) -> set[str]:
        return {
            name
            for name in names
            if name in DEFAULT_EXCLUDED_DIRS or name in DEFAULT_EXCLUDED_FILES
        }

    shutil.copytree(base_project, destination, ignore=ignore)


def apply_overlay(case_dir: Path, destination: Path) -> None:
    for source in case_dir.rglob("*"):
        if not source.is_file():
            continue
        relative = source.relative_to(case_dir)
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)


def materialize_cases(
    base_project: Path,
    out_dir: Path,
    selected_cases: list[str] | None,
    force: bool,
) -> list[Path]:
    if not (base_project / "project.godot").is_file():
        raise ValueError(f"Base project does not contain project.godot: {base_project}")

    available_cases = case_names()
    cases = selected_cases or available_cases
    unknown = sorted(set(cases) - set(available_cases))
    if unknown:
        raise ValueError("Unknown probe case(s): " + ", ".join(unknown))

    out_dir.mkdir(parents=True, exist_ok=True)
    generated: list[Path] = []
    for case_name in cases:
        destination = out_dir / case_name
        if destination.exists():
            if not force:
                raise FileExistsError(
                    f"Destination already exists: {destination}. Pass --force to replace it."
                )
            shutil.rmtree(destination)
        copy_base_project(base_project, destination)
        apply_overlay(CASES_DIR / case_name, destination)
        generated.append(destination)
    return generated


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-project", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument(
        "--case",
        action="append",
        choices=case_names(),
        help="Materialize only this case. Repeat for multiple cases.",
    )
    parser.add_argument("--force", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    generated = materialize_cases(
        args.base_project.resolve(),
        args.out.resolve(),
        args.case,
        args.force,
    )
    for path in generated:
        print(path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
