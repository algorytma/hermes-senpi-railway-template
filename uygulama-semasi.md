<img src="https://r2cdn.perplexity.ai/pplx-full-logo-primary-dark%402x.png" style="height:64px;margin-right:32px"/>

# Uygulama notu kısmındaki gibi ilerleyelim. 2 aşamalı, şimdi 1. aşama için gerekenlere başla,

Tamam, 1. aşamada kod yazdırmaya başlamadan önce **mimari kararları, klasör ağacını, config yüzeyini ve operasyon kurallarını** netleştireceğiz. Bu yaklaşım doğru çünkü OpenClaw/Hermes benzeri yapılarda asıl kırılma noktası genelde kod değil; state, workspace, MCP kayıtları ve update/migration akışının baştan tasarlanmamış olmasıdır.[^1][^2][^3]

## 1. aşamanın hedefi

Bu aşamada üretilecek şeyler:

- hedef **mimari tanımı**
- kalıcı veri için **`/data` klasör standardı**
- **provider registry** tasarımı
- **MCP registry** tasarımı
- **skill manifest** tasarımı
- **risk policy** tasarımı
- **deploy / update / backup / migration** akışı
- Antigravity’nin 2. aşamada kod üretirken izleyeceği net spesifikasyon[^4][^5][^1]

Bu aşamada henüz gerçek app kodu yazdırmıyoruz; sadece kodun oturacağı sözleşmeyi oluşturuyoruz. Böylece sonraki aşamada ajan “rastgele template genişletmek” yerine, senin sistem tasarımına uyan bir foundation üretir.[^6][^7]

## Önerilen mimari

Temel model şu olmalı: **ephemeral container + stateful `/data` volume + declarative config + exportable workspace**. OpenClaw Railway dokümanı state ve workspace’in `/data/.openclaw` ve `/data/workspace` altında tutulmasını öneriyor; ayrıca `/setup` tabanlı wrapper desenleri de taşınabilirlik için bu ayrımı kullanıyor.[^3][^1]

Bunu Hermes tarafına uyarlarsak:

- **runtime layer**: Hermes/OpenClaw binary veya image, pinned version
- **control layer**: geçici setup/admin yüzeyi
- **config layer**: provider, MCP, risk, skills manifest dosyaları
- **workspace layer**: ajan davranışını etkileyen markdown/yaml dosyaları
- **execution layer**: trading tool’lar ve Senpi MCP
- **backup/migration layer**: export, restore, snapshot, health validation[^5][^8][^1]

Benim önerim, sistemi tek parça değil iki mantıksal role ayırmak:

- **analysis agent**: veri toplar, yorumlar, öneri üretir
- **execution agent**: sadece izinli trade aksiyonlarını uygular

Gerçekte bunlar tek deploy içinde iki profile olarak da başlayabilir; ama config seviyesinde ayrılmış olmalı. Bu, ileride güvenliği sertleştirmeyi kolaylaştırır.[^9][^10]

## `/data` klasör standardı

OpenClaw docs workspace’i agent’ın “home” alanı, state dizinini de config/credentials/sessions alanı olarak ayırıyor; bu ayrımı aynen korumak en sağlıklısıdır. Benim önerdiğim kalıcı dizin yapısı:[^2]

```text
/data
  /.runtime
    version.json
    build-info.json
    migrations/
  /.hermes
    config.generated.yaml
    secrets.refs.yaml
    sessions/
    auth/
    cache/
  /workspace
    AGENTS.md
    BOOTSTRAP.md
    MEMORY.md
    USER.md
    skills/
    prompts/
    journals/
  /providers
    provider_registry.yaml
    model_aliases.yaml
  /mcp
    mcp_registry.yaml
    mcp.generated.yaml
  /skills
    manifests/
    installed/
    registry-cache/
  /risk
    risk_policy.yaml
    symbol_policy.yaml
  /logs
    gateway/
    audit/
    trades/
    setup/
  /backups
    manifests/
    exports/
    snapshots/
  /tmp
```

Bu yapının mantığı:

- **`.hermes`** sadece runtime/config/session
- **workspace** sadece ajan hafızası ve davranış metinleri
- **providers/mcp/skills/risk** ayrı deklaratif kontrol düzlemleri
- **backups** taşınabilir arşivler
- **logs** inceleme ve audit için ayrı[^1][^2][^3]


