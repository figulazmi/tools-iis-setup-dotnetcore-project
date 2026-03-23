#Requires -RunAsAdministrator
<#
.SYNOPSIS
    IIS Multi-Project Setup Script untuk .NET Core

.PARAMETER ConfigPath
    Path ke file server-config.json. Default: .\server-config.json

.PARAMETER Mode
    Setup  : Install IIS + buat semua site/app pool (default)
    Update : Update environment variables dari config (tanpa buat ulang site)
    Remove : Hapus semua site/app pool yang ada di config
    Status : Tampilkan status semua site
    Audit  : Tampilkan semua port yang sudah dipakai di server ini

.EXAMPLE
    .\Setup-IIS.ps1
    .\Setup-IIS.ps1 -Mode Status
    .\Setup-IIS.ps1 -Mode Update
    .\Setup-IIS.ps1 -Mode Audit
    .\Setup-IIS.ps1 -ConfigPath "C:\configs\production.json" -Mode Setup
#>

param(
    [string]$ConfigPath = ".\server-config.json",
    [ValidateSet("Setup", "Update", "Remove", "Status", "Audit")]
    [string]$Mode = "Setup"
)

# ─────────────────────────────────────────────
#  HELPER FUNCTIONS
# ─────────────────────────────────────────────

function Write-Header {
    param([string]$Text)
    Write-Host ""
    Write-Host "===============================================" -ForegroundColor Cyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host "===============================================" -ForegroundColor Cyan
}

function Write-Step    { param([string]$t) Write-Host "  > $t" -ForegroundColor Yellow }
function Write-Success { param([string]$t) Write-Host "  OK $t" -ForegroundColor Green }
function Write-Warn    { param([string]$t) Write-Host "  !! $t" -ForegroundColor Magenta }
function Write-Fail    { param([string]$t) Write-Host "  XX $t" -ForegroundColor Red }

# ─────────────────────────────────────────────
#  PORT VALIDATION FUNCTIONS
# ─────────────────────────────────────────────

function Get-UsedPorts {
    # Ambil semua port yang sedang LISTENING dari netstat
    $listeningPorts = @()
    $netstatOutput = netstat -ano | Select-String "LISTENING"
    foreach ($line in $netstatOutput) {
        if ($line -match ":(\d+)\s+\d+\.\d+\.\d+\.\d+:0\s+LISTENING" -or
            $line -match ":(\d+)\s+\[::\]:0\s+LISTENING") {
            $port = [int]$Matches[1]
            if ($port -notin $listeningPorts) {
                $listeningPorts += $port
            }
        }
    }
    return $listeningPorts
}

function Get-IISBindingPorts {
    # Ambil semua port yang sudah dipakai IIS site
    $iisPorts = @()
    try {
        $bindings = Get-WebBinding
        foreach ($b in $bindings) {
            if ($b.bindingInformation -match ":(\d+):") {
                $port = [int]$Matches[1]
                if ($port -notin $iisPorts) {
                    $iisPorts += $port
                }
            }
        }
    } catch {}
    return $iisPorts
}

