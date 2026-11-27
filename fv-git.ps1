<#
  GitHub channel helper (active: Epic-super / security-reverse-lab)
  Usage:
    fv-git.ps1 push    -> push main to the active repo over SSH
    fv-git.ps1 publish -> create the GitHub repo + push (needs token)
    fv-git.ps1 status  -> show channel status
    fv-git.ps1 doctor  -> diagnose ssh/auth
#>

$ErrorActionPreference = "Stop"
$Repo    = "D:\Desktop\FelixVec-Git"
$Remote  = "git@github-epic:Epic-super/security-reverse-lab.git"
$Alias   = "github-epic"
$KeyFile = "$env:USERPROFILE\.ssh\id_ed25519"

function Write-Step($m) { Write-Host "`n>> $m" -ForegroundColor Cyan }
function Write-Ok($m)   { Write-Host "   [OK] $m" -ForegroundColor Green }
function Write-Warn($m) { Write-Host "   [--] $m" -ForegroundColor Yellow }
function Write-Err($m)  { Write-Host "   [!!] $m" -ForegroundColor Red }

function Test-Key {
    if (-not (Test-Path $KeyFile)) { Write-Err "missing key: $KeyFile"; return $false }
    if (-not (Test-Path "$KeyFile.pub")) { Write-Err "missing pubkey"; return $false }
    Write-Ok "key present: $KeyFile"
    return $true
}

function Test-SshAuth {
    Write-Step "Testing SSH auth against GitHub via alias '$Alias'"
    $out = & ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 $Alias -T git@github.com 2>&1 | Out-String
    if ($out -match "successfully authenticated") {
        if ($out -match "Hi ([A-Za-z0-9_-]+)!") {
            Write-Ok "authenticated as '$($matches[1])'"
        } else { Write-Ok "authenticated" }
        return $true
    }
    Write-Warn "SSH auth failed -- public key is not registered on the FelixVec account yet."
    Write-Host $out
    return $false
}

switch ($args[0]) {

"status" {
    Write-Step "GitHub channel status"
    Write-Host "   repo path : $Repo"
    Write-Host "   remote    : $Remote"
    Write-Host "   ssh alias : $Alias"
    Write-Host "   key       : $KeyFile"
    Write-Host "   git user  : $(git -C $Repo config user.name) <$(git -C $Repo config user.email)>"
    Write-Host ""
    Write-Host "   [public key to register on the account]"
    Get-Content "$KeyFile.pub"
    Write-Host ""
    Write-Host "   [ssh config entries]"
    Select-String -Path "$env:USERPROFILE\.ssh\config" -Pattern "github-epic" -Context 0,5 | ForEach-Object { $_.Line; $_.Context.PostContext }
    Test-SshAuth | Out-Null
}

"doctor" {
    Write-Step "Diagnostics"
    Write-Host "   git   : $(git --version)"
    Write-Host "   gh    : $((& gh --version 2>$null) -join ' ')"
    Write-Host "   ssh   : $((& ssh -V 2>&1) -join ' ')"
    Write-Host ""
    Test-Key | Out-Null
    Test-SshAuth | Out-Null
    Write-Step "gh auth"
    & gh auth status 2>&1 | ForEach-Object { "   $_" }
}

"push" {
    if (-not (Test-Path $Repo)) { Write-Err "repo missing: $Repo"; exit 1 }
    Set-Location $Repo
    Write-Step "Committing and pushing to FelixVec"
    git add -A
    if (git diff --cached --quiet) { Write-Warn "nothing staged" }
    else {
        git commit -m "docs: update notes" 2>&1 | ForEach-Object { "   $_" }
    }
    if (Test-SshAuth) {
        git remote remove origin 2>$null
        git remote add origin $Remote
        git push -u origin main 2>&1 | ForEach-Object { "   $_" }
        Write-Ok "pushed to $Remote"
    } else {
        Write-Err "SSH channel not ready -- public key must be added to the GitHub account."
    }
}

"publish" {
    Write-Step "Publishing repo to GitHub"
    Write-Host "   Requires a token for the FelixVec account (gh auth login, or GITHUB_TOKEN)."
    Write-Host "   Set it in the environment, then re-run:"
    Write-Host "     `$env:GH_TOKEN = 'ghp_xxx' ; fv-git.ps1 publish"
    Write-Host ""
    $tok = $env:GH_TOKEN
    if (-not $tok) { Write-Err "GH_TOKEN not set"; exit 1 }

    $api = "https://api.github.com"
    $h = @{ Authorization = "Bearer $tok"; Accept = "application/vnd.github+json"; "X-GitHub-Api-Version" = "2022-11-28"; "User-Agent" = "fv-git" }

    $me = Invoke-RestMethod -Uri "$api/user" -Headers $h
    Write-Ok "token owner: $($me.login)"
    if ($me.login -ne "felixvec") { Write-Warn "token owner is '$($me.login)', expected 'felixvec'" }

    # 1) register ssh key
    $pub = (Get-Content "$KeyFile.pub" -Raw).Trim()
    $existing = Invoke-RestMethod -Uri "$api/user/keys" -Headers $h
    $match = $existing | Where-Object { $_.key -eq ($pub -split ' ')[1] }
    if ($match) { Write-Ok "ssh key already registered" }
    else {
        $null = Invoke-RestMethod -Uri "$api/user/keys" -Method Post -Headers $h -Body @{ title = "FelixVec-workstation"; key = $pub }
        Write-Ok "ssh key registered"
    }

    # 2) create repo
    $repoName = "security-reverse-lab"
    try {
        $null = Invoke-RestMethod -Uri "$api/user/repos" -Method Post -Headers $h -Body @{
            name = $repoName; description = "Reverse engineering & vulnerability research notes"
            private = $false; auto_init = $false; has_issues = $true; has_wiki = $false
        }
        Write-Ok "repo created: felixvec/$repoName"
    } catch {
        if ($_.Exception.Response.StatusCode -eq 422) { Write-Warn "repo already exists" }
        else { throw }
    }

    # 3) push
    Set-Location $Repo
    git remote remove origin 2>$null
    git remote add origin $Remote
    git push -u origin main 2>&1 | ForEach-Object { "   $_" }
    Write-Ok "push done"
}

default {
    Write-Host "fv-git.ps1 <status|doctor|push|publish>"
    exit 1
}
}

