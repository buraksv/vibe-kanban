-- Rename enum values only if they haven't been renamed already
DO $$
BEGIN
    -- Check if old value exists before renaming
    IF EXISTS (
        SELECT 1 FROM pg_enum e
        JOIN pg_type t ON t.oid = e.enumtypid
        WHERE t.typname = 'task_status' AND e.enumlabel = 'in-progress'
    ) THEN
        ALTER TYPE task_status RENAME VALUE 'in-progress' TO 'inprogress';
    END IF;
    
    IF EXISTS (
        SELECT 1 FROM pg_enum e
        JOIN pg_type t ON t.oid = e.enumtypid
        WHERE t.typname = 'task_status' AND e.enumlabel = 'in-review'
    ) THEN
        ALTER TYPE task_status RENAME VALUE 'in-review' TO 'inreview';
    END IF;
END
$$;
