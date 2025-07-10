# oac_database
Database scripts for the OAC project

## Installation (from NPM)
> npm install -g @igea/oac_database

### Update the database

#### From global installation
> oac_database

#### From source
> npm start

#### Options:
 - --db_host, -dh        [127.0.0.1] Database host
 - --db_port, -dp        [5432] Database port
 - --db_name, -dn        [oac] Database name
 - --db_schema, -ds      [public] Database name
 - --db_user, -du        [postgres] Database user
 - --db_password, -dk    [postgres] Database password
 - --db_replace, -dr     [false] to replace the existing DB with a new one
