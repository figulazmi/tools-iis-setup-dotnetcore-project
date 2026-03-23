#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Publish satu atau semua .NET Core project ke folder IIS

.PARAMETER ConfigPath
    Path ke server-config.json

.PARAMETER ProjectName
    Nama project spesifik (field "name" di config). Kosongkan untuk semua.

.PARAMETER SourceRoot
    Root folder solution di server. Contoh: "C:\Dev\PetroChina.Eproc"

.EXAMPLE
    .\Publish-Projects.ps1 -SourceRoot "C:\Dev\MyProject"
    .\Publish-Projects.ps1 -SourceRoot "C:\Dev\MyProject" -ProjectName "MyAPI"
#>

param(
    [string]$ConfigPath  = ".\server-config.json",
    [string]$ProjectName = "",
    [Parameter(Mandatory=$true)]
    [string]$SourceRoot
)

function Write-Step    { param([string]$t) Write-Host "  > $t" -ForegroundColor Yellow }
function Write-Success { param([string]$t) Write-Host "  OK $t" -ForegroundColor Green }
function Write-Fail    { param([string]$t) Write-Host "  XX $t" -ForegroundColor Red }
function Write-Header  {
    param([string]$Text)
    Write-Host ""
    Write-Host "-----------------------------------------------" -ForegroundColor Cyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host "-----------------------------------------------" -ForegroundColor Cyan
}

if (-not (Test-Path $ConfigPath)) { Write-Fail "Config tidak ditemukan: $ConfigPath"; exit 1 }
$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json

$projects = @($config.projects | Where-Object { $_.enabled -eq $true })
if ($ProjectName) {
    $projects = @($projects | Where-Object { $_.name -eq $ProjectName })
    if ($projects.Count -eq 0) { Write-Fail "Project '$ProjectName' tidak ditemukan di config"; exit 1 }
}

Import-Module WebAdministration -ErrorAction SilentlyContinue

foreach ($project in $projects) {
    Write-Header "Publishing: $($project.displayName)"

    # Cari .csproj berdasarkan nama project atau dllName
    $searchName = if ($project.dllName) {
        [System.IO.Path]::GetFileNameWithoutExtension($project.dllName)
    } else {
        $project.name
    }

    $projectFolder = Get-ChildItem -Path $SourceRoot -Recurse -Filter "*.csproj" |
                     Where-Object {
                         $_.Directory.Name -like "*$searchName*" -or
                         $_.BaseName       -like "*$searchName*"
                     } |
                     Select-Object -First 1

    if (-not $projectFolder) {
        Write-Fail "Tidak menemukan .csproj untuk '$searchName' di $SourceRoot"
        Write-Host "    Tip: Pastikan nama folder/project mengandung kata: $searchName" -ForegroundColor Gray
        continue
    }

    $csprojPath = $projectFolder.FullName
    $outputPath = $project.physicalPath

    Write-Step "Project : $csprojPath"
    Write-Step "Output  : $outputPath"

    # Stop site dulu untuk hindari file lock
    Write-Step "Stop site sementara..."
    Stop-Website    -Name $project.siteName    -ErrorAction SilentlyContinue
    Stop-WebAppPool -Name $project.appPoolName -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # Publish
    Write-Step "dotnet publish..."
    dotnet publish $csprojPath --configuration Release --output $outputPath --no-self-contained

    if ($LASTEXITCODE -ne 0) {
        Write-Fail "Publish gagal untuk $($project.name)!"
        Start-WebAppPool -Name $project.appPoolName -ErrorAction SilentlyContinue
        Start-Website    -Name $project.siteName    -ErrorAction SilentlyContinue
        continue
    }

    Write-Success "Publish selesai ke $outputPath"

    # Pastikan folder Media ada setelah publish
    $mediaPath = Join-Path $outputPath "Media"
    if (-not (Test-Path $mediaPath)) {
        New-Item -ItemType Directory -Path $mediaPath -Force | Out-Null
        Write-Success "Folder Media dibuat"
    }

    # Fix permission setelah publish (file baru mungkin belum punya permission)
    icacls $outputPath /grant "IIS AppPool\$($project.appPoolName):(OI)(CI)F" /T | Out-Null
    Write-Success "Permission folder diupdate"

    # Restart site
    Write-Step "Restart site..."
    Start-WebAppPool -Name $project.appPoolName -ErrorAction SilentlyContinue
    Start-Website    -Name $project.siteName    -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    $state = (Get-Website -Name $project.siteName -ErrorAction SilentlyContinue).State
    Write-Success "Site '$($project.siteName)' state: $state"
}

Write-Host ""
Write-Host "  Selesai. Cek status: .\Setup-IIS.ps1 -Mode Status" -ForegroundColor Green
Write-Host ""
