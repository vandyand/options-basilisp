[CmdletBinding()]
param(
    [ValidateSet('liveness')]
    [string]$Phase = 'liveness',
    [ValidatePattern('^\d{4}-\d{2}-\d{2}$')]
    [string]$Date = (Get-Date).ToString('yyyy-MM-dd'),
    [string]$OutDir
)

$ErrorActionPreference = 'Stop'

if (-not $OutDir) {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
    $OutDir = Join-Path $repoRoot 'live_runtime\monday-open-checks'
}

$remote = 'stevetrading-vps'
$remoteRoot = '/opt/stevetrading/shared/thetadata-parity-v1'
$remoteScript = @'
set -u
unit_state() { systemctl is-active "$1" 2>/dev/null || true; }
health_file="$(mktemp)"
health_meta="$(curl -sS --max-time 8 -o "$health_file" -w '%{http_code} %{size_download}' \
  'http://127.0.0.1:25503/v3/option/list/expirations?symbol=SPY&format=json' 2>/dev/null || true)"
rm -f "$health_file"
receipt_dir="$REMOTE_ROOT/receipts/$TARGET_DATE/stream-events"
receipt="$(find "$receipt_dir" -maxdepth 1 -type f -name '*.json' 2>/dev/null | sort | tail -n 1)"
receipt_status=""
market_events="0"
if [[ -n "$receipt" ]] && command -v jq >/dev/null 2>&1; then
  receipt_status="$(jq -r '.status // empty' "$receipt" 2>/dev/null || true)"
  market_events="$(jq -r '.summary.market_event_count // 0' "$receipt" 2>/dev/null || printf '0')"
fi
jq -n \
  --arg host "$(hostname)" \
  --arg six "$(unit_state stevetrading-six.service)" \
  --arg terminal "$(unit_state theta-terminal.service)" \
  --arg snapshot "$(unit_state stevetrading-raw-thetadata-parity.service)" \
  --arg capture "$(unit_state stevetrading-thetadata-stream-capture.service)" \
  --arg history "$(unit_state stevetrading-raw-history-parity.service)" \
  --arg health_meta "$health_meta" \
  --arg receipt "$receipt" \
  --arg receipt_status "$receipt_status" \
  --argjson market_events "$market_events" \
  '{host: $host,
    units: {stevetrading_six: $six, theta_terminal: $terminal,
            raw_snapshot: $snapshot, stream_capture: $capture, raw_history: $history},
    terminal_health: {curl: $health_meta},
    latest_stream_receipt: {path: $receipt, status: $receipt_status,
                            market_event_count: $market_events}}'
'@

$remoteScript = $remoteScript -replace "`r`n", "`n"
$encodedScript = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remoteScript))
$remoteCommand = "echo $encodedScript | base64 -d | env TARGET_DATE='$Date' REMOTE_ROOT='$remoteRoot' bash -s"
$lines = & ssh.exe -o BatchMode=yes -o ConnectTimeout=12 $remote $remoteCommand 2>&1
$remoteExit = $LASTEXITCODE
$rawOutput = ($lines -join [Environment]::NewLine).Trim()

$remoteStatus = 'OBSERVED'
try {
    $remoteCheckpoint = $rawOutput | ConvertFrom-Json -ErrorAction Stop
}
catch {
    $remoteStatus = 'UNREACHABLE'
    $remoteCheckpoint = [ordered]@{ error = "remote checkpoint failed (exit $remoteExit)"; output = $rawOutput }
}

$status = $remoteStatus
$payload = [ordered]@{
    schema_version    = 1
    created_at        = (Get-Date).ToString('o')
    phase             = $Phase
    target_date       = $Date
    status            = $status
    remote            = $remote
    remote_status     = $remoteStatus
    remote_checkpoint = $remoteCheckpoint
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$stamp = (Get-Date).ToString('yyyyMMddTHHmmsszzz').Replace(':', '')
$out = Join-Path $OutDir "$Date-$Phase-$stamp.json"
$payload | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $out -Encoding utf8
Write-Output "Monday-open checkpoint written: $out"

if ($remoteStatus -eq 'UNREACHABLE') {
    exit 1
}
