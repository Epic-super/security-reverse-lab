<#
  fv-redact-scan.ps1 -- scan the repo for anything that should not be public
  Usage:
    powershell -ExecutionPolicy Bypass -File fv-redact-scan.ps1
    powershell -ExecutionPolicy Bypass -File fv-redact-scan.ps1 -Path "D:\some\other\dir"
#>
param([string]$Path = "D:\Desktop\FelixVec-Git")

$ErrorActionPreference = "Continue"
$hits = New-Object System.Collections.ArrayList

function Add-Hit($file, $line, $text, $cat) {
    $rel = $file.Replace($Path, ".")
    [void]$hits.Add([pscustomobject]@{ File = $rel; Line = $line; Category = $cat; Snippet = $text.Trim() })
}

$files = Get-ChildItem -Path $Path -Recurse -File -Force |
    Where-Object { $_.FullName -notmatch '\\\.git\\|\\node_modules\\|\\__pycache__\\|\\\.venv\\' -and $_.Length -lt 5MB }

Write-Host "scanning $($files.Count) files under $Path" -ForegroundColor Cyan

foreach ($f in $files) {
    if ($f.Extension -match '^\.(png|jpg|jpeg|gif|webp|ico|pdf|zip|rar|7z|exe|dll|so|dylib|apk|ipa|bin|pack)$') { continue }
    try {
        $content = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8)
    } catch { continue }
    if (-not $content) { continue }

    # The prompt templates intentionally contain synthetic examples of sensitive values
    $isTemplate = $f.FullName -match 'PROMPT-single-dialog-summary\.md$|PROMPT-combos\.md$'

    $lines = $content -split "`r?`n"
    $inExample = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $l = $lines[$i]
        if ($l.Trim().Length -eq 0) { continue }
        if ($isTemplate) { continue }

        # Regions marked with these markers are demo samples, not real data
        if ($l -match '<!--\s*redact-scan:\s*skip\s*-->') { $inExample = $true; continue }
        if ($l -match '<!--\s*redact-scan:\s*end\s*-->') { $inExample = $false; continue }
        if ($inExample) { continue }

        # credentials
        if ($l -match '(ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|gho_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{30,}|sk-[A-Za-z0-9]{32,}|-----BEGIN [A-Z ]*PRIVATE KEY-----)') {
            Add-Hit $f.FullName ($i+1) $l "credential"
        }
        # real email
        if ($l -match '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' -and $l -notmatch 'example\.(com|org|net)|@users\.noreply\.github\.com|git@github\.com|<REDACTED|\{\{|\}\}|placeholder|@qq\.com') {
            Add-Hit $f.FullName ($i+1) $l "email"
        }
        # private network IP
        if ($l -match '\b(10\.[0-9]{1,3}|172\.(1[6-9]|2[0-9]|3[01])|192\.168)\.[0-9]{1,3}\.[0-9]{1,3}\b') {
            Add-Hit $f.FullName ($i+1) $l "private-ip"
        }
        # real windows user path
        if ($l -match '[A-Za-z]:\\Users\\[^\\\s"'']+' -and $l -notmatch '<你的名字>|真实名|USER_HOME|Users\\\\') {
            Add-Hit $f.FullName ($i+1) $l "user-path"
        }
        # business hostname: require a plausible domain shape and a real-ish TLD
        $domRe = '(?<![\w.-])([a-z0-9][a-z0-9-]{0,62}\.){1,3}(com|cn|net|org|io|top|xyz|cc|vip|co|me|dev|app|cloud|site|tech)(?![\w-])'
        if ($l -match $domRe -and
            $l -notmatch 'example\.(com|org|net)|com\.example\.app|github\.com|githubusercontent\.com|github\.io|localhost|w3\.org|apache\.org|gnu\.org|python\.org|nist\.gov|owasp\.org|pentestmonkey\.com|portswigger\.net|readthedocs\.io|shields\.io|Encoding\.UTF8|UTF8Encoding|Text\.Encoding|@qq\.com|asp\.net|ASP\.NET|aspnet') {
            Add-Hit $f.FullName ($i+1) $l "external-host"
        }
    }
}

if ($hits.Count -eq 0) {
    Write-Host "`nCLEAN -- nothing sensitive found." -ForegroundColor Green
    exit 0
}

Write-Host "`n$($hits.Count) potential issue(s):`n" -ForegroundColor Yellow
$hits | Group-Object Category | ForEach-Object {
    Write-Host "== $($_.Name) ($($_.Count)) ==" -ForegroundColor Yellow
    $_.Group | Select-Object -First 20 | ForEach-Object {
        $snip = $_.Snippet
        if ($snip.Length -gt 110) { $snip = $snip.Substring(0,110) + "..." }
        Write-Host ("  {0}:{1}  {2}" -f $_.File, $_.Line, $snip) -ForegroundColor DarkYellow
    }
    if ($_.Count -gt 20) { Write-Host "  ... and $($_.Count - 20) more" -ForegroundColor DarkGray }
    Write-Host ""
}
Write-Host "Fix: replace with TARGET / TARGET_IP / <REDACTED> / USER_HOME etc." -ForegroundColor Cyan
exit 1
