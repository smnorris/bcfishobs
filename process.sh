#!/bin/bash

set -euxo pipefail

PSQL="psql $DATABASE_URL -v ON_ERROR_STOP=1"

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
$PSQL -f sql/process.sql

# dump to file, do not include source geoms
ogr2ogr -f Parquet \
  /vsis3/bchamp/bcfishobs/observations.parquet \
  PG:$DATABASE_URL \
  --debug ON \
  -lco FID=observation_key \
  -nln observations \
  -sql "SELECT
    observation_key           ,
    fish_observation_point_id ,
    wbody_id                  ,
    species_code              ,
    agency_id                 ,
    point_type_code           ,
    observation_date          ,
    agency_name               ,
    source                    ,
    source_ref                ,
    utm_zone                  ,
    utm_easting               ,
    utm_northing              ,
    activity_code             ,
    activity                  ,
    life_stage_code           ,
    life_stage                ,
    species_name              ,
    waterbody_identifier      ,
    waterbody_type            ,
    gazetted_name             ,
    new_watershed_code        ,
    trimmed_watershed_code    ,
    acat_report_url           ,
    feature_code              ,
    linear_feature_id         ,
    wscode::text as wscode    ,
    localcode::text as localcode ,
    blue_line_key             ,
    watershed_group_code      ,
    downstream_route_measure  ,
    match_type                ,
    distance_to_stream        ,
    geom
  from bcfishobs.observations"

# make public
aws s3api put-object-acl --bucket bchamp --key bcfishobs/observations.parquet --acl public-read