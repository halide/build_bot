$ErrorActionPreference = "Stop"

function Fail($message)
{
    Write-Error $message
    exit 1
}

cd $PSScriptRoot

##
# Check necessary tools are installed

if (-not (Get-Command winget -ErrorAction SilentlyContinue))
{
    Fail "winget is not installed: cannot continue"
}

##
# Check/set HALIDE_BB_WORKER_NAME

if (-not $env:HALIDE_BB_WORKER_NAME)
{
    Fail "Environment variable HALIDE_BB_WORKER_NAME unset: cannot continue"
}

Write-Host "Setting HALIDE_BB_WORKER_NAME environment variable..."
[Environment]::SetEnvironmentVariable("HALIDE_BB_WORKER_NAME", $env:HALIDE_BB_WORKER_NAME, "User")

##
# Set important registry settings

$keyPath = "HKCU:\Software\Microsoft\Windows\Windows Error Reporting"
if (-not (Test-Path $keyPath))
{
    New-Item -Path $keyPath -Force | Out-Null
}
Set-ItemProperty -Path $keyPath -Name "DontShowUI" -Value 1 -Type DWord
Write-Host "Disabled Windows Error Reporting crash dialogs (Current User)"

##
# Install system dependencies

Write-Host "Installing winget-managed dependencies..."
winget import winget-packages.json --accept-package-agreements --accept-source-agreements
winget install -e --id Microsoft.VisualStudio.2022.Community --override "--passive --config $PSScriptRoot\.vsconfig"

##
# Install uv

Write-Host "Installing uv..."
powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"

##
# Install vcpkg and its dependencies

$baseline = "2025.07.25"

$vcpkg_root = "C:\vcpkg"
$vcpkg_repo = "https://github.com/microsoft/vcpkg.git"

if (-not (Test-Path $vcpkg_root))
{
    Write-Host "Cloning vcpkg into $vcpkg_root..."
    git clone $vcpkg_repo $vcpkg_root
}
else
{
    Write-Host "$vcpkg_root exists, fetching latest tags..."
    git -C $vcpkg_root fetch --tags origin
}

Write-Host "Checking out vcpkg $baseline..."
git -C $vcpkg_root checkout $baseline

Write-Host "Setting VCPKG_ROOT environment variable..."
[Environment]::SetEnvironmentVariable("VCPKG_ROOT", "$vcpkg_root", "User")
$env:VCPKG_ROOT = $vcpkg_root

Write-Host "Bootstrapping vcpkg..."
& "$vcpkg_root\bootstrap-vcpkg.bat" -disableMetrics

Write-Host "Installing vcpkg packages..."
# TODO: determine this from the repository
& "$vcpkg_root\vcpkg.exe" install libjpeg-turbo libpng zlib openblas --triplet x64-windows
& "$vcpkg_root\vcpkg.exe" install libjpeg-turbo libpng zlib openblas --triplet x86-windows

##
# Install the autostart task

$workerScript = Resolve-Path "$PSScriptRoot\..\..\worker.ps1"

# Create/update the scheduled task
$taskName = "Halide Buildbot Worker"
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"$workerScript`""
$trigger = New-ScheduledTaskTrigger -AtLogOn
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartInterval (New-TimeSpan -Minutes 1) -RestartCount 3
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive

# Remove existing task if it exists
$existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existingTask)
{
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    Write-Host "Removed existing scheduled task"
}

# Register the new task
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal | Out-Null
Write-Host "Registered scheduled task '$taskName'"

# Start the task immediately
Start-ScheduledTask -TaskName $taskName
Write-Host "Started buildbot worker task"

##
# All done!

Write-Host "Finished! The buildbot worker is now running and will start automatically at login."
