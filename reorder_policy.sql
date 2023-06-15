-- Reordering chunks in hypertable is kept as a separate script. This is because
-- reordering is a IO intensive operation, hence we should only test this feature
-- only when we want to.
--
-- Following function creates reordering policies on the Hypertables created in the base script.
-- Make sure to pass the num_hypertables_in_base & schema_name same as the values passed for
-- the base script.

\set num_hypertables_in_base 2
\set schema_name 'timeseries'

CREATE OR REPLACE FUNCTION create_reorder_policies(
    num_hypertables INTEGER,
    schema_name VARCHAR
) RETURNS VOID AS $$
DECLARE
    count integer;
BEGIN
    FOR count IN 1..num_hypertables LOOP
        -- Create an index on series_id for each hypertable
        EXECUTE format('CREATE INDEX IF NOT EXISTS table_%s_series_id_idx ON %I.table_%s(series_id);',
                        count, schema_name, count);

        -- Add a reordering policy for each hypertable based on the newly created index
        EXECUTE format('SELECT add_reorder_policy(%L, %L, if_not_exists => true);',
                        schema_name || '.table_' || count, 'table_' || count || '_series_id_idx');

        RAISE NOTICE 'Added reorder policy for hypertable: %.table_%', schema_name, count;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

SELECT create_reorder_policies(:'num_hypertables_in_base', :'schema_name');

SELECT
	j.job_id,
    application_name,
    schedule_interval,
    max_runtime,
    proc_schema,
    proc_name,
    scheduled,
    fixed_schedule,
    config
FROM timescaledb_information.jobs j JOIN timescaledb_information.job_stats js ON j.job_id = js.job_id
WHERE application_name LIKE 'Reorder Policy%'
ORDER BY 1 DESC;
