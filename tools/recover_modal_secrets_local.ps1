param(
    [string]$NewProfile = "netlittle2"
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$projectParent = Split-Path -Parent $repoRoot
$secureDir = Join-Path $env:USERPROFILE "LittleNet-New-Modal-Secrets"
$generatedAiFile = Join-Path $secureDir "ai.env"

function Read-DotEnvFile {
    param([string]$Path)
    $map = @{}
    if (-not (Test-Path $Path -PathType Leaf)) { return $map }
    foreach ($raw in Get-Content -LiteralPath $Path -ErrorAction Stop) {
        $line = $raw.TrimStart([char]0xFEFF).Trim()
        if (-not $line -or $line.StartsWith('#') -or -not $line.Contains('=')) { continue }
        $parts = $line.Split('=', 2)
        $key = $parts[0].Trim()
        $value = $parts[1].Trim()
        if (-not $key) { continue }
        if ($value.Length -ge 2 -and $value.StartsWith('"') -and $value.EndsWith('"')) {
            try { $value = $value | ConvertFrom-Json } catch { $value = $value.Substring(1, $value.Length - 2) }
        } elseif ($value.Length -ge 2 -and $value.StartsWith("'") -and $value.EndsWith("'")) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        if ($value -ne '') { $map[$key] = [string]$value }
    }
    return $map
}

function Merge-Values {
    param([hashtable]$Target, [hashtable]$Source)
    foreach ($k in $Source.Keys) { $Target[$k] = $Source[$k] }
}

function Write-DotEnv {
    param([string]$Path, [hashtable]$Values, [string[]]$Keys)
    $lines = @()
    foreach ($key in $Keys) {
        if ($Values.ContainsKey($key) -and $Values[$key] -ne '') {
            $escaped = ($Values[$key] -replace '\\','\\\\' -replace '"','\"' -replace "`r",'\r' -replace "`n",'\n')
            $lines += "$key=`"$escaped`""
        }
    }
    [System.IO.File]::WriteAllLines($Path, $lines, [System.Text.UTF8Encoding]::new($false))
}

function Run-Modal {
    param([string[]]$ModalArgs)
    & modal @ModalArgs
    if ($LASTEXITCODE -ne 0) { throw "modal command failed: modal $($ModalArgs -join ' ')" }
}

Write-Host "LittleNet local secret recovery" -ForegroundColor Cyan
Write-Host "No secret values will be printed." -ForegroundColor Yellow

# Remove plaintext leftovers from failed cloud-export attempts. Those runs failed
# before any secret export completed, but cleaning them removes ambiguity.
Get-ChildItem $env:TEMP -Directory -Filter 'LittleNet-Modal-Secret-Migrate-*' -ErrorAction SilentlyContinue |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

New-Item -ItemType Directory -Force $secureDir | Out-Null

$candidates = @(
    (Join-Path $projectParent 'LittleNet-env-backup.txt'),
    (Join-Path $projectParent 'LittleNet-1-OLD\.env'),
    (Join-Path $repoRoot '.env'),
    (Join-Path $secureDir 'web.env'),
    (Join-Path $secureDir 'r2.env'),
    (Join-Path $secureDir 'email.env'),
    $generatedAiFile
)

$values = @{}
$used = @()
foreach ($candidate in $candidates) {
    if (Test-Path $candidate -PathType Leaf) {
        $parsed = Read-DotEnvFile $candidate
        if ($parsed.Count -gt 0) {
            Merge-Values $values $parsed
            $used += $candidate
        }
    }
}

# Keep the newly generated internal AI secret if ai.env exists. Generate internal
# keys locally when absent; no provider dashboard is needed for these.
if (Test-Path $generatedAiFile -PathType Leaf) {
    $aiLocal = Read-DotEnvFile $generatedAiFile
    if ($aiLocal.ContainsKey('AI_SHARED_SECRET')) { $values['AI_SHARED_SECRET'] = $aiLocal['AI_SHARED_SECRET'] }
}
if (-not $values.ContainsKey('AI_SHARED_SECRET')) {
    $values['AI_SHARED_SECRET'] = py -c "import secrets; print(secrets.token_urlsafe(48))"
}
if (-not $values.ContainsKey('SECRET_KEY')) {
    $values['SECRET_KEY'] = py -c "import secrets; print(secrets.token_urlsafe(48))"
}

# Safe defaults/non-secret placeholders. Endpoint values are intentionally
# replaced after the new Modal AI/web deployments produce their URLs.
$defaults = @{
    'COOKIE_SECURE' = '1'
    'APP_TIMEZONE' = 'Asia/Kolkata'
    'JOB_QUEUE_PROVIDER' = 'qstash'
    'QSTASH_URL' = 'https://qstash.upstash.io'
    'R2_SIGNED_URL_TTL' = '300'
    'AI_REQUEST_TIMEOUT' = '180'
}
foreach ($k in $defaults.Keys) {
    if (-not $values.ContainsKey($k)) { $values[$k] = $defaults[$k] }
}
if (-not $values.ContainsKey('AI_SERVICE_URL')) { $values['AI_SERVICE_URL'] = 'https://placeholder.invalid' }
if (-not $values.ContainsKey('BASE_URL')) { $values['BASE_URL'] = 'https://placeholder.invalid' }
if (-not $values.ContainsKey('QSTASH_MODAL_ENDPOINT')) { $values['QSTASH_MODAL_ENDPOINT'] = 'https://placeholder.invalid/ai/jobs/process-media' }

$requiredCore = @('DATABASE_URL','R2_ACCOUNT_ID','R2_ACCESS_KEY_ID','R2_SECRET_ACCESS_KEY','R2_BUCKET')
$missingCore = @($requiredCore | Where-Object { -not $values.ContainsKey($_) -or [string]::IsNullOrWhiteSpace($values[$_]) })

$qstashKeys = @('QSTASH_TOKEN','QSTASH_CURRENT_SIGNING_KEY','QSTASH_NEXT_SIGNING_KEY')
$missingQstash = @($qstashKeys | Where-Object { -not $values.ContainsKey($_) -or [string]::IsNullOrWhiteSpace($values[$_]) })

$mailReady = ($values.ContainsKey('RESEND_API_KEY') -and -not [string]::IsNullOrWhiteSpace($values['RESEND_API_KEY'])) -or
             (($values.ContainsKey('SMTP_USER') -and -not [string]::IsNullOrWhiteSpace($values['SMTP_USER'])) -and
              ($values.ContainsKey('SMTP_PASSWORD') -and -not [string]::IsNullOrWhiteSpace($values['SMTP_PASSWORD'])))

Write-Host "Recovered environment data from $($used.Count) local file(s)." -ForegroundColor Green
foreach ($p in $used) { Write-Host "  source: $p" }

if ($missingCore.Count -gt 0) {
    Write-Host "`nCannot complete migration yet. Missing provider keys:" -ForegroundColor Red
    foreach ($k in $missingCore) { Write-Host "  - $k" -ForegroundColor Red }
    if ($missingQstash.Count -gt 0) {
        Write-Host "Missing QStash keys:" -ForegroundColor Yellow
        foreach ($k in $missingQstash) { Write-Host "  - $k" -ForegroundColor Yellow }
    }
    if (-not $mailReady) { Write-Host "  - RESEND_API_KEY (or SMTP_USER + SMTP_PASSWORD)" -ForegroundColor Yellow }
    Write-Host "No secret values were printed. Give this missing-key list to AntiGravity and let it search your local machine/provider CLIs only." -ForegroundColor Yellow
    exit 2
}

$aiKeys = @('AI_SHARED_SECRET')
$webKeys = @(
    'DATABASE_URL','SECRET_KEY','BASE_URL','COOKIE_SECURE','AI_SERVICE_URL','AI_SHARED_SECRET','AI_REQUEST_TIMEOUT',
    'JOB_QUEUE_PROVIDER','QSTASH_TOKEN','QSTASH_CURRENT_SIGNING_KEY','QSTASH_NEXT_SIGNING_KEY','QSTASH_MODAL_ENDPOINT','QSTASH_URL',
    'APP_TIMEZONE','LITTLENET_SYNC_JOBS','TURNSTILE_SITE_KEY','TURNSTILE_SECRET_KEY','K2_HORIZON_ENABLED','K2_HORIZON_BASE_URL',
    'K2_HORIZON_API_KEY','K2_HORIZON_MODEL','K2_CONNECT_TIMEOUT','K2_READ_TIMEOUT','K2_MAX_RETRIES','K2_CIRCUIT_BREAKER_THRESHOLD',
    'K2_CIRCUIT_BREAKER_RESET_SECONDS','MAIL_EMAIL','MAIL_PASSWORD','SMTP_HOST','SMTP_PORT','SMTP_USER','SMTP_PASSWORD','SMTP_USE_TLS'
)
$r2Keys = @('R2_ACCOUNT_ID','R2_ACCESS_KEY_ID','R2_SECRET_ACCESS_KEY','R2_BUCKET','R2_SIGNED_URL_TTL')
$emailKeys = @('RESEND_API_KEY','RESEND_FROM_EMAIL','RESEND_FROM_NAME','RESEND_DOMAIN_VERIFIED','MAIL_EMAIL','MAIL_PASSWORD','SMTP_HOST','SMTP_PORT','SMTP_USER','SMTP_PASSWORD','SMTP_USE_TLS')

$aiOut = Join-Path $secureDir 'ai.env'
$webOut = Join-Path $secureDir 'web.env'
$r2Out = Join-Path $secureDir 'r2.env'
$emailOut = Join-Path $secureDir 'email.env'
Write-DotEnv $aiOut $values $aiKeys
Write-DotEnv $webOut $values $webKeys
Write-DotEnv $r2Out $values $r2Keys
Write-DotEnv $emailOut $values $emailKeys

Run-Modal @('profile','activate',$NewProfile)
if ((& modal profile current).Trim() -ne $NewProfile) { throw "Could not activate Modal profile $NewProfile" }

Write-Host "`nImporting recovered secrets into $NewProfile..." -ForegroundColor Cyan
Run-Modal @('secret','create','littlenet-ai-secrets','--from-dotenv',$aiOut,'--force')
Run-Modal @('secret','create','littlenet-web-secrets','--from-dotenv',$webOut,'--force')
Run-Modal @('secret','create','littlenet-r2','--from-dotenv',$r2Out,'--force')
if ($mailReady) {
    Run-Modal @('secret','create','littlenet-email','--from-dotenv',$emailOut,'--force')
} else {
    # Keep object existence predictable; mail can be added later without blocking AI deployment.
    'LITTLENET_MAIL_PENDING="1"' | Set-Content -LiteralPath $emailOut -Encoding utf8
    Run-Modal @('secret','create','littlenet-email','--from-dotenv',$emailOut,'--force')
}

Write-Host "`nRecovered/imported successfully." -ForegroundColor Green
if ($missingQstash.Count -gt 0) {
    Write-Host "QStash background jobs are NOT ready yet; missing key names:" -ForegroundColor Yellow
    foreach ($k in $missingQstash) { Write-Host "  - $k" -ForegroundColor Yellow }
}
if (-not $mailReady) { Write-Host "Email provider credential was not found locally; email remains pending." -ForegroundColor Yellow }
Write-Host "Endpoint placeholders will be replaced after the new Modal deployments." -ForegroundColor Yellow
Write-Host "`nModal secret objects:" -ForegroundColor Cyan
Run-Modal @('secret','list')
