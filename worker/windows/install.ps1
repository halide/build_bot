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
# All done!

$workerScript = Resolve-Path "$PSScriptRoot\..\..\worker.ps1"
Write-Host "Finished! Restart PowerShell and run $workerScript"
