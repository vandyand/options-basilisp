[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$RunDir,
    [Parameter(Mandatory)] [datetime]$Deadline
)

$ErrorActionPreference = 'Stop'
$runtime = 'C:\Users\vandy\AppData\Local\Temp\stevetrading-databento-parity-runtime\Scripts\python.exe'
$comparator = Join-Path $PSScriptRoot 'databento_multischema_parity.py'
. "$HOME\.config\powershell\profile.ps1"
$env:DATABENTO_API_KEY = Get-DevSecret DATABENTO_API_KEY

try {
    while ($true) {
        Write-Output "[$((Get-Date).ToString('o'))] EQUS historical parity attempt"
        & $runtime $comparator `
            --run-dir $RunDir `
            --schemas mbp-1 trades ohlcv-1s `
            --representation market `
            --max-total-cost-usd 1 `
            --max-total-billable-bytes 268435456
        if ($LASTEXITCODE -eq 0) { return }
        if ((Get-Date).AddMinutes(5) -gt $Deadline) {
            throw "EQUS historical data did not become available before $Deadline"
        }
        Start-Sleep -Seconds 300
    }
}
finally {
    Remove-Item Env:\DATABENTO_API_KEY -ErrorAction SilentlyContinue
}
