# SnipSaverWin10 v0.5.8 Release Artifact

SnipSaverWin10 is a Windows 10-only tray helper for saving Snipping Tool / Screen Sketch results into the user's Screenshots folder.

This release is scoped specifically to Windows 10. Windows 11 already has a different built-in autosave path, so this project does not target Windows 11.

## Included README Screenshot

Use `screenshot.jpg` as the README image.

The image is a synthetic demo mockup showing:

- Windows 10 desktop/taskbar
- SnipSaver tray icon
- open tray context menu
- English SnipSaver settings
- `C:\Users\Lenovo\Pictures\Screenshots`
- a saved `.jpg` screenshot file

## Release Contents

- `dist\SnipSaverWin10-Installer.exe`
- `dist\SnipSaverWin10-Portable.exe`
- `dist\SnipSaverWin10-payload.zip`
- `outputs\SnipSaver-Core.ps1`
- `outputs\SnipSaver-Tray.ps1`
- `outputs\Run-SnipSaver-Tray.cmd`
- `outputs\Run-SnipSaver-Tray-Portable.cmd`
- `outputs\Install-SnipSaver.ps1`
- `outputs\Uninstall-SnipSaver.ps1`
- `outputs\Test-SnipSaverSettings.ps1`
- `outputs\assets\snipsaver-active.ico`
- `outputs\assets\snipsaver-paused.ico`
- `outputs\locales\de.json`
- `outputs\locales\en.json`
- `screenshot.jpg`

The EXE files are the primary release artifacts. The PowerShell files remain included for source transparency and development/debugging.

## Validation

Automated settings smoke test:

```text
23/23 checks passed
```

Runtime check after restart:

```text
Running instances: 1
Autostart shortcut: present
HKCU Run value: Run-SnipSaver-Tray.cmd
Clipboard loop guard: no log growth after 5 seconds
```

## Notes

Supported UI languages are currently limited to Deutsch and English. Additional languages should stay out of release builds until WinForms encoding is handled reliably.
