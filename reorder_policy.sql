-- Reordering chunks in hypertable is kept as a separate script. This is because
-- reordering is a IO intensive operation, hence we should only test this feature
-- only when we want to.
--
-- Following function creates reordering policies on the Hypertables created in the base script.
-- Make sure to pass the num_hypertables & hypertables_schema same as the values passed for
-- the base script.

select $help$
This script needs base.sql to be applied.

Note:
- 'hypertables_schema' should be same as what was supplied in 'hypertables_schema' in base.sql
- 'num_hypertables' should be less than or equal to 'num_hypertables' supplied in base.sql

Usage:
psql -d "URI" -f reorder_policy.sql \
    -v hypertables_schema='timeseries' \
    -v num_hypertables=20

$help$ as help_output
\gset

--------------------------------------------------------------------------------
-- display help and exit?
\if :{?help}
\echo :help_output
\q
\endif

CREATE OR REPLACE FUNCTION create_reorder_policies(
    num_hypertables INTEGER,
    hypertables_schema VARCHAR
) RETURNS VOID AS $$
DECLARE
    count integer;
BEGIN
    FOR count IN 1..num_hypertables LOOP
        -- Create an index on series_id for each hypertable
        EXECUTE format('CREATE INDEX IF NOT EXISTS table_%s_series_id_idx ON %I.table_%s(series_id);',
                        count, hypertables_schema, count);

        -- Add a reordering policy for each hypertable based on the newly created index
        EXECUTE format('SELECT add_reorder_policy(%L, %L, if_not_exists => true);',
                        hypertables_schema || '.table_' || count, 'table_' || count || '_series_id_idx');

        RAISE NOTICE 'Added reorder policy for hypertable: %.table_%', hypertables_schema, count;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

SELECT create_reorder_policies(:'num_hypertables', :'hypertables_schema');

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
FROM timescaledb_information.jobs j
WHERE application_name LIKE 'Reorder Policy%'
ORDER BY 1 DESC;
