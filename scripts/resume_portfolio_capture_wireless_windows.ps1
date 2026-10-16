# Resume screenshot capture over securely paired Android Wi-Fi, without rebuilding Windows.
# Runs in the disposable Fasty-Screenshot-Capture clone, NEVER the private Fasty.
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$repo = Join-Path $HOME "Fasty-Screenshot-Capture"
$client = Join-Path $repo "client"
$images = Join-Path $repo "docs\screenshots"
$package = "com.christosdamianidis.fasty.portfoliodemo"
$activity = "$package/com.christosdamianidis.fasty.MainActivity"
$reviewBranch = "docs/real-fasty-screenshots-20261016"
$expectedRemote = "https://github.com/christosdamianidis99/Fasty-Portfolio.git"

function Invoke-Checked([string]$label, [scriptblock]$cmd) {
    Write-Host "=== $label ===" -ForegroundColor Cyan
    & $cmd
    if ($LASTEXITCODE -ne 0) {
        throw "$label failed (exit $LASTEXITCODE)"
    }
}

if (-not (Test-Path (Join-Path $repo ".git"))) {
    throw "Missing original capture clone: $repo"
}
if ((& git -C $repo branch --show-current).Trim() -ne "tools/isolated-screenshot-capture-20261016") {
    throw "Wrong Git branch; refusing to capture."
}
if ((& git -C $repo remote get-url origin).Trim() -ne $expectedRemote) {
    throw "Wrong Git remote; refusing to publish."
}
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) { throw "Flutter not found." }

$adbCommand = Get-Command adb -ErrorAction SilentlyContinue
if ($adbCommand) { $adb = $adbCommand.Source }
else { $adb = Join-Path $env:LOCALAPPDATA "Android\Sdk\platform-tools\adb.exe" }
if (-not (Test-Path $adb)) { throw "Android Platform Tools / adb not found." }

$windowsPng = Join-Path $images "windows-workspace.png"
if (-not (Test-Path $windowsPng) -or (Get-Item $windowsPng).Length -lt 4000) {
    throw "Previous Windows screenshot missing/empty: $windowsPng"
}
Write-Host "Reusing Windows screenshot: $windowsPng" -ForegroundColor Green

