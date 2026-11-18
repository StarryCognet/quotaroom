# Builds the three Windows distribution forms from a Flutter release build:
#   - portable zip
#   - Inno Setup installer (setup.exe)
#   - 7-Zip SFX single-file launcher (single.exe)
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File tool/package_windows.ps1 -Version 2.2.1
#
# Optional tool paths (auto-detected by default):
#   -SevenZip C:\path\to\7z.exe
#   -Iscc C:\path\to\ISCC.exe
#   -SkipInstaller / -SkipSingleFile
param(
    [Parameter(Mandatory = $true)]
    [string]$Version,

    [string]$ReleaseDir = "",
    [string]$OutputDir = "",

    [string]$SevenZip = "",
    [string]$Iscc = "",

    [switch]$SkipInstaller,
    [switch]$SkipSingleFile
)

$ErrorActionPreference = "Stop"

$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if (-not $ReleaseDir) {
    $ReleaseDir = Join-Path $root "build\windows\x64\runner\Release"
}
if (-not $OutputDir) {
    $OutputDir = Join-Path $root "dist"
}

$ReleaseDir = (Resolve-Path -LiteralPath $ReleaseDir).Path.TrimEnd('\')
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$OutputDir = (Resolve-Path -LiteralPath $OutputDir).Path

$exePath = Join-Path $ReleaseDir "QuotaRoom.exe"
if (-not (Test-Path -LiteralPath $exePath)) {
    throw "QuotaRoom.exe not found in $ReleaseDir. Run 'flutter build windows --release' first."
}

function Find-Tool {
    param(
        [string]$Name,
        [string[]]$Candidates
    )
    if ($Name -and (Test-Path -LiteralPath $Name)) {
        return (Resolve-Path -LiteralPath $Name).Path
    }
    foreach ($candidate in $Candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    if ($Name) {
        $command = Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($command) {
            return $command.Source
        }
    }
    return $null
}

$portablePath = Join-Path $OutputDir "QuotaRoom-v$Version-windows-x64.zip"
$setupPath = Join-Path $OutputDir "QuotaRoom-v$Version-windows-x64-setup.exe"
$singlePath = Join-Path $OutputDir "QuotaRoom-v$Version-windows-x64-single.exe"

# Avoid checksumming stale outputs from an earlier run when a form is skipped.
Remove-Item -LiteralPath $portablePath, $setupPath, $singlePath -Force -ErrorAction SilentlyContinue

Write-Host "==> Portable zip"
Compress-Archive -Path (Join-Path $ReleaseDir '*') -DestinationPath $portablePath -Force

if (-not $SkipInstaller) {
    Write-Host "==> Inno Setup installer"
    $isccPath = Find-Tool -Name $Iscc -Candidates @(
        "$env:ProgramFiles\Inno Setup 7\ISCC.exe",
        "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
        "${env:ProgramFiles(x86)}\Inno Setup 7\ISCC.exe",
        "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
        "$env:LOCALAPPDATA\Programs\Inno Setup 7\ISCC.exe",
        "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
    )
    if (-not $isccPath) {
        throw "ISCC.exe not found. Install Inno Setup (https://jrsoftware.org/isdl.php) or pass -Iscc <path>."
    }
    $issPath = Join-Path $root "windows\installer\QuotaRoom.iss"
    & $isccPath "/DMyAppVersion=$Version" "/DSourceDir=$ReleaseDir" "/DOutputDir=$OutputDir" $issPath
    if ($LASTEXITCODE -ne 0) {
        throw "Inno Setup failed with exit code $LASTEXITCODE."
    }
    if (-not (Test-Path -LiteralPath $setupPath)) {
        throw "Inno Setup did not produce $setupPath."
    }
}

if (-not $SkipSingleFile) {
    Write-Host "==> Single-file launcher"
    $sevenZipPath = Find-Tool -Name $SevenZip -Candidates @(
        "$env:ProgramFiles\7-Zip\7z.exe",
        "${env:ProgramFiles(x86)}\7-Zip\7z.exe",
        "$env:LOCALAPPDATA\Programs\7-Zip\7z.exe"
    )
    if (-not $sevenZipPath) {
        throw "7z.exe not found. Install 7-Zip or pass -SevenZip <path>."
    }
    $sfxModule = Join-Path $root "windows\sfx\7zSD.sfx"
    if (-not (Test-Path -LiteralPath $sfxModule)) {
        throw "7zSD.sfx not found at $sfxModule."
    }
    $configTemplate = Get-Content -LiteralPath (Join-Path $root "windows\sfx\config.txt") -Raw -Encoding UTF8
    $configText = $configTemplate.Replace("__VERSION__", $Version)

    $tempBase = [IO.Path]::Combine($env:TEMP, "QuotaRoom-package-" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $tempBase | Out-Null
    $archivePath = Join-Path $tempBase "app.7z"
    $configPath = Join-Path $tempBase "config.txt"
    try {
        [IO.File]::WriteAllText($configPath, $configText, (New-Object System.Text.UTF8Encoding($false)))

        Push-Location $ReleaseDir
        try {
            & $sevenZipPath a -t7z -mx=9 -ms=on -y $archivePath ".\*" | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "7-Zip failed with exit code $LASTEXITCODE."
            }
        } finally {
            Pop-Location
        }

        $stream = [IO.File]::Open($singlePath, [IO.FileMode]::Create, [IO.FileAccess]::Write)
        try {
            foreach ($part in @($sfxModule, $configPath, $archivePath)) {
                $bytes = [IO.File]::ReadAllBytes($part)
                $stream.Write($bytes, 0, $bytes.Length)
            }
        } finally {
            $stream.Dispose()
        }
    } finally {
        Remove-Item -LiteralPath $tempBase -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$assets = @(
    @{ Path = $portablePath; Name = "portable zip"; Required = $true },
    @{ Path = $setupPath; Name = "installer"; Required = (-not $SkipInstaller) },
    @{ Path = $singlePath; Name = "single-file"; Required = (-not $SkipSingleFile) }
)

$checksumLines = New-Object System.Collections.Generic.List[string]
foreach ($asset in $assets) {
    if (-not (Test-Path -LiteralPath $asset.Path)) {
        if ($asset.Required) {
            throw "Missing expected asset: $($asset.Path)"
        }
        continue
    }
    $file = Get-Item -LiteralPath $asset.Path
    $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLower()
    $checksumLines.Add("$hash  $($file.Name)")
    Write-Host ("    {0,-22} {1,8:N1} MB" -f $asset.Name, ($file.Length / 1MB))
}

$sumsPath = Join-Path $OutputDir "SHA256SUMS-windows.txt"
[IO.File]::WriteAllText($sumsPath, (($checksumLines -join "`n") + "`n"), (New-Object System.Text.ASCIIEncoding))
Write-Host "==> Checksums written to $sumsPath"
Write-Host "Done. Output: $OutputDir"
