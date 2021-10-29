-- Now that we are done with matching points to streams,
-- create the output table

DROP TABLE IF EXISTS bcfishobs.fiss_fish_obsrvtn_events CASCADE;

CREATE TABLE bcfishobs.fiss_fish_obsrvtn_events
( fish_obsrvtn_pnt_distinct_id integer,
  linear_feature_id integer,
  wscode_ltree ltree,
  localcode_ltree ltree,
  blue_line_key integer,
  waterbody_key integer,
  downstream_route_measure double precision,
  watershed_group_code character varying(4),
  obs_ids integer[],
  species_codes text[],
  species_ids integer[],
  maximal_species integer[],
  distance_to_stream double precision,
  match_type text);

-- insert data from the _prelim2 table,
-- remove any duplicates by unnesting arrays and re-aggregating
WITH popped AS
(SELECT
  p2.fish_obsrvtn_pnt_distinct_id,
  p2.linear_feature_id,
  p2.wscode_ltree,
  p2.localcode_ltree,
  p2.blue_line_key,
  p2.waterbody_key,
  p2.downstream_route_measure,
  s.watershed_group_code,
  unnest(dstnct.obs_ids) as obs_id,
  unnest(dstnct.species_codes) as species_code,
  unnest(dstnct.species_ids) as species_id
FROM bcfishobs.fiss_fish_obsrvtn_events_prelim2 p2
INNER JOIN bcfishobs.fiss_fish_obsrvtn_pnt_distinct dstnct
ON p2.fish_obsrvtn_pnt_distinct_id = dstnct.fish_obsrvtn_pnt_distinct_id
INNER JOIN whse_basemapping.fwa_stream_networks_sp s
ON p2.linear_feature_id = s.linear_feature_id),

-- re-aggregate, collapsing observations and species into arrays
agg AS
(SELECT
  linear_feature_id,
  wscode_ltree,
  localcode_ltree,
  blue_line_key,
  waterbody_key,
  downstream_route_measure,
  watershed_group_code,
  array_agg(distinct obs_id) as obs_ids,
  array_agg(distinct species_id) AS species_ids,
  array_agg(distinct species_code) AS species_codes
FROM popped
GROUP BY
  linear_feature_id,
  wscode_ltree,
  localcode_ltree,
  blue_line_key,
  waterbody_key,
  downstream_route_measure,
  watershed_group_code
ORDER BY blue_line_key, downstream_route_measure
)

INSERT INTO bcfishobs.fiss_fish_obsrvtn_events
 ( fish_obsrvtn_pnt_distinct_id,
  linear_feature_id,
  wscode_ltree,
  localcode_ltree,
  blue_line_key,
  waterbody_key,
  downstream_route_measure,
  watershed_group_code,
  obs_ids,
  species_ids,
  species_codes,
  distance_to_stream,
  match_type)

-- finally, on insert only return one record per unique blue_line_key / measure
-- This eliminates duplicate events (and while we don't really care which
-- point is retained, sorting by distance_to_stream ensures it is the closest)
SELECT DISTINCT ON (blue_line_key, downstream_route_measure)
  p.fish_obsrvtn_pnt_distinct_id,
  a.linear_feature_id,
  a.wscode_ltree,
  a.localcode_ltree,
  a.blue_line_key,
  a.waterbody_key,
  a.downstream_route_measure,
  a.watershed_group_code,
  a.obs_ids,
  a.species_ids,
  a.species_codes,
  p.distance_to_stream,
  p.match_type
 FROM agg a
 INNER JOIN bcfishobs.fiss_fish_obsrvtn_events_prelim2 p
 ON a.blue_line_key = p.blue_line_key
 AND a.downstream_route_measure = p.downstream_route_measure
 ORDER BY blue_line_key, downstream_route_measure, distance_to_stream;


CREATE INDEX ON bcfishobs.fiss_fish_obsrvtn_events USING gist (wscode_ltree);
CREATE INDEX ON bcfishobs.fiss_fish_obsrvtn_events USING btree (wscode_ltree);
CREATE INDEX ON bcfishobs.fiss_fish_obsrvtn_events USING gist (localcode_ltree) ;
CREATE INDEX ON bcfishobs.fiss_fish_obsrvtn_events USING btree (localcode_ltree);
CREATE INDEX ON bcfishobs.fiss_fish_obsrvtn_events (linear_feature_id);
CREATE INDEX ON bcfishobs.fiss_fish_obsrvtn_events (blue_line_key);
CREATE INDEX ON bcfishobs.fiss_fish_obsrvtn_events (waterbody_key);

