#!/usr/bin/env bash
set +e
parent_path=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )
cd "$parent_path"

export HOST=10.199.50.108
export PORT=5439
export USER=postgres
export PGPASSWORD=postgrespwd
export OSNAME="`uname -a`"
export PSQL=psql
export LINESEP=`for i in {1..80}; do echo -n =; done`
export TAC=tac

OSNAME="${OSNAME:0:5}" 
if [ "$OSNAME" == "MINGW" ]; then
   PSQL=psql.exe
fi
echo $OSNAME

$PSQL -h $HOST -p $PORT -U $USER -f ./../src/functions.sql -v SCHEMANAME=public
$PSQL -h $HOST -p $PORT -U $USER -f test.sql -v SCHEMANAME=test


if [ "$OSNAME" == "Darwi" ]; then
    TAC=cat    
fi
$PSQL -h $HOST -p $PORT -U $USER --command "SELECT * FROM runtests('test'::name)" --no-psqlrc --no-align --quiet --pset pager=off --pset tuples_only=true --set ON_ERROR_STOP=1 | $TAC > results.tap   

echo $LINESEP
cat results.tap
echo $LINESEP

read -rsp $'Press any key to continue...\n' -n 1 key

exit 0;