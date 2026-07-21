[CmdletBinding()]
param(
    [datetime]$Deadline = [datetime]'2026-07-21T11:30:00-04:00'
)

$ErrorActionPreference = 'Stop'
$manifestRoot = 'D:\SteveTradingData\manifests\v1\databento-live-validation'
$retry = Join-Path $PSScriptRoot 'Invoke-DatabentoOptionParityRetry.ps1'
$rawRoot = 'D:\SteveTradingData\raw\v1\databento-live-validation\GLBX.MDP3\2026-07-20'
$equsRetry = Join-Path $PSScriptRoot 'Invoke-DatabentoEqusParityRetry.ps1'

function Get-LiveReceipt([string]$liveDbn) {
    $receiptPath = Join-Path (Split-Path -Parent $liveDbn) 'receipt.json'
    if (-not (Test-Path -LiteralPath $receiptPath)) {
        throw "Live receipt not found: $receiptPath"
    }
    Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
}

function ConvertTo-IsoTimestamp($value) {
    if ($value -is [datetime]) {
        return $value.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ')
    }
    return [string]$value
}

function Invoke-OneFinalComparison {
    param(
        [Parameter(Mandatory)] [ValidateSet('options','futures')] [string]$Kind,
        [Parameter(Mandatory)] [System.IO.FileInfo]$Sample,
        [switch]$TradesOnly
    )

    $payload = Get-Content -LiteralPath $Sample.FullName -Raw | ConvertFrom-Json
    $liveDbn = [string]$payload.live_dbn
    if (-not (Test-Path -LiteralPath $liveDbn)) {
        throw "Live DBN not found for $($Sample.Name): $liveDbn"
    }
    $receipt = Get-LiveReceipt $liveDbn
    $runId = Split-Path -Leaf (Split-Path -Parent $liveDbn)
    $comparisonKind = if ($TradesOnly) { "$Kind-trades" } else { $Kind }
    $classId = "glbx-$comparisonKind-monday-20260720-$runId-final"
    $arguments = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $retry,
        '-ClassId', $classId,
        '-Deadline', $Deadline.ToString('o'),
        '-Sample', $Sample.FullName,
        '-LiveDbn', $liveDbn,
        '-Start', (ConvertTo-IsoTimestamp $receipt.subscribed_at),
        '-End', (ConvertTo-IsoTimestamp $receipt.ended_at)
    )
    if ($Kind -eq 'futures') {
        $arguments += @('-MaxTotalBillableBytes', '5242880', '-AllTradeSymbols')
    }
    elseif ($TradesOnly) {
        $arguments += @('-MaxTotalBillableBytes', '52428800', '-TradesOnly')
    }
    else {
        $arguments += @('-MaxTotalBillableBytes', '209715200')
    }

    Write-Output "[$((Get-Date).ToString('o'))] Final $Kind comparison for $runId"
    & pwsh @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Final $Kind comparison failed for $runId with exit $LASTEXITCODE"
    }
}

$optionSamples = @(Get-ChildItem -LiteralPath $manifestRoot -File -Filter '*-option-sample.json' |
    Where-Object { $_.LastWriteTime.Date -eq [datetime]'2026-07-20' } |
    Sort-Object Name)
$optionTradeSamples = @(Get-ChildItem -LiteralPath $manifestRoot -File -Filter '*-option-trades-sample.json' |
    Where-Object { $_.LastWriteTime.Date -eq [datetime]'2026-07-20' } |
    Sort-Object Name)
$futuresSamples = @(Get-ChildItem -LiteralPath $manifestRoot -File -Filter '*-futures-trade-symbols.json' |
    Where-Object { $_.LastWriteTime.Date -eq [datetime]'2026-07-20' } |
    Sort-Object Name)

if ($optionSamples.Count -lt 4) {
    throw "Expected at least four Monday option samples, found $($optionSamples.Count)"
}
if ($futuresSamples.Count -lt 4) {
    throw "Expected at least four Monday futures samples, found $($futuresSamples.Count)"
}

foreach ($sample in $optionSamples) {
    Invoke-OneFinalComparison -Kind options -Sample $sample
}
foreach ($sample in $optionTradeSamples) {
    Invoke-OneFinalComparison -Kind options -Sample $sample -TradesOnly
}
foreach ($sample in $futuresSamples) {
    Invoke-OneFinalComparison -Kind futures -Sample $sample
}

$equsReceipt = Get-ChildItem -LiteralPath 'D:\SteveTradingData\raw\v1\databento-live-validation\EQUS.MINI\2026-07-20' `
    -Recurse -File -Filter receipt.json -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
if ($equsReceipt) {
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $equsRetry `
        -RunDir $equsReceipt.DirectoryName `
        -Deadline $Deadline.ToString('o')
    if ($LASTEXITCODE -ne 0) { throw "EQUS final parity retry exited $LASTEXITCODE" }
}
else {
    Write-Warning 'No completed Monday EQUS live capture was found; skipping EQUS comparison.'
}
