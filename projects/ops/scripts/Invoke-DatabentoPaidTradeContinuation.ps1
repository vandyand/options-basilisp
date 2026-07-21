[CmdletBinding()]
param(
    [decimal]$GlobalBudgetUsd = 9.50,
    [datetime]$CutoffEt = [datetime]'2026-07-21T08:00:00-04:00'
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$basilisp = Join-Path $repo '.venv\Scripts\basilisp.exe'
$runner = Join-Path $repo 'scripts\databento_paid_trade_continuation.lpy'
. "$HOME\.config\powershell\profile.ps1"
$env:DATABENTO_API_KEY = Get-DevSecret DATABENTO_API_KEY

try {
    & $basilisp run $runner -- `
        --cutoff-et $CutoffEt.ToString('o') `
        --global-budget-usd ([string]$GlobalBudgetUsd) `
        --basilisp-exe $basilisp `
        --collector (Join-Path $repo 'scripts\databento_event_collection.lpy')
    if ($LASTEXITCODE -ne 0) { throw "Paid trade continuation exited $LASTEXITCODE" }
}
finally {
    Remove-Item Env:\DATABENTO_API_KEY -ErrorAction SilentlyContinue
}
