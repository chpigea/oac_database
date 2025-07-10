-- pg_prove --dbname postgres --runtests -U postgres --schema test
---------------------------------------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS :SCHEMANAME ;
---------------------------------------------------------------------------------------------------
SET search_path = public, :SCHEMANAME ; 
---------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION :SCHEMANAME.add_GpsPointRaw(
    v_year INTEGER, v_lon NUMERIC, v_lat NUMERIC, v_code INTEGER DEFAULT 0, v_timestamp BIGINT DEFAULT 0
) RETURNS BOOLEAN AS $$
-- Utility to add GpsPointRaw record for tests
BEGIN    
    INSERT INTO GPSPOINTSRAW(WORKYEAR,EVENTCODEID,USERID,DEVICEID,INSTRUMENTID,SYSTEMTIMESTAMP,GPSTIMESTAMP,SAVEDTIMESTAMP,
        STATUS,LAT,LON,MEASURE,SECONDARYMEASURE,ISRELATIVE,INSTRUMENTALARM,ALARMNOTIFICATION,BATTERYLEVEL,PUMPFLOW,GEOM) 
    VALUES (v_year,v_code,0,0,0,v_timestamp,v_timestamp,v_timestamp,'TEST',v_lat,v_lon,0.5,0.6,0,0,0,20,20,ST_GEOMFROMTEXT('POINT(' || v_lon || ' ' || v_lat || ')',4326));    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;
---------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION :SCHEMANAME.add_Pipe(
    v_year INTEGER, v_geom GEOMETRY, v_radius NUMERIC
) RETURNS BIGINT AS $$
-- Utility to add Pipe record for tests
DECLARE
    v_length NUMERIC;
    v_id BIGINT;
BEGIN    
    v_id := nextval('pipes_id_seq');
    v_length:=ST_LENGTH(v_geom::GEOGRAPHY);
    INSERT INTO PIPES(ID,WORKYEAR,PIPETYPEID,PLANT,ADMINISTRATION,STREET,PIECESCOUNT,PIPESTATUSID,LENGTHM,LENGTHG,GEOM,BUFF) 
    VALUES (v_id,v_year,0,'PLANT','ADMIN','STREET',0,0,v_length,v_length,v_geom, ST_BUFFER(v_geom::GEOGRAPHY,v_radius)::GEOMETRY);    
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;
---------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION :SCHEMANAME.add_PipePiece(
    v_year INTEGER, v_pipeid BIGINT, v_start NUMERIC, v_end NUMERIC
) RETURNS BIGINT AS $$
-- Utility to add Pipe piece record for tests
DECLARE
    v_id BIGINT;
BEGIN   
    v_id := nextval('pipepieces_id_seq');
    INSERT INTO PIPEPIECES(ID,WORKYEAR,PIPEID,STARTM,ENDM,GEOM) 
    SELECT v_id,v_year, v_pipeid, v_start, v_end, ST_LineSubstring(GEOM, v_start, v_end)
    FROM PIPES 
    WHERE WORKYEAR=v_year AND ID=v_pipeid;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;
---------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION :SCHEMANAME.setup_insert(
) RETURNS SETOF TEXT AS $$
-- Test setup. Add specific year (1900) for tests (with relatives table partitions).
BEGIN
    INSERT INTO WORKYEARS(year,starttimestamp) VALUES (1900,0);
END;
$$ LANGUAGE plpgsql;
---------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION :SCHEMANAME.test_getversion(
) RETURNS SETOF TEXT AS $$
-- Test Gis360 API version
BEGIN
    RETURN NEXT is( LENGTH(Gis360_GetVersion())>0, TRUE, 'Should have API version' );
END;
$$ LANGUAGE plpgsql;
---------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION :SCHEMANAME.test_pgversion(
) RETURNS SETOF TEXT AS $$
-- Test Postgres version
DECLARE
    v_version INTEGER:= 100005;