function Test-PortAvailable {
    param([int]$Port, [string]$ProjectName)

    $allUsed = Get-UsedPorts
    $iisUsed = Get-IISBindingPorts

    # Cek port sudah dipakai process lain
    if ($Port -in $allUsed) {
        # Cek apakah port ini milik IIS site kita sendiri (eproc)
        $ourSite = Get-WebBinding | Where-Object {
            $_.bindingInformation -like "*:${Port}:*"
        } | Where-Object {
            # Cek apakah binding ini milik site yang ada di config kita
            $siteName = ($_.ItemXPath -split "'")[1]
            $config.projects.siteName -contains $siteName
        }

        if ($ourSite) {
            Write-Warn "Port $Port sudah dipakai site kita sendiri — akan di-skip pembuatan binding"
            return $true
        }

        Write-Fail "PORT CONFLICT: Port $Port sudah dipakai oleh process lain! ($ProjectName)"
        Write-Host ""
        Write-Host "    Proses yang memakai port $Port :" -ForegroundColor White
        netstat -ano | findstr ":$Port " | findstr "LISTENING"
        Write-Host ""
        Write-Host "    Solusi: Ganti port di server-config.json" -ForegroundColor Yellow
        Write-Host "    Gunakan range port yang aman:" -ForegroundColor Yellow
        Write-Host "    Project 1: 6000-6099  |  Project 2: 6100-6199  |  Project 3: 6200-6299" -ForegroundColor Cyan
        Write-Host ""
        return $false
    }

    # Cek port sudah dipakai IIS site lain
    if ($Port -in $iisUsed) {
        $conflictSite = Get-WebBinding | Where-Object {
            $_.bindingInformation -like "*:${Port}:*"
        }
        Write-Fail "PORT CONFLICT: Port $Port sudah dipakai IIS site lain! ($ProjectName)"
        Write-Host "    Site konflik: $($conflictSite.ItemXPath)" -ForegroundColor White
        Write-Host "    Solusi: Ganti port di server-config.json" -ForegroundColor Yellow
        return $false
    }

    Write-Success "Port $Port tersedia untuk $ProjectName"
    return $true
}

function Show-PortAudit {
    Write-Header "Audit Port Server"

    Write-Host ""
    Write-Host "  PORT YANG SEDANG DIPAKAI (LISTENING):" -ForegroundColor White
    Write-Host "  ─────────────────────────────────────" -ForegroundColor Gray

    $netstatLines = netstat -ano | Select-String "LISTENING"
    $portMap = @{}

    foreach ($line in $netstatLines) {
        if ($line -match "TCP\s+\d+\.\d+\.\d+\.\d+:(\d+)") {
            $port = $Matches[1]
            if (-not $portMap.ContainsKey($port)) {
                $portMap[$port] = $line.ToString().Trim()
            }
        }
    }

    # Tampilkan port IIS dengan nama site
    Write-Host ""
    Write-Host "  IIS SITE BINDINGS:" -ForegroundColor White
    Write-Host "  ─────────────────────────────────────" -ForegroundColor Gray
    try {
        Get-WebBinding | Select-Object @{n="Port";e={
            if ($_.bindingInformation -match ":(\d+):") { $Matches[1] } else { "-" }
        }}, @{n="Host";e={
            $parts = $_.bindingInformation -split ":"
            if ($parts[2]) { $parts[2] } else { "*" }
        }}, protocol, @{n="Site";e={
            ($_.ItemXPath -split "'")[1]
        }} | Sort-Object Port | Format-Table -AutoSize
    } catch {
        Write-Warn "Tidak bisa ambil IIS binding (import WebAdministration terlebih dahulu)"
    }

    # Tampilkan rekomendasi port aman
    Write-Host ""
    Write-Host "  REKOMENDASI PORT UNTUK PROJECT BARU:" -ForegroundColor White
    Write-Host "  ─────────────────────────────────────" -ForegroundColor Gray

    $usedPorts  = Get-UsedPorts
    $iisPorts   = Get-IISBindingPorts
    $allUsed    = ($usedPorts + $iisPorts) | Sort-Object -Unique

    $ranges = @(
        @{Start=6000; End=6099; Label="Range 1 (Project Pertama)"},
        @{Start=6100; End=6199; Label="Range 2 (Project Kedua)"},
        @{Start=6200; End=6299; Label="Range 3 (Project Ketiga)"},
        @{Start=6300; End=6399; Label="Range 4 (Project Keempat)"}
    )

    foreach ($range in $ranges) {
        $available = @()
        for ($p = $range.Start; $p -le $range.End; $p++) {
            if ($p -notin $allUsed) { $available += $p }
        }
        $status = if ($available.Count -gt 90) { "AMAN" } elseif ($available.Count -gt 0) { "SEBAGIAN" } else { "PENUH" }
        $color  = if ($status -eq "AMAN") { "Green" } elseif ($status -eq "SEBAGIAN") { "Yellow" } else { "Red" }

        Write-Host "    $($range.Label): " -NoNewline
        Write-Host "$status ($($available.Count) port tersedia)" -ForegroundColor $color

        if ($available.Count -gt 0 -and $available.Count -le 90) {
            Write-Host "    Port tersedia: $($available[0..9] -join ', ')..." -ForegroundColor Gray
        }
    }
    Write-Host ""
}

