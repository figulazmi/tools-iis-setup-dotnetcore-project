# IIS Multi-Project Setup — .NET Core

Script otomatis untuk setup IIS di Windows Server untuk hosting beberapa project
ASP.NET Core sekaligus. Edit config JSON, jalankan script, selesai.

Fitur terbaru:

- Mode `Update` tanpa `iisreset` global, hanya recycle app pool yang benar-benar berubah.
- Sinkronisasi env vars penuh: key lama di IIS yang sudah tidak ada di config akan dihapus.
- Validasi `requiredEnvKeys` per project sebelum apply untuk mencegah key kritikal terlewat.
- Dry-run untuk preview diff env vars sebelum apply (tanpa perubahan ke IIS).

---

## File dalam Paket Ini

| File | Fungsi |
|------|--------|
| `server-config.json` | **Edit di sini** — daftar project, port, env vars, SSL |
| `Setup-IIS.ps1` | Install IIS + buat App Pool + buat Site + set env vars |
| `Publish-Projects.ps1` | Publish build artifact ke folder masing-masing project |

---

## Prasyarat

1. **Windows Server 2019/2022**
2. **ASP.NET Core Hosting Bundle** — wajib untuk IIS hosting
   - Download: `https://dotnet.microsoft.com/download/dotnet/9.0`
   - Pilih: **Hosting Bundle** (bukan SDK atau Runtime biasa)
   - Setelah install → `iisreset /restart`
3. **PowerShell 5.1+** (sudah built-in di Windows Server)

---

## Cara Penggunaan

### Langkah 1 — Edit `server-config.json`

Sesuaikan untuk project baru kamu:

```json
{
  "serverName": "Nama Server Kamu",
  "dotnetVersion": "9.0",
  "projects": [
    {
      "name": "NamaProject",
      "displayName": "Nama Tampilan",
      "siteName": "nama-site-iis",
      "appPoolName": "nama-pool",
      "dllName": "NamaProject.API.dll",          <- PENTING: nama DLL hasil publish
      "physicalPath": "C:\\inetpub\\wwwroot\\nama-project",
      "bindings": [
        { "protocol": "http", "hostname": "", "port": 5000 }
      ],
      "environment": "Production",
      "hostingModel": "inprocess",
      "envVars": {
        "ConnectionStrings__MainConnection": "Server=...;Database=...;"
      },
      "requiredEnvKeys": [
        "ConnectionStrings__MainConnection"
      ],
      "enabled": true
    }
  ]
}
```

> **Tips dllName**: Nama DLL = nama file `.csproj` kamu.
> Contoh: `MyProject.API.csproj` → `dllName: "MyProject.API.dll"`

---

### Langkah 2 — Jalankan Setup IIS

Buka **PowerShell sebagai Administrator**:

```powershell
cd C:\scripts\iis-setup
.\Setup-IIS.ps1
```

Script otomatis akan:
- Install IIS dan fitur yang diperlukan
- Cek ASP.NET Core Hosting Bundle
- Buat App Pool (No Managed Code, AlwaysRunning)
- Buat IIS Site dengan port binding
- Buat folder `logs\` dan `Media\` otomatis
- Set permission folder ke App Pool
- Buat `web.config` dengan nama DLL yang benar
- Set semua environment variables
- Buka firewall port
- Restart IIS

---

### Langkah 3 — Publish dan Transfer File

**Publish di laptop:**
```powershell
dotnet publish ./src/MyProject.API `
    --configuration Release `
    --output ./publish/MyProject.API `
    --no-self-contained
```

**Transfer ke server** via WinSCP atau SMB ke folder `physicalPath` masing-masing project.

---

### Langkah 4 — Cek Status

```powershell
.\Setup-IIS.ps1 -Mode Status
```

---

## Mode-mode Script

| Mode | Perintah | Fungsi |
|------|----------|--------|
| `Setup` (default) | `.\Setup-IIS.ps1` | Install IIS + validasi port + buat semua site baru |
| `Update` | `.\Setup-IIS.ps1 -Mode Update` | Sinkronisasi penuh env vars + recycle app pool yang berubah (tanpa `iisreset` global) |
| `Update (Dry-Run)` | `.\Setup-IIS.ps1 -Mode Update -DryRun` | Tampilkan diff env vars (add/change/remove) tanpa apply dan tanpa recycle |
| `Status` | `.\Setup-IIS.ps1 -Mode Status` | Tampilkan status semua site |
| `Remove` | `.\Setup-IIS.ps1 -Mode Remove` | Hapus semua site (dengan konfirmasi) |
| `Audit` | `.\Setup-IIS.ps1 -Mode Audit` | Tampilkan semua port yang dipakai + rekomendasi port aman |

Contoh preview sebelum apply:

```powershell
.\Setup-IIS.ps1 -Mode Update -DryRun
```

---

## Konfigurasi SSL

### Opsi A — Let's Encrypt via win-acme (Gratis, Recommended)

```json
"ssl": {
  "mode": "winacme",
  "winAcmePath": "C:\\tools\\win-acme\\wacs.exe"
}
```

