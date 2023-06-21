-- This file aims to test toolkit hyperfunctions and see if they work properly after migration or not.
-- This is done by creating Caggs using toolkit functions as we would expect the users to do. These
-- Caggs will be compared after migration

select $help$
This script needs base.sql to be applied.

Note:
- 'hypertables_schema' should be same as what was supplied in 'hypertables_schema' in base.sql
- 'num_hypertables' should be less than or equal to 'num_hypertables' supplied in base.sql

Usage:
psql -d "URI" -f toolkit.sql \
    -v hypertables_schema='timeseries' \
    -v num_hypertables=20 \
    -v gapfilling_start_ts='2023-01-01' \
    -v gapfilling_end_ts='2023-03-31'

$help$ as help_output
\gset

--------------------------------------------------------------------------------
-- display help and exit?
\if :{?help}
\echo :help_output
\q
\endif

CREATE EXTENSION IF NOT EXISTS timescaledb_toolkit;

CREATE OR REPLACE FUNCTION create_financial_analysis_matviews(
    num_hypertables INTEGER,
    hypertables_schema VARCHAR
) RETURNS VOID AS $$
DECLARE
    count integer;
BEGIN
    FOR count IN 1..num_hypertables LOOP
        EXECUTE format(
        $sql$
            CREATE MATERIALIZED VIEW %I.toolkit_cagg_financial_%s WITH (timescaledb.continuous) AS
            SELECT
                time_bucket('1 day'::interval, "time") as day,
                open(candlestick_agg("time", col1, col2)),
                close(candlestick_agg("time", col1, col3)),
                high(candlestick_agg("time", col1, col4)),
                high_time(candlestick_agg("time", col1, col4)),
                low(candlestick_agg("time", col1, col5)),
                low_time(candlestick_agg("time", col1, col5)),
                volume(candlestick_agg("time", col1, col5))
            FROM %I.table_%s
            GROUP BY 1 ORDER BY 1 DESC
            WITH NO DATA;
        $sql$, hypertables_schema, count, hypertables_schema, count);

        EXECUTE format($sql$
        SELECT add_continuous_aggregate_policy('%I.toolkit_cagg_financial_%s',
                start_offset => INTERVAL '1 week',
                end_offset => INTERVAL '1 day',
                schedule_interval => INTERVAL '1 day');
        $sql$, hypertables_schema, count);

        RAISE NOTICE 'Completed cagg: %.toolkit_cagg_financial_%', hypertables_schema, count;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

SELECT create_financial_analysis_matviews(:'num_hypertables', :'hypertables_schema');

CREATE OR REPLACE FUNCTION create_statistical_analysis_matviews(
    num_hypertables INTEGER,
    hypertables_schema VARCHAR
) RETURNS VOID AS $$
DECLARE
    count integer;
BEGIN
    FOR count IN 1..num_hypertables LOOP
        EXECUTE format(
        $sql$
            CREATE MATERIALIZED VIEW %I.toolkit_cagg_statistical_%s WITH (timescaledb.continuous) AS
            SELECT
                time_bucket('1 day', time) as day,
                sum(stats_agg(col1)),
                average(stats_agg(col1)),
                stddev(stats_agg(col1)),
                variance(stats_agg(col1))
            FROM %I.table_%s
            GROUP BY 1 ORDER BY 1 DESC
            WITH NO DATA;
        $sql$, hypertables_schema, count, hypertables_schema, count);

        EXECUTE format($sql$
        SELECT add_continuous_aggregate_policy('%I.toolkit_cagg_statistical_%s',
                start_offset => INTERVAL '1 week',
                end_offset => INTERVAL '1 day',
                schedule_interval => INTERVAL '1 day');
        $sql$, hypertables_schema, count);

        RAISE NOTICE 'Completed cagg: %.toolkit_cagg_statistical_%', hypertables_schema, count;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

SELECT create_statistical_analysis_matviews(:'num_hypertables', :'hypertables_schema');