# ─────────────────────────────────────────────
#  CORE FUNCTIONS
# ─────────────────────────────────────────────

function Ensure-IISInstalled {
    Write-Header "Memeriksa IIS"
    $iisFeature = Get-WindowsFeature -Name Web-Server
    if (-not $iisFeature.Installed) {
        Write-Step "Menginstall IIS..."
        $features = @(
            "Web-Server","Web-Common-Http","Web-Default-Doc","Web-Static-Content",
            "Web-Http-Errors","Web-Http-Redirect","Web-Health","Web-Http-Logging",
            "Web-Request-Monitor","Web-Security","Web-Filtering","Web-Basic-Auth",
            "Web-Windows-Auth","Web-Mgmt-Tools","Web-Mgmt-Console"
        )
        Install-WindowsFeature -Name $features -IncludeManagementTools | Out-Null
        Write-Success "IIS berhasil diinstall"
    } else {
        Write-Success "IIS sudah terinstall"
    }
    Import-Module WebAdministration -ErrorAction Stop
    Write-Success "WebAdministration module loaded"
}

function Ensure-HostingBundle {
    Write-Header "Memeriksa ASP.NET Core Hosting Bundle"
    $ancmModule = Get-WebGlobalModule | Where-Object { $_.Name -like "*AspNetCore*" }
    if ($ancmModule) {
        Write-Success "ASP.NET Core Module V2 sudah terdaftar di IIS"
    } else {
        Write-Warn "ASP.NET Core Hosting Bundle belum terinstall!"
        Write-Host ""
        Write-Host "    Download: https://dotnet.microsoft.com/download/dotnet/$($config.dotnetVersion)" -ForegroundColor Cyan
        Write-Host "    Pilih: Hosting Bundle, lalu jalankan: iisreset /restart" -ForegroundColor White
        Write-Host ""
        $continue = Read-Host "    Lanjutkan tanpa hosting bundle? (y/N)"
        if ($continue -ne "y" -and $continue -ne "Y") {
            Write-Fail "Setup dibatalkan. Install hosting bundle terlebih dahulu."
            exit 1
        }
    }
}

function Create-PhysicalPath {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        Write-Success "Folder dibuat: $Path"
    } else {
        Write-Success "Folder sudah ada: $Path"
    }
    $logPath = Join-Path $Path "logs"
    if (-not (Test-Path $logPath)) {
        New-Item -ItemType Directory -Path $logPath -Force | Out-Null
    }
    $mediaPath = Join-Path $Path "Media"
    if (-not (Test-Path $mediaPath)) {
        New-Item -ItemType Directory -Path $mediaPath -Force | Out-Null
        Write-Success "Folder Media dibuat: $mediaPath"
    }
}

function Set-FolderPermissions {
    param([string]$Path, [string]$PoolName)
    Write-Step "Set permission folder untuk App Pool..."
    icacls $Path /grant "IIS AppPool\${PoolName}:(OI)(CI)F" /T | Out-Null
    Write-Success "Permission OK: IIS AppPool\$PoolName -> $Path"
}

