param(
  [string]$Godot = "C:\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64_console.exe",
  [string]$Verifier = "C:\recent_project\roboblast-grenade-verifier",
  [string]$Ablated = "C:\recent_project\godot-4-3d-third-person-controller\.worktrees\grenade-verifier-implementation",
  [string]$Reference = "C:\recent_project\godot-4-3d-third-person-controller-reference"
)

$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force -Path "$Verifier\artifacts" | Out-Null

python "$Verifier\run_grader.py" --project "$Ablated" --godot "$Godot" --out "$Verifier\artifacts\ablated-score.json"

if (Test-Path $Reference) {
  python "$Verifier\run_grader.py" --project "$Reference" --godot "$Godot" --out "$Verifier\artifacts\reference-score.json"
} else {
  Write-Host "Reference project not found at $Reference"
}
