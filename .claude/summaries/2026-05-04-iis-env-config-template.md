---
id: 2026-05-04-iis-app-pool-env-vars-survive-publish-001
date: 2026-05-04
source: claude-code-cli
collection: knowledge_v2
project: petrochina-eproc
chunk_type: decision
topic: IIS App Pool Env Vars Survive Publish
tags: [petrochina, eproc, dotnet, iis, ci-cd, app-pool, environment-variables, implemented]
related: []
session_type: architecture
environment: dev
git_branch: main
status: implemented
chunk_source: code
---

## CHUNK 1: IIS App Pool Env Vars Survive Publish
<!-- rag_chunk_meta chunk_type=decision tags=[petrochina, eproc, dotnet, iis, ci-cd, app-pool, environment-variables, implemented] -->

## CHUNK 1: IIS App Pool Environment Variables Survive CI/CD Publish

### Context

A PowerShell IIS setup tool manages three ASP.NET Core applications deployed by Jenkins or dotnet publish to IIS physical paths. The deployment process replaces web.config, so any environment variables stored in web.config are lost after each publish.

### Problem

The original Setup-IIS.ps1 wrote environment variables to the IIS site path using MACHINE/WEBROOT/APPHOST/siteName with the system.webServer/aspNetCore/environmentVariables filter. That target writes to the site web.config. Jenkins file replacement then overwrote web.config and forced operators to set environment variables again on every development or production server.

### Solution

Set-EnvVars was changed to target the IIS Application Pool collection in applicationHost.config. The script now uses MACHINE/WEBROOT/APPHOST with the system.applicationHost/applicationPools/add[@name='appPoolName']/environmentVariables filter. ASPNETCORE_ENVIRONMENT is added to the desired environment map from server-config.json environment, while Set-WebConfig no longer writes an environmentVariables block. Application Pool environment variables are inherited by the ASP.NET Core worker process and survive dotnet publish because applicationHost.config is outside the deploy folder.

### Key Facts

- IIS site-level aspNetCore environment variables are stored in web.config and can be overwritten by dotnet publish.
- IIS Application Pool environment variables are stored in applicationHost.config and survive CI/CD file replacement.
- ASPNETCORE_ENVIRONMENT can be set per Application Pool so each site loads appsettings.Development.json or appsettings.Production.json independently.
- The setup tool manages environment variables per appPoolName, which supports separate API, Internal, and External sites in one solution.

### Code / Commands

```powershell
$pspath = "MACHINE/WEBROOT/APPHOST"
$filter = "system.applicationHost/applicationPools/add[@name='$appPoolName']/environmentVariables"
$desiredMap["ASPNETCORE_ENVIRONMENT"] = [string]$Project.environment
```

## CHUNK 2: Post Publish IIS Env Sync
<!-- rag_chunk_meta chunk_type=runbook tags=[petrochina, eproc, dotnet, iis, ci-cd, jenkins, environment-variables, implemented] -->

## CHUNK 2: Post Publish IIS Environment Sync Runbook

### Context

The IIS setup repository includes Publish-Projects.ps1, which builds ASP.NET Core projects and publishes them directly into IIS physical paths. The same repository includes Setup-IIS.ps1 with Setup, Update, SyncBindings, Status, Remove, and Audit modes.

### Problem

Publishing application files alone does not guarantee server runtime configuration is up to date. If server-config.json changes, the IIS environment variables must be synchronized after publish so the deployed process reads the correct connection strings, URLs, secrets, and ASPNETCORE_ENVIRONMENT values.

### Solution

Publish-Projects.ps1 was updated to call Setup-IIS.ps1 -Mode Update -ConfigPath $ConfigPath after a successful dotnet publish. This post-publish step syncs server-config.json envVars into IIS Application Pool environment variables. Operators can still run Setup-IIS.ps1 -Mode Update manually when only config changes are needed, and SyncBindings remains separate for port or hostname changes.

### Key Facts

- Publish-Projects.ps1 now performs a post-publish environment sync after dotnet publish succeeds.
- Setup-IIS.ps1 -Mode Update synchronizes envVars from server-config.json without recreating IIS sites.
- The Update mode recycles only changed Application Pools and avoids a global iisreset when possible.
- Binding or port changes still use Setup-IIS.ps1 -Mode SyncBindings, not Update.

### Code / Commands

```powershell
$setupScript = Join-Path $PSScriptRoot "Setup-IIS.ps1"
& $setupScript -Mode Update -ConfigPath $ConfigPath
```

## CHUNK 3: Safe Appsettings And Server Config
<!-- rag_chunk_meta chunk_type=pattern tags=[petrochina, eproc, dotnet, iis, configuration, secrets, appsettings, implemented] -->

## CHUNK 3: Safe Appsettings and Server Config Pattern

### Context

PetroChina.Eproc has API, Internal, and External ASP.NET Core projects. Each project can have appsettings.json, appsettings.Development.json, and appsettings.Production.json, while IIS runtime values are supplied from the external setup repository through server-config.json.

### Target Files

- src/PetroChina.Eproc.API/appsettings.Production.json
- src/Internal/PetroChina.Eproc.Internal.App/appsettings.Production.json
- src/External/PetroChina.Eproc.External.App/appsettings.Production.json
- .gitignore
- server-config.json in the IIS setup repository
- CLAUDE.md in the IIS setup repository

### Problem

Production appsettings files previously contained CHANGE_ME_VIA_ENV placeholders for secrets and deployment-specific values. Development appsettings files contained local credentials and needed to stay out of source control. The IIS setup template also needed to avoid real credentials and project-specific names so it could be reused for new servers.

### Solution

Production appsettings files were simplified to contain only non-sensitive values. API production config now keeps production logging and MailReceiver.Production, while Internal and External production configs keep only HttpMode. Runtime values such as connection strings, SecretKey, APIUrl, HangFire credentials, JDE credentials, Active Directory credentials, attachment path, WebUrl, and mail recipients are provided via IIS Application Pool environment variables. Development appsettings files for API, Internal, and External are ignored in .gitignore. server-config.json was converted to a generic template with FILL_IN placeholders and no real credentials or project names, and CLAUDE.md now forbids writing credentials into tracked files.

### Key Facts

- appsettings.Production.json should contain only non-sensitive production defaults.
- IIS Application Pool environment variables override appsettings.json and appsettings.Production.json in ASP.NET Core configuration.
- appsettings.Development.json files for API, Internal, and External are ignored because they can contain local credentials.
- server-config.json is a safe reusable template using FILL_IN placeholders rather than real project names or credentials.

### Verification

```bash
rtk grep -i "real-secret-pattern" server-config.json
rtk git status --short
```

### Caveats

server-config.json must be copied and filled locally on each server, then kept out of commits when it contains real values.

---

## SESSION METADATA

- **Total chunks**: 3
- **Qdrant collection**: knowledge_v2
- **Generated by**: rag_capture.py v2 -- Incremental Capture
- **Author**: Figur Ulul Azmi
- **Date**: 2026-05-04
- **Unresolved items**: (fill manually if needed)