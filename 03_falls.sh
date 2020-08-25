#!/bin/bash
set -euxo pipefail

# load bcgw obstacles
bcdata bc2pg WHSE_FISH.FISS_OBSTACLES_PNT_SP \
  --fid FISH_OBSTACLE_POINT_ID

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

# load unpublished obstacles to master obstacles table, then reference falls to FWA streams
psql -f sql/falls.sql