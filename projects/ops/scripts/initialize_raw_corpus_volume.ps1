[CmdletBinding()]
param(
    [string]$DriveLetter = 'D',
    [string]$ExpectedLabel = 'Seagate Hub',
    [string]$CorpusDirectory = 'SteveTradingData',
    [switch]$Initialize
)

$ErrorActionPreference = 'Stop'
$drive = $DriveLetter.TrimEnd(':').ToUpperInvariant()
if ($drive.Length -ne 1) { throw 'DriveLetter must be one letter, for example D.' }

$volume = Get-Volume -DriveLetter $drive
$partition = Get-Partition -DriveLetter $drive
$disk = Get-Disk -Number $partition.DiskNumber
$physical = Get-PhysicalDisk | Where-Object { $_.FriendlyName -eq $disk.FriendlyName } | Select-Object -First 1

$status = [ordered]@{
    drive = "$drive`:"
    label = $volume.FileSystemLabel
    filesystem = $volume.FileSystem
    volume_health = $volume.HealthStatus.ToString()
    volume_operational_status = ($volume.OperationalStatus -join ', ')
    disk_health = $disk.HealthStatus.ToString()
    disk_operational_status = ($disk.OperationalStatus -join ', ')
    physical_disk_health = if ($physical) { $physical.HealthStatus.ToString() } else { 'unknown' }
    free_bytes = [int64]$volume.SizeRemaining
    target = "$drive`:\$CorpusDirectory"
    initialized = $false
}

if ($volume.FileSystemLabel -ne $ExpectedLabel) {
    throw ("Refusing volume initialization: expected label '{0}', found '{1}'." -f $ExpectedLabel, $volume.FileSystemLabel)
}
if ($volume.HealthStatus -ne 'Healthy' -or $disk.HealthStatus -ne 'Healthy' -or ($physical -and $physical.HealthStatus -ne 'Healthy')) {
    $status | ConvertTo-Json -Depth 3
    throw 'Refusing raw-corpus write: storage health is not Healthy. Repair and re-check the volume first.'
}

if ($Initialize) {
    $root = $status.target
    @(
        $root,
        "$root\raw\v1",
        "$root\manifests\v1",
        "$root\derived\v1",
        "$root\quarantine\v1"
    ) | ForEach-Object { New-Item -ItemType Directory -Path $_ -Force | Out-Null }
    $status.initialized = $true
}

$status | ConvertTo-Json -Depth 3
