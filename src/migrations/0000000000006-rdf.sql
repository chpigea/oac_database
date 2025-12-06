CREATE TABLE IF NOT EXISTS investigations (
    iri     TEXT PRIMARY KEY,
    dataset TEXT NOT NULL,
    format  TEXT NOT NULL DEFAULT 'turtle'
);