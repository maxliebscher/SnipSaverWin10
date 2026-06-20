param(
    [switch]$Portable,
    [switch]$NoAutostart
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\SnipSaver-Core.ps1"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$launcherPath = Join-Path $scriptRoot $(if ($Portable) { 'Run-SnipSaver-Tray-Portable.cmd' } else { 'Run-SnipSaver-Tray.cmd' })

if (-not (Test-Path -LiteralPath $launcherPath)) {
    throw "Missing launcher: $launcherPath"
}

$state = New-SnipSaverState -ScriptRoot $scriptRoot -Portable:$Portable
Import-SnipSaverConfig -State $state
$state.Config.autoStart = -not [bool]$NoAutostart
Export-SnipSaverConfig -State $state
Ensure-SnipSaverAutostart -State $state

if ($state.Config.autoStart) {
    Write-Host "Installed SnipSaver autostart for current user."
}
else {
    Write-Host "Installed SnipSaver without autostart."
}

Write-Host "Clipboard retention is enabled by default. On Windows 10, if PNG clipboard retention repeats saves, switch clipboard format to JPG or turn clipboard retention off in Settings."
