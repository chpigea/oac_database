---------------------------------------------------------------
ALTER TABLE USERS DROP COLUMN token;
ALTER TABLE USERS ADD COLUMN is_admin BOOLEAN DEFAULT FALSE;
---------------------------------------------------------------
ALTER TABLE USERS DROP COLUMN valid;
ALTER TABLE USERS ADD COLUMN is_active BOOLEAN DEFAULT TRUE;
---------------------------------------------------------------
INSERT INTO USERS(name, surname, username, email, password, is_admin)
VALUES('igea', 'igea', 'igea', 'info@igea-soluzioni.it', md5('@igea#'), TRUE);
---------------------------------------------------------------
