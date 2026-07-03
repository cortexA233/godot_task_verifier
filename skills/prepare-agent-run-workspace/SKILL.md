---
name: prepare-agent-run-workspace
description: Use when preparing evaluated rollout or coding-agent run workspaces from ablated projects, especially when hidden verifier or original-solution files must be excluded and an operator-owned baseline git commit, prompt copy, and run manifest are needed before handoff.
---

# Prepare Agent Run Workspace

## Overview

Prepare the evaluator side of an agent run. This skill creates a clean `workspace/` for the evaluated agent and an adjacent `evidence/` directory with baseline metadata before the agent starts.

The evaluated agent must not run this setup script. Give the agent only the prepared `workspace/` and the prompt text from `evidence/prompt-for-agent.md`.

## Quick Start

```powershell
python "$env:USERPROFILE\.codex\skills\prepare-agent-run-workspace\scripts\setup_agent_run.py" `
  --source C:\path\to\ablated-project `
  --run-root C:\agent-runs\claude-code-01 `
  --agent claude-code `
  --model "model/version if known" `
  --tool "Godot MCP available" `
  --godot-mcp available `
  --prompt C:\path\to\TASK_PROMPT.md
```

The command creates:

- `run-root\workspace`: the isolated project handed to the agent.
- `run-root\evidence`: evaluator-owned records, not handed to the agent.
- `evidence\run-manifest.json`: source path, agent/model/tools, Godot MCP status, baseline SHA, prompt paths.
- `evidence\baseline-sha.txt`: the clean baseline commit.
- `evidence\prompt.md`: a copy of the original prompt.
- `evidence\prompt-for-agent.md`: prompt plus `AGENT_RUN_RECORD.md` instructions.

## Workflow

1. Start from the ablated task project, not from the verifier repo, original-solution branch, or hidden-test workspace.
2. Choose a fresh `--run-root` outside the source project.
3. Run `setup_agent_run.py`.
4. Confirm the generated `workspace/` is what the evaluated agent should see.
5. Give the agent only the `workspace/` path and the contents of `evidence\prompt-for-agent.md`.
6. After the agent finishes, use `collect-agent-run-evidence`.

The script initializes a new local git repository inside `workspace/` after copying and exclusion checks. That repository contains only the baseline commit and has no remotes or original solution history.

## Profiles

Default profile is `roboblast`. It requires `project.godot` and excludes:

- directories: `.git`, `.godot`, `.codex`, `.claude`, `.superpowers`, `.worktrees`, `__verifier__`, `artifacts`, `bin`, `exports`, `output`, `tmp`, `verifier_godot`
- files: `__verifier_result.json`, `AGENTS.md`, `AGENTS.zh.md`, `BENCHMARK.md`, `CLAUDE.md`, `TASK_PROMPT.zh.md`, `export_debug_arena.py`, `game_take_home.html`, `probe_matrix.md`, `run_calibration.ps1`, `run_grader.py`, `skills-lock.json`, and `*.log`
- path: `docs/superpowers`

Use `--profile generic` only for non-RoboBlast projects where those stricter exclusions are not appropriate.

## Safety Rules

- Do not create `--run-root` inside `--source`.
- Do not add `AGENTS.md` to the agent workspace to control evidence capture; use `prompt-for-agent.md`.
- Do not ask the evaluated agent to initialize git, create the baseline commit, or run this setup script.
- Do not hand the `evidence/` directory to the agent.
- Do not include verifier repositories, original-solution branches, hidden notes, hidden tests, or scoring details in the source.

## Related Skills

Use `copy-agent-workspace` for a plain clean copy with no baseline/evidence workflow. Use `collect-agent-run-evidence` after the evaluated agent finishes.
