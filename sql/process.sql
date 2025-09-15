------------------------------------------------------------
-- load source data plus a synthetic primary key to preliminary table holding all observation source data
------------------------------------------------------------
drop table if exists bcfishobs.obs;
create table bcfishobs.obs (
 observation_key           text  primary key        ,
 fish_observation_point_id numeric,
 wbody_id                  numeric                  ,
 species_code              character varying(6)     ,
 agency_id                 numeric                  ,
 point_type_code           character varying(20)    ,
 observation_date          date                     ,
 agency_name               character varying(60)    ,
 source                    character varying(1000)  ,
 source_ref                character varying(4000)  ,
 utm_zone                  integer                  ,
 utm_easting               integer                  ,
 utm_northing              integer                  ,
 activity_code             character varying(100)   ,
 activity                  character varying(300)   ,
 life_stage_code           character varying(100)   ,
 life_stage                character varying(300)   ,
 species_name              character varying(60)    ,
 waterbody_identifier      character varying(9)     ,
 waterbody_type            character varying(20)    ,
 gazetted_name             character varying(30)    ,
 new_watershed_code        character varying(56)    ,
 trimmed_watershed_code    character varying(56)    ,
 acat_report_url           character varying(254)   ,
 feature_code              character varying(10)    ,
 linear_feature_id         bigint,
 wscode                    ltree,
 localcode                 ltree,
 blue_line_key             integer,
 watershed_group_code      character varying(4),
 downstream_route_measure  double precision,
 match_type                text,
 distance_to_stream        double precision,
 geom_src                  geometry(PointZ,3005)
 geom                      geometry(PointZM,3005)
);
create index on bcfishobs.obs (linear_feature_id);
create index on bcfishobs.obs (blue_line_key);
create index on bcfishobs.obs (blue_line_key, downstream_route_measure);
create index on bcfishobs.obs (wscode);
create index on bcfishobs.obs (localcode);
create index on bcfishobs.obs using gist (wscode);
create index on bcfishobs.obs using gist (localcode);
create index on bcfishobs.obs using gist (geom);


insert into bcfishobs.obs (
 observation_key,
 fish_observation_point_id,
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
 geom_src
)
select
 substring(encode(digest(concat_ws('|', source, species_code, observation_date, utm_zone, utm_easting, utm_northing, life_stage_code, activity_code), 'sha1'), 'hex') for 10) as observation_key,
 fish_observation_point_id,
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
 (st_dump(geom)).geom as geom_src
from whse_fish.fiss_fish_obsrvtn_pnt_sp
on conflict do nothing;


-- ---------------------------------------------
-- Join each observation point to all streams within 1500m.
-- This is used for subsequent analysis/inserts. Since we are
-- using such a large search area and also calculating the measures, this takes a bit of time
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
     ST_Distance(s.geom, pt.geom_src) as distance_to_stream
    from whse_basemapping.fwa_stream_networks_sp as s
    where s.localcode_ltree is not null
    and not s.wscode_ltree <@ '999'
    and s.edge_type != 6010
    order by s.geom <-> pt.geom_src
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
  st_interpolatepoint(s.geom, pts.geom_src) AS downstream_route_measure,
  c.distance_to_stream
FROM bluelines bl
INNER JOIN candidates c ON bl.observation_key = c.observation_key
AND bl.blue_line_key = c.blue_line_key
AND bl.distance_to_stream = c.distance_to_stream
INNER JOIN bcfishobs.obs pts ON bl.observation_key = pts.observation_key
inner join whse_basemapping.fwa_stream_networks_sp s on bl.linear_feature_id = s.linear_feature_id;


------------------------------------------------------------
-- Create table holding the observation to stream matches that should be retained
-- ---------------------------------------------

drop table if exists bcfishobs.obs_fwa;
create table bcfishobs.obs_fwa (
  observation_key text primary key,
  linear_feature_id bigint,
  wscode_ltree ltree,
  localcode_ltree ltree,
  waterbody_key integer,
  blue_line_key integer,
  downstream_route_measure double precision,
  distance_to_stream double precision,
  match_type text
);
create index on bcfishobs.obs_fwa (linear_feature_id);


