-- Make email and ip_address nullable for webhook-triggered reviews (idempotent)
DO $$
BEGIN
    -- Check if email column is NOT NULL and drop constraint if it is
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'reviews' 
        AND column_name = 'email' 
        AND is_nullable = 'NO'
    ) THEN
        ALTER TABLE reviews ALTER COLUMN email DROP NOT NULL;
    END IF;
    
    -- Check if ip_address column is NOT NULL and drop constraint if it is
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'reviews' 
        AND column_name = 'ip_address' 
        AND is_nullable = 'NO'
    ) THEN
        ALTER TABLE reviews ALTER COLUMN ip_address DROP NOT NULL;
    END IF;
END
$$;

-- Add webhook-specific columns (idempotent)
ALTER TABLE reviews
ADD COLUMN IF NOT EXISTS github_installation_id BIGINT,
ADD COLUMN IF NOT EXISTS pr_owner TEXT,
ADD COLUMN IF NOT EXISTS pr_repo TEXT,
ADD COLUMN IF NOT EXISTS pr_number INTEGER;

-- Index for webhook reviews
CREATE INDEX IF NOT EXISTS idx_reviews_webhook ON reviews (github_installation_id)
WHERE github_installation_id IS NOT NULL;
