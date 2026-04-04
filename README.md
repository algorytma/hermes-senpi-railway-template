# Hermes-Senpi Trader — Railway Template

> **A production-ready, persistent-volume-first Hermes AI trading agent on Railway with Senpi MCP integration.**
>
> Analysis-first, execution-controlled, dual-profile architecture for autonomous crypto trading on Hyperliquid.

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/new/template)

---

## What You Get

- **Hermes Agent** (NousResearch) — pinned upstream release, no fork
- **Dual-profile architecture** — `analysis` (always-on) and `execution` (manually enabled) share one service but use isolated `HERMES_HOME` directories
- **Persistent state via Railway Volume** — config, workspace, credentials, and logs survive redeploys
- **Senpi MCP integration** — `@senpi-ai/mcp-server` registered in `mcp_registry.yaml`, active only in execution profile
- **Multi-provider support** — OpenRouter, NVIDIA NIM, DashScope, Z.AI, Kimi, MiniMax (7 providers, alias-based routing)
- **Risk-gated execution** — `risk_policy.yaml` required before execution profile starts; `allow_open_new_position: false` by default
- **Wolf Strategy skill** — first skill pre-configured as manifest; disabled, human-approval required
- **Bootstrap system** — idempotent init, schema migrations, config generation on every container start
- **Backup & restore scripts** — platform-portable `.tar.gz` exports, not Railway-only
- **Security boundaries** — secrets in env only, no API keys in config files or logs

---

## Quick Start (Railway)

### 1. Fork and Connect

```bash
git clone https://github.com/algorytma/hermes-senpi-railway-template
cd hermes-senpi-railway-template
```

### 2. Create Railway Project

```bash
railway login
railway init
```

### 3. Add a Persistent Volume

Railway Dashboard → **Storage** → **Add Volume**
- Mount Path: `/data`
- Size: 5 GB (minimum)

### 4. Set Environment Variables

Railway Dashboard → **Variables** → add the following:

| Variable | Required | Description |
|---|---|---|
| `OPENROUTER_API_KEY` | **Yes** | Primary AI provider key |
| `SENPI_AUTH_TOKEN` | Yes (execution) | Senpi platform auth token for MCP |
| `ACTIVE_PROFILE` | Yes | `analysis` (default) or `execution` |
| `DATA_DIR` | Yes | Set to `/data` |
| `HERMES_VERSION` | Recommended | `v0.6.0` (pinned) |
| `NVIDIA_API_KEY` | Optional | For `trade-fast` alias (NVIDIA NIM) |
| `DASHSCOPE_API_KEY` | Optional | For Qwen/DashScope models |
| `ZAI_API_KEY` / `ZAI_BASE_URL` | Optional | Z.AI / GLM models |
| `KIMI_API_KEY` / `KIMI_BASE_URL` | Optional | Moonshot / Kimi models |
| `MINIMAX_API_KEY` / `MINIMAX_BASE_URL` | Optional | MiniMax models |
| `TELEGRAM_BOT_TOKEN` | Optional | For Telegram notifications |
| `ADMIN_SETUP_TOKEN` | Optional | Admin endpoint auth |
| `BACKUP_ENCRYPTION_PASSPHRASE` | Optional | Encrypt backup archives |

> **Important:** Never put API key values in `railway.toml` or any config file. Use Railway Variables only.

### 5. Deploy

```bash
railway up
```

On first boot, the bootstrap system:
1. Creates the full `/data` directory structure
2. Copies default canonical config files into `/data`
3. Runs schema migrations
4. Generates Hermes config from registry YAML files + env vars
5. Starts Hermes in `analysis` profile

---

## Architecture

```
Container (hermes-agent:v0.6.0)
    │
    └─▶ bootstrap/prestart.sh
            ├── init-volume.sh          # first-run /data setup
            ├── run-migrations.sh       # schema version check
            ├── validate-risk.sh        # execution: risk_policy.yaml required
            └── scripts/render-config.py
                    │
                    ├── providers/provider_registry.yaml  ─┐
                    ├── providers/model_aliases.yaml        ├─▶ config.generated.yaml
                    ├── mcp/mcp_registry.yaml (filtered)  ─┘
                    └── mcp/mcp.generated.yaml
                                │
                          hermes runtime
```

