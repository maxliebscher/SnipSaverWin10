Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
if (-not ('SnipSaver.NativeMethods' -as [type])) {
    Add-Type -TypeDefinition @'
namespace SnipSaver {
    public static class NativeMethods {
        [System.Runtime.InteropServices.DllImport("user32.dll")]
        public static extern uint GetClipboardSequenceNumber();
    }
}
'@
}

function New-SnipSaverState {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptRoot,

        [switch]$Portable
    )

    $defaultTargetDirectory = Join-Path $env:USERPROFILE 'Pictures\Screenshots'
    $dataRoot = if ($Portable) {
        Join-Path $ScriptRoot 'portable-data'
    }
    else {
        Join-Path $env:APPDATA 'SnipSaver'
    }

    New-Item -ItemType Directory -Path $dataRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $defaultTargetDirectory -Force | Out-Null

    $state = @{
        AppName = 'SnipSaver'
        AppVersion = '0.5.8'
        ScriptRoot = $ScriptRoot
        Portable = [bool]$Portable
        DataRoot = $dataRoot
        ConfigPath = Join-Path $dataRoot 'config.json'
        LogPath = Join-Path $dataRoot 'snipsaver.log'
        LocaleRoot = Join-Path $ScriptRoot 'locales'
        ReleaseRoot = Join-Path $ScriptRoot 'releases'
        DefaultTargetDirectory = $defaultTargetDirectory
        CaptureSourceCandidates = @(
            (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.ScreenSketch_8wekyb3d8bbwe\TempState'),
            (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.Windows.Client.CBS_cw5n1h2txyewy\TempState')
        )
        ProcessedFiles = @{}
        RecentFingerprints = @{}
        LastClipboardFingerprint = $null
        LastClipboardSequenceNumber = 0
        SourcePath = $null
        Config = $null
        Translations = @{}
        EffectiveLanguage = 'en'
        CaptureMutex = $null
        AppMutex = $null
        CaptureTimer = $null
        CaptureEnabledRuntime = $false
        Languages = @(
            [pscustomobject]@{ Code = 'de'; Label = 'Deutsch' },
            [pscustomobject]@{ Code = 'en'; Label = 'English' }
        )
        IconThemes = @(
            [pscustomobject]@{ Id = 'clean-capture'; Label = 'Clean Capture' },
            [pscustomobject]@{ Id = 'warm-utility'; Label = 'Warm Utility' },
            [pscustomobject]@{ Id = 'sharp-minimal'; Label = 'Sharp Minimal' },
            [pscustomobject]@{ Id = 'lens-badge'; Label = 'Lens Badge' }
        )
    }

    $state.Config = Get-SnipSaverDefaultConfig -State $state
    return $state
}

function Get-SnipSaverDefaultConfig {
    param([Parameter(Mandatory = $true)]$State)

    return @{
        outputFormat = 'jpg'
        jpegQuality = 92
        targetDirectory = $State.DefaultTargetDirectory
        keepClipboard = $true
        clipboardFormat = 'png'
        autoStart = if ($State.Portable) { $false } else { $true }
        languageMode = 'system'
        language = 'de'
        captureEnabled = $true
        iconTheme = 'clean-capture'
    }
}

function Write-SnipSaverLog {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $Message
    Add-Content -LiteralPath $State.LogPath -Value $line
}

function Merge-SnipSaverConfig {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)]$Candidate
    )

    $merged = Get-SnipSaverDefaultConfig -State $State
    foreach ($key in $Candidate.PSObject.Properties.Name) {
        $merged[$key] = $Candidate.$key
    }

    if ($merged.outputFormat -notin @('jpg', 'png')) {
        $merged.outputFormat = 'jpg'
    }

    $parsedQuality = 92
    if ([int]::TryParse([string]$merged.jpegQuality, [ref]$parsedQuality)) {
        $merged.jpegQuality = [Math]::Max(40, [Math]::Min(100, $parsedQuality))
    }
    else {
        $merged.jpegQuality = 92
    }

    if ([string]::IsNullOrWhiteSpace([string]$merged.targetDirectory)) {
        $merged.targetDirectory = $State.DefaultTargetDirectory
    }

    foreach ($flag in @('keepClipboard', 'autoStart', 'captureEnabled')) {
        $merged[$flag] = [bool]$merged[$flag]
    }

    if ($merged.clipboardFormat -notin @('jpg', 'png')) {
        $merged.clipboardFormat = 'png'
    }

    if ($merged.languageMode -notin @('system', 'manual')) {
        $merged.languageMode = 'system'
    }

    $supportedLanguages = @('de', 'en')
    if ($merged.language -notin $supportedLanguages) {
        $merged.languageMode = 'system'
        $merged.language = 'de'
    }

    $merged.iconTheme = 'clean-capture'

    return $merged
}

