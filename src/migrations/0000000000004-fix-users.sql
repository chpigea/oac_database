alter table users drop column is_admin;
alter table users add column role INTEGER not null default 2;
update users set role = 0 where username = 'igea';
