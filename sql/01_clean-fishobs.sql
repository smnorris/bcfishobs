-- ------------------------------------
-- Create table of distinct observations points
-- - aggregate ids and species codes into arrays
-- - add watershed group code
-- - use only point_type_code = 'Observation' (not summaries)
-- ------------------------------------

-- ** NOTE **
-- ** Geometries are not unique **
-- ** Observations with different watershed codes may be in exactly the same spot **

DROP TABLE IF EXISTS whse_fish.fiss_fish_obsrvtn_distinct;

CREATE TABLE whse_fish.fiss_fish_obsrvtn_distinct AS
WITH obs AS
(
  SELECT
    row_number() over() as fiss_fish_obsrvtn_distinct_id,
    array_agg(o.fish_observation_point_id) as obs_ids,
    o.utm_zone,
    o.utm_easting,
    o.utm_northing,
    o.wbody_id,
    o.waterbody_type,
    o.new_watershed_code,
    array_agg(o.species_code) as species_codes,
    (ST_Dump(o.geom)).geom
  FROM whse_fish.fiss_fish_obsrvtn_pnt_sp o
  WHERE o.point_type_code = 'Observation'
  GROUP BY
    o.utm_zone,
    o.utm_easting,
    o.utm_northing,
    o.wbody_id,
    o.waterbody_type,
    o.new_watershed_code,
    o.geom
)

SELECT
  obs.*,
  wsg.watershed_group_code
FROM obs
LEFT OUTER JOIN whse_basemapping.fwa_watershed_groups_subdivided wsg
ON ST_Intersects(obs.geom, wsg.geom);

ALTER TABLE whse_fish.fiss_fish_obsrvtn_distinct ADD PRIMARY KEY (fiss_fish_obsrvtn_distinct_id);

CREATE INDEX fiss_fish_obsrvtn_distinct_wbidix ON whse_fish.fiss_fish_obsrvtn_distinct (wbody_id);
CREATE INDEX fiss_fish_obsrvtn_distinct_gidx ON whse_fish.fiss_fish_obsrvtn_distinct USING gist (geom);