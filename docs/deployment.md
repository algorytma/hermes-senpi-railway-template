# Deployment Rehberi

Bu doküman Hermes-Senpi Trader'ı Railway'e sıfırdan deploy etme adımlarını açıklar.

---

## Ön Koşullar

- Railway hesabı ve CLI (`npm install -g @railway/cli`)
- Aşağıdaki API key'ler hazır:
  - `OPENROUTER_API_KEY` (zorunlu)
  - `SENPI_AUTH_TOKEN` (execution için zorunlu)

---

## 1. Repository Hazırlığı

```bash
git clone https://github.com/YOUR_ORG/hermes-senpi-trader
cd hermes-senpi-trader
cp .env.example .env
# .env'i düzenle — test için en az OPENROUTER_API_KEY ekle
```

## 2. Railway Projesi Oluştur

```bash
railway login
railway init
```

### Volume ekle (zorunlu)

Railway Dashboard → Storage → Add Volume:
- Mount Path: `/data`
- Size: 5 GB (başlangıç)

### Env var'ları tanımla

Railway Dashboard → Variables:

```
ACTIVE_PROFILE=analysis
DATA_DIR=/data
HERMES_VERSION=v0.6.0
OPENROUTER_API_KEY=sk-or-...
SENPI_AUTH_TOKEN=senpi-...
```

## 3. İlk Deploy

```bash
railway up
```

İlk başlangıçta bootstrap şunları yapar:
1. `/data` klasör yapısını oluşturur
2. `defaults/` içindeki config şablonlarını `/data` altına kopyalar
3. `render-config.py` ile generated config'leri üretir
4. Analysis profili ile Hermes'i başlatır

## 4. Doğrulama

```bash
# Healthcheck
railway run bash scripts/healthcheck.sh

# Log'lara bak
railway logs
```

## 5. Config Özelleştirmesi

Volume'deki canonical config dosyalarını kendi ihtiyaçlarınıza göre düzenleyin:

```bash
# Railway exec ile
railway run nano /data/providers/provider_registry.yaml
railway run nano /data/risk/risk_policy.yaml
```

Değişiklik sonrası container'ı yeniden başlatın (config otomatik regenerate edilir).

## 6. Execution Profiline Geçiş

> ⚠️ Bunu sadece analiz testi tamamlandıktan sonra yapın.

1. `risk_policy.yaml`'ı review edin
2. Railway Variables'ta `ACTIVE_PROFILE=execution` yapın
3. `SENPI_AUTH_TOKEN` geçerli mi kontrol edin
4. Redeploy edin

---

## Günceleme (Image Upgrade)

```bash
# railway.toml'da HERMES_VERSION'ı güncelle
# Backup al
railway run bash scripts/backup-export.sh

# Yeni versiyonu deploy et
railway up

# Migration otomatik çalışır
# Healthcheck
railway run bash scripts/healthcheck.sh
```

## Rollback

Railway Dashboard → Deployments → önceki deployment → Rollback
