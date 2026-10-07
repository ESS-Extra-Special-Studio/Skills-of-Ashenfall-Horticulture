# Release check: required files present, nothing local tracked, Lua passes
# the static checks, the pak has the badge, and a built zip holds only file
# types CurseForge accepts. Run from the repo root before and after packaging.
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
foreach ($name in @("Scripts\main.lua", "enabled.txt", "LICENSE", "README.md", "CHANGELOG.md", "SoAHorticulture_P.pak", "SoAHorticulture_P.utoc", "SoAHorticulture_P.ucas")) {
    if (-not (Test-Path (Join-Path $mod $name))) {
        Write-Host "FAIL: $name is missing"
        $failed = $true
    }
}
# The IoStore table of contents lists its package file names in plain text.
$utoc = Join-Path $mod "SoAHorticulture_P.utoc"
if ((Test-Path $utoc) -and -not [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($utoc)).Contains("T_HorticultureSkillIcon.uasset")) {
    Write-Host "FAIL: SoAHorticulture_P has no T_HorticultureSkillIcon badge"
    $failed = $true
}
foreach ($z in Get-ChildItem (Join-Path $root "dist") -Filter *.zip -ErrorAction SilentlyContinue) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($z.FullName)
    try { $wrong = @($archive.Entries | Where-Object { $_.Name -and $_.Name -notmatch '\.(txt|lua|dll|pak|utoc|ucas)$' } | ForEach-Object FullName) }
    finally { $archive.Dispose() }
    foreach ($w in $wrong) { Write-Host "FAIL: dist\$($z.Name) holds $w (CurseForge accepts .txt .lua .dll .pak .utoc .ucas only)"; $failed = $true }
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
