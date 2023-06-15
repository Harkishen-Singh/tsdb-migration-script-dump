-- This file aims to test toolkit hyperfunctions and see if they work properly after migration or not.
-- This is done by creating Caggs using toolkit functions as we would expect the users to do. These
-- Caggs will be compared after migration

-- Number of hypertables on which toolkit functions based Caggs should be applied. Must be <= than hypertables created in base script.
\set num_hypertables 2
\set gapfilling_start_ts '2023-01-01'
\set gapfilling_end_ts '2023-01-07'
-- Same as in base table.
\set schema_name 'timeseries'

CREATE OR REPLACE FUNCTION create_downsampling_matviews(
    num_hypertables INTEGER,
    schema_name VARCHAR
) RETURNS VOID AS $$
DECLARE
    count integer;
BEGIN
    FOR count IN 1..num_hypertables LOOP
        -- Downsampling using asap_sooth.
        EXECUTE format(
        $sql$
            CREATE MATERIALIZED VIEW %I.cagg_downsampling_asap_smooth_%s WITH (timescaledb.continuous) AS
            SELECT
                time_bucket('1 day', time) AS day,
                (unnest(asap_smooth(time, col1, 8))).time as actual_time,
                (unnest(asap_smooth(time, col1, 8))).value as value
            FROM %I.table_%s
            GROUP BY 1 ORDER BY 1 DESC
            WITH NO DATA;
        $sql$, schema_name, count, schema_name, count);

        EXECUTE format($sql$
        SELECT add_continuous_aggregate_policy('%I.cagg_downsampling_asap_smooth_%s',
                start_offset => INTERVAL '1 week',
                end_offset => INTERVAL '1 day',
                schedule_interval => INTERVAL '1 day');
        $sql$, schema_name, count);

        RAISE NOTICE 'Completed cagg: %.cagg_downsampling_asap_smooth_%', schema_name, count;

        -- Downsampling using lttb.
        EXECUTE format(
        $sql$
            CREATE MATERIALIZED VIEW %I.cagg_downsampling_lttb_%s WITH (timescaledb.continuous) AS
            SELECT
                time_bucket('1 day', time) AS day,
                (unnest(lttb(time, col1, 8))).time as actual_time,
                (unnest(lttb(time, col1, 8))).value as value
            FROM %I.table_%s
            GROUP BY 1 ORDER BY 1 DESC
            WITH NO DATA;
        $sql$, schema_name, count, schema_name, count);

        EXECUTE format($sql$
        SELECT add_continuous_aggregate_policy('%I.cagg_downsampling_lttb_%s',
                start_offset => INTERVAL '1 week',
                end_offset => INTERVAL '1 day',
                schedule_interval => INTERVAL '1 day');
        $sql$, schema_name, count);

        RAISE NOTICE 'Completed cagg: %.cagg_downsampling_lttb_%', schema_name, count;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

SELECT create_downsampling_matviews(:'num_hypertables', :'schema_name');

CREATE OR REPLACE FUNCTION create_financial_analysis_matviews(
    num_hypertables INTEGER,
    schema_name VARCHAR
) RETURNS VOID AS $$
DECLARE
    count integer;
BEGIN
    FOR count IN 1..num_hypertables LOOP
        EXECUTE format(
        $sql$
            CREATE MATERIALIZED VIEW %I.cagg_financial_%s WITH (timescaledb.continuous) AS
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
        $sql$, schema_name, count, schema_name, count);

        EXECUTE format($sql$
        SELECT add_continuous_aggregate_policy('%I.cagg_financial_%s',
                start_offset => INTERVAL '1 week',
                end_offset => INTERVAL '1 day',
                schedule_interval => INTERVAL '1 day');
        $sql$, schema_name, count);

        RAISE NOTICE 'Completed cagg: %.cagg_financial_%', schema_name, count;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

SELECT create_financial_analysis_matviews(:'num_hypertables', :'schema_name');

CREATE OR REPLACE FUNCTION create_statistical_analysis_matviews(
    num_hypertables INTEGER,
    schema_name VARCHAR
) RETURNS VOID AS $$
DECLARE
    count integer;
BEGIN
    FOR count IN 1..num_hypertables LOOP
        EXECUTE format(
        $sql$
            CREATE MATERIALIZED VIEW %I.cagg_statistical_%s WITH (timescaledb.continuous) AS
            SELECT
                time_bucket('1 day', time) as day,
                sum(stats_agg(col1)),
                average(stats_agg(col1)),
                stddev(stats_agg(col1)),
                variance(stats_agg(col1))
            FROM %I.table_%s
            GROUP BY 1 ORDER BY 1 DESC
            WITH NO DATA;
        $sql$, schema_name, count, schema_name, count);

        EXECUTE format($sql$
        SELECT add_continuous_aggregate_policy('%I.cagg_statistical_%s',
                start_offset => INTERVAL '1 week',
                end_offset => INTERVAL '1 day',
                schedule_interval => INTERVAL '1 day');
        $sql$, schema_name, count);

        RAISE NOTICE 'Completed cagg: %.cagg_statistical_%', schema_name, count;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

SELECT create_statistical_analysis_matviews(:'num_hypertables', :'schema_name');
