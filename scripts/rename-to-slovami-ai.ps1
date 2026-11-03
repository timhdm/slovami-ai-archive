# One-time source package migration for Slovami AI.
# Run from a clean checkout of fix/eres2net-diarization-crash.
$ErrorActionPreference = 'Stop'
$repoRoot = (git rev-parse --show-toplevel).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Not inside a Git repository.' }
Set-Location $repoRoot
if ((git branch --show-current).Trim() -ne 'fix/eres2net-diarization-crash') {
    throw 'Wrong branch. Expected fix/eres2net-diarization-crash.'
}
if (git status --porcelain) { throw 'Working tree must be clean. Commit or discard local changes first.' }

# Rewrite only tracked text source files. Preserve third-party URLs and licensing notices.
$extensions = @('.kt', '.kts', '.xml', '.md', '.ps1', '.yml', '.yaml', '.properties', '.pro')
$tracked = @(git ls-files)
foreach ($relative in $tracked) {
    $ext = [IO.Path]::GetExtension($relative)
    if ($ext -notin $extensions) { continue }
    $full = Join-Path $repoRoot ($relative.Replace('/', [IO.Path]::DirectorySeparatorChar))
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { continue }
    $text = [IO.File]::ReadAllText($full)
    $updated = $text.Replace('app.slovami.ai', 'app.slovami.ai')
    $updated = $updated.Replace('SlovamiAiApp', 'SlovamiAiApp')
    if ($ext -in @('.kt', '.kts')) {
        $updated = $updated.Replace('ProtocolVoice', 'SlovamiAI')
    } elseif ($ext -eq '.xml') {
        $updated = $updated.Replace('Theme.ProtocolVoice', 'Theme.SlovamiAI')
        $updated = $updated.Replace('>ProtocolVoice<', '>Slovami AI<')
        $updated = $updated.Replace('Downloads/ProtocolVoice', 'Downloads/SlovamiAI')
    } elseif ($ext -eq '.md') {
        $updated = $updated.Replace('# ProtocolVoice', '# Slovami AI')
        $updated = $updated.Replace('ProtocolVoice transcribes', 'Slovami AI transcribes')
        $updated = $updated.Replace('ProtocolVoice runs', 'Slovami AI runs')
        $updated = $updated.Replace('ProtocolVoice has', 'Slovami AI has')
        $updated = $updated.Replace('## Why ProtocolVoice', '## Why Slovami AI')
        $updated = $updated.Replace('Downloads/ProtocolVoice', 'Downloads/SlovamiAI')
    } elseif ($ext -eq '.ps1') {
        $updated = $updated.Replace("'timhdm/slovami-ai'", "'timhdm/slovami-ai'")
        $updated = $updated.Replace('slovami-ai-debug-apk', 'slovami-ai-debug-apk')
    }
    if ($updated -cne $text) {
        [IO.File]::WriteAllText($full, $updated, [Text.UTF8Encoding]::new($false))
    }
}

# Move tracked Kotlin source trees; Git will detect the renames.
$roots = @('app/src/main/java/app/protocolvoice', 'app/src/test/java/app/protocolvoice', 'app/src/androidTest/java/app/protocolvoice')
foreach ($source in $roots) {
    if (Test-Path $source) {
        $target = $source.Replace('app/protocolvoice', 'app/slovami/ai')
        New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
        git mv $source $target
        if ($LASTEXITCODE -ne 0) { throw "Could not move $source." }
    }
}

# Rename the Application class file, if present.
$appFile = 'app/src/main/java/app/slovami/ai/SlovamiAiApp.kt'
if (Test-Path $appFile) {
    git mv $appFile 'app/src/main/java/app/slovami/ai/SlovamiAiApp.kt'
    if ($LASTEXITCODE -ne 0) { throw 'Could not rename Application source file.' }
}
Write-Host 'Migration prepared. Review git diff and build before committing.'
git status --short
