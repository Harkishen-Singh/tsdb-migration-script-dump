import argparse
import subprocess

# Define a list of SQL file names in the order they should be executed
files = ["base.sql", "add_dimension.sql", "reorder_policy.sql", "toolkit.sql"]

# Define the psql command for each file as a string with placeholder variables
commands = {
    "base.sql": """
    psql -d {URI} -f base.sql \
        -v common_tables_schema={common_tables_schema} \
        -v num_common_tables={num_common_tables} \
        -v hypertables_schema={hypertables_schema} \
        -v num_hypertables={num_hypertables} \
        {ignore_compression_policies} \
        -v chunk_interval='{chunk_interval}' \
        -v start_time='{start_time}' \
        -v end_time='{end_time}'
    """,

    "add_dimension.sql": """
    psql -d {URI} -f add_dimension.sql \
        -v common_tables_schema={common_tables_schema} \
        -v schema_name={dim_schema_name} \
        -v num_hypertables={num_hypertables} \
        -v chunk_interval='{chunk_interval}' \
        -v num_partitions={num_partitions}
    """,

    "reorder_policy.sql": """
    psql -d {URI} -f reorder_policy.sql \
        -v hypertables_schema={hypertables_schema} \
        -v num_hypertables={num_hypertables}
    """,

    "toolkit.sql": """
    psql -d {URI} -f toolkit.sql \
        -v hypertables_schema={hypertables_schema} \
        -v num_hypertables={num_hypertables} \
        -v gapfilling_start_ts='{gapfilling_start_ts}' \
        -v gapfilling_end_ts='{gapfilling_end_ts}'
    """
}

# Define the command-line arguments
parser = argparse.ArgumentParser()
parser.add_argument("URI", help="Postgres database URI")
parser.add_argument("--common_tables_schema", help="Value for common_tables_schema")
parser.add_argument("--num_common_tables", help="Value for num_common_tables")
parser.add_argument("--hypertables_schema", help="Value for hypertables_schema")
parser.add_argument("--num_hypertables", help="Value for num_hypertables")
parser.add_argument("--ignore_compression_policies", help="Value for ignore_compression_policies. Should be 1")
parser.add_argument("--chunk_interval", help="Value for chunk_interval")
parser.add_argument("--start_time", help="Value for start_time")
parser.add_argument("--end_time", help="Value for end_time")
parser.add_argument("--dim_schema_name", help="Value for schema name for multi dimensional hypertable. Must be different than schema_name")
parser.add_argument("--num_partitions", help="Value for num_partitions")
parser.add_argument("--gapfilling_start_ts", help="Value for gapfilling_start_ts")
parser.add_argument("--gapfilling_end_ts", help="Value for gapfilling_end_ts")

args = parser.parse_args()

# Convert arguments to a dictionary and add conditional argument
args_dict = vars(args)
if args_dict.get("ignore_compression_policies"):
    args_dict["ignore_compression_policies"] = "-v ignore_compression_policies=" + args_dict["ignore_compression_policies"]
else:
    args_dict["ignore_compression_policies"] = ""

# Run the psql command for each file
for file in files:
    command = commands[file].format(**args_dict)
    print('\n\nRunning ', command)
    subprocess.run(command, shell=True, check=True)
