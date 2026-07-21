[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ClassId,

    [Parameter(Mandatory = $true)]
    [datetime]$Deadline,

    [string]$Sample = 'D:\SteveTradingData\manifests\v1\databento-live-validation\20260720T152956568061Z-option-sample.json',
    [string]$LiveDbn = 'D:\SteveTradingData\raw\v1\databento-live-validation\GLBX.MDP3\2026-07-20\20260720T152956568061Z\live.dbn',
    [string]$Start = '2026-07-20T15:29:57Z',
    [string]$End = '2026-07-20T15:34:58Z',
    [decimal]$MaxTotalCostUsd = 1.00,
    [int64]$MaxTotalBillableBytes = 209715200,
    [switch]$TradesOnly,
    [switch]$AllTradeSymbols
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$basilisp = Join-Path $repo '.venv\Scripts\basilisp.exe'
$collector = Join-Path $repo 'scripts\databento_event_collection.lpy'
$comparator = Join-Path $repo 'scripts\databento_event_parity.lpy'
$rawRoot = 'D:\SteveTradingData\raw\v1\databento-historical-validation'
$manifestRoot = 'D:\SteveTradingData\manifests\v1\databento-historical-validation'
$manifestDir = Join-Path $manifestRoot "databento\GLBX.MDP3\probationary\$ClassId\trade_date=2026-07-20"
$parityOut = "D:\SteveTradingData\manifests\v1\databento-live-validation\$ClassId-parity.json"

if (-not (Test-Path -LiteralPath $basilisp)) { throw "Basilisp runtime not found: $basilisp" }
if (-not (Test-Path -LiteralPath $Sample)) { throw "Sample manifest not found: $Sample" }
if (-not (Test-Path -LiteralPath $LiveDbn)) { throw "Live DBN not found: $LiveDbn" }

$samplePayload = Get-Content -LiteralPath $Sample -Raw | ConvertFrom-Json
$rootProperties = @($samplePayload.roots.PSObject.Properties)
$symbols = @($rootProperties | ForEach-Object { @($_.Value.selected.symbol) })
$schemas = 'mbp-1,trades'
if ($AllTradeSymbols) {
    $symbols = @($samplePayload.trade_active_symbols.symbol | Where-Object { $_ } | Sort-Object -Unique)
    $schemas = 'trades'
}
elseif ($TradesOnly) {
    $symbols += @($rootProperties | ForEach-Object { @($_.Value.trade_symbols.symbol) })
    $symbols = @($symbols | Where-Object { $_ } | Sort-Object -Unique)
    $schemas = 'trades'
}
$symbolArg = $symbols -join ','

. "$HOME\.config\powershell\profile.ps1"
$env:DATABENTO_API_KEY = Get-DevSecret DATABENTO_API_KEY

try {
    $receiptFile = Get-ChildItem -LiteralPath $manifestDir -Filter 'run=*.json' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    while (-not $receiptFile) {
        Write-Output "[$((Get-Date).ToString('o'))] Historical availability attempt for $ClassId"
        & $basilisp run $collector `
            --dataset GLBX.MDP3 `
            --class-id $ClassId `
            --admission probationary `
            --symbols $symbolArg `
            --stype-in raw_symbol `
            --schemas $schemas `
            --start $Start `
            --end $End `
            --out-root $rawRoot `
            --manifest-root $manifestRoot `
            --max-total-cost-usd ([string]$MaxTotalCostUsd) `
            --max-total-billable-bytes $MaxTotalBillableBytes

        if ($LASTEXITCODE -eq 0) {
            $receiptFile = Get-ChildItem -LiteralPath $manifestDir -Filter 'run=*.json' -File |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 1
            break
        }

        if ((Get-Date).AddMinutes(5) -gt $Deadline) {
            throw "Historical data did not become available before $Deadline"
        }
        Start-Sleep -Seconds 300
    }

    $receipt = Get-Content -LiteralPath $receiptFile.FullName -Raw | ConvertFrom-Json
    $historicalTrades = Join-Path $receipt.raw_run_dir 'trades.dbn'
    $historicalMbp = if ($TradesOnly -or $AllTradeSymbols) { $historicalTrades } else { Join-Path $receipt.raw_run_dir 'mbp-1.dbn' }

    & $basilisp run $comparator `
        --live-dbn $LiveDbn `
        --historical-mbp-dbn $historicalMbp `
        --historical-trades-dbn $historicalTrades `
        --symbols $symbolArg `
        --schemas $schemas `
        --out $parityOut
    if ($LASTEXITCODE -ne 0) { throw "Parity comparator exited $LASTEXITCODE" }
}
finally {
    Remove-Item Env:\DATABENTO_API_KEY -ErrorAction SilentlyContinue
}
