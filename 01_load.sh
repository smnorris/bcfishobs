#!/bin/bash
set -euxo pipefail

# Get data and load to postgres

# This script presumes:
# 1. The PGHOST, PGUSER, PGDATABASE, PGPORT environment variables are set
# 2. Password authentication for the DB is not required

# load observations
bcdata bc2pg WHSE_FISH.FISS_FISH_OBSRVTN_PNT_SP

# load 50k waterbody table
wget -N https://hillcrestgeo.ca/outgoing/whse_fish/whse_fish.wdic_waterbodies.csv.zip
unzip -qjun whse_fish.wdic_waterbodies.csv.zip
ogr2ogr \
  -f PostgreSQL \
  "PG:host=$PGHOST user=$PGUSER dbname=$PGDATABASE port=$PGPORT" \
  -lco OVERWRITE=YES \
  -lco SCHEMA=whse_fish \
  -nln wdic_waterbodies_load \
  -nlt NONE \
  whse_fish.wdic_waterbodies.csv
rm whse_fish.wdic_waterbodies.csv

# load species code table
wget -N https://raw.githubusercontent.com/smnorris/fishbc/master/data-raw/whse_fish_species_cd/whse_fish_species_cd.csv
psql -c "DROP TABLE IF EXISTS whse_fish.species_cd;"
psql -c "CREATE TABLE whse_fish.species_cd
 (species_id     integer primary key,
 code            text,
 name            text,
 cdcgr_code      text,
 cdclr_code      text,
 scientific_name text,
 spctype_code    text,
 spcgrp_code     text);"

psql -c "\copy whse_fish.species_cd FROM 'whse_fish_species_cd.csv' delimiter ',' csv header"

# load obstacles
bcdata bc2pg WHSE_FISH.FISS_OBSTACLES_PNT_SP --fid FISH_OBSTACLE_POINT_ID

# load additional (unpublished) obstacle data
psql -c "DROP TABLE IF EXISTS whse_fish.fiss_obstacles_unpublished;"
psql -c "CREATE TABLE whse_fish.fiss_obstacles_unpublished
 (id                 integer           ,
 featur_typ_code    character varying ,
 point_id_field     numeric           ,
 utm_zone           numeric           ,
 utm_easting        numeric           ,
 utm_northing       numeric           ,
 height             numeric           ,
 length             numeric           ,
 strsrvy_rchsrvy_id numeric           ,
 sitesrvy_id        numeric           ,
 comments           character varying)"
psql -c "\copy whse_fish.fiss_obstacles_unpublished FROM 'data/fiss_obstacles_unpublished.csv' delimiter ',' csv header"