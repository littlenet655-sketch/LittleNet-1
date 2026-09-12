param(
    [string]$OldProfile = "littlenet655",
    [string]$NewProfile = "netlittle2"
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$tempDir = Join-Path $env:TEMP "LittleNet-Modal-Secret-Migrate-$stamp"
$exportScript = Join-Path $repoRoot "tools\modal_secret_export.py"
$success = $false

function Run-Modal {
    param([Parameter(Mandatory=$true)][string[]]$ModalArgs)
    & modal @ModalArgs
    if ($LASTEXITCODE -ne 0) {
        throw "modal command failed: modal $($ModalArgs -join ' ')"
    }
}

try {
    Write-Host "LittleNet Modal secret migration" -ForegroundColor Cyan
    Write-Host "Old profile: $OldProfile"
    Write-Host "New profile: $NewProfile"
    Write-Host "Secret values will NOT be printed." -ForegroundColor Yellow

    if (-not (Test-Path $exportScript)) {
        throw "Missing helper: $exportScript"
    }

    New-Item -ItemType Directory -Force $tempDir | Out-Null

    Write-Host "`n[1/4] Activating old Modal profile..." -ForegroundColor Cyan
    Run-Modal -ModalArgs @("profile", "activate", $OldProfile)
    $currentOld = (& modal profile current).Trim()
    if ($currentOld -ne $OldProfile) {
        throw "Expected old profile '$OldProfile', got '$currentOld'"
    }

    Write-Host "[2/4] Exporting four LittleNet secrets to a temporary local directory..." -ForegroundColor Cyan
    Run-Modal -ModalArgs @("run", $exportScript, "--output-dir", $tempDir)

    $files = @{
        "littlenet-ai-secrets"  = Join-Path $tempDir "littlenet-ai-secrets.env"
        "littlenet-web-secrets" = Join-Path $tempDir "littlenet-web-secrets.env"
        "littlenet-r2"          = Join-Path $tempDir "littlenet-r2.env"
        "littlenet-email"       = Join-Path $tempDir "littlenet-email.env"
    }
    foreach ($pair in $files.GetEnumerator()) {
        if (-not (Test-Path $pair.Value)) {
            throw "Expected export file was not created: $($pair.Value)"
        }
        if ((Get-Item $pair.Value).Length -le 0) {
            throw "Export file is empty: $($pair.Value)"
        }
    }

    Write-Host "[3/4] Activating new Modal profile and importing secrets..." -ForegroundColor Cyan
    Run-Modal -ModalArgs @("profile", "activate", $NewProfile)
    $currentNew = (& modal profile current).Trim()
    if ($currentNew -ne $NewProfile) {
        throw "Expected new profile '$NewProfile', got '$currentNew'"
    }

    foreach ($name in @("littlenet-ai-secrets", "littlenet-web-secrets", "littlenet-r2", "littlenet-email")) {
        Write-Host "  importing $name"
        Run-Modal -ModalArgs @("secret", "create", $name, "--from-dotenv", $files[$name], "--force")
    }

    Write-Host "[4/4] Verifying secret objects in the new workspace..." -ForegroundColor Cyan
    Run-Modal -ModalArgs @("secret", "list")

    $success = $true
    Write-Host "`nMigration completed. Active profile: $NewProfile" -ForegroundColor Green
    Write-Host "Old apps/secrets were NOT deleted or modified." -ForegroundColor Green
    Write-Host "Endpoint URL values are copied as-is for now; we will update them after the new AI/web deployments." -ForegroundColor Yellow
}
finally {
    if ($success -and (Test-Path $tempDir)) {
        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "Temporary plaintext secret files deleted." -ForegroundColor Green
    }
    elseif (Test-Path $tempDir) {
        Write-Host "Migration did not finish. Temporary files remain at:" -ForegroundColor Yellow
        Write-Host $tempDir -ForegroundColor Yellow
        Write-Host "Do not upload or commit that directory." -ForegroundColor Yellow
    }

    try { & modal profile activate $NewProfile | Out-Null } catch {}
}