## Config yüzeyi

Aşama 1’de kesinleştirmemiz gereken en önemli şey, config’in “tek büyük env dosyası” olmaması. Env sadece secret ve deployment wiring için kullanılmalı; gerçek davranış ise YAML dosyalarında tutulmalı. Bu desen, dosyaları volume üstünde tutarak image update’lerinden bağımsız hale getirir.[^11][^1]

Önerilen ana config dosyaları:

- `/data/providers/provider_registry.yaml`
- `/data/providers/model_aliases.yaml`
- `/data/mcp/mcp_registry.yaml`
- `/data/skills/manifests/*.yaml`
- `/data/risk/risk_policy.yaml`
- `/data/.hermes/config.generated.yaml`

Burada `config.generated.yaml` canonical kaynak değil, **üretilmiş çıktı** olmalı. Canonical kaynak yukarıdaki registry dosyaları olur; bootstrap/prestart script her açılışta bunlardan Hermes/OpenClaw uyumlu final config’i üretir.[^12][^11]

## Provider registry spesifikasyonu

Senin hedeflerin için provider katmanı alias tabanlı olmalı. Yani ajan doğrudan `deepseek-v3` veya `qwen-max` çağırmak yerine `trade-fast`, `trade-safe`, `reasoning-max`, `research-cheap` gibi canonical alias’lar kullanmalı. Böylece yarın provider değişince prompt ve workflow bozulmaz.[^13]

Önerilen alanlar:

```yaml
providers:
  openrouter:
    type: openai_compatible
    base_url: https://openrouter.ai/api/v1
    api_key_env: OPENROUTER_API_KEY
    enabled: true
  nvidia_nim:
    type: openai_compatible
    base_url: https://integrate.api.nvidia.com/v1
    api_key_env: NVIDIA_API_KEY
    enabled: true
  opencode:
    type: openai_compatible
    base_url_env: OPENCODE_BASE_URL
    api_key_env: OPENCODE_API_KEY
    enabled: true
  dashscope:
    type: openai_compatible
    base_url_env: DASHSCOPE_BASE_URL
    api_key_env: DASHSCOPE_API_KEY
    enabled: false
```

Ve ayrı alias dosyası:

```yaml
aliases:
  general-fast:
    provider: openrouter
    model: openai/gpt-4.1-mini
  trade-fast:
    provider: dashscope
    model: qwen-max
  trade-safe:
    provider: openrouter
    model: anthropic/claude-3.7-sonnet
  reasoning-max:
    provider: openrouter
    model: deepseek/deepseek-r1
```

Bu yapı sana hem OpenRouter, hem NIM, hem OpenAI-compatible gateway, hem de Çinli model sağlayıcıları tek düzlemde yönetme imkânı verir.[^13]

## MCP registry spesifikasyonu

Hermes tarafında MCP’ler genellikle komut/arg/env tabanlı tanımlanıyor; benzer örneklerde `~/.hermes/config.yaml` içine `mcp_servers.<name>` blokları ekleniyor. Ancak bunu elle değil registry’den üretmek daha doğru.[^14][^12]

Önerilen format:

```yaml
servers:
  senpi:
    enabled: true
    transport: stdio
    command: npx
    args: ["-y", "@senpi-ai/mcp-server"]
    env:
      SENPI_AUTH_TOKEN: ${SENPI_AUTH_TOKEN}
    tags: ["trading", "hyperliquid", "senpi"]
    risk_level: high
  filesystem_local:
    enabled: true
    transport: stdio
    command: npx
    args: ["-y", "@modelcontextprotocol/server-filesystem", "/data/workspace"]
    tags: ["local", "filesystem"]
    risk_level: medium
```

Ek alanlar:

- `enabled`
- `transport`
- `command`
- `args`
- `env`
- `tags`
- `risk_level`
- `profiles` (`analysis`, `execution`)
- `requires_confirmation`[^11][^12]

Böylece execution profile için yalnızca izinli MCP’leri aktif edebilirsin.

## Skill manifest spesifikasyonu

`senpi-agent-skills` ve `senpi-skills` gibi repolar bize skill’lerin bağımsız yaşam döngüsü olması gerektiğini gösteriyor. Bu yüzden skill sistemi git clone değil, manifest tabanlı olmalı.[^15][^16]

