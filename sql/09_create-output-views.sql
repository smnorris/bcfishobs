-- for convenience, create a view that holds all observation
-- events (not just distinct locations), commonly queried columns, and the
-- location that the observation is referenced to - as a point geometry with Z and M values

DROP MATERIALIZED VIEW IF EXISTS whse_fish.fiss_fish_obsrvtn_events_vw CASCADE;

CREATE MATERIALIZED VIEW whse_fish.fiss_fish_obsrvtn_events_vw AS

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
   (ST_Dump(
      ST_LocateAlong(s.geom, e.downstream_route_measure)
      )
   ).geom::geometry(PointZM, 3005) AS geom
FROM whse_fish.fiss_fish_obsrvtn_events e
INNER JOIN whse_basemapping.fwa_stream_networks_sp s
ON e.linear_feature_id = s.linear_feature_id)

SELECT
  a.fish_observation_point_id,
  a.linear_feature_id,
  a.wscode_ltree,
  a.localcode_ltree,
  a.blue_line_key,
  a.waterbody_key,
  a.downstream_route_measure,
  a.distance_to_stream,
  a.match_type,
  a.watershed_group_code,
  b.species_code,
  b.agency_id,
  b.observation_date,
  b.agency_name,
  b.source,
  b.source_ref,
  a.geom
FROM all_obs a
INNER JOIN whse_fish.fiss_fish_obsrvtn_pnt_sp  b
ON a.fish_observation_point_id = b.fish_observation_point_id;

-- create indexes
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