### Two Profiles, One Container

| | Analysis | Execution |
|-|----------|-----------|
| `HERMES_HOME` | `/data/.hermes/analysis` | `/data/.hermes/execution` |
| Default model alias | `analysis-deep` | `trade-safe` |
| Senpi MCP | ❌ Disabled | ✅ Active |
| Trade execution | ❌ | ✅ (risk-gated) |
| Active by default | ✅ | ❌ — requires `ACTIVE_PROFILE=execution` |

### Switching to Execution Profile

> ⚠️ Only do this after analysis testing and risk policy review.

1. Review `/data/risk/risk_policy.yaml` thoroughly
2. Set `ACTIVE_PROFILE=execution` in Railway Variables
3. Verify `SENPI_AUTH_TOKEN` is valid
4. Redeploy — `validate-risk.sh` will gate the startup

---

## Config System

### Canonical vs Generated

```
Env vars (secrets)
    +
Canonical YAML → bootstrap/render-config.py → Generated config → Hermes runtime
  (you edit)                                    (auto-produced)    (reads this)
```

| File | Type | Edit by |
|------|------|---------|
| `providers/provider_registry.yaml` | CANONICAL | Operator |
| `providers/model_aliases.yaml` | CANONICAL | Operator |
| `mcp/mcp_registry.yaml` | CANONICAL | Operator |
| `skills/manifests/*.yaml` | CANONICAL | Operator |
| `risk/risk_policy.yaml` | CANONICAL | Operator |
| `workspace/AGENTS.md` | CANONICAL | Operator |
| `.hermes/*/config.generated.yaml` | GENERATED | `render-config.py` |
| `mcp/mcp.generated.yaml` | GENERATED | `render-config.py` |
| `workspace/MEMORY.md` | GENERATED | Hermes agent |

**Rule:** Never edit generated files. Edit canonical YAML and restart the container.

### Model Alias System

Agents reference model aliases, never raw model IDs. This lets you swap providers without touching prompts.

| Alias | Use Case | Default Provider/Model |
|-------|----------|----------------------|
| `general-fast` | Routing, classification | OpenRouter / GPT-4.1-mini |
| `general-smart` | High-comprehension tasks | OpenRouter / Claude Sonnet |
| `analysis-deep` | Multi-step market analysis | OpenRouter / DeepSeek-R1 |
| `trade-fast` | Low-latency trade decision | NVIDIA NIM / DeepSeek-R1 |
| `trade-safe` | Safe execution default | OpenRouter / Claude Sonnet |
| `reasoning-max` | Complex multi-step strategy | OpenRouter / DeepSeek-R1 |
| `research-cheap` | News, data collection | OpenRouter / Llama 3.3 free |
| `cn-research` | Chinese source analysis | Kimi / kimi-latest |

---

## Risk Policy

The execution profile **will not start** without a valid `risk_policy.yaml`.

Default safe values (set during first-run init):

```yaml
mode: copilot                           # human approval required for all actions
execution:
  dry_run_default: true                 # everything is dry-run until you change this
  allow_open_new_position: false        # cannot open new positions by default
symbols:
  allowlist: ["BTC", "ETH", "SOL"]
  default_action: deny                  # all non-allowlist symbols rejected
trading:
  max_leverage: 3
  max_position_size_usd: 300
  max_daily_loss_usd: 100
```

To enable live trading:
1. Set `allow_open_new_position: true`
2. Set `dry_run_default: false`
3. Change `mode: semi-auto` or `mode: auto`
4. Restart container

---

## Skills

Skills are managed via YAML manifests in `/data/skills/manifests/`. 

Pre-configured skill manifests (all disabled by default):

| Skill | Profile | Risk | Auto-approval |
|-------|---------|------|---------------|
| `wolf-strategy` | analysis | high | No |
| `senpi-market-scan` | analysis | low | Yes |
| `senpi-stop-manager` | execution | high | No |

### Installing a Skill

```bash
railway run bash scripts/install-skill.sh /data/skills/manifests/wolf-strategy.yaml
```

> **Required:** `pinned_commit` must be set in the manifest. Branch-only installs are rejected.

---

## Backup & Restore

### Full Backup

```bash
railway run bash scripts/backup-export.sh
# Output: /data/backups/exports/backup-YYYYMMDD-HHMMSS.tar.gz
```