function Import-SnipSaverConfig {
    param([Parameter(Mandatory = $true)]$State)

    if (-not (Test-Path -LiteralPath $State.ConfigPath)) {
        $State.Config = Get-SnipSaverDefaultConfig -State $State
        Export-SnipSaverConfig -State $State
        return
    }

    try {
        $candidate = Get-Content -LiteralPath $State.ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $State.Config = Merge-SnipSaverConfig -State $State -Candidate $candidate
    }
    catch {
        $State.Config = Get-SnipSaverDefaultConfig -State $State
    }
}

function Export-SnipSaverConfig {
    param([Parameter(Mandatory = $true)]$State)

    New-Item -ItemType Directory -Path (Split-Path -Parent $State.ConfigPath) -Force | Out-Null
    $State.Config | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $State.ConfigPath -Encoding UTF8
}

function Resolve-SnipSaverRequestedLanguage {
    param([Parameter(Mandatory = $true)]$State)

    if ($State.Config.languageMode -eq 'manual' -and -not [string]::IsNullOrWhiteSpace([string]$State.Config.language)) {
        return [string]$State.Config.language
    }

    return [System.Globalization.CultureInfo]::CurrentUICulture.Name
}

function Get-SnipSaverLocaleSequence {
    param([Parameter(Mandatory = $true)]$State)

    $requested = Resolve-SnipSaverRequestedLanguage -State $State
    $sequence = New-Object System.Collections.Generic.List[string]
    $supported = @('de', 'en')
    if (-not [string]::IsNullOrWhiteSpace($requested)) {
        $baseCode = if ($requested.Contains('-')) { $requested.Split('-')[0] } else { $requested }
        if ($baseCode -in $supported) {
            $sequence.Add($baseCode)
        }
    }

    if (-not $sequence.Contains('de')) {
        $sequence.Add('de')
    }

    if (-not $sequence.Contains('en')) {
        $sequence.Add('en')
    }

    return $sequence.ToArray()
}

function Import-SnipSaverTranslations {
    param([Parameter(Mandatory = $true)]$State)

    $merged = @{}
    $effectiveLanguage = 'en'
    $localeSequence = Get-SnipSaverLocaleSequence -State $State
    [array]::Reverse($localeSequence)
    foreach ($code in $localeSequence) {
        $localePath = Join-Path $State.LocaleRoot ("{0}.json" -f $code)
        if (-not (Test-Path -LiteralPath $localePath)) {
            continue
        }

        try {
            $content = Get-Content -LiteralPath $localePath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($prop in $content.PSObject.Properties) {
                $merged[$prop.Name] = [string]$prop.Value
            }

            $effectiveLanguage = $code
        }
        catch {
        }
    }

    $State.Translations = $merged
    $State.EffectiveLanguage = $effectiveLanguage
}

function Get-SnipSaverText {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)][string]$Key
    )

    if ($State.Translations.ContainsKey($Key)) {
        return $State.Translations[$Key]
    }

    return $Key
}

function Reset-SnipSaverLanguage {
    param([Parameter(Mandatory = $true)]$State)

    $State.Config.languageMode = 'system'
    $State.Config.language = 'en'
    Export-SnipSaverConfig -State $State
    Import-SnipSaverTranslations -State $State
}

function Reset-SnipSaverDefaults {
    param([Parameter(Mandatory = $true)]$State)

    $State.Config = Get-SnipSaverDefaultConfig -State $State
    Export-SnipSaverConfig -State $State
    Import-SnipSaverTranslations -State $State
}

function Get-SnipSaverTargetDirectory {
    param([Parameter(Mandatory = $true)]$State)

    $targetDirectory = [string]$State.Config.targetDirectory
    if ([string]::IsNullOrWhiteSpace($targetDirectory)) {
        $targetDirectory = $State.DefaultTargetDirectory
    }

    New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
    return $targetDirectory
}

