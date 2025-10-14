#!/bin/bash

set -euxo pipefail

PSQL="psql $DATABASE_URL -v ON_ERROR_STOP=1"

$PSQL -c "truncate whse_fish.wdic_waterbodies"
$PSQL -c "\copy whse_fish.wdic_waterbodies FROM PROGRAM 'curl -s https://www.hillcrestgeo.ca/outgoing/public/whse_fish/whse_fish.wdic_waterbodies.csv.gz | gunzip' delimiter ',' csv header"
$PSQL -c "truncate whse_fish.species_cd"
$PSQL -c "\copy whse_fish.species_cd FROM PROGRAM 'curl -s https://raw.githubusercontent.com/smnorris/fishbc/master/data-raw/whse_fish_species_cd/whse_fish_species_cd.csv' delimiter ',' csv header"