function Create-AppPool {
    param([object]$Project)
    $poolName = $Project.appPoolName
    if (Test-Path "IIS:\AppPools\$poolName") {
        Write-Warn "App Pool '$poolName' sudah ada, skip"
        return
    }
    Write-Step "Membuat App Pool: $poolName"
    New-WebAppPool -Name $poolName | Out-Null
    Set-ItemProperty "IIS:\AppPools\$poolName" -Name "managedRuntimeVersion" -Value ""
    Set-ItemProperty "IIS:\AppPools\$poolName" -Name "managedPipelineMode"   -Value "Integrated"
    Set-ItemProperty "IIS:\AppPools\$poolName" -Name "startMode"             -Value "AlwaysRunning"
    Set-ItemProperty "IIS:\AppPools\$poolName" -Name "autoStart"             -Value $true
    Write-Success "App Pool '$poolName' dibuat (No Managed Code, AlwaysRunning)"
}

function Create-WebSite {
    param([object]$Project)
    $siteName = $Project.siteName
    $poolName = $Project.appPoolName
    $path     = $Project.physicalPath
    $bindings = $Project.bindings

    $existingSite = Get-Website -Name $siteName -ErrorAction SilentlyContinue
    if ($existingSite) {
        Write-Warn "Site '$siteName' sudah ada, skip"
        return
    }

    Write-Step "Membuat IIS Site: $siteName"
    $firstBinding = $bindings[0]
    $hostname     = if ($firstBinding.hostname) { $firstBinding.hostname } else { "" }

    New-Website -Name $siteName `
                -PhysicalPath $path `
                -ApplicationPool $poolName `
                -Port $firstBinding.port `
                -HostHeader $hostname `
                -Force | Out-Null

    if ($bindings.Count -gt 1) {
        for ($i = 1; $i -lt $bindings.Count; $i++) {
            $b = $bindings[$i]
            New-WebBinding -Name $siteName -Protocol $b.protocol -Port $b.port -HostHeader $b.hostname | Out-Null
            Write-Step "  Tambah binding: $($b.protocol)://$($b.hostname):$($b.port)"
        }
    }
    Write-Success "Site '$siteName' dibuat"
}

function Set-WebConfig {
    param([object]$Project)
    $path          = $Project.physicalPath
    $webConfigPath = Join-Path $path "web.config"
    $hostingModel  = if ($Project.hostingModel) { $Project.hostingModel } else { "inprocess" }

    if ($Project.dllName) {
        $dllName = $Project.dllName
    } else {
        $existingDll = Get-ChildItem -Path $path -Filter "*.dll" -ErrorAction SilentlyContinue |
                       Where-Object {
                           $_.Name -notlike "System.*" -and
                           $_.Name -notlike "Microsoft.*" -and
                           $_.Name -notlike "AutoMapper*" -and
                           $_.Name -notlike "Azure.*" -and
                           $_.Name -notlike "EFCore*" -and
                           $_.Name -notlike "Hangfire*" -and
                           $_.Name -notlike "MudBlazor*" -and
                           $_.Name -notlike "Newtonsoft*"
                       } | Select-Object -First 1
        $dllName = if ($existingDll) { $existingDll.Name } else { "$($Project.name).dll" }
    }

    Write-Step "DLL target: $dllName"

    $lines = @(
        '<?xml version="1.0" encoding="utf-8"?>',
        '<configuration>',
        '  <location path="." inheritInChildApplications="false">',
        '    <system.webServer>',
        '      <handlers>',
        '        <add name="aspNetCore" path="*" verb="*" modules="AspNetCoreModuleV2" resourceType="Unspecified" />',
        '      </handlers>',
        "      <aspNetCore processPath=`"dotnet`"",
        "                  arguments=`".\$dllName`"",
        '                  stdoutLogEnabled="true"',
        '                  stdoutLogFile=".\logs\stdout"',
        "                  hostingModel=`"$hostingModel`">",
        '        <environmentVariables>',
        "          <environmentVariable name=`"ASPNETCORE_ENVIRONMENT`" value=`"$($Project.environment)`" />",
        '        </environmentVariables>',
        '      </aspNetCore>',
        '    </system.webServer>',
        '  </location>',
        '</configuration>'
    )

    $webConfigContent = $lines -join "`r`n"
    Set-Content -Path $webConfigPath -Value $webConfigContent -Encoding UTF8 -NoNewline
    Write-Success "web.config dibuat (dll: $dllName, hostingModel: $hostingModel)"
}

