#!/usr/bin/env python3
"""Finalize an agent-run workspace and export objective git evidence."""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def resolve_dir(path: str) -> Path:
    return Path(path).expanduser().resolve()


def run_git(
    workspace: Path,
    args: list[str],
    check: bool = True,
    stdout_path: Path | None = None,
) -> subprocess.CompletedProcess[str]:
    stdout_target = subprocess.PIPE
    handle = None
    if stdout_path is not None:
        handle = stdout_path.open("w", encoding="utf-8", newline="")
        stdout_target = handle
    try:
        return subprocess.run(
            ["git", *args],
            cwd=workspace,
            check=check,
            text=True,
            stdout=stdout_target,
            stderr=subprocess.PIPE,
        )
    finally:
        if handle is not None:
            handle.close()


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Export git status, binary diff, final commit metadata, and agent "
            "run notes from an isolated workspace."
        )
    )
    parser.add_argument(
        "--run-root",
        help="Directory containing workspace/ and evidence/.",
    )
    parser.add_argument("--workspace", help="Workspace path when not using --run-root.")
    parser.add_argument("--evidence-dir", help="Evidence path when not using --run-root.")
    parser.add_argument("--workspace-name", default="workspace")
    parser.add_argument("--evidence-name", default="evidence")
    parser.add_argument(
        "--score-json",
        help="Optional verifier score JSON to copy into evidence/score.json.",
    )
    parser.add_argument(
        "--grader-command",
        default="",
        help="Exact verifier command to record in evidence/grader-command.txt.",
    )
    parser.add_argument(
        "--agent-record",
        default="AGENT_RUN_RECORD.md",
        help="Agent-authored run note path relative to workspace.",
    )
    parser.add_argument(
        "--artifact",
        action="append",
        default=[],
        help="Additional transcript, tool log, screenshot, or run artifact to copy into evidence/artifacts/. Repeat as needed.",
    )
    parser.add_argument("--json", action="store_true", help="Print summary as JSON.")
    return parser.parse_args(argv)


def resolve_paths(args: argparse.Namespace) -> tuple[Path, Path]:
    if args.run_root:
        run_root = resolve_dir(args.run_root)
        return (
            (run_root / args.workspace_name).resolve(),
            (run_root / args.evidence_name).resolve(),
        )
    if not args.workspace or not args.evidence_dir:
        raise ValueError("Use --run-root or provide both --workspace and --evidence-dir.")
    return resolve_dir(args.workspace), resolve_dir(args.evidence_dir)


def load_manifest(evidence: Path) -> dict[str, object]:
    manifest_path = evidence / "run-manifest.json"
    if not manifest_path.is_file():
        raise ValueError(f"Missing manifest: {manifest_path}")
    return json.loads(manifest_path.read_text(encoding="utf-8-sig"))


def read_baseline(evidence: Path, manifest: dict[str, object]) -> str:
    if manifest.get("baseline_sha"):
        return str(manifest["baseline_sha"])
    baseline_path = evidence / "baseline-sha.txt"
    if not baseline_path.is_file():
        raise ValueError("Missing baseline SHA in manifest and baseline-sha.txt.")
    return baseline_path.read_text(encoding="utf-8-sig").strip()


def has_staged_changes(workspace: Path) -> bool:
    completed = run_git(workspace, ["diff", "--cached", "--quiet"], check=False)
    return completed.returncode == 1


def write_text(path: Path, text: str) -> None:
    path.write_text(text, encoding="utf-8", newline="\n")


def copy_artifacts(paths: list[str], evidence: Path) -> list[str]:
    copied: list[str] = []
    if not paths:
        return copied
    artifact_dir = evidence / "artifacts"
    artifact_dir.mkdir(exist_ok=True)
    used_names: set[str] = set()
    for raw_path in paths:
        source = Path(raw_path).expanduser().resolve()
        if not source.is_file():
            raise ValueError(f"Artifact does not exist or is not a file: {source}")
        name = source.name
        candidate = name
        stem = source.stem
        suffix = source.suffix
        counter = 2
        while candidate.casefold() in used_names or (artifact_dir / candidate).exists():
            candidate = f"{stem}-{counter}{suffix}"
            counter += 1
        used_names.add(candidate.casefold())
        destination = artifact_dir / candidate
        shutil.copy2(source, destination)
        copied.append(str(destination))
    return copied


def print_summary(summary: dict[str, object], as_json: bool) -> None:
    if as_json:
        print(json.dumps(summary, indent=2, sort_keys=True))
        return
    print(f"Workspace: {summary['workspace']}")
    print(f"Diff: {summary['diff_path']}")
    print(f"Final SHA: {summary['final_sha']}")
    print(f"Attempt commit created: {summary['attempt_commit_created']}")


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    try:
        workspace, evidence = resolve_paths(args)
        if not workspace.is_dir():
            raise ValueError(f"Workspace does not exist: {workspace}")
        if not evidence.is_dir():
            raise ValueError(f"Evidence directory does not exist: {evidence}")
        if not (workspace / ".git").is_dir():
            raise ValueError(f"Workspace is not a git repository: {workspace}")

        manifest = load_manifest(evidence)
        baseline_sha = read_baseline(evidence, manifest)

        status_path = evidence / "git-status.txt"
        status = run_git(workspace, ["status", "--short"]).stdout
        write_text(status_path, status)

        run_git(workspace, ["add", "-A"])
        diff_path = evidence / "diff.patch"
        run_git(workspace, ["diff", "--cached", "--binary", baseline_sha], stdout_path=diff_path)

        attempt_commit_created = False
        if has_staged_changes(workspace):
            run_git(workspace, ["commit", "-m", "agent attempt"])
            attempt_commit_created = True

        final_sha = run_git(workspace, ["rev-parse", "HEAD"]).stdout.strip()
        write_text(evidence / "final-sha.txt", final_sha + "\n")

        record_source = workspace / args.agent_record
        record_path = ""
        if record_source.is_file():
            record_destination = evidence / record_source.name
            shutil.copy2(record_source, record_destination)
            record_path = str(record_destination)

        score_path = ""
        if args.score_json:
            score_source = Path(args.score_json).expanduser().resolve()
            if not score_source.is_file():
                raise ValueError(f"Score JSON does not exist: {score_source}")
            score_destination = evidence / "score.json"
            shutil.copy2(score_source, score_destination)
            score_path = str(score_destination)

        if args.grader_command:
            write_text(evidence / "grader-command.txt", args.grader_command + "\n")

        artifact_paths = copy_artifacts(args.artifact, evidence)

        manifest.update(
            {
                "finalized_at": utc_now(),
                "final_sha": final_sha,
                "attempt_commit_created": attempt_commit_created,
                "git_status_path": str(status_path),
                "diff_path": str(diff_path),
                "agent_record_path": record_path,
                "score_path": score_path,
                "artifact_paths": artifact_paths,
                "grader_command": args.grader_command,
            }
        )
        manifest_path = evidence / "run-manifest.json"
        manifest_path.write_text(
            json.dumps(manifest, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )

        summary = {
            "workspace": str(workspace),
            "evidence_dir": str(evidence),
            "diff_path": str(diff_path),
            "final_sha": final_sha,
            "attempt_commit_created": attempt_commit_created,
            "agent_record_path": record_path,
            "score_path": score_path,
            "artifact_paths": artifact_paths,
        }
        print_summary(summary, args.json)
        return 0
    except subprocess.CalledProcessError as exc:
        print(exc.stderr.strip(), file=sys.stderr)
        return exc.returncode
    except Exception as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