BEGIN
    RETURN NEXT is( pg_version_num() >= v_version, TRUE, 'Should have PostgreSQL version >= ' || v_version );
END;
$$ LANGUAGE plpgsql;
---------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION :SCHEMANAME.test_partitions(
) RETURNS SETOF TEXT AS $$
-- Test create partition on insert into table WORKYEARS
BEGIN
    RETURN NEXT is( year, 1900, 'Should have year as 1900') 
    FROM WORKYEARS WHERE YEAR=1900;
    RETURN NEXT has_table( 'public'::name, 'gpspointsraw_1900'::name );
    RETURN NEXT has_table( 'public'::name, 'pipes_1900'::name );
    RETURN NEXT has_table( 'public'::name, 'pipepieces_1900'::name );
    RETURN NEXT has_table( 'public'::name, 'events_1900'::name ); 
END;
$$ LANGUAGE plpgsql;
---------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION :SCHEMANAME.test_gpspointsraw_protect(
) RETURNS SETOF TEXT AS $$
-- Test protect table GPSPOINTSRAW from accidental Delete/Update command
DECLARE
    v_ret BOOLEAN;
BEGIN
    
    v_ret := test.add_GpsPointRaw(1900, 11.5, 43.2, 0);
    
    RETURN NEXT is( t.cnt, 1, 'Should exists 1 record') 
    FROM ( SELECT COUNT(0)::INTEGER CNT FROM GPSPOINTSRAW WHERE WORKYEAR=1900) t;
    
    PREPARE gpspointsraw_delete_test AS DELETE FROM GPSPOINTSRAW WHERE WORKYEAR=1900;
    RETURN NEXT throws_ok( 'gpspointsraw_delete_test', 'Unable to update or delete records on table GPSPOINTSRAW' );
    
    PREPARE gpspointsraw_update_test AS UPDATE GPSPOINTSRAW SET SPEED=10 WHERE WORKYEAR=1900;    
    RETURN NEXT throws_ok( 'gpspointsraw_update_test', 'Unable to update or delete records on table GPSPOINTSRAW' );
    
END;
$$ LANGUAGE plpgsql;
---------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION :SCHEMANAME.test_getworkday(
) RETURNS SETOF TEXT AS $$
-- Test Gis360_GetWorkDay function
BEGIN
    RETURN NEXT is( t.value, '2018-04-10', 'Should be return timestamp to varchar in format YYYY-MM-DD') 
    FROM ( SELECT Gis360_GetWorkDay(1523349390000) As value) t;
END;
$$ LANGUAGE plpgsql;
---------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION :SCHEMANAME.test_elaborateSessionData_01(
) RETURNS SETOF TEXT AS $$
-- Test Gis360_ElaborateSessionData function
-- Case with Gps Point data all in the same pipe. Data activates the first part of the pipe.
DECLARE
    v_year INTEGER := 1900;
    v_radius NUMERIC := 7.5;
    v_ret BOOLEAN;
    v_pipe GEOMETRY;
    v_pt GEOMETRY;
    v_time BIGINT:=Gis360_GpstimestampFromWorkDay('1900-01-01');
    v_id BIGINT;
