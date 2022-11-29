-- clear existing data
truncate bcfishobs.fiss_fish_obsrvtn_events;

-- de-aggregate
WITH popped AS (
  SELECT
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
  FROM temp.fiss_fish_obsrvtn_events_prelim_b p2
  INNER JOIN temp.fiss_fish_obsrvtn_pnt_distinct dstnct
  ON p2.fish_obsrvtn_pnt_distinct_id = dstnct.fish_obsrvtn_pnt_distinct_id
),

-- round the measures to further de-duplicate locations (and reduce excess precision)
-- (note that observations will be shifted slightly away from ends of stream lines due to rounding)
rounded as (
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
insert into bcfishobs.fiss_fish_obsrvtn_events (  
  linear_feature_id,
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
and r.downstream_route_measure >= s.downstream_route_measure
GROUP BY
  s.linear_feature_id,
  s.wscode_ltree,
  s.localcode_ltree,
  r.blue_line_key,
  r.downstream_route_measure,
  postgisftw.FWA_LocateAlong(r.blue_line_key, r.downstream_route_measure)
ORDER BY r.blue_line_key, r.downstream_route_measure
on conflict do nothing; 


-- Dump all un-referenced points (within 1500m of a stream) for QA.
-- Note that points >1500m from a stream will not be in this table, but there
-- are not many of those.
truncate bcfishobs.fiss_fish_obsrvtn_unmatched;
insert into bcfishobs.fiss_fish_obsrvtn_unmatched (
  fish_obsrvtn_pnt_distinct_id,
  obs_ids,
  species_ids,
  distance_to_stream,
  geom
)
SELECT DISTINCT ON (e1.fish_obsrvtn_pnt_distinct_id)
  e1.fish_obsrvtn_pnt_distinct_id,
  o.obs_ids,
  o.species_ids,
  e1.distance_to_stream,
  o.geom
FROM temp.fiss_fish_obsrvtn_events_prelim_a e1
LEFT OUTER JOIN temp.fiss_fish_obsrvtn_events_prelim_b e2
ON e1.fish_obsrvtn_pnt_distinct_id = e2.fish_obsrvtn_pnt_distinct_id
INNER JOIN temp.fiss_fish_obsrvtn_pnt_distinct o
ON e1.fish_obsrvtn_pnt_distinct_id = o.fish_obsrvtn_pnt_distinct_id
WHERE e2.fish_obsrvtn_pnt_distinct_id IS NULL
ORDER BY e1.fish_obsrvtn_pnt_distinct_id, e1.distance_to_stream;