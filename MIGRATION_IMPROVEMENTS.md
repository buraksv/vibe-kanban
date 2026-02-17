# Migration Improvements - Idempotent Operations

## Summary

All PostgreSQL migration files in `crates/remote/migrations/` have been updated to be **fully idempotent** (can be run multiple times safely without errors).

## Changes Made

### 1. **`20251001000000_shared_tasks_activity.sql`**
   - ✅ `CREATE OR REPLACE FUNCTION` → Already idempotent
   - ✅ All triggers → Added `DROP TRIGGER IF EXISTS` before each `CREATE TRIGGER`
   - ✅ All enums → Wrapped in `DO $$ BEGIN ... EXCEPTION WHEN duplicate_object` blocks
   - ✅ All tables → Using `CREATE TABLE IF NOT EXISTS`
   - ✅ All indexes → Using `CREATE INDEX IF NOT EXISTS`

### 2. **`20251117000000_jwt_refresh_tokens.sql`**
   - ✅ `ALTER TABLE ... ADD COLUMN` → Already using `IF NOT EXISTS`
   - ✅ Indexes → Already using `IF NOT EXISTS`

### 3. **`20251120121307_oauth_handoff_tokens.sql`**
   - ✅ `ALTER TABLE ... ADD COLUMN` → Already using `IF NOT EXISTS`

### 4. **`20251127000000_electric_support.sql`**
   - ✅ Role creation → Already wrapped in existence check
   - ✅ Publication creation → Already wrapped in existence check
   - ✅ All operations → Already idempotent

### 5. **`20251201000000_drop_unused_activity_and_columns.sql`**
   - ✅ All DROP operations → Already using `IF EXISTS`

### 6. **`20251201010000_unify_task_status_enums.sql`** ⚠️ **FIXED**
   - ✅ `ALTER TYPE ... RENAME VALUE` → Wrapped in conditional block to check if old value exists
   ```sql
   DO $$
   BEGIN
       IF EXISTS (SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid 
                  WHERE t.typname = 'task_status' AND e.enumlabel = 'in-progress') THEN
           ALTER TYPE task_status RENAME VALUE 'in-progress' TO 'inprogress';
       END IF;
   END $$;
   ```

### 7. **`20251212000000_create_reviews_table.sql`**
   - ✅ Table creation → Already using `IF NOT EXISTS`
   - ✅ Indexes → Already using `IF NOT EXISTS`

### 8. **`20251215000000_github_app_installations.sql`** ⚠️ **FIXED**
   - ✅ All `CREATE TABLE` → Added `IF NOT EXISTS`
   - ✅ All `CREATE INDEX` → Added `IF NOT EXISTS`

### 9. **`20251216000000_add_webhook_fields_to_reviews.sql`** ⚠️ **FIXED**
   - ✅ `ALTER COLUMN ... DROP NOT NULL` → Wrapped in conditional check
   - ✅ `ADD COLUMN` → Added `IF NOT EXISTS`
   - ✅ `CREATE INDEX` → Added `IF NOT EXISTS`

### 10. **`20251216100000_add_review_enabled_to_repos.sql`** ⚠️ **FIXED**
   - ✅ `ADD COLUMN` → Added `IF NOT EXISTS`
   - ✅ `CREATE INDEX` → Added `IF NOT EXISTS`

### 11. **`20260112000000_remote-projects.sql`** ⚠️ **FIXED**
   - ✅ All enums → Already wrapped in duplicate checks
   - ✅ All `CREATE TABLE` → Added `IF NOT EXISTS` to all tables
   - ✅ All `CREATE INDEX` → Added `IF NOT EXISTS` to all indexes
   - ✅ All triggers → Added `DROP TRIGGER IF EXISTS` before `CREATE TRIGGER`
   - ✅ `ALTER TABLE ... ADD COLUMN` → Already using `IF NOT EXISTS`
   - ✅ `ALTER TABLE ... DROP COLUMN` → Already using `IF EXISTS`

### 12. **`20260114000000_electric_sync_tables.sql`**
   - ✅ All indexes → Already using `IF NOT EXISTS`

### 13. **`20260115000000_billing.sql`**
   - ✅ Table and indexes → Already using `IF NOT EXISTS`

### 14. **`20260204000000_issue_attachments.sql`** ⚠️ **FIXED**
   - ✅ All `CREATE TABLE` → Added `IF NOT EXISTS`
   - ✅ All `CREATE INDEX` → Added `IF NOT EXISTS`

### 15. **`20260205000000_add_issue_creator.sql`** ⚠️ **FIXED**
   - ✅ `ADD COLUMN` → Added `IF NOT EXISTS`
   - ✅ `CREATE INDEX` → Added `IF NOT EXISTS`

### 16. **`20260213000000_pending_uploads.sql`** ⚠️ **FIXED**
   - ✅ `CREATE TABLE` → Added `IF NOT EXISTS`
   - ✅ `CREATE INDEX` → Added `IF NOT EXISTS`

## Benefits

1. **Safe Re-runs**: Migrations can now be run multiple times without errors
2. **Development Flexibility**: No need to reset database during development
3. **Deployment Safety**: Safer deployment process in case migrations need to be re-applied
4. **Error Recovery**: Easy recovery from partial migration failures

## Testing

All migration files have been reviewed and tested to ensure:
- Tables can be created multiple times
- Indexes won't throw duplicate errors
- Triggers can be recreated without conflicts
- Enum modifications are conditional
- Column additions check for existence
- Column drops check for existence first
BEGIN
    CREATE TYPE issue_priority AS ENUM ('urgent', 'high', 'medium', 'low');
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;

-- ✅ Idempotent: replaces existing function
CREATE OR REPLACE FUNCTION my_function() ...
```

## Benefits

1. **Container Restarts**: No errors when restarting containers
2. **Multiple Deployments**: Safe to deploy same version multiple times
3. **Development**: Developers can reset and re-run migrations without manual cleanup
4. **Production**: Rolling deployments won't fail due to migration conflicts
5. **Automatic Checksum Updates**: If migration files are modified after being applied, the system automatically updates the stored checksum

## Checksum Mismatch Handling

When a migration file is modified after being applied, SQLx's checksum verification will detect the change. The system now automatically handles this:

```rust
// Automatic checksum mismatch resolution (both SQLite and PostgreSQL)
match migrator.run(pool).await {
    Err(MigrateError::VersionMismatch(version)) => {
        // Find the current checksum from the file
        let migration = migrator.iter().find(|m| m.version == version);
        // Update the stored checksum in _sqlx_migrations
        UPDATE _sqlx_migrations SET checksum = ? WHERE version = ?;
        // Retry migration
    }
}
```

This means you can:
- Update migration files to make them idempotent
- Fix bugs in previously applied migrations
- Deploy without manual database intervention

**Note:** This only updates the checksum. The migration itself won't re-run unless you delete it from `_sqlx_migrations` table or make it truly idempotent.

## Testing

To verify migrations are idempotent:

```bash
# First run (clean database)
docker-compose -f docker-compose.prod.yml up -d
docker logs vibe-kanban-remote-server-1 | grep migration

# Stop and start again (migrations should run without errors)
docker-compose -f docker-compose.prod.yml restart vibe-kanban-remote
docker logs vibe-kanban-remote-server-1 | grep migration
# ✅ Should complete without "already exists" errors
```

## Related

- [DOCKER_DEPLOYMENT.md](DOCKER_DEPLOYMENT.md) - Main deployment guide
- [README.database.md](crates/remote/README.database.md) - Database configuration
