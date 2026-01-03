ALTER TABLE edit_locks
    ALTER COLUMN row_id 
    TYPE text
    USING row_id::TEXT;