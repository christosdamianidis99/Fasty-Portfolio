param(
    [switch]$CaptureOnly
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# Run ONLY from the dedicated GitHub tooling branch. Never touch the private
# production repository or the installed Fasty Android package.
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$client = Join-Path $repo "client"
$images = Join-Path $repo "docs\screenshots"
$demoPackage = "com.christosdamianidis.fasty.portfoliodemo"
$branch = "docs/real-fasty-screenshots-20261016"

function Invoke-Checked {
    param([string]$Label, [scriptblock]$Command)
    Write-Host "=== $Label ===" -ForegroundColor Cyan
    & $Command
    if ($LASTEXITCODE -ne 0) {
        throw "$Label failed with exit code $LASTEXITCODE"
    }
}

foreach ($command in @("git", "flutter")) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        throw "Missing $command. Install it and reopen PowerShell."
    }
}

$adbCommand = Get-Command adb -ErrorAction SilentlyContinue
if ($adbCommand) {
    $adb = $adbCommand.Source
} else {
    $adb = Join-Path $env:LOCALAPPDATA "Android\Sdk\platform-tools\adb.exe"
}
if (-not (Test-Path $adb)) {
    throw "ADB is not available."
}

Push-Location $repo
try {
    $currentBranch = (& git branch --show-current).Trim()
    if ($LASTEXITCODE -ne 0 -or $currentBranch -ne "tools/isolated-screenshot-capture-20261016") {
        throw "Expected a fresh clone of the isolated capture-tooling branch."
    }

    $repoUrl = (& git remote get-url origin).Trim()
    if ($repoUrl -notmatch "^https://github[.]com/christosdamianidis99/Fasty-Portfolio[.]git$") {
        throw "Unexpected Git remote; refusing to run against another project."
    }

    if ((& git status --porcelain) -ne $null) {
        throw "The capture checkout has local modifications. Use a fresh clone."
    }

    $devices = @(& $adb devices | Where-Object {
        $_ -match '^([^\s]+)\s+device\s*$'
    } | ForEach-Object {
        if ($_ -match '^([^\s]+)\s+device\s*$') { $Matches[1] }
    })

    if ($devices.Count -ne 1) {
        throw "Connect and authorize exactly one Android device. Found: $($devices.Count)"
    }
    $serial = $devices[0]
    Write-Host "Authorized Android device: $serial"

    New-Item -ItemType Directory -Force -Path $images | Out-Null

    # Build the alternate entrypoint, not the production entrypoint.
    # The test data exists only in NativeDatabase.memory().
    Push-Location $client
    try {
        Invoke-Checked "Install Flutter dependencies" { flutter pub get }

        Invoke-Checked "Build isolated Windows demo" {
            flutter build windows --debug --target lib/portfolio_capture_main.dart --dart-define=FASTY_CAPTURE_VIEW=workspace
        }

        $windowsBuild = Join-Path $client "build\windows"
        $exe = Get-ChildItem $windowsBuild -Filter "fasty.exe" -File -Recurse |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $exe) {
            throw "Cannot find the Windows Fasty demo executable."
        }

        Add-Type -AssemblyName System.Drawing
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class FastyScreenshotWin32 {
    [StructLayout(LayoutKind.Sequential)]
    public struct Rect {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }
    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr h, out Rect rect);
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr h, int command);
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr h);
}
'@

        Write-Host "=== Capture actual Fasty Windows demo window ===" -ForegroundColor Cyan
        $p = Start-Process -FilePath $exe.FullName -WorkingDirectory $exe.DirectoryName -PassThru
        try {
            $handle = [IntPtr]::Zero
            for ($i = 0; $i -lt 120; $i++) {
                Start-Sleep -Seconds 1
                $p.Refresh()
                if ($p.HasExited) { throw "The Windows demo closed before capture." }
                $handle = $p.MainWindowHandle
                if ($handle -ne [IntPtr]::Zero) { break }
            }
            if ($handle -eq [IntPtr]::Zero) {
                throw "The Windows demo did not open a captureable window."
            }
            [void][FastyScreenshotWin32]::ShowWindow($handle, 3)
            [void][FastyScreenshotWin32]::SetForegroundWindow($handle)
            Start-Sleep -Seconds 5

            $rect = New-Object FastyScreenshotWin32+Rect
            if (-not [FastyScreenshotWin32]::GetWindowRect($handle, [ref]$rect)) {
                throw "Cannot read demo window bounds."
            }
            $width = $rect.Right - $rect.Left
            $height = $rect.Bottom - $rect.Top
            if ($width -lt 600 -or $height -lt 400) {
                throw "Unexpected demo window size: $width x $height"
            }
            $bmp = New-Object System.Drawing.Bitmap($width, $height)
            try {
                $graphics = [System.Drawing.Graphics]::FromImage($bmp)
                try {
                    $graphics.CopyFromScreen($rect.Left, $rect.Top, 0, 0, $bmp.Size)
                } finally {
                    $graphics.Dispose()
                }
                $bmp.Save(
                    (Join-Path $images "windows-workspace.png"),
                    [System.Drawing.Imaging.ImageFormat]::Png
                )
            } finally {
                $bmp.Dispose()
            }
            Write-Host "Windows demo screenshot captured."
        } finally {
            if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
        }

        function Capture-Android {
            param([string]$View, [string]$Filename)
            Invoke-Checked "Build isolated Android demo: $View" {
                flutter build apk --debug --target lib/portfolio_capture_main.dart "--dart-define=FASTY_CAPTURE_VIEW=$View"
            }
            $apk = Join-Path $client "build\app\outputs\flutter-apk\app-debug.apk"
            if (-not (Test-Path $apk)) { throw "Missing Android demo APK." }
            Invoke-Checked "Install Android screenshot-only package" {
                & $adb -s $serial install -r $apk
            }
            Invoke-Checked "Launch actual Android Fasty UI: $View" {
                & $adb -s $serial shell am force-stop $demoPackage
                & $adb -s $serial shell am start -n "$demoPackage/com.christosdamianidis.fasty.MainActivity"
            }
            Start-Sleep -Seconds 7
            $remoteScreenshot = "/sdcard/Download/fasty-portfolio-demo.png"
            try {
                Invoke-Checked "Capture Android screenshot: $View" {
                    & $adb -s $serial shell screencap -p $remoteScreenshot
                    & $adb -s $serial pull $remoteScreenshot (Join-Path $images $Filename)
                }
            } finally {
                & $adb -s $serial shell rm -f $remoteScreenshot | Out-Null
            }
        }

        try {
            Capture-Android -View "workspace" -Filename "android-workspace.png"
            Capture-Android -View "editor" -Filename "android-note-editor.png"
        } finally {
            # Remove only our separately named screenshot demo package.
            & $adb -s $serial uninstall $demoPackage | Out-Null
        }
    } finally {
        Pop-Location
    }

    foreach ($name in @("windows-workspace.png", "android-workspace.png", "android-note-editor.png")) {
        $path = Join-Path $images $name
        if (-not (Test-Path $path)) { throw "Missing screenshot: $name" }
        $stream = [System.IO.File]::OpenRead($path)
        try {
            $img = [System.Drawing.Image]::FromStream($stream)
            try {
                Write-Host ("Captured {0}: {1} x {2}" -f $name, $img.Width, $img.Height)
                if ($img.Width -lt 320 -or $img.Height -lt 400) {
                    throw "Invalid screenshot dimensions for $name"
                }
            } finally {
                $img.Dispose()
            }
        } finally {
            $stream.Dispose()
        }
    }

    if ($CaptureOnly) {
        Write-Host "Capture complete. Images saved in $images. Upload skipped."
        exit 0
    }

    # Flutter may regenerate tracked platform files or the dependency lockfile.
    # This is a disposable dedicated clone, so restore any generated changes
    # before switching to a screenshot-only branch. Images remain untracked.
    Invoke-Checked "Restore generated changes in dedicated capture checkout" {
        git restore -- .
    }

    # Stage only images. No source files, local state, identities, credentials,
    # generated platform files or private data are part of this push.
    Invoke-Checked "Fetch public main branch" {
        git fetch origin refs/heads/main:refs/remotes/origin/main
    }
    Invoke-Checked "Create screenshot-only branch from public main" {
        git switch -c $branch origin/main
    }
    Invoke-Checked "Stage ONLY three demo screenshots" {
        git add -- docs/screenshots/windows-workspace.png docs/screenshots/android-workspace.png docs/screenshots/android-note-editor.png
    }
    Invoke-Checked "Validate staged screenshots" { git diff --cached --check }
    Invoke-Checked "Commit demo screenshots" {
        git commit -m "docs: add real Fasty Windows and Android UI screenshots"
    }
    Invoke-Checked "Push screenshot-only branch" {
        git push -u origin $branch
    }

    Write-Host "SUCCESS: Three real demo screenshots pushed to branch $branch" -ForegroundColor Green
    Write-Host "No real account credentials, private notes, or production app data were used."
    Write-Host "Send the final terminal output to ChatGPT to finish GitHub README and website updates."
} finally {
    Pop-Location
}
