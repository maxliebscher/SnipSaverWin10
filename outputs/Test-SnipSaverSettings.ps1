param(
    [switch]$KeepArtifacts
)

$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptRoot 'SnipSaver-Core.ps1')

$state = New-SnipSaverState -ScriptRoot $scriptRoot
$startupFolder = [Environment]::GetFolderPath('Startup')
$shortcutPath = Join-Path $startupFolder 'SnipSaver.lnk'
$runKeyPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$runValueName = 'SnipSaver'
$artifactRoot = Join-Path $scriptRoot 'test-artifacts'
$backupRoot = Join-Path $env:TEMP ('SnipSaverTestBackup_{0}' -f ([guid]::NewGuid().ToString('N')))
$configBackup = Join-Path $backupRoot 'config.json'
$shortcutBackup = Join-Path $backupRoot 'SnipSaver.lnk'

$results = New-Object System.Collections.Generic.List[object]

function Add-Result {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][bool]$Passed,
        [string]$Details = ''
    )

    $script:results.Add([pscustomobject]@{
        Name = $Name
        Passed = $Passed
        Details = $Details
    }) | Out-Null

    if (-not $Passed) {
        throw "FAILED: $Name $Details"
    }
}

function Test-Equal {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        $Actual,
        $Expected
    )

    Add-Result -Name $Name -Passed ($Actual -eq $Expected) -Details ("expected '{0}', got '{1}'" -f $Expected, $Actual)
}

function New-TestBitmap {
    $bitmap = New-Object System.Drawing.Bitmap 32, 24
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.Clear([System.Drawing.Color]::White)
        $brush = New-Object System.Drawing.SolidBrush ([System.Drawing.ColorTranslator]::FromHtml('#00A7A0'))
        $graphics.FillRectangle($brush, 4, 4, 24, 16)
        $brush.Dispose()
        return $bitmap
    }
    finally {
        $graphics.Dispose()
    }
}

New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
if (Test-Path -LiteralPath $state.ConfigPath) {
    Copy-Item -LiteralPath $state.ConfigPath -Destination $configBackup -Force
}

$hadShortcut = Test-Path -LiteralPath $shortcutPath
if ($hadShortcut) {
    Copy-Item -LiteralPath $shortcutPath -Destination $shortcutBackup -Force
}

$hadRunValue = $false
$oldRunValue = $null
try {
    $oldRunValue = (Get-ItemProperty -Path $runKeyPath -Name $runValueName -ErrorAction Stop).$runValueName
    $hadRunValue = $true
}
catch {
}

