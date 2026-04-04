# Migration Rehberi

Bu doküman Hermes-Senpi Trader sistemini bir Railway projesinden başka bir Railway projesine veya farklı bir hosta taşıma adımlarını açıklar.

---

## Migrasyon Türleri

| Tür | Senaryo | Süre |
|-----|---------|------|
| **Volume migrasyon** | Aynı Railway hesabı, farklı proje | ~10 dk |
| **Tam host migrasyonu** | Railway → başka Railway/VPS | ~15-30 dk |
| **Config-only migrasyon** | State olmadan sadece config taşı | ~5 dk |

---

## 1. Tam Migrasyon (Önerilen)

### Adım 1: Kaynak sistemde backup al

```bash
# Railway CLI ile exec
railway run bash scripts/backup-export.sh

# Çıktı: /data/backups/exports/backup-YYYYMMDD-HHMMSS.tar.gz
```

### Adım 2: Backup dosyasını indir

Railway Volume'deki backup dosyasını local'e kopyala:
```bash
railway run cat /data/backups/exports/backup-20260404-000000.tar.gz > backup-20260404.tar.gz
```

### Adım 3: Yeni Railway projesi oluştur

```bash
railway init
railway up  # İlk deploy — volume boş başlar
```

### Adım 4: Backup dosyasını yeni sisteme yükle

```bash
cat backup-20260404.tar.gz | railway run bash -c 'cat > /tmp/restore.tar.gz && bash scripts/backup-restore.sh /tmp/restore.tar.gz'
```

### Adım 5: Env var'larını tanımla

Railway Dashboard → Variables'ta şunları tanımla:
```
OPENROUTER_API_KEY=<kaynak sistemle aynı veya yeni>
SENPI_AUTH_TOKEN=<geçerli token>
ACTIVE_PROFILE=analysis
DATA_DIR=/data
```

> **Önemli:** API key'ler backup arşivine gitmez. Her host için ayrıca tanımlanmalıdır.

### Adım 6: Redeploy ve validation

```bash
railway redeploy
```

Sistem başladığında:
1. Bootstrap volume'de backup'tan gelen dosyaları bulur
2. Migration check çalışır (schema uyumluluğu doğrulanır)
3. Gen config yeni env var'larla yeniden üretilir
4. Session'lar temizlenmiş gelir

### Adım 7: Healthcheck

```bash
railway run bash scripts/healthcheck.sh
```

Tüm kontroller geçtikten sonra `analysis` profiliyle test et.

---

## 2. Config-Only Migrasyon

State veya hafıza taşınmadan sadece config yapısı yeni ortama taşınmak istendiğinde:

```bash
# Kaynak sistem
bash scripts/export-config.sh
# → /data/backups/exports/config-YYYYMMDD.tar.gz

# Yeni sistem
bash scripts/backup-restore.sh config-YYYYMMDD.tar.gz
```

Bu yöntemde workspace (MEMORY.md, journals) taşınmaz — temiz başlangıç.

---

## 3. Schema Migration (Version Upgrade)

Hermes imajı güncellendikten sonra container yeniden başladığında `run-migrations.sh` otomatik çalışır.

### Migration dosyası ekleme

Yeni schema değişikliklerini versioned migration script olarak ekle:

```bash
# Dosya adı format: NNNN_kisa_aciklama.sh
touch migrations/0002_add_health_logs.sh
```

Script içeriği idempotent olmalı — birden fazla çalıştırılsa da güvenli.

### Rollback

Yeni image'da migration başarısız olursa:
1. Railway'de önceki deployment'ı restore et
2. Volume'de `migrations/applied.log` son satırını kontrol et
3. Sorunlu migration script'ini düzelttikten sonra redeploy

---

## Taşınan / Taşınmayan Veriler

| Veri | Full Backup | Config Export | Notlar |
|------|-------------|---------------|--------|
| Canonical config (providers, mcp, risk) | ✅ | ✅ | Her zaman taşınır |
| Skill manifest'leri | ✅ | ✅ | Installed değil |
| Workspace (AGENTS.md, USER.md) | ✅ | ❌ | Full backup'ta |
| MEMORY.md, journals | ✅ | ❌ | State |
| .hermes/sessions | ❌ | ❌ | Yenilenir |
| .hermes/cache | ❌ | ❌ | Temizlenir |
| Trade logs (audit) | ✅ | ❌ | Full backup'ta |
| API key'ler | ❌ | ❌ | ASLA — env'de |

---

## Checklist

```
[ ] Kaynak sistemde backup alındı
[ ] Backup verify edildi (tar -tzf backup.tar.gz)
[ ] Yeni sistemde Railway volume bağlı
[ ] Env var'lar tanımlandı (API key'ler dahil)
[ ] Restore çalıştırıldı
[ ] Healthcheck geçti
[ ] analysis profili ile test edildi
[ ] Kaynak sistem kapatılmadan önce execution onaylandı
```
