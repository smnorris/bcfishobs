#!/bin/bash

set -euxo pipefail

PSQL="psql $DATABASE_URL -v ON_ERROR_STOP=1"

$PSQL -c "truncate whse_fish.wdic_waterbodies"
$PSQL -c "\copy whse_fish.wdic_waterbodies FROM PROGRAM 'curl -s https://www.hillcrestgeo.ca/outgoing/public/whse_fish/whse_fish.wdic_waterbodies.csv.gz | gunzip' delimiter ',' csv header"
$PSQL -c "truncate whse_fish.species_cd"
$PSQL -c "\copy whse_fish.species_cd FROM PROGRAM 'curl -s https://raw.githubusercontent.com/smnorris/fishbc/master/data-raw/whse_fish_species_cd/whse_fish_species_cd.csv' delimiter ',' csv header"


bcdata bc2pg WHSE_FISH.FISS_FISH_OBSRVTN_PNT_SP --query "POINT_TYPE_CODE = 'Observation'" --geometry_type POINT

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

# load to bcfishobs.observations, dropping duplicates and creating a
# hashed key for convenience
$PSQL -c "truncate bcfishobs.observations"
$PSQL -f sql/load_1.sql
$PSQL -f sql/load_2.sql
$PSQL -f sql/load_3.sql