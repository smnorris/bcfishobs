-- for convenience, create a materialized view that holds all observation events
-- (not just distinct locations), commonly queried columns, and the location that
-- the observation is referenced to - as a point geometry

CREATE MATERIALIZED VIEW whse_fish.fiss_fish_obsrvtn_events_vw
AS

WITH all_obs AS
(SELECT
   unnest(e.obs_ids) AS fish_observation_point_id,
   e.linear_feature_id,
   e.wscode_ltree,
   e.localcode_ltree,
   e.blue_line_key,
   e.waterbody_key,
   e.downstream_route_measure,
   e.distance_to_stream,
   e.match_type,
   e.watershed_group_code,
   ST_LineInterpolatePoint(
     ST_LineMerge(s.geom),
     ROUND(
       CAST(
          (e.downstream_route_measure -
             s.downstream_route_measure) / s.length_metre AS NUMERIC
        ),
       5)
     ) AS geom
FROM whse_fish.fiss_fish_obsrvtn_events e
INNER JOIN whse_basemapping.fwa_stream_networks_sp s
ON e.linear_feature_id = s.linear_feature_id)

SELECT
  a.*,
  b.species_code,
  b.agency_id,
  b.observation_date,
  b.agency_name,
  b.source,
  b.source_ref
FROM all_obs a
INNER JOIN whse_fish.fiss_fish_obsrvtn_pnt_sp  b
ON a.fish_observation_point_id = b.fish_observation_point_id;

-- We can index the matierialized view for performance

CREATE UNIQUE INDEX ON whse_fish.fiss_fish_obsrvtn_events_vw (fish_observation_point_id);
CREATE INDEX ON whse_fish.fiss_fish_obsrvtn_events_vw (linear_feature_id);
CREATE INDEX ON whse_fish.fiss_fish_obsrvtn_events_vw (blue_line_key);
CREATE INDEX ON whse_fish.fiss_fish_obsrvtn_events_vw (waterbody_key);
CREATE INDEX ON whse_fish.fiss_fish_obsrvtn_events_vw (wscode_ltree);
CREATE INDEX ON whse_fish.fiss_fish_obsrvtn_events_vw (localcode_ltree);
CREATE INDEX ON whse_fish.fiss_fish_obsrvtn_events_vw (watershed_group_code);

-- create GIST indexes on geom and ltree types
CREATE INDEX ON whse_fish.fiss_fish_obsrvtn_events_vw USING GIST (geom);
CREATE INDEX ON whse_fish.fiss_fish_obsrvtn_events_vw USING GIST (wscode_ltree);
CREATE INDEX ON whse_fish.fiss_fish_obsrvtn_events_vw USING GIST (localcode_ltree);
