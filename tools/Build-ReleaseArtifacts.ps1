param(
    [string]$Configuration = 'Release'
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$outputsRoot = Join-Path $repoRoot 'outputs'
$distRoot = Join-Path $repoRoot 'dist'
$payloadRoot = Join-Path $distRoot 'payload'
$payloadZip = Join-Path $distRoot 'SnipSaverWin10-payload.zip'

if (-not (Test-Path -LiteralPath $outputsRoot)) {
    throw "Missing outputs directory: $outputsRoot"
}

Remove-Item -LiteralPath $distRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $payloadRoot -Force | Out-Null

$includePaths = @(
    'SnipSaver-Core.ps1',
    'SnipSaver-Tray.ps1',
    'Install-SnipSaver.ps1',
    'Uninstall-SnipSaver.ps1',
    'Run-SnipSaver-Tray.cmd',
    'Run-SnipSaver-Tray-Portable.cmd',
    'Start-SnipSaver-Portable.cmd',
    'Test-SnipSaverSettings.ps1',
    'assets',
    'locales',
    'releases'
)

foreach ($relativePath in $includePaths) {
    $source = Join-Path $outputsRoot $relativePath
    if (-not (Test-Path -LiteralPath $source)) {
        throw "Missing release input: $source"
    }

    $target = Join-Path $payloadRoot $relativePath
    if ((Get-Item -LiteralPath $source).PSIsContainer) {
        Copy-Item -LiteralPath $source -Destination $target -Recurse -Force
    }
    else {
        New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
        Copy-Item -LiteralPath $source -Destination $target -Force
    }
}

$cleanCaptureSource = Join-Path $outputsRoot 'icon-previews\clean-capture.svg'
if (-not (Test-Path -LiteralPath $cleanCaptureSource)) {
    throw "Missing release input: $cleanCaptureSource"
}
$cleanCaptureTarget = Join-Path $payloadRoot 'icon-previews\clean-capture.svg'
New-Item -ItemType Directory -Path (Split-Path -Parent $cleanCaptureTarget) -Force | Out-Null
Copy-Item -LiteralPath $cleanCaptureSource -Destination $cleanCaptureTarget -Force

Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($payloadRoot, $payloadZip, [System.IO.Compression.CompressionLevel]::Optimal, $false)
$payloadBase64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($payloadZip))

