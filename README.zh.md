# RoboBlast Grenade Verifier 中文预览版

这是 RoboBlast 手榴弹武器 benchmark 的私有外部 verifier。它以行为为准给候选 Godot 项目打 0-100 分：先把候选项目复制到临时目录，再注入 `verifier_godot/__verifier__`，然后以 headless 模式运行 Godot，最后写出结构化评分产物。

本仓库的作业源头是 `game_take_home.html`。`BENCHMARK.md` 记录 benchmark 设计、agent 评估协议、候选项目接口契约、分数解释和可复现规则。

## 仓库地图

| 路径 | 用途 |
| --- | --- |
| `run_grader.py` | headless 评分的主 CLI 入口。 |
| `verifier_godot/__verifier__/` | Godot 侧的确定性行为检查。 |
| `report_renderer.py`, `render_report.py` | PDF 评分报告生成。 |
| `export_debug_arena.py` | 导出与 verifier 布局一致的手动 Godot debug arena。 |
| `BENCHMARK.md` | benchmark 定义和评估协议。 |
| `probe_matrix.md` | anti-cheat 探针预期和观测结果。 |
| `evaluation/writeup.html` | 可直接在浏览器打开、带视觉素材的作业 writeup。 |
| `evaluation/evidence/` | 校准和探针用的精选 score JSON 证据。 |
| `evaluation/probes/` | 用于测试 verifier 鲁棒性的 near-miss fake solution。 |
| `skills/prepare-agent-run-workspace/` | 准备隔离 agent run workspace 的 repo-local skill。 |
| `skills/collect-agent-run-evidence/` | agent 完成后收集客观运行证据的 repo-local skill。 |
| `tests/` | 覆盖 runner 行为、报告渲染、导出和一致性检查的 Python 测试。 |

## 依赖

- Godot 4.6 console executable。
- Python 3.11+。
- 如果需要渲染 PDF 或运行完整测试套件，安装报告/测试依赖：

```powershell
python -m pip install -r requirements.txt
```

## 快速开始

先设置本地 checkout 和工具路径：

```powershell
$Verifier = "<path-to-this-repo>"
$Godot = "<path-to-godot-4.6-console-executable>"
$Project = "<path-to-candidate-project>"
```

对一个候选 Godot 项目运行 verifier：

```powershell
python "$Verifier\run_grader.py" `
  --project "$Project" `
  --godot "$Godot" `
  --out "$Verifier\artifacts\score.json" `
  --log "$Verifier\artifacts\godot-verifier.log"
```

在同一次评分中写出详细 PDF 报告：

```powershell
python "$Verifier\run_grader.py" `
  --project "$Project" `
  --godot "$Godot" `
  --out "$Verifier\artifacts\score.json" `
  --pdf-report "$Verifier\artifacts\score-report.pdf" `
  --log "$Verifier\artifacts\godot-verifier.log"
```

也可以之后从已有 score JSON 渲染 PDF：

```powershell
python "$Verifier\render_report.py" `
  "$Verifier\artifacts\score.json" `
  "$Verifier\artifacts\score-report.pdf"
