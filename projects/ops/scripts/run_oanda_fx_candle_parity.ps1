param(
    [ValidateSet('practice', 'live')]
    [string]$Environment = 'live',
    [int]$DurationSeconds = 1800,
    [double]$PollSeconds = 2,
    [int]$SettleSeconds = 15
)

$ErrorActionPreference = 'Stop'

Import-Module Microsoft.PowerShell.SecretManagement -ErrorAction Stop
Import-Module Microsoft.PowerShell.SecretStore -ErrorAction Stop
. "$HOME\.config\powershell\profile.ps1"
Unlock-DevSecrets
$secretName = if ($Environment -eq 'live') { 'OANDA_LIVE_KEY' } else { 'OANDA_DEMO_KEY' }
$env:OANDA_API_KEY = Get-Secret $secretName -Vault DevSecrets -AsPlainText

try {
    $opsRoot = Split-Path -Parent $PSScriptRoot
    $script = Join-Path $PSScriptRoot 'oanda_fx_candle_parity.py'
    $outRoot = Join-Path $opsRoot 'evidence\oanda-fx-candle-parity'
    & python $script --out-root $outRoot --environment $Environment --duration-seconds $DurationSeconds --poll-seconds $PollSeconds --settle-seconds $SettleSeconds
    exit $LASTEXITCODE
}
finally {
    Remove-Item Env:OANDA_API_KEY -ErrorAction SilentlyContinue
}
