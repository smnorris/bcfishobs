-- Insert observations on waterbodies, matching on wb_key, within 1500m
-- ---------------------------------------------
create table bcfishobs.fiss_fish_obsrvtn_events_prelim_b (
  fish_obsrvtn_pnt_distinct_id integer primary key,
  linear_feature_id bigint,
  wscode_ltree ltree,
  localcode_ltree ltree,
  waterbody_key integer,
  blue_line_key integer,
  downstream_route_measure double precision,
  distance_to_stream double precision,
  match_type text
);

-- ---------------------------------------------
-- Insert events matched to waterbodies.
-- This is perhaps more complicated than it has to be but we want to
-- ensure that observations in waterbodies are associated with waterbodies.
-- We use a large 1500m tolerance (in previous query) because observations in
-- larger lakes can be quite far from a stream flow line. This makes the
-- assumption we can prioritize the waterbody key of observation points
-- over the actual the location of the point.

-- This query:
--   - joins the observations to the FWA via wbody_key (1:many via lookup)
--   - from the many possible matches, choose just the closest
--   - inserts these records into the output table

-- where observation is coded as a lake or wetland,
-- join to waterbody_key via wdic_waterbodies
WITH wb AS
(
  SELECT DISTINCT
    o.fish_obsrvtn_pnt_distinct_id,
    wb.waterbody_key
  FROM bcfishobs.fiss_fish_obsrvtn_pnt_distinct o
  INNER JOIN whse_fish.wdic_waterbodies wdic ON o.wbody_id = wdic.id
  INNER JOIN whse_basemapping.fwa_waterbodies_20k_50k lut
     ON LTRIM(wdic.waterbody_identifier,'0') = lut.waterbody_key_50k::TEXT||lut.watershed_group_code_50k
  INNER JOIN whse_basemapping.fwa_waterbodies wb
  ON lut.waterbody_key_20k = wb.waterbody_key
  WHERE o.waterbody_type IN ('Lake', 'Wetland')
  ORDER BY o.fish_obsrvtn_pnt_distinct_id
),
-- from the candidate matches generated above, use the one closest to a stream
closest AS
(
  SELECT DISTINCT ON
   (e.fish_obsrvtn_pnt_distinct_id)
    e.fish_obsrvtn_pnt_distinct_id,
    e.distance_to_stream
  FROM bcfishobs.fiss_fish_obsrvtn_events_prelim_a e
  INNER JOIN wb ON e.fish_obsrvtn_pnt_distinct_id = wb.fish_obsrvtn_pnt_distinct_id
  AND e.waterbody_key = wb.waterbody_key
  ORDER BY fish_obsrvtn_pnt_distinct_id, distance_to_stream
)
-- Insert the results into our output table
-- Note that there are duplicate records because observations can be
-- equidistant from
-- several stream lines. Insert records with highest measure (though they
-- should be the same)
INSERT INTO bcfishobs.fiss_fish_obsrvtn_events_prelim_b
SELECT DISTINCT ON (e.fish_obsrvtn_pnt_distinct_id)
  e.fish_obsrvtn_pnt_distinct_id,
  e.linear_feature_id,
  e.wscode_ltree,
  e.localcode_ltree,
  e.waterbody_key,
  e.blue_line_key,
  e.downstream_route_measure,
  e.distance_to_stream,
  'D. matched - waterbody; construction line within 1500m; lookup'
FROM bcfishobs.fiss_fish_obsrvtn_events_prelim_a e
INNER JOIN closest
ON e.fish_obsrvtn_pnt_distinct_id = closest.fish_obsrvtn_pnt_distinct_id
AND e.distance_to_stream = closest.distance_to_stream
WHERE e.waterbody_key is NOT NULL
ORDER BY e.fish_obsrvtn_pnt_distinct_id, e.downstream_route_measure;


-- ---------------------------------------------
-- Some observations in waterbodies do not get added above due to
-- lookup quirks.
-- Insert these records simply based on the closest stream
-- ---------------------------------------------
WITH unmatched_wb AS
(    SELECT e.*
    FROM bcfishobs.fiss_fish_obsrvtn_events_prelim_a e
    INNER JOIN bcfishobs.fiss_fish_obsrvtn_pnt_distinct o
    ON e.fish_obsrvtn_pnt_distinct_id = o.fish_obsrvtn_pnt_distinct_id
    LEFT OUTER JOIN bcfishobs.fiss_fish_obsrvtn_events_prelim_b p
    ON e.fish_obsrvtn_pnt_distinct_id = p.fish_obsrvtn_pnt_distinct_id
    WHERE o.wbody_id IS NOT NULL AND o.waterbody_type IN ('Lake','Wetland')
    AND p.fish_obsrvtn_pnt_distinct_id IS NULL
),

closest_unmatched AS
(
  SELECT DISTINCT ON (fish_obsrvtn_pnt_distinct_id)
    fish_obsrvtn_pnt_distinct_id,
    distance_to_stream
  FROM unmatched_wb
  ORDER BY fish_obsrvtn_pnt_distinct_id, distance_to_stream
)

INSERT INTO bcfishobs.fiss_fish_obsrvtn_events_prelim_b
SELECT DISTINCT ON (e.fish_obsrvtn_pnt_distinct_id)
  e.fish_obsrvtn_pnt_distinct_id,
  e.linear_feature_id,
  e.wscode_ltree,
  e.localcode_ltree,
  e.waterbody_key,
  e.blue_line_key,
  e.downstream_route_measure,
  e.distance_to_stream,
  'E. matched - waterbody; construction line within 1500m; closest'
FROM bcfishobs.fiss_fish_obsrvtn_events_prelim_a e
INNER JOIN closest_unmatched
ON e.fish_obsrvtn_pnt_distinct_id = closest_unmatched.fish_obsrvtn_pnt_distinct_id
AND e.distance_to_stream = closest_unmatched.distance_to_stream
ORDER BY e.fish_obsrvtn_pnt_distinct_id, e.downstream_route_measure;


