# Writes what Windows recorded about XCL's last crashes to runlogs\crash-event.txt: the
# "Application Error" (1000) and "Windows Error Reporting" (1001) events that name xcl.exe, with
# the faulting module and offset. A fail-fast (0xC0000409) leaves nothing in XCL's own log.
#
#   .\scripts\crash-event.ps1        (right after the run that crashed)
$ErrorActionPreference = 'Stop'
$out = Join-Path (Split-Path $PSScriptRoot -Parent) 'runlogs\crash-event.txt'
$events = Get-WinEvent -FilterHashtable @{ LogName = 'Application'; Id = 1000, 1001 } -MaxEvents 300 -ErrorAction SilentlyContinue |
    Where-Object { $_.Message -match 'xcl\.exe' } | Select-Object -First 4
$text = if ($events) {
    ($events | ForEach-Object { "=== $($_.TimeCreated.ToString('s')) event $($_.Id) ($($_.ProviderName))`r`n$($_.Message)" }) -join "`r`n`r`n"
} else {
    'no Application event 1000 / 1001 names xcl.exe'
}
[System.IO.File]::WriteAllText($out, $text, (New-Object System.Text.UTF8Encoding($false)))
Write-Host $text
Write-Host "`nwritten to $out"
