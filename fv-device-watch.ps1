<#
  Poll GitHub device flow and, on success:
    1. store the token for gh CLI (felixvec account)
    2. register the FelixVec SSH public key on the account
    3. create the FelixVec-notes repo
    4. push the local repo
  Run:  powershell -ExecutionPolicy Bypass -File fv-device-watch.ps1
#>
$ErrorActionPreference = "Continue"
$cid = "Iv1.b231c327f1eaa229"
$scope = "repo,read:org,gist,workflow"
$Repo = "D:\Desktop\FelixVec-Git"
$Remote = "git@github-felixvec:FelixVec/FelixVec-notes.git"
$KeyFile = "$env:USERPROFILE\.ssh\id_ed25519_felixvec"

function Log($m) { Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $m" }

# 1) request device code
$raw = Invoke-RestMethod -Uri "https://github.com/login/device/code" -Method Post `
    -ContentType "application/x-www-form-urlencoded" `
    -Body @{ client_id = $cid; scope = $scope } -TimeoutSec 30

$p = @{}
foreach ($kv in ($raw -split '&')) { $k,$v = $kv -split '=',2; $p[$k] = [System.Uri]::UnescapeDataString($v) }

$deviceCode = $p['device_code']
$userCode   = $p['user_code']
$interval   = [int]$p['interval']

Log "======================================================"
Log "  USER CODE : $userCode"
Log "  URL       : https://github.com/login/device"
Log "  (sign in as FelixVec, then enter the code)"
Log "======================================================"
Set-Content "$env:TEMP\fv_usercode.txt" $userCode -Encoding UTF8

# 2) poll for token
$token = $null
$deadline = (Get-Date).AddSeconds([int]$p['expires_in'])
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds $interval
    try {
        $r = Invoke-RestMethod -Uri "https://github.com/login/oauth/access_token" -Method Post `
            -ContentType "application/x-www-form-urlencoded" `
            -Body @{ client_id = $cid; device_code = $deviceCode; grant_type = "urn:ietf:params:oauth:grant-type:device_code" } `
            -TimeoutSec 30
    } catch {
        Log "poll error: $($_.Exception.Message.Split([Environment]::NewLine)[0])"
        continue
    }
    if ($r.access_token) { $token = $r.access_token; break }
    Log "waiting... ($($r.error))"
}

if (-not $token) { Log "TIMEOUT / not authorized"; exit 1 }
Log "authorized"

# 3) persist token for gh CLI
$hostsDir = "$env:APPDATA\GitHub CLI"
New-Item -ItemType Directory -Force $hostsDir | Out-Null
$hostsFile = "$hostsDir\hosts.yml"
$yaml = @"
github.com:
    user: felixvec
    git_protocol: ssh
    oauth_token: $token
"@
[System.IO.File]::WriteAllText($hostsFile, $yaml, (New-Object System.Text.UTF8Encoding($false)))
Log "token stored in $hostsFile"

# 4) register ssh key + create repo via API
$h = @{ Authorization = "Bearer $token"; Accept = "application/vnd.github+json"; "X-GitHub-Api-Version" = "2022-11-28"; "User-Agent" = "fv-device-watch" }
$me = Invoke-RestMethod -Uri "https://api.github.com/user" -Headers $h
Log "token owner: $($me.login)"

$pub = (Get-Content "$KeyFile.pub" -Raw).Trim()
$existing = Invoke-RestMethod -Uri "https://api.github.com/user/keys" -Headers $h
if ($existing | Where-Object { $_.key -eq ($pub -split ' ')[1] }) {
    Log "ssh key already registered"
} else {
    $null = Invoke-RestMethod -Uri "https://api.github.com/user/keys" -Method Post -Headers $h -Body @{ title = "FelixVec-workstation"; key = $pub }
    Log "ssh key registered"
}

try {
    $null = Invoke-RestMethod -Uri "https://api.github.com/user/repos" -Method Post -Headers $h -Body @{
        name = "FelixVec-notes"
        description = "Reverse engineering & vulnerability research notes"
        private = $false; auto_init = $false; has_issues = $true; has_wiki = $false
    }
    Log "repo created: felixvec/FelixVec-notes"
} catch {
    if ($_.Exception.Response.StatusCode -eq 422) { Log "repo already exists" } else { Log "repo create failed: $($_.Exception.Message)" }
}

# 5) push
Push-Location $Repo
git remote remove origin 2>$null
git remote add origin $Remote
git push -u origin main 2>&1 | ForEach-Object { "   $_" }
Pop-Location

# 6) verify ssh
$out = & ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 github-felixvec -T git@github.com 2>&1 | Out-String
Log "ssh verify: $($out.Trim())"
Log "DONE"