function Set-EnvVars {
    param([object]$Project)
    $siteName = $Project.siteName
    $envVars  = $Project.envVars

    if (-not $envVars) {
        Write-Warn "Tidak ada envVars di config untuk $($Project.name)"
        return
    }

    Write-Step "Set environment variables untuk $($Project.name)..."

    $pspath = "MACHINE/WEBROOT/APPHOST/$siteName"
    $filter = "system.webServer/aspNetCore/environmentVariables"

    $envVars.PSObject.Properties | ForEach-Object {
        $key   = $_.Name
        $value = $_.Value
        try {
            Remove-WebConfigurationProperty -PSPath $pspath -Filter $filter -Name "." `
                -AtElement @{name=$key} -ErrorAction SilentlyContinue
            Add-WebConfigurationProperty -PSPath $pspath -Filter $filter -Name "." `
                -Value @{name=$key; value=$value}
            Write-Success "  ENV: $key"
        } catch {
            Write-Warn "  Gagal set ENV '$key': $($_.Exception.Message)"
        }
    }
}

function Setup-SSL {
    param([object]$SslConfig, [array]$Projects)
    if ($SslConfig.mode -eq "none") {
        Write-Warn "SSL mode = none. Edit server-config.json ssl.mode = 'winacme' atau 'pfx' untuk aktifkan."
        return
    }
    Write-Header "Setup SSL"
    if ($SslConfig.mode -eq "winacme") {
        $wacs = $SslConfig.winAcmePath
        if (-not (Test-Path $wacs)) {
            Write-Fail "win-acme tidak ditemukan: $wacs"
            Write-Host "    Download: https://www.win-acme.com" -ForegroundColor Cyan
            return
        }
        Write-Host ""
        Write-Host "    Jalankan win-acme manual untuk tiap domain:" -ForegroundColor White
        foreach ($p in $Projects) {
            $hostname = $p.bindings[0].hostname
            if ($hostname) {
                Write-Host "    $wacs --target iis --host $hostname" -ForegroundColor Cyan
            }
        }
        Write-Warn "Jalankan perintah di atas setelah setup selesai"
    }
    elseif ($SslConfig.mode -eq "pfx") {
        if (-not (Test-Path $SslConfig.pfxPath)) {
            Write-Fail "File PFX tidak ditemukan: $($SslConfig.pfxPath)"
            return
        }
        $securePass = ConvertTo-SecureString $SslConfig.pfxPassword -AsPlainText -Force
        $cert = Import-PfxCertificate -FilePath $SslConfig.pfxPath `
                    -CertStoreLocation "Cert:\LocalMachine\My" -Password $securePass
        Write-Success "Certificate imported: $($cert.Thumbprint)"
        foreach ($p in $Projects) {
            $hostname = $p.bindings[0].hostname
            if ($hostname) {
                New-WebBinding -Name $p.siteName -Protocol "https" -Port 443 `
                    -HostHeader $hostname -SslFlags 1 -ErrorAction SilentlyContinue
                $binding = Get-WebBinding -Name $p.siteName -Protocol "https"
                $binding.AddSslCertificate($cert.Thumbprint, "My")
                Write-Success "SSL binding: $($p.siteName) ($hostname)"
            }
        }
    }
}