BEGIN
    v_pipe := ST_TRANSFORM(ST_SETSRID('LINESTRING(787473 4650133, 787573 4650133)'::GEOMETRY,32632), 4326);
    v_id := test.add_Pipe( v_year, v_pipe, v_radius);
    
    RETURN NEXT is( v_id>0, TRUE, 'Should be true after adding pipe'); 
    
    v_pt := ST_TRANSFORM(ST_SETSRID('POINT(787475 4650133)'::GEOMETRY,32632), 4326);
    v_ret := test.add_GpsPointRaw(v_year, ST_X(v_pt)::NUMERIC, ST_Y(v_pt)::NUMERIC, 0, v_time);
    v_pt := ST_TRANSFORM(ST_SETSRID('POINT(787476 4650136)'::GEOMETRY,32632), 4326);
    v_ret := test.add_GpsPointRaw(v_year, ST_X(v_pt)::NUMERIC, ST_Y(v_pt)::NUMERIC, 0, v_time+1000);
    v_pt := ST_TRANSFORM(ST_SETSRID('POINT(787477 4650136)'::GEOMETRY,32632), 4326);
    v_ret := test.add_GpsPointRaw(v_year, ST_X(v_pt)::NUMERIC, ST_Y(v_pt)::NUMERIC, 0, v_time+2000);
    v_pt := ST_TRANSFORM(ST_SETSRID('POINT(787478 4650136)'::GEOMETRY,32632), 4326);
    v_ret := test.add_GpsPointRaw(v_year, ST_X(v_pt)::NUMERIC, ST_Y(v_pt)::NUMERIC, 0, v_time+3000);
    
    
    RETURN NEXT is( t.cnt, 1, 'Should exists 1 PIPES record') 
    FROM ( SELECT COUNT(0)::INTEGER CNT FROM PIPES WHERE WORKYEAR=1900) t;
    
    RETURN NEXT is( t.cnt, 4, 'Should exists 4 GPSPOINTSRAW records') 
    FROM ( SELECT COUNT(0)::INTEGER CNT FROM GPSPOINTSRAW WHERE WORKYEAR=1900) t;
    
    v_ret := gis360_ElaborateSessionData(Gis360_GetWorkDay(v_time), 0, 0, 0, 1.5);
    
    RETURN NEXT is( t.cnt, 1, 'Should exists 1 record') 
    FROM ( SELECT COUNT(0)::INTEGER CNT FROM PIPEPIECES WHERE WORKYEAR=1900) t;
    
    RETURN NEXT is( t.cnt, 2, 'Should exists 2 records') 
    FROM ( SELECT COUNT(0)::INTEGER CNT FROM EVENTS WHERE WORKYEAR=1900) t;
    
    -- Start point
    RETURN NEXT is( ROUND(t.x::NUMERIC, 2),  787473.00, 'The X coordinate of the start point of the 1st pipe piece should be 787473.00') 
    FROM ( SELECT ST_X(ST_StartPoint(ST_TRANSFORM(geom,32632))) x FROM PIPEPIECES WHERE WORKYEAR=1900) t;
    RETURN NEXT is( ROUND(t.y::NUMERIC, 2), 4650133.00, 'The Y coordinate of the start point of the 1st pipe piece should be 4650133.00') 
    FROM ( SELECT ST_Y(ST_StartPoint(ST_TRANSFORM(geom,32632))) y FROM PIPEPIECES WHERE WORKYEAR=1900) t;
    -- End point
    RETURN NEXT is( ROUND(t.x::NUMERIC, 2),  787479.55, 'The X coordinate of the end point of the 1st pipe piece should be 787479.55') 
    FROM ( SELECT ST_X(ST_EndPoint(ST_TRANSFORM(geom,32632))) x FROM PIPEPIECES WHERE WORKYEAR=1900) t;
    RETURN NEXT is( ROUND(t.y::NUMERIC, 2), 4650133.00, 'The Y coordinate of the end point of the 1st pipe piece should be 4650133.00') 
    FROM ( SELECT ST_Y(ST_EndPoint(ST_TRANSFORM(geom,32632))) y FROM PIPEPIECES WHERE WORKYEAR=1900) t;
    
END;
$$ LANGUAGE plpgsql;
---------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION :SCHEMANAME.test_elaborateSessionData_02(
) RETURNS SETOF TEXT AS $$
-- Test Gis360_ElaborateSessionData function
-- Case with Gps Point data all in the same pipe. Data activates two parts of the pipe.
DECLARE
    v_year INTEGER := 1900;
    v_radius NUMERIC := 7.5;
    v_ret BOOLEAN;
    v_pipe GEOMETRY;
    v_pt GEOMETRY;
    v_time BIGINT:=Gis360_GpstimestampFromWorkDay('1900-01-01');
    v_id BIGINT;
