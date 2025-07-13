#!/usr/bin/env node
const fs = require('fs')
const path = require('path')
const md5File = require('md5-file')
const pgtools = require("pgtools")
const { Client } = require('pg')
const meow  = require('meow')


const cli = meow(`
  Usage:
    $ oac_database
  
  Options:
    --db_host, -dh        [127.0.0.1] Database host
    --db_port, -dp        [5432] Database port
    --db_name, -dn        [oac] Database name
    --db_schema, -ds      [public] Database name
    --db_user, -du        [postgres] Database user
    --db_password, -dk    [postgres] Database password
    --db_modules, -dm     [core] Modules to install (separated by comma)
    --db_replace, -dr     [false] to replace the existing DB with a new one
  
  Examples:
    $ oac_database --db_name oac
`, {
    flags: {
        db_host:      { alias: 'dh', type: 'string' },
        db_port:      { alias: 'dp', type: 'string' },
        db_name:      { alias: 'dn', type: 'string' },
        db_schema:    { alias: 'ds', type: 'string' },
        db_user:      { alias: 'du', type: 'string' },
        db_password:  { alias: 'dk', type: 'string' },
        db_modules:   { alias: 'dm', type: 'string' },
        db_replace:   { alias: 'dr', type: 'boolean' }
    }
})
//--------------------------------------------------------------------------------------
let DEFAULT_CONFIG = {
    host: cli.flags.dbHost || "127.0.0.1",
    port: cli.flags.dbPort ||  5432,
    database: cli.flags.dbName || "oac",
    user: cli.flags.dbUser || "postgres",
    password: cli.flags.dbPassword || "postgres",
    schema: cli.flags.dbSchema || "public",
    modules: cli.flags.dbModules || "core",
    replace: cli.flags.dbReplace || false
}
DEFAULT_CONFIG.modules = DEFAULT_CONFIG.modules.split(",")
for(let x=0; x<DEFAULT_CONFIG.modules.length; x++)
    DEFAULT_CONFIG.modules[x] = DEFAULT_CONFIG.modules[x].trim()
if(DEFAULT_CONFIG.modules.indexOf("core") == -1)
    DEFAULT_CONFIG.modules = ["core"].concat(DEFAULT_CONFIG.modules)
