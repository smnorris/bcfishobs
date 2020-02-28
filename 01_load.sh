# Get data and load to postgres

# This script presumes:
# 1. The PGHOST, PGUSER, PGDATABASE, PGPORT environment variables are set
# 2. Password authentication for the DB is not required

# load observations
bcdata bc2pg WHSE_FISH.FISS_FISH_OBSRVTN_PNT_SP \
  --fid FISH_OBSERVATION_POINT_ID

# load 50k waterbody table & species table (not published on DataBC Catalogue)
wget -N https://hillcrestgeo.ca/outgoing/whse_fish/whse_fish.wdic_waterbodies.csv.zip
wget -N https://hillcrestgeo.ca/outgoing/whse_fish/species_cd.csv.zip

unzip -qjun whse_fish.wdic_waterbodies.csv.zip
unzip -qjun species_cd.csv.zip

ogr2ogr \
  -f PostgreSQL \
  "PG:host=$PGHOST user=$PGUSER dbname=$PGDATABASE port=$PGPORT" \
  -lco OVERWRITE=YES \
  -lco SCHEMA=whse_fish \
  -nln wdic_waterbodies_load \
  -nlt NONE \
  whse_fish.wdic_waterbodies.csv

ogr2ogr \
  -f PostgreSQL \
  "PG:host=$PGHOST user=$PGUSER dbname=$PGDATABASE port=$PGPORT" \
  -lco OVERWRITE=YES \
  -lco SCHEMA=whse_fish \
  -nln species_cd \
  -nlt NONE \
  species_cd.csv

rm whse_fish.wdic_waterbodies.csv
rm species_cd.csv

