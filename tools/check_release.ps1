# Release check: no developer switches in the mod folder, Lua passes the
# static checks. Run from the repo root before packaging.
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$mod = Join-Path $root "SkillsOfAshenfallHorticulture"
$failed = $false

foreach ($name in @("dev.txt", "dev-unlock.txt", "book-mesh.txt")) {
    if (Test-Path (Join-Path $mod $name)) {
        Write-Host "FAIL: $name is in the mod folder; remove it before release"
        $failed = $true
    }
}
foreach ($name in @("Scripts\main.lua", "Textures\horticulture-skill-icon.png", "enabled.txt", "LICENSE", "README.md")) {
    if (-not (Test-Path (Join-Path $mod $name))) {
        Write-Host "FAIL: $name is missing"
        $failed = $true
    }
}
if (-not (Test-Path (Join-Path $mod "placement.txt"))) {
    Write-Host "WARN: no placement.txt; the book uses the unverified wiki map position"
}

$py = Join-Path $env:LOCALAPPDATA "Programs\Python\Python312\python.exe"
& $py (Join-Path $PSScriptRoot "lua_check.py")
if ($LASTEXITCODE -ne 0) { $failed = $true }
& $py (Join-Path $PSScriptRoot "training_test.py")
if ($LASTEXITCODE -ne 0) { $failed = $true }

if ($failed) { Write-Host "RELEASE CHECK FAILED"; exit 1 }
Write-Host "RELEASE CHECK PASSED"