function New-LauncherSource {
    param(
        [Parameter(Mandatory = $true)][string]$ClassName,
        [Parameter(Mandatory = $true)][string]$Mode,
        [Parameter(Mandatory = $true)][string]$Base64Payload
    )

    if ($Mode -eq 'Install') {
        $afterExtractCode = @'
            RunPowerShell(installDir, "Install-SnipSaver.ps1", "");
            StartCommand(Path.Combine(installDir, "Run-SnipSaver-Tray.cmd"));
'@
        $installDirectoryCode = @'
        string localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        return Path.Combine(localAppData, "Programs", "SnipSaverWin10");
'@
    }
    else {
        $afterExtractCode = @'
            StartCommand(Path.Combine(installDir, "Run-SnipSaver-Tray-Portable.cmd"));
'@
        $installDirectoryCode = @'
        string exeDir = AppDomain.CurrentDomain.BaseDirectory;
        return Path.Combine(exeDir, "SnipSaverWin10-portable");
'@
    }

    return @"
using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;

internal static class $ClassName
{
    private const string PayloadBase64 = "$Base64Payload";

    [STAThread]
    private static int Main(string[] args)
    {
        try
        {
            string installDir = GetInstallDirectory();
            ExtractPayload(installDir);
$afterExtractCode

            return 0;
        }
        catch (Exception ex)
        {
            System.Windows.Forms.MessageBox.Show(ex.Message, "SnipSaverWin10", System.Windows.Forms.MessageBoxButtons.OK, System.Windows.Forms.MessageBoxIcon.Error);
            return 1;
        }
    }

    private static string GetInstallDirectory()
    {
$installDirectoryCode
    }

    private static void ExtractPayload(string targetDirectory)
    {
        if (Directory.Exists(targetDirectory))
        {
            Directory.Delete(targetDirectory, true);
        }

        Directory.CreateDirectory(targetDirectory);
        string tempZip = Path.Combine(Path.GetTempPath(), "SnipSaverWin10-" + Guid.NewGuid().ToString("N") + ".zip");
        try
        {
            File.WriteAllBytes(tempZip, Convert.FromBase64String(PayloadBase64));
            ZipFile.ExtractToDirectory(tempZip, targetDirectory);
        }
        finally
        {
            if (File.Exists(tempZip))
            {
                File.Delete(tempZip);
            }
        }
    }

    private static void RunPowerShell(string workingDirectory, string scriptName, string arguments)
    {
        string scriptPath = Path.Combine(workingDirectory, scriptName);
        var startInfo = new ProcessStartInfo();
        startInfo.FileName = "powershell.exe";
        startInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File \"" + scriptPath + "\" " + arguments;
        startInfo.WorkingDirectory = workingDirectory;
        startInfo.UseShellExecute = false;
        startInfo.CreateNoWindow = true;
        using (var process = Process.Start(startInfo))
        {
            process.WaitForExit();
            if (process.ExitCode != 0)
            {
                throw new Exception(scriptName + " failed with exit code " + process.ExitCode.ToString());
            }
        }
    }

    private static void StartCommand(string commandPath)
    {
        var startInfo = new ProcessStartInfo();
        startInfo.FileName = commandPath;
        startInfo.WorkingDirectory = Path.GetDirectoryName(commandPath);
        startInfo.UseShellExecute = true;
        startInfo.WindowStyle = ProcessWindowStyle.Hidden;
        Process.Start(startInfo);
    }
}
"@
}

$installerSource = Join-Path $distRoot 'SnipSaverWin10-Installer.cs'
$portableSource = Join-Path $distRoot 'SnipSaverWin10-Portable.cs'
$installerExe = Join-Path $distRoot 'SnipSaverWin10-Installer.exe'
$portableExe = Join-Path $distRoot 'SnipSaverWin10-Portable.exe'
$exeIcon = Join-Path $outputsRoot 'assets\snipsaver-active.ico'
if (-not (Test-Path -LiteralPath $exeIcon)) {
    throw "Missing EXE icon: $exeIcon"
}

New-LauncherSource -ClassName 'SnipSaverWin10Installer' -Mode 'Install' -Base64Payload $payloadBase64 |
    Set-Content -LiteralPath $installerSource -Encoding UTF8
New-LauncherSource -ClassName 'SnipSaverWin10Portable' -Mode 'Portable' -Base64Payload $payloadBase64 |
    Set-Content -LiteralPath $portableSource -Encoding UTF8

$cscCandidates = @(
    'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe',
    'C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe'
)
$csc = $cscCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $csc) {
    throw 'Could not find csc.exe from .NET Framework 4.'
}

& $csc /nologo /target:winexe /win32icon:$exeIcon /r:System.Windows.Forms.dll /r:System.IO.Compression.dll /r:System.IO.Compression.FileSystem.dll /out:$installerExe $installerSource
& $csc /nologo /target:winexe /win32icon:$exeIcon /r:System.Windows.Forms.dll /r:System.IO.Compression.dll /r:System.IO.Compression.FileSystem.dll /out:$portableExe $portableSource

[pscustomobject]@{
    Installer = $installerExe
    Portable = $portableExe
    PayloadZip = $payloadZip
    PayloadBytes = (Get-Item -LiteralPath $payloadZip).Length
    InstallerBytes = (Get-Item -LiteralPath $installerExe).Length
    PortableBytes = (Get-Item -LiteralPath $portableExe).Length
} | ConvertTo-Json -Depth 3
