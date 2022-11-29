-- Finally, within records that still have not been inserted,
-- find those that are >100m and <500m from a stream and have a exact
-- (linear_feature_id) match in the xref lookup.

WITH unmatched AS
(   SELECT e1.*
    FROM temp.fiss_fish_obsrvtn_events_prelim_a e1
    LEFT OUTER JOIN temp.fiss_fish_obsrvtn_events_prelim_b e2
    ON e1.fish_obsrvtn_pnt_distinct_id = e2.fish_obsrvtn_pnt_distinct_id
    INNER JOIN temp.fiss_fish_obsrvtn_pnt_distinct o
    ON e1.fish_obsrvtn_pnt_distinct_id = o.fish_obsrvtn_pnt_distinct_id
    INNER JOIN whse_basemapping.fwa_streams_20k_50k lut
    ON replace(o.new_watershed_code, '-', '') = lut.watershed_code_50k
    AND e1.linear_feature_id = lut.linear_feature_id_20k
    WHERE o.waterbody_type NOT IN ('Lake', 'Wetland')
    AND e1.distance_to_stream > 100 AND e1.distance_to_stream < 500
    AND e2.fish_obsrvtn_pnt_distinct_id IS NULL
    ORDER BY e1.fish_obsrvtn_pnt_distinct_id , e1.distance_to_stream
),

-- there can still potentially be multiple results, find the closest
closest_unmatched AS
(
  SELECT DISTINCT ON (fish_obsrvtn_pnt_distinct_id)
    fish_obsrvtn_pnt_distinct_id,
    distance_to_stream
  FROM unmatched
  ORDER BY fish_obsrvtn_pnt_distinct_id, distance_to_stream
)

INSERT INTO temp.fiss_fish_obsrvtn_events_prelim_b
SELECT DISTINCT ON (e.fish_obsrvtn_pnt_distinct_id)
  e.fish_obsrvtn_pnt_distinct_id,
  e.linear_feature_id,
  e.wscode_ltree,
  e.localcode_ltree,
  e.waterbody_key,
  e.blue_line_key,
  e.downstream_route_measure,
  e.distance_to_stream,
  'C. matched - stream; 100-500m; lookup'
FROM temp.fiss_fish_obsrvtn_events_prelim_a e
INNER JOIN closest_unmatched
ON e.fish_obsrvtn_pnt_distinct_id = closest_unmatched.fish_obsrvtn_pnt_distinct_id
AND e.distance_to_stream = closest_unmatched.distance_to_stream
INNER JOIN temp.fiss_fish_obsrvtn_pnt_distinct o
ON e.fish_obsrvtn_pnt_distinct_id = o.fish_obsrvtn_pnt_distinct_id
