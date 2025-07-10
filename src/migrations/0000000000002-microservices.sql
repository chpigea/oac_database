-------------------------------------------------------
CREATE TABLE IF NOT EXISTS microservices (
    host        VARCHAR(255) NOT NULL,
    protocol    VARCHAR(5)  NOT NULL,
    port        INTEGER NOT NULL,
    name        VARCHAR(100) NOT NULL,
    CONSTRAINT microservices_UQ UNIQUE(host, protocol, port, name)
);
-------------------------------------------------------