# Secure Android 11+ wireless debugging pairing. Do not enable legacy
# adb tcpip 5555; pairing on the phone requires explicit user approval.
# The pairing port and the connect port are DIFFERENT numbers.
function Read-PrivateWirelessEndpoint([string]$Prompt) {
    $endpoint = (Read-Host $Prompt).Trim()
    if ($endpoint -notmatch '^(?<ip>(?:\d{1,3}\.){3}\d{1,3}):(?<port>\d{2,5})
function Invoke-Adb {
    param([string]$Label, [string[]]$Arguments)
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        $serial = Wait-Android
        try {
            & $adb -s $serial @Arguments 2>$null | Out-Host
            if ($LASTEXITCODE -eq 0) { return }
        } catch {
            Write-Warning "ADB reconnecting during $Label (attempt $attempt)."
        }
        Start-Sleep -Seconds 2
    }
    throw "ADB command failed after retries: $Label"
}
function Start-AndCheckDemo {
    param([string]$View)
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        $serial = Wait-Android
        Write-Host "Launching Fasty demo ($View); attempt $attempt"
        try {
            & $adb -s $serial shell am force-stop $package 2>$null | Out-Null
            & $adb -s $serial shell am start -n $activity 2>$null | Out-Host
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "ADB disconnected during launch; retrying after reconnect."
                continue
            }
        } catch {
            Write-Warning "USB/ADB temporarily unavailable during app launch."
            continue
        }
        Start-Sleep -Seconds 6
        $serial = Wait-Android
        for ($probe = 0; $probe -lt 10; $probe++) {
            try {
                $window = @(& $adb -s $serial shell dumpsys window 2>$null)
                $activityState = @(& $adb -s $serial shell dumpsys activity activities 2>$null)
            } catch {
                $window = @()
                $activityState = @()
            }
            $focused = ($window | Where-Object { $_ -match 'mCurrentFocus=|mFocusedApp=' }) -join ' '
            $resumed = ($activityState | Where-Object { $_ -match 'topResumedActivity|mResumedActivity' }) -join ' '
            if (($focused + $resumed).Contains($package)) {
                Write-Host "Verified real Fasty demo in foreground." -ForegroundColor Green
                return $serial
            }
            Start-Sleep -Seconds 2
        }
    }
    throw "Cannot confirm Fasty demo on screen. No phone screenshots were uploaded."
}
function Capture-Android {
    param([string]$View,[string]$File)
    $serial = Start-AndCheckDemo -View $View
    $remote = "/sdcard/Download/fasty-portfolio-demo-screenshot.png"
    $dest = Join-Path $images $File
    try {
        # If USB drops during capture, retry from the actual app launch.
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            try {
                $serial = Wait-Android
                & $adb -s $serial shell screencap -p $remote 2>$null | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    & $adb -s $serial pull $remote $dest 2>$null | Out-Host
                    if ($LASTEXITCODE -eq 0 -and (Test-Path $dest) -and (Get-Item $dest).Length -gt 4000) {
                        Write-Host "Saved $File" -ForegroundColor Green
                        return
                    }
                }
            } catch {
                Write-Warning "ADB connection interrupted while capturing $View."
            }
            Write-Warning "USB interruption during capture; relaunching demo."
            $serial = Start-AndCheckDemo -View $View
        }
        throw "Couldn't capture $View after 3 retries."
    } finally {
        try {
            $serial = Wait-Android -Seconds 10
            & $adb -s $serial shell rm -f $remote | Out-Null
        } catch {
            Write-Warning "Could not clean temporary screenshot on phone: $_"
        }
    }
}

$serial = Wait-Android
$installed = @(& $adb -s $serial shell pm path $package 2>$null)
if (-not (($installed -join ' ') -match 'package:')) {
    $apk = Join-Path $client "build\app\outputs\flutter-apk\app-debug.apk"
    if (-not (Test-Path $apk)) { throw "Workspace APK missing; cannot resume without rebuilding." }
    Invoke-Adb -Label "Install cached workspace demo APK" -Arguments @("install","-r",$apk)
}

try {
    Write-Host "=== Android workspace (no rebuild) ===" -ForegroundColor Cyan
    Capture-Android -View "workspace" -File "android-workspace.png"

    Write-Host "=== Build note editor demo (only remaining Android build) ===" -ForegroundColor Cyan
    Push-Location $client
    try {
        Invoke-Checked "Build Android editor screenshot demo" {
            flutter build apk --debug --target lib/portfolio_capture_main.dart --dart-define=FASTY_CAPTURE_VIEW=editor
        }
        $apk = Join-Path $client "build\app\outputs\flutter-apk\app-debug.apk"
        if (-not (Test-Path $apk)) { throw "Missing editor APK." }
        # Installs a DIFFERENT application ID from normal Fasty; no personal data.
        Invoke-Adb -Label "Install editor demo APK" -Arguments @("install","-r",$apk)
    } finally { Pop-Location }

    Capture-Android -View "editor" -File "android-note-editor.png"
} finally {
    try {
        $serial = Wait-Android -Seconds 10
        & $adb -s $serial uninstall $package | Out-Null
        Write-Host "Isolated demo app removed; normal Fasty untouched."
    } catch { Write-Warning "Demo uninstallation could not complete: $_" }
}

Add-Type -AssemblyName System.Drawing
foreach ($name in @("windows-workspace.png","android-workspace.png","android-note-editor.png")) {
    $path = Join-Path $images $name
    if (-not (Test-Path $path)) { throw "Screenshot missing: $name" }
    $stream = [System.IO.File]::OpenRead($path)
    try {
        $img = [System.Drawing.Image]::FromStream($stream)
        try {
            if ($img.Width -lt 320 -or $img.Height -lt 400) { throw "Invalid $name size." }
            Write-Host ("Verified {0}: {1} x {2}" -f $name,$img.Width,$img.Height)
        } finally { $img.Dispose() }
    } finally { $stream.Dispose() }
}

