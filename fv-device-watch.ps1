<#
  fv-device-watch.ps1 -- GitHub device flow -> auto-provision FelixVec channel

  Run:  powershell -ExecutionPolicy Bypass -File fv-device-watch.ps1

  Notes
  -----
  * GitHub returns the device-token response as application/x-www-form-urlencoded,
    so it must be parsed manually (Invoke-RestMethod will not decode it).
  * GitHub throttles polling: answering "slow_down" means the poll interval must
    grow by 5 seconds. The loop below honours that instead of hammering the API.
  * A successful exchange may also surface as a dropped connection; the code
    retries and re-reads the token when that happens.
#>
$ErrorActionPreference = "Continue"
$cid = "Iv1.b231c327f1eaa229"
$scope = "repo,read:org,gist,workflow"
$Repo = "D:\Desktop\FelixVec-Git"
$Remote = "git@github-felixvec:FelixVec/FelixVec-notes.git"
$KeyFile = "$env:USERPROFILE\.ssh\id_ed25519_felixvec"
$StateFile = "$env:TEMP\fv_device_state.json"

function Log($m) { Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $m" }

function ConvertFrom-UrlEncoded([string]$text) {
    $h = @{}
    foreach ($pair in ($text -split '&')) {
        if (-not $pair) { continue }
        $kv = $pair -split '=', 2
        $k = [System.Uri]::UnescapeDataString($kv[0])
        $v = if ($kv.Count -gt 1) { [System.Uri]::UnescapeDataString($kv[1]) } else { "" }
        $h[$k] = $v
    }
    return $h
}

function Get-DeviceToken([string]$deviceCode) {
    $body = "client_id=$cid&device_code=$deviceCode&grant_type=urn:ietf:params:oauth:grant-type:device_code"
    try {
        $resp = Invoke-WebRequest -Uri "https://github.com/login/oauth/access_token" -Method Post `
            -ContentType "application/x-www-form-urlencoded" -Body $body -TimeoutSec 25 -UseBasicParsing
        $raw = $resp.Content
        if ($raw -is [byte[]]) { $raw = [System.Text.Encoding]::UTF8.GetString($raw) }
        return ConvertFrom-UrlEncoded $raw
    } catch {
        # A dropped connection can also mean the exchange just succeeded
        return @{ __error = $_.Exception.Message.Split([Environment]::NewLine)[0] }
    }
}

# ---------- 1) request device code ----------
$raw = Invoke-WebRequest -Uri "https://github.com/login/device/code" -Method Post `
    -ContentType "application/x-www-form-urlencoded" `
    -Body "client_id=$cid&scope=$scope" -TimeoutSec 30 -UseBasicParsing
$rawText = $raw.Content
if ($rawText -is [byte[]]) { $rawText = [System.Text.Encoding]::UTF8.GetString($rawText) }
$p = ConvertFrom-UrlEncoded $rawText

$deviceCode = $p['device_code']
$userCode   = $p['user_code']
$interval   = [int]$p['interval']
$expiresIn  = [int]$p['expires_in']

@{ device_code=$deviceCode; user_code=$userCode; interval=$interval; expires_in=$expiresIn } |
    ConvertTo-Json | Set-Content $StateFile -Encoding UTF8

Log "======================================================"
Log "  USER CODE : $userCode"
Log "  URL       : https://github.com/login/device"
Log "  expires   : $expiresIn s"
Log "======================================================"

# ---------- 2) poll for token (honour slow_down) ----------
$token = $null
$deadline = (Get-Date).AddSeconds($expiresIn)
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds $interval
    $r = Get-DeviceToken $deviceCode

    if ($r.ContainsKey('access_token') -and $r['access_token']) {
        $token = $r['access_token']
        break
    }
    if ($r['error'] -eq 'slow_down') {
        $interval += 5
        Log "slow_down -> poll interval now ${interval}s"
        continue
    }
    if ($r['error'] -eq 'expired_token') { Log "device code expired"; break }
    if ($r.ContainsKey('__error')) { Log "poll error: $($r['__error'])"; continue }
    Log "waiting... ($($r['error']))"
}

if (-not $token) { Log "TIMEOUT / not authorized"; exit 1 }
Log "AUTHORIZED"

# ---------- 3) persist token for gh CLI ----------
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
Log "token stored"

# ---------- 4) register ssh key + create repo ----------
$h = @{ Authorization = "Bearer $token"; Accept = "application/vnd.github+json"; "X-GitHub-Api-Version" = "2022-11-28"; "User-Agent" = "fv-device-watch" }
$me = Invoke-RestMethod -Uri "https://api.github.com/user" -Headers $h
Log "token owner: $($me.login)"
if ($me.login -ne "felixvec") { Log "WARNING: expected felixvec, got $($me.login)" }

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
    if ($_.Exception.Response.StatusCode -eq 422) { Log "repo already exists" }
    else { Log "repo create failed: $($_.Exception.Message)" }
}

# ---------- 5) push ----------
Push-Location $Repo
git remote remove origin 2>$null
git remote add origin $Remote
git push -u origin main 2>&1 | ForEach-Object { "   $_" }
Pop-Location

# ---------- 6) verify ssh ----------
$out = & ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 github-felixvec -T git@github.com 2>&1 | Out-String
Log "ssh verify: $($out.Trim())"
Log "DONE"
