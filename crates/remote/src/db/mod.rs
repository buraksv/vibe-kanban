pub mod attachments;
pub mod auth;
pub mod blobs;
pub mod github_app;
pub mod identity_errors;
pub mod invitations;
pub mod issue_assignees;
pub mod issue_comment_reactions;
pub mod issue_comments;
pub mod issue_followers;
pub mod issue_relationships;
pub mod issue_tags;
pub mod issues;
pub mod migration;
pub mod notifications;
pub mod oauth;
pub mod oauth_accounts;
pub mod organization_members;
pub mod organizations;
pub mod pending_uploads;
pub mod project_notification_preferences;
pub mod project_statuses;
pub mod projects;
pub mod pull_requests;
pub mod reviews;
pub mod tags;
pub mod types;
pub mod users;
pub mod workspaces;

use sqlx::{
    Executor, PgPool, Postgres, Transaction, migrate::MigrateError, postgres::PgPoolOptions,
};

pub(crate) type Tx<'a> = Transaction<'a, Postgres>;

/// Get the current transaction ID from Postgres.
/// Must be called within an active transaction.
/// Uses text conversion to avoid xid8->bigint cast issues in some PG versions.
pub async fn get_txid<'e, E>(executor: E) -> Result<i64, sqlx::Error>
where
    E: Executor<'e, Database = Postgres>,
{
    let row: (i64,) = sqlx::query_as("SELECT pg_current_xact_id()::text::bigint")
        .fetch_one(executor)
        .await?;
    Ok(row.0)
}

pub(crate) async fn migrate(pool: &PgPool) -> Result<(), MigrateError> {
    use std::collections::HashSet;

    // Check if migrations should be skipped via environment variable
    if std::env::var("SKIP_MIGRATIONS")
        .map(|v| v.eq_ignore_ascii_case("true") || v == "1")
        .unwrap_or(false)
    {
        tracing::info!("Skipping database migrations (SKIP_MIGRATIONS=true)");
        return Ok(());
    }

    let migrator = sqlx::migrate!("./migrations");
    let mut processed_versions: HashSet<i64> = HashSet::new();

    loop {
        match migrator.run(pool).await {
            Ok(()) => return Ok(()),
            Err(MigrateError::VersionMismatch(version)) => {
                // Guard against infinite loop
                if !processed_versions.insert(version) {
                    tracing::error!(
                        "Migration version {} checksum mismatch persists after update attempt",
                        version
                    );
                    return Err(MigrateError::VersionMismatch(version));
                }

                tracing::warn!(
                    "Migration version {} has checksum mismatch. This can happen when migration files are updated after being applied. Updating stored checksum...",
                    version
                );

                // Find the migration with the mismatched version and get its current checksum
                if let Some(migration) = migrator.iter().find(|m| m.version == version) {
                    // Update the checksum in _sqlx_migrations to match the current file
                    let result = sqlx::query(
                        "UPDATE _sqlx_migrations SET checksum = $1 WHERE version = $2"
                    )
                    .bind(&*migration.checksum)
                    .bind(version)
                    .execute(pool)
                    .await;

                    match result {
                        Ok(_) => {
                            tracing::info!(
                                "Updated checksum for migration version {}",
                                version
                            );
                            // Continue loop to retry migration
                        }
                        Err(e) => {
                            tracing::error!(
                                "Failed to update checksum for migration {}: {}",
                                version,
                                e
                            );
                            return Err(MigrateError::Execute(Box::new(e)));
                        }
                    }
                } else {
                    tracing::error!(
                        "Migration version {} not found in current migration set",
                        version
                    );
                    return Err(MigrateError::VersionMismatch(version));
                }
            }
            Err(e) => return Err(e),
        }
    }
}

pub async fn create_pool(database_url: &str) -> Result<PgPool, sqlx::Error> {
    PgPoolOptions::new()
        .max_connections(10)
        .connect(database_url)
        .await
}

pub(crate) async fn ensure_electric_role_password(
    pool: &PgPool,
    password: &str,
) -> Result<(), sqlx::Error> {
    if password.is_empty() {
        return Ok(());
    }

    // PostgreSQL doesn't support parameter binding for ALTER ROLE PASSWORD
    // We need to escape the password properly and embed it directly in the SQL
    let escaped_password = password.replace("'", "''");
    let sql = format!("ALTER ROLE electric_sync WITH PASSWORD '{escaped_password}'");

    sqlx::query(&sql).execute(pool).await?;

    Ok(())
}
