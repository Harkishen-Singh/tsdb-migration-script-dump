-- For detailed verification, pass -v detail=1
-- Note: Detailed outputs will be lengthy!

\t

-- function that gets the schema structure of all tables (plain + hypertables) in the database.
CREATE OR REPLACE FUNCTION get_table_information()
RETURNS TABLE (
    ret_table_schema text,
    ret_table_name text,
    ret_column_name text,
    ret_data_type text,
    ret_character_maximum_length int
) AS $$
BEGIN
    CREATE TEMP TABLE temp_table ON COMMIT DROP AS
    SELECT
        table_schema::text,
        table_name::text,
        column_name::text,
        data_type::text,
        character_maximum_length::int
    FROM
        information_schema.columns
    WHERE
        table_name IN (SELECT table_name
                       FROM information_schema.tables
                       WHERE table_schema NOT IN ('pg_catalog', 'information_schema'))
        AND table_schema IN (SELECT table_schema
                             FROM information_schema.tables
                             WHERE table_schema NOT IN ('pg_catalog', 'information_schema'))
    ORDER BY
        table_schema,
        table_name,
        ordinal_position;

    RETURN QUERY SELECT * FROM temp_table;
END
$$ LANGUAGE plpgsql;

SELECT * FROM get_table_information();

\if :{?detail}
-- LONG SCRIPTS. Run on purpose only.

-- Get all indexes in the db
SELECT t.relname as table_name,
       i.relname as index_name,
       a.attname as column_name
FROM   pg_class t,
       pg_class i,
       pg_index ix,
       pg_attribute a
WHERE  t.oid = ix.indrelid
       AND i.oid = ix.indexrelid
       AND a.attrelid = t.oid
       AND a.attnum = ANY(ix.indkey)
       AND t.relkind = 'r'
       AND t.relname NOT LIKE 'pg_%'
      ORDER BY 1, 2, 3;

-- Get all constraints in the db.
SELECT conname, conrelid::regclass, contype
FROM   pg_constraint
WHERE  connamespace::regnamespace::text NOT LIKE 'pg_%'
ORDER  BY conrelid::regclass::text, contype, conname;

-- Get all triggers in the db.
SELECT event_object_table as table_name,
       trigger_name,
       action_timing,
       event_manipulation,
       action_statement
FROM   information_schema.triggers
WHERE  event_object_schema NOT LIKE 'pg_%'
ORDER  BY 1, 2, 3, 4, 5;

\else

-- Count of all indexes in the db
SELECT count(*) FROM (SELECT t.relname as table_name,
       i.relname as index_name,
       a.attname as column_name
FROM   pg_class t,
       pg_class i,
       pg_index ix,
       pg_attribute a
WHERE  t.oid = ix.indrelid
       AND i.oid = ix.indexrelid
       AND a.attrelid = t.oid
       AND a.attnum = ANY(ix.indkey)
       AND t.relkind = 'r'
       AND t.relname NOT LIKE 'pg_%'
      ORDER BY 1, 2, 3) a;

-- Get all constraints in the db.
SELECT count(*) FROM (SELECT conname, conrelid::regclass, contype
FROM   pg_constraint
WHERE  connamespace::regnamespace::text NOT LIKE 'pg_%'
ORDER  BY conrelid::regclass::text, contype, conname) a;

-- Get all triggers in the db.
SELECT count(*) FROM (SELECT event_object_table as table_name,
       trigger_name,
       action_timing,
       event_manipulation,
       action_statement
FROM   information_schema.triggers
WHERE  event_object_schema NOT LIKE 'pg_%'
ORDER  BY 1, 2, 3, 4, 5) a;

\endif

-- Get sequences in the db.
CREATE OR REPLACE FUNCTION get_sequence_values()
RETURNS TABLE (
    seq_schema text,
    seq_name text,
    seq_value bigint
) AS $$
BEGIN
    CREATE TEMP TABLE temp_sequence_values ON COMMIT DROP AS
    SELECT sequence_schema::text, sequence_name::text, NULL::bigint AS last_value
    FROM information_schema.sequences
    WHERE sequence_schema NOT IN ('pg_catalog', 'information_schema');

    FOR seq_schema, seq_name IN (SELECT sequence_schema, sequence_name
                                  FROM temp_sequence_values)
    LOOP
        EXECUTE format('SELECT last_value FROM %I.%I', seq_schema, seq_name) INTO seq_value;
        UPDATE temp_sequence_values
        SET last_value = seq_value
        WHERE sequence_schema = seq_schema AND sequence_name = seq_name;
    END LOOP;

    RETURN QUERY SELECT * FROM temp_sequence_values;
END
$$ LANGUAGE plpgsql;

-- Get continuous aggregates.
SELECT
    view_owner,
    view_schema,
    view_name,
    hypertable_schema,
    hypertable_name,
    compression_enabled,
    materialization_hypertable_schema,
    materialization_hypertable_name
FROM timescaledb_information.continuous_aggregates ORDER BY 1, 2, 3, 4, 5;

-- Get Hypertables.
SELECT * FROM timescaledb_information.hypertables ORDER BY 1, 2, 3, 4;

-- Get policies along with their statistics.
SELECT
    application_name,
    schedule_interval,
    max_runtime,
    proc_schema || '.' || proc_name as proc_schema_and_name,
    j.hypertable_schema || '.' || j.hypertable_name as hypertable_name_schema,
    scheduled,
    fixed_schedule,
    config,
    j.next_start is not null next_start_exists,
    last_run_started_at < last_successful_finish most_recent_job_succeeded
FROM timescaledb_information.jobs j JOIN timescaledb_information.job_stats js ON j.job_id = js.job_id
ORDER BY 1, 4, 5;