# Publish only 3 screenshots from a clean separate worktree at public main;
# do not stage generated build files or any personal data from capture clone.
Invoke-Checked "Fetch public main" {
    git -C $repo fetch origin refs/heads/main:refs/remotes/origin/main
}
$existing = @(& git -C $repo ls-remote --heads origin "refs/heads/$reviewBranch")
if ($existing.Count -gt 0) { throw "Screenshot review branch already exists. Refusing overwrite." }
$publishDir = Join-Path $env:TEMP ("fasty-screenshot-upload-" + [guid]::NewGuid().ToString("N"))
Invoke-Checked "Create clean screenshot-only worktree" {
    git -C $repo worktree add -b $reviewBranch $publishDir origin/main
}
Push-Location $publishDir
try {
    New-Item -ItemType Directory -Force -Path "docs\screenshots" | Out-Null
    foreach ($name in @("windows-workspace.png","android-workspace.png","android-note-editor.png")) {
        Copy-Item (Join-Path $images $name) (Join-Path "docs\screenshots" $name)
    }
    Invoke-Checked "Stage only three PNG files" {
        git add -- docs/screenshots/windows-workspace.png docs/screenshots/android-workspace.png docs/screenshots/android-note-editor.png
    }
    $staged = @(& git diff --cached --name-only)
    if ($staged.Count -ne 3) { throw "Expected exactly three screenshots staged." }
    Invoke-Checked "Check screenshot staging" { git diff --cached --check }
    Invoke-Checked "Commit screenshots" { git commit -m "docs: capture Fasty Windows and Android demo UI" }
    Invoke-Checked "Push screenshot review branch" { git push -u origin $reviewBranch }
    Write-Host "SUCCESS: Real app screenshots uploaded to branch $reviewBranch" -ForegroundColor Green
    Write-Host "Send this output to ChatGPT to add screenshots to README and website."
} finally { Pop-Location }
) {
        throw "Expected a local IPv4 address and port, e.g. 192.168.1.10:37123"
    }
    $ip = [System.Net.IPAddress]::Parse($Matches['ip'])
    $octets = $ip.GetAddressBytes()
    $isPrivate = ($octets[0] -eq 10) -or
        ($octets[0] -eq 192 -and $octets[1] -eq 168) -or
        ($octets[0] -eq 172 -and $octets[1] -ge 16 -and $octets[1] -le 31)
    $port = [int]$Matches['port']
    if (-not $isPrivate -or $port -lt 1 -or $port -gt 65535) {
        throw "Only private Wi-Fi IPv4 addresses and valid ports are allowed."
    }
    return $endpoint
}

Write-Host "=== Secure Android Wireless Debugging setup ===" -ForegroundColor Cyan
Write-Host "Unplug the USB cable. Both devices must be on the same trusted Wi-Fi network."
Write-Host "Phone: Developer options -> Wireless debugging -> Pair device with pairing code."
$pairEndpoint = Read-PrivateWirelessEndpoint "PAIRING screen IP:port (temporary pairing port)"
Invoke-Checked "Secure wireless debugging pairing" {
    # ADB prompts for the six-digit code on this PC. Do not send it in chat.
    & $adb pair $pairEndpoint
}
Write-Host "Return to the phone's main Wireless debugging screen."
$wirelessSerial = Read-PrivateWirelessEndpoint "Main Wireless debugging IP:port (connection port)"
Invoke-Checked "Connect securely paired Android device" { & $adb connect $wirelessSerial }

