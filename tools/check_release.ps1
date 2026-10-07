# Release check: required files present, nothing local tracked, Lua passes
# the static checks. Run from the repo root before packaging.
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$mod = Join-Path $root "SkillsOfAshenfallHorticulture"
$failed = $false

# The game writes config.txt on first run; tools\package.ps1 never packs it.
if (git -C $root ls-files -- "SkillsOfAshenfallHorticulture/config.txt") {
    Write-Host "FAIL: config.txt is tracked by git"
    $failed = $true
}
$local = git -C $root ls-files -- "SkillsOfAshenfallHorticulture" | Where-Object { $_ -match '(^|/)(dev|debug)[^/]*\.(txt|lua)$' }
if ($local) {
    Write-Host "FAIL: local-only files are tracked: $($local -join ', ')"
    $failed = $true
}
foreach ($name in @("Scripts\main.lua", "Textures\horticulture-skill-icon.png", "enabled.txt", "LICENSE", "README.md")) {
    if (-not (Test-Path (Join-Path $mod $name))) {
        Write-Host "FAIL: $name is missing"
        $failed = $true
    }
}
# The skill id names every player's save file.
if (-not (Select-String -Path (Join-Path $mod "Scripts\main.lua") -SimpleMatch 'local SKILL = "Horticulture"' -Quiet)) {
    Write-Host "FAIL: the skill id in main.lua is not Horticulture"
    $failed = $true
}
# The prize effect stays off until it is proven in game.
if (Select-String -Path (Join-Path $mod "Scripts\horticulture_prize.lua") -SimpleMatch "Prize.ENABLED = true" -Quiet) {
    Write-Host "WARN: prize specimens are on; ship only if they were checked in game"
}
if (Test-Path (Join-Path $mod "meshes.txt")) {
    Write-Host "WARN: meshes.txt points hybrids at other mesh paths; it is never packed"
}

$py = Join-Path $env:LOCALAPPDATA "Programs\Python\Python312\python.exe"
& $py (Join-Path $PSScriptRoot "lua_check.py")
if ($LASTEXITCODE -ne 0) { $failed = $true }
& $py (Join-Path $PSScriptRoot "training_test.py")
if ($LASTEXITCODE -ne 0) { $failed = $true }
& $py (Join-Path $PSScriptRoot "splice_test.py")
if ($LASTEXITCODE -ne 0) { $failed = $true }

if ($failed) { Write-Host "RELEASE CHECK FAILED"; exit 1 }
Write-Host "RELEASE CHECK PASSED"
