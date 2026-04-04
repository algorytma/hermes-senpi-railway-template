# Mimari

Bu doküman Hermes-Senpi Trader'ın teknik mimarisini açıklar.

---

## Katmanlar

```
┌─────────────────────────────────────────────┐
│  Railway Service: hermes-senpi-trader        │
│                                             │
│  docker/entrypoint.sh                       │
│       └─▶ bootstrap/prestart.sh             │
│               ├── init-volume.sh            │
│               ├── validate-risk.sh          │
│               ├── run-migrations.sh         │
│               └── render-config.py          │
│                       └─▶ hermes runtime    │
│                                             │
│  /data (Railway Persistent Volume)          │
│  ├── .hermes/analysis/   HERMES_HOME(ana)  │
│  ├── .hermes/execution/  HERMES_HOME(exec) │
│  ├── workspace/                            │
│  ├── providers/   ← CANONICAL              │
│  ├── mcp/         ← CANONICAL + GENERATED  │
│  ├── skills/      ← CANONICAL              │
│  └── risk/        ← CANONICAL              │
└─────────────────────────────────────────────┘
```

## Config Akışı

```
Env vars (secret)
    │
    ├─ providers/provider_registry.yaml  ──┐
    ├─ providers/model_aliases.yaml        │
    ├─ mcp/mcp_registry.yaml              ├▶ render-config.py
    ├─ config/profiles.yaml               │
    └─ risk/risk_policy.yaml           ───┘
                                           │
                          ┌────────────────┴──────────────────┐
                          │                                   │
              .hermes/analysis/             .hermes/execution/
              config.generated.yaml         config.generated.yaml
                          │                                   │
                     hermes (analysis)               hermes (execution)
```

## İki Profil, Bir Container

| | Analysis | Execution |
|-|----------|-----------|
| `HERMES_HOME` | `/data/.hermes/analysis` | `/data/.hermes/execution` |
| Senpi MCP | ❌ Kapalı | ✅ Açık |
| Trade execution | ❌ | ✅ (risk policy koşullu) |
| Default alias | `analysis-deep` | `trade-safe` |
| Başlatma | Varsayılan | Elle `ACTIVE_PROFILE=execution` |

## Canonical vs Generated

| Dosya | Tür | Kim Düzenler |
|-------|-----|-------------|
| `providers/*.yaml` | CANONICAL | Operatör |
| `mcp/mcp_registry.yaml` | CANONICAL | Operatör |
| `skills/manifests/*.yaml` | CANONICAL | Operatör |
| `risk/*.yaml` | CANONICAL | Operatör |
| `workspace/AGENTS.md` | CANONICAL | Operatör |
| `.hermes/*/config.generated.yaml` | GENERATED | render-config.py |
| `mcp/mcp.generated.yaml` | GENERATED | render-config.py |
| `workspace/MEMORY.md` | GENERATED | Hermes agent |
