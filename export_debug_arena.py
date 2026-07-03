import argparse
import sys
from pathlib import Path

from debug_scene_exporter import export_debug_project


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Export a manually runnable RoboBlast verifier debug arena project.")
    parser.add_argument("--project", required=True, type=Path, help="Path to the candidate Godot project.")
    parser.add_argument("--out", required=True, type=Path, help="Path to write the exported debug project copy.")
    parser.add_argument(
        "--verifier-root",
        type=Path,
        default=Path(__file__).resolve().parent,
        help="Root directory containing verifier_godot.",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        debug_scene = export_debug_project(args.project, args.out, args.verifier_root.resolve())
    except Exception as exc:
        print(f"Could not export debug arena: {exc}", file=sys.stderr)
        return 2
    print(f"Exported debug project: {args.out}")
    print(f"Open scene in Godot: res://__verifier__/debug_arena.tscn")
    print(f"Scene file: {debug_scene}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
