# CLAUDE.md

## Session Resume Protocol

Before reading source files or answering project-specific questions, run:

```bash
rtk rag resume
```

If open checkpoints are listed, load the relevant checkpoint and follow its `next_step` before any broad exploration. If no open checkpoint exists, continue with the repository's existing RAG-first protocol.

## Fallback Essentials (if global CLAUDE.md is absent)

Full versions live in `~/.claude/CLAUDE.md`. Minimal rules below keep this repo self-sufficient.

### RTK (Rust Token Killer)

- Prefix every shell command with `rtk` (git, ls, grep, find, curl, etc.). RTK is always safe — passes through if no filter exists.
- Inside chains too: `rtk git add . && rtk git commit -m "..." && rtk git push`.

### RAG-First Protocol

Before answering project-specific questions (architecture, patterns, prior decisions, deploy procedures, past bugs):

1. Load deferred schema once per session: `ToolSearch select:mcp__qdrant-knowledge__search_knowledge`
2. Call `search_knowledge(query, project="petrochina-eproc")` — query ≥ 8 descriptive words.
3. If found → answer from RAG as ground truth. If not found → state "NOT FOUND IN RAG" and proceed with general knowledge disclaimer.
4. Never silently fall back to training data for project questions.

Skip RAG for: general programming questions, framework docs, small talk.

## Project: tools-iis-setup-dotnetcore-project

PowerShell script suite for IIS multi-project setup and maintenance for .NET Core apps.
Used to deploy PetroChina.Eproc (3 sites: eproc-api, eproc-internal, eproc-external) to Windows Server IIS.

```
Setup-IIS.ps1         — main script (Setup/Update/SyncBindings/Remove/Status/Audit modes)
Publish-Projects.ps1  — dotnet publish + post-deploy env var sync
server-config.json    — per-server config (env vars, ports, paths) — DO NOT COMMIT secrets
```

### Key Architecture Decisions

- Env vars stored in **IIS Application Pool** (`applicationHost.config`), NOT in `web.config`.
  Reason: `dotnet publish` replaces `web.config` on every deploy — App Pool vars survive.
- `ASPNETCORE_ENVIRONMENT` is also set via App Pool (from `server-config.json` `"environment"` field).
- Post-deploy: `Publish-Projects.ps1` auto-calls `Setup-IIS.ps1 -Mode Update` to sync env vars.

### Port Convention (PetroChina.Eproc)

| Site | Port (Dev) | Port (Prod) |
|------|-----------|------------|
| eproc-api      | 6200 | 6200 |
| eproc-internal | 6201 | 6201 |
| eproc-external | 6202 | 6202 |

## Critical Rules

- **English only** in code, comments, logs.
- **Never write real credentials, secrets, passwords, tokens, connection strings, private IP credentials, or production values into tracked project files.** Use placeholders such as `FILL_IN`, `CHANGE_ME`, or local ignored files instead.
- **Never commit** `server-config.json` with real credentials — copy from template and fill locally.
- If a user-provided file already contains credentials, do not copy them into new files or examples; redact them in responses and preserve/remove only as explicitly requested.
- **Plan first** if touching > 2 files.

## Docs Tracing Protocol

After changing code:
- Update `README.md` when script usage, modes, or deployment steps change.

Rules:
- Do not overwrite existing docs blindly. Edit the relevant section only.
- Do not modify `CLAUDE.md` unless explicitly requested.
- At the end of the work, report both code files and docs files changed.


---

## RAG Capture Canonical Tooling                                                                                                                                            
   
  For all RAG knowledge capture, checkpoint, resume, promote, merge, and push workflows, use the canonical local implementation:                                             
                                                               
  `C:/Users/Clandesitine/scripts/rag-capture-v2/rag_capture.py`

  The `rag` command is acceptable only as a CLI wrapper if it resolves to the same implementation. Prefer explicit `python
  "C:/Users/Clandesitine/scripts/rag-capture-v2/rag_capture.py" ...` when there is any ambiguity.

  Do not treat `rag-knowledge-capture-cli` as the storage engine. It is only a Claude Code skill/instruction wrapper that describes the workflow. The actual execution must
  be done through `rag_capture.py` or the `rag` CLI.

  ### Required flow

  For capture:
  1. Create chunk content internally.
  2. Run:
     ```bash
     rtk python "C:/Users/Clandesitine/scripts/rag-capture-v2/rag_capture.py" add        -p PROJECT        -t TYPE        --topic "TOPIC"        --tags "tag1,tag2,tag3"        --environment homelab        --status implemented        --content "$CONTENT"
  3. Run:
  rtk python "C:/Users/Clandesitine/scripts/rag-capture-v2/rag_capture.py" merge     -p PROJECT     --output YYYY-MM-DD-topic.md

  For resume:
  rtk python "C:/Users/Clandesitine/scripts/rag-capture-v2/rag_capture.py" resume

  For checkpoint:
  rtk python "C:/Users/Clandesitine/scripts/rag-capture-v2/rag_capture.py" checkpoint ...

  For promote:
  rtk python "C:/Users/Clandesitine/scripts/rag-capture-v2/rag_capture.py" promote ...

  Rules

  - Do not invoke rag-knowledge-capture-cli unless the user explicitly asks to inspect or update the skill instructions.
  - Do not use the Write tool to create .claude/summaries/*.md; rag_capture.py merge creates summary files.
  - Do not print chunk bodies to chat unless the user explicitly asks to review the content.
  - Use English only inside chunks for embedding quality.
  - Use one chunk per distinct problem-solution pair.
  - Use --project homelab for VM B1, Qdrant, Ollama, MCP, n8n, Docker, and infrastructure knowledge.
  - Use --project petrochina-eproc only for PetroChina/Eproc/.NET/Blazor/CQRS knowledge.
  - Always use rtk for shell commands.

  Versi super pendek kalau mau dimasukkan ke memory:

  ```markdown
  Always use `C:/Users/Clandesitine/scripts/rag-capture-v2/rag_capture.py` or its `rag` CLI wrapper for RAG capture/resume/checkpoint/merge/promote. Do not invoke
  `rag-knowledge-capture-cli` as the capture engine; it is only an instruction wrapper. Prefer explicit `rtk python
  "C:/Users/Clandesitine/scripts/rag-capture-v2/rag_capture.py" ...` when ambiguity exists.
  ```

