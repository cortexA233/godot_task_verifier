param(
  [string]$Godot = "C:\Godot_v4.6-stable_mono_win64\Godot_v4.6-stable_mono_win64_console.exe",
  [string]$Verifier = "C:\recent_project\roboblast-grenade-verifier",
  [string]$Ablated = "C:\recent_project\godot-4-3d-third-person-controller",
  [string]$Reference = "C:\recent_project\godot-4-3d-third-person-controller-reference"
)

$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force -Path "$Verifier\artifacts" | Out-Null

Write-Host "Running ablated calibration against $Ablated"
python "$Verifier\run_grader.py" --project "$Ablated" --godot "$Godot" --out "$Verifier\artifacts\ablated-score.json" --log "$Verifier\artifacts\ablated-score.log"

if (Test-Path $Reference) {
  Write-Host "Running reference calibration against $Reference"
  python "$Verifier\run_grader.py" --project "$Reference" --godot "$Godot" --out "$Verifier\artifacts\reference-score.json" --log "$Verifier\artifacts\reference-score.log"
} else {
  Write-Host "Reference project not found at $Reference"
}
