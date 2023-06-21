select $help$
This script needs base.sql to be pre-applied.

Note:
- 'common_tables_schema' must be same as 'common_tables_schema' in base.sql
- 'schema_name' must be different than as what was supplied in 'hypertables_schema' in base.sql

Usage:
psql -d "URI" -f add_dimension.sql \
    -v common_tables_schema='common' \
    -v schema_name='test_add_dimension' \
    -v num_hypertables=10 \
    -v chunk_interval='1 week' \
    -v num_partitions=10

$help$ as help_output
\gset

--------------------------------------------------------------------------------
-- display help and exit?
\if :{?help}
\echo :help_output
\q
\endif

CREATE EXTENSION IF NOT EXISTS TIMESCALEDB;

begin;

CREATE SCHEMA IF NOT EXISTS :schema_name;

CREATE OR REPLACE FUNCTION create_hypertables(
    common_tables_schema TEXT,
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
                        col1 integer REFERENCES %3$s.table1(id),
                        col2 integer REFERENCES %3$s.table2(id),
                        col3 integer REFERENCES %3$s.table3(id),
                        col4 integer REFERENCES %3$s.table4(id),
                        col5 integer,
                        col6 integer
                    );',
                    schema_name, count, common_tables_schema);

    EXECUTE format('SELECT create_hypertable(%L, %L, chunk_time_interval => interval %L);',
                    schema_name || '.dim_table_' || count, 'time', chunk_interval);

    RAISE NOTICE 'Completed hypertable: %.dim_table_%', schema_name, count;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

SELECT create_hypertables(
    :'common_tables_schema'::TEXT,
    :'num_hypertables'::INTEGER,
    :'schema_name'::VARCHAR,
    :'chunk_interval'::INTERVAL);

-- Create compression and retention policies.
CREATE OR REPLACE FUNCTION create_compression_retention_policies_for_add_dim(num_hypertables INTEGER, schema_name VARCHAR)
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

SELECT create_compression_retention_policies_for_add_dim(:'num_hypertables'::INTEGER, :'schema_name'::VARCHAR);

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
    :'num_hypertables'::INTEGER,
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

