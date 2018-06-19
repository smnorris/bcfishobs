-- Find points on streams that are within 100m of stream, but only
-- insert those with an exact match in the 20k-50k lookup.
-- This means that if we have multiple matches within 100m, we insert
-- the record with a match in the xref - if available.
WITH unmatched AS
(   SELECT e.*
    FROM whse_fish.fiss_fish_obsrvtn_events_prelim1 e
    INNER JOIN whse_fish.fiss_fish_obsrvtn_distinct o
    ON e.fish_obsrvtn_distinct_id = o.fish_obsrvtn_distinct_id
    INNER JOIN whse_basemapping.fwa_streams_20k_50k lut
    ON replace(o.new_watershed_code, '-', '') = lut.watershed_code_50k
    AND e.linear_feature_id = lut.linear_feature_id_20k
    WHERE o.waterbody_type NOT IN ('Lake', 'Wetland')
    AND e.distance_to_stream <= 100
    ORDER BY e.fish_obsrvtn_distinct_id , e.distance_to_stream
),

-- there can still potentially be multiple results, find the closest
closest_unmatched AS
(
  SELECT DISTINCT ON (fish_obsrvtn_distinct_id)
    fish_obsrvtn_distinct_id,
    distance_to_stream
  FROM unmatched
  ORDER BY fish_obsrvtn_distinct_id, distance_to_stream
)

INSERT INTO whse_fish.fiss_fish_obsrvtn_events_prelim2
SELECT DISTINCT ON (e.fish_obsrvtn_distinct_id)
  e.fish_obsrvtn_distinct_id,
  e.linear_feature_id,
  e.wscode_ltree,
  e.localcode_ltree,
  e.waterbody_key,
  e.blue_line_key,
  e.downstream_route_measure,
  e.distance_to_stream,
  'A. matched - stream; within 100m; lookup'
FROM whse_fish.fiss_fish_obsrvtn_events_prelim1 e
INNER JOIN closest_unmatched
ON e.fish_obsrvtn_distinct_id = closest_unmatched.fish_obsrvtn_distinct_id
AND e.distance_to_stream = closest_unmatched.distance_to_stream
