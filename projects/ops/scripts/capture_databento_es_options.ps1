[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-z0-9-]+$')]
    [string]$Window
)

$ErrorActionPreference = 'Stop'

# This wrapper is intentionally secretless on disk.  The task runs under the
# interactive Windows user, unlocks DevSecrets in that process, and passes the
# key only through the child process environment.
. "$HOME\.config\powershell\profile.ps1"
Unlock-DevSecrets
$env:DATABENTO_API_KEY = Get-Secret DATABENTO_API_KEY -Vault DevSecrets -AsPlainText

$repo = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$python = 'C:\Users\vandy\AppData\Local\Temp\stevetrading-databento-parity-runtime\Scripts\python.exe'
$capture = Join-Path $PSScriptRoot 'databento_live_multischema_capture.py'
$outRoot = 'D:\SteveTradingData\raw\v1\databento-live-validation'
$logRoot = 'D:\SteveTradingData\manifests\v1\databento-live-validation\logs'

if (-not (Test-Path $python)) { throw "Databento runtime not found: $python" }
if ((Get-Volume -DriveLetter D).HealthStatus -ne 'Healthy') { throw 'D: corpus volume is not healthy' }
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
$log = Join-Path $logRoot ("es-opt-{0}-{1}.log" -f $Window, (Get-Date -Format 'yyyyMMddTHHmmss'))

try {
    & $python $capture `
        --out-root $outRoot `
        --dataset GLBX.MDP3 `
        --symbols ES.OPT `
        --stype-in parent `
        --schemas definition,mbp-1,trades `
        --duration-seconds 300 *>&1 | Tee-Object -FilePath $log
    if ($LASTEXITCODE -ne 0) { throw "Databento ES options capture exited $LASTEXITCODE" }
}
finally {
    Remove-Item Env:\DATABENTO_API_KEY -ErrorAction SilentlyContinue
}