------------------------------------------------------------
-- Load each matching type to obs_fwa table in a different load
-- ---------------------------------------------

-- First, insert events matched to waterbodies.
-- This is perhaps more complicated than it has to be but we want to
-- ensure that observations in waterbodies are associated with waterbodies.
-- We use a large 1500m tolerance (in previous query) because observations in
-- larger lakes can be quite far from a stream flow line. This makes the
-- assumption we can prioritize the waterbody key of observation points
-- over the actual the location of the point.

-- This query:
--   - joins the observations to the FWA via wbody_key (1:many via lookup)
--   - from the many possible matches, choose just the closest
--   - inserts these records into the output table

-- where observation is coded as a lake or wetland,
-- join to waterbody_key via wdic_waterbodies
WITH wb AS
(
  SELECT DISTINCT
    o.observation_key,
    wb.waterbody_key
  FROM bcfishobs.obs o
  INNER JOIN whse_fish.wdic_waterbodies wdic ON o.wbody_id = wdic.id
  INNER JOIN whse_basemapping.fwa_waterbodies_20k_50k lut
     ON LTRIM(wdic.waterbody_identifier,'0') = lut.waterbody_key_50k::TEXT||lut.watershed_group_code_50k
  INNER JOIN whse_basemapping.fwa_waterbodies wb
  ON lut.waterbody_key_20k = wb.waterbody_key
  WHERE o.waterbody_type IN ('Lake', 'Wetland')
  ORDER BY o.observation_key
),
-- from the candidate matches generated above, use the one closest to a stream
closest AS
(
  SELECT DISTINCT ON
   (e.observation_key)
    e.observation_key,
    e.distance_to_stream
  FROM bcfishobs.obs_streams1500m e
  INNER JOIN wb ON e.observation_key = wb.observation_key
  AND e.waterbody_key = wb.waterbody_key
  ORDER BY observation_key, distance_to_stream
)
-- Insert the results into our output table
-- Note that there are duplicate records because observations can be
-- equidistant from
-- several stream lines. Insert records with highest measure (though they
-- should be the same)
INSERT INTO bcfishobs.obs_fwa
SELECT DISTINCT ON (e.observation_key)
  e.observation_key,
  e.linear_feature_id,
  e.wscode_ltree,
  e.localcode_ltree,
  e.waterbody_key,
  e.blue_line_key,
  e.downstream_route_measure,
  e.distance_to_stream,
  'D. matched - waterbody; construction line within 1500m; lookup'
FROM bcfishobs.obs_streams1500m e
INNER JOIN closest
ON e.observation_key = closest.observation_key
AND e.distance_to_stream = closest.distance_to_stream
WHERE e.waterbody_key is NOT NULL
ORDER BY e.observation_key, e.downstream_route_measure;



-- ---------------------------------------------
-- Some observations in waterbodies do not get added above due to
-- lookup quirks.
-- Insert these records simply based on the closest stream
-- ---------------------------------------------
WITH unmatched_wb AS
(    SELECT e.*
    FROM bcfishobs.obs_streams1500m e
    INNER JOIN bcfishobs.obs o
    ON e.observation_key = o.observation_key
    LEFT OUTER JOIN bcfishobs.obs_fwa p
    ON e.observation_key = p.observation_key
    WHERE o.wbody_id IS NOT NULL AND o.waterbody_type IN ('Lake','Wetland')
    AND p.observation_key IS NULL
),

closest_unmatched AS
(
  SELECT DISTINCT ON (observation_key)
    observation_key,
    distance_to_stream
  FROM unmatched_wb
  ORDER BY observation_key, distance_to_stream
)

INSERT INTO bcfishobs.obs_fwa
SELECT DISTINCT ON (e.observation_key)
  e.observation_key,
  e.linear_feature_id,
  e.wscode_ltree,
  e.localcode_ltree,
  e.waterbody_key,
  e.blue_line_key,
  e.downstream_route_measure,
  e.distance_to_stream,
  'E. matched - waterbody; construction line within 1500m; closest'
