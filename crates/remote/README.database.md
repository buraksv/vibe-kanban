# Remote Database Configuration

## Database Name Clarification

### TL;DR
**You can use ANY database name** in production. The "remote" database name you see in scripts is **only for development**.

## Build Time vs Runtime

### Build Time (Development Only)
The `scripts/prepare-db.sh` script uses "remote" as a **temporary database name**:

```bash
# This is ONLY for generating SQLx metadata (.sqlx/ folder)
createdb -p $PORT remote  # ← Temporary database
export DATABASE_URL="postgres://localhost:$PORT/remote"
sqlx migrate run          # Generate metadata
cargo sqlx prepare        # Write to .sqlx/
# Database is deleted after this
```

**Purpose:** Generate `.sqlx/` folder for SQLx offline mode (so Docker builds don't need a database connection)

**When it runs:**
- During development when running `pnpm run remote:prepare-db`
- NOT during Docker build
- NOT during runtime/production

### Runtime (Production)
The application uses whatever database you specify in `DATABASE_URL`:

```rust
// crates/remote/src/config.rs
let database_url = env::var("DATABASE_URL")  // ← Your choice!
```

**Examples:**
```bash
# ✅ All of these are valid
DATABASE_URL=postgres://user:pass@host:5432/vibe_kanban
DATABASE_URL=postgres://user:pass@host:5432/production
DATABASE_URL=postgres://user:pass@host:5432/my_custom_db
DATABASE_URL=postgres://user:pass@host:5432/totally_different_name
```

## Quick Start

### 1. Create Your Database
```sql
-- Use ANY name you want
CREATE DATABASE vibe_kanban;  -- or production, or my_app, etc.
CREATE USER vibe_kanban WITH ENCRYPTED PASSWORD 'your_password';
GRANT ALL PRIVILEGES ON DATABASE vibe_kanban TO vibe_kanban;
```

### 2. Set Environment Variable
```bash
# .env file
DATABASE_URL=postgres://vibe_kanban:your_password@your-host:5432/vibe_kanban
#                                                                 ↑
#                                                     This is YOUR database name
```

### 3. Run Migrations
```bash
docker-compose up -d vibe-kanban-remote
# Migrations run automatically on first start
```

## Common Questions

### Q: Do I need to create a "remote" database?
**A:** NO! Only if you're running the `prepare-db.sh` script locally for development.

### Q: What database name should I use in production?
**A:** Whatever you want! `vibe_kanban`, `production`, `my_app`, etc. Just make sure:
1. The database exists in PostgreSQL
2. The user has proper permissions
3. `DATABASE_URL` matches your database name

### Q: I'm getting "database remote does not exist"
**A:** You're probably running `prepare-db.sh` or have the wrong `DATABASE_URL`. 

**For production:**
```bash
# Change this:
DATABASE_URL=postgres://user:pass@host:5432/remote  # ❌ Wrong

# To this (your actual database):
DATABASE_URL=postgres://user:pass@host:5432/vibe_kanban  # ✅ Correct
```

### Q: Why does the codebase use "remote" as a name?
**A:** Historical naming for the development script. It could have been called "temp" or "dev" - it's just an arbitrary name for the temporary database created during SQLx metadata generation.

## Migration Files Location

- Migration SQL files: `crates/remote/migrations/*.sql`
- SQLx metadata (offline mode): `crates/remote/.sqlx/`

These migrations will run on **whatever database** you specify in `DATABASE_URL`.

## See Also

- [Main Docker Deployment Guide](../../DOCKER_DEPLOYMENT.md)
- [SQLx Migration Documentation](https://github.com/launchbadge/sqlx/blob/main/sqlx-cli/README.md)