# Use ONLY the paired Wi-Fi endpoint. Ignore any USB connections.
function Wait-Android {
    param([int]$Seconds = 120)
    $deadline = (Get-Date).AddSeconds($Seconds)
    $lastReported = $null
    $nextReconnect = Get-Date
    while ((Get-Date) -lt $deadline) {
        try { $listing = @(& $adb devices 2>$null) } catch { $listing = @() }
        foreach ($line in $listing) {
            if ($line -match '^([^\s]+)\s+device\s*
function Invoke-Adb {
    param([string]$Label, [string[]]$Arguments)
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        $serial = Wait-Android
        try {
            & $adb -s $serial @Arguments 2>$null | Out-Host
            if ($LASTEXITCODE -eq 0) { return }
        } catch {
            Write-Warning "ADB reconnecting during $Label (attempt $attempt)."
        }
        Start-Sleep -Seconds 2
    }
    throw "ADB command failed after retries: $Label"
}
function Start-AndCheckDemo {
    param([string]$View)
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        $serial = Wait-Android
        Write-Host "Launching Fasty demo ($View); attempt $attempt"
        try {
            & $adb -s $serial shell am force-stop $package 2>$null | Out-Null
            & $adb -s $serial shell am start -n $activity 2>$null | Out-Host
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "ADB disconnected during launch; retrying after reconnect."
                continue
            }
        } catch {
            Write-Warning "USB/ADB temporarily unavailable during app launch."
            continue
        }
        Start-Sleep -Seconds 6
        $serial = Wait-Android
        for ($probe = 0; $probe -lt 10; $probe++) {
            try {
                $window = @(& $adb -s $serial shell dumpsys window 2>$null)
                $activityState = @(& $adb -s $serial shell dumpsys activity activities 2>$null)
            } catch {
                $window = @()
                $activityState = @()
            }
            $focused = ($window | Where-Object { $_ -match 'mCurrentFocus=|mFocusedApp=' }) -join ' '
            $resumed = ($activityState | Where-Object { $_ -match 'topResumedActivity|mResumedActivity' }) -join ' '
            if (($focused + $resumed).Contains($package)) {
                Write-Host "Verified real Fasty demo in foreground." -ForegroundColor Green
                return $serial
            }
            Start-Sleep -Seconds 2
        }
    }
    throw "Cannot confirm Fasty demo on screen. No phone screenshots were uploaded."
}
function Capture-Android {
    param([string]$View,[string]$File)
    $serial = Start-AndCheckDemo -View $View
    $remote = "/sdcard/Download/fasty-portfolio-demo-screenshot.png"
    $dest = Join-Path $images $File
    try {
        # If USB drops during capture, retry from the actual app launch.
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            try {
                $serial = Wait-Android
                & $adb -s $serial shell screencap -p $remote 2>$null | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    & $adb -s $serial pull $remote $dest 2>$null | Out-Host
                    if ($LASTEXITCODE -eq 0 -and (Test-Path $dest) -and (Get-Item $dest).Length -gt 4000) {
                        Write-Host "Saved $File" -ForegroundColor Green
                        return
                    }
                }
            } catch {
                Write-Warning "ADB connection interrupted while capturing $View."
            }
            Write-Warning "USB interruption during capture; relaunching demo."
            $serial = Start-AndCheckDemo -View $View
        }
        throw "Couldn't capture $View after 3 retries."
    } finally {
        try {
            $serial = Wait-Android -Seconds 10
            & $adb -s $serial shell rm -f $remote | Out-Null
        } catch {
            Write-Warning "Could not clean temporary screenshot on phone: $_"
        }
    }
}

$serial = Wait-Android
$installed = @(& $adb -s $serial shell pm path $package 2>$null)
if (-not (($installed -join ' ') -match 'package:')) {
    $apk = Join-Path $client "build\app\outputs\flutter-apk\app-debug.apk"
    if (-not (Test-Path $apk)) { throw "Workspace APK missing; cannot resume without rebuilding." }
    Invoke-Adb -Label "Install cached workspace demo APK" -Arguments @("install","-r",$apk)
}

