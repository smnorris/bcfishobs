#!/bin/bash
set -euxo pipefail

# run the queries

# This script presumes:
# 1. The PGHOST, PGUSER, PGDATABASE, PGPORT environment variables are set
# 2. Password authentication for the DB is not required OR a .pgpass exists OR $PGPASSWORD is set

# make sure the intarray extension is added
psql -c "CREATE EXTENSION IF NOT EXISTS intarray"

psql -f sql/01_clean-fishobs.sql
psql -f sql/02_clean-wdic.sql
psql -f sql/03_create-prelim-table.sql
psql -f sql/04_add-waterbodies.sql
psql -f sql/05_add-streams-100m-lookup.sql
psql -f sql/06_add-streams-100m-closest.sql
psql -f sql/07_add-streams-100m-500m.sql
psql -f sql/08_create-output-tables.sql

# Tag maximal observations for each species
# As this is run as a loop it is easier to do via Python
python tag_maximal_events.py

# process obstacles/falls
psql -f sql/falls.sql

# report on the results of the job
psql2csv < sql/qa_match_observations.sql > qa_match_observations.csv

psql2csv < sql/qa_match_falls.sql > qa_match_falls.csv

psql -f sql/11_cleanup.sql

