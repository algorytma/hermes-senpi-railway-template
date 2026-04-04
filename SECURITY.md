# Security Policy

This document describes the security model of the **hermes-senpi-trader** Railway template, including security boundaries, threat mitigations, and the operator pre-deploy checklist.

---

## Security Architecture

### Layer 1 — Secrets Isolation

All API keys, auth tokens, and credentials exist **only in env vars** (Railway Variables). No secret value is ever written to:
- Config YAML files (only env var *names* appear, e.g. `api_key_env: OPENROUTER_API_KEY`)
- Log files (scripts avoid echoing resolved secret values)
- Workspace markdown files
- Backup archives

**Verification:** After deploy, run:
```bash
grep -r "sk-" /data/ 2>/dev/null    # should return nothing
grep -r "senpi" /data/mcp/ 2>/dev/null  # should only show config keys, not token values
```

### Layer 2 — Execution Default-Off

The execution profile (which can place real trades) is **disabled by default**:

| Safeguard | Location | Default |
|-----------|----------|---------|
| Profile selection | `ACTIVE_PROFILE` env var | `analysis` |
| New position opening | `risk_policy.yaml` | `allow_open_new_position: false` |
| All actions dry-run | `risk_policy.yaml` | `dry_run_default: true` |
| Human approval mode | `risk_policy.yaml` | `mode: copilot` |

The execution profile cannot start unless `risk_policy.yaml` passes full validation (`bootstrap/validate-risk.sh`).

### Layer 3 — Senpi MCP Isolation

The Senpi MCP server (which connects to Hyperliquid via the Senpi platform) is registered with:

```yaml
profiles: [execution]          # NEVER loads in analysis profile
requires_confirmation: true    # Each tool call triggers a confirmation prompt
```

This means the analysis agent **physically cannot** call Senpi trading APIs, regardless of prompt content.

### Layer 4 — Symbol Allowlist (`deny` by default)

```yaml
symbols:
  allowlist: ["BTC", "ETH", "SOL"]
  default_action: deny   # ALL other symbols rejected — validation enforces this
```

`validate-risk.sh` exits with an error if `default_action` is not `deny`. There is no way to accidentally trade an unlisted symbol.

### Layer 5 — Pinned Dependencies

- **Hermes image**: `FROM ghcr.io/nousresearch/hermes-agent:${HERMES_VERSION}` — `latest` is never used
- **Skills**: `pinned_commit` is mandatory in skill manifests; `install-skill.sh` rejects branch-only or placeholder values
- **MCP servers**: `npx -y` with versioned package names (no `@latest`)

---

## Threat Model

### In-Scope Threats

| Threat | Mitigation |
|--------|-----------|
| Leaked API key from config file | Keys stored only in env vars; `api_key_env:` pattern enforced |
| Agent opens unauthorized trade | Execution profile off by default; `allow_open_new_position: false` |
| Agent trades non-allowlist symbol | `default_action: deny` enforced by validation |
| Malicious skill code injection | `pinned_commit` required; skills are read-only git clones |
| Analysis agent triggers execution | Senpi MCP excluded from analysis profile via `profiles` field |
| Backup exposes credentials | Backup script excludes generated configs; env vars never land on disk |
| Schema migration data corruption | Migrations tracked in `applied.log`; idempotent by design |
| Container compromise → data loss | Volume persists independently; container is disposable |
| Supply chain: Hermes image tampering | Pinned digest via `HERMES_VERSION` build arg; operator verifies tag |

### Out-of-Scope Threats

- Railway platform-level compromise (trust Railway's security)
- Senpi platform vulnerabilities (trust Senpi's security)
- Network-level attacks between Railway service and external APIs

---

## Operator Security Checklist

Run through this list before your first deployment and before enabling execution:

### Pre-Deploy

```
[ ] .env file is in .gitignore and has NOT been committed to git
[ ] railway.toml contains no secret values — only variable names
[ ] All API keys set via Railway Variables (Dashboard → Variables)
[ ] ACTIVE_PROFILE=analysis (execution is opt-in)
[ ] SENPI_AUTH_TOKEN is valid and not shared across projects
```

### Before Enabling Execution

```
[ ] /data/risk/risk_policy.yaml reviewed and intentionally configured
[ ] dry_run_default: true (test with dry run first)
[ ] allow_open_new_position: false (open manually when ready)
[ ] mode: copilot (human approval for all actions)
[ ] symbols.allowlist contains only intended symbols
[ ] symbols.default_action: deny
[ ] max_daily_loss_usd is set to an acceptable loss ceiling
[ ] max_leverage does not exceed your risk tolerance
[ ] Backup taken and verified before switching to execution
```

### Before Live Trading (dry_run: false)

```
[ ] At least 1 week of analysis testing completed
[ ] Dry-run execution tested and outcomes reviewed
[ ] Risk policy limits verified against actual portfolio size
[ ] SENPI_AUTH_TOKEN confirmed to have trading permissions
[ ] Telegram or alert channel configured for trade notifications
[ ] Rollback plan documented: Railway Deployments → Rollback
```

---

## API Key Rotation

When rotating a provider API key:

1. Set the new key in Railway Variables (replace the value)
2. Redeploy — the container picks up the new env var
3. No config files need to be changed
4. Revoke the old key immediately after confirming the new one works

When rotating `SENPI_AUTH_TOKEN`:

1. Set the new token in Railway Variables
2. Redeploy
3. Verify analysis profile boots cleanly (check `scripts/healthcheck.sh`)
4. If using execution profile, verify Senpi MCP connects before opening trades

---

## Backup Security

Backup archives (`.tar.gz`) produced by `scripts/backup-export.sh` contain:
- ✅ Canonical config YAML (providers, mcp registry, risk policy)
- ✅ Workspace content (AGENTS.md, USER.md, MEMORY.md, journals)
- ✅ Skill manifests
- ✅ Trade audit logs
- ❌ API keys (never on disk)
- ❌ Generated configs (regenerated from env on restore)
- ❌ Session state (cleared on restore)
- ❌ Auth tokens (never on disk)

**Store backup archives in a private, access-controlled location.** While they don't contain API keys, they contain your trading strategy config and audit history.

Optional: Set `BACKUP_ENCRYPTION_PASSPHRASE` for GPG-encrypted archives (planned feature).

---

## Reporting Security Issues

If you discover a security vulnerability in this template, please open a **private** GitHub Security Advisory rather than a public issue:

GitHub → Repository → Security tab → Report a vulnerability

Do not post vulnerability details in public issues or discussions.

---

## Audit References

This security model is informed by:
- [OpenClaw Security Guidance](https://docs.openclaw.ai/gateway/security)
- [Senpi-ai/senpi-hyperclaw-railway-template Security](https://github.com/Senpi-ai/senpi-hyperclaw-railway-template/blob/main/SECURITY.md)
- [Railway Volumes Documentation](https://docs.railway.com/volumes/overview)
- [NousResearch Hermes Agent](https://github.com/NousResearch/hermes-agent)