function Show-Status {
    Write-Header "Status IIS Sites"
    foreach ($project in $config.projects) {
        $siteName = $project.siteName
        $poolName = $project.appPoolName

        $site = Get-Website -Name $siteName -ErrorAction SilentlyContinue
        $pool = Get-WebAppPoolState -Name $poolName -ErrorAction SilentlyContinue

        $siteStatus = if ($site) { $site.State } else { "NOT FOUND" }
        $poolStatus = if ($pool) { $pool.Value  } else { "NOT FOUND" }
        $enabled    = if ($project.enabled) { "enabled" } else { "disabled" }

        $siteColor = if ($siteStatus -eq "Started") { "Green" } elseif ($siteStatus -eq "NOT FOUND") { "Red" } else { "Yellow" }
        $poolColor  = if ($poolStatus -eq "Started") { "Green" } elseif ($poolStatus -eq "NOT FOUND") { "Red" } else { "Yellow" }

        Write-Host ""
        Write-Host "  [$($project.displayName)] ($enabled)" -ForegroundColor White
        Write-Host "    Site : " -NoNewline; Write-Host $siteStatus -ForegroundColor $siteColor
        Write-Host "    Pool : " -NoNewline; Write-Host $poolStatus -ForegroundColor $poolColor
        Write-Host "    DLL  : $($project.dllName)" -ForegroundColor Gray
        Write-Host "    Path : $($project.physicalPath)" -ForegroundColor Gray
        $hostname = $project.bindings[0].hostname
        $port     = $project.bindings[0].port
        $url      = if ($hostname) { "http://$hostname" } else { "http://SERVER_IP:$port" }
        Write-Host "    URL  : $url" -ForegroundColor Gray
    }
    Write-Host ""
}

function Remove-AllSites {
    Write-Header "Menghapus Semua Site"
    $confirm = Read-Host "  Ketik 'ya' untuk konfirmasi hapus semua site dari config"
    if ($confirm -ne "ya") { Write-Warn "Dibatalkan"; return }
    foreach ($project in $config.projects) {
        $site = Get-Website -Name $project.siteName -ErrorAction SilentlyContinue
        if ($site) {
            Stop-Website -Name $project.siteName -ErrorAction SilentlyContinue
            Remove-Website -Name $project.siteName
            Write-Success "Site '$($project.siteName)' dihapus"
        }
        $pool = Get-WebAppPoolState -Name $project.appPoolName -ErrorAction SilentlyContinue
        if ($pool) {
            Stop-WebAppPool -Name $project.appPoolName -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1
            Remove-WebAppPool -Name $project.appPoolName
            Write-Success "Pool '$($project.appPoolName)' dihapus"
        }
    }
}

# ─────────────────────────────────────────────
#  MAIN
# ─────────────────────────────────────────────

Clear-Host
Write-Host ""
Write-Host "  IIS Multi-Project Setup untuk .NET Core" -ForegroundColor Cyan
Write-Host "  Mode: $Mode" -ForegroundColor White
Write-Host ""

if (-not (Test-Path $ConfigPath)) {
    Write-Fail "Config tidak ditemukan: $ConfigPath"
    exit 1
}

$config   = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$projects = @($config.projects | Where-Object { $_.enabled -eq $true })

Write-Host "  Config  : $($config.serverName)" -ForegroundColor White
Write-Host "  Projects: $($projects.Count) aktif" -ForegroundColor White

# ── Mode: Audit ──────────────────────────────
if ($Mode -eq "Audit") {
    Import-Module WebAdministration -ErrorAction SilentlyContinue
    Show-PortAudit
    exit 0
}

# ── Mode: Status ─────────────────────────────
if ($Mode -eq "Status") {
    Import-Module WebAdministration -ErrorAction SilentlyContinue
    Show-Status
    exit 0
}

# ── Mode: Remove ─────────────────────────────
if ($Mode -eq "Remove") {
    Import-Module WebAdministration -ErrorAction SilentlyContinue
    Remove-AllSites
    exit 0
}

