# Runs a title and records the run in the repository, so another machine gets it with `git pull`:
# XCL's log, its report and the console output (a panic message is only there) go to runlogs\,
# are committed on the current branch and pushed to -Remote.
#
#   .\scripts\record-run.ps1 -Game 'D:\Games\SomeTitle' -Remote fork [-Seconds 0] [-Xcl .\target\debug\xcl.exe]
#
# For a private branch on your own fork only: the files name local paths and the title. The
# script refuses to run on main and to push to ivall/xcl. -Seconds 0 lets the title run until it ends.
param(
    [Parameter(Mandatory = $true)][string]$Game,
    [Parameter(Mandatory = $true)][string]$Remote,
    [int]$Seconds = 0,
    [string]$Xcl = (Join-Path $PSScriptRoot '..\target\debug\xcl.exe')
)
$ErrorActionPreference = 'Stop'

if (-not (Test-Path $Xcl)) { throw "no $Xcl - build it first (cargo build -p xcl)" }
$root = Split-Path $PSScriptRoot -Parent
$branch = (git -C $root rev-parse --abbrev-ref HEAD).Trim()
if ($branch -eq 'main' -or $branch -eq 'HEAD') { throw "on '$branch': switch to your run-log branch first" }
$url = (git -C $root remote get-url $Remote).Trim()
if ($LASTEXITCODE -ne 0) { throw "no git remote '$Remote'" }
if ($url -match 'ivall/xcl') { throw "remote '$Remote' is $url - run logs go to your own fork, not upstream" }
$commit = (git -C $root rev-parse --short HEAD).Trim()

# ProcessStartInfo, as in smoke.ps1 (Start-Process cannot build its environment on PowerShell 5.1
# when PATH is present twice with different casing)
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $Xcl
$psi.Arguments = 'run "' + $Game + '"'
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
$psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
$p = New-Object System.Diagnostics.Process
$p.StartInfo = $psi
if ($Seconds -gt 0) { $env:XCL_RUN_SECONDS = "$Seconds" }
$null = $p.Start()
$stdoutTask = $p.StandardOutput.ReadToEndAsync()
$stderrTask = $p.StandardError.ReadToEndAsync()
if ($Seconds -gt 0 -and -not $p.WaitForExit(($Seconds + 120) * 1000)) {
    if (-not $p.HasExited) { $p.Kill() }
}
$p.WaitForExit()
$stdout = $stdoutTask.Result
$stderr = $stderrTask.Result
if ($Seconds -gt 0) { Remove-Item Env:XCL_RUN_SECONDS }
$code = '0x{0:x}' -f $p.ExitCode

$out = Join-Path $root 'runlogs'
$null = New-Item -ItemType Directory -Force $out
$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $out 'console.txt'), "xcl $commit, exit $code`n--- stdout`n$stdout`n--- stderr`n$stderr", $utf8)

# byte copies: Get-Content / Set-Content would corrupt the UTF-8
$logLine = ($stdout -split "`n" | Where-Object { $_ -match '(^Log:|see the log:)\s+(.+)$' } | Select-Object -Last 1)
if ($logLine) {
    $log = ($logLine -replace '^.*?(Log:|see the log:)\s+', '').Trim()
    # XCL built from this branch writes both to runlogs\ itself: nothing to copy then
    $inPlace = (Test-Path $log) -and ((Split-Path (Resolve-Path $log) -Parent) -eq (Resolve-Path $out).Path)
    $report = Join-Path (Split-Path $log -Parent) 'report.json'
    if (-not $inPlace) {
        if (Test-Path $log) { Copy-Item $log (Join-Path $out 'xcl.log') -Force }
        if (Test-Path $report) { Copy-Item $report (Join-Path $out 'report.json') -Force }
    }
} else {
    Write-Warning 'XCL printed no log path: only console.txt is recorded'
}

git -C $root add -- runlogs
if (-not (git -C $root status --porcelain -- runlogs)) { Write-Host 'run recorded: nothing changed since the last one'; exit 0 }
git -C $root commit --quiet -m "Run log: $(Split-Path $Game -Leaf), exit $code, xcl $commit" -- runlogs
if ($LASTEXITCODE -ne 0) { throw 'git commit failed' }
git -C $root push --quiet $Remote "HEAD:$branch"
if ($LASTEXITCODE -ne 0) { throw "git push to '$Remote' failed (the run is committed locally)" }
Write-Host "run recorded (exit $code) and pushed to $Remote/$branch"