```

## Verifier 检查什么

Verifier 评分的是可观察到的 gameplay 行为，而不是固定文件名、类名、节点路径或 signal 名。它会在确定性 arena 中运行真实游戏系统，检查候选实现是否做出了可用的手榴弹武器，同时保留 RoboBlast 原有 gameplay。

评分分类：

| 分类 | 分值 |
| --- | ---: |
| `weapon_controls` | 15 |
| `hud_feedback` | 10 |
| `trajectory_preview` | 30 |
| `projectile_physics` | 15 |
| `explosion_gameplay` | 20 |
| `visual_audio_polish` | 5 |
| `stability_repeatability` | 5 |

Score JSON 也把正式 benchmark 暴露为 `logic_score` 和 `logic_max_score`。它和 `score/max_score` 是同一个 100 分正式分数，包含现有的 `visual_audio_polish` 分类。基于截图的视觉分析由 screenshot probe 作为辅助证据单独报告，不计入 100 分 benchmark 分数或 pass threshold。

`visual_audio_polish` 包含运行时检查：被抛出、正在移动的 grenade projectile 必须带有可见的非 placeholder 模型。内置 primitive placeholder mesh，以及明显复用的 bullet、coin、trajectory 或 explosion asset，不会获得这项模型分。

武器切换是行为评分。Verifier 会优先驱动 `swap_weapons` 或 `weapon_switch` input action；如果候选实现直接处理玩家可见的 `Tab` key path，verifier 会退回到通过 Godot input event path 注入真实 `Tab` 输入。手柄绑定分会单独记录，不依赖具体 action 名。

`passed` 字段只是报告便利项。目前它要求 `score >= 85`，并且核心 gameplay 分类至少拿到半分线：`trajectory_preview >= 15`、`projectile_physics >= 8`、`explosion_gameplay >= 10`，再加上视觉呈现 floor：`visual_audio_polish >= 4`。主要 benchmark 信号仍然是 0-100 总分和分类明细。

Score JSON 也可能包含软性的 `suspect` flag 和 `suspect_reasons`，用于提示人工复核。典型原因包括全局伤害 sweep、far/side/rear safety target 被误伤，以及玩家自伤。

## Agent Run 流程

被评测的 agent 只能拿到 ablated task workspace 和 agent-facing prompt。不要把 verifier 仓库、隐藏测试、评分细节、原始解法历史、校准产物或其他 task 分支给 agent。

### Skills

这两个 repo-local skill 按信任边界和时间点拆开。被评测的 agent 不应该运行任何一个脚本。

#### `prepare-agent-run-workspace`

在 agent 开始前使用。它是 evaluator/operator 侧的 setup 步骤：从 ablated task project 创建隔离的 `workspace/`，并在旁边创建 evaluator 拥有的 `evidence/`。

它会剥离 hidden/verifier/solution 文件，在 `workspace/` 中初始化一个新的本地 git repo，创建 baseline commit，把任务 prompt 复制到 `evidence/prompt.md`，并写出 `evidence/run-manifest.json`、`evidence/baseline-sha.txt` 和 `evidence/prompt-for-agent.md`。

给 agent 的内容只应该是准备好的 `workspace/` 路径，以及 `evidence/prompt-for-agent.md` 的文本。不要把 `evidence/`、verifier 仓库、原始解法历史、隐藏 probes 或评分细节给 agent。

#### `collect-agent-run-evidence`

在 agent 停止后使用。它是 evaluator/operator 侧的 finalization 步骤，用来记录 agent 在准备好的 workspace 中实际改了什么。

它会读取 `workspace/` 中的本地 git repo，记录 `git-status.txt`，写出从 baseline 到最终状态的 binary-capable `diff.patch`，创建或记录 `final-sha.txt`，在 agent 创建了 `AGENT_RUN_RECORD.md` 时复制它，并更新 `run-manifest.json` 中的 finalized evidence paths。

外部 verifier 跑完后，用 `--score-json` 和 `--grader-command` 再调用一次，让 `evidence/` 中包含 score artifact 和产生它的精确命令。`AGENT_RUN_RECORD.md` 只能当作有用上下文，不能当作客观证据；正式证据是 diff、manifest、score JSON、log、grader command，以及 transcript/tool artifacts。

### Commands

正式 rollout run 推荐使用 repo-local preparation skill：

```powershell
$Verifier = "<path-to-this-repo>"
$AblatedProject = "<path-to-ablated-task-project>"
$RunRoot = "<path-to-agent-runs>\run-01-cc-sonnet"
$TaskPrompt = "<path-to-task-prompt>\TASK_PROMPT.md"

python "$Verifier\skills\prepare-agent-run-workspace\scripts\setup_agent_run.py" `
  --source "$AblatedProject" `
  --run-root "$RunRoot" `
  --agent cc-sonnet `
  --model "model/version if known" `
  --tool "Godot MCP available" `
  --godot-mcp available `
  --prompt "$TaskPrompt"
```

这个命令会创建给 agent 使用的 `workspace/`，并在旁边创建 evaluator 拥有的 `evidence/`。给 agent 的内容应是 `workspace/` 路径和 `evidence/prompt-for-agent.md` 的文本。

Agent 完成后，收集客观证据：

```powershell
python "$Verifier\skills\collect-agent-run-evidence\scripts\finalize_agent_run.py" `
  --run-root "$RunRoot"
```

运行 verifier 后，再带着 score 和精确 grader command 重新收集一次证据：

```powershell
$ScoreJson = "<path-to-score-json>"
$GraderCommand = 'python "<path-to-this-repo>\run_grader.py" --project "<path-to-agent-run>\workspace" --godot "<path-to-godot-4.6-console-executable>" --out "<path-to-score-json>"'

python "$Verifier\skills\collect-agent-run-evidence\scripts\finalize_agent_run.py" `
  --run-root "$RunRoot" `
  --score-json "$ScoreJson" `
  --grader-command "$GraderCommand"
```

如果只需要一个不带 baseline/evidence metadata 的干净 rollout copy，可以用：

```powershell
python "$Verifier\prepare_rollout_workspace.py" `
  --project "$AblatedProject" `
  --out "<path-to-clean-rollout-workspace>" `
  --force
```

## Debug Arena 导出

导出 verifier arena，方便在 Godot 中手动检查：

```powershell
python "$Verifier\export_debug_arena.py" `
  --project "$Project" `
  --out "$Verifier\artifacts\debug-arena"
