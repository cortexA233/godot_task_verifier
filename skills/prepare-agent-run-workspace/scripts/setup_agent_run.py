#!/usr/bin/env python3
"""Prepare an isolated agent-run workspace with a baseline git commit."""

from __future__ import annotations

import argparse
import fnmatch
import json
import os
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


DEFAULT_EXCLUDED_DIRS = {
    ".git",
    ".codex",
    ".worktree",
    ".worktrees",
    ".superpowers",
}
DEFAULT_EXCLUDED_FILES = {"AGENTS.md", "AGENTS.zh.md", "CLAUDE.md"}

ROBOBLAST_EXCLUDED_DIRS = DEFAULT_EXCLUDED_DIRS | {
    ".godot",
    ".claude",
    "__verifier__",
    "artifacts",
    "bin",
    "exports",
    "output",
    "tmp",
    "verifier_godot",
}
ROBOBLAST_EXCLUDED_FILES = DEFAULT_EXCLUDED_FILES | {
    "__verifier_result.json",
    "BENCHMARK.md",
    "TASK_PROMPT.zh.md",
    "export_debug_arena.py",
    "game_take_home.html",
    "probe_matrix.md",
    "run_calibration.ps1",
    "run_grader.py",
    "skills-lock.json",
}
ROBOBLAST_EXCLUDED_GLOBS = {"*.log"}
ROBOBLAST_EXCLUDED_REL_PATHS = {"docs/superpowers"}
RUN_RECORD_REQUIREMENT = """

---

## Run Record Requirement

At the end of your work, create `AGENT_RUN_RECORD.md` at the project root with:

- Agent/model/version if known.
- Tools available and tools actually used, including whether Godot MCP was visible or used.
- Files changed and why.
- Godot/editor/test commands run, with outcomes.
- Manual observations from running the game.
- Known remaining issues or uncertainties.
- A short summary of the implemented behavior.

Do not inspect git history, remotes, other branches, parent directories, original solution files, verifier files, hidden tests, or anything outside this workspace.
"""


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def resolve_dir(path: str) -> Path:
    return Path(path).expanduser().resolve()


def is_relative_to(path: Path, parent: Path) -> bool:
    try:
        path.relative_to(parent)
        return True
    except ValueError:
        return False


def normalize_rel(path: Path) -> str:
    return path.as_posix().casefold()


def matches_name(name: str, excluded: set[str]) -> bool:
    folded = name.casefold()
    return any(folded == item.casefold() for item in excluded)


def matches_glob(name: str, patterns: set[str]) -> bool:
    folded = name.casefold()
    return any(fnmatch.fnmatchcase(folded, pattern.casefold()) for pattern in patterns)


def run_git(workspace: Path, args: list[str]) -> str:
    completed = subprocess.run(
        ["git", *args],
        cwd=workspace,
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    return completed.stdout.strip()


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Create an isolated agent workspace, initialize a local baseline "
            "git repository, and write evidence metadata."
        )
    )
    parser.add_argument("--source", required=True, help="Ablated project to copy.")
    parser.add_argument(
        "--run-root",
        required=True,
        help="Directory that will contain workspace/ and evidence/.",
    )
    parser.add_argument(
        "--profile",
        choices=("generic", "roboblast"),
        default="roboblast",
        help="Exclusion and validation profile. Defaults to roboblast.",
    )
    parser.add_argument("--workspace-name", default="workspace")
    parser.add_argument("--evidence-name", default="evidence")
    parser.add_argument("--agent", default="", help="Agent name, such as claude-code.")
    parser.add_argument("--model", default="", help="Agent model/version if known.")
    parser.add_argument(
        "--tool",
        action="append",
        default=[],
        help="Tool made available to the agent. Repeat as needed.",
    )
    parser.add_argument(
        "--godot-mcp",
        choices=("available", "used", "not-available", "unknown"),
        default="unknown",
        help="Godot MCP availability for this run.",
    )
    parser.add_argument(
        "--prompt",
        help="Prompt/spec file to copy into evidence/prompt.md.",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Print the summary as JSON.",
    )
    return parser.parse_args(argv)


def profile_rules(profile: str) -> tuple[set[str], set[str], set[str], set[str]]:
    if profile == "generic":
        return DEFAULT_EXCLUDED_DIRS, DEFAULT_EXCLUDED_FILES, set(), set()
    return (
        ROBOBLAST_EXCLUDED_DIRS,
        ROBOBLAST_EXCLUDED_FILES,
        ROBOBLAST_EXCLUDED_GLOBS,
        ROBOBLAST_EXCLUDED_REL_PATHS,
    )


def validate_paths(source: Path, run_root: Path, workspace: Path, evidence: Path) -> None:
    if not source.exists() or not source.is_dir():
        raise ValueError(f"Source is not an existing directory: {source}")
    if is_relative_to(run_root, source):
        raise ValueError("Run root must be outside the source workspace.")
    if workspace.exists():
        raise ValueError(f"Workspace already exists: {workspace}")
    if evidence.exists():
        raise ValueError(f"Evidence directory already exists: {evidence}")
    if not run_root.parent.exists():
        raise ValueError(f"Run root parent does not exist: {run_root.parent}")


