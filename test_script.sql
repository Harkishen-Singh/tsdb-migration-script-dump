-- \set num_hypertables_to_be_created 20
-- \set chunk_interval '1 week'
\set schema_name 'timeseries'
-- \set start_time '2023-01-01'
-- \set end_time '2023-12-31'

-- CREATE EXTENSION IF NOT EXISTS TIMESCALEDB;

-- BEGIN;

-- -- -- Create the schema
-- CREATE SCHEMA IF NOT EXISTS common;

-- DO $$
-- DECLARE
--   i INT;
-- BEGIN
--   -- Create tables and custom types
--   FOR i IN 1..20 LOOP
--     EXECUTE format(
--       $sql$
--       CREATE TYPE custom_type_%s AS ENUM ('Type1', 'Type2', 'Type3');
--       CREATE TABLE common.table%s (
--         id serial primary key,
--         column1 int,
--         column2 varchar(255),
--         column3 custom_type_%s,
--         column4 text,
--         column5 boolean,
--         column6 date,
--         column7 time,
--         column8 timestamp,
--         column9 json,
--         column10 jsonb
--       );
--     $sql$, i, i, i);

--     -- Insert data into the tables
--     FOR j IN 1..100000 LOOP
--       EXECUTE format(
--         $sql$
--         INSERT INTO common.table%s (column1, column2, column3, column4, column5, column6, column7, column8, column9, column10)
--         VALUES (
--           floor(random() * 100)::int,
--           md5(random()::text),
--           (CASE floor(random() * 3)::int WHEN 0 THEN 'Type1' WHEN 1 THEN 'Type2' ELSE 'Type3' END)::custom_type_%s,
--           md5(random()::text),
--           (CASE floor(random() * 2)::int WHEN 0 THEN true ELSE false END),
--           current_date,
--           current_time,
--           current_timestamp,
--           json_build_object('key', md5(random()::text)),
--           jsonb_build_object('key', md5(random()::text))
--         );
--       $sql$, i, i);
--     END LOOP;
--     RAISE NOTICE 'Created table common.table%', i;
--   END LOOP;
-- END $$;

-- END;

-- CREATE SCHEMA IF NOT EXISTS test_schema;

-- -- -- Create Hypertables and insert data.
-- DO
-- $$
-- DECLARE
--     count integer;
--     num_hypertables_to_be_created integer := 10; -- Replace with your desired number
--     schema_name varchar := 'test_schema'; -- Replace with your schema name
--     chunk_interval interval := '1 week'; -- Replace with your desired interval
--     start_time timestamp := '2023-01-01 00:00:00'; -- Replace with your desired start time
--     end_time timestamp := '2023-01-02 00:00:00'; -- Replace with your desired end time
-- BEGIN
--     FOR count IN 1..num_hypertables_to_be_created LOOP
--         EXECUTE format('CREATE TABLE IF NOT EXISTS %I.table_%s (
--                             time timestamptz NOT NULL,
--                             series_id integer NOT NULL,
--                             col1 integer REFERENCES common.table1(id),
--                             col2 integer REFERENCES common.table2(id),
--                             col3 integer REFERENCES common.table3(id),
--                             col4 integer REFERENCES common.table4(id),
--                             col5 integer REFERENCES common.table5(id),
--                             col6 integer REFERENCES common.table6(id),
--                             col7 integer REFERENCES common.table7(id),
--                             col8 integer REFERENCES common.table8(id)
--                         );',
--                         schema_name, count);

--         EXECUTE format('SELECT create_hypertable(%L, %L, chunk_time_interval => interval %L);',
--                         schema_name || '.table_' || count, 'time', chunk_interval);


--         -- EXECUTE format($sql$ ALTER TABLE %I SET (timescaledb.compress, timescaledb.compress_segmentby = 'series_id') $sql$, schema_name || '.table_' || count);

--         EXECUTE format('INSERT INTO %I.table_%s (time, series_id, col1, col2, col3, col4, col5, col6, col7, col8)
--             SELECT
--                 generate_series(TIMESTAMP %L, TIMESTAMP %L, interval %L) AS time,
--                 ceil(random() * 100)::integer AS series_id,
--                 ceil(random() * 100)::integer AS col1,
--                 ceil(random() * 100)::integer AS col2,
--                 ceil(random() * 100)::integer AS col3,
--                 ceil(random() * 100)::integer AS col4,
--                 ceil(random() * 100)::integer AS col5,
--                 ceil(random() * 100)::integer AS col6,
--                 ceil(random() * 100)::integer AS col7,
--                 ceil(random() * 100)::integer AS col8;',
--         schema_name, count, start_time, end_time, '1 minute');

--         -- -- Add a compression policy to compress chunks older than 1 week
--         EXECUTE format('SELECT add_compression_policy(%L, INTERVAL %L)',
--                         schema_name || '.table_' || count, '1 week');