FROM bcfishobs.obs_streams1500m e
INNER JOIN closest_unmatched
ON e.observation_key = closest_unmatched.observation_key
AND e.distance_to_stream = closest_unmatched.distance_to_stream
ORDER BY e.observation_key, e.downstream_route_measure;


------------------------------------------------------------
-- now match streams in several steps
------------------------------------------------------------
-- 1.
-- Find points on streams that are within 100m of stream, but only
-- insert those with an exact match in the 20k-50k lookup.
-- This means that if we have multiple matches within 100m, we insert
-- the record with a match in the xref - if available.
WITH unmatched AS
(   SELECT e.*
    FROM bcfishobs.obs_streams1500m e
    INNER JOIN bcfishobs.obs o
    ON e.observation_key = o.observation_key
    INNER JOIN whse_basemapping.fwa_streams_20k_50k lut
    ON replace(o.new_watershed_code, '-', '') = lut.watershed_code_50k
    AND e.linear_feature_id = lut.linear_feature_id_20k
    WHERE o.waterbody_type NOT IN ('Lake', 'Wetland')
    AND e.distance_to_stream <= 100
    ORDER BY e.observation_key , e.distance_to_stream
),

-- there can still potentially be multiple results, find the closest
closest_unmatched AS
(
  SELECT DISTINCT ON (observation_key)
    observation_key,
    distance_to_stream
  FROM unmatched
  ORDER BY observation_key, distance_to_stream
)

INSERT INTO bcfishobs.obs_fwa
SELECT DISTINCT ON (e.observation_key)
  e.observation_key,
  e.linear_feature_id,
  e.wscode_ltree,
  e.localcode_ltree,
  e.waterbody_key,
  e.blue_line_key,
  e.downstream_route_measure,
  e.distance_to_stream,
  'A. matched - stream; within 100m; lookup'
FROM bcfishobs.obs_streams1500m e
INNER JOIN closest_unmatched
ON e.observation_key = closest_unmatched.observation_key
AND e.distance_to_stream = closest_unmatched.distance_to_stream;



------------------------------------------------------------
-- 2.
-- For records that we haven't yet inserted, insert those that are 100m
-- or less from a stream, based just on minimum distance to stream
WITH unmatched AS
(   SELECT e1.*
    FROM bcfishobs.obs_streams1500m e1
    LEFT OUTER JOIN bcfishobs.obs_fwa e2
    ON e1.observation_key = e2.observation_key
    INNER JOIN bcfishobs.obs o
    ON e1.observation_key = o.observation_key
    WHERE o.waterbody_type NOT IN ('Lake', 'Wetland')
    AND e1.distance_to_stream <= 100
    AND e2.observation_key IS NULL
    ORDER BY e1.observation_key , e1.distance_to_stream
),

-- there can still potentially be multiple results, find the closest
closest_unmatched AS
(
  SELECT DISTINCT ON (observation_key)
    observation_key,
    distance_to_stream
  FROM unmatched
  ORDER BY observation_key, distance_to_stream
)

INSERT INTO bcfishobs.obs_fwa
SELECT DISTINCT ON (e.observation_key)
  e.observation_key,
  e.linear_feature_id,
  e.wscode_ltree,
  e.localcode_ltree,
  e.waterbody_key,
  e.blue_line_key,
  e.downstream_route_measure,
  e.distance_to_stream,
  'B. matched - stream; within 100m; closest stream'
FROM bcfishobs.obs_streams1500m e
INNER JOIN closest_unmatched
ON e.observation_key = closest_unmatched.observation_key
AND e.distance_to_stream = closest_unmatched.distance_to_stream;



------------------------------------------------------------
-- 3.
-- Finally, within records that still have not been inserted,
-- find those that are >100m and <500m from a stream and have a exact
-- (linear_feature_id) match in the xref lookup.
WITH unmatched AS
(   SELECT e1.*
    FROM bcfishobs.obs_streams1500m e1
    LEFT OUTER JOIN bcfishobs.obs_fwa e2
    ON e1.observation_key = e2.observation_key
    INNER JOIN bcfishobs.obs o
    ON e1.observation_key = o.observation_key
    INNER JOIN whse_basemapping.fwa_streams_20k_50k lut
    ON replace(o.new_watershed_code, '-', '') = lut.watershed_code_50k
    AND e1.linear_feature_id = lut.linear_feature_id_20k
    WHERE o.waterbody_type NOT IN ('Lake', 'Wetland')
    AND e1.distance_to_stream > 100 AND e1.distance_to_stream < 500
    AND e2.observation_key IS NULL
    ORDER BY e1.observation_key , e1.distance_to_stream
),

