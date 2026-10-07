# Builds the release zip for Skills of Ashenfall: Horticulture from an allowlist.
#
# Only files tracked by git AND matching $Allow are packed, so local files
# (config.txt, meshes.txt, logs) can never ship; config.txt is written with
# defaults on first run. The zip holds one SkillsOfAshenfallHorticulture
# folder, ready to drop into Content\Paks\~mods next to ESLDragonWilds and
# SkillsOfAshenfallHistorian. Run tools\check_release.ps1 first.
# CurseForge only accepts .txt .lua .dll .pak .utoc .ucas in a Dragonwilds
# UE4SS mod: the docs ship as .txt copies and the badge ships cooked in
# SoAHorticulture_P (the PNG stays in the repo as the source for
# DragonwildsAssets' cook).
#   powershell -File tools\package.ps1 -Version 1.0.0
param([Parameter(Mandatory = $true)][string]$Version)
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo
$mod = 'SkillsOfAshenfallHorticulture'

$Allow = @(
    "^$mod/enabled\.txt$",
    "^$mod/Scripts/[a-z_]+\.lua$",
    "^$mod/Scripts/placements/hort_plant_[a-z0-9_]+_v[0-9]{3}\.lua$",
    "^$mod/Scripts/placements/hort_fruit_layers_v[0-9]{3}\.lua$",
    "^$mod/SoAHorticulture_P\.(pak|ucas|utoc)$"
)
# Repo file -> name in the zip.
$Docs = [ordered]@{ "$mod/README.md" = "$mod/README.txt"; "$mod/LICENSE" = "$mod/LICENSE.txt"; "$mod/CHANGELOG.md" = "$mod/CHANGELOG.txt" }
$AllowedTypes = '\.(txt|lua|dll|pak|utoc|ucas)$'
$Never = '(^|/)(dev|debug|config)\.txt$|\.log$|\.tmp$'

$tracked = git ls-files
$files = $tracked | Where-Object { $f = $_; ($Allow | Where-Object { $f -match $_ }).Count -gt 0 }
$bad = $files | Where-Object { $_ -match $Never }
if ($bad) { throw "Refusing to pack: $($bad -join ', ')" }
foreach ($need in "$mod/enabled.txt", "$mod/Scripts/main.lua", "$mod/SoAHorticulture_P.pak", "$mod/SoAHorticulture_P.utoc", "$mod/SoAHorticulture_P.ucas") {
    if ($files -notcontains $need) { throw "Missing $need" }
}
foreach ($d in $Docs.Keys) { if ($tracked -notcontains $d) { throw "Missing $d" } }
$dirty = git status --porcelain -- $mod
if ($dirty) { Write-Warning "Uncommitted changes under $mod are packed as they are on disk:`n$dirty" }

$stage = Join-Path $repo "dist\stage-$Version"
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
foreach ($f in $files) {
    $to = Join-Path $stage $f
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $to) | Out-Null
    Copy-Item -LiteralPath (Join-Path $repo $f) -Destination $to
}
foreach ($d in $Docs.Keys) { Copy-Item -LiteralPath (Join-Path $repo $d) -Destination (Join-Path $stage $Docs[$d]) }
$wrongType = Get-ChildItem -LiteralPath $stage -Recurse -File -Force | Where-Object { $_.Name -notmatch $AllowedTypes }
if ($wrongType) { throw "Refusing to pack file types CurseForge rejects: $(($wrongType | ForEach-Object Name) -join ', ')" }

$zip = Join-Path $repo "dist\$mod-$Version.zip"
if (Test-Path $zip) { Remove-Item -Force $zip }
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::Open($zip, 'Create')
try {
    # Forward slashes in entry names, so every unzip tool keeps the folders.
    Get-ChildItem -LiteralPath $stage -Recurse -File -Force | ForEach-Object {
        $name = $_.FullName.Substring($stage.Length + 1).Replace('\', '/')
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $_.FullName, $name) | Out-Null
    }
} finally { $archive.Dispose() }
Remove-Item -Recurse -Force $stage
$check = [IO.Compression.ZipFile]::OpenRead($zip)
try { $bad = @($check.Entries | Where-Object { $_.Name -and $_.Name -notmatch $AllowedTypes } | ForEach-Object FullName) } finally { $check.Dispose() }
if ($bad) { Remove-Item -Force $zip; throw "Zip removed, it held file types CurseForge rejects: $($bad -join ', ')" }
Write-Output "Packed $($files.Count + $Docs.Count) files into $zip"
