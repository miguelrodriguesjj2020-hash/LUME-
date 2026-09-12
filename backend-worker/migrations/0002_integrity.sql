CREATE INDEX IF NOT EXISTS idx_progress_profile_updated ON progress(profile_id,server_updated_at);
CREATE INDEX IF NOT EXISTS idx_editions_source_revision ON editions(source_revision);