BEGIN
    v_pipe := ST_TRANSFORM(ST_SETSRID('LINESTRING(787473 4650133, 787573 4650133)'::GEOMETRY,32632), 4326);
    v_id := test.add_Pipe( v_year, v_pipe, v_radius);
    
    RETURN NEXT is( v_id>0, TRUE, 'Should be true after adding pipe'); 
    
    v_pt := ST_TRANSFORM(ST_SETSRID('POINT(787475 4650133)'::GEOMETRY,32632), 4326);
    v_ret := test.add_GpsPointRaw(v_year, ST_X(v_pt)::NUMERIC, ST_Y(v_pt)::NUMERIC, 0, v_time);
    v_pt := ST_TRANSFORM(ST_SETSRID('POINT(787476 4650136)'::GEOMETRY,32632), 4326);
    v_ret := test.add_GpsPointRaw(v_year, ST_X(v_pt)::NUMERIC, ST_Y(v_pt)::NUMERIC, 0, v_time+1000);
    v_pt := ST_TRANSFORM(ST_SETSRID('POINT(787477 4650136)'::GEOMETRY,32632), 4326);
    v_ret := test.add_GpsPointRaw(v_year, ST_X(v_pt)::NUMERIC, ST_Y(v_pt)::NUMERIC, 0, v_time+2000);
    v_pt := ST_TRANSFORM(ST_SETSRID('POINT(787478 4650136)'::GEOMETRY,32632), 4326);
    v_ret := test.add_GpsPointRaw(v_year, ST_X(v_pt)::NUMERIC, ST_Y(v_pt)::NUMERIC, 0, v_time+3000);

    v_pt := ST_TRANSFORM(ST_SETSRID('POINT(787569 4650136)'::GEOMETRY,32632), 4326);
    v_ret := test.add_GpsPointRaw(v_year, ST_X(v_pt)::NUMERIC, ST_Y(v_pt)::NUMERIC, 0, v_time+4000);
    v_pt := ST_TRANSFORM(ST_SETSRID('POINT(787570 4650136)'::GEOMETRY,32632), 4326);
    v_ret := test.add_GpsPointRaw(v_year, ST_X(v_pt)::NUMERIC, ST_Y(v_pt)::NUMERIC, 0, v_time+5000);
    v_pt := ST_TRANSFORM(ST_SETSRID('POINT(787571 4650136)'::GEOMETRY,32632), 4326);
    v_ret := test.add_GpsPointRaw(v_year, ST_X(v_pt)::NUMERIC, ST_Y(v_pt)::NUMERIC, 0, v_time+6000);
    v_pt := ST_TRANSFORM(ST_SETSRID('POINT(787572 4650136)'::GEOMETRY,32632), 4326);
    v_ret := test.add_GpsPointRaw(v_year, ST_X(v_pt)::NUMERIC, ST_Y(v_pt)::NUMERIC, 0, v_time+7000);
    
    RETURN NEXT is( t.cnt, 1, 'Should exists 1 PIPES record') 
    FROM ( SELECT COUNT(0)::INTEGER CNT FROM PIPES WHERE WORKYEAR=1900) t;
    
    RETURN NEXT is( t.cnt, 8, 'Should exists 8 GPSPOINTSRAW records') 
    FROM ( SELECT COUNT(0)::INTEGER CNT FROM GPSPOINTSRAW WHERE WORKYEAR=1900) t;
    
    v_ret := gis360_ElaborateSessionData(Gis360_GetWorkDay(v_time), 0, 0, 0, 1.5);
    
    RETURN NEXT is( t.cnt, 2, 'Should exists 2 pipe pieces') 
    FROM ( SELECT COUNT(0)::INTEGER CNT FROM PIPEPIECES WHERE WORKYEAR=1900) t;
    
    RETURN NEXT is( t.cnt, 3, 'Should exists 3 events') 
    FROM ( SELECT COUNT(0)::INTEGER CNT FROM EVENTS WHERE WORKYEAR=1900) t;
    
    -- First pipe piece
        -- Start point
    RETURN NEXT is( ROUND(t.x::NUMERIC, 2),  787473.00, 'The X coordinate of the start point of the 1st pipe piece should be 787473.00') 
    FROM ( SELECT ST_X(ST_StartPoint(ST_TRANSFORM(geom,32632))) x FROM PIPEPIECES WHERE WORKYEAR=1900 LIMIT 1 OFFSET 0) t;
    RETURN NEXT is( ROUND(t.y::NUMERIC, 2), 4650133.00, 'The Y coordinate of the start point of the 1st pipe piece should be 4650133.00') 
    FROM ( SELECT ST_Y(ST_StartPoint(ST_TRANSFORM(geom,32632))) y FROM PIPEPIECES WHERE WORKYEAR=1900 LIMIT 1 OFFSET 0) t;
        -- End point
    RETURN NEXT is( ROUND(t.x::NUMERIC, 2),  787479.55, 'The X coordinate of the end point of the 1st pipe piece should be 787479.55') 
    FROM ( SELECT ST_X(ST_EndPoint(ST_TRANSFORM(geom,32632))) x FROM PIPEPIECES WHERE WORKYEAR=1900 LIMIT 1 OFFSET 0) t;
    RETURN NEXT is( ROUND(t.y::NUMERIC, 2), 4650133.00, 'The Y coordinate of the end point of the 1st pipe piece should be 4650133.00') 
    FROM ( SELECT ST_Y(ST_EndPoint(ST_TRANSFORM(geom,32632))) y FROM PIPEPIECES WHERE WORKYEAR=1900 LIMIT 1 OFFSET 0) t;
    
     -- Second pipe piece
        -- Start point
    RETURN NEXT is( ROUND(t.x::NUMERIC, 2),  787567.55, 'The X coordinate of the start point of the 2nd pipe piece should be 787567.55') 
    FROM ( SELECT ST_X(ST_StartPoint(ST_TRANSFORM(geom,32632))) x FROM PIPEPIECES WHERE WORKYEAR=1900 LIMIT 1 OFFSET 1) t;
    RETURN NEXT is( ROUND(t.y::NUMERIC, 2), 4650133.00, 'The Y coordinate of the start point of the 2nd pipe piece should be 4650133.00') 
    FROM ( SELECT ST_Y(ST_StartPoint(ST_TRANSFORM(geom,32632))) y FROM PIPEPIECES WHERE WORKYEAR=1900 LIMIT 1 OFFSET 1) t;
        -- End point
    RETURN NEXT is( ROUND(t.x::NUMERIC, 2),  787573.00, 'The X coordinate of the end point of the 2nd pipe piece should be 787573.00') 
    FROM ( SELECT ST_X(ST_EndPoint(ST_TRANSFORM(geom,32632))) x FROM PIPEPIECES WHERE WORKYEAR=1900 LIMIT 1 OFFSET 1) t;
    RETURN NEXT is( ROUND(t.y::NUMERIC, 2), 4650133.00, 'The Y coordinate of the end point of the 2nd pipe piece should be 4650133.00') 
    FROM ( SELECT ST_Y(ST_EndPoint(ST_TRANSFORM(geom,32632))) y FROM PIPEPIECES WHERE WORKYEAR=1900 LIMIT 1 OFFSET 1) t;
    
