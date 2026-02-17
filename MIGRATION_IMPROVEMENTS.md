# Migration Improvements - Idempotent Operations

## Changes Made

All PostgreSQL migration files have been updated to be **idempotent** (can be run multiple times safely).

### Files Modified

1. **`20251127000000_electric_support.sql`**
   - ✅ `CREATE ROLE electric_sync` → Now checks if role exists
   - ✅ `GRANT CONNECT ON DATABASE` → Uses `current_database()` instead of hardcoded "remote"
   - ✅ `CREATE PUBLICATION` → Checks if publication exists before creating

2. **`20251001000000_shared_tasks_activity.sql`**
   - ✅ `CREATE FUNCTION ensure_activity_partition` → Changed to `CREATE OR REPLACE`
   - ✅ `CREATE FUNCTION activity_notify` → Changed to `CREATE OR REPLACE`

3. **`20260112000000_remote-projects.sql`**
   - ✅ `CREATE TYPE issue_priority` → Wrapped in duplicate check
   - ✅ `CREATE TYPE issue_relationship_type` → Wrapped in duplicate check
   - ✅ `CREATE TYPE notification_type` → Wrapped in duplicate check
   - ✅ `CREATE TYPE pull_request_status` → Wrapped in duplicate check

### Before (Problem)

```sql
CREATE ROLE electric_sync WITH LOGIN REPLICATION;
-- ❌ ERROR: role "electric_sync" already exists

CREATE TYPE issue_priority AS ENUM ('urgent', 'high', 'medium', 'low');
-- ❌ ERROR: type "issue_priority" already exists

CREATE FUNCTION my_function() ...
-- ❌ ERROR: function already exists
```

### After (Solution)

```sql
-- ✅ Idempotent: checks if role exists
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'electric_sync') THEN
        CREATE ROLE electric_sync WITH LOGIN REPLICATION;
    END IF;
END
$$;

-- ✅ Idempotent: handles duplicate type error
DO $$
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
