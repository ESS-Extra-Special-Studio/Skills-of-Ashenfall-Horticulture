# Builds the release zip for Skills of Ashenfall: Horticulture from an allowlist.
#
# Only files tracked by git AND matching $Allow are packed, so local files
# (dev.txt, dev-unlock.txt, spike.txt, showcase.txt, config.txt, logs) can
# never ship; config.txt is written with defaults on first run. placement.txt
# ships only once a verified book position is committed. The zip holds one SkillsOfAshenfallHorticulture folder, ready to
# drop into Content\Paks\~mods next to ESLDragonWilds and
# SkillsOfAshenfallHistorian. Run tools\check_release.ps1 first.
#   powershell -File tools\package.ps1 -Version 1.0.0
param([Parameter(Mandatory = $true)][string]$Version)
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo
$mod = 'SkillsOfAshenfallHorticulture'

$Allow = @(
    "^$mod/enabled\.txt$",
    "^$mod/placement\.txt$",
    "^$mod/(README|CHANGELOG)\.md$",
    "^$mod/LICENSE$",
    "^$mod/Scripts/[a-z_]+\.lua$",
    "^$mod/Scripts/placements/hort_plant_[a-z0-9_]+_v[0-9]{3}\.lua$",
    "^$mod/SoAHorticulture_P\.(pak|ucas|utoc)$",
    "^$mod/Textures/[a-z0-9-]+\.png$"
)
$Never = '(^|/)(dev|dev-unlock|spike|showcase|book-mesh|debug|config)\.txt$|\.log$|\.tmp$'
# main.lua requires these only when dev.txt or spike.txt is present.
$DevOnly = "^$mod/Scripts/horticulture_(dev|spike)\.lua$"

$tracked = git ls-files
$files = $tracked | Where-Object { $f = $_; ($Allow | Where-Object { $f -match $_ }).Count -gt 0 } | Where-Object { $_ -notmatch $DevOnly }
$bad = $files | Where-Object { $_ -match $Never }
if ($bad) { throw "Refusing to pack: $($bad -join ', ')" }
foreach ($need in "$mod/enabled.txt", "$mod/Scripts/main.lua", "$mod/Textures/horticulture-skill-icon.png", "$mod/README.md", "$mod/LICENSE") {
    if ($files -notcontains $need) { throw "Missing $need" }
}
$dirty = git status --porcelain -- $mod
if ($dirty) { Write-Warning "Uncommitted changes under $mod are packed as they are on disk:`n$dirty" }

$stage = Join-Path $repo "dist\stage-$Version"
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
foreach ($f in $files) {
    $to = Join-Path $stage $f
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $to) | Out-Null
    Copy-Item -LiteralPath (Join-Path $repo $f) -Destination $to
}

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
Write-Output "Packed $($files.Count) files into $zip"
