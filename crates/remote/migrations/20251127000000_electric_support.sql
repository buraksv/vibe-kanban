-- Create electric_sync role if it doesn't exist (idempotent)
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'electric_sync') THEN
        CREATE ROLE electric_sync WITH LOGIN REPLICATION;
    END IF;
END
$$;

-- Grant permissions (these commands are idempotent by nature)
DO $$
BEGIN
    -- Note: Replace 'remote' with your actual database name if different
    -- In production, this should use current_database() or be parameterized
    EXECUTE format('GRANT CONNECT ON DATABASE %I TO electric_sync', current_database());
EXCEPTION
    WHEN OTHERS THEN
        -- Some PostgreSQL versions don't support GRANT CONNECT on current database
        -- from within a migration. This is safe to ignore.
        RAISE NOTICE 'Could not grant CONNECT (this is normal): %', SQLERRM;
END;
$$;

GRANT USAGE ON SCHEMA public TO electric_sync;

-- Create publication if it doesn't exist (idempotent)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication WHERE pubname = 'electric_publication_default'
    ) THEN
        CREATE PUBLICATION electric_publication_default;
    END IF;
END
$$;

CREATE OR REPLACE FUNCTION electric_sync_table(p_schema text, p_table text)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    qualified text := format('%I.%I', p_schema, p_table);
BEGIN
    EXECUTE format('ALTER TABLE %s REPLICA IDENTITY FULL', qualified);
    EXECUTE format('GRANT SELECT ON TABLE %s TO electric_sync', qualified);
    EXECUTE format('ALTER PUBLICATION %I ADD TABLE %s', 'electric_publication_default', qualified);
END;
$$;

SELECT electric_sync_table('public', 'shared_tasks');
