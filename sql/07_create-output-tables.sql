DROP TABLE IF EXISTS bcfishobs.fiss_fish_obsrvtn_events CASCADE;

CREATE TABLE bcfishobs.fiss_fish_obsrvtn_events
( fish_obsrvtn_event_id bigint
     GENERATED ALWAYS AS ((((blue_line_key::bigint + 1) - 354087611) * 10000000) + round(downstream_route_measure::bigint)) STORED PRIMARY KEY,
  linear_feature_id integer,
  wscode_ltree ltree,
  localcode_ltree ltree,
  blue_line_key integer,
  watershed_group_code character varying(4),
  downstream_route_measure double precision,
  match_types text[],
  obs_ids integer[],
  species_codes text[],
  species_ids integer[],
  maximal_species integer[],
  distances_to_stream double precision[],
  geom geometry(pointzm, 3005)
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
  watershed_group_code,
  downstream_route_measure,
  obs_ids,
  species_ids,
  species_codes,
  distances_to_stream,
  match_types,
  geom
  )
SELECT
  s.linear_feature_id,
  s.wscode_ltree,
  s.localcode_ltree,
  r.blue_line_key,
  s.watershed_group_code,
  r.downstream_route_measure,
  array_agg(r.obs_id) as obs_ids,
  array_agg(r.species_id) AS species_ids,
  array_agg(r.species_code) AS species_codes,
  array_agg(r.distance_to_stream) as distances_to_stream,
  array_agg(r.match_type) as match_types,
  postgisftw.FWA_LocateAlong(r.blue_line_key, r.downstream_route_measure) as geom
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

CREATE INDEX ON bcfishobs.fiss_fish_obsrvtn_events (linear_feature_id);
CREATE INDEX ON bcfishobs.fiss_fish_obsrvtn_events (blue_line_key);
CREATE INDEX ON bcfishobs.fiss_fish_obsrvtn_events (wscode_ltree);
CREATE INDEX ON bcfishobs.fiss_fish_obsrvtn_events (localcode_ltree);
CREATE INDEX ON bcfishobs.fiss_fish_obsrvtn_events_sp USING GIST (wscode_ltree);
CREATE INDEX ON bcfishobs.fiss_fish_obsrvtn_events_sp USING GIST (localcode_ltree);
CREATE INDEX ON bcfishobs.fiss_fish_obsrvtn_events_sp USING GIST (geom);
CREATE INDEX ON bcfishobs.fiss_fish_obsrvtn_events USING GIST (obs_ids gist__intbig_ops);
CREATE INDEX ON bcfishobs.fiss_fish_obsrvtn_events USING GIST (species_ids gist__intbig_ops);



-- de-aggregated view - all matched observations as single points, snapped to streams
DROP VIEW IF EXISTS bcfishobs.fiss_fish_obsrvtn_events_vw;
CREATE VIEW bcfishobs.fiss_fish_obsrvtn_events_vw AS

WITH all_obs AS
(SELECT
   unnest(e.obs_ids) AS fish_observation_point_id,
   e.fish_obsrvtn_event_id,
   s.linear_feature_id,
   s.wscode_ltree,
   s.localcode_ltree,
   e.blue_line_key,
   s.waterbody_key,
   e.downstream_route_measure,
   unnest(e.distances_to_stream) as distance_to_stream,
   unnest(e.match_types) as match_type,
   s.watershed_group_code,
   e.geom
FROM bcfishobs.fiss_fish_obsrvtn_events e
INNER JOIN whse_basemapping.fwa_stream_networks_sp s
ON e.linear_feature_id = s.linear_feature_id
)

SELECT
  a.fish_observation_point_id,
  a.fish_obsrvtn_event_id,
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