Örnek manifest:

```yaml
name: wolf-strategy
source:
  repo_url: https://github.com/Senpi-ai/senpi-skills
  branch: main
  pinned_commit: abcdef1234567890
  subpath: wolf-strategy
install:
  target_dir: /data/skills/installed/wolf-strategy
  link_into_workspace: /data/workspace/skills/wolf-strategy
policy:
  enabled: false
  profile: analysis
  requires_human_approval: true
metadata:
  category: trading
  risk: high
  installed_at: null
```

Bu yapı sayesinde:

- skill sürümü pinlenir
- kurulduğu yer bellidir
- workspace’e nasıl bağlandığı nettir
- execution’da mı analysis’te mi çalışacağı belirlenir[^16][^15]


## Risk policy spesifikasyonu

Senin use-case’inde risk config’i “opsiyonel dosya” değil, sistemin merkezidir. Bu dosya olmadan execution açılmamalı. Önerilen ilk şema:

```yaml
mode: copilot
portfolio:
  max_daily_loss_usd: 100
  max_daily_loss_pct: 2
  max_open_positions: 3
  max_gross_exposure_usd: 1500
trading:
  max_position_size_usd: 300
  max_leverage: 3
  cooldown_seconds_after_loss: 1800
  require_human_approval_for:
    - market_open
    - leverage_gt_2
    - new_symbol
symbols:
  allowlist: ["BTC", "ETH", "SOL"]
  denylist: []
execution:
  dry_run_default: true
  allow_reduce_only_without_confirmation: true
  allow_open_new_position: false
audit:
  write_trade_journal: true
  write_decision_trace: true
```

Başlangıçta `mode: copilot` ve `allow_open_new_position: false` ile başlamanı öneririm. Sonra yarı otonom moda geçersin.[^9]

## Faz 1 teslimat listesi

1. **Mimari karar dokümanı**
2. **Klasör ağacı**
3. **Canonical config dosya listesi**
4. **Provider registry şeması**
5. **MCP registry şeması**
6. **Skill manifest şeması**
7. **Risk policy şeması**
8. **Deploy/update/backup/migration akışı**
9. **Aşama 2 için Antigravity “architecture-only” prompt’u**

Aşağıda Aşama 1 için verilecek prompt’u hazırladım.

## Antigravity prompt — Aşama 1

```text
Sen kıdemli bir AI infrastructure ve agent systems mimarısın.

Görevin: Railway üzerinde çalışacak, persistent-volume-first, taşınabilir, güncelleme-dostu, çoklu model sağlayıcılı ve Senpi MCP/skills destekli bir Hermes/OpenClaw trading agent sistemi için SADECE 1. AŞAMA mimari spesifikasyonu hazırlamak.

ÖNEMLİ SINIR
- Bu aşamada gerçek uygulama kodu yazma.
- Dockerfile, app server, UI kodu, backend kodu, bot kodu üretme.
- Sadece mimari, klasör yapısı, config sözleşmeleri, operasyon planı ve ikinci aşama için net teknik spesifikasyon üret.

HEDEF
Aşağıdaki ihtiyaçları karşılayan production-grade foundation tasarla:
- Railway üzerinde çalışsın
- Persistent volume `/data` merkezli olsun
- Update sonrası state kaybı yaşanmasın
- Başka sunucuya hızlı taşınabilsin
- OpenRouter, OpenAI-compatible provider’lar, NVIDIA NIM ve Çinli model sağlayıcıları desteklenebilsin
- Senpi MCP entegre edilebilsin
- Senpi skill repo/manifest mantığı desteklenebilsin
- Gerçek fon yönetimi için güvenli temelleri olsun
- Analysis ve execution rollerini ayrıştırmaya uygun olsun

ÇIKTI FORMATIN
Yanıtını aşağıdaki başlıklarla ver:

1. System Goals
2. Architectural Principles
3. Recommended Runtime Topology
4. Persistent Volume Layout
5. Canonical Config Sources
6. Provider Registry Spec
7. Model Alias Strategy
8. MCP Registry Spec
9. Skill Manifest Spec
10. Risk Policy Spec
11. Bootstrap / Prestart / Runtime Lifecycle
12. Backup and Restore Strategy
13. Upgrade and Rollback Strategy
14. Migration Strategy to Another Host
15. Security Boundaries
16. Phase 2 Build Plan
17. Open Questions / Assumptions

ZORUNLU DETAYLAR
- `/data` altında önerilen klasör ağacını ver
- Hangi dosyaların canonical source olduğunu açıkça belirt
- Hangi dosyaların generated olduğunu açıkça belirt
- Env ile YAML arasındaki ayrımı açıkla
- Provider registry için örnek YAML şeması ver
- Model alias stratejisi öner
- MCP registry için örnek YAML şeması ver
- Senpi MCP için özel örnek ekle
- Skill manifest için örnek YAML ver
- Risk policy için örnek YAML ver
- Analysis agent ve execution agent ayrımını config perspektifinden açıkla
- Update sırasında version pinning, migration checks, rollback planı ver
- Backup/export ve başka hosta restore akışını açıkla
- Güvensiz varsayımlardan kaçın
- “allow all users” veya geniş yetkili varsayılanlar önermeden ilerle

TEKNİK TERCİHLER
- Env yalnızca secret ve deployment wiring için kullanılsın
- Runtime davranışı volume içindeki YAML dosyalarıyla kontrol edilsin
- Final Hermes/OpenClaw config dosyası generated olsun
- Provider, MCP, skill ve risk yapılandırmaları ayrı dosyalarda olsun
- Skills pinned commit ile yönetilsin
- Container disposable kabul edilsin
- Volume asıl sistem state’i kabul edilsin

TESLİMAT KALİTESİ
- Somut ol
- Şema ver
- Örnek YAML ver
- Gereksiz genel geçer öneri verme
- İkinci aşamada koda dönüştürülebilecek netlikte yaz
```