try {
    Write-Host "=== Android workspace (no rebuild) ===" -ForegroundColor Cyan
    Capture-Android -View "workspace" -File "android-workspace.png"

    Write-Host "=== Build note editor demo (only remaining Android build) ===" -ForegroundColor Cyan
    Push-Location $client
    try {
        Invoke-Checked "Build Android editor screenshot demo" {
            flutter build apk --debug --target lib/portfolio_capture_main.dart --dart-define=FASTY_CAPTURE_VIEW=editor
        }
        $apk = Join-Path $client "build\app\outputs\flutter-apk\app-debug.apk"
        if (-not (Test-Path $apk)) { throw "Missing editor APK." }
        # Installs a DIFFERENT application ID from normal Fasty; no personal data.
        Invoke-Adb -Label "Install editor demo APK" -Arguments @("install","-r",$apk)
    } finally { Pop-Location }

    Capture-Android -View "editor" -File "android-note-editor.png"
} finally {
    try {
        $serial = Wait-Android -Seconds 10
        & $adb -s $serial uninstall $package | Out-Null
        Write-Host "Isolated demo app removed; normal Fasty untouched."
    } catch { Write-Warning "Demo uninstallation could not complete: $_" }
}

Add-Type -AssemblyName System.Drawing
foreach ($name in @("windows-workspace.png","android-workspace.png","android-note-editor.png")) {
    $path = Join-Path $images $name
    if (-not (Test-Path $path)) { throw "Screenshot missing: $name" }
    $stream = [System.IO.File]::OpenRead($path)
    try {
        $img = [System.Drawing.Image]::FromStream($stream)
        try {
            if ($img.Width -lt 320 -or $img.Height -lt 400) { throw "Invalid $name size." }
            Write-Host ("Verified {0}: {1} x {2}" -f $name,$img.Width,$img.Height)
        } finally { $img.Dispose() }
    } finally { $stream.Dispose() }
}

