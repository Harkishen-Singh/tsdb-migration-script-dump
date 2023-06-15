\set num_hypertables_to_be_created 10
\set num_partitions 10
\set chunk_interval '1 week'
\set schema_name 'test_add_dimension'

CREATE EXTENSION IF NOT EXISTS TIMESCALEDB;

CREATE SCHEMA IF NOT EXISTS :schema_name;

CREATE OR REPLACE FUNCTION create_hypertables(
    num_hypertables INTEGER,
    schema_name VARCHAR,
    chunk_interval INTERVAL
) RETURNS VOID AS $$
DECLARE
    count integer;
BEGIN
    FOR count IN 1..num_hypertables LOOP
    EXECUTE format('CREATE TABLE %I.dim_table_%s (
                        time timestamptz NOT NULL,
                        series_id integer NOT NULL,
                        col1 integer REFERENCES common.table1(id),
                        col2 integer REFERENCES common.table2(id),
                        col3 integer REFERENCES common.table3(id),
                        col4 integer REFERENCES common.table4(id),
                        col5 integer,
                        col6 integer
                    );',
                    schema_name, count);

    EXECUTE format('SELECT create_hypertable(%L, %L, chunk_time_interval => interval %L);',
                    schema_name || '.dim_table_' || count, 'time', chunk_interval);

    RAISE NOTICE 'Completed hypertable: %.dim_table_%', schema_name, count;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

SELECT create_hypertables(:'num_hypertables_to_be_created'::INTEGER, :'schema_name'::VARCHAR, :'chunk_interval'::INTERVAL);

-- Create compression and retention policies.
CREATE OR REPLACE FUNCTION create_compression_retention_policies(num_hypertables INTEGER, schema_name VARCHAR)
RETURNS VOID AS $$
DECLARE
    count integer;
BEGIN
    FOR count IN 1..num_hypertables LOOP
        EXECUTE format($sql$ ALTER TABLE %s SET (timescaledb.compress, timescaledb.compress_segmentby = 'series_id, col1, col2, col3, col4') $sql$, schema_name || '.dim_table_' || count);

        -- Add a compression policy to compress chunks older than 1 week
        EXECUTE format('SELECT add_compression_policy(%L, INTERVAL %L)',
                        schema_name || '.dim_table_' || count, '1 week');

        -- Add a retention policy to drop chunks older than 5 years
        EXECUTE format('SELECT add_retention_policy(%L, INTERVAL %L)',
                        schema_name || '.dim_table_' || count, '5 years');

    END LOOP;
END;
$$ LANGUAGE plpgsql;

SELECT create_compression_retention_policies(:'num_hypertables_to_be_created'::INTEGER, :'schema_name'::VARCHAR);

-- add dimensions to existing hypertables.
CREATE OR REPLACE FUNCTION add_dimensions_to_hypertables(
    num_hypertables INTEGER,
    schema_name VARCHAR,
    column_name VARCHAR,
    number_of_partitions INTEGER
) RETURNS VOID AS $$
DECLARE
    count integer;
BEGIN
    FOR count IN 1..num_hypertables LOOP
        EXECUTE format('SELECT add_dimension(%L, %L, number_partitions => %L);',
                       schema_name || '.dim_table_' || count, column_name, number_of_partitions);
    END LOOP;
END;
$$ LANGUAGE plpgsql;

SELECT add_dimensions_to_hypertables(
    :'num_hypertables_to_be_created'::INTEGER,
    :'schema_name'::VARCHAR,
    'series_id'::VARCHAR,
    :'num_partitions'::INTEGER);

SELECT
    h.table_name AS hypertable,
    d.column_name AS dimension_column,
    d.num_slices AS number_partitions
FROM
    _timescaledb_catalog.hypertable h
INNER JOIN
    _timescaledb_catalog.dimension d
ON
    h.id = d.hypertable_id
WHERE
    h.schema_name = :'schema_name';
