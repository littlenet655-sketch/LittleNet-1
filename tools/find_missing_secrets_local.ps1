param(
    [string]$OutputDir = "$env:USERPROFILE\LittleNet-New-Modal-Secrets"
)

$ErrorActionPreference = "Stop"

$Wanted = @(
    "R2_ACCOUNT_ID",
    "R2_ACCESS_KEY_ID",
    "R2_SECRET_ACCESS_KEY",
    "R2_BUCKET",
    "QSTASH_TOKEN",
    "QSTASH_CURRENT_SIGNING_KEY",
    "QSTASH_NEXT_SIGNING_KEY",
    "RESEND_API_KEY",
    "SMTP_USER",
    "SMTP_PASSWORD"
)

$Found = @{}
$Sources = @{}

function Add-FoundValue {
    param(
        [string]$Key,
        [string]$Value,
        [string]$Source
    )
    if (-not $Key -or -not $Value) { return }
    if ($Wanted -notcontains $Key) { return }
    if ($Found.ContainsKey($Key)) { return }
    $trimmed = $Value.Trim().Trim('"').Trim("'")
    if ([string]::IsNullOrWhiteSpace($trimmed)) { return }
    if ($trimmed -match '^(PASTE_|replace-|changeme|your_|<|\$\{|\*\*\*)') { return }
    $Found[$Key] = $trimmed
    $Sources[$Key] = $Source
}

Write-Host "LittleNet targeted local secret search" -ForegroundColor Cyan
Write-Host "Secret VALUES will NOT be printed." -ForegroundColor Yellow

# 1) Process/User/Machine environment variables
foreach ($key in $Wanted) {
    foreach ($scope in @('Process','User','Machine')) {
        try {
            $val = [Environment]::GetEnvironmentVariable($key, $scope)
            if ($val) { Add-FoundValue $key $val "environment:$scope" }
        } catch {}
    }
}

# 2) Common LittleNet/project/config locations. Keep this bounded to avoid crawling the whole drive.
$roots = @(
    "D:\aitprojects",
    "$env:USERPROFILE\Documents",
    "$env:USERPROFILE\Desktop",
    "$env:USERPROFILE\Downloads",
    "$env:USERPROFILE\.config",
    "$env:USERPROFILE\.cloudflared",
    "$env:USERPROFILE\.wrangler",
    "$env:USERPROFILE\AppData\Roaming",
    "$env:USERPROFILE\AppData\Local"
) | Where-Object { Test-Path $_ }

$includeNames = @(
    '.env','.env.local','.env.production','.env.development','.env.backup',
    'wrangler.toml','wrangler.json','wrangler.jsonc','config.toml','config.json',
    'settings.json','secrets.env','recovered.env','web.env','r2.env','email.env',
    'PowerShell_history.txt','ConsoleHost_history.txt'
)

$extensions = @('.env','.txt','.json','.jsonc','.toml','.yaml','.yml','.ini','.cfg','.conf','.ps1','.cmd','.bat')
$skipParts = @('node_modules','.git','dist','build','.expo','.gradle','venv','.venv','__pycache__','Temp','Cache','Code Cache','GPUCache')