def make_ignore(
    source: Path,
    excluded_dirs: set[str],
    excluded_files: set[str],
    excluded_globs: set[str],
    excluded_rel_paths: set[str],
) -> tuple[object, list[str]]:
    excluded_paths: list[str] = []

    def ignore(directory: str, names: list[str]) -> set[str]:
        base = Path(directory)
        ignored: set[str] = set()
        for name in names:
            candidate = base / name
            rel = normalize_rel(candidate.relative_to(source))
            if rel in {item.casefold() for item in excluded_rel_paths}:
                ignored.add(name)
            elif candidate.is_dir() and matches_name(name, excluded_dirs):
                ignored.add(name)
            elif candidate.is_file() and matches_name(name, excluded_files):
                ignored.add(name)
            elif candidate.is_file() and matches_glob(name, excluded_globs):
                ignored.add(name)
            if name in ignored:
                excluded_paths.append(str(candidate))
        return ignored

    return ignore, excluded_paths


def find_forbidden(
    workspace: Path,
    excluded_dirs: set[str],
    excluded_files: set[str],
    excluded_globs: set[str],
    excluded_rel_paths: set[str],
) -> list[str]:
    forbidden: list[str] = []
    folded_rel_paths = {item.casefold() for item in excluded_rel_paths}
    for root, dirnames, filenames in os.walk(workspace):
        root_path = Path(root)
        for dirname in dirnames:
            candidate = root_path / dirname
            rel = normalize_rel(candidate.relative_to(workspace))
            if matches_name(dirname, excluded_dirs) or rel in folded_rel_paths:
                forbidden.append(str(candidate))
        for filename in filenames:
            if matches_name(filename, excluded_files) or matches_glob(filename, excluded_globs):
                forbidden.append(str(root_path / filename))
    return forbidden


def initialize_git(workspace: Path) -> str:
    run_git(workspace, ["init"])
    run_git(workspace, ["config", "user.name", "Agent Evidence Bot"])
    run_git(workspace, ["config", "user.email", "agent-evidence@example.invalid"])
    run_git(workspace, ["add", "-A"])
    run_git(workspace, ["commit", "-m", "baseline ablated task"])
    return run_git(workspace, ["rev-parse", "HEAD"])


def print_summary(summary: dict[str, object], as_json: bool) -> None:
    if as_json:
        print(json.dumps(summary, indent=2, sort_keys=True))
        return
    print(f"Workspace: {summary['workspace']}")
    print(f"Evidence: {summary['evidence_dir']}")
    print(f"Baseline SHA: {summary['baseline_sha']}")
    print(f"Manifest: {summary['manifest_path']}")


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    source = resolve_dir(args.source)
    run_root = resolve_dir(args.run_root)
    workspace = (run_root / args.workspace_name).resolve()
    evidence = (run_root / args.evidence_name).resolve()
    excluded_dirs, excluded_files, excluded_globs, excluded_rel_paths = profile_rules(
        args.profile
    )

    try:
        validate_paths(source, run_root, workspace, evidence)
        run_root.mkdir(parents=True, exist_ok=True)
        evidence.mkdir()
        ignore, excluded_paths = make_ignore(
            source, excluded_dirs, excluded_files, excluded_globs, excluded_rel_paths
        )
        shutil.copytree(source, workspace, ignore=ignore, symlinks=True)

        if args.profile == "roboblast" and not (workspace / "project.godot").is_file():
            raise ValueError("RoboBlast profile requires project.godot in the copy.")

        forbidden = find_forbidden(
            workspace, excluded_dirs, excluded_files, excluded_globs, excluded_rel_paths
        )
        if forbidden:
            raise ValueError(
                "Forbidden paths remained after copy:\n" + "\n".join(forbidden)
            )

        prompt_path = None
        prompt_for_agent_path = None
        if args.prompt:
            prompt_source = Path(args.prompt).expanduser().resolve()
            if not prompt_source.is_file():
                raise ValueError(f"Prompt file does not exist: {prompt_source}")
            prompt_path = evidence / "prompt.md"
            shutil.copy2(prompt_source, prompt_path)
            prompt_for_agent_path = evidence / "prompt-for-agent.md"
            prompt_for_agent_path.write_text(
                prompt_source.read_text(encoding="utf-8").rstrip()
                + RUN_RECORD_REQUIREMENT,
                encoding="utf-8",
            )

        baseline_sha = initialize_git(workspace)
        (evidence / "baseline-sha.txt").write_text(
            baseline_sha + "\n", encoding="utf-8"
        )

        manifest = {
            "created_at": utc_now(),
            "source": str(source),
            "run_root": str(run_root),
            "workspace": str(workspace),
            "evidence_dir": str(evidence),
            "profile": args.profile,
            "baseline_sha": baseline_sha,
            "agent": args.agent,
            "model": args.model,
            "tools": args.tool,
            "godot_mcp": args.godot_mcp,
            "prompt_path": str(prompt_path) if prompt_path else "",
            "prompt_for_agent_path": (
                str(prompt_for_agent_path) if prompt_for_agent_path else ""
            ),
            "excluded_paths": excluded_paths,
        }
        manifest_path = evidence / "run-manifest.json"
        manifest_path.write_text(
            json.dumps(manifest, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )

        summary = {
            "workspace": str(workspace),
            "evidence_dir": str(evidence),
            "baseline_sha": baseline_sha,
            "manifest_path": str(manifest_path),
        }
        print_summary(summary, args.json)
        return 0
    except Exception as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
