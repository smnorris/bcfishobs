-- ------------------------------------
-- Create table of distinct observations points
-- - aggregate ids and species codes into arrays
-- - add watershed group code
-- - use only point_type_code = 'Observation' (not summaries)
-- ------------------------------------

-- ** NOTE **
-- ** Geometries are not unique **
-- ** Observations with different watershed codes may be in exactly the
--    same spot **

DROP TABLE IF EXISTS whse_fish.fiss_fish_obsrvtn_pnt_distinct;

CREATE TABLE whse_fish.fiss_fish_obsrvtn_pnt_distinct
(
 fish_obsrvtn_pnt_distinct_id serial primary key  ,
 obs_ids                  integer[]           ,
 utm_zone                 integer             ,
 utm_easting              integer             ,
 utm_northing             integer             ,
 wbody_id                 integer             ,
 waterbody_type           character varying   ,
 new_watershed_code       character varying   ,
 species_codes            character varying[] ,
 watershed_group_code     text                ,
 geom                     geometry(Point, 3005)
);


INSERT INTO whse_fish.fiss_fish_obsrvtn_pnt_distinct
(
  obs_ids              ,
  utm_zone             ,
  utm_easting          ,
  utm_northing         ,
  wbody_id             ,
  waterbody_type       ,
  new_watershed_code   ,
  species_codes        ,
  watershed_group_code ,
  geom
)
SELECT
  array_agg(o.fish_observation_point_id) as obs_ids,
  o.utm_zone,
  o.utm_easting,
  o.utm_northing,
  o.wbody_id,
  o.waterbody_type,
  o.new_watershed_code,
  array_agg(o.species_code) as species_codes,
  wsg.watershed_group_code,
  (ST_Dump(o.geom)).geom
FROM whse_fish.fiss_fish_obsrvtn_pnt_sp o
LEFT OUTER JOIN whse_basemapping.fwa_watershed_groups_subdivided wsg
ON ST_Intersects(o.geom, wsg.geom)
WHERE o.point_type_code = 'Observation'
GROUP BY
  o.utm_zone,
  o.utm_easting,
  o.utm_northing,
  o.wbody_id,
  o.waterbody_type,
  o.new_watershed_code,
  wsg.watershed_group_code,
  o.geom;

CREATE INDEX fiss_fish_obsrvtn_distinct_wbidix ON whse_fish.fiss_fish_obsrvtn_pnt_distinct (wbody_id);
CREATE INDEX fiss_fish_obsrvtn_distinct_gidx ON whse_fish.fiss_fish_obsrvtn_pnt_distinct USING gist (geom);