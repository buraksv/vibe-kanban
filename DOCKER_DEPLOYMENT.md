# Docker Deployment Guide for Vibe Kanban

Bu döküman, Vibe Kanban'ı Docker ve Jenkins kullanarak uzak PostgreSQL sunucusu ile nasıl deploy edeceğinizi açıklar.

## 📋 İçindekiler

- [Gereksinimler](#gereksinimler)
- [Hızlı Başlangıç](#hızlı-başlangıç)
- [Docker Compose Kullanımı](#docker-compose-kullanımı)
- [Jenkins Pipeline Kurulumu](#jenkins-pipeline-kurulumu)
- [Migration Yönetimi](#migration-yönetimi)
- [Production Deployment](#production-deployment)
- [Sorun Giderme](#sorun-giderme)

## 🔧 Gereksinimler

- Docker 20.10+
- Docker Compose 2.0+
- PostgreSQL 14+ (uzak sunucu)
- Jenkins (CI/CD için)
- Node.js 20+ ve pnpm (development için)
- Rust 1.93+ (local build için)

## 🚀 Hızlı Başlangıç

### 1. Environment Dosyasını Hazırlayın

```bash
cp .env.docker.example .env
```

`.env` dosyasını düzenleyip gerekli değerleri doldurun:

```bash
# Minimum gerekli ayarlar
DATABASE_URL=postgres://user:pass@your-postgres-host:5432/vibe_kanban
SERVER_PUBLIC_BASE_URL=https://your-domain.com
AUTH_PUBLIC_BASE_URL=https://your-domain.com
JWT_SECRET=your_secure_jwt_secret_min_32_chars
GITHUB_CLIENT_ID=your_github_client_id
GITHUB_CLIENT_SECRET=your_github_client_secret
```

**⚠️ ÖNEMLİ:** Database adı olarak **istediğiniz ismi** kullanabilirsiniz (`vibe_kanban`, `production`, vs.). 
"remote" adı **sadece** development build scriptlerinde geçici olarak kullanılır, production'da değil!

### 2. PostgreSQL Veritabanını Hazırlayın

PostgreSQL sunucunuzda veritabanını oluşturun:

```sql
-- İstediğiniz database adını kullanabilirsiniz (örn: vibe_kanban, production_db, vs.)
CREATE DATABASE vibe_kanban;
CREATE USER vibe_kanban WITH ENCRYPTED PASSWORD 'your_secure_password';
GRANT ALL PRIVILEGES ON DATABASE vibe_kanban TO vibe_kanban;

-- Extra: Owner olarak atamak isterseniz
ALTER DATABASE vibe_kanban OWNER TO vibe_kanban;
```

**💡 İpucu:** Database adı `DATABASE_URL` environment variable'ında belirttiğiniz isimle eşleşmelidir.
Örnek: `postgres://vibe_kanban:pass@host:5432/vibe_kanban` (son kısım database adı)

### 3. İlk Deployment

İlk deployment'ta migration'ların çalışması gerekir:

```bash
# .env dosyasında SKIP_MIGRATIONS=false olduğundan emin olun
docker-compose up -d vibe-kanban-remote
```

Container başladığında migration'lar otomatik olarak çalışacaktır.

### 4. Sonraki Deployment'lar

Migration'lar SQLx tarafından otomatik olarak yönetilir ve sadece yeni migration'lar çalıştırılır. 
Ancak her başlangıçta migration kontrolünü atlamak isterseniz:

```bash
# .env dosyasında
SKIP_MIGRATIONS=true
```

ayarını yapabilirsiniz. Bu, özellikle production ortamında hızlı restart'lar için kullanışlıdır.

## 🐳 Docker Compose Kullanımı

### Development Ortamı

Local PostgreSQL ile development:

```bash
docker-compose up -d postgres
# Postgres hazır olana kadar bekleyin
docker-compose up -d vibe-kanban-remote
```

### Production Ortamı

External PostgreSQL ile production:

```bash
docker-compose -f docker-compose.prod.yml up -d
```

### Logları Görüntüleme

```bash
# Tüm loglar
docker-compose logs -f vibe-kanban-remote

# Son 100 satır
docker-compose logs --tail=100 vibe-kanban-remote
```

### Container Durumunu Kontrol Etme

```bash
# Health check
docker-compose ps

# Manuel health check
curl http://localhost:8081/v1/health
```

## 🔄 Jenkins Pipeline Kurulumu

### 1. Jenkins Credentials Ekleyin

Jenkins Dashboard → Manage Jenkins → Credentials → Global credentials

Aşağıdaki credential'ları ekleyin:

- `docker-registry-url` (String) - Docker registry URL'i
- `docker-registry-credentials` (Username/Password) - Docker registry kimlik bilgileri
- `vibe-kanban-database-url` (Secret text) - PostgreSQL connection string
- `postgres-password` (Secret text) - PostgreSQL şifresi
- `server-public-base-url` (Secret text)
- `auth-public-base-url` (Secret text)
- `jwt-secret` (Secret text)
- `github-client-id` (Secret text)
- `github-client-secret` (Secret text)
- `google-client-id` (Secret text, opsiyonel)
- `google-client-secret` (Secret text, opsiyonel)

### 2. Pipeline Job Oluşturun

1. New Item → Pipeline
2. Pipeline → Definition: Pipeline script from SCM
3. SCM: Git
4. Repository URL: `<your-repo-url>`
5. Script Path: `Jenkinsfile`

### 3. Build Parameters

Jenkinsfile'da tanımlı parametreler:

- `BUILD_LOCAL`: Local server (SQLite) image'ını build et
- `RUN_TESTS`: Build öncesi testleri çalıştır
- `PUSH_TO_REGISTRY`: Image'ları registry'ye push et
- `REMOTE_FEATURES`: Cargo features (örn: `vk-billing`)

### 4. Branch-based Deployment

- `develop` branch → Staging ortamına otomatik deploy
- `main` branch → Production ortamına manuel onay ile deploy

## 🔄 Migration Yönetimi

### Migration Stratejisi

Vibe Kanban SQLx migration sistemini kullanır. Bu sistem:

✅ **Idempotent**: Migration'lar güvenle **tekrar çalıştırılabilir** - "already exists" hataları almaz
✅ **Versiyonlanmış**: Her migration bir version numarasına sahip ve izlenir
✅ **Güvenli**: Sadece uygulanmamış migration'lar çalıştırılır
✅ **Akıllı**: `CREATE ROLE`, `CREATE TYPE`, `CREATE FUNCTION` gibi komutlar var olup olmadığını kontrol eder

### Migration Kontrolü

#### Seçenek 1: Her Başlangıçta Migration Kontrolü (Önerilen)

```bash
SKIP_MIGRATIONS=false  # Default
```

**Avantajlar:**
- Yeni migration'lar otomatik uygulanır
- Güvenli ve tutarlı
- Kod ile veritabanı senkronize kalır

**Dezavantajlar:**
- Her başlangıçta ~1-2 saniye ekstra süre

#### Seçenek 2: Migration Kontrolünü Atlama

```bash
SKIP_MIGRATIONS=true
```

**Ne Zaman Kullanılmalı:**
- Production'da sık restart yapılıyorsa
- Migration'ların manuel kontrol edildiği durumlarda
- Aynı version'ın tekrar deploy edildiği durumlarda

**⚠️ Uyarı:** Yeni migration'lar varsa manuel olarak çalıştırmanız gerekir!

### Manuel Migration Çalıştırma

Gerekirse migration'ları manuel olarak çalıştırabilirsiniz:

```bash
# Container içinde
docker exec -it vibe-kanban-remote /bin/bash
# Migration'ları manuel çalıştırma gerektiğinde, SQLx sistemi kullanılıyor
# Bu nedenle doğrudan migration çalıştırma yöntemi yok
# SKIP_MIGRATIONS=false ile container'ı restart edin
```

Ya da yeni bir container oluşturup migration çalıştırın:

```bash
# Tek seferlik migration container'ı
docker run --rm \
  -e DATABASE_URL=$DATABASE_URL \
  -e SKIP_MIGRATIONS=false \
  your-image:tag \
  /bin/bash -c "exit 0"  # Container başlayıp migration'ı çalıştırır ve çıkar
```

### Migration Dosyaları

- Local (SQLite): `crates/db/migrations/*.sql`
- Remote (PostgreSQL): `crates/remote/migrations/*.sql`

**✅ Tüm migration'lar idempotent'tir** - tekrar çalıştırılabilir, hata vermez:
- `CREATE ROLE` → Önce var olup olmadığını kontrol eder
- `CREATE TYPE` → Duplicate error handling ile korunmuş
- `CREATE FUNCTION` → `CREATE OR REPLACE` kullanır
- `CREATE TABLE` → `IF NOT EXISTS` kullanır
- `CREATE PUBLICATION` → Önce var olup olmadığını kontrol eder

Bu sayede migration'lar container restart'ında "already exists" hatası vermez.

Detaylı bilgi: [MIGRATION_IMPROVEMENTS.md](MIGRATION_IMPROVEMENTS.md)

## 🚀 Production Deployment

### İlk Kez Deployment

1. **PostgreSQL'i hazırlayın**
   ```sql
   CREATE DATABASE vibe_kanban;
   CREATE USER vibe_kanban WITH PASSWORD 'secure_password';
   GRANT ALL PRIVILEGES ON DATABASE vibe_kanban TO vibe_kanban;
   ```

2. **Environment değişkenlerini ayarlayın**
   ```bash
   cp .env.docker.example .env.prod
   # .env.prod dosyasını production değerleriyle doldurun
   SKIP_MIGRATIONS=false  # İlk deployment için
   ```

3. **Image'ı build edin**
   ```bash
   docker build -t vibe-kanban-remote:v1.0.0 \
     -f crates/remote/Dockerfile .
   ```

4. **Deploy edin**
   ```bash
   docker-compose -f docker-compose.prod.yml up -d
   ```

5. **Health check yapın**
   ```bash
   curl http://your-domain.com/v1/health
   ```

### Güncellemeler için Deployment

1. **Yeni version'ı pull edin**
   ```bash
   docker pull your-registry/vibe-kanban-remote:latest
   ```

2. **Migration kontrolünü ayarlayın**
   ```bash
   # Yeni migration varsa:
   SKIP_MIGRATIONS=false
   
   # Migration yoksa (hızlı deployment):
   SKIP_MIGRATIONS=true
   ```

3. **Zero-downtime deployment için**
   ```bash
   # Yeni container'ı başlat
   docker-compose -f docker-compose.prod.yml up -d --no-deps --scale vibe-kanban-remote=2
   
   # Health check
   sleep 10
   
   # Eski container'ı durdur
   docker-compose -f docker-compose.prod.yml up -d --no-deps --scale vibe-kanban-remote=1
   ```

### Rollback Stratejisi

```bash
# Önceki version'a dön
docker-compose -f docker-compose.prod.yml down
docker pull your-registry/vibe-kanban-remote:v1.0.0
docker-compose -f docker-compose.prod.yml up -d

# Veritabanı migration'ı geri almak
# SQLx downgrade desteklemez, backup'tan restore yapın
```

## 🔍 Sorun Giderme

### Migration Hataları

**Sorun:** `migration 20251001000000 was previously applied but has been modified` veya `role "electric_sync" already exists`

**ÇÖZÜM:** ✅ Artık otomatik düzeltiliyor! Sistem:
1. Checksum mismatch'i algılar
2. Migration dosyasının yeni checksum'ını hesaplar
3. Database'deki eski checksum'ı günceller
4. Migration'ı tekrar çalıştırır

Logları kontrol edin:
```bash
docker logs vibe-kanban-remote | grep -i migration
# "Updating stored checksum..." mesajını görmelisiniz
```

**Eğer hala sorun devam ediyorsa:**

```bash
# Option 1: Migration history'yi tamamen sıfırla (sadece development/test için!)
docker exec -it vibe-kanban-postgres psql -U vibe_kanban -d vibe_kanban
DELETE FROM _sqlx_migrations;
\q

# Container'ı yeniden başlat
docker-compose -f docker-compose.prod.yml restart vibe-kanban-remote
```

**Sorun:** `migration version mismatch` hatası
```bash
# Artık otomatik düzeltiliyor, ama manuel olarak da düzeltebilirsiniz:
docker exec -it vibe-kanban-postgres psql -U vibe_kanban -d vibe_kanban
DELETE FROM _sqlx_migrations WHERE version = <problem_version>;
# Container'ı restart edin
```

**Sorun:** Migration çalışmıyor
```bash
# Kontrol 1: SKIP_MIGRATIONS değişkenini kontrol edin
docker exec -it vibe-kanban-remote env | grep SKIP_MIGRATIONS

# Kontrol 2: Logları inceleyin
docker logs vibe-kanban-remote | grep -i migration

# Kontrol 3: Manuel olarak çalıştırın
docker-compose restart vibe-kanban-remote
```

### Database Connection Hataları

```bash
# PostgreSQL'in erişilebilir olduğunu kontrol edin
docker exec -it vibe-kanban-remote sh
ping postgres-host

# Connection string'i kontrol edin
docker exec -it vibe-kanban-remote env | grep DATABASE_URL

# PostgreSQL loglarını kontrol edin
docker logs vibe-kanban-postgres
```

### Container Başlamıyor

```bash
# 1. Logları inceleyin
docker logs vibe-kanban-remote --tail=50

# 2. Configuration'ı kontrol edin
docker exec -it vibe-kanban-remote env

# 3. Health check'i manuel test edin
docker exec -it vibe-kanban-remote wget --spider -q http://localhost:8081/v1/health
echo $?  # 0 olmalı
```

### Performance Sorunları

```bash
# Container kaynaklarını kontrol edin
docker stats vibe-kanban-remote

# Database connection pool'u artırın (kod değişikliği gerektirir)
# crates/remote/src/db/mod.rs dosyasında:
# PgPoolOptions::new().max_connections(20)  // Default: 10
```

## 📊 Monitoring

### Health Check Endpoint

```bash
# HTTP GET /v1/health
curl http://localhost:8081/v1/health
```

### Prometheus Metrics (gelecek)

Migration metrikleri için plans:
- `vibe_migrations_total`: Toplam migration sayısı
- `vibe_migrations_duration_seconds`: Migration süresi
- `vibe_migrations_failed_total`: Başarısız migration sayısı

## 🔐 Güvenlik Önerileri

1. **JWT Secret**: Minimum 32 karakter, rastgele
   ```bash
   openssl rand -base64 32
   ```

2. **PostgreSQL Password**: Güçlü şifre kullanın
   ```bash
   openssl rand -base64 24
   ```

3. **Environment Variables**: `.env` dosyalarını git'e eklemeyin
   ```bash
   echo ".env" >> .gitignore
   echo ".env.*" >> .gitignore
   ```

4. **Container Security**: Non-root user kullanın (Dockerfile'da zaten ayarlı)

5. **Network Security**: Production'da internal network kullanın

## 📚 Ek Kaynaklar

- [SQLx Migration Docs](https://github.com/launchbadge/sqlx/blob/main/sqlx-cli/README.md#sqlx-migrate)
- [Docker Compose Best Practices](https://docs.docker.com/compose/production/)
- [Jenkins Pipeline Documentation](https://www.jenkins.io/doc/book/pipeline/)

## ❓ Sık Sorulan Sorular (FAQ)

### Neden "remote" database'ine bağlanmaya çalışıyor?

**CEVAP:** "remote" database adı **sadece development/build zamanında** SQLx metadata oluşturmak için kullanılır.

- **Build zamanı**: `crates/remote/scripts/prepare-db.sh` scripti geçici bir PostgreSQL başlatır, "remote" database'i oluşturur, migration'ları çalıştırır ve `.sqlx/` klasörüne metadata yazar. Sonra her şeyi temizler.

- **Runtime (Production)**: `DATABASE_URL` environment variable'ından aldığı **herhangi bir database adını** kullanır. "remote" adı runtime'da hiç kullanılmaz!

**Çözüm:** `DATABASE_URL` içinde istediğiniz database adını kullanın:
```bash
DATABASE_URL=postgres://user:pass@host:5432/vibe_kanban  # ✅ Doğru
DATABASE_URL=postgres://user:pass@host:5432/production   # ✅ Doğru  
DATABASE_URL=postgres://user:pass@host:5432/my_app       # ✅ Doğru
```

### Migration'lar her başlangıçta tekrar çalışıyor mu?

**CEVAP:** Hayır! SQLx migration sistemi **idempotent**tir:
- Her migration sadece **bir kez** çalıştırılır
- PostgreSQL'de `_sqlx_migrations` tablosunda hangi migration'ların çalıştığı takip edilir
- Aynı migration tekrar çalışmaz

`SKIP_MIGRATIONS=false` (default) olduğunda, sistem sadece **migration kontrolü** yapar (~1-2 saniye). Yeni migration yoksa hiçbir şey değişmez.

**Özel Durum:** Migration dosyası daha önce uygulandıktan SONRA değiştirilirse, sistem:
1. Checksum mismatch'i algılar
2. Otomatik olarak checksum'ı günceller
3. Migration'ı tekrar çalıştırmaya çalışır (ama idempotent olduğu için sorun çıkmaz!)

Bu sayede migration dosyalarını güncelleyebilirsiniz (örn: idempotent hale getirmek için).

### SKIP_MIGRATIONS ne zaman true yapmalıyım?

**CEVAP:** İki durumda kullanışlıdır:

1. **Production'da sık restart**: Rolling deployment veya auto-scaling durumlarında her container'ın migration kontrolü yapmasına gerek yoktur.

2. **Manuel migration yönetimi**: Database migration'larını deploy işleminden ayrı, özel bir job/script ile çalıştırıyorsanız.

**⚠️ Uyarı:** `SKIP_MIGRATIONS=true` ile yeni migration'lar otomatik çalışmaz, manuel olarak uygulamanız gerekir!

### Docker build esnasında "could not find database: remote" hatası

**CEVAP:** Bu hata **normal değil**. SQLx offline mode kullandığınızda build zamanında database'e bağlanmaz.

**Kontrol edin:**
1. `.sqlx/` klasörü var mı? (Git'te commit edilmiş olmalı)
2. Dockerfile'da `SQLX_OFFLINE=true` set edilmiş mi?
3. `cargo sqlx prepare` komutu daha önce çalıştırılmış mı?

**Çözüm:**
```bash
# Development'ta metadata oluştur
cd crates/remote
pnpm run remote:prepare-db  # veya ./scripts/prepare-db.sh

# .sqlx/ klasörünü commit et
git add .sqlx/
git commit -m "Update SQLx metadata"
```

### Database connection hatası alıyorum

**CEVAP:** Kontrol listesi:

1. **PostgreSQL erişilebilir mi?**
   ```bash
   psql -h your-host -U your-user -d your-database
   ```

2. **DATABASE_URL doğru mu?**
   ```bash
   docker exec vibe-kanban-remote env | grep DATABASE_URL
   # Format: postgres://user:password@host:port/database
   ```

3. **Network bağlantısı var mı?**
   ```bash
   docker exec vibe-kanban-remote ping postgres-host
   ```

4. **PostgreSQL user'ın yetkileri yeterli mi?**
   ```sql
   GRANT ALL PRIVILEGES ON DATABASE your_db TO your_user;
   ```

## 🤝 Katkıda Bulunma

Sorularınız veya önerileriniz için issue açabilirsiniz.

## 📄 Lisans

Bu proje MIT lisansı altında lisanslanmıştır.
