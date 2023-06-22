select $help$
This script creates Hypertables along with their compression and retention policies.
These Hypertables are created using the tables in a common schema, referenced by a bunch of foreign keys.
Additionally, the script creates 2 continuous aggregates for each Hypertable:
1. Simple Cagg
2. Hierarchial Cagg

Usage:
psql -d "URI" -f base.sql \
    -v common_tables_schema='common' \
    -v num_common_tables=10 \
    -v hypertables_schema='timeseries' \
    -v num_hypertables=20 \
    -v ignore_compression_policies=1 \
    -v chunk_interval='1 week' \
    -v resolution='1 minute' \
    -v start_time='2023-01-01' \
    -v end_time='2023-03-31'

Supported flags:
    common_tables_schema [required]
        Schema for creation of common tables.
        Eg: 'common'

    num_common_tables [required]
        Number of common tables to be created. Hypertables will use these tables as foreign keys.
        Must not be less than 8.
        Eg: 20

    hypertables_schema [required]
        Schema under which hypertables should be created.
        Eg: 'timeseries'

    num_hypertables [required]
        Number of Hypertables to be created.
        Eg: 20

    chunk_interval [required]
        Chunk interval of the Hypertables created.
        Eg: '1 week'

    resolution [required]
        Intervals in which samples should be created.
        Eg: '10 seconds'

    start_time [required]
        Start writing data into the created Hypertables from 'start_time' time.
        Data is written with intervals of 1 minute.
        Eg: '2023-01-01'

    end_time [required]
        Write until 'end_time' time.
        Eg: '2023-03-01'

    ignore_compression_policies [optional]
        Do not create compression policies for Hypertables.

    help [optional]
        prints this message describing the script
        -v help=1

$help$ as help_output
\gset

--------------------------------------------------------------------------------
-- display help and exit?
\if :{?help}
\echo :help_output
\q
\endif

CREATE EXTENSION IF NOT EXISTS TIMESCALEDB;

-- Create tables and custom types
CREATE SCHEMA IF NOT EXISTS :common_tables_schema;

CREATE TYPE custom_type_1 AS ENUM ('Type1', 'Type2', 'Type3');

CREATE OR REPLACE FUNCTION create_common_tables_and_types(common_tables_schema TEXT, num_tables INTEGER)
RETURNS VOID AS $$
DECLARE
  i INT;
BEGIN
  FOR i IN 1..num_tables LOOP
    EXECUTE format(
      $sql$
      CREATE TABLE %s.table%s (
        id serial primary key,
        column1 int,
        column2 varchar(255),
        column3 custom_type_1,
        column4 text,
        column5 boolean,
        column6 date,
        column7 time,
        column8 timestamp,
        column9 json,
        column10 jsonb
      );
      $sql$, common_tables_schema, i);

    -- Insert data into the tables
    IF i = 1 THEN
      FOR j IN 1..1000000 LOOP
        EXECUTE format(
          $sql$
          INSERT INTO %s.table%s (column1, column2, column3, column4, column5, column6, column7, column8, column9, column10)
          VALUES (
            floor(random() * 100)::int,
            md5(random()::text),
            (CASE floor(random() * 3)::int WHEN 0 THEN 'Type1' WHEN 1 THEN 'Type2' ELSE 'Type3' END)::custom_type_%s,
            md5(random()::text),
            (CASE floor(random() * 2)::int WHEN 0 THEN true ELSE false END),
            current_date,
            current_time,
            current_timestamp,
            json_build_object('key', md5(random()::text)),
            jsonb_build_object('key', md5(random()::text))
          );
          $sql$, common_tables_schema, i, i);
      END LOOP;
    ELSE
      EXECUTE format('INSERT INTO %s.table%s SELECT * FROM %s.table1;', common_tables_schema, i, common_tables_schema);
    END IF;

    RAISE NOTICE 'Created table common.table%', i;
  END LOOP;
END;
$$ LANGUAGE plpgsql;

SELECT create_common_tables_and_types(:'common_tables_schema'::TEXT, :'num_common_tables'::INTEGER); -- Hard code common tables.

-- Create Hypertables and insert data.
CREATE SCHEMA IF NOT EXISTS :hypertables_schema;

CREATE OR REPLACE PROCEDURE create_hypertables_and_insert_data(
    common_tables_schema TEXT,
    num_hypertables INTEGER,
    hypertables_schema VARCHAR,
    chunk_interval INTERVAL,
    resolution INTERVAL,
    start_time TIMESTAMP,
    end_time TIMESTAMP
) AS $$
DECLARE
    count integer;
BEGIN
    FOR count IN 1..num_hypertables LOOP
        EXECUTE format('CREATE TABLE IF NOT EXISTS %I.table_%s (
                time timestamptz NOT NULL,
                series_id integer NOT NULL,
                col1 integer REFERENCES %3$s.table1(id),
                col2 integer REFERENCES %3$s.table2(id),
                col3 integer REFERENCES %3$s.table3(id),
                col4 integer REFERENCES %3$s.table4(id),
                col5 integer,
                col6 jsonb,
                col7 jsonb,
                col8 jsonb
            );',
            hypertables_schema, count, common_tables_schema);

        IF count = 1 THEN
            EXECUTE format(
                $sql$
                INSERT INTO %I.table_%s (time, series_id, col1, col2, col3, col4, col5, col6, col7, col8)
                SELECT
                    generate_series(TIMESTAMP %L, TIMESTAMP %L, interval %L) AS time,
                    ceil(random() * 100)::integer AS series_id,
                    ceil(random() * 100)::integer AS col1,
                    ceil(random() * 100)::integer AS col2,
                    ceil(random() * 100)::integer AS col3,
                    ceil(random() * 100)::integer AS col4,
                    ceil(random() * 100)::integer AS col5,
                    json_build_object('key', md5(random()::text)) AS col6,
                    json_build_object('key', md5(random()::text)) AS col7,
                    json_build_object('key', md5(random()::text)) AS col8;
                $sql$,
            hypertables_schema, count, start_time, end_time, resolution);
        ELSE
            EXECUTE format('INSERT INTO %I.table_%s SELECT * FROM %I.table_1;',
            hypertables_schema, count, hypertables_schema);
        END IF;

        EXECUTE format('SELECT create_hypertable(%L, %L, chunk_time_interval => interval %L, migrate_data => true);',
                hypertables_schema || '.table_' || count, 'time', chunk_interval);

        COMMIT;

        RAISE NOTICE 'Completed hypertable: %.table_%', hypertables_schema, count;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