function Get-SnipSaverSourcePath {
    param([Parameter(Mandatory = $true)]$State)

    foreach ($candidate in $State.CaptureSourceCandidates) {
        if (-not (Test-Path -LiteralPath $candidate)) {
            continue
        }

        $recentFile = Get-ChildItem -LiteralPath $candidate -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTimeUtc -Descending |
            Select-Object -First 1

        if ($recentFile -and (([DateTime]::UtcNow - $recentFile.LastWriteTimeUtc).TotalSeconds -lt 120)) {
            return $candidate
        }
    }

    return $null
}

function Wait-SnipSaverFileReady {
    param([Parameter(Mandatory = $true)][string]$Path)

    for ($i = 0; $i -lt 20; $i++) {
        if (-not (Test-Path -LiteralPath $Path)) {
            Start-Sleep -Milliseconds 200
            continue
        }

        try {
            $stream = [System.IO.File]::Open($Path, 'Open', 'Read', 'None')
            $stream.Close()
            return $true
        }
        catch {
            Start-Sleep -Milliseconds 200
        }
    }

    return $false
}

function Get-SnipSaverImageFingerprint {
    param([Parameter(Mandatory = $true)][System.Drawing.Image]$Image)

    $stream = $null
    try {
        $stream = New-Object System.IO.MemoryStream
        $Image.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
        $hash = [System.Security.Cryptography.MD5]::Create().ComputeHash($stream.ToArray())
        return ([System.BitConverter]::ToString($hash)).Replace('-', '')
    }
    finally {
        if ($stream) {
            $stream.Dispose()
        }
    }
}

function Test-SnipSaverRecentFingerprint {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)][string]$Fingerprint
    )

    $now = [DateTime]::UtcNow
    foreach ($key in @($State.RecentFingerprints.Keys)) {
        if (($now - $State.RecentFingerprints[$key]).TotalSeconds -gt 30) {
            [void]$State.RecentFingerprints.Remove($key)
        }
    }

    return $State.RecentFingerprints.ContainsKey($Fingerprint)
}

function Add-SnipSaverFingerprint {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)][string]$Fingerprint
    )

    $State.RecentFingerprints[$Fingerprint] = [DateTime]::UtcNow
}

function Get-SnipSaverClipboardSequenceNumber {
    try {
        return [uint32][SnipSaver.NativeMethods]::GetClipboardSequenceNumber()
    }
    catch {
        return [uint32]0
    }
}

function Save-SnipSaverImage {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)][System.Drawing.Image]$Image,
        [Parameter(Mandatory = $true)][string]$DestinationBaseName
    )

    $targetDirectory = Get-SnipSaverTargetDirectory -State $State
    $timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss_fff'
    $extension = if ($State.Config.outputFormat -eq 'png') { 'png' } else { 'jpg' }
    $destinationPath = Join-Path $targetDirectory ("{0}_{1}.{2}" -f $timestamp, $DestinationBaseName, $extension)

    if ($State.Config.outputFormat -eq 'png') {
        $Image.Save($destinationPath, [System.Drawing.Imaging.ImageFormat]::Png)
        return $destinationPath
    }

    $bitmap = $null
    $graphics = $null
    try {
        $bitmap = New-Object System.Drawing.Bitmap $Image.Width, $Image.Height
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $graphics.Clear([System.Drawing.Color]::White)
        $graphics.DrawImage($Image, 0, 0, $Image.Width, $Image.Height)

        $encoder = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() |
            Where-Object { $_.MimeType -eq 'image/jpeg' } |
            Select-Object -First 1

        $qualityParam = New-Object System.Drawing.Imaging.EncoderParameter(
            [System.Drawing.Imaging.Encoder]::Quality,
            [long]$State.Config.jpegQuality
        )
        $encoderParams = New-Object System.Drawing.Imaging.EncoderParameters 1
        $encoderParams.Param[0] = $qualityParam
        $bitmap.Save($destinationPath, $encoder, $encoderParams)
        return $destinationPath
    }
    finally {
        if ($graphics) {
            $graphics.Dispose()
        }
        if ($bitmap) {
            $bitmap.Dispose()
        }
    }
}

