[CmdletBinding()]
param(
    [double]$DurationSeconds = 600,
    [string]$Symbols = 'AAPL,AMZN,AVGO,GME,GOOG,HYG,LLY,META,MSFT,NFLX,NVDA,ORCL,QQQ,SPY,SQQQ,TLT,TQQQ,TSLA,TSM,VXX'
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$runtime = Join-Path $repo '.venv\Scripts\basilisp.exe'
$capture = Join-Path $repo 'scripts\databento_live_multischema_capture.lpy'
$outRoot = 'D:\SteveTradingData\raw\v1\databento-live-validation'
$logRoot = 'D:\SteveTradingData\manifests\v1\databento-live-validation\logs'

if (-not (Test-Path -LiteralPath $runtime)) { throw "Databento parity runtime not found: $runtime" }
if (-not (Test-Path -LiteralPath $capture)) { throw "Live capture utility not found: $capture" }
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
$stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffffffZ')
$log = Join-Path $logRoot "$stamp-equity-trades-tbbo-mbp1.log"

. "$HOME\.config\powershell\profile.ps1"
$env:DATABENTO_API_KEY = Get-DevSecret DATABENTO_API_KEY

try {
    Push-Location $repo
    try {
        & $runtime run $capture `
            --out-root $outRoot `
            --dataset EQUS.MINI `
            --symbols $Symbols `
            --stype-in raw_symbol `
            --schemas definition,trades,tbbo,mbp-1 `
            --duration-seconds $DurationSeconds 2>&1 | Tee-Object -FilePath $log
        if ($LASTEXITCODE -ne 0) { throw "Databento equity schema capture exited $LASTEXITCODE" }
    }
    finally {
        Pop-Location
    }
}
finally {
    Remove-Item Env:\DATABENTO_API_KEY -ErrorAction SilentlyContinue
}
