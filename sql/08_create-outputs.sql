-- Now that we are done with matching points to streams, create the output table

DROP MATERIALIZED VIEW IF EXISTS whse_fish.fiss_fish_obsrvtn_events_vw;
DROP TABLE IF EXISTS whse_fish.fiss_fish_obsrvtn_events;

CREATE TABLE whse_fish.fiss_fish_obsrvtn_events
( fish_obsrvtn_distinct_id integer,
  linear_feature_id integer,
  wscode_ltree ltree,
  localcode_ltree ltree,
  blue_line_key integer,
  waterbody_key integer,
  downstream_route_measure double precision,
  watershed_group_code character varying(4),
  obs_ids integer[],
  species_codes text[],
  maximal_species text[],
  distance_to_stream double precision,
  match_type text);

-- insert data from the _prelim2 table,
-- remove any duplicates by unnesting arrays and re-aggregating
WITH popped AS
(SELECT
  p2.fish_obsrvtn_distinct_id,
  p2.linear_feature_id,
  p2.wscode_ltree,
  p2.localcode_ltree,
  p2.blue_line_key,
  p2.waterbody_key,
  p2.downstream_route_measure,
  s.watershed_group_code,
  unnest(dstnct.obs_ids) as obs_id,
  unnest(dstnct.species_codes) as species_code
FROM whse_fish.fiss_fish_obsrvtn_events_prelim2 p2
INNER JOIN whse_fish.fiss_fish_obsrvtn_distinct dstnct
ON p2.fish_obsrvtn_distinct_id = dstnct.fish_obsrvtn_distinct_id
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
  array_agg(obs_id) as obs_ids,
  array_agg(species_code) AS species_codes
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

INSERT INTO whse_fish.fiss_fish_obsrvtn_events
 ( fish_obsrvtn_distinct_id,
  linear_feature_id,
  wscode_ltree,
  localcode_ltree,
  blue_line_key,
  waterbody_key,
  downstream_route_measure,
  watershed_group_code,
  obs_ids,
  species_codes,
  distance_to_stream,
  match_type)

-- finally, on insert only return one record per unique blue_line_key / measure
-- This eliminates duplicate events (and while we don't really care which point is
-- retained, sorting by distance_to_stream ensures it is the closest)
SELECT DISTINCT ON (blue_line_key, downstream_route_measure)
  p.fish_obsrvtn_distinct_id,
  a.linear_feature_id,
  a.wscode_ltree,
  a.localcode_ltree,
  a.blue_line_key,
  a.waterbody_key,
  a.downstream_route_measure,
  a.watershed_group_code,
  a.obs_ids,
  a.species_codes,
  p.distance_to_stream,
  p.match_type
 FROM agg a
 INNER JOIN whse_fish.fiss_fish_obsrvtn_events_prelim2 p
 ON a.blue_line_key = p.blue_line_key
 AND a.downstream_route_measure = p.downstream_route_measure
 ORDER BY blue_line_key, downstream_route_measure, distance_to_stream;


CREATE INDEX ON whse_fish.fiss_fish_obsrvtn_events USING gist (wscode_ltree);
CREATE INDEX ON whse_fish.fiss_fish_obsrvtn_events USING btree (wscode_ltree);
CREATE INDEX ON whse_fish.fiss_fish_obsrvtn_events USING gist (localcode_ltree) ;
CREATE INDEX ON whse_fish.fiss_fish_obsrvtn_events USING btree (localcode_ltree);
CREATE INDEX ON whse_fish.fiss_fish_obsrvtn_events (linear_feature_id);
CREATE INDEX ON whse_fish.fiss_fish_obsrvtn_events (blue_line_key);
CREATE INDEX ON whse_fish.fiss_fish_obsrvtn_events (waterbody_key);


-- Dump all un-referenced points (within 1500m of a stream) for QA.
-- Note that points >1500m from a stream will not be in this table, but there
-- are not many of those.
DROP TABLE IF EXISTS whse_fish.fiss_fish_obsrvtn_unmatched;
CREATE TABLE whse_fish.fiss_fish_obsrvtn_unmatched AS
SELECT DISTINCT ON (e1.fish_obsrvtn_distinct_id)
  e1.fish_obsrvtn_distinct_id,
  o.obs_ids,
  o.species_codes,
  e1.distance_to_stream,
  o.geom
FROM whse_fish.fiss_fish_obsrvtn_events_prelim1 e1
LEFT OUTER JOIN whse_fish.fiss_fish_obsrvtn_events_prelim2 e2
ON e1.fish_obsrvtn_distinct_id = e2.fish_obsrvtn_distinct_id
INNER JOIN whse_fish.fiss_fish_obsrvtn_distinct o
ON e1.fish_obsrvtn_distinct_id = o.fish_obsrvtn_distinct_id
WHERE e2.fish_obsrvtn_distinct_id IS NULL
ORDER BY e1.fish_obsrvtn_distinct_id, e1.distance_to_stream;

ALTER TABLE whse_fish.fiss_fish_obsrvtn_unmatched
ADD PRIMARY KEY (fish_obsrvtn_distinct_id);
