import argparse
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


EXCLUDED_DIRS = {".git", ".godot", ".superpowers", ".worktrees", "exports", "bin"}
RESULT_FILE_NAME = "__verifier_result.json"


def ignore_candidate_files(_directory, names):
    return {name for name in names if name in EXCLUDED_DIRS}


def copy_candidate_project(source: Path, destination: Path) -> None:
    source = source.resolve()
    destination = destination.resolve()
    if not (source / "project.godot").exists():
        raise FileNotFoundError(f"Candidate project is missing project.godot: {source}")
    if destination.exists():
        shutil.rmtree(destination)
    shutil.copytree(source, destination, ignore=ignore_candidate_files)


def inject_verifier(verifier_root: Path, project_copy: Path) -> None:
    source = verifier_root / "verifier_godot" / "__verifier__"
    target = project_copy / "__verifier__"
    if not source.exists():
        raise FileNotFoundError(f"Verifier Godot folder does not exist: {source}")
    if target.exists():
        shutil.rmtree(target)
    shutil.copytree(source, target)


def _run_command(command: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(command, text=True, capture_output=True, check=False, encoding="utf-8", errors="replace")


def run_godot(godot: Path, godot_args: list[str], project_copy: Path, log_path: Path) -> subprocess.CompletedProcess:
    import_command = [str(godot), *godot_args, "--headless", "--path", str(project_copy), "--import"]
    script_command = [str(godot), *godot_args, "--headless", "--path", str(project_copy), "--script", "res://__verifier__/runner.gd"]

    import_run = _run_command(import_command)
    script_run = _run_command(script_command)

    log_path.parent.mkdir(parents=True, exist_ok=True)
    log_path.write_text(
        "IMPORT COMMAND: "
        + " ".join(import_command)
        + "\n\nIMPORT STDOUT:\n"
        + import_run.stdout
        + "\nIMPORT STDERR:\n"
        + import_run.stderr
        + "\n\nSCRIPT COMMAND: "
        + " ".join(script_command)
        + "\n\nSCRIPT STDOUT:\n"
        + script_run.stdout
        + "\nSCRIPT STDERR:\n"
        + script_run.stderr,
        encoding="utf-8",
    )

    if import_run.returncode != 0 and script_run.returncode == 0:
        return import_run
    return script_run


def read_result(project_copy: Path) -> dict:
    result_path = project_copy / RESULT_FILE_NAME
    if not result_path.exists():
        raise FileNotFoundError(f"Godot verifier did not write {RESULT_FILE_NAME}")
    return json.loads(result_path.read_text(encoding="utf-8"))


def write_result(result: dict, out_path: Path) -> None:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(result, indent=2), encoding="utf-8")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Run the RoboBlast grenade benchmark verifier.")
    parser.add_argument("--project", required=True, type=Path, help="Path to the candidate Godot project.")
    parser.add_argument("--godot", required=True, type=Path, help="Path to the Godot console executable.")
    parser.add_argument("--godot-arg", action="append", default=[], help="Additional argument placed before --headless. Used by tests.")
    parser.add_argument("--verifier-root", type=Path, default=Path(__file__).resolve().parent, help="Root directory containing verifier_godot.")
    parser.add_argument("--out", required=True, type=Path, help="Path to write score JSON.")
    parser.add_argument("--pdf-report", type=Path, help="Optional path to write a detailed PDF score report.")
    parser.add_argument("--log", type=Path, help="Path to write Godot stdout/stderr log.")
    parser.add_argument("--keep-temp", action="store_true", help="Keep the temporary project copy for inspection.")
    return parser


def infrastructure_failure(message: str, out_path: Path, log_path: Path) -> int:
    failure = {
        "score": 0,
        "max_score": 100,
        "passed": False,
        "godot_version": "",
        "breakdown": [{"name": "grader_infrastructure", "score": 0, "max": 100, "notes": message}],
        "artifacts": {"log": str(log_path), "screenshots": []},
    }
    write_result(failure, out_path)
    print(f"Verifier infrastructure failure: {message}", file=sys.stderr)
    return 2


def render_optional_pdf_report(result: dict, pdf_report: Path | None, source_json_path: Path) -> None:
    if pdf_report is None:
        return
    from report_renderer import render_pdf_report

    render_pdf_report(result, pdf_report, source_json_path)


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    log_path = args.log if args.log else args.out.with_suffix(".log")
    temp_root = Path(tempfile.mkdtemp(prefix="roboblast-grenade-verifier-"))
    temp_project = temp_root / "candidate"

    try:
        copy_candidate_project(args.project, temp_project)
        inject_verifier(args.verifier_root.resolve(), temp_project)
        completed = run_godot(args.godot, args.godot_arg, temp_project, log_path)
        result = read_result(temp_project)
        result.setdefault("artifacts", {})
        result["artifacts"]["log"] = str(log_path)
        write_result(result, args.out)
        try:
            render_optional_pdf_report(result, args.pdf_report, args.out)
        except Exception as exc:
            print(f"Verifier infrastructure failure: could not render PDF report: {exc}", file=sys.stderr)
            return 2
        print(f"Score: {result.get('score', 0)}/{result.get('max_score', 100)}")
        if completed.returncode != 0:
            print(f"Godot exited with {completed.returncode}, but a verifier result was produced.", file=sys.stderr)
        return 0
    except Exception as exc:
        return infrastructure_failure(str(exc), args.out, log_path)
    finally:
        if args.keep_temp:
            print(f"Temporary project kept at: {temp_project}")
        else:
            shutil.rmtree(temp_root, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