CALL create_hypertables_and_insert_data(
    :'common_tables_schema'::TEXT,
    :'num_hypertables'::INTEGER,
    :'hypertables_schema'::VARCHAR,
    :'chunk_interval'::INTERVAL,
    :'resolution'::INTERVAL,
    :'start_time'::TIMESTAMP,
    :'end_time'::TIMESTAMP
);

-- Create compression and retention policies.
CREATE OR REPLACE FUNCTION create_compression_retention_policies(num_hypertables INTEGER, hypertables_schema VARCHAR, ignore_compression BOOLEAN)
RETURNS VOID AS $$
DECLARE
    count integer;
BEGIN
    FOR count IN 1..num_hypertables LOOP
        EXECUTE format($sql$ ALTER TABLE %s SET (timescaledb.compress, timescaledb.compress_segmentby = 'series_id, col1, col2, col3, col4') $sql$, hypertables_schema || '.table_' || count);

        IF NOT ignore_compression THEN
            -- Add a compression policy to compress chunks older than 1 week
            EXECUTE format('SELECT add_compression_policy(%L, INTERVAL %L)',
                            hypertables_schema || '.table_' || count, '1 week');
        END IF;

        -- Add a retention policy to drop chunks older than 5 years
        EXECUTE format('SELECT add_retention_policy(%L, INTERVAL %L)',
                        hypertables_schema || '.table_' || count, '5 years');

    END LOOP;
END;
$$ LANGUAGE plpgsql;

\if :{?ignore_compression_policies}
    SELECT create_compression_retention_policies(:'num_hypertables'::INTEGER, :'hypertables_schema'::VARCHAR, TRUE);
\else
    SELECT create_compression_retention_policies(:'num_hypertables'::INTEGER, :'hypertables_schema'::VARCHAR, FALSE);
\endif

-- Let's add continuous policies.
CREATE OR REPLACE FUNCTION create_continuous_agg_policies(IN num_hypertables INTEGER, IN hypertables_schema VARCHAR)
RETURNS VOID AS $$
DECLARE
    i integer;
BEGIN
    FOR i IN 1..num_hypertables LOOP
        EXECUTE format(
        $sql$
            CREATE MATERIALIZED VIEW %I.table_%s_agg WITH (timescaledb.continuous) AS
            SELECT
                time_bucket('1 day', time) AS day,
                series_id,
                min(col1) AS _col1,
                avg(col2) AS _col2,
                max(col3) AS _col3,
                avg(col4) AS _col4,
                avg(col5) AS _col5,
                avg(col6) AS _col6,
                max(col7) AS _col7,
                min(col8) AS _col8
            FROM %I.table_%s
            GROUP BY day, series_id
            WITH NO DATA;
        $sql$, hypertables_schema, i, hypertables_schema, i);

        EXECUTE format($sql$
        SELECT add_continuous_aggregate_policy('%I.table_%s_agg',
                start_offset => INTERVAL '2 weeks',
                end_offset => INTERVAL '1 day',
                schedule_interval => INTERVAL '1 hour');
        $sql$, hypertables_schema, i);

    END LOOP;
END;
$$ LANGUAGE plpgsql;

SELECT create_continuous_agg_policies(:'num_hypertables'::INTEGER, :'hypertables_schema'::VARCHAR);

-- Create hierarchial Caggs.
CREATE OR REPLACE FUNCTION create_hierarchical_caggs(IN num_hypertables INTEGER, IN hypertables_schema VARCHAR)
RETURNS VOID AS $$
DECLARE
    i integer;
BEGIN
    FOR i IN 1..num_hypertables LOOP
        EXECUTE format(
        $sql$
            CREATE MATERIALIZED VIEW %I.table_%s_agg_weekly WITH (timescaledb.continuous) AS
            SELECT
                time_bucket('1 week', day) AS week,
                series_id,
                min(_col1) AS _col1,
                avg(_col2) AS _col2,
                max(_col3) AS _col3,
                min(_col4) AS _col4,
                max(_col5) AS _col5,
                max(_col6) AS _col6,
                avg(_col7) AS _col7,
                min(_col8) AS _col8
            FROM %I.table_%s_agg
            GROUP BY week, series_id
            WITH NO DATA;
        $sql$, hypertables_schema, i, hypertables_schema, i);

        EXECUTE format($sql$
        SELECT add_continuous_aggregate_policy('%I.table_%s_agg_weekly',
                start_offset => INTERVAL '8 weeks',
                end_offset => INTERVAL '1 week',
                schedule_interval => INTERVAL '1 hour');
        $sql$, hypertables_schema, i);

    END LOOP;
END;
$$ LANGUAGE plpgsql;

SELECT create_hierarchical_caggs(:'num_hypertables'::INTEGER, :'hypertables_schema'::VARCHAR);
