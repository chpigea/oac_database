# Install PgUnit
https://github.com/adrianandrei-ca/pgunit

## Create a dedicated schema (for PgUnit)
```sql
CREATE SCHEMA pgunit;
CREATE EXTENSION DBLINK SCHEMA pgunit;
```

## Run the script
```sql
SET search_path TO pgunit;
```
Execute the content of the **PGUnit.sql** file using PgAdmin, PSQL, DBeaver (or whatever you prefer).

PgUnit functions should be installed in the pgunit schema.

## Create a dedicated schema (for Gis360 Test procedures)

```sql
CREATE SCHEMA oac_ut;
```

## Performing Tests
### Warning
If we run tests on Windows server we can obtain the following error message:
```
could not establish connection
```
To avoid it we have to configure dblink for the current session with user/password parameters:
```sql
select set_config('pgunit.dblink_conn_extra', 'user=postgres password=postgres', false)
```

### Run all tests
```sql
SELECT * FROM pgunit.test_run_all();
```

|test_name|successful|failed|erroneous|error_message|duration|
|---|---|---|---|---|---|
|test_case_01|true|false|false|OK|00:00:00.5815|

### Run Suite tests
To run just tests inside a specific suite execute the following statement:
```sql
select * from pgunit.test_run_suite('schema');
```
In this example we will execute all tests with the **test_case_schema** prefix.

# Remove PgUnit
If you want to completely remove PgUnit execute the following SQL statements:
```sql
SET search_path TO pgunit;
DROP EXTENSION DBLINK;
```
Execute the SQL statements from the **PGUnitDrop.sql** file and finally do:

```sql
DROP SCHEMA pgunit;
```