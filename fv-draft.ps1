<#
  fv-draft.ps1 -- start a new note from a template
  Usage:
    powershell -ExecutionPolicy Bypass -File fv-draft.ps1 -Type reverse -Title "NSIS 壳脱壳过程"
    powershell -ExecutionPolicy Bypass -File fv-draft.ps1 -Type vuln    -Title "JWT alg=none 与 kid 注入组合"
    powershell -ExecutionPolicy Bypass -File fv-draft.ps1 -Type lab     -Title "DC-3"
    powershell -ExecutionPolicy Bypass -File fv-draft.ps1 -Type writeup -Title "第一次赏金提交流"
#>
param(
    [Parameter(Mandatory=$true)][ValidateSet("reverse","vuln","lab","writeup")][string]$Type,
    [Parameter(Mandatory=$true)][string]$Title,
    [string]$Path = ""
)

$ErrorActionPreference = "Stop"
$Repo = "D:\Desktop\FelixVec-Git"
$TplDir = Join-Path $Repo "_templates"

$map = @{
    reverse = @{ tpl = "reverse-note.md"; dir = "01-reverse" }
    vuln    = @{ tpl = "vuln-analysis.md"; dir = "02-pentest" }
    lab     = @{ tpl = "lab-record.md";  dir = "03-labs" }
    writeup = @{ tpl = "lab-record.md";  dir = "05-writeups" }
}

$m = $map[$Type]
$tpl = Join-Path $TplDir $m.tpl
if (-not (Test-Path $tpl)) { Write-Host "template missing: $tpl" -ForegroundColor Red; exit 1 }

if (-not $Path) {
    # ASCII-only slug; non-ASCII characters are dropped so the path stays shell-safe
    $slug = ($Title -replace '[^\x20-\x7E]','' -replace '[\\/:*?"<>|]','' -replace '\s+','-').ToLower().Trim('-')
    if (-not $slug) { $slug = "note-" + (Get-Date -Format "yyyyMMdd-HHmmss") }
    $Path = Join-Path (Join-Path $Repo $m.dir) $slug
}
New-Item -ItemType Directory -Force $Path | Out-Null

$target = Join-Path $Path "README.md"
if (Test-Path $target) {
    Write-Host "already exists: $target" -ForegroundColor Yellow
    exit 1
}

$content = Get-Content $tpl -Raw
$content = $content -replace '^# .*$', "# $Title" -replace '(?m)^# 逆向分析笔记$',"# $Title"
Set-Content -Path $target -Value $content -Encoding UTF8

$notes = Join-Path $Path "notes.md"
if (-not (Test-Path $notes)) {
@"
# 过程记录 · $Title

## 时间线

| 时间 | 动作 | 结果 |
|---|---|---|
| | | |

## 踩过的坑

| 现象 | 原因 | 解决 |
|---|---|---|
| | | |

## 待办

- [ ]
"@ | Set-Content -Path $notes -Encoding UTF8
}

New-Item -ItemType Directory -Force (Join-Path $Path "artifacts") | Out-Null

Write-Host ""
Write-Host "created: $target" -ForegroundColor Green
Write-Host "         $notes" -ForegroundColor Green
Write-Host "         $(Join-Path $Path 'artifacts')" -ForegroundColor Green
Write-Host ""
Write-Host "next: open _templates\PROMPTS.md, copy the matching prompt," -ForegroundColor Cyan
Write-Host "      paste it into the conversation where you did the work," -ForegroundColor Cyan
Write-Host "      and let it turn your notes into a readable article." -ForegroundColor Cyan