# Publish only 3 screenshots from a clean separate worktree at public main;
# do not stage generated build files or any personal data from capture clone.
Invoke-Checked "Fetch public main" {
    git -C $repo fetch origin refs/heads/main:refs/remotes/origin/main
}
$existing = @(& git -C $repo ls-remote --heads origin "refs/heads/$reviewBranch")
if ($existing.Count -gt 0) { throw "Screenshot review branch already exists. Refusing overwrite." }
$publishDir = Join-Path $env:TEMP ("fasty-screenshot-upload-" + [guid]::NewGuid().ToString("N"))
Invoke-Checked "Create clean screenshot-only worktree" {
    git -C $repo worktree add -b $reviewBranch $publishDir origin/main
}
Push-Location $publishDir
try {
    New-Item -ItemType Directory -Force -Path "docs\screenshots" | Out-Null
    foreach ($name in @("windows-workspace.png","android-workspace.png","android-note-editor.png")) {
        Copy-Item (Join-Path $images $name) (Join-Path "docs\screenshots" $name)
    }
    Invoke-Checked "Stage only three PNG files" {
        git add -- docs/screenshots/windows-workspace.png docs/screenshots/android-workspace.png docs/screenshots/android-note-editor.png
    }
    $staged = @(& git diff --cached --name-only)
    if ($staged.Count -ne 3) { throw "Expected exactly three screenshots staged." }
    Invoke-Checked "Check screenshot staging" { git diff --cached --check }
    Invoke-Checked "Commit screenshots" { git commit -m "docs: capture Fasty Windows and Android demo UI" }
    Invoke-Checked "Push screenshot review branch" { git push -u origin $reviewBranch }
    Write-Host "SUCCESS: Real app screenshots uploaded to branch $reviewBranch" -ForegroundColor Green
    Write-Host "Send this output to ChatGPT to add screenshots to README and website."
} finally { Pop-Location }
 -and $Matches[1] -eq $wirelessSerial) {
                return $wirelessSerial
            }
        }
        if ((Get-Date) -ge $nextReconnect) {
            try { & $adb connect $wirelessSerial 2>$null | Out-Null } catch {}
            $nextReconnect = (Get-Date).AddSeconds(8)
        }
        $state = "Waiting for wireless ADB on $wirelessSerial. Keep phone unlocked and Wireless debugging enabled."
        if ($state -ne $lastReported) { Write-Host $state -ForegroundColor Yellow; $lastReported = $state }
        Start-Sleep -Seconds 2
    }
    throw "Wireless ADB unavailable. Check Wi-Fi, Wireless debugging, or the connection port shown by the phone."
}
function Invoke-Adb {
    param([string]$Label, [string[]]$Arguments)
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        $serial = Wait-Android
        try {
            & $adb -s $serial @Arguments 2>$null | Out-Host
            if ($LASTEXITCODE -eq 0) { return }
        } catch {
            Write-Warning "ADB reconnecting during $Label (attempt $attempt)."
        }
        Start-Sleep -Seconds 2
    }
    throw "ADB command failed after retries: $Label"
}
function Start-AndCheckDemo {
    param([string]$View)
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        $serial = Wait-Android
        Write-Host "Launching Fasty demo ($View); attempt $attempt"
        try {
            & $adb -s $serial shell am force-stop $package 2>$null | Out-Null
            & $adb -s $serial shell am start -n $activity 2>$null | Out-Host
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "ADB disconnected during launch; retrying after reconnect."
                continue
            }
        } catch {
            Write-Warning "USB/ADB temporarily unavailable during app launch."
            continue
        }
        Start-Sleep -Seconds 6
        $serial = Wait-Android
        for ($probe = 0; $probe -lt 10; $probe++) {
            try {
                $window = @(& $adb -s $serial shell dumpsys window 2>$null)
                $activityState = @(& $adb -s $serial shell dumpsys activity activities 2>$null)
            } catch {
                $window = @()
                $activityState = @()
            }
            $focused = ($window | Where-Object { $_ -match 'mCurrentFocus=|mFocusedApp=' }) -join ' '
            $resumed = ($activityState | Where-Object { $_ -match 'topResumedActivity|mResumedActivity' }) -join ' '
            if (($focused + $resumed).Contains($package)) {
                Write-Host "Verified real Fasty demo in foreground." -ForegroundColor Green
                return $serial
            }
            Start-Sleep -Seconds 2
        }
    }
    throw "Cannot confirm Fasty demo on screen. No phone screenshots were uploaded."
}
function Capture-Android {
    param([string]$View,[string]$File)
    $serial = Start-AndCheckDemo -View $View
    $remote = "/sdcard/Download/fasty-portfolio-demo-screenshot.png"
    $dest = Join-Path $images $File
    try {
        # If USB drops during capture, retry from the actual app launch.
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            try {
                $serial = Wait-Android
                & $adb -s $serial shell screencap -p $remote 2>$null | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    & $adb -s $serial pull $remote $dest 2>$null | Out-Host
                    if ($LASTEXITCODE -eq 0 -and (Test-Path $dest) -and (Get-Item $dest).Length -gt 4000) {
                        Write-Host "Saved $File" -ForegroundColor Green
                        return
                    }
                }
            } catch {
                Write-Warning "ADB connection interrupted while capturing $View."
            }
            Write-Warning "USB interruption during capture; relaunching demo."
            $serial = Start-AndCheckDemo -View $View
        }
        throw "Couldn't capture $View after 3 retries."
    } finally {
        try {
            $serial = Wait-Android -Seconds 10
            & $adb -s $serial shell rm -f $remote | Out-Null
        } catch {
            Write-Warning "Could not clean temporary screenshot on phone: $_"
        }
    }
}

$serial = Wait-Android
$installed = @(& $adb -s $serial shell pm path $package 2>$null)
if (-not (($installed -join ' ') -match 'package:')) {
    $apk = Join-Path $client "build\app\outputs\flutter-apk\app-debug.apk"
    if (-not (Test-Path $apk)) { throw "Workspace APK missing; cannot resume without rebuilding." }
    Invoke-Adb -Label "Install cached workspace demo APK" -Arguments @("install","-r",$apk)
}