//--------------------------------------------------------------------------------------
console.log("Start installing/upgrading OAC database with the following parameters:")
console.log("  - HOST:\t" + DEFAULT_CONFIG.host)
console.log("  - PORT:\t" + DEFAULT_CONFIG.port)
console.log("  - DATABASE:\t" + DEFAULT_CONFIG.database)
console.log("  - SCHEMA:\t" + DEFAULT_CONFIG.schema)
console.log("  - USER:\t" + DEFAULT_CONFIG.user)
console.log("  - MODULES:\t[" + DEFAULT_CONFIG.modules.join(",") + "]")
console.log("  - REPLACE:\t" + DEFAULT_CONFIG.replace)
//--------------------------------------------------------------------------------------
async function getOutstandingMigrations(directory, migrations = []) {
    //const directory = path.join(__dirname, "src", "migrations")
    const files = fs.readdirSync(directory)

    const sql = await Promise.all(
        files
            .filter((file) => file.split(".")[1] === "sql")
            .filter((file) => !migrations.includes(file))
            .map(async (file) => ({
                file,
                query: fs.readFileSync(path.join(`${directory}`, `${file}`), {
                    encoding: "utf-8",
                }),
                md5: md5File.sync(path.join(`${directory}`, `${file}`))
            }))
    );
    return sql
}
//--------------------------------------------------------------------------------------
async function connect(config, callback) {

    const client = new Client(config)
    try{
        await client.connect()
        callback(client)
    } catch (err) {
		console.error(err)
        if(err.message.includes(DEFAULT_CONFIG.database)){
            console.log(`Database ${DEFAULT_CONFIG.database} does not exist: start creating it...`)
            delete config["database"]
            pgtools.createdb(config, DEFAULT_CONFIG.database, function (err, res) {
                if (err) {
                    console.error(err)
                    process.exit(-1)
                }else{
                    config["database"] = DEFAULT_CONFIG.database
                    const client2 = new Client(config)
                    client2.connect().then( () => {
                        callback(client2)
                    })
                }
            });
        }
    }
}
//--------------------------------------------------------------------------------------
async function checkMigrationModuleField(client){
    let res = false
    try {
        let sql = "SELECT column_name " +
            "FROM information_schema.columns " +
            "WHERE table_name = 'migrations' " +
            "AND column_name = 'module' " +
            "AND table_schema = '" + DEFAULT_CONFIG.schema + "'"
        let result = await client.query(sql)
        if(result.rows.length == 0)
            await client.query("ALTER TABLE migrations ADD COLUMN module VARCHAR(100) NOT NULL DEFAULT 'core'")
        res = true
    } catch (err){
        console.warn(err)
    }
    return res
}
//--------------------------------------------------------------------------------------
async function migrate(client) {
    let existingMigrations = []
    let empty_database = true
    let migration_table = false
    let postgis_database = false

    try {

        try {
            let result = await client.query("SELECT postgis_full_version() as version")
            console.log("PostGis Version: " + JSON.stringify(result.rows[0]["version"]))
            postgis_database = true
        } catch {
            console.warn("PostGIS extension is not installed")
        }
        /*
        if(!postgis_database){
            console.log("Installing PostGIS extension...")
            await client.query("CREATE EXTENSION if not EXISTS postgis")
            postgis_database = true
        }

        if(postgis_database){
            try {
                await client.query("CREATE EXTENSION if not EXISTS pgrouting")
                let result = await client.query("SELECT pgr_version as version FROM pgr_version()")
                console.log("PgRouting Version: " + JSON.stringify(result.rows[0]["version"]))
            } catch(e) {
                console.warn("PgRouting extension not installed: " + e)
            }
        }
        */
        
        try {
            let result = await client.query("SELECT oac_getversion() as version")
            console.log("OAC Version: " + JSON.stringify(result.rows[0]["version"]))
            empty_database = false
        } catch {
            console.warn("Empty (Gis360) database")
        }

        // ---------------------------------------------------------------------------------------
        // Loop throw possible modules
        let modules = [{
            key: 'core',
            name: 'oac_database'
        }]
        //----------------------------------------------------------------------------------------
        let directory = path.join(__dirname, "migrations")
        let isCoreModule = true
        let migrate_mod_field = false
        for(let m = 0; m < modules.length; m++){
            let module = modules[m]
            if(module.key != 'core') empty_database = false
            if(DEFAULT_CONFIG.modules.indexOf(module.key) != -1){
                if(module.key != 'core'){
                    isCoreModule = false
                    directory = path.join(__dirname, 'node_modules', '@igea', module.name, 'src', 'migrations')
                    if(!fs.existsSync(directory)){
                        directory = path.join(__dirname, '..', module.name, 'src', 'migrations')
                    }
                }
                if(!migrate_mod_field) migrate_mod_field = await checkMigrationModuleField(client)
                if(!empty_database){
                    console.log("A")
                    try {
                        let sql_migrations_items = "SELECT * FROM migrations"
                        if(migrate_mod_field)
                            sql_migrations_items += " WHERE module = '" + module.key + "'"
                        let result = await client.query(sql_migrations_items);
                        existingMigrations = result.rows.map(r => r.file)
                        console.log("B")
                        console.log(existingMigrations)
                        migration_table = true
                    } catch {
                        //Migrations table does not exist (but an older Gis360 database version exists!)
                        if(module.key == 'core')
                            existingMigrations = ['00000001-init-schema.sql', '00000002-init-functions.sql', '00000003-init-triggers.sql']
                    }
                }

                const outstandingMigrations = await getOutstandingMigrations(
                    directory,
                    existingMigrations
                );

                if(outstandingMigrations.length){
                    console.log("Migration's files to execute:")
                    for(let index in outstandingMigrations)
                        console.log("  * [" + outstandingMigrations[index].md5 + "] - " + outstandingMigrations[index].file)

                    try{

                        await client.query("BEGIN")

                        for(let index in outstandingMigrations){
                            let migration = outstandingMigrations[index]
                            console.log(`Installing script [${module.key}]<${migration.file}>...`)
                            await client.query(migration.query.toString())
                            if(!migrate_mod_field && module.key == 'core')
                                await client.query("INSERT INTO migrations (md5sum, file) VALUES ($1, $2)", [
                                    migration.md5, migration.file
                                ])
                            else
                                await client.query("INSERT INTO migrations (md5sum, file, module) VALUES ($1, $2, $3)", [
                                    migration.md5, migration.file, module.key
                                ])
                        }

                        if(!empty_database && !migration_table){
                            await client.query(
                                "insert into migrations(md5sum,file) VALUES ('bcda17ef90d9921595fedba9a50cf23e', '00000001-init-schema.sql')"
                            )
                            await client.query(
                                "insert into migrations(md5sum,file) VALUES ('b5263de524c9c955135bb231c708c4e0', '00000002-init-functions.sql')"
                            )
                            await client.query(
                                "insert into migrations(md5sum,file) VALUES ('6cfb957017ba87a1ffafa8fd20497843', '00000003-init-triggers.sql')"
                            )
                        }
                        await client.query("COMMIT")

                    } catch (err) {
                        console.error(err)
                        await client.query("ROLLBACK")
                        break
                    }
                    console.log(`[<OK>] - Database module [${module.key}]: DONE!`)
                }else{
                    console.log(`[<OK>] - Database module [${module.key}] already updated!`)
                }

                if(!migrate_mod_field) migrate_mod_field = await checkMigrationModuleField(client)

            }else{
                console.warn (`[~KO~] - Database module ${module.key} NOT FOUND`)
            }
        }
        if(empty_database)
            console.log("[<OK>] - Database installed!")
        else
            console.log("[<OK>] - Database updated!")
        //----------------------------------------------------------------------------------------
    } catch (err) {
        console.error(err)
    } finally {
        await client.end()
    }
}
//--------------------------------------------------------------------------------------
async function killActiveSessions(pgConfig, callback){
    pgConfig["database"] = 'postgres'
    const pgClient = new Client(pgConfig)
    try {
        await pgClient.connect()
        console.log(`Killing active sessions of ${DEFAULT_CONFIG.database}...`)
        let sql = `
            SELECT pg_terminate_backend(pid)
            FROM pg_stat_activity
            WHERE datname = '${DEFAULT_CONFIG.database}' 
              AND leader_pid IS NULL`

        await pgClient.query(sql)
        console.log(`Active sessions of ${DEFAULT_CONFIG.database} killed!`)
        callback(true)
    } catch(e) {
        console.error(`${e}`)
        callback(false)
    } finally {
        await pgClient.end()
    }
}
//--------------------------------------------------------------------------------------
let config = {
    host: DEFAULT_CONFIG.host,
    port: DEFAULT_CONFIG.port,
    database: DEFAULT_CONFIG.database,
    user: DEFAULT_CONFIG.user,
    password: DEFAULT_CONFIG.password,
    schema: DEFAULT_CONFIG.schema,
}

if(DEFAULT_CONFIG.replace){
    let pgConfig = {
        host: config.host,
        port: config.port,
        user: config.user,
        password: config.password
    }
    killActiveSessions(pgConfig, function(result){
        if(result){
            pgtools.dropdb(pgConfig, DEFAULT_CONFIG.database, function(err, res){
                let err_message = `${err}`
                if(!err || err_message.includes("invalid_catalog_name")) connect(config, migrate)
                else console.error(err_message)
            })
        }
    })
}else{
    connect(config, migrate)
}
//--------------------------------------------------------------------------------------


