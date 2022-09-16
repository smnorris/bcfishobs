DROP TABLE IF EXISTS bcfishobs.fiss_fish_obsrvtn_events CASCADE;

CREATE TABLE bcfishobs.fiss_fish_obsrvtn_events
( fish_obsrvtn_event_id bigint
     GENERATED ALWAYS AS ((((blue_line_key::bigint + 1) - 354087611) * 10000000) + round(downstream_route_measure::bigint)) STORED PRIMARY KEY,
  linear_feature_id integer,
  wscode_ltree ltree,
  localcode_ltree ltree,
  blue_line_key integer,
  downstream_route_measure double precision,
  match_types text[],
  obs_ids integer[],
  species_codes text[],
  species_ids integer[],
  maximal_species integer[],
  distances_to_stream double precision[]
  );


-- de-aggregate
WITH popped AS
(SELECT
  p2.fish_obsrvtn_pnt_distinct_id,
  p2.linear_feature_id,
  p2.wscode_ltree,
  p2.localcode_ltree,
  p2.blue_line_key,
  p2.waterbody_key,
  p2.downstream_route_measure,
  p2.match_type,
  p2.distance_to_stream,
  unnest(dstnct.obs_ids) as obs_id,
  unnest(dstnct.species_codes) as species_code,
  unnest(dstnct.species_ids) as species_id
FROM bcfishobs.fiss_fish_obsrvtn_events_prelim2 p2
INNER JOIN bcfishobs.fiss_fish_obsrvtn_pnt_distinct dstnct
ON p2.fish_obsrvtn_pnt_distinct_id = dstnct.fish_obsrvtn_pnt_distinct_id
),

-- round the measures to further de-duplicate locations (and reduce excess precision)
-- (note that observations will be shifted slightly away from ends of stream lines due to rounding)
rounded as
(
  SELECT
  p.linear_feature_id,
  p.wscode_ltree,
  p.localcode_ltree,
  p.blue_line_key,
  p.waterbody_key,
  p.match_type,
  p.distance_to_stream,
  CEIL(GREATEST(s.downstream_route_measure, FLOOR(LEAST(s.upstream_route_measure, p.downstream_route_measure)))) as downstream_route_measure,
  s.watershed_group_code,
  p.obs_id,
  p.species_code,
  p.species_id
FROM popped p
INNER JOIN whse_basemapping.fwa_stream_networks_sp s
ON p.linear_feature_id = s.linear_feature_id
)

-- re-aggregate on network location, collapsing info about individual observation into arrays.
-- Also, get linear_feature_id and wscode values for upstream/downstream queries.
-- Note that to get the matching stream, we can't just join based on blkey and measure due to FWA 
-- data errors (>1 match in isolated cases where source stream has incorrect dnstr measure). To
-- correct for this, join back to source geom and order by distance to matched stream, only inserting
-- the first match.
insert into bcfishobs.fiss_fish_obsrvtn_events
  (  linear_feature_id,
  wscode_ltree,
  localcode_ltree,
  blue_line_key,
  downstream_route_measure,
  obs_ids,
  species_ids,
  species_codes,
  distances_to_stream,
  match_types
  )
SELECT
  s.linear_feature_id,
  s.wscode_ltree,
  s.localcode_ltree,
  r.blue_line_key,
  r.downstream_route_measure,
  array_agg(r.obs_id) as obs_ids,
  array_agg(r.species_id) AS species_ids,
  array_agg(r.species_code) AS species_codes,
  array_agg(r.distance_to_stream) as distances_to_stream,
  array_agg(r.match_type) as match_types
FROM rounded r
inner join whse_fish.fiss_fish_obsrvtn_pnt_sp o
on r.obs_id = o.fish_observation_point_id
inner join whse_basemapping.fwa_stream_networks_sp s
ON r.blue_line_key = s.blue_line_key
and r.downstream_route_measure < s.upstream_route_measure
and r.downstream_route_measure > s.downstream_route_measure
GROUP BY
  s.linear_feature_id,
  s.wscode_ltree,
  s.localcode_ltree,
  r.blue_line_key,
  r.downstream_route_measure,
  o.geom
ORDER BY r.blue_line_key, r.downstream_route_measure, st_distance(s.geom, o.geom)
on conflict do nothing; 

CREATE INDEX ON bcfishobs.fiss_fish_obsrvtn_events (blue_line_key);
CREATE INDEX ON bcfishobs.fiss_fish_obsrvtn_events USING GIST (obs_ids gist__intbig_ops);
CREATE INDEX ON bcfishobs.fiss_fish_obsrvtn_events USING GIST (species_ids gist__intbig_ops);


-- create primary output - all matched observations as single points, snapped to streams

DROP TABLE IF EXISTS bcfishobs.fiss_fish_obsrvtn_events_sp;

CREATE TABLE bcfishobs.fiss_fish_obsrvtn_events_sp AS

WITH all_obs AS
(SELECT
   unnest(e.obs_ids) AS fish_observation_point_id,
   s.linear_feature_id,
   s.wscode_ltree,
   s.localcode_ltree,
   e.blue_line_key,
   s.waterbody_key,
   e.downstream_route_measure,
   unnest(e.distances_to_stream) as distance_to_stream,
   unnest(e.match_types) as match_type,
   s.watershed_group_code,
   postgisftw.FWA_LocateAlong(e.blue_line_key, e.downstream_route_measure) as geom
FROM bcfishobs.fiss_fish_obsrvtn_events e
INNER JOIN whse_basemapping.fwa_stream_networks_sp s
ON e.blue_line_key = s.blue_line_key
and e.downstream_route_measure < s.upstream_route_measure
and e.downstream_route_measure > s.downstream_route_measure)

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