Config-only backup (no workspace/logs):

```bash
railway run bash scripts/export-config.sh
```

### Restore

```bash
railway run bash scripts/backup-restore.sh /data/backups/exports/backup-20260404-000000.tar.gz
railway redeploy
```

> After restore, generated configs are wiped and regenerated from canonical YAML + your current env vars. Sessions are cleared.

---

## Local Smoke Test

```bash
cp .env.example .env
# Edit .env — add at minimum OPENROUTER_API_KEY

docker build --build-arg HERMES_VERSION=v0.6.0 -t hermes-senpi-trader .

docker run --rm \
  -e ACTIVE_PROFILE=analysis \
  -e DATA_DIR=/data \
  -e OPENROUTER_API_KEY=your-key \
  -v $(pwd)/.tmpdata:/data \
  hermes-senpi-trader

# Check logs — bootstrap should complete and Hermes should start
```

### Healthcheck

```bash
docker run --rm ... bash scripts/healthcheck.sh
```

---

## Upgrading Hermes

```bash
# 1. Take a backup
railway run bash scripts/backup-export.sh

# 2. Update HERMES_VERSION in railway.toml and redeploy
# railway.toml → [build.args] → HERMES_VERSION = "v0.7.0"

railway up

# 3. Bootstrap auto-runs migrations and regenerates config
```

To rollback: Railway Dashboard → Deployments → previous deploy → Rollback.

---

## Security

See [SECURITY.md](SECURITY.md) for the full security model, boundaries, and operator checklist.

Key guarantees:
- API keys exist only in env vars — never in config files, logs, or workspace
- Senpi MCP is isolated to the `execution` profile
- Execution starts with `dry_run: true` and `allow_open_new_position: false`
- `symbols.default_action: deny` — all non-listed symbols rejected

---

## Project Structure

```
hermes-senpi-trader/
├── Dockerfile                      # hermes-agent:v0.6.0 based, pinned
├── railway.toml                    # Railway deploy config
├── .env.example                    # Environment variable template
├── CLAUDE.md                       # AI assistant guidance for this repo
├── SECURITY.md                     # Security model and operator checklist
├── LICENSE
│
├── bootstrap/                      # Container lifecycle scripts
│   ├── prestart.sh                 # Main entrypoint (6-step boot)
│   ├── init-volume.sh              # First-run /data initialization
│   ├── validate-risk.sh            # Execution profile risk gate
│   └── run-migrations.sh           # Schema version migrations
│
├── scripts/                        # Utility scripts
│   ├── render-config.py            # Canonical YAML → Hermes config
│   ├── install-skill.sh            # Pinned-commit skill installer
│   ├── backup-export.sh            # Full volume backup
│   ├── backup-restore.sh           # Restore from backup archive
│   ├── export-config.sh            # Config-only export
│   └── healthcheck.sh              # Container health validation
│
├── config/                         # Canonical config templates (.example.yaml)
│   ├── providers/
│   │   ├── provider_registry.example.yaml
│   │   └── model_aliases.example.yaml
│   ├── mcp_registry.example.yaml
│   ├── profiles.example.yaml
│   ├── risk_policy.example.yaml
│   ├── symbol_policy.example.yaml
│   └── skills/
│       ├── wolf-strategy.example.yaml
│       ├── senpi-market-scan.example.yaml
│       └── senpi-stop-manager.example.yaml
│
├── defaults/workspace/             # First-run agent workspace content
│   ├── AGENTS.md
│   ├── BOOTSTRAP.md
│   └── USER.md
│
├── templates/
│   └── hermes-config.j2            # Jinja2 template for config generation
│
├── docker/
│   └── entrypoint.sh               # Docker SIGTERM handler
│
├── migrations/
│   └── 0001_initial_schema.sh
│
└── docs/
    ├── architecture.md
    ├── deployment.md
    ├── backup-restore.md
    ├── migration.md
    └── security.md
```

---

## Related

- [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent)
- [Senpi-ai/senpi-hyperclaw-railway-template](https://github.com/Senpi-ai/senpi-hyperclaw-railway-template)
- [Senpi.ai](https://senpi.ai)
- [Railway Volumes](https://docs.railway.com/volumes/overview)