function Get-SnipSaverJpegEncoder {
    return [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() |
        Where-Object { $_.MimeType -eq 'image/jpeg' } |
        Select-Object -First 1
}

function Convert-SnipSaverImageToJpegBytes {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)][System.Drawing.Image]$Image
    )

    $bitmap = $null
    $graphics = $null
    $stream = $null
    try {
        $bitmap = New-Object System.Drawing.Bitmap $Image.Width, $Image.Height
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $graphics.Clear([System.Drawing.Color]::White)
        $graphics.DrawImage($Image, 0, 0, $Image.Width, $Image.Height)

        $encoder = Get-SnipSaverJpegEncoder
        $qualityParam = New-Object System.Drawing.Imaging.EncoderParameter(
            [System.Drawing.Imaging.Encoder]::Quality,
            [long]$State.Config.jpegQuality
        )
        $encoderParams = New-Object System.Drawing.Imaging.EncoderParameters 1
        $encoderParams.Param[0] = $qualityParam

        $stream = New-Object System.IO.MemoryStream
        $bitmap.Save($stream, $encoder, $encoderParams)
        return $stream.ToArray()
    }
    finally {
        if ($stream) {
            $stream.Dispose()
        }
        if ($graphics) {
            $graphics.Dispose()
        }
        if ($bitmap) {
            $bitmap.Dispose()
        }
    }
}

function Convert-SnipSaverImageToPngBytes {
    param([Parameter(Mandatory = $true)][System.Drawing.Image]$Image)

    $stream = $null
    try {
        $stream = New-Object System.IO.MemoryStream
        $Image.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
        return $stream.ToArray()
    }
    finally {
        if ($stream) {
            $stream.Dispose()
        }
    }
}

function New-SnipSaverBitmapCopy {
    param(
        [Parameter(Mandatory = $true)][System.Drawing.Image]$Image,
        [switch]$WhiteBackground
    )

    $bitmap = New-Object System.Drawing.Bitmap $Image.Width, $Image.Height
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        if ($WhiteBackground) {
            $graphics.Clear([System.Drawing.Color]::White)
        }
        else {
            $graphics.Clear([System.Drawing.Color]::Transparent)
        }

        $graphics.DrawImage($Image, 0, 0, $Image.Width, $Image.Height)
        return $bitmap
    }
    finally {
        $graphics.Dispose()
    }
}

function Update-SnipSaverClipboardImage {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)][System.Drawing.Image]$Image
    )

    try {
        if (-not $State.Config.keepClipboard) {
            [System.Windows.Forms.Clipboard]::Clear()
            $State.LastClipboardSequenceNumber = Get-SnipSaverClipboardSequenceNumber
            return
        }

        $dataObject = New-Object System.Windows.Forms.DataObject
        $clipboardBitmap = $null
        $primaryStream = $null
        $extraStream = $null

        try {
            if ($State.Config.clipboardFormat -eq 'jpg') {
                $jpegBytes = Convert-SnipSaverImageToJpegBytes -State $State -Image $Image
                $primaryStream = New-Object System.IO.MemoryStream(, $jpegBytes)
                $extraStream = New-Object System.IO.MemoryStream(, $jpegBytes)
                $clipboardBitmap = [System.Drawing.Bitmap]::FromStream($primaryStream)
                $dataObject.SetImage($clipboardBitmap)
                $dataObject.SetData('JFIF', $extraStream)
            }
            else {
                $pngBytes = Convert-SnipSaverImageToPngBytes -Image $Image
                $primaryStream = New-Object System.IO.MemoryStream(, $pngBytes)
                $clipboardBitmap = New-SnipSaverBitmapCopy -Image $Image
                $dataObject.SetImage($clipboardBitmap)
                $dataObject.SetData('PNG', $primaryStream)
            }

            [System.Windows.Forms.Clipboard]::SetDataObject($dataObject, $true)
            $State.LastClipboardSequenceNumber = Get-SnipSaverClipboardSequenceNumber
        }
        finally {
            if ($clipboardBitmap) {
                $clipboardBitmap.Dispose()
            }
            if ($extraStream) {
                $extraStream.Dispose()
            }
            if ($primaryStream) {
                $primaryStream.Dispose()
            }
        }
    }
    catch {
        Write-SnipSaverLog -State $State -Message ("clipboard update error {0}" -f $_.Exception.Message)
    }
}

