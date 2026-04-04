# Güvenlik Politikası

Bu doküman Hermes-Senpi Trader sisteminin güvenlik sınırlarını, riski azaltma kararlarını ve operatör sorumluluklarını açıklar.

---

## Tasarım Prensipleri

### 1. Secret'lar Sadece Env'de Yaşar

Hiçbir API key veya auth token config dosyasına, log'a veya workspace dosyasına yazılmaz. Tüm secret'lar Railway/env sistemi üzerinden gelir. Config dosyalarında yalnızca `api_key_env: ENV_VAR_NAME` referansı bulunur; değer değil.

**Denetim:** `grep -r "sk-" /data/` veya `grep -r "SENPI_" /data/workspace/` çalıştırıldığında hiçbir sonuç dönmemeli.

### 2. Execution Varsayılan Pasif

Container her zaman `ACTIVE_PROFILE=analysis` ile başlar. Execution profili:
- Elle `ACTIVE_PROFILE=execution` yapılarak açılır
- Açılırken `risk_policy.yaml` geçerlilik kontrolünden geçer
- `allow_open_new_position: false` varsayılan

### 3. Allowlist — Deny by Default

`risk_policy.yaml` içinde `symbols.default_action: deny` zorunludur. Bu alan `allow` veya boş bırakılamaz — `validate-risk.sh` bunu bloklar.

### 4. Senpi MCP Sadece Execution'da

`mcp_registry.yaml` içinde Senpi MCP `profiles: [execution]` ile sınırlandırılmıştır. Analysis profile'da Senpi MCP yüklenmez, bu nedenle analysis agent'ı hiçbir koşulda trade emri veremez.

### 5. Pinned Dependencies

- Hermes image: `FROM hermes-agent:v0.6.0` — `latest` kullanılmaz
- Skill'ler: `pinned_commit` zorunlu — branch-only kurulum `install-skill.sh` tarafından reddedilir

---

## Güvenlik Sınırları Tablosu

| Sınır | Mekanizma | Uygulayan |
|-------|-----------|-----------|
| Secret'lar loglanmaz | `redact_secrets: true` | risk_policy.yaml |
| API key config'de yok | `api_key_env:` pattern | provider_registry.yaml |
| Execution kapalı başlar | `ACTIVE_PROFILE=analysis` | Dockerfile ENV |
| Risk policy olmadan execution açılmaz | Exit 1 | validate-risk.sh |
| Allowlist dışı sembol reddedilir | `default_action: deny` | risk_policy.yaml |
| Kaldıraç limiti | `max_leverage: 3` | risk_policy.yaml |
| Senpi MCP analiz profilinde yok | `profiles: [execution]` | mcp_registry.yaml |
| Skill versiyon pinned | `pinned_commit` zorunlu | install-skill.sh |
| Container'da secret yok | Env-only | Railway Variables |
| Generated config imzasız | `_meta.generator` field | render-config.py |

---

## Operatör Sorumlulukları

### Execution Profili Açmadan Önce
1. `risk_policy.yaml` tamamlanmış ve test edilmiş olmalı
2. `dry_run_default: true` ile en az bir hafta gözlem yapılmış olmalı
3. `max_daily_loss_usd` gözden geçirilmiş olmalı
4. Allowlist sadece test edilmiş semboller içermeli

### API Key Rotasyonu
1. Railway Variables'ta key'i güncelle
2. Container'ı yeniden başlat (env'den okunur, config dosyaları değişmez)
3. Eski key'i iptal et

### Backup Güvenliği
- Backup arşivleri API key içermez (env'den gelir)
- Ama `risk_policy.yaml`, MCP registry ve workspace içerir
- Arşivleri halka açık konumda saklamayın
- `BACKUP_ENCRYPTION_PASSPHRASE` env'i ile GPG şifrelemesi eklenebilir (gelecek sürüm)

---

## Bilinen Riskler ve Mitigasyonlar

| Risk | Önem | Mitigasyon |
|------|------|-----------|
| Senpi MCP tokeni sızdığında | Kritik | Token yalnızca env'de, key rotasyonu hızlı |
| Skill repo güncellenmesi | Yüksek | pinned_commit — upstream değişimi etkisiz |
| Agent yanlış sembol önerisi | Orta | Allowlist + insan onayı zorunlu |
| Kaldıraç limiti aşıldığında | Yüksek | max_leverage hard cap, agent override edemez |
| Volume yedeksiz silinmesi | Kritik | Düzenli backup.sh + Railway native backup |
| .env dosyası git'e giderse | Kritik | .gitignore zorunlu, pre-commit hook önerilir |

---

## Güvenlik Kontrol Listesi (Deploy Öncesi)

```
[ ] .env dosyası .gitignore'da
[ ] railway.toml'da secret değer yok
[ ] risk_policy.yaml oluşturulmuş ve reviewed
[ ] ACTIVE_PROFILE=analysis (execution kapalı)
[ ] dry_run_default: true
[ ] allow_open_new_position: false
[ ] allowlist sadece hedef semboller
[ ] Senpi MCP tokeni geçerli ve Railway Variables'ta
[ ] Backup test edilmiş
```