try {
    New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null

    $defaultConfig = Get-SnipSaverDefaultConfig -State $state
    Test-Equal -Name 'default output format' -Actual $defaultConfig.outputFormat -Expected 'jpg'
    Test-Equal -Name 'default jpeg quality' -Actual $defaultConfig.jpegQuality -Expected 92
    Test-Equal -Name 'default clipboard retention' -Actual $defaultConfig.keepClipboard -Expected $true
    Test-Equal -Name 'default clipboard format' -Actual $defaultConfig.clipboardFormat -Expected 'png'
    Test-Equal -Name 'default icon theme' -Actual $defaultConfig.iconTheme -Expected 'clean-capture'

    $candidate = [pscustomobject]@{
        outputFormat = 'png'
        jpegQuality = 101
        targetDirectory = ''
        keepClipboard = $false
        clipboardFormat = 'bad'
        autoStart = $false
        languageMode = 'manual'
        language = 'fr'
        captureEnabled = $false
        iconTheme = 'warm-utility'
    }
    $merged = Merge-SnipSaverConfig -State $state -Candidate $candidate
    Test-Equal -Name 'invalid high jpeg quality clamps to 100' -Actual $merged.jpegQuality -Expected 100
    Test-Equal -Name 'blank target directory falls back' -Actual $merged.targetDirectory -Expected $state.DefaultTargetDirectory
    Test-Equal -Name 'clipboard format fallback' -Actual $merged.clipboardFormat -Expected 'png'
    Test-Equal -Name 'unsupported language resets mode' -Actual $merged.languageMode -Expected 'system'
    Test-Equal -Name 'unsupported language resets language' -Actual $merged.language -Expected 'de'
    Test-Equal -Name 'icon theme locked' -Actual $merged.iconTheme -Expected 'clean-capture'

    $candidateLow = [pscustomobject]@{ jpegQuality = 1 }
    $mergedLow = Merge-SnipSaverConfig -State $state -Candidate $candidateLow
    Test-Equal -Name 'low jpeg quality clamps to 40' -Actual $mergedLow.jpegQuality -Expected 40

    foreach ($language in @('de', 'en')) {
        $state.Config = Get-SnipSaverDefaultConfig -State $state
        $state.Config.languageMode = 'manual'
        $state.Config.language = $language
        Import-SnipSaverTranslations -State $state
        $startText = Get-SnipSaverText -State $state -Key 'menu.start'
        Add-Result -Name ("translation menu.start {0}" -f $language) -Passed (-not [string]::IsNullOrWhiteSpace($startText)) -Details $startText
    }

    $state.Config = Get-SnipSaverDefaultConfig -State $state
    $state.Config.targetDirectory = $artifactRoot
    $bitmap = New-TestBitmap
    try {
        $state.Config.outputFormat = 'jpg'
        $jpgPath = Save-SnipSaverImage -State $state -Image $bitmap -DestinationBaseName 'settings-test'
        Add-Result -Name 'jpg save creates file' -Passed (Test-Path -LiteralPath $jpgPath) -Details $jpgPath

        $state.Config.outputFormat = 'png'
        $pngPath = Save-SnipSaverImage -State $state -Image $bitmap -DestinationBaseName 'settings-test'
        Add-Result -Name 'png save creates file' -Passed (Test-Path -LiteralPath $pngPath) -Details $pngPath

        $jpgBytes = Convert-SnipSaverImageToJpegBytes -State $state -Image $bitmap
        $pngBytes = Convert-SnipSaverImageToPngBytes -Image $bitmap
        Add-Result -Name 'jpeg clipboard bytes generated' -Passed ($jpgBytes.Length -gt 100) -Details $jpgBytes.Length
        Add-Result -Name 'png clipboard bytes generated' -Passed ($pngBytes.Length -gt 100) -Details $pngBytes.Length
    }
    finally {
        $bitmap.Dispose()
    }

    $activeIcon = New-SnipSaverTrayIcon -State $state -Active:$true
    $pausedIcon = New-SnipSaverTrayIcon -State $state -Active:$false
    try {
        Test-Equal -Name 'active icon width' -Actual $activeIcon.Width -Expected 32
        Test-Equal -Name 'paused icon width' -Actual $pausedIcon.Width -Expected 32
    }
    finally {
        $activeIcon.Dispose()
        $pausedIcon.Dispose()
    }

    $state.Config = Get-SnipSaverDefaultConfig -State $state
    $state.Config.autoStart = $false
    Ensure-SnipSaverAutostart -State $state
    Add-Result -Name 'autostart off removes run value' -Passed (-not (Get-ItemProperty -Path $runKeyPath -Name $runValueName -ErrorAction SilentlyContinue)) -Details ''

    $state.Config.autoStart = $true
    Ensure-SnipSaverAutostart -State $state
    $newRunValue = (Get-ItemProperty -Path $runKeyPath -Name $runValueName -ErrorAction Stop).$runValueName
    Add-Result -Name 'autostart on writes run value' -Passed ($newRunValue -like '*Run-SnipSaver-Tray.cmd*') -Details $newRunValue
    Add-Result -Name 'autostart shortcut exists or logged' -Passed ((Test-Path -LiteralPath $shortcutPath) -or (Test-Path -LiteralPath $state.LogPath)) -Details $shortcutPath

    [pscustomobject]@{
        Passed = $true
        Count = $results.Count
        Results = $results
    } | ConvertTo-Json -Depth 6
}
finally {
    if (Test-Path -LiteralPath $configBackup) {
        Copy-Item -LiteralPath $configBackup -Destination $state.ConfigPath -Force
    }
    elseif (Test-Path -LiteralPath $state.ConfigPath) {
        Remove-Item -LiteralPath $state.ConfigPath -Force
    }

    if ($hadShortcut -and (Test-Path -LiteralPath $shortcutBackup)) {
        Copy-Item -LiteralPath $shortcutBackup -Destination $shortcutPath -Force
    }
    elseif (-not $hadShortcut -and (Test-Path -LiteralPath $shortcutPath)) {
        Remove-Item -LiteralPath $shortcutPath -Force -ErrorAction SilentlyContinue
    }

    if ($hadRunValue) {
        New-Item -Path $runKeyPath -Force | Out-Null
        Set-ItemProperty -Path $runKeyPath -Name $runValueName -Value $oldRunValue
    }
    else {
        Remove-ItemProperty -Path $runKeyPath -Name $runValueName -ErrorAction SilentlyContinue
    }

    if (-not $KeepArtifacts -and (Test-Path -LiteralPath $artifactRoot)) {
        Remove-Item -LiteralPath $artifactRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    Remove-Item -LiteralPath $backupRoot -Recurse -Force -ErrorAction SilentlyContinue
}
