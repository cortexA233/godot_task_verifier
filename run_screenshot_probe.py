import argparse
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import run_grader


PROBE_OUTPUT_DIR = "__screenshot_probe__"
PROBE_SCRIPT = "res://__verifier__/screenshot_probe_runner.gd"


def _run_command(command: list[str], timeout: int) -> subprocess.CompletedProcess:
    return subprocess.run(
        command,
        text=True,
        capture_output=True,
        check=False,
        encoding="utf-8",
        errors="replace",
        timeout=timeout,
    )


def _write_command_log(path: Path, command: list[str], completed: subprocess.CompletedProcess) -> None:
    path.write_text(
        "COMMAND: "
        + " ".join(command)
        + "\n\nSTDOUT:\n"
        + completed.stdout
        + "\nSTDERR:\n"
        + completed.stderr,
        encoding="utf-8",
    )


def _copy_probe_artifacts(project_copy: Path, output_dir: Path) -> dict:
    source = project_copy / PROBE_OUTPUT_DIR
    output_dir.mkdir(parents=True, exist_ok=True)
    if not source.exists():
        return {}
    for artifact in source.iterdir():
        if artifact.is_file():
            shutil.copy2(artifact, output_dir / artifact.name)
    result_path = output_dir / "result.json"
    if result_path.exists():
        return json.loads(result_path.read_text(encoding="utf-8"))
    return {}


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Run the experimental RoboBlast rendered screenshot probe.")
    parser.add_argument("--project", required=True, type=Path, help="Path to the candidate Godot project.")
    parser.add_argument("--godot", required=True, type=Path, help="Path to the Godot console executable.")
    parser.add_argument("--out-dir", required=True, type=Path, help="Directory to write screenshots and result.json.")
    parser.add_argument("--verifier-root", type=Path, default=Path(__file__).resolve().parent, help="Root directory containing verifier_godot.")
    parser.add_argument("--timeout", type=int, default=120, help="Timeout in seconds for each Godot command.")
    parser.add_argument("--keep-temp", action="store_true", help="Keep the injected temporary project copy.")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    temp_root = Path(tempfile.mkdtemp(prefix="roboblast-screenshot-probe-"))
    temp_project = temp_root / "candidate"
    args.out_dir.mkdir(parents=True, exist_ok=True)

    try:
        run_grader.copy_candidate_project(args.project, temp_project)
        run_grader.inject_verifier(args.verifier_root.resolve(), temp_project)
        (temp_project / PROBE_OUTPUT_DIR).mkdir(parents=True, exist_ok=True)

        import_command = [str(args.godot), "--headless", "--path", str(temp_project), "--import"]
        script_command = [str(args.godot), "--path", str(temp_project), "--script", PROBE_SCRIPT]

        import_run = _run_command(import_command, args.timeout)
        _write_command_log(args.out_dir / "import.log", import_command, import_run)
        if import_run.returncode != 0:
            print(f"Godot import failed with {import_run.returncode}. See {args.out_dir / 'import.log'}", file=sys.stderr)
            return import_run.returncode or 1

        try:
            script_run = _run_command(script_command, args.timeout)
        except subprocess.TimeoutExpired as exc:
            (args.out_dir / "run.log").write_text(f"COMMAND: {' '.join(script_command)}\n\nTIMEOUT:\n{exc}\n", encoding="utf-8")
            print(f"Screenshot probe timed out after {args.timeout}s. See {args.out_dir / 'run.log'}", file=sys.stderr)
            return 124
        _write_command_log(args.out_dir / "run.log", script_command, script_run)
        result = _copy_probe_artifacts(temp_project, args.out_dir)
        if not result:
            print(f"Screenshot probe did not write result.json. See {args.out_dir / 'run.log'}", file=sys.stderr)
            return script_run.returncode or 1
        print(f"Wrote screenshot probe artifacts: {args.out_dir}")
        print(f"Stop reason: {result.get('stop_reason', 'unknown')} at frame {result.get('explosion_frame', -1)}")
        print(f"Screenshots: {len(result.get('captures', []))}")
        return script_run.returncode
    finally:
        if args.keep_temp:
            print(f"Temporary project kept at: {temp_project}")
        else:
            shutil.rmtree(temp_root, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
