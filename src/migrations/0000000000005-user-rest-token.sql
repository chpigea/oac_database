alter table users add column reset_token VARCHAR(36) NOT NULL DEFAULT '';
alter table users add column reset_token_expiration BIGINT NOT NULL DEFAULT 0;