```

在 Godot 中打开导出的项目，然后运行：

```text
res://__verifier__/debug_arena.tscn
```

Debug scene 使用和 grader 相同的确定性 arena shell 与固定 seed target 生成逻辑。它会测量默认投掷距离，放置近距离 damage target 和 far/side/rear safety target，并加入 camera、light、floor 和 label 方便检查。

Verifier 拥有的场景启用了 mouse safety。Debug arena 启动时 cursor 可见，`F8` 可临时切换 mouse capture 方便手动瞄准，`Esc` 会释放 cursor。自动 grenade throw 仍然使用 Godot input action，不需要捕获 cursor。

## Experimental Screenshot Probe

Screenshot probe 是辅助视觉证据 runner。它不是正式 0-100 分的一部分，每个结果都会标记 `used_for_score: false`。

```powershell
python "$Verifier\run_screenshot_probe.py" `
  --project "$Project" `
  --godot "C:\Godot_v4.6\Godot_v4.6-stable_win64_console.exe" `
  --out-dir "$Verifier\artifacts\screenshot-probe" `
  --mode both
```

模式：

| Mode | Evidence |
| --- | --- |
| `debug-arena` | 在受控 verifier arena 中，grenade throw 后每 10 个 physics frame 截图，直到 explosion 或 timeout。 |
| `main-scene` | 当 playable scene 暴露 player 和 camera 时，对真实 `res://main.tscn` 写出 ready、aim、grenade-ready 和 post-throw 截图。 |
| `both` | 两种视觉模式都运行，并分别写出 `debug_arena/` 和 `main_scene/` artifact folder。 |

顶层 `result.json` 每个尝试过的视觉 run 都有一个 `modes` entry。它也包含 screenshot visual analysis 的 `auxiliary_score_sections` entry；该分数标记为 `used_for_score: false`，不计入正式 100 分 verifier score。Headless 机器可能无法进行 windowed rendering，这会被记录为 probe infrastructure state，而不是 candidate scoring failure。

## 校准和证据

运行本地 calibration：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$Verifier\run_calibration.ps1"
```

这个脚本会重跑 ablated 和 reference 检查。下面 probe 和 rollout 行是由 probe materializer 与 agent-run evidence workflow 产出的 curated evidence，不是单靠 `run_calibration.ps1` 生成。

最新本地 calibration 记录于 2026-07-03，使用 Godot `4.6.stable.official.89cea1439`，pass line 为 `score >= 85`。

| 候选或探针 | 分数 | 结果 |
| --- | ---: | --- |
| Ablated task branch `codex/grenade-rollout-task` at `fb0fd4f` | 13/100 | 按预期失败。 |
| Reference `main` at `1cf08f7` | 91/100 | 通过。 |
| Global targetable sweep probe at `14310ca` | 78/100 | 失败；`explosion_gameplay` capped to 4/20。 |
| HUD-only probe | 19/100 | 已捕获。 |
| Visual-only/no-damage probe | 34/100 | 已捕获。 |
| Damage-without-preview probe | 54/100 | 已捕获。 |
| Fixed-trajectory probe | 65/100 | 已捕获。 |
| Bad-distance probe | 50/100 | 已捕获。 |
| Single-use probe | 75/100 | 已捕获。 |
| Wrong projectile model overlay on the 100-point Codex candidate | 98/100 | `passed: false`；`visual_audio_polish` floor 捕获 placeholder model。 |

精选 calibration 和 probe score JSON 位于 `evaluation/evidence/`。Anti-cheat 预期记录在 `probe_matrix.md`。

游戏仓库里的已发布 rollout 分支记录了每个 agent family 各 3 次尝试。每个分支都在 `evaluation/agent-runs/<run>/` 下包含 branch-captured `score.json`、`score-report.pdf`、`diff.patch`、verifier log、grader command 和 run manifest：

| Agent run family | 分数 |
| --- | --- |
| `agent-run/01-codex` through `agent-run/03-codex` | 73/100, 75/100, 100/100，来自当前 verifier 和 PDF reports |
| `agent-run/01-cc-opus` through `agent-run/03-cc-opus` | 74/100, 88/100, 80/100 |
| `agent-run/01-cc-sonnet` through `agent-run/03-cc-sonnet` | 77/100, 82/100, 59/100 |

替换后的 Codex score JSON、PDF reports、logs、commands 和 manifests 保存在 `evaluation/evidence/agent-runs-20260703-151656/run-0{1,2,3}-codex/`。

本仓库的作业 writeup 是 `evaluation/writeup.html`。

## 开发

运行单元测试：

```powershell
python -m unittest discover -s tests -v
```

常用窄验证：

```powershell
python run_grader.py --help
python -m py_compile run_grader.py report_renderer.py render_report.py export_debug_arena.py
```

生成的运行时产物默认不要入 git，除非它们是有意整理过的证据。常用 scratch 位置是 `artifacts/` 和 `tmp/`。
