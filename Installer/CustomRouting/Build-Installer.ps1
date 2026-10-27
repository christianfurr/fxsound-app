[CmdletBinding()]
param(
    [string]$RepoRoot = (Join-Path $PSScriptRoot '..\..'),
    [string]$OutputDirectory = (Join-Path $PSScriptRoot 'output'),
    [string]$CompilerPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$executable = Join-Path $RepoRoot 'bin\x64\FxSound.exe'
$presets = Join-Path $RepoRoot 'bin\x64\Factsoft'
$officialHash = '3e4c6aead03e1dd9f093de4ff9842b8d7ed9487f8b033a87c3ab83e5f65ca710'
$officialUrl = 'https://raw.githubusercontent.com/fxsound2/fxsound-app/37463e50a1ac3cda3baff8445a6070a37bf495e4/release/fxsound_setup.exe'

if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
    throw 'Build Release | x64 first. bin\x64\FxSound.exe was not found.'
}
$bytes = [System.IO.File]::ReadAllBytes($executable)
if ($bytes.Length -lt 64 -or $bytes[0] -ne 0x4D -or $bytes[1] -ne 0x5A) {
    throw 'FxSound.exe is not a Windows executable.'
}
$peOffset = [BitConverter]::ToInt32($bytes, 0x3C)
if ($peOffset -lt 0 -or $peOffset -gt ($bytes.Length - 6) -or
    [BitConverter]::ToUInt32($bytes, $peOffset) -ne 0x00004550 -or
    [BitConverter]::ToUInt16($bytes, $peOffset + 4) -ne 0x8664) {
    throw 'The installer requires an x64 Windows build of FxSound.'
}
if (-not [System.Text.Encoding]::Unicode.GetString($bytes).Contains('user_selected_input')) {
    throw 'This executable does not contain the custom input setting. Rebuild the audio-routing branch.'
}
if (@(Get-ChildItem -LiteralPath $presets -Filter '*.fac' -File).Count -eq 0) {
    throw 'No factory presets were found in bin\x64\Factsoft.'
}

if ([string]::IsNullOrWhiteSpace($CompilerPath)) {
    $compilerCommand = Get-Command 'ISCC.exe' -ErrorAction SilentlyContinue
    if ($compilerCommand) { $CompilerPath = $compilerCommand.Source }
    foreach ($programFiles in @(${env:ProgramFiles(x86)}, $env:ProgramFiles)) {
        if ([string]::IsNullOrWhiteSpace($programFiles)) { continue }
        foreach ($version in @('Inno Setup 6', 'Inno Setup 7')) {
            $candidate = Join-Path $programFiles "$version\ISCC.exe"
            if (-not $CompilerPath -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
                $CompilerPath = $candidate
            }
        }
    }
}
if (-not $CompilerPath -or -not (Test-Path -LiteralPath $CompilerPath -PathType Leaf)) {
    throw 'Install Inno Setup 6.3 or newer from https://jrsoftware.org/isdl.php, then run this script again.'
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$OutputDirectory = (Resolve-Path -LiteralPath $OutputDirectory).Path
$staging = Join-Path ([System.IO.Path]::GetTempPath()) ('FxSoundCustom-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $staging 'app\Factsoft') -Force | Out-Null
try {
    Copy-Item -LiteralPath $executable -Destination (Join-Path $staging 'app\FxSound.exe')
    Get-ChildItem -LiteralPath $presets -Filter '*.fac' -File |
        Copy-Item -Destination (Join-Path $staging 'app\Factsoft')
    $fonts = Join-Path $RepoRoot 'Installer\Resources\Fonts'
    if (Test-Path -LiteralPath $fonts -PathType Container) {
        Get-ChildItem -LiteralPath $fonts -File |
            Where-Object { $_.Extension -in @('.ttf', '.otf') } |
            Copy-Item -Destination (Join-Path $staging 'app')
    }
    Copy-Item -LiteralPath (Join-Path $RepoRoot 'LICENSE') -Destination (Join-Path $staging 'LICENSE.txt')
    $sourceDescription = @'
FxSound Custom - selectable audio inputs and routing preferences

Application source: https://github.com/christianfurr/fxsound-app/tree/feat/custom-routing-installer
Upstream contribution: https://github.com/fxsound2/fxsound-app/pull/665
Resources: https://github.com/fxsound2/Resources/tree/8f0385f015cd6b10026b2db6a0625a6db4de89b0
Application license: GNU Affero General Public License v3.0 (see LICENSE.txt).

This is a community custom build. The bundled prerequisite is the original,
unmodified FxSound 1.2.16.0 installer from the upstream project. It supplies
the existing signed audio driver; this custom package does not build a driver.
'@
    Set-Content -LiteralPath (Join-Path $staging 'SOURCE.txt') -Value $sourceDescription -Encoding UTF8
    $installNotes = @'
This installs FxSound Custom with selectable playback and recording inputs.

Exit any running FxSound instance using its tray icon before continuing.

If the official audio driver is missing, setup opens the bundled official
FxSound installer first. Complete it, exit the official app if it launches,
and click Retry here. Administrator permission is required for installation.

The custom application is installed separately in Program Files\FxSound Custom.
Open FxSound Custom from the Start menu, then choose Settings > Routing.

The custom and official applications share presets/settings and cannot run
at the same time. Uninstalling FxSound Custom leaves the official driver,
official application, and your shared presets/settings in place.
'@
    Set-Content -LiteralPath (Join-Path $staging 'INSTALL-NOTES.txt') -Value $installNotes -Encoding UTF8

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $official = Join-Path $staging 'fxsound-official-1.2.16.exe'
    Write-Host 'Downloading the official FxSound driver prerequisite...'
    Invoke-WebRequest -Uri $officialUrl -OutFile $official -UseBasicParsing
    if ((Get-FileHash -LiteralPath $official -Algorithm SHA256).Hash.ToLowerInvariant() -ne $officialHash) {
        throw 'The official FxSound download did not match its pinned SHA-256.'
    }
    Write-Host 'Compiling FxSoundCustomSetup.exe...'
    & $CompilerPath "/DPayloadDir=$staging" "/O$OutputDirectory" (Join-Path $PSScriptRoot 'FxSoundCustom.iss')
    if ($LASTEXITCODE -ne 0) { throw "Inno Setup failed with exit code $LASTEXITCODE." }
    $installer = Join-Path $OutputDirectory 'FxSoundCustomSetup.exe'
    if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) {
        throw 'Inno Setup did not produce the expected installer.'
    }
    $hash = (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash.ToLowerInvariant()
    Set-Content -LiteralPath (Join-Path $OutputDirectory 'SHA256SUMS.txt') -Value "$hash  FxSoundCustomSetup.exe" -Encoding ASCII
    Copy-Item -LiteralPath (Join-Path $staging 'SOURCE.txt') -Destination $OutputDirectory
    Write-Host "Created $installer"
} finally {
    Remove-Item -LiteralPath $staging -Recurse -Force
}
