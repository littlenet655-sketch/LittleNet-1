param(
    [string]$Profile = "netlittle2",
    [string]$AiUrl = "https://netlittle2--littlenet-ai-ai-web.modal.run",
    [string]$WebUrl = "https://netlittle2--littlenet-web-web.modal.run"
)

$ErrorActionPreference = "Stop"
$secureDir = Join-Path $env:USERPROFILE "LittleNet-New-Modal-Secrets"
$webFile = Join-Path $secureDir "web.env"

function Read-EnvMap([string]$Path) {
    $map = [ordered]@{}
    if (-not (Test-Path $Path -PathType Leaf)) { throw "Missing local secret file: $Path" }
    foreach ($raw in Get-Content -LiteralPath $Path) {
        $line = $raw.TrimStart([char]0xFEFF).Trim()
        if (-not $line -or $line.StartsWith('#') -or -not $line.Contains('=')) { continue }
        $parts = $line.Split('=',2)
        $key = $parts[0].Trim()
        $value = $parts[1].Trim()
        if ($key) { $map[$key] = $value }
    }
    return $map
}

function Quote-Env([string]$Value) {
    $escaped = $Value.Replace('\','\\').Replace('"','\"')
    return '"' + $escaped + '"'
}

Write-Host "Configuring LittleNet new Modal endpoints" -ForegroundColor Cyan
& modal profile activate $Profile | Out-Null
if ((& modal profile current).Trim() -ne $Profile) { throw "Could not activate Modal profile $Profile" }

$map = Read-EnvMap $webFile
$map['AI_SERVICE_URL'] = Quote-Env $AiUrl
$map['BASE_URL'] = Quote-Env $WebUrl
$map['JOB_QUEUE_PROVIDER'] = Quote-Env 'modal'

# QStash is no longer part of the production path. Remove its credentials and
# old endpoint from the replacement secret while retaining harmless QSTASH_URL
# only if it already exists for backward compatibility.
foreach ($key in @('QSTASH_TOKEN','QSTASH_CURRENT_SIGNING_KEY','QSTASH_NEXT_SIGNING_KEY','QSTASH_MODAL_ENDPOINT')) {
    if ($map.Contains($key)) { $map.Remove($key) }
}

$lines = @()
foreach ($key in $map.Keys) { $lines += "$key=$($map[$key])" }
[IO.File]::WriteAllLines($webFile, $lines, [Text.UTF8Encoding]::new($false))

& modal secret create littlenet-web-secrets --from-dotenv $webFile --force
if ($LASTEXITCODE -ne 0) { throw "Failed to update littlenet-web-secrets" }

Write-Host "Updated littlenet-web-secrets without printing secret values." -ForegroundColor Green
Write-Host "AI_SERVICE_URL: $AiUrl"
Write-Host "BASE_URL:       $WebUrl"
Write-Host "Queue:          modal (QStash credentials no longer required)" -ForegroundColor Green
