# Downloads the latest workflow run for this branch and installs its signed debug APK.
# Requirements: GitHub CLI (gh), Android platform-tools (adb), connected Android device.
param(
    [string]$Repository = 'timhdm/slovami-ai',
    [string]$Branch = 'fix/eres2net-diarization-crash'
)

$ErrorActionPreference = 'Stop'

foreach ($tool in @('gh', 'adb')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "Missing command: $tool. Install it and restart PowerShell."
    }
}

& gh auth status 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw 'GitHub CLI is not authenticated. Run: gh auth login'
}

$runsJson = & gh run list --repo $Repository --workflow android.yml --branch $Branch --limit 20 --json databaseId,createdAt,status,conclusion,event,headSha
if ($LASTEXITCODE -ne 0) { throw 'Could not list GitHub Actions runs.' }
$runs = @($runsJson | ConvertFrom-Json)
$run = $runs |
    Where-Object { $_.event -in @('push', 'workflow_dispatch') } |
    Sort-Object createdAt -Descending |
    Select-Object -First 1

if (-not $run) { throw "No workflow runs found for branch $Branch." }

Write-Host "Workflow run: $($run.databaseId), commit: $($run.headSha)"
if ($run.status -ne 'completed') {
    Write-Host 'Waiting for the workflow to complete...'
    & gh run watch $run.databaseId --repo $Repository --exit-status
    if ($LASTEXITCODE -ne 0) { throw 'GitHub Actions run did not succeed.' }
} elseif ($run.conclusion -ne 'success') {
    throw "Latest run did not succeed: $($run.conclusion). See: gh run view $($run.databaseId) --repo $Repository"
}

$devices = @(& adb devices | Select-Object -Skip 1 | Where-Object { $_ -match '\sdevice\s*$' })
if ($LASTEXITCODE -ne 0 -or $devices.Count -ne 1) {
    throw "Expected exactly one authorized ADB device, found $($devices.Count). Check: adb devices"
}

$dir = Join-Path ([System.IO.Path]::GetTempPath()) ("slovami-ai-" + $run.databaseId + "-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $dir -Force | Out-Null
Write-Host 'Downloading debug APK...'
& gh run download $run.databaseId --repo $Repository --name slovami-ai-debug-apk --dir $dir
if ($LASTEXITCODE -ne 0) { throw 'Could not download APK artifact.' }

$apks = @(Get-ChildItem -Path $dir -Filter '*.apk' -File -Recurse)
if ($apks.Count -ne 1) { throw "Expected one APK in $dir, found $($apks.Count)." }

Write-Host "Installing $($apks[0].Name)..."
& adb install -r $apks[0].FullName
if ($LASTEXITCODE -ne 0) {
    throw 'ADB installation failed. Check app signing key and device storage.'
}
Write-Host 'APK installed successfully.'