function Save-SnipSaverFileIfNew {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)][System.IO.FileInfo]$File
    )

    $extension = $File.Extension.ToLowerInvariant()
    if ($extension -notin '.png', '.bmp', '.jpg', '.jpeg', '.tif', '.tiff') {
        return
    }

    if ($File.Name -notlike 'Screenshot_*') {
        return
    }

    $stampKey = $File.LastWriteTimeUtc.Ticks
    if ($State.ProcessedFiles.ContainsKey($File.FullName) -and $State.ProcessedFiles[$File.FullName] -eq $stampKey) {
        return
    }

    if (-not (Wait-SnipSaverFileReady -Path $File.FullName)) {
        return
    }

    $image = $null
    try {
        $image = [System.Drawing.Image]::FromFile($File.FullName)
        $fingerprint = Get-SnipSaverImageFingerprint -Image $image
        if (Test-SnipSaverRecentFingerprint -State $State -Fingerprint $fingerprint) {
            $State.ProcessedFiles[$File.FullName] = $stampKey
            return
        }

        $destination = Save-SnipSaverImage -State $State -Image $image -DestinationBaseName ([System.IO.Path]::GetFileNameWithoutExtension($File.Name))
        Add-SnipSaverFingerprint -State $State -Fingerprint $fingerprint
        Update-SnipSaverClipboardImage -State $State -Image $image
        $State.ProcessedFiles[$File.FullName] = $stampKey
        Write-SnipSaverLog -State $State -Message ("saved file {0}" -f $destination)
    }
    catch {
        Write-SnipSaverLog -State $State -Message ("file error {0}" -f $_.Exception.Message)
    }
    finally {
        if ($image) {
            $image.Dispose()
        }
    }
}

function Save-SnipSaverClipboardIfNew {
    param([Parameter(Mandatory = $true)]$State)

    try {
        $clipboardSequence = Get-SnipSaverClipboardSequenceNumber
        if ($clipboardSequence -ne 0 -and $State.LastClipboardSequenceNumber -eq $clipboardSequence) {
            return
        }

        if (-not [System.Windows.Forms.Clipboard]::ContainsImage()) {
            $State.LastClipboardFingerprint = $null
            $State.LastClipboardSequenceNumber = $clipboardSequence
            return
        }

        $image = [System.Windows.Forms.Clipboard]::GetImage()
        if (-not $image) {
            return
        }

        try {
            $fingerprint = Get-SnipSaverImageFingerprint -Image $image
            if ($State.LastClipboardFingerprint -eq $fingerprint) {
                $State.LastClipboardSequenceNumber = $clipboardSequence
                return
            }
            if (Test-SnipSaverRecentFingerprint -State $State -Fingerprint $fingerprint) {
                $State.LastClipboardFingerprint = $fingerprint
                $State.LastClipboardSequenceNumber = $clipboardSequence
                return
            }

            $destination = Save-SnipSaverImage -State $State -Image $image -DestinationBaseName 'clipboard'
            Add-SnipSaverFingerprint -State $State -Fingerprint $fingerprint
            $State.LastClipboardFingerprint = $fingerprint
            Update-SnipSaverClipboardImage -State $State -Image $image
            Write-SnipSaverLog -State $State -Message ("saved clipboard {0}" -f $destination)
        }
        finally {
            $image.Dispose()
        }
    }
    catch {
        Write-SnipSaverLog -State $State -Message ("clipboard error {0}" -f $_.Exception.Message)
    }
}

function Invoke-SnipSaverCaptureTick {
    param([Parameter(Mandatory = $true)]$State)

    if (-not $State.Config.captureEnabled) {
        return
    }

    $State.SourcePath = Get-SnipSaverSourcePath -State $State
    if ($State.SourcePath) {
        foreach ($file in Get-ChildItem -LiteralPath $State.SourcePath -File -ErrorAction SilentlyContinue) {
            Save-SnipSaverFileIfNew -State $State -File $file
        }
        return
    }

    Save-SnipSaverClipboardIfNew -State $State
}

function Acquire-SnipSaverMutex {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)][string]$PropertyName,
        [Parameter(Mandatory = $true)][string]$MutexName
    )

    $createdNew = $false
    $mutex = New-Object System.Threading.Mutex($true, $MutexName, [ref]$createdNew)
    if (-not $createdNew) {
        $mutex.Dispose()
        return $null
    }

    $State[$PropertyName] = $mutex
    return $mutex
}

