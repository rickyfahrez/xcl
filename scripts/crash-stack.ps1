# Runs a title under cdb (Debugging Tools for Windows) and writes the state at the first fatal
# event to runlogs\crash-stack.txt: the event, the registers, the crashing thread's stack, every
# thread's stack and the module list. For a fail-fast (0xC0000409), which no handler inside the
# process sees, this is the only way to learn who called what.
#
#   .\scripts\crash-stack.ps1 -Game 'D:\Games\SomeTitle' [-Xcl .\target\debug\xcl.exe] [-Cdb <path to cdb.exe>]
#
# First-chance exceptions are left to the process (XCL and titles handle many of their own); cdb
# stops at a fail-fast or at an exception nobody handled. The title's own code is mapped by XCL
# and shows as bare addresses: xcl.log (same folder) has the module bases.
param(
    [Parameter(Mandatory = $true)][string]$Game,
    [string]$Xcl = (Join-Path $PSScriptRoot '..\target\debug\xcl.exe'),
    [string]$Cdb
)
$ErrorActionPreference = 'Stop'

if (-not (Test-Path $Xcl)) { throw "no $Xcl - build it first (cargo build -p xcl)" }
if (-not $Cdb) {
    $candidates = @(
        "${env:ProgramFiles(x86)}\Windows Kits\10\Debuggers\x64\cdb.exe",
        "$env:ProgramFiles\Windows Kits\10\Debuggers\x64\cdb.exe"
    )
    $onPath = Get-Command cdb.exe -ErrorAction SilentlyContinue
    if ($onPath) { $candidates += $onPath.Source }
    $store = Get-AppxPackage Microsoft.WinDbg -ErrorAction SilentlyContinue
    if ($store) { $candidates += (Join-Path $store.InstallLocation 'amd64\cdb.exe') }
    $Cdb = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
}
if (-not $Cdb -or -not (Test-Path $Cdb)) {
    throw ("cdb.exe not found. Install it one of these ways, then run this again:`n" +
        "  - Settings > Apps > Installed apps > Windows Software Development Kit > Modify > Change > tick 'Debugging Tools for Windows'`n" +
        "  - winget install Microsoft.WinDbg`n" +
        "or pass -Cdb <path to cdb.exe>")
}

$out = Join-Path (Split-Path $PSScriptRoot -Parent) 'runlogs'
$null = New-Item -ItemType Directory -Force $out
$stack = Join-Path $out 'crash-stack.txt'
$symbols = Join-Path $env:TEMP 'xcl-symbols'
$exe = (Resolve-Path $Xcl).Path

# sxd: no stop on the first chance, stop when nobody handled it. sxi: not an event to stop at
# (the launcher starts the host as a child process; -o follows it). After `g`, the rest runs at
# the first stop.
$commands = @(
    'sxd *', 'sxd av', 'sxd ii', 'sxd eh', 'sxd gp', 'sxd dz', 'sxd iov', 'sxd dm', 'sxd ch', 'sxd isc', 'sxd 3c', 'sxd bpe', 'sxd sse', 'sxd wob',
    'sxi ibp', 'sxi cpr', 'sxi epr', 'sxi ct', 'sxi et', 'sxi ld', 'sxi ud',
    'g',
    '.echo ===XCL-STOP', '.lastevent', '.exr -1',
    '.echo ===REGISTERS', 'r',
    '.echo ===STACK', 'kn 100',
    '.echo ===RAW-STACK', 'dqs @rsp L80',
    '.echo ===THREADS', '~*kn 30',
    '.echo ===MODULES', 'lm',
    '.echo ===XCL-END', 'q'
) -join ';'

Write-Host "cdb: $Cdb"
Write-Host "the title runs under the debugger; the stack goes to $stack"
& $Cdb -o -G -y "srv*$symbols*https://msdl.microsoft.com/download/symbols" -logo $stack -c $commands $exe run $Game | Out-Null

if (-not (Test-Path $stack)) { throw 'cdb wrote no log' }
if (Select-String -Path $stack -Pattern '^===XCL-STOP' -Quiet) {
    Write-Host "recorded a stop: $stack"
} else {
    Write-Host "the run ended without a fatal event (cdb's output is still in $stack)"
}
