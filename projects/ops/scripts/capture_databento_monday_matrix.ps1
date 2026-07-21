[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-z0-9-]+$')]
    [string]$Window,

    [switch]$CaptureOnly,

    [ValidatePattern('^[A-Z0-9]+(?:,[A-Z0-9]+)*$')]
    [string]$OptionRoots = 'ES,NQ,SR3'
)

$ErrorActionPreference = 'Stop'
. "$HOME\.config\powershell\profile.ps1"
$env:DATABENTO_API_KEY = Get-DevSecret DATABENTO_API_KEY

$runtime = 'C:\Users\vandy\AppData\Local\Temp\stevetrading-databento-parity-runtime\Scripts\python.exe'
$capture = Join-Path $PSScriptRoot 'databento_live_multischema_capture.py'
$repo = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$basilisp = Join-Path $repo '.venv\Scripts\basilisp.exe'
$sampler = Join-Path $repo 'scripts\databento_option_parity_sample.lpy'
$parityRetry = Join-Path $PSScriptRoot 'Invoke-DatabentoOptionParityRetry.ps1'
$outRoot = 'D:\SteveTradingData\raw\v1\databento-live-validation'
$logRoot = 'D:\SteveTradingData\manifests\v1\databento-live-validation\logs'
$manifestRoot = 'D:\SteveTradingData\manifests\v1\databento-live-validation'
$stamp = Get-Date -Format 'yyyyMMddTHHmmss'
$optionParents = (($OptionRoots -split ',') | ForEach-Object { "$_.OPT" }) -join ','

if (-not (Test-Path -LiteralPath $runtime)) { throw "Databento runtime not found: $runtime" }
if ((Get-Volume -DriveLetter D).HealthStatus -ne 'Healthy') { throw 'D: corpus volume is not healthy' }
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null

$jobs = @(
    @{
        Label = 'options'
        Symbols = $optionParents
        Schemas = 'definition,mbp-1,trades'
        Duration = '300'
    },
    @{
        Label = 'futures'
        Symbols = 'ES.FUT,NQ.FUT,RTY.FUT,ZN.FUT,ZB.FUT,SR3.FUT'
        Schemas = 'definition,mbp-1,trades'
        Duration = '300'
    }
)

try {
    $processes = foreach ($job in $jobs) {
        $stdout = Join-Path $logRoot ("monday-{0}-{1}-{2}.stdout.log" -f $job.Label, $Window, $stamp)
        $stderr = Join-Path $logRoot ("monday-{0}-{1}-{2}.stderr.log" -f $job.Label, $Window, $stamp)
        $arguments = @(
            $capture,
            '--out-root', $outRoot,
            '--dataset', 'GLBX.MDP3',
            '--symbols', $job.Symbols,
            '--stype-in', 'parent',
            '--schemas', $job.Schemas,
            '--duration-seconds', $job.Duration
        )
        $process = Start-Process -FilePath $runtime -ArgumentList $arguments `
            -WorkingDirectory (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) `
            -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
        [pscustomobject]@{ Label = $job.Label; Process = $process; Stdout = $stdout; Stderr = $stderr }
    }

    $failed = @()
    foreach ($entry in $processes) {
        $entry.Process.WaitForExit()
        if ($entry.Process.ExitCode -ne 0) {
            $failed += "{0}: exit={1}, stderr={2}" -f $entry.Label, $entry.Process.ExitCode, $entry.Stderr
        }
    }
    if ($failed.Count -gt 0) { throw ($failed -join '; ') }

    $optionsEntry = $processes | Where-Object Label -eq 'options' | Select-Object -First 1
    $optionsReceipt = Get-Content -LiteralPath $optionsEntry.Stdout -Raw | ConvertFrom-Json
    $liveDbn = Join-Path $optionsReceipt.run_dir 'live.dbn'
    $runId = Split-Path -Leaf $optionsReceipt.run_dir
    $sample = Join-Path $manifestRoot "$runId-option-sample.json"

    & $basilisp run $sampler `
        --live-dbn $liveDbn `
        --sample-size 24 `
        --roots $OptionRoots `
        --out $sample
    if ($LASTEXITCODE -ne 0) { throw "Option sampler exited $LASTEXITCODE" }

    $futuresEntry = $processes | Where-Object Label -eq 'futures' | Select-Object -First 1
    $futuresReceipt = Get-Content -LiteralPath $futuresEntry.Stdout -Raw | ConvertFrom-Json
    $futuresLiveDbn = Join-Path $futuresReceipt.run_dir 'live.dbn'
    $futuresRunId = Split-Path -Leaf $futuresReceipt.run_dir
    $futuresSample = Join-Path $manifestRoot "$futuresRunId-futures-trade-symbols.json"

    & $basilisp run $sampler `
        --live-dbn $futuresLiveDbn `
        --sample-size 1 `
        --roots ES,NQ,RTY,ZN,ZB,SR3 `
        --out $futuresSample
    if ($LASTEXITCODE -ne 0) { throw "Futures trade-symbol extraction exited $LASTEXITCODE" }

    # During the live session, capturing both immutable streams and both
    # selection manifests is the only critical path. Same-session history is
    # commonly unavailable and must not block or invalidate those captures.
    if ($CaptureOnly) { return }

    $deadline = (Get-Date).AddHours(1).ToString('o')
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $parityRetry `
        -ClassId "glbx-options-monday-20260720-$Window-preliminary" `
        -Deadline $deadline `
        -Sample $sample `
        -LiveDbn $liveDbn `
        -Start $optionsReceipt.subscribed_at `
        -End $optionsReceipt.ended_at `
        -MaxTotalBillableBytes 1048576 `
        -TradesOnly
    if ($LASTEXITCODE -ne 0) { throw "Historical option parity retry exited $LASTEXITCODE" }

    $deadline = (Get-Date).AddHours(1).ToString('o')
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $parityRetry `
        -ClassId "glbx-futures-monday-20260720-$Window-trades-preliminary" `
        -Deadline $deadline `
        -Sample $futuresSample `
        -LiveDbn $futuresLiveDbn `
        -Start $futuresReceipt.subscribed_at `
        -End $futuresReceipt.ended_at `
        -MaxTotalBillableBytes 5242880 `
        -AllTradeSymbols
    if ($LASTEXITCODE -ne 0) { throw "Futures historical parity retry exited $LASTEXITCODE" }
}
finally {
    Remove-Item Env:\DATABENTO_API_KEY -ErrorAction SilentlyContinue
}