function Release-SnipSaverMutex {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)][string]$PropertyName
    )

    $mutex = $State[$PropertyName]
    if (-not $mutex) {
        return
    }

    try {
        $mutex.ReleaseMutex() | Out-Null
    }
    catch {
    }

    $mutex.Dispose()
    $State[$PropertyName] = $null
}

function Start-SnipSaverCaptureLoop {
    param([Parameter(Mandatory = $true)]$State)

    while ($true) {
        Invoke-SnipSaverCaptureTick -State $State
        Start-Sleep -Milliseconds 500
    }
}

function Get-SnipSaverThemeDefinition {
    param([Parameter(Mandatory = $true)][string]$ThemeId)

    switch ($ThemeId) {
        'warm-utility' {
            return @{
                ActiveBackground = '#E7A14B'
                ActiveAccent = '#352417'
                InactiveBackground = '#C6B39C'
                InactiveAccent = '#6B5642'
                Shape = 'circle'
            }
        }
        'sharp-minimal' {
            return @{
                ActiveBackground = '#1E2228'
                ActiveAccent = '#F5F7FA'
                InactiveBackground = '#8B95A3'
                InactiveAccent = '#E7EDF4'
                Shape = 'square'
            }
        }
        'lens-badge' {
            return @{
                ActiveBackground = '#247A72'
                ActiveAccent = '#F5FAFA'
                InactiveBackground = '#91ABA6'
                InactiveAccent = '#F5FAFA'
                Shape = 'lens'
            }
        }
        default {
            return @{
                ActiveBackground = '#00A7A0'
                ActiveAccent = '#FFFDF5'
                InactiveBackground = '#7FA8A7'
                InactiveAccent = '#F6F4EC'
                Shape = 'rounded-square'
            }
        }
    }
}

function Convert-SnipSaverColor {
    param([Parameter(Mandatory = $true)][string]$Hex)
    return [System.Drawing.ColorTranslator]::FromHtml($Hex)
}

