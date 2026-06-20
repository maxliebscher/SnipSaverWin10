param(
    [switch]$Portable,
    [switch]$SettingsOnly
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\SnipSaver-Core.ps1"

$state = New-SnipSaverState -ScriptRoot $PSScriptRoot -Portable:$Portable
Import-SnipSaverConfig -State $state
Import-SnipSaverTranslations -State $state
if (-not $SettingsOnly) {
    Ensure-SnipSaverAutostart -State $state
}

$appMutex = if ($SettingsOnly) { $null } else { Acquire-SnipSaverMutex -State $state -PropertyName 'AppMutex' -MutexName 'Local\SnipSaverTrayApp' }
if (-not $SettingsOnly -and -not $appMutex) {
    exit
}

$captureMutex = if ($SettingsOnly) { $null } else { Acquire-SnipSaverMutex -State $state -PropertyName 'CaptureMutex' -MutexName 'Local\SnipSaverCapture' }
if (-not $SettingsOnly -and -not $captureMutex) {
    Release-SnipSaverMutex -State $state -PropertyName 'AppMutex'
    exit
}

$notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$contextMenu = New-Object System.Windows.Forms.ContextMenuStrip
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 500

function Show-SnipSaverSettings {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)][System.Windows.Forms.NotifyIcon]$NotifyIcon,
        [Parameter(Mandatory = $true)][System.Windows.Forms.ContextMenuStrip]$Menu
    )

    $form = New-Object System.Windows.Forms.Form
    $form.Text = Get-SnipSaverText -State $State -Key 'settings.title'
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.ClientSize = New-Object System.Drawing.Size(540, 580)
    $form.AutoScroll = $true
    Apply-SnipSaverRightToLeft -Form $form -LanguageCode $State.EffectiveLanguage

    $controls = @{
        outputFormatLabel = New-Object System.Windows.Forms.Label
        outputFormatBox = New-Object System.Windows.Forms.ComboBox
        jpegQualityLabel = New-Object System.Windows.Forms.Label
        jpegQualityBox = New-Object System.Windows.Forms.NumericUpDown
        targetDirectoryLabel = New-Object System.Windows.Forms.Label
        targetDirectoryBox = New-Object System.Windows.Forms.TextBox
        browseButton = New-Object System.Windows.Forms.Button
        keepClipboardBox = New-Object System.Windows.Forms.CheckBox
        clipboardFormatLabel = New-Object System.Windows.Forms.Label
        clipboardFormatBox = New-Object System.Windows.Forms.ComboBox
        clipboardNoticeLabel = New-Object System.Windows.Forms.Label
        autoStartBox = New-Object System.Windows.Forms.CheckBox
        languageModeLabel = New-Object System.Windows.Forms.Label
        languageModeBox = New-Object System.Windows.Forms.ComboBox
        languageLabel = New-Object System.Windows.Forms.Label
        languageBox = New-Object System.Windows.Forms.ComboBox
        saveButton = New-Object System.Windows.Forms.Button
        cancelButton = New-Object System.Windows.Forms.Button
        resetDefaultsButton = New-Object System.Windows.Forms.Button
    }

    $labelWidth = 180
    $fieldX = 220
    $fieldWidth = 230
    foreach ($labelName in @(
        'outputFormatLabel',
        'jpegQualityLabel',
        'targetDirectoryLabel',
        'clipboardFormatLabel',
        'languageModeLabel',
        'languageLabel'
    )) {
        $controls[$labelName].Size = New-Object System.Drawing.Size($labelWidth, 22)
        $form.Controls.Add($controls[$labelName])
    }

    $controls.outputFormatBox.Location = New-Object System.Drawing.Point(210, 16)
    $controls.outputFormatLabel.Location = New-Object System.Drawing.Point(20, 20)
    $controls.outputFormatBox.Size = New-Object System.Drawing.Size($fieldWidth, 24)
    $controls.outputFormatBox.Location = New-Object System.Drawing.Point($fieldX, 18)
    $controls.outputFormatBox.DropDownStyle = 'DropDownList'
    [void]$controls.outputFormatBox.Items.AddRange(@('JPG', 'PNG'))

    $controls.jpegQualityLabel.Location = New-Object System.Drawing.Point(20, 64)
    $controls.jpegQualityBox.Size = New-Object System.Drawing.Size(90, 24)
    $controls.jpegQualityBox.Location = New-Object System.Drawing.Point($fieldX, 62)
    $controls.jpegQualityBox.Minimum = 40
    $controls.jpegQualityBox.Maximum = 100

    $controls.targetDirectoryLabel.Location = New-Object System.Drawing.Point(20, 108)
    $controls.targetDirectoryBox.Location = New-Object System.Drawing.Point($fieldX, 106)
    $controls.targetDirectoryBox.Size = New-Object System.Drawing.Size(185, 24)
    $controls.browseButton.Location = New-Object System.Drawing.Point(415, 104)
    $controls.browseButton.Size = New-Object System.Drawing.Size(90, 28)

    $controls.keepClipboardBox.Location = New-Object System.Drawing.Point(20, 150)
    $controls.keepClipboardBox.Size = New-Object System.Drawing.Size(485, 24)

    $controls.clipboardFormatLabel.Location = New-Object System.Drawing.Point(20, 190)
    $controls.clipboardFormatBox.Location = New-Object System.Drawing.Point($fieldX, 188)
    $controls.clipboardFormatBox.Size = New-Object System.Drawing.Size($fieldWidth, 24)
    $controls.clipboardFormatBox.DropDownStyle = 'DropDownList'
    [void]$controls.clipboardFormatBox.Items.AddRange(@('PNG', 'JPG'))

    $controls.clipboardNoticeLabel.Location = New-Object System.Drawing.Point(20, 225)
    $controls.clipboardNoticeLabel.Size = New-Object System.Drawing.Size(485, 44)

    $controls.autoStartBox.Location = New-Object System.Drawing.Point(20, 280)
    $controls.autoStartBox.Size = New-Object System.Drawing.Size(485, 24)

    $controls.languageModeLabel.Location = New-Object System.Drawing.Point(20, 322)
    $controls.languageModeBox.Location = New-Object System.Drawing.Point($fieldX, 320)
    $controls.languageModeBox.Size = New-Object System.Drawing.Size($fieldWidth, 24)
    $controls.languageModeBox.DropDownStyle = 'DropDownList'

    $controls.languageLabel.Location = New-Object System.Drawing.Point(20, 366)
    $controls.languageBox.Location = New-Object System.Drawing.Point($fieldX, 364)
    $controls.languageBox.Size = New-Object System.Drawing.Size($fieldWidth, 24)
    $controls.languageBox.DropDownStyle = 'DropDownList'

    $controls.resetDefaultsButton.Location = New-Object System.Drawing.Point(20, 520)
    $controls.resetDefaultsButton.Size = New-Object System.Drawing.Size(145, 32)
    $controls.cancelButton.Location = New-Object System.Drawing.Point(320, 520)
    $controls.cancelButton.Size = New-Object System.Drawing.Size(90, 32)
    $controls.saveButton.Location = New-Object System.Drawing.Point(420, 520)
    $controls.saveButton.Size = New-Object System.Drawing.Size(90, 32)

    foreach ($controlName in @(
        'outputFormatBox',
        'jpegQualityBox',
        'targetDirectoryBox',
        'browseButton',
        'keepClipboardBox',
        'clipboardFormatBox',
        'clipboardNoticeLabel',
        'autoStartBox',
        'languageModeBox',
        'languageBox',
        'saveButton',
        'cancelButton',
        'resetDefaultsButton'
    )) {
        $form.Controls.Add($controls[$controlName])
    }

    function Sync-ClipboardControls {
        $controls.clipboardFormatLabel.Enabled = $controls.keepClipboardBox.Checked
        $controls.clipboardFormatBox.Enabled = $controls.keepClipboardBox.Checked
    }

    function Sync-SettingsControls {
        $controls.outputFormatLabel.Text = Get-SnipSaverText -State $State -Key 'settings.outputFormat'
        $controls.jpegQualityLabel.Text = Get-SnipSaverText -State $State -Key 'settings.jpegQuality'
        $controls.targetDirectoryLabel.Text = Get-SnipSaverText -State $State -Key 'settings.targetDirectory'
        $controls.browseButton.Text = Get-SnipSaverText -State $State -Key 'settings.browse'
        $controls.keepClipboardBox.Text = Get-SnipSaverText -State $State -Key 'settings.keepClipboard'
        $controls.clipboardFormatLabel.Text = Get-SnipSaverText -State $State -Key 'settings.clipboardFormat'
        $controls.clipboardNoticeLabel.Text = Get-SnipSaverText -State $State -Key 'settings.clipboardNotice'
        $controls.autoStartBox.Text = Get-SnipSaverText -State $State -Key 'settings.autoStart'
        $controls.languageModeLabel.Text = Get-SnipSaverText -State $State -Key 'settings.languageMode'
        $controls.languageLabel.Text = Get-SnipSaverText -State $State -Key 'settings.language'
        $controls.saveButton.Text = Get-SnipSaverText -State $State -Key 'settings.save'
        $controls.cancelButton.Text = Get-SnipSaverText -State $State -Key 'settings.cancel'
        $controls.resetDefaultsButton.Text = Get-SnipSaverText -State $State -Key 'settings.resetDefaults'
        $form.Text = Get-SnipSaverText -State $State -Key 'settings.title'
        Apply-SnipSaverRightToLeft -Form $form -LanguageCode $State.EffectiveLanguage

        $controls.languageModeBox.Items.Clear()
        [void]$controls.languageModeBox.Items.AddRange(@(
            (Get-SnipSaverText -State $State -Key 'settings.languageMode.system'),
            (Get-SnipSaverText -State $State -Key 'settings.languageMode.manual')
        ))

        $controls.languageBox.Items.Clear()
        foreach ($item in Get-SnipSaverLanguageItems -State $State) {
            [void]$controls.languageBox.Items.Add($item.Label)
        }

        $controls.outputFormatBox.SelectedItem = $State.Config.outputFormat.ToUpperInvariant()
        $controls.jpegQualityBox.Value = [decimal]$State.Config.jpegQuality
        $controls.targetDirectoryBox.Text = $State.Config.targetDirectory
        $controls.keepClipboardBox.Checked = $State.Config.keepClipboard
        $controls.clipboardFormatBox.SelectedItem = $State.Config.clipboardFormat.ToUpperInvariant()
        $controls.autoStartBox.Checked = $State.Config.autoStart
        $controls.languageModeBox.SelectedIndex = if ($State.Config.languageMode -eq 'manual') { 1 } else { 0 }

        $languageItems = Get-SnipSaverLanguageItems -State $State
        if ($State.Config.languageMode -eq 'system') {
            $controls.languageBox.SelectedIndex = 0
        }
        else {
            $languageIndex = [Array]::IndexOf($languageItems.Value, $State.Config.language)
            $controls.languageBox.SelectedIndex = if ($languageIndex -ge 0) { $languageIndex + 1 } else { 1 }
        }

        $controls.jpegQualityBox.Enabled = ($State.Config.outputFormat -eq 'jpg')
        Sync-ClipboardControls
    }

    Sync-SettingsControls

    $controls.outputFormatBox.add_SelectedIndexChanged({
        $controls.jpegQualityBox.Enabled = ($controls.outputFormatBox.SelectedItem -eq 'JPG')
    })

    $controls.keepClipboardBox.add_CheckedChanged({
        Sync-ClipboardControls
    })

    $controls.languageBox.add_SelectedIndexChanged({
        if ($controls.languageBox.SelectedIndex -gt 0 -and $controls.languageModeBox.SelectedIndex -ne 1) {
            $controls.languageModeBox.SelectedIndex = 1
        }
    })

    $controls.languageModeBox.add_SelectedIndexChanged({
        if ($controls.languageModeBox.SelectedIndex -eq 0 -and $controls.languageBox.SelectedIndex -ne 0) {
            $controls.languageBox.SelectedIndex = 0
        }
    })

    $controls.browseButton.add_Click({
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.SelectedPath = $controls.targetDirectoryBox.Text
        if ($dialog.ShowDialog() -eq 'OK') {
            $controls.targetDirectoryBox.Text = $dialog.SelectedPath
        }
    })

    $controls.resetDefaultsButton.add_Click({
        Reset-SnipSaverDefaults -State $State
        Sync-SettingsControls
    })

    $controls.cancelButton.add_Click({
        $form.Close()
    })

    $controls.saveButton.add_Click({
        $State.Config.outputFormat = ([string]$controls.outputFormatBox.SelectedItem).ToLowerInvariant()
        $State.Config.jpegQuality = [int]$controls.jpegQualityBox.Value
        $State.Config.targetDirectory = $controls.targetDirectoryBox.Text
        $State.Config.keepClipboard = $controls.keepClipboardBox.Checked
        $State.Config.clipboardFormat = ([string]$controls.clipboardFormatBox.SelectedItem).ToLowerInvariant()
        $State.Config.autoStart = $controls.autoStartBox.Checked
        $State.Config.languageMode = if ($controls.languageModeBox.SelectedIndex -eq 1) { 'manual' } else { 'system' }
        if ($controls.languageBox.SelectedIndex -gt 0) {
            $languageItems = Get-SnipSaverLanguageItems -State $State
            $State.Config.language = $languageItems[$controls.languageBox.SelectedIndex].Value
        }
        else {
            $State.Config.language = 'en'
        }

        Export-SnipSaverConfig -State $State
        Import-SnipSaverTranslations -State $State
        Ensure-SnipSaverAutostart -State $State
        Refresh-SnipSaverTrayUi -State $State -NotifyIcon $NotifyIcon -Menu $Menu
        $form.Close()
    })

    [void]$form.ShowDialog()
}

