[CmdletBinding()]
param(
    [string]$TradeDate = '2026-07-21',
    [datetime]$Deadline = [datetime]'2026-07-22T13:30:00-04:00'
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$runtime = 'C:\Users\vandy\AppData\Local\Temp\stevetrading-databento-parity-runtime\Scripts\python.exe'
$comparator = Join-Path $PSScriptRoot 'databento_multischema_parity.py'
$dateRoot = Join-Path 'D:\SteveTradingData\raw\v1\databento-live-validation\EQUS.MINI' $TradeDate
$logRoot = 'D:\SteveTradingData\manifests\v1\databento-live-validation\logs'

if (-not (Test-Path -LiteralPath $runtime)) { throw "Databento parity runtime not found: $runtime" }
if (-not (Test-Path -LiteralPath $comparator)) { throw "Comparator not found: $comparator" }
if (-not (Test-Path -LiteralPath $dateRoot)) { throw "No live-capture date directory: $dateRoot" }
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null

function Get-EligibleRuns {
    @(Get-ChildItem -LiteralPath $dateRoot -Directory | Where-Object {
        $receiptPath = Join-Path $_.FullName 'receipt.json'
        if (-not (Test-Path -LiteralPath $receiptPath)) { return $false }
        $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
        @($receipt.schemas) -contains 'tbbo'
    })
}

. "$HOME\.config\powershell\profile.ps1"
$env:DATABENTO_API_KEY = Get-DevSecret DATABENTO_API_KEY

try {
    $completed = @{}
    while ((Get-Date) -lt $Deadline) {
        $runs = Get-EligibleRuns
        if (-not $runs) { throw "No completed TBBO live receipts found below $dateRoot" }

        foreach ($run in $runs) {
            if ($completed[$run.FullName]) { continue }
            $stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffffffZ')
            $resultName = "final-$TradeDate-$stamp"
            $log = Join-Path $logRoot "$stamp-equity-schema-parity.log"
            & $runtime $comparator `
                --run-dir $run.FullName `
                --schemas trades tbbo mbp-1 `
                --representation market `
                --result-name $resultName `
                --max-total-cost-usd 1 `
                --max-total-billable-bytes 1073741824 2>&1 | Tee-Object -FilePath $log

            $summaryPath = Join-Path $run.FullName "summary-$resultName.json"
            if (Test-Path -LiteralPath $summaryPath) {
                $summary = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json
                if ($summary.status -ne 'INCONCLUSIVE') {
                    $completed[$run.FullName] = $true
                }
            }
        }

        if ($completed.Count -eq $runs.Count) { return }
        if ((Get-Date).AddMinutes(30) -gt $Deadline) { break }
        Start-Sleep -Seconds 1800
    }
    throw "Equity schema history remained inconclusive for one or more runs before $Deadline"
}
finally {
    Remove-Item Env:\DATABENTO_API_KEY -ErrorAction SilentlyContinue
}