## Şimdi önerdiğim çalışma şekli

Şimdi en doğru adım, bu Aşama 1 prompt’unu Antigravity’ye verip ondan gelen çıktıyı birlikte **mimari review** etmek. Çünkü bu aşamada amaç “hemen kod” değil, “yanlış mimariyi erken fark etmek” olmalı.[^2][^1]

Antigravity çıktısını bana getir; ben de onu şu açılardan denetleyeyim:

- persistent volume disiplini,
- update/rollback güvenliği,
- provider abstraction kalitesi,
- Senpi MCP/skills entegrasyon mantığı,
- gerçek fon yönetimine uygun risk sınırları.
<span style="display:none">[^17][^18][^19][^20][^21][^22][^23][^24]</span>

<div align="center">⁂</div>

[^1]: https://docs.openclaw.ai/install/railway

[^2]: https://docs.openclaw.ai/concepts/agent-workspace

[^3]: https://railway.com/deploy/openclaw-clawdbot-latest

[^4]: https://docs.railway.com/volumes/backups

[^5]: https://docs.openclaw.ai/cli/backup

[^6]: https://station.railway.com/questions/how-to-import-or-add-a-template-json-fil-47e03e11

[^7]: https://docs.railway.com/templates/deploy

[^8]: https://docs.railway.com/integrations/api/manage-volumes

[^9]: https://mcpmarket.com/server/hyperliquid-3

[^10]: https://www.youtube.com/watch?v=o-wKcu9eJ3s

[^11]: https://docs.mcp-agent.com/reference/configuration

[^12]: https://www.ainativelang.com/blog/how-to-install-setup-hermes

[^13]: https://dev.to/arshtechpro/hermes-agent-a-self-improving-ai-agent-that-runs-anywhere-2b7d

[^14]: https://hermes-agent.nousresearch.com/docs/guides/use-mcp-with-hermes/

[^15]: https://www.flowhunt.io/integrations/hyperliquid/

[^16]: https://subquery.network/hermes

[^17]: https://railway.com/deploy/openclaw

[^18]: https://github.com/creativetimofficial/openclaw-railway

[^19]: https://railway.com/deploy/openclaw-secure

[^20]: https://github.com/codetitlan/openclaw-railway-template

[^21]: https://github.com/NousResearch/hermes-agent/blob/main/cli-config.yaml.example

[^22]: https://docs.railway.com/templates/publish-and-share

[^23]: https://railway.com/deploy/openclaw-clawdbot-railway-template

[^24]: https://station.railway.com/feedback/feature-request-export-deployment-setti-6cafc872