-- there can still potentially be multiple results, find the closest
closest_unmatched AS
(
  SELECT DISTINCT ON (observation_key)
    observation_key,
    distance_to_stream
  FROM unmatched
  ORDER BY observation_key, distance_to_stream
)

INSERT INTO bcfishobs.obs_fwa
SELECT DISTINCT ON (e.observation_key)
  e.observation_key,
  e.linear_feature_id,
  e.wscode_ltree,
  e.localcode_ltree,
  e.waterbody_key,
  e.blue_line_key,
  e.downstream_route_measure,
  e.distance_to_stream,
  'C. matched - stream; 100-500m; lookup'
FROM bcfishobs.obs_streams1500m e
INNER JOIN closest_unmatched
ON e.observation_key = closest_unmatched.observation_key
AND e.distance_to_stream = closest_unmatched.distance_to_stream
INNER JOIN bcfishobs.obs o
ON e.observation_key = o.observation_key;


------------------------------------------------------------
-- load data from obs and obs_fwa tables to the output bcfishobs.observations table,
-- rounding the measures and retaining both the snapped and source geometries

insert into bcfishobs.observations (
  observation_key         ,
  fish_observation_point_id,
  wbody_id                ,
  species_code            ,
  agency_id               ,
  point_type_code         ,
  observation_date        ,
  agency_name             ,
  source                  ,
  source_ref              ,
  utm_zone                ,
  utm_easting             ,
  utm_northing            ,
  activity_code           ,
  activity                ,
  life_stage_code         ,
  life_stage              ,
  species_name            ,
  waterbody_identifier    ,
  waterbody_type          ,
  gazetted_name           ,
  new_watershed_code      ,
  trimmed_watershed_code  ,
  acat_report_url         ,
  feature_code            ,
  linear_feature_id       ,
  wscode                  ,
  localcode               ,
  blue_line_key           ,
  watershed_group_code    ,
  downstream_route_measure,
  match_type              ,
  distance_to_stream     ,
  -- geom_src,
  geom
)
select
  o.observation_key         ,
  o.fish_observation_point_id,
  o.wbody_id                ,
  o.species_code            ,
  o.agency_id               ,
  o.point_type_code         ,
  o.observation_date        ,
  o.agency_name             ,
  o.source                  ,
  o.source_ref              ,
  o.utm_zone                ,
  o.utm_easting             ,
  o.utm_northing            ,
  o.activity_code           ,
  o.activity                ,
  o.life_stage_code         ,
  o.life_stage              ,
  o.species_name            ,
  o.waterbody_identifier    ,
  o.waterbody_type          ,
  o.gazetted_name           ,
  o.new_watershed_code      ,
  o.trimmed_watershed_code  ,
  o.acat_report_url         ,
  o.feature_code            ,
  fwa.linear_feature_id       ,
  fwa.wscode_ltree as wscode                  ,
  fwa.localcode_ltree as localcode              ,
  fwa.blue_line_key           ,
  s.watershed_group_code    ,
  CEIL(GREATEST(s.downstream_route_measure, FLOOR(LEAST(s.upstream_route_measure, fwa.downstream_route_measure)))) as downstream_route_measure,
  fwa.match_type              ,
  fwa.distance_to_stream     ,
  -- o.geom_src,
  ST_Force3DZ(whse_basemapping.FWA_LocateAlong(fwa.blue_line_key, CEIL(GREATEST(s.downstream_route_measure, FLOOR(LEAST(s.upstream_route_measure, fwa.downstream_route_measure)))))) as geom
from bcfishobs.obs o
inner join bcfishobs.obs_fwa fwa on o.observation_key = fwa.observation_key
inner join whse_basemapping.fwa_stream_networks_sp s on fwa.linear_feature_id = s.linear_feature_id;