function Refresh-SnipSaverTrayUi {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)][System.Windows.Forms.NotifyIcon]$NotifyIcon,
        [Parameter(Mandatory = $true)][System.Windows.Forms.ContextMenuStrip]$Menu
    )

    $Menu.Items.Clear()

    $startItem = $Menu.Items.Add((Get-SnipSaverText -State $State -Key 'menu.start'))
    $startItem.Enabled = -not $State.Config.captureEnabled
    $startItem.add_Click({
        $state.Config.captureEnabled = $true
        Export-SnipSaverConfig -State $state
        Refresh-SnipSaverTrayUi -State $state -NotifyIcon $notifyIcon -Menu $contextMenu
    })

    $stopItem = $Menu.Items.Add((Get-SnipSaverText -State $State -Key 'menu.stop'))
    $stopItem.Enabled = $State.Config.captureEnabled
    $stopItem.add_Click({
        $state.Config.captureEnabled = $false
        Export-SnipSaverConfig -State $state
        Refresh-SnipSaverTrayUi -State $state -NotifyIcon $notifyIcon -Menu $contextMenu
    })

    [void]$Menu.Items.Add('-')

    $openFolderItem = $Menu.Items.Add((Get-SnipSaverText -State $State -Key 'menu.openFolder'))
    $openFolderItem.add_Click({
        Start-Process explorer.exe (Get-SnipSaverTargetDirectory -State $state)
    })

    $settingsItem = $Menu.Items.Add((Get-SnipSaverText -State $State -Key 'menu.settings'))
    $settingsItem.add_Click({
        Show-SnipSaverSettings -State $state -NotifyIcon $notifyIcon -Menu $contextMenu
    })

    $restartItem = $Menu.Items.Add((Get-SnipSaverText -State $State -Key 'menu.restart'))
    $restartItem.add_Click({
        $launcherName = if ($state.Portable) { 'Run-SnipSaver-Tray-Portable.cmd' } else { 'Run-SnipSaver-Tray.cmd' }
        $launcherPath = Join-Path $state.ScriptRoot $launcherName
        Start-Process $launcherPath
        $notifyIcon.Visible = $false
        $timer.Stop()
        [System.Windows.Forms.Application]::Exit()
    })

    $resetLanguageItem = $Menu.Items.Add('Reset Language / Sprache')
    $resetLanguageItem.add_Click({
        Reset-SnipSaverLanguage -State $state
        Refresh-SnipSaverTrayUi -State $state -NotifyIcon $notifyIcon -Menu $contextMenu
    })

    [void]$Menu.Items.Add('-')

    $quitItem = $Menu.Items.Add((Get-SnipSaverText -State $State -Key 'menu.quit'))
    $quitItem.add_Click({
        $notifyIcon.Visible = $false
        $timer.Stop()
        [System.Windows.Forms.Application]::Exit()
    })

    $NotifyIcon.Icon = New-SnipSaverTrayIcon -State $State -Active:$State.Config.captureEnabled
    $NotifyIcon.Text = if ($State.Config.captureEnabled) {
        Get-SnipSaverText -State $State -Key 'tray.active'
    }
    else {
        Get-SnipSaverText -State $State -Key 'tray.paused'
    }
}