--         -- Add a retention policy to drop chunks older than 5 years
--         EXECUTE format('SELECT add_retention_policy(%L, INTERVAL %L)',
--                         schema_name || '.table_' || count, '5 years');
--     END LOOP;
-- END
-- $$;

-- -- Create compression and retention policies.
-- DO
-- $$
-- DECLARE
--     count integer;
--     num_hypertables_to_be_created integer := 10;
--     schema_name varchar := 'test_schema';
--     chunk_interval interval := '1 week';
--     start_time timestamp := '2023-01-01 00:00:00';
--     end_time timestamp := '2023-01-02 00:00:00';
-- BEGIN
--     FOR count IN 1..num_hypertables_to_be_created LOOP
--         EXECUTE format($sql$ ALTER TABLE %s SET (timescaledb.compress, timescaledb.compress_segmentby = 'series_id, col1, col2, col3, col4, col5, col6, col7, col8') $sql$, schema_name || '.table_' || count);

--         -- Add a compression policy to compress chunks older than 1 week
--         EXECUTE format('SELECT add_compression_policy(%L, INTERVAL %L)',
--                         schema_name || '.table_' || count, '1 week');

--         -- Add a retention policy to drop chunks older than 5 years
--         EXECUTE format('SELECT add_retention_policy(%L, INTERVAL %L)',
--                         schema_name || '.table_' || count, '5 years');

--     END LOOP;
-- END
-- $$;

-- -- Let's add continuous policies.
-- DO
-- $$
-- DECLARE
--     i integer;
--     num_hypertables_to_be_created integer := 10; -- Replace with your desired number
--     schema_name varchar := 'test_schema'; -- Replace with your schema name
--     chunk_interval interval := '1 week'; -- Replace with your desired interval
--     start_time timestamp := '2023-01-01 00:00:00'; -- Replace with your desired start time
--     end_time timestamp := '2023-01-02 00:00:00'; -- Replace with your desired end time
-- BEGIN
--     FOR i IN 1..num_hypertables_to_be_created LOOP
--         EXECUTE format(
--         $sql$
--             CREATE MATERIALIZED VIEW %I.table_%s_agg WITH (timescaledb.continuous) AS
--             SELECT
--                 time_bucket('1 day', time) AS day,
--                 series_id,
--                 min(col1) AS _col1,
--                 avg(col2) AS _col2,
--                 max(col3) AS _col3,
--                 avg(col4) AS _col4,
--                 avg(col5) AS _col5,
--                 avg(col6) AS _col6,
--                 max(col7) AS _col7,
--                 min(col8) AS _col8
--             FROM %I.table_%s
--             GROUP BY day, series_id
--             WITH NO DATA;
--         $sql$, schema_name, i, schema_name, i);

--         EXECUTE format($sql$
--         SELECT add_continuous_aggregate_policy('%I.table_%s_agg',
--                 start_offset => INTERVAL '2 weeks',
--                 end_offset => INTERVAL '1 day',
--                 schedule_interval => INTERVAL '1 hour');
--         $sql$, schema_name, i);

--     END LOOP;
-- END
-- $$;

-- -- Create hierarchial Caggs.
-- DO
-- $$
-- DECLARE
--     i integer;
--     num_hypertables_to_be_created integer := 10;
--     schema_name varchar := 'test_schema';
--     chunk_interval interval := '1 week';
--     start_time timestamp := '2023-01-01 00:00:00';
--     end_time timestamp := '2023-01-02 00:00:00';
-- BEGIN
--     FOR i IN 1..num_hypertables_to_be_created LOOP
--         EXECUTE format(
--         $sql$
--             CREATE MATERIALIZED VIEW %I.table_%s_agg_weekly WITH (timescaledb.continuous) AS
--             SELECT
--                 time_bucket('1 week', day) AS week,
--                 series_id,
--                 min(_col1) AS _col1,
--                 avg(_col2) AS _col2,
--                 max(_col3) AS _col3,
--                 min(_col4) AS _col4,
--                 max(_col5) AS _col5,
--                 max(_col6) AS _col6,
--                 avg(_col7) AS _col7,
--                 min(_col8) AS _col8
--             FROM %I.table_%s_agg
--             GROUP BY week, series_id
--             WITH NO DATA;
--         $sql$, schema_name, i, schema_name, i);

--         EXECUTE format($sql$
--         SELECT add_continuous_aggregate_policy('%I.table_%s_agg_weekly',
--                 start_offset => INTERVAL '8 weeks',
--                 end_offset => INTERVAL '1 week',
--                 schedule_interval => INTERVAL '1 hour');
--         $sql$, schema_name, i);

--     END LOOP;
-- END
-- $$;

CREATE OR REPLACE FUNCTION tests_func(se text) RETURNS VOID AS
$$
BEGIN
    RAISE NOTICE 'works %', se;
END;
$$
LANGUAGE PLPGSQL;

SELECT tests_func(:'schema_name'::text);

-- TODO: convert the existing code to PLPGSQL functions so that we can use the psql variables.

