---------------------------------------------------------------
ALTER TABLE USERS DROP COLUMN token;
ALTER TABLE USERS ADD COLUMN is_admin BOOLEAN DEFAULT FALSE;
---------------------------------------------------------------
INSERT INTO USERS(name, surname, username, email, password, valid, is_admin)
VALUES('igea', 'igea', 'igea', 'info@igea-soluzioni.it', md5('@igea#'), 1, TRUE);
---------------------------------------------------------------
