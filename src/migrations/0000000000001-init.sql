------------------------------------------------------
CREATE TABLE IF NOT EXISTS migrations (
    md5sum TEXT PRIMARY KEY,
    file TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);
------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS USERS_ID_SEQ;
CREATE TABLE IF NOT EXISTS USERS(
    ID          INTEGER NOT NULL DEFAULT nextval('users_id_seq'),
    NAME        VARCHAR(255) NOT NULL,
    SURNAME     VARCHAR(255) NOT NULL,
    USERNAME    VARCHAR(255) NOT NULL,
    EMAIL       VARCHAR(255) NOT NULL,
    MOBILE      VARCHAR(255) NULL,
    PASSWORD    VARCHAR(255) NOT NULL,
    TOKEN       VARCHAR(255) NOT NULL,
    VALID       INTEGER NOT NULL,
    CONSTRAINT USERS_PK PRIMARY KEY(ID),
    CONSTRAINT USERS_UQ1 UNIQUE(USERNAME),
    CONSTRAINT USERS_UQ2 UNIQUE(EMAIL)
);
------------------------------------------------------