# ── Mode: Setup ──────────────────────────────
if ($Mode -eq "Setup") {
    Ensure-IISInstalled
    Ensure-HostingBundle

    # Validasi semua port sebelum mulai setup
    Write-Header "Validasi Port"
    $portConflict = $false
    foreach ($project in $projects) {
        foreach ($binding in $project.bindings) {
            $available = Test-PortAvailable -Port $binding.port -ProjectName $project.displayName
            if (-not $available) { $portConflict = $true }
        }
    }

    if ($portConflict) {
        Write-Host ""
        Write-Fail "Setup dibatalkan karena ada konflik port!"
        Write-Host "  Jalankan '.\Setup-IIS.ps1 -Mode Audit' untuk lihat port yang tersedia" -ForegroundColor Yellow
        Write-Host ""
        exit 1
    }

    Write-Success "Semua port tersedia, lanjutkan setup..."
}

Import-Module WebAdministration -ErrorAction Stop

foreach ($project in $projects) {
    Write-Header "Project: $($project.displayName)"

    # 1. Buat folder fisik + logs + Media
    Write-Step "Menyiapkan folder..."
    Create-PhysicalPath -Path $project.physicalPath

    if ($Mode -eq "Setup") {
        # 2. Set permission folder ke App Pool
        Set-FolderPermissions -Path $project.physicalPath -PoolName $project.appPoolName

        # 3. Buat App Pool
        Create-AppPool -Project $project

        # 4. Buat IIS Site
        Create-WebSite -Project $project

        # 5. Buat web.config dengan nama DLL yang benar
        Write-Step "Membuat web.config..."
        Set-WebConfig -Project $project

        # 6. Buka firewall port (hanya untuk binding tanpa hostname/IP only)
        foreach ($binding in $project.bindings) {
            if (-not $binding.hostname) {
                $ruleName = "IIS - $($project.displayName) port $($binding.port)"
                $existing = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
                if (-not $existing) {
                    New-NetFirewallRule -DisplayName $ruleName `
                        -Direction Inbound -Protocol TCP -LocalPort $binding.port -Action Allow | Out-Null
                    Write-Success "Firewall port $($binding.port) dibuka"
                } else {
                    Write-Warn "Firewall rule sudah ada untuk port $($binding.port), skip"
                }
            }
        }
    }

    # 7. Set environment variables (Setup & Update)
    Set-EnvVars -Project $project

    # 8. Start site & pool
    Write-Step "Start site..."
    try {
        Start-WebAppPool -Name $project.appPoolName -ErrorAction SilentlyContinue
        Start-Website    -Name $project.siteName    -ErrorAction SilentlyContinue
        Write-Success "Site running: $($project.siteName)"
    } catch {
        Write-Warn "Belum bisa start - publish dulu file ke: $($project.physicalPath)"
    }
}

# ── SSL Setup ────────────────────────────────
if ($Mode -eq "Setup") {
    Write-Host ""
    Setup-SSL -SslConfig $config.ssl -Projects $projects
}

# ── Restart IIS ──────────────────────────────
iisreset /restart | Out-Null
Write-Success "IIS direstart"

# ── Summary ──────────────────────────────────
Write-Host ""
Show-Status

Write-Host "  LANGKAH SELANJUTNYA:" -ForegroundColor Yellow
Write-Host "  1. Publish project dari laptop: dotnet publish -c Release -o <physicalPath>" -ForegroundColor White
Write-Host "  2. Transfer hasil publish ke folder masing-masing project" -ForegroundColor White
Write-Host "  3. Jika ada perubahan envVars: .\Setup-IIS.ps1 -Mode Update" -ForegroundColor White
Write-Host "  4. Untuk cek port server: .\Setup-IIS.ps1 -Mode Audit" -ForegroundColor White
if ($config.ssl.mode -eq "none") {
    Write-Host "  5. Setup SSL: edit server-config.json ssl.mode = 'winacme' atau 'pfx'" -ForegroundColor White
}
Write-Host ""