function New-SnipSaverTrayIcon {
    param(
        [Parameter(Mandatory = $true)]$State,
        [bool]$Active
    )

    $assetName = if ($Active) { 'snipsaver-active.ico' } else { 'snipsaver-paused.ico' }
    $assetPath = Join-Path (Join-Path $State.ScriptRoot 'assets') $assetName
    if (Test-Path -LiteralPath $assetPath) {
        $loadedIcon = $null
        try {
            $loadedIcon = New-Object System.Drawing.Icon $assetPath
            return $loadedIcon.Clone()
        }
        finally {
            if ($loadedIcon) {
                $loadedIcon.Dispose()
            }
        }
    }

    $theme = Get-SnipSaverThemeDefinition -ThemeId 'clean-capture'
    $background = Convert-SnipSaverColor -Hex ($(if ($Active) { $theme.ActiveBackground } else { $theme.InactiveBackground }))
    $accent = Convert-SnipSaverColor -Hex ($(if ($Active) { $theme.ActiveAccent } else { $theme.InactiveAccent }))

    $bitmap = New-Object System.Drawing.Bitmap 32, 32
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $fillBrush = New-Object System.Drawing.SolidBrush $background
    $pen = New-Object System.Drawing.Pen $accent, 3

    try {
        switch ($theme.Shape) {
            'circle' {
                $graphics.FillEllipse($fillBrush, 2, 2, 28, 28)
            }
            'square' {
                $graphics.FillRectangle($fillBrush, 2, 2, 28, 28)
            }
            'lens' {
                $graphics.FillEllipse($fillBrush, 2, 2, 28, 28)
            }
            default {
                $path = New-Object System.Drawing.Drawing2D.GraphicsPath
                $radius = 8
                $path.AddArc(2, 2, $radius, $radius, 180, 90)
                $path.AddArc(30 - $radius, 2, $radius, $radius, 270, 90)
                $path.AddArc(30 - $radius, 30 - $radius, $radius, $radius, 0, 90)
                $path.AddArc(2, 30 - $radius, $radius, $radius, 90, 90)
                $path.CloseFigure()
                $graphics.FillPath($fillBrush, $path)
                $path.Dispose()
            }
        }

        if ($theme.Shape -eq 'lens') {
            $graphics.DrawEllipse($pen, 8, 8, 12, 12)
            $graphics.DrawLine($pen, 20, 20, 26, 26)
        }
        else {
            $graphics.DrawLine($pen, 8, 3, 3, 3)
            $graphics.DrawLine($pen, 3, 3, 3, 8)
            $graphics.DrawLine($pen, 24, 3, 29, 3)
            $graphics.DrawLine($pen, 29, 3, 29, 8)
            $graphics.DrawLine($pen, 3, 24, 3, 29)
            $graphics.DrawLine($pen, 3, 29, 8, 29)
            $graphics.DrawLine($pen, 24, 29, 29, 29)
            $graphics.DrawLine($pen, 29, 24, 29, 29)
        }

        if ($Active) {
            $activeBrush = New-Object System.Drawing.SolidBrush $accent
            $graphics.FillEllipse($activeBrush, 20, 20, 8, 8)
            $activePen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(120, $accent)), 2
            $graphics.DrawEllipse($activePen, 18, 18, 12, 12)
            $activePen.Dispose()
            $activeBrush.Dispose()
        }
        else {
            $graphics.DrawLine($pen, 9, 16, 23, 16)
            $graphics.DrawLine($pen, 9, 19, 23, 19)
        }

        $iconHandle = $bitmap.GetHicon()
        return [System.Drawing.Icon]::FromHandle($iconHandle)
    }
    finally {
        $pen.Dispose()
        $fillBrush.Dispose()
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

function Ensure-SnipSaverAutostart {
    param([Parameter(Mandatory = $true)]$State)

    $startupFolder = [Environment]::GetFolderPath('Startup')
    $shortcutPath = if ([string]::IsNullOrWhiteSpace($startupFolder)) { $null } else { Join-Path $startupFolder 'SnipSaver.lnk' }
    $runKeyPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    $runValueName = 'SnipSaver'

    if (-not $State.Config.autoStart) {
        if ($shortcutPath) {
            Remove-Item -LiteralPath $shortcutPath -Force -ErrorAction SilentlyContinue
        }
        Remove-ItemProperty -Path $runKeyPath -Name $runValueName -ErrorAction SilentlyContinue
        return
    }

    $launcherName = if ($State.Portable) { 'Run-SnipSaver-Tray-Portable.cmd' } else { 'Run-SnipSaver-Tray.cmd' }
    $launcherPath = Join-Path $State.ScriptRoot $launcherName
    if (-not (Test-Path -LiteralPath $launcherPath)) {
        return
    }

    if ($shortcutPath) {
        try {
            $wsh = New-Object -ComObject WScript.Shell
            $shortcut = $wsh.CreateShortcut($shortcutPath)
            $shortcut.TargetPath = $launcherPath
            $shortcut.WorkingDirectory = $State.ScriptRoot
            $shortcut.Description = 'SnipSaver tray application'
            $shortcut.WindowStyle = 7
            $shortcut.Save()
        }
        catch {
            Write-SnipSaverLog -State $State -Message ("autostart shortcut error {0}" -f $_.Exception.Message)
        }
    }

    try {
        New-Item -Path $runKeyPath -Force | Out-Null
        Set-ItemProperty -Path $runKeyPath -Name $runValueName -Value ('"{0}"' -f $launcherPath)
    }
    catch {
        Write-SnipSaverLog -State $State -Message ("autostart run key error {0}" -f $_.Exception.Message)
    }
}

function Get-SnipSaverLanguageItems {
    param([Parameter(Mandatory = $true)]$State)

    $items = New-Object System.Collections.Generic.List[object]
    $items.Add([pscustomobject]@{ Value = 'system'; Label = (Get-SnipSaverText -State $State -Key 'settings.language.system') })
    foreach ($language in $State.Languages) {
        $items.Add([pscustomobject]@{ Value = $language.Code; Label = $language.Label })
    }

    return $items.ToArray()
}

function Apply-SnipSaverRightToLeft {
    param(
        [Parameter(Mandatory = $true)][System.Windows.Forms.Form]$Form,
        [Parameter(Mandatory = $true)][string]$LanguageCode
    )

    if ($LanguageCode -like 'ar*') {
        $Form.RightToLeft = [System.Windows.Forms.RightToLeft]::Yes
        $Form.RightToLeftLayout = $true
    }
    else {
        $Form.RightToLeft = [System.Windows.Forms.RightToLeft]::No
        $Form.RightToLeftLayout = $false
    }
}

function Get-SnipSaverPortableSuffix {
    param([Parameter(Mandatory = $true)]$State)
    if ($State.Portable) { return ' -Portable' }
    return ''
}

