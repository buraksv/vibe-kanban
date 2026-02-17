-- Add creator_user_id to issues table to track who created each issue
ALTER TABLE issues
ADD COLUMN IF NOT EXISTS creator_user_id UUID REFERENCES users(id) ON DELETE SET NULL;

-- Index for efficient queries filtering by creator
CREATE INDEX IF NOT EXISTS idx_issues_creator_user_id ON issues(creator_user_id) WHERE creator_user_id IS NOT NULL;
