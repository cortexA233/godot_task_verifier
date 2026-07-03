---
name: collect-agent-run-evidence
description: Use when an evaluated rollout or coding-agent run has finished in a prepared workspace and Codex needs to collect objective run evidence such as git status, binary diff against baseline, final commit, agent self-report, score JSON, grader command, transcript logs, or tool artifacts.
---

# Collect Agent Run Evidence

## Overview

Finalize an evaluator-owned agent run after the evaluated agent stops. This skill exports objective git evidence from a prepared `workspace/` into its adjacent `evidence/` directory.

The evaluated agent must not run this script. Run it from outside the workspace after the agent has finished.

## Quick Start

```powershell
python "$env:USERPROFILE\.codex\skills\collect-agent-run-evidence\scripts\finalize_agent_run.py" `
  --run-root C:\agent-runs\claude-code-01
```

This writes:

- `evidence\git-status.txt`: status before final staging.
- `evidence\diff.patch`: binary-capable diff from baseline to final attempt.
- `evidence\final-sha.txt`: final workspace commit SHA.
- `evidence\AGENT_RUN_RECORD.md`: copied if the agent created it.
- updated `evidence\run-manifest.json`: finalized timestamp and evidence paths.

## Optional Evidence

Record a verifier score and exact command:

```powershell
python "$env:USERPROFILE\.codex\skills\collect-agent-run-evidence\scripts\finalize_agent_run.py" `
  --run-root C:\agent-runs\claude-code-01 `
  --score-json C:\path\to\score.json `
  --grader-command 'python C:\path\to\run_grader.py --project C:\agent-runs\claude-code-01\workspace --out C:\path\to\score.json'
```

Copy transcript or tool logs into `evidence\artifacts`:

```powershell
python "$env:USERPROFILE\.codex\skills\collect-agent-run-evidence\scripts\finalize_agent_run.py" `
  --run-root C:\agent-runs\claude-code-01 `
  --artifact C:\path\to\session-transcript.jsonl `
  --artifact C:\path\to\godot-mcp-log.txt
```

## Workflow

1. Confirm the agent has stopped and no process is still editing the workspace.
2. Run `finalize_agent_run.py` with the matching `--run-root`.
3. Run the external verifier if needed.
4. Re-run finalize with `--score-json`, `--grader-command`, and any `--artifact` paths, or copy those files into `evidence/` using the same naming convention.
5. Use `diff.patch`, `run-manifest.json`, `score.json`, and transcript/tool logs as the formal report evidence.

`AGENT_RUN_RECORD.md` is useful for failure analysis but is only an agent-authored self-report. Do not treat it as objective evidence.

## Safety Rules

- Do not run this before the agent is done.
- Do not run this inside the evaluated agent as part of its task.
- Do not trust the agent self-report instead of `diff.patch` and external score artifacts.
- Do not modify the baseline SHA or manifest to make a run look cleaner.
- If a score is generated later, keep the exact grader command with the score.

## Related Skills

Use `prepare-agent-run-workspace` before the evaluated agent starts. Use `copy-agent-workspace` only for plain isolated copies that do not need run evidence.
