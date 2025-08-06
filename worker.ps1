$ErrorActionPreference = "Stop"

function Fail($message)
{
    Write-Error $message
    exit 1
}

cd $PSScriptRoot

if (-not (Test-Path "worker/halide_bb_pass.txt"))
{
    Fail "Missing worker/halide_bb_pass.txt: cannot continue"
}

if (-not $env:HALIDE_BB_WORKER_NAME)
{
    Fail "Environment variable HALIDE_BB_WORKER_NAME unset: cannot continue"
}

if (-not (Get-Command uv -ErrorAction SilentlyContinue))
{
    Fail "uv is not installed: cannot continue"
}

# Check if we're running from Task Scheduler (no interactive user session)
$isTaskScheduler = [Environment]::UserInteractive -eq $false -or $env:SESSIONNAME -eq $null

if ($isTaskScheduler)
{
    Write-Host "Launching buildbot worker (Task Scheduler mode)"
    & uv run --package worker buildbot-worker start --nodaemon worker
}
else
{
    Write-Host "Launching buildbot worker"
    & uv run --package worker buildbot-worker start worker
}