try {
    Write-Host "=== Android workspace (no rebuild) ===" -ForegroundColor Cyan
    Capture-Android -View "workspace" -File "android-workspace.png"

    Write-Host "=== Build note editor demo (only remaining Android build) ===" -ForegroundColor Cyan
    Push-Location $client
    try {
        Invoke-Checked "Build Android editor screenshot demo" {
            flutter build apk --debug --target lib/portfolio_capture_main.dart --dart-define=FASTY_CAPTURE_VIEW=editor
        }
        $apk = Join-Path $client "build\app\outputs\flutter-apk\app-debug.apk"
        if (-not (Test-Path $apk)) { throw "Missing editor APK." }
        # Installs a DIFFERENT application ID from normal Fasty; no personal data.
        Invoke-Adb -Label "Install editor demo APK" -Arguments @("install","-r",$apk)
    } finally { Pop-Location }

    Capture-Android -View "editor" -File "android-note-editor.png"
} finally {
    try {
        $serial = Wait-Android -Seconds 10
        & $adb -s $serial uninstall $package | Out-Null
        Write-Host "Isolated demo app removed; normal Fasty untouched."
    } catch { Write-Warning "Demo uninstallation could not complete: $_" }
}

Add-Type -AssemblyName System.Drawing
foreach ($name in @("windows-workspace.png","android-workspace.png","android-note-editor.png")) {
    $path = Join-Path $images $name
    if (-not (Test-Path $path)) { throw "Screenshot missing: $name" }
    $stream = [System.IO.File]::OpenRead($path)
    try {
        $img = [System.Drawing.Image]::FromStream($stream)
        try {
            if ($img.Width -lt 320 -or $img.Height -lt 400) { throw "Invalid $name size." }
            Write-Host ("Verified {0}: {1} x {2}" -f $name,$img.Width,$img.Height)
        } finally { $img.Dispose() }
    } finally { $stream.Dispose() }
}

# Publish only 3 screenshots from a clean separate worktree at public main;
# do not stage generated build files or any personal data from capture clone.
Invoke-Checked "Fetch public main" {
    git -C $repo fetch origin refs/heads/main:refs/remotes/origin/main
}
$existing = @(& git -C $repo ls-remote --heads origin "refs/heads/$reviewBranch")
if ($existing.Count -gt 0) { throw "Screenshot review branch already exists. Refusing overwrite." }
$publishDir = Join-Path $env:TEMP ("fasty-screenshot-upload-" + [guid]::NewGuid().ToString("N"))
Invoke-Checked "Create clean screenshot-only worktree" {
    git -C $repo worktree add -b $reviewBranch $publishDir origin/main
}
Push-Location $publishDir
try {
    New-Item -ItemType Directory -Force -Path "docs\screenshots" | Out-Null
    foreach ($name in @("windows-workspace.png","android-workspace.png","android-note-editor.png")) {
        Copy-Item (Join-Path $images $name) (Join-Path "docs\screenshots" $name)
    }
    Invoke-Checked "Stage only three PNG files" {
        git add -- docs/screenshots/windows-workspace.png docs/screenshots/android-workspace.png docs/screenshots/android-note-editor.png
    }
    $staged = @(& git diff --cached --name-only)
    if ($staged.Count -ne 3) { throw "Expected exactly three screenshots staged." }
    Invoke-Checked "Check screenshot staging" { git diff --cached --check }
    Invoke-Checked "Commit screenshots" { git commit -m "docs: capture Fasty Windows and Android demo UI" }
    Invoke-Checked "Push screenshot review branch" { git push -u origin $reviewBranch }
    Write-Host "SUCCESS: Real app screenshots uploaded to branch $reviewBranch" -ForegroundColor Green
    Write-Host "Send this output to ChatGPT to add screenshots to README and website."
} finally { Pop-Location }
