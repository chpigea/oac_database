CREATE TABLE edit_locks(
    table_name      VARCHAR(36) NOT NULL,
    row_id          BIGINT NOT NULL,
    client_uuid     VARCHAR(36) NOT NULL,
    locked_at_ts    BIGINT NOT NULL,
    expires_at_ts   BIGINT NOT NULL,
    PRIMARY KEY(table_name, row_id)
);

CREATE INDEX edit_locks_exp_idx 
    ON edit_locks(expires_at_ts);