-- index the species ids and observation ids for fast retreival
CREATE INDEX ON bcfishobs.fiss_fish_obsrvtn_events USING GIST (obs_ids gist__intbig_ops);
CREATE INDEX ON bcfishobs.fiss_fish_obsrvtn_events USING GIST (species_ids gist__intbig_ops);

-- Dump all un-referenced points (within 1500m of a stream) for QA.
-- Note that points >1500m from a stream will not be in this table, but there
-- are not many of those.
DROP TABLE IF EXISTS bcfishobs.fiss_fish_obsrvtn_unmatched;
CREATE TABLE bcfishobs.fiss_fish_obsrvtn_unmatched AS
SELECT DISTINCT ON (e1.fish_obsrvtn_pnt_distinct_id)
  e1.fish_obsrvtn_pnt_distinct_id,
  o.obs_ids,
  o.species_ids,
  e1.distance_to_stream,
  o.geom
FROM bcfishobs.fiss_fish_obsrvtn_events_prelim1 e1
LEFT OUTER JOIN bcfishobs.fiss_fish_obsrvtn_events_prelim2 e2
ON e1.fish_obsrvtn_pnt_distinct_id = e2.fish_obsrvtn_pnt_distinct_id
INNER JOIN bcfishobs.fiss_fish_obsrvtn_pnt_distinct o
ON e1.fish_obsrvtn_pnt_distinct_id = o.fish_obsrvtn_pnt_distinct_id
WHERE e2.fish_obsrvtn_pnt_distinct_id IS NULL
ORDER BY e1.fish_obsrvtn_pnt_distinct_id, e1.distance_to_stream;

ALTER TABLE bcfishobs.fiss_fish_obsrvtn_unmatched
ADD PRIMARY KEY (fish_obsrvtn_pnt_distinct_id);


-- create a new table that adds (stream referenenced) geometry to the events table
-- this is probably the most used output

DROP TABLE IF EXISTS bcfishobs.fiss_fish_obsrvtn_events_sp;

CREATE TABLE bcfishobs.fiss_fish_obsrvtn_events_sp AS

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
   ST_LocateAlong(s.geom, e.downstream_route_measure) as geom
FROM bcfishobs.fiss_fish_obsrvtn_events e
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
  sp.species_id,
  b.species_code,
  b.agency_id,
  b.observation_date,
  b.agency_name,
  b.source,
  b.source_ref,
  (st_dump(a.geom)).geom::geometry(PointZM, 3005) AS geom
FROM all_obs a
INNER JOIN whse_fish.fiss_fish_obsrvtn_pnt_sp  b
ON a.fish_observation_point_id = b.fish_observation_point_id
INNER JOIN whse_fish.species_cd sp ON b.species_code = sp.code;

-- create indexes
CREATE INDEX ON bcfishobs.fiss_fish_obsrvtn_events_sp (linear_feature_id);
CREATE INDEX ON bcfishobs.fiss_fish_obsrvtn_events_sp (blue_line_key);
CREATE INDEX ON bcfishobs.fiss_fish_obsrvtn_events_sp (waterbody_key);
CREATE INDEX ON bcfishobs.fiss_fish_obsrvtn_events_sp (wscode_ltree);
CREATE INDEX ON bcfishobs.fiss_fish_obsrvtn_events_sp (localcode_ltree);
CREATE INDEX ON bcfishobs.fiss_fish_obsrvtn_events_sp (watershed_group_code);

-- create GIST indexes on geom and ltree types
CREATE INDEX ON bcfishobs.fiss_fish_obsrvtn_events_sp USING GIST (geom);
CREATE INDEX ON bcfishobs.fiss_fish_obsrvtn_events_sp USING GIST (wscode_ltree);
CREATE INDEX ON bcfishobs.fiss_fish_obsrvtn_events_sp USING GIST (localcode_ltree);

