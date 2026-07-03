# Issue tracker: GitHub

Issues and PRDs for this repo live as GitHub issues. Use the `gh` CLI for issue operations.

## Repository

Infer the repository from `git remote -v`. In this clone, `origin` points to:

```text
https://github.com/cortexA233/godot_task_verifier.git
```

## Conventions

- Create an issue: `gh issue create --title "..." --body "..."`
- Read an issue: `gh issue view <number> --comments`
- List issues: `gh issue list --state open --json number,title,body,labels,comments`
- Comment on an issue: `gh issue comment <number> --body "..."`
- Apply or remove labels: `gh issue edit <number> --add-label "..."` or `--remove-label "..."`
- Close an issue: `gh issue close <number> --comment "..."`

Use heredocs or temporary files for multi-line issue bodies.

## Pull requests as a triage surface

PRs as a request surface: no.

`/triage` should process GitHub issues only. Do not pull external PRs into the triage queue unless this file is updated later.

## Skill behavior

When a skill says "publish to the issue tracker", create a GitHub issue.

When a skill says "fetch the relevant ticket", run `gh issue view <number> --comments`.
