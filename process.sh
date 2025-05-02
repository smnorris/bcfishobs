#!/bin/bash

set -euxo pipefail

PSQL="psql $DATABASE_URL -v ON_ERROR_STOP=1"

$PSQL -c "truncate whse_fish.wdic_waterbodies"
$PSQL -c "\copy whse_fish.wdic_waterbodies FROM PROGRAM 'curl -s https://www.hillcrestgeo.ca/outgoing/public/whse_fish/whse_fish.wdic_waterbodies.csv.gz | gunzip' delimiter ',' csv header"
$PSQL -c "truncate whse_fish.species_cd"
$PSQL -c "\copy whse_fish.species_cd FROM PROGRAM 'curl -s https://raw.githubusercontent.com/smnorris/fishbc/master/data-raw/whse_fish_species_cd/whse_fish_species_cd.csv' delimiter ',' csv header"

#bcdata bc2pg WHSE_FISH.FISS_FISH_OBSRVTN_PNT_SP --query "POINT_TYPE_CODE = 'Observation'" --geometry_type POINT

# rather than downloading via bcdata/WFS, pull data from NRS object storage
# (presumes data is being cached weekly by bcfishpass workflows)
ogr2ogr -f PostgreSQL \
    "PG:$DATABASE_URL" \
    --config OGR_TRUNCATE=YES \
    -append \
    -preserve_fid \
    -nln whse_fish.fiss_fish_obsrvtn_pnt_sp \
    --config PG_USE_COPY=YES \
    /vsicurl/https://nrs.objectstore.gov.bc.ca/bchamp/bcdata/whse_fish.fiss_fish_obsrvtn_pnt_sp.parquet \
    whse_fish.fiss_fish_obsrvtn_pnt_sp

# report on duplicates in source
$PSQL -c "select
  source,
  species_code,
  observation_date,
  utm_zone,
  utm_easting,
  utm_northing,
  life_stage_code,
  activity_code,
  count(*) as n
from whse_fish.fiss_fish_obsrvtn_pnt_sp
group by source,
  species_code,
  observation_date,
  utm_zone,
  utm_easting,
  utm_northing,
  life_stage_code,
  activity_code
having count(*) > 1;" --csv > duplicates.csv

# load to bcfishobs.observations, snapping to fwa streams and adding a hashed key for convenience
$PSQL -c "truncate bcfishobs.observations"
$PSQL -f sql/process.sql

# drop temp tables
$PSQL -c "drop table bcfishobs.obs; drop table bcfishobs.obs_fwa;"