COMMENT ON TABLE bcfishobs.fiss_fish_obsrvtn_events IS 'Unique locations of BC Fish Observations snapped to FWA streams';
COMMENT ON COLUMN bcfishobs.fiss_fish_obsrvtn_events.fish_obsrvtn_event_id IS 'Unique identifier, linked to blue_line_key and measure';
COMMENT ON COLUMN bcfishobs.fiss_fish_obsrvtn_events.match_types IS 'Notes on how the observation(s) were matched to the stream';
COMMENT ON COLUMN bcfishobs.fiss_fish_obsrvtn_events.obs_ids IS 'fish_observation_point_id for observations associated with the location';
COMMENT ON COLUMN bcfishobs.fiss_fish_obsrvtn_events.species_codes IS 'BC fish species codes, see https://raw.githubusercontent.com/smnorris/fishbc/master/data-raw/whse_fish_species_cd/whse_fish_species_cd.csv';
COMMENT ON COLUMN bcfishobs.fiss_fish_obsrvtn_events.species_ids IS 'Species IDs, see https://raw.githubusercontent.com/smnorris/fishbc/master/data-raw/whse_fish_species_cd/whse_fish_species_cd.csv';
COMMENT ON COLUMN bcfishobs.fiss_fish_obsrvtn_events.maximal_species IS 'Indicates if the observation is the most upstream for the given species (no additional observations upstream)';
COMMENT ON COLUMN bcfishobs.fiss_fish_obsrvtn_events.distances_to_stream IS 'Distances (m) from source observations to output point';
COMMENT ON COLUMN bcfishobs.fiss_fish_obsrvtn_events.geom IS 'Geometry of observation(s) on the FWA stream (measure rounded to the nearest metre)';

COMMENT ON VIEW bcfishobs.fiss_fish_obsrvtn_events_vw IS 'BC Fish Observations snapped to FWA streams';
COMMENT ON COLUMN bcfishobs.fiss_fish_obsrvtn_events.fish_obsrvtn_event_id IS 'Links to fiss_fish_obsrvtn_events, a unique location on the stream network based on blue_line_key and measure';
COMMENT ON COLUMN bcfishobs.fiss_fish_obsrvtn_events_vw.fish_observation_point_id IS 'Source observation primary key';
COMMENT ON COLUMN bcfishobs.fiss_fish_obsrvtn_events_vw.distance_to_stream IS 'Distance (m) from source observation to output point';
COMMENT ON COLUMN bcfishobs.fiss_fish_obsrvtn_events_vw.match_type IS 'Notes on how the observation was matched to the stream';
COMMENT ON COLUMN bcfishobs.fiss_fish_obsrvtn_events_vw.species_id IS 'Species ID, see https://raw.githubusercontent.com/smnorris/fishbc/master/data-raw/whse_fish_species_cd/whse_fish_species_cd.csv';
COMMENT ON COLUMN bcfishobs.fiss_fish_obsrvtn_events_vw.species_code IS 'BC fish species code, see https://raw.githubusercontent.com/smnorris/fishbc/master/data-raw/whse_fish_species_cd/whse_fish_species_cd.csv';
COMMENT ON COLUMN bcfishobs.fiss_fish_obsrvtn_events_vw.agency_id IS '';
COMMENT ON COLUMN bcfishobs.fiss_fish_obsrvtn_events_vw.observation_date IS 'The date on which the observation occurred.';
COMMENT ON COLUMN bcfishobs.fiss_fish_obsrvtn_events_vw.agency_name IS 'The name of the agency that made the observation.';
COMMENT ON COLUMN bcfishobs.fiss_fish_obsrvtn_events_vw.source IS 'The abbreviation, and if appropriate, the primary key, of the dataset(s) from which the data was obtained. For example: FDIS Database: fshclctn_id 66589';
COMMENT ON COLUMN bcfishobs.fiss_fish_obsrvtn_events_vw.source_ref IS 'The concatenation of all biographical references for the source data.  This may include citations to reports that published the observations, or the name of a project under which the observations were made. Some example values for SOURCE REF are: A RECONNAISSANCE SURVEY OF CULTUS LAKE, and Bonaparte Watershed Fish and Fish Habitat Inventory - 2000';
COMMENT ON COLUMN bcfishobs.fiss_fish_obsrvtn_events_vw.geom IS 'Geometry of observation on the FWA stream (measure rounded to the nearest metre)';