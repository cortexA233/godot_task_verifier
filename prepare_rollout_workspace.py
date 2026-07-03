import argparse
import shutil
from pathlib import Path


EXCLUDED_DIR_NAMES = {
    ".git",
    ".godot",
    ".codex",
    ".claude",
    ".superpowers",
    ".worktrees",
    "__verifier__",
    "artifacts",
    "bin",
    "exports",
    "output",
    "tmp",
    "verifier_godot",
}

EXCLUDED_FILE_NAMES = {
    "__verifier_result.json",
    "AGENTS.md",
    "AGENTS.zh.md",
    "BENCHMARK.md",
    "CLAUDE.md",
    "TASK_PROMPT.zh.md",
    "export_debug_arena.py",
    "game_take_home.html",
    "probe_matrix.md",
    "run_calibration.ps1",
    "run_grader.py",
    "skills-lock.json",
}

EXCLUDED_PATHS = {
    Path("docs") / "superpowers",
}


def _relative_to_source(path: Path, source: Path) -> Path:
    return path.resolve().relative_to(source.resolve())


def should_exclude(path: Path, source: Path) -> bool:
    relative = _relative_to_source(path, source)
    if any(relative == excluded or excluded in relative.parents for excluded in EXCLUDED_PATHS):
        return True
    if path.is_dir():
        return path.name in EXCLUDED_DIR_NAMES
    return path.name in EXCLUDED_FILE_NAMES or path.name.endswith(".log")


def _copy_filtered_directory(source: Path, destination: Path, root: Path) -> None:
    destination.mkdir(parents=True, exist_ok=True)
    for item in source.iterdir():
        if should_exclude(item, root):
            continue
        target = destination / item.name
        if item.is_dir():
            _copy_filtered_directory(item, target, root)
        else:
            shutil.copy2(item, target)


def prepare_rollout_workspace(source: Path, destination: Path, force: bool = False) -> None:
    source = source.resolve()
    destination = destination.resolve()
    if not (source / "project.godot").exists():
        raise FileNotFoundError(f"Source project is missing project.godot: {source}")
    if destination.exists():
        if not force:
            raise FileExistsError(f"Destination already exists; pass --force to replace it: {destination}")
        shutil.rmtree(destination)
    _copy_filtered_directory(source, destination, source)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Prepare a clean RoboBlast rollout workspace for an agent.")
    parser.add_argument("--project", required=True, type=Path, help="Path to the ablated Godot project.")
    parser.add_argument("--out", required=True, type=Path, help="Destination directory for the clean rollout workspace.")
    parser.add_argument("--force", action="store_true", help="Replace the destination if it already exists.")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        prepare_rollout_workspace(args.project, args.out, force=args.force)
    except Exception as exc:
        print(f"Could not prepare rollout workspace: {exc}")
        return 2
    print(f"Prepared rollout workspace at: {args.out.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
