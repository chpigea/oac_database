CREATE TABLE IF NOT EXISTS investigations (
    uuid    TEXT PRIMARY KEY,
    dataset TEXT NOT NULL,
    format  TEXT NOT NULL DEFAULT 'turtle'
);