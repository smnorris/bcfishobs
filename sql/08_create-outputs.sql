-- create output table, add source ids and species codes for easier use

DROP TABLE IF EXISTS whse_fish.fiss_fish_obsrvtn_events;

CREATE TABLE whse_fish.fiss_fish_obsrvtn_events
(fiss_fish_obsrvtn_distinct_id bigint PRIMARY KEY,
  linear_feature_id integer,
  wscode_ltree ltree,
  localcode_ltree ltree,
  blue_line_key integer,
  waterbody_key integer,
  downstream_route_measure double precision,
  distance_to_stream double precision,
  match_type text,
  watershed_group_code character varying(4),
  obs_ids integer[],
  species_codes character varying[]);

INSERT INTO whse_fish.fiss_fish_obsrvtn_events
SELECT DISTINCT
  p2.fiss_fish_obsrvtn_distinct_id,
  p2.linear_feature_id,
  p2.wscode_ltree,
  p2.localcode_ltree,
  p2.blue_line_key,
  p2.waterbody_key,
  p2.downstream_route_measure,
  p2.distance_to_stream,
  p2.match_type,
  s.watershed_group_code,
  dstnct.obs_ids,
  dstnct.species_codes
FROM whse_fish.fiss_fish_obsrvtn_events_prelim2 p2
INNER JOIN whse_fish.fiss_fish_obsrvtn_distinct dstnct
ON p2.fiss_fish_obsrvtn_distinct_id = dstnct.fiss_fish_obsrvtn_distinct_id
INNER JOIN whse_basemapping.fwa_stream_networks_sp s ON p2.linear_feature_id = s.linear_feature_id;

CREATE INDEX ON whse_fish.fiss_fish_obsrvtn_events USING gist (wscode_ltree);
CREATE INDEX ON whse_fish.fiss_fish_obsrvtn_events USING btree (wscode_ltree);
CREATE INDEX ON whse_fish.fiss_fish_obsrvtn_events USING gist (localcode_ltree) ;
CREATE INDEX ON whse_fish.fiss_fish_obsrvtn_events USING btree (localcode_ltree);
CREATE INDEX ON whse_fish.fiss_fish_obsrvtn_events (linear_feature_id);
CREATE INDEX ON whse_fish.fiss_fish_obsrvtn_events (blue_line_key);
CREATE INDEX ON whse_fish.fiss_fish_obsrvtn_events (waterbody_key);


-- Dump all un-referenced points for QA
DROP TABLE IF EXISTS whse_fish.fiss_fish_obsrvtn_unmatched;
CREATE TABLE whse_fish.fiss_fish_obsrvtn_unmatched AS
SELECT DISTINCT ON (e1.fiss_fish_obsrvtn_distinct_id)
  e1.fiss_fish_obsrvtn_distinct_id,
  o.obs_ids,
  o.species_codes,
  e1.distance_to_stream,
  o.geom
FROM whse_fish.fiss_fish_obsrvtn_events_prelim1 e1
LEFT OUTER JOIN whse_fish.fiss_fish_obsrvtn_events_prelim2 e2
ON e1.fiss_fish_obsrvtn_distinct_id = e2.fiss_fish_obsrvtn_distinct_id
INNER JOIN whse_fish.fiss_fish_obsrvtn_distinct o
ON e1.fiss_fish_obsrvtn_distinct_id = o.fiss_fish_obsrvtn_distinct_id
WHERE e2.fiss_fish_obsrvtn_distinct_id IS NULL
ORDER BY e1.fiss_fish_obsrvtn_distinct_id, e1.distance_to_stream;

ALTER TABLE whse_fish.fiss_fish_obsrvtn_unmatched
ADD PRIMARY KEY (fiss_fish_obsrvtn_distinct_id);

-- drop temp tables
DROP TABLE IF EXISTS whse_fish.wdic_waterbodies_load;
DROP TABLE whse_fish.fiss_fish_obsrvtn_events_prelim1;
DROP TABLE whse_fish.fiss_fish_obsrvtn_events_prelim2;