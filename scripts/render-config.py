#!/usr/bin/env python3
"""
scripts/render-config.py — Canonical YAML → Hermes Generated Config

Canonical kaynaklardan (provider_registry, model_aliases, mcp_registry,
risk_policy) okuyarak Hermes runtime'ının tüketeceği config.generated.yaml
ve mcp.generated.yaml dosyalarını üretir.

Kullanım:
  python3 render-config.py \\
    --profile analysis \\
    --data-dir /data \\
    --hermes-home /data/.hermes/analysis \\
    --output-hermes /data/.hermes/analysis/config.generated.yaml \\
    --output-mcp /data/mcp/mcp.generated.yaml
"""

import argparse
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path
from string import Template
from typing import Any

try:
    import yaml
except ImportError:
    print("HATA: pyyaml yüklü değil. pip install pyyaml", file=sys.stderr)
    sys.exit(1)


# ---------------------------------------------------------------------------
# Yardımcılar
# ---------------------------------------------------------------------------

def log(msg: str) -> None:
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{ts}] [CONF ] {msg}")


def err(msg: str) -> None:
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{ts}] [CONF ] ERROR: {msg}", file=sys.stderr)


def load_yaml(path: Path) -> dict:
    """YAML dosyasını yükle; yoksa boş dict döndür."""
    if not path.exists():
        log(f"  UYARI: Dosya bulunamadı, atlanıyor: {path}")
        return {}
    with open(path) as f:
        result = yaml.safe_load(f) or {}
    return result


def resolve_env(value: str) -> str:
    """${VAR_NAME} formatındaki env referanslarını çöz."""
    if not isinstance(value, str):
        return value
    if value.startswith("${") and value.endswith("}"):
        env_var = value[2:-1]
        resolved = os.environ.get(env_var, "")
        if not resolved:
            log(f"  UYARI: Env var bulunamadı veya boş: {env_var}")
        return resolved
    return value


def resolve_env_in_dict(d: dict) -> dict:
    """Dict içindeki tüm ${VAR} referanslarını özyinelemeli çöz."""
    result = {}
    for k, v in d.items():
        if isinstance(v, dict):
            result[k] = resolve_env_in_dict(v)
        elif isinstance(v, str):
            result[k] = resolve_env(v)
        else:
            result[k] = v
    return result


# ---------------------------------------------------------------------------
# Provider çözümleyici
# ---------------------------------------------------------------------------

def build_provider_map(registry: dict, aliases: dict) -> dict:
    """
    provider_registry + model_aliases → Hermes provider/model config.
    Hermes config formatı: provider adı + model + api_key + base_url
    """
    providers = registry.get("providers", {})
    alias_map = aliases.get("aliases", {})
    resolved = {}

    for alias_name, alias_cfg in alias_map.items():
        provider_name = alias_cfg.get("provider")
        model = alias_cfg.get("model")

        if not provider_name or not model:
            log(f"  UYARI: Alias '{alias_name}' provider veya model içermiyor — atlandı")
            continue

        provider = providers.get(provider_name, {})
        if not provider.get("enabled", True):
            log(f"  ~ Devre dışı provider '{provider_name}' için alias '{alias_name}' atlandı")
            continue

        # API key çöz
        api_key_env = provider.get("api_key_env", "")
        api_key = os.environ.get(api_key_env, "") if api_key_env else ""

        # Base URL çöz
        base_url = provider.get("base_url", "")
        if not base_url:
            base_url_env = provider.get("base_url_env", "")
            base_url = os.environ.get(base_url_env, "") if base_url_env else ""

        resolved[alias_name] = {
            "provider": provider_name,
            "model": model,
            "base_url": base_url,
            "api_key": api_key,
            "max_tokens": alias_cfg.get("max_tokens", 4096),
            "temperature": alias_cfg.get("temperature", 0.3),
        }
        log(f"  ✓ Alias çözümlendi: {alias_name} → {provider_name}/{model}")

    return resolved


# ---------------------------------------------------------------------------
# MCP config üretici
# ---------------------------------------------------------------------------