END;
$$ LANGUAGE plpgsql;
---------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION :SCHEMANAME.test_elaborateSessionData_03(
) RETURNS SETOF TEXT AS $$
-- Test Gis360_ElaborateSessionData function
-- Case with Gps Point data outside the same pipe (but near at start/end points). Data activates two parts of the pipe. 
DECLARE
    v_year INTEGER := 1900;
    v_radius NUMERIC := 7.5;
    v_ret BOOLEAN;
    v_pipe GEOMETRY;
    v_pt GEOMETRY;
    v_time BIGINT := Gis360_GpstimestampFromWorkDay('1900-01-01');
    geomtext VARCHAR;
    v_id BIGINT;
BEGIN
    v_pipe := ST_TRANSFORM(ST_SETSRID('LINESTRING(787473 4650133, 787573 4650133)'::GEOMETRY,32632), 4326);
    v_id := test.add_Pipe( v_year, v_pipe, v_radius);
    
    RETURN NEXT is( v_id>0, TRUE, 'Should be true after adding pipe'); 
    
    v_pt := ST_TRANSFORM(ST_SETSRID('POINT(787472 4650134)'::GEOMETRY,32632), 4326);
    v_ret := test.add_GpsPointRaw(v_year, ST_X(v_pt)::NUMERIC, ST_Y(v_pt)::NUMERIC, 0, v_time);
    
    v_pt := ST_TRANSFORM(ST_SETSRID('POINT(787574 4650132)'::GEOMETRY,32632), 4326);
    v_ret := test.add_GpsPointRaw(v_year, ST_X(v_pt)::NUMERIC, ST_Y(v_pt)::NUMERIC, 0, v_time+1000);
    
    RETURN NEXT is( t.cnt, 1, 'Should exists 1 PIPES record') 
    FROM ( SELECT COUNT(0)::INTEGER CNT FROM PIPES WHERE WORKYEAR=1900) t;
    
    RETURN NEXT is( t.cnt, 2, 'Should exists 2 GPSPOINTSRAW records') 
    FROM ( SELECT COUNT(0)::INTEGER CNT FROM GPSPOINTSRAW WHERE WORKYEAR=1900) t;
    
    v_ret := gis360_ElaborateSessionData(Gis360_GetWorkDay(v_time), 0, 0, 0, 1.5);    
    
    RETURN NEXT is( t.cnt, 2, 'Should exists 2 events records') 
    FROM ( SELECT COUNT(0)::INTEGER CNT FROM EVENTS WHERE WORKYEAR=1900) t;
    
    RETURN NEXT is( t.cnt, 2, 'Should exists 2 pipe pieces records') 
    FROM ( SELECT COUNT(0)::INTEGER CNT FROM PIPEPIECES WHERE WORKYEAR=1900) t;
    
    -- First pipe piece
        -- Start point
    RETURN NEXT is( ROUND(t.x::NUMERIC, 2),  787473.00, 'The X coordinate of the start point of the 1st pipe piece should be 787473.00') 
    FROM ( SELECT ST_X(ST_StartPoint(ST_TRANSFORM(geom,32632))) x FROM PIPEPIECES WHERE WORKYEAR=1900 LIMIT 1 OFFSET 0) t;
    RETURN NEXT is( ROUND(t.y::NUMERIC, 2), 4650133.00, 'The Y coordinate of the start point of the 1st pipe piece should be 4650133.00') 
    FROM ( SELECT ST_Y(ST_StartPoint(ST_TRANSFORM(geom,32632))) y FROM PIPEPIECES WHERE WORKYEAR=1900 LIMIT 1 OFFSET 0) t;
        -- End point
    RETURN NEXT is( ROUND(t.x::NUMERIC, 2),  787474.50, 'The X coordinate of the end point of the 1st pipe piece should be 787474.50') 
    FROM ( SELECT ST_X(ST_EndPoint(ST_TRANSFORM(geom,32632))) x FROM PIPEPIECES WHERE WORKYEAR=1900 LIMIT 1 OFFSET 0) t;
    RETURN NEXT is( ROUND(t.y::NUMERIC, 2), 4650133.00, 'The Y coordinate of the end point of the 1st pipe piece should be 4650133.00') 
    FROM ( SELECT ST_Y(ST_EndPoint(ST_TRANSFORM(geom,32632))) y FROM PIPEPIECES WHERE WORKYEAR=1900 LIMIT 1 OFFSET 0) t;
    
     -- Second pipe piece
        -- Start point
    RETURN NEXT is( ROUND(t.x::NUMERIC, 2),  787571.50, 'The X coordinate of the start point of the 2nd pipe piece should be 787571.50') 
    FROM ( SELECT ST_X(ST_StartPoint(ST_TRANSFORM(geom,32632))) x FROM PIPEPIECES WHERE WORKYEAR=1900 LIMIT 1 OFFSET 1) t;
    RETURN NEXT is( ROUND(t.y::NUMERIC, 2), 4650133.00, 'The Y coordinate of the start point of the 2nd pipe piece should be 4650133.00') 
    FROM ( SELECT ST_Y(ST_StartPoint(ST_TRANSFORM(geom,32632))) y FROM PIPEPIECES WHERE WORKYEAR=1900 LIMIT 1 OFFSET 1) t;
        -- End point
    RETURN NEXT is( ROUND(t.x::NUMERIC, 2),  787573.00, 'The X coordinate of the end point of the 2nd pipe piece should be 787573.00') 
    FROM ( SELECT ST_X(ST_EndPoint(ST_TRANSFORM(geom,32632))) x FROM PIPEPIECES WHERE WORKYEAR=1900 LIMIT 1 OFFSET 1) t;
    RETURN NEXT is( ROUND(t.y::NUMERIC, 2), 4650133.00, 'The Y coordinate of the end point of the 2nd pipe piece should be 4650133.00') 
    FROM ( SELECT ST_Y(ST_EndPoint(ST_TRANSFORM(geom,32632))) y FROM PIPEPIECES WHERE WORKYEAR=1900 LIMIT 1 OFFSET 1) t;
    
