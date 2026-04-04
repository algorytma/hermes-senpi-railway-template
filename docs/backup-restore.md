# Backup ve Restore Rehberi

---

## Backup Türleri

| Tür | Script | İçerik | Ne zaman |
|-----|--------|---------|----------|
| **Tam backup** | `backup-export.sh` | Config + workspace + logs/audit | Deploy öncesi, haftalık |
| **Config backup** | `export-config.sh` | Sadece canonical config | Config değişikliği öncesi |

---

## Tam Backup Al

```bash
# Railway'de
railway run bash scripts/backup-export.sh

# Çıktı
# /data/backups/exports/backup-YYYYMMDD-HHMMSS.tar.gz
# /data/backups/manifests/manifest-YYYYMMDD-HHMMSS.json
```

Backup içeriği:
- `.hermes/` (session ve cache hariç)
- `workspace/`
- `providers/`
- `mcp/` (mcp_registry.yaml)
- `skills/` (manifests)
- `risk/`

## Config-Only Backup

```bash
railway run bash scripts/export-config.sh
```

Sadece canonical YAML dosyaları — state, log ve workspace dahil değil.

---

## Backup Doğrulama

```bash
# Arşiv içeriğini listele
tar -tzf backup-20260404-000000.tar.gz | head -50

# Manifest'i oku
cat /data/backups/manifests/manifest-20260404-000000.json
```

---

## Restore

```bash
railway run bash scripts/backup-restore.sh /data/backups/exports/backup-20260404-000000.tar.gz
```

Restore sonrası otomatik olarak:
- Session'lar temizlenir
- Generated config'ler silinir (sonraki boot'ta yeniden üretilir)
- Migration check tetiklenir

Sonra container'ı yeniden başlatın:
```bash
railway redeploy
```

---

## Zamanlanmış Backup (Opsiyonel)

Railway Cron veya harici bir scheduler ile düzenli backup:

```bash
# Örnek: her gece 02:00'de
0 2 * * * railway run bash /app/scripts/backup-export.sh
```

---

## Railway Native Backup

Railway, volume'lar için platform seviyesinde backup da sunuyor:

Railway Dashboard → Storage → Volume → Backups → Create Backup

Bu yöntem platform bağımlıdır. Taşınabilirlik için `backup-export.sh` kullanımı önerilir.