def build_mcp_config(registry: dict, profile: str) -> dict:
    """
    mcp_registry.yaml + ACTIVE_PROFILE → mcp_servers dict (Hermes formatı).
    Sadece ilgili profile'daki ve enabled=true olan sunucular dahil edilir.
    """
    servers = registry.get("servers", {})
    result = {}

    for server_name, server_cfg in servers.items():
        if not server_cfg.get("enabled", True):
            log(f"  ~ MCP '{server_name}' devre dışı — atlandı")
            continue

        profiles = server_cfg.get("profiles", ["analysis", "execution"])
        if profile not in profiles:
            log(f"  ~ MCP '{server_name}' bu profile dahil değil ({profile}) — atlandı")
            continue

        # Env var'ları çöz
        env_raw = server_cfg.get("env", {})
        env_resolved = resolve_env_in_dict(env_raw) if env_raw else {}

        # Boş env değerlerini temizle (env var yoksa Hermes'e verme)
        env_clean = {k: v for k, v in env_resolved.items() if v}

        hermes_entry = {
            "transport": server_cfg.get("transport", "stdio"),
            "command": server_cfg.get("command", ""),
            "args": server_cfg.get("args", []),
        }
        if env_clean:
            hermes_entry["env"] = env_clean

        result[server_name] = hermes_entry
        log(f"  ✓ MCP dahil edildi: {server_name} [risk={server_cfg.get('risk_level', '?')}]")

    return result


# ---------------------------------------------------------------------------
# Hermes config.generated.yaml üretici
# ---------------------------------------------------------------------------

def render_hermes_config(
    profile: str,
    provider_map: dict,
    mcp_servers: dict,
    hermes_home: Path,
    workspace_dir: Path,
    data_dir: Path,
) -> dict:
    """
    Hermes'in beklediği config formatını üret.
    Referans: https://github.com/NousResearch/hermes-agent
    """

    # Default model alias'ı belirle
    if profile == "execution":
        default_alias = "trade-safe"
    else:
        default_alias = "analysis-deep"

    default_provider = provider_map.get(default_alias, {})

    config = {
        # --- Bu dosya, bootstrap tarafından üretilmiştir. Elle düzenleme ---
        # --- Değişiklik yapmak için canonical YAML dosyalarını düzenle  ---
        "model": default_provider.get("model", ""),
        "provider": default_provider.get("provider", "openrouter"),
        "base_url": default_provider.get("base_url", "https://openrouter.ai/api/v1"),
        "api_key": default_provider.get("api_key", ""),
        "workspace": str(workspace_dir),
        "mcp_servers": mcp_servers,
        # Profil bazlı extra metadata
        "_meta": {
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "profile": profile,
            "hermes_home": str(hermes_home),
            "generator": "render-config.py",
            "canonical_sources": [
                "providers/provider_registry.yaml",
                "providers/model_aliases.yaml",
                "mcp/mcp_registry.yaml",
            ],
        },
    }

    # Boş değerleri temizle
    config = {k: v for k, v in config.items() if v != "" and v is not None}

    return config


# ---------------------------------------------------------------------------
# MCP standalone generated yaml
# ---------------------------------------------------------------------------

def render_mcp_generated(profile: str, mcp_servers: dict) -> dict:
    return {
        "_meta": {
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "profile": profile,
            "generator": "render-config.py",
        },
        "mcp_servers": mcp_servers,
    }


