[CmdletBinding()]
param([int]$DurationSeconds = 300)

$ErrorActionPreference = 'Stop'
. "$HOME\.config\powershell\profile.ps1"
$env:DATABENTO_API_KEY = Get-DevSecret DATABENTO_API_KEY

$runtime = 'C:\Users\vandy\AppData\Local\Temp\stevetrading-databento-parity-runtime\Scripts\python.exe'
$capture = Join-Path $PSScriptRoot 'databento_live_multischema_capture.py'
$repo = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$outRoot = 'D:\SteveTradingData\raw\v1\databento-live-validation'
$logRoot = 'D:\SteveTradingData\manifests\v1\databento-live-validation\logs'
$stamp = Get-Date -Format 'yyyyMMddTHHmmss'
$stdout = Join-Path $logRoot "monday-equs-$stamp.stdout.log"
$stderr = Join-Path $logRoot "monday-equs-$stamp.stderr.log"
$symbols = 'SPY,QQQ,IWM,AAPL,MSFT,NVDA,AMD,TSLA,AMZN,META,GOOGL,NFLX,AVGO,PLTR,XLF'

try {
    New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
    $arguments = @(
        $capture, '--out-root', $outRoot, '--dataset', 'EQUS.MINI',
        '--symbols', $symbols, '--stype-in', 'raw_symbol',
        '--schemas', 'definition,mbp-1,trades,ohlcv-1s',
        '--duration-seconds', [string]$DurationSeconds
    )
    $process = Start-Process -FilePath $runtime -ArgumentList $arguments `
        -WorkingDirectory $repo -WindowStyle Hidden `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) { throw "EQUS capture exited $($process.ExitCode); stderr=$stderr" }
}
finally {
    Remove-Item Env:\DATABENTO_API_KEY -ErrorAction SilentlyContinue
}