END;
$$ LANGUAGE plpgsql;
---------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION :SCHEMANAME.test_AdjustPiecesOfPipe_01(
) RETURNS SETOF TEXT AS $$
--Test Gis360_AdjustPiecesOfPipe
DECLARE
    v_year INTEGER := 1900;
    v_toll NUMERIC := 1.5;
    v_radius NUMERIC := 7.5;
    v_ret BOOLEAN;
    v_pipeid BIGINT;
    v_id BIGINT;
    v_pipe GEOMETRY;
BEGIN
    v_pipe := ST_TRANSFORM(ST_SETSRID('LINESTRING(787473 4650133, 787573 4650133)'::GEOMETRY,32632), 4326);
    v_pipeid := test.add_Pipe( v_year, v_pipe, v_radius);
    RETURN NEXT is( v_pipeid>0, TRUE, 'Should be true after adding pipe'); 
    v_id := test.add_PipePiece(v_year, v_pipeid, 0.0, 0.5);
    RETURN NEXT is( v_id>0, TRUE, 'Should be true after adding pipe piece'); 
    v_id := test.add_PipePiece(v_year, v_pipeid, 0.51, 0.6);
    RETURN NEXT is( v_id>0, TRUE, 'Should be true after adding pipe piece'); 
    
    RETURN NEXT is( ROUND(t.glength::NUMERIC, 2), 50.00, 'The length of the 1st pipe piece (before adjust) should be 50.00 m') 
    FROM ( SELECT ST_Length(ST_TRANSFORM(geom,32632)) glength FROM PIPEPIECES WHERE WORKYEAR=1900 LIMIT 1 OFFSET 0) t;
    RETURN NEXT is( ROUND(t.glength::NUMERIC, 2),  9.00, 'The length of the 2nd pipe piece (before adjust) should be 9.00 m') 
    FROM ( SELECT ST_Length(ST_TRANSFORM(geom,32632)) glength FROM PIPEPIECES WHERE WORKYEAR=1900 LIMIT 1 OFFSET 1) t;
    
    v_ret := Gis360_AdjustPiecesOfPipe(v_year, v_pipeid, 1.5);
    RETURN NEXT is( v_ret, TRUE, 'Should be true after adjust pipe pieces'); 
    
    RETURN NEXT is( ROUND(t.glength::NUMERIC, 2), 50.00, 'The length of the 1st pipe piece (after adjust) should be 50.00 m') 
    FROM ( SELECT ST_Length(ST_TRANSFORM(geom,32632)) glength FROM PIPEPIECES WHERE WORKYEAR=1900 LIMIT 1 OFFSET 0) t;
    RETURN NEXT is( ROUND(t.glength::NUMERIC, 2), 10.00, 'The length of the 2nd pipe piece (after adjust) should be 10.00 m') 
    FROM ( SELECT ST_Length(ST_TRANSFORM(geom,32632)) glength FROM PIPEPIECES WHERE WORKYEAR=1900 LIMIT 1 OFFSET 1) t;
    