Setelah setup, jalankan win-acme:
```powershell
C:\tools\win-acme\wacs.exe --target iis --host nama-domain.com
```

### Opsi B — Certificate PFX

```json
"ssl": {
  "mode": "pfx",
  "pfxPath": "C:\\certs\\yourdomain.pfx",
  "pfxPassword": "password_pfx"
}
```

---

## Cara Isi `envVars` di `server-config.json`

Format env vars menggunakan **double underscore `__`** untuk nested config:

```
appsettings.json structure      →  envVars key
──────────────────────────────     ──────────────────────────────────
ConnectionStrings.MainConnection → ConnectionStrings__MainConnection
ApplicationConfig.SecretKey      → ApplicationConfig__SecretKey
Integration.JDE.Username         → Integration__JDE__Username
APIUrl (root level)              → APIUrl
```

Nilai di `envVars` akan **override** nilai di `appsettings.Production.json` saat runtime.

Tambahkan juga `requiredEnvKeys` per project untuk key kritikal yang wajib ada dan tidak boleh kosong:

```json
"requiredEnvKeys": [
  "ConnectionStrings__MainConnection",
  "ApplicationConfig__SecretKey"
]
```

Jika ada key wajib yang hilang/kosong, script akan batal sebelum perubahan diaplikasikan.

---


## Konvensi Port — Hindari Tabrakan

**Selalu jalankan Audit dulu sebelum setup project baru:**
```powershell
.\Setup-IIS.ps1 -Mode Audit
```

Gunakan range port yang terstruktur per project:

| Range | Fungsi |
|-------|--------|
| `80`, `443` | HTTP/HTTPS publik (domain) |
| `5000–5099` | Hindari — sering dipakai .NET default & HTTP.sys |
| `6000–6099` | Project 1 (API: 6000, Internal: 6001, External: 6002) |
| `6100–6199` | Project 2 (API: 6100, Internal: 6101, External: 6102) |
| `6200–6299` | Project 3 |
| `6300–6399` | Project 4 |
| `8000–8099` | Tools (Hangfire, Swagger, dsb) |

Script akan **otomatis batal** jika ada konflik port saat Mode Setup dijalankan.

## Troubleshooting

### HTTP Error 500.31 — Failed to load ASP.NET Core runtime
ASP.NET Core Hosting Bundle belum terinstall.
```powershell
# Verifikasi setelah install
Get-WebGlobalModule | Where-Object { $_.Name -like "*AspNetCore*" }
```

### HTTP Error 500.30 — ASP.NET Core app failed to start
App crash saat startup. Cek event log:
```powershell
Get-EventLog -LogName Application -Newest 20 |
    Where-Object { $_.EntryType -eq "Error" } |
    Select-Object TimeGenerated, Source, Message |
    Format-List
```

Penyebab paling umum:
| Error | Solusi |
|-------|--------|
| `ArgumentNullException` di `Program.cs` | Ada env var yang belum di-set di `envVars` |
| `DirectoryNotFoundException: Media\` | Jalankan Setup ulang — folder Media akan dibuat otomatis |
| `Cannot open database` | Connection string salah di `envVars` |

### HTTP Error 500 — Unexpected content type: text/html
API belum jalan, IIS return halaman error. Cek apakah API site Started:
```powershell
.\Setup-IIS.ps1 -Mode Status
```

### Site tidak bisa start setelah publish
```powershell
# Fix permission folder setelah transfer file baru
icacls "C:\inetpub\wwwroot\nama-project" /grant "IIS AppPool\nama-pool:(OI)(CI)F" /T
iisreset /restart
```

### Cek env vars yang sudah ter-set
```powershell
Get-WebConfigurationProperty `
    -PSPath "MACHINE/WEBROOT/APPHOST/nama-site" `
    -Filter "system.webServer/aspNetCore/environmentVariables" `
    -Name "." | Select-Object name, value
```

### Edit env vars via IIS Manager (UI)
```
IIS Manager → Sites → [nama-site] → Configuration Editor
→ Section: system.webServer/aspNetCore
→ environmentVariables → klik "..."
```

---

## Untuk Project Baru di Kemudian Hari

1. Tambahkan blok baru di array `projects` di `server-config.json`
2. Set `"enabled": true`
3. Isi `dllName` dengan nama DLL hasil publish
4. Isi `envVars` dengan semua config yang dibutuhkan
5. Jalankan: `.\Setup-IIS.ps1 -Mode Setup`
6. Transfer hasil publish ke `physicalPath`

**Estimasi waktu setup project baru: ~5 menit** ✅

---

## Struktur Folder Hasil Setup

```
C:\inetpub\wwwroot\
├── myproject-api\
│   ├── logs\                 ← stdout logs
│   ├── Media\                ← static files (dibuat otomatis)
│   ├── web.config            ← dibuat otomatis oleh script
│   ├── MyProject.API.dll     ← hasil dotnet publish
│   └── ...
├── myproject-internal\
│   └── ...
└── myproject-external\
    └── ...

C:\scripts\iis-setup\
├── Setup-IIS.ps1
├── Publish-Projects.ps1
└── server-config.json
```