# ---------------------------------------------------------------------------
# Ana giriş noktası
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(description="Hermes-Senpi Config Renderer")
    parser.add_argument("--profile", default="analysis",
                        choices=["analysis", "execution"],
                        help="Aktif agent profili")
    parser.add_argument("--data-dir", default="/data",
                        help="Volume kök dizini")
    parser.add_argument("--hermes-home", default=None,
                        help="HERMES_HOME dizini (varsayılan: data-dir/.hermes/profile)")
    parser.add_argument("--output-hermes", default=None,
                        help="Hermes config çıktı yolu")
    parser.add_argument("--output-mcp", default=None,
                        help="MCP generated config çıktı yolu")
    parser.add_argument("--dry-run", action="store_true",
                        help="Dosyaya yazmadan stdout'a bas")
    args = parser.parse_args()

    data_dir = Path(args.data_dir)
    profile = args.profile

    hermes_home = Path(args.hermes_home) if args.hermes_home else \
                  data_dir / ".hermes" / profile

    output_hermes = Path(args.output_hermes) if args.output_hermes else \
                    hermes_home / "config.generated.yaml"

    output_mcp = Path(args.output_mcp) if args.output_mcp else \
                 data_dir / "mcp" / "mcp.generated.yaml"

    workspace_dir = data_dir / "workspace"

    log(f"Config renderer başlıyor (profile={profile})")
    log(f"  data_dir    : {data_dir}")
    log(f"  hermes_home : {hermes_home}")
    log(f"  output      : {output_hermes}")
    log(f"  mcp output  : {output_mcp}")

    # ---------------------------------------------------------------------------
    # Canonical dosyaları yükle
    # ---------------------------------------------------------------------------
    log("Canonical config dosyaları yükleniyor...")
    provider_registry = load_yaml(data_dir / "providers" / "provider_registry.yaml")
    model_aliases     = load_yaml(data_dir / "providers" / "model_aliases.yaml")
    mcp_registry      = load_yaml(data_dir / "mcp" / "mcp_registry.yaml")

    # ---------------------------------------------------------------------------
    # Provider map oluştur
    # ---------------------------------------------------------------------------
    log("Provider alias'ları çözümleniyor...")
    provider_map = build_provider_map(provider_registry, model_aliases)

    if not provider_map:
        err("Hiç geçerli provider alias çözümlenemedi. provider_registry.yaml ve "
            "model_aliases.yaml dosyalarını ve env var'larını kontrol edin.")
        sys.exit(1)

    # ---------------------------------------------------------------------------
    # MCP config oluştur
    # ---------------------------------------------------------------------------
    log(f"MCP sunucuları filtreleniyor (profile={profile})...")
    mcp_servers = build_mcp_config(mcp_registry, profile)

    if not mcp_servers:
        log("UYARI: Bu profil için aktif MCP sunucusu bulunamadı.")

    # ---------------------------------------------------------------------------
    # Hermes config üret
    # ---------------------------------------------------------------------------
    log("Hermes config.generated.yaml üretiliyor...")
    hermes_config = render_hermes_config(
        profile=profile,
        provider_map=provider_map,
        mcp_servers=mcp_servers,
        hermes_home=hermes_home,
        workspace_dir=workspace_dir,
        data_dir=data_dir,
    )

    mcp_config = render_mcp_generated(profile, mcp_servers)

    # ---------------------------------------------------------------------------
    # Yaz veya stdout'a bas
    # ---------------------------------------------------------------------------
    if args.dry_run:
        log("--- DRY RUN: config.generated.yaml ---")
        print(yaml.dump(hermes_config, allow_unicode=True, default_flow_style=False))
        log("--- DRY RUN: mcp.generated.yaml ---")
        print(yaml.dump(mcp_config, allow_unicode=True, default_flow_style=False))
    else:
        output_hermes.parent.mkdir(parents=True, exist_ok=True)
        with open(output_hermes, "w") as f:
            f.write("# GENERATED — Elle düzenleme. render-config.py tarafından üretildi.\n")
            f.write(f"# Profile: {profile} | {datetime.now(timezone.utc).isoformat()}\n\n")
            yaml.dump(hermes_config, f, allow_unicode=True, default_flow_style=False)
        log(f"✓ Yazıldı: {output_hermes}")

        output_mcp.parent.mkdir(parents=True, exist_ok=True)
        with open(output_mcp, "w") as f:
            f.write("# GENERATED — Elle düzenleme. render-config.py tarafından üretildi.\n")
            f.write(f"# Profile: {profile} | {datetime.now(timezone.utc).isoformat()}\n\n")
            yaml.dump(mcp_config, f, allow_unicode=True, default_flow_style=False)
        log(f"✓ Yazıldı: {output_mcp}")

    log("Config renderer tamamlandı ✓")


if __name__ == "__main__":
    main()
