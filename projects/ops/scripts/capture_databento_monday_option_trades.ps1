[CmdletBinding()]
param(
    [int]$DurationSeconds = 2700,
    [string]$Roots = 'ES,NQ,RTY,ZN,ZB,SR3'
)

$ErrorActionPreference = 'Stop'
. "$HOME\.config\powershell\profile.ps1"
$env:DATABENTO_API_KEY = Get-DevSecret DATABENTO_API_KEY

$runtime = 'C:\Users\vandy\AppData\Local\Temp\stevetrading-databento-parity-runtime\Scripts\python.exe'
$capture = Join-Path $PSScriptRoot 'databento_live_multischema_capture.py'
$repo = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$basilisp = Join-Path $repo '.venv\Scripts\basilisp.exe'
$sampler = Join-Path $repo 'scripts\databento_option_parity_sample.lpy'
$outRoot = 'D:\SteveTradingData\raw\v1\databento-live-validation'
$manifestRoot = 'D:\SteveTradingData\manifests\v1\databento-live-validation'
$logRoot = Join-Path $manifestRoot 'logs'
$stamp = Get-Date -Format 'yyyyMMddTHHmmss'
$stdout = Join-Path $logRoot "monday-option-trades-$stamp.stdout.log"
$stderr = Join-Path $logRoot "monday-option-trades-$stamp.stderr.log"
$parents = (($Roots -split ',') | ForEach-Object { "$_.OPT" }) -join ','

try {
    if (-not (Test-Path -LiteralPath $runtime)) { throw "Databento runtime not found: $runtime" }
    if ((Get-Volume -DriveLetter D).HealthStatus -ne 'Healthy') { throw 'D: corpus volume is not healthy' }
    New-Item -ItemType Directory -Force -Path $logRoot | Out-Null

    $arguments = @(
        $capture,
        '--out-root', $outRoot,
        '--dataset', 'GLBX.MDP3',
        '--symbols', $parents,
        '--stype-in', 'parent',
        '--schemas', 'definition,trades',
        '--duration-seconds', [string]$DurationSeconds
    )
    $process = Start-Process -FilePath $runtime -ArgumentList $arguments `
        -WorkingDirectory $repo -WindowStyle Hidden `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) { throw "Option trades capture exited $($process.ExitCode); stderr=$stderr" }

    $receipt = Get-Content -LiteralPath $stdout -Raw | ConvertFrom-Json
    $liveDbn = Join-Path $receipt.run_dir 'live.dbn'
    $runId = Split-Path -Leaf $receipt.run_dir
    $sample = Join-Path $manifestRoot "$runId-option-trades-sample.json"

    & $basilisp run $sampler `
        --live-dbn $liveDbn `
        --sample-size 24 `
        --roots $Roots `
        --trades-only `
        --out $sample
    if ($LASTEXITCODE -ne 0) { throw "Option trades sampler exited $LASTEXITCODE" }
}
finally {
    Remove-Item Env:\DATABENTO_API_KEY -ErrorAction SilentlyContinue
}