try {
    if ($SettingsOnly) {
        Write-SnipSaverLog -State $state -Message 'settings window opening'
        try {
            Show-SnipSaverSettings -State $state -NotifyIcon $notifyIcon -Menu $contextMenu
            Write-SnipSaverLog -State $state -Message 'settings window closed'
        }
        catch {
            Write-SnipSaverLog -State $state -Message ("settings window error {0}" -f $_.Exception.Message)
            throw
        }
        return
    }

    $notifyIcon.ContextMenuStrip = $contextMenu
    $notifyIcon.Visible = $true
    $notifyIcon.Icon = New-SnipSaverTrayIcon -State $state -Active:$state.Config.captureEnabled
    $timer.add_Tick({
        Invoke-SnipSaverCaptureTick -State $state
    })
    $timer.Start()
    Refresh-SnipSaverTrayUi -State $state -NotifyIcon $notifyIcon -Menu $contextMenu
    [System.Windows.Forms.Application]::Run()
}
finally {
    $timer.Stop()
    $notifyIcon.Visible = $false
    $notifyIcon.Dispose()
    $timer.Dispose()
    Release-SnipSaverMutex -State $state -PropertyName 'CaptureMutex'
    Release-SnipSaverMutex -State $state -PropertyName 'AppMutex'
}