END;
$$ LANGUAGE plpgsql;
---------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION :SCHEMANAME.test_AdjustPiecesOfPipe_02(
) RETURNS SETOF TEXT AS $$
--Test Gis360_AdjustPiecesOfPipe
DECLARE
    v_year INTEGER := 1900;
    v_toll NUMERIC := 1.5;
    v_radius NUMERIC := 7.5;
    v_ret BOOLEAN;
    v_pipeid BIGINT;
    v_id BIGINT;
    v_pipe GEOMETRY;
BEGIN
    v_pipe := ST_TRANSFORM(ST_SETSRID('LINESTRING(787473 4650133, 787573 4650133)'::GEOMETRY,32632), 4326);
    v_pipeid := test.add_Pipe( v_year, v_pipe, v_radius);
    RETURN NEXT is( v_pipeid>0, TRUE, 'Should be true after adding pipe'); 
    v_id := test.add_PipePiece(v_year, v_pipeid, 0.51, 0.6);
    RETURN NEXT is( v_id>0, TRUE, 'Should be true after adding pipe piece'); 
    v_id := test.add_PipePiece(v_year, v_pipeid, 0.0, 0.5);
    RETURN NEXT is( v_id>0, TRUE, 'Should be true after adding pipe piece'); 
    
    RETURN NEXT is( ROUND(t.glength::NUMERIC, 2),  9.00, 'The length of the 1st pipe piece (before adjust) should be 9.00 m') 
    FROM ( SELECT ST_Length(ST_TRANSFORM(geom,32632)) glength FROM PIPEPIECES WHERE WORKYEAR=1900 LIMIT 1 OFFSET 0) t;
    RETURN NEXT is( ROUND(t.glength::NUMERIC, 2), 50.00, 'The length of the 2nd pipe piece (before adjust) should be 50.00 m') 
    FROM ( SELECT ST_Length(ST_TRANSFORM(geom,32632)) glength FROM PIPEPIECES WHERE WORKYEAR=1900 LIMIT 1 OFFSET 1) t;
    
    v_ret := Gis360_AdjustPiecesOfPipe(v_year, v_pipeid, 1.5);
    RETURN NEXT is( v_ret, TRUE, 'Should be true after adjust pipe pieces'); 
    
    RETURN NEXT is( ROUND(t.glength::NUMERIC, 2),  9.00, 'The length of the 1st pipe piece (after adjust) should be 9.00 m') 
    FROM ( SELECT ST_Length(ST_TRANSFORM(geom,32632)) glength FROM PIPEPIECES WHERE WORKYEAR=1900 LIMIT 1 OFFSET 0) t;
    RETURN NEXT is( ROUND(t.glength::NUMERIC, 2), 51.00, 'The length of the 2nd pipe piece (after adjust) should be 51.00 m') 
    FROM ( SELECT ST_Length(ST_TRANSFORM(geom,32632)) glength FROM PIPEPIECES WHERE WORKYEAR=1900 LIMIT 1 OFFSET 1) t;
    
END;
$$ LANGUAGE plpgsql;
---------------------------------------------------------------------------------------------------
