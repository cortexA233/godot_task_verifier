param(
    [string]$Godot = "C:\Godot_v4.6\Godot_v4.6-stable_win64_console.exe",
    [string]$OutRoot = "$PSScriptRoot\artifacts\trajectory-shadow-calibration",
    [string]$ProbeCandidateRoot = "$PSScriptRoot\artifacts\probe-candidates"
)

$ErrorActionPreference = "Stop"
$Verifier = $PSScriptRoot

if (-not (Test-Path $Godot)) {
    throw "Godot 4.6 console executable not found at $Godot"
}

if (-not (Test-Path $ProbeCandidateRoot)) {
    $mainVerifierProbeRoot = "C:\recent_project\roboblast-grenade-verifier\artifacts\probe-candidates"
    if (Test-Path $mainVerifierProbeRoot) {
        $ProbeCandidateRoot = $mainVerifierProbeRoot
    }
}

$Cases = @(
    @{ Name = "reference"; Project = "C:\recent_project\godot-4-3d-third-person-controller-agent-runs-20260703-151656\reference-main-complete" },
    @{ Name = "ablated"; Project = "C:\recent_project\godot-4-3d-third-person-controller-agent-runs-20260703-151656\rollout-task\workspace" },
    @{ Name = "fixed-trajectory"; Project = "$ProbeCandidateRoot\fixed-trajectory" },
    @{ Name = "damage-no-preview"; Project = "$ProbeCandidateRoot\damage-no-preview" },
    @{ Name = "sonnet-3"; Project = "C:\recent_project\godot-4-3d-third-person-controller-agent-runs-20260703-151656\run-03-cc-sonnet\workspace" },
    @{ Name = "high-score-codex"; Project = "C:\recent_project\godot-4-3d-third-person-controller-agent-runs-20260703-151656\run-03-codex\workspace" }
)

New-Item -ItemType Directory -Force -Path $OutRoot | Out-Null

foreach ($Case in $Cases) {
    $project = [string]$Case.Project
    if (-not (Test-Path (Join-Path $project "project.godot"))) {
        throw "Project for $($Case.Name) does not contain project.godot: $project"
    }
    $outDir = Join-Path $OutRoot $Case.Name
    Write-Host "Running trajectory-shadow probe for $($Case.Name)"
    python (Join-Path $Verifier "run_screenshot_probe.py") `
        --project $project `
        --godot $Godot `
        --out-dir $outDir `
        --mode trajectory-shadow `
        --timeout 180
}

Write-Host ""
Write-Host "Trajectory shadow calibration summary"
Get-ChildItem $OutRoot -Directory | Sort-Object Name | ForEach-Object {
    $resultPath = Join-Path $_.FullName "result.json"
    if (-not (Test-Path $resultPath)) {
        Write-Host "$($_.Name): missing result.json"
        return
    }
    $result = Get-Content $resultPath -Raw | ConvertFrom-Json
    $shadow = $result.modes.trajectory_shadow
    $summary = $shadow.summary
    Write-Host ("{0}: verdict={1} healthy={2} suspect={3} missing={4} gameplay_visible={5} side_arc={6} runtime_match={7} centroid_spread={8}" -f `
        $_.Name, `
        $shadow.provisional_verdict, `
        $summary.healthy_heading_count, `
        $summary.suspect_heading_count, `
        $summary.missing_heading_count, `
        $summary.gameplay_preview_visible_count, `
        $summary.side_preview_arc_like_count, `
        $summary.runtime_direction_match_count, `
        $summary.gameplay_centroid_spread_px)
}
