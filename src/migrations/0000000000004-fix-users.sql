alter table users drop column IF EXISTS is_admin;
alter table users add column IF NOT EXISTS role INTEGER not null default 2;
update users set role = 0 where username = 'igea';