function Should-SkipPath([string]$path) {
    foreach ($part in $skipParts) {
        if ($path -match [regex]::Escape("\$part\") -or $path -match [regex]::Escape("/$part/")) { return $true }
    }
    return $false
}

$files = New-Object System.Collections.Generic.List[string]
foreach ($root in $roots) {
    try {
        Get-ChildItem -LiteralPath $root -File -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object {
                -not (Should-SkipPath $_.FullName) -and
                ($includeNames -contains $_.Name -or $extensions -contains $_.Extension.ToLowerInvariant()) -and
                $_.Length -lt 5MB
            } |
            Select-Object -First 20000 |
            ForEach-Object { $files.Add($_.FullName) }
    } catch {}
}

$patterns = @{}
foreach ($key in $Wanted) {
    # Supports KEY=value, KEY: value, "KEY": "value", set KEY=value, $env:KEY="value"
    $patterns[$key] = @(
        "(?im)^\s*" + [regex]::Escape($key) + "\s*=\s*(.+?)\s*$",
        "(?im)^\s*[\"']?" + [regex]::Escape($key) + "[\"']?\s*:\s*[\"']?([^\"'\r\n,}]+)",
        "(?im)^\s*set\s+" + [regex]::Escape($key) + "\s*=\s*(.+?)\s*$",
        "(?im)\$env:" + [regex]::Escape($key) + "\s*=\s*[\"']([^\"']+)"
    )
}

foreach ($file in ($files | Select-Object -Unique)) {
    if ($Found.Count -eq $Wanted.Count) { break }
    try {
        $text = [IO.File]::ReadAllText($file)
    } catch { continue }

    foreach ($key in $Wanted) {
        if ($Found.ContainsKey($key)) { continue }
        foreach ($pattern in $patterns[$key]) {
            $m = [regex]::Match($text, $pattern)
            if ($m.Success) {
                Add-FoundValue $key $m.Groups[1].Value $file
                break
            }
        }
    }
}

# 3) PowerShell PSReadLine history locations explicitly
$historyCandidates = @(
    "$env:APPDATA\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt",
    "$env:APPDATA\Microsoft\PowerShell\PSReadLine\ConsoleHost_history.txt"
)
foreach ($file in $historyCandidates) {
    if (-not (Test-Path $file)) { continue }
    try { $text = [IO.File]::ReadAllText($file) } catch { continue }
    foreach ($key in $Wanted) {
        if ($Found.ContainsKey($key)) { continue }
        foreach ($pattern in $patterns[$key]) {
            $m = [regex]::Match($text, $pattern)
            if ($m.Success) {
                Add-FoundValue $key $m.Groups[1].Value $file
                break
            }
        }
    }
}

New-Item -ItemType Directory -Force $OutputDir | Out-Null
$outFile = Join-Path $OutputDir 'recovered.env'
$lines = @()
foreach ($key in $Wanted) {
    if ($Found.ContainsKey($key)) {
        $escaped = $Found[$key].Replace('`','``').Replace('"','\"')
        $lines += "$key=\"$escaped\""
    }
}
Set-Content -LiteralPath $outFile -Value $lines -Encoding UTF8

Write-Host "`nRecovered key names:" -ForegroundColor Green
if ($Found.Count -eq 0) {
    Write-Host "  (none)"
} else {
    foreach ($key in $Wanted) {
        if ($Found.ContainsKey($key)) {
            Write-Host "  + $key" -ForegroundColor Green
            Write-Host "    source: $($Sources[$key])" -ForegroundColor DarkGray
        }
    }
}

$missing = @($Wanted | Where-Object { -not $Found.ContainsKey($_) })
Write-Host "`nStill missing key names:" -ForegroundColor Yellow
if ($missing.Count -eq 0) {
    Write-Host "  (none)" -ForegroundColor Green
} else {
    foreach ($key in $missing) { Write-Host "  - $key" -ForegroundColor Yellow }
}

Write-Host "`nRecovered values were written to:" -ForegroundColor Cyan
Write-Host "  $outFile" -ForegroundColor Cyan
Write-Host "Do not upload, commit, or paste that file." -ForegroundColor Yellow

# Success if all R2 + QStash keys exist and either Resend or SMTP fallback is usable.
$requiredCore = @(
    'R2_ACCOUNT_ID','R2_ACCESS_KEY_ID','R2_SECRET_ACCESS_KEY','R2_BUCKET',
    'QSTASH_TOKEN','QSTASH_CURRENT_SIGNING_KEY','QSTASH_NEXT_SIGNING_KEY'
)
$coreMissing = @($requiredCore | Where-Object { -not $Found.ContainsKey($_) })
$mailOk = $Found.ContainsKey('RESEND_API_KEY') -or ($Found.ContainsKey('SMTP_USER') -and $Found.ContainsKey('SMTP_PASSWORD'))
if ($coreMissing.Count -eq 0 -and $mailOk) {
    Write-Host "`nSEARCH_READY=True" -ForegroundColor Green
    exit 0
}
Write-Host "`nSEARCH_READY=False" -ForegroundColor Yellow
exit 2
