$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$startupFolder = [Environment]::GetFolderPath('Startup')
$shortcutPath = Join-Path $startupFolder 'SnipSaver.lnk'
$appDataPath = Join-Path $env:APPDATA 'SnipSaver'

Remove-Item -LiteralPath $shortcutPath -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $appDataPath -Recurse -Force -ErrorAction SilentlyContinue

Write-Host 'Uninstalled SnipSaver startup integration.'
