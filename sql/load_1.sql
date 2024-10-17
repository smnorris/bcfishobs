-- load source data plus a synthetic primary key to target table
drop table if exists bcfishobs.obs;
create table bcfishobs.obs (like bcfishobs.observations including all);

insert into bcfishobs.obs (
 observation_key,
 wbody_id,
 species_code,
 agency_id,
 point_type_code,
 observation_date,
 agency_name,
 source,
 source_ref,
 utm_zone,
 utm_easting,
 utm_northing,
 activity_code,
 activity,
 life_stage_code,
 life_stage,
 species_name,
 waterbody_identifier,
 waterbody_type,
 gazetted_name,
 new_watershed_code,
 trimmed_watershed_code,
 acat_report_url,
 feature_code,
 geom
)
select
 substring(encode(digest(concat_ws('|', source, species_code, observation_date, utm_zone, utm_easting, utm_northing, life_stage_code, activity_code), 'sha1'), 'hex') for 10) as observation_key,
 wbody_id,
 species_code,
 agency_id,
 point_type_code,
 observation_date,
 agency_name,
 source,
 source_ref,
 utm_zone,
 utm_easting,
 utm_northing,
 activity_code,
 activity,
 life_stage_code,
 life_stage,
 species_name,
 waterbody_identifier,
 waterbody_type,
 gazetted_name,
 new_watershed_code,
 trimmed_watershed_code,
 acat_report_url,
 feature_code,
 geom
from whse_fish.fiss_fish_obsrvtn_pnt_sp
on conflict do nothing;


-- ---------------------------------------------
-- First, join each observation to all streams within 1500m.
-- Use this for subsequent analysis. Since we are
-- using such a large search area and also calculating the measures, this takes time
-- ---------------------------------------------
drop table if exists bcfishobs.obs_streams1500m;
create table bcfishobs.obs_streams1500m (
  observation_key text,
  linear_feature_id bigint,
  wscode_ltree ltree,
  localcode_ltree ltree,
  waterbody_key integer,
  blue_line_key integer,
  downstream_route_measure double precision,
  distance_to_stream double precision
);
create index on bcfishobs.obs_streams1500m (observation_key);


WITH candidates AS (
  select
    pt.observation_key,
    nn.linear_feature_id,
    nn.blue_line_key,
    nn.distance_to_stream
  from bcfishobs.obs as pt
  cross join lateral
  (select
     s.linear_feature_id,
     s.blue_line_key,
     ST_Distance(s.geom, pt.geom) as distance_to_stream
    from whse_basemapping.fwa_stream_networks_sp as s
    where s.localcode_ltree is not null
    and not s.wscode_ltree <@ '999'
    and s.edge_type != 6010
    order by s.geom <-> pt.geom
    limit 100) as nn
  where nn.distance_to_stream < 1500
),

-- find just the closest point for distinct blue_line_keys -
-- we don't want to match to all individual stream segments
bluelines AS (
  select distinct on (observation_key, blue_line_key)
    observation_key,
    blue_line_key,
    linear_feature_id,
    distance_to_stream
  from candidates
  order by observation_key, blue_line_key, distance_to_stream
)

-- from the selected blue lines, generate downstream_route_measure
insert into bcfishobs.obs_streams1500m
SELECT
  bl.observation_key,
  c.linear_feature_id,
  s.wscode_ltree,
  s.localcode_ltree,
  s.waterbody_key,
  bl.blue_line_key,
  st_interpolatepoint(s.geom, pts.geom) AS downstream_route_measure,
  c.distance_to_stream
FROM bluelines bl
INNER JOIN candidates c ON bl.observation_key = c.observation_key
AND bl.blue_line_key = c.blue_line_key
AND bl.distance_to_stream = c.distance_to_stream
INNER JOIN bcfishobs.obs pts ON bl.observation_key = pts.observation_key
inner join whse_basemapping.fwa_stream_networks_sp s on bl.linear_feature_id = s.linear_feature_id;