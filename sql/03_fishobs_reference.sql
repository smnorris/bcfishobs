-- ---------------------------------------------
-- Reference fish observations on the FWA stream network, creating output
-- event table linking the observation points to blue_lines
-- Building the observation event table is more complex than simply snapping
-- to the nearest stream because we want to ensure that observations within
-- waterbodies are associated with waterbodies, rather than the closest stream
-- ---------------------------------------------



-- ---------------------------------------------
-- First, create preliminary event table, with observations matched to all
-- streams within 1500m. Use this for subsequent analysis. Since we are using
-- such a large search area and also calculating the measures, this may take
-- some time (~6min)
-- ---------------------------------------------

-- For development, create a non-temp table
-- DROP TABLE IF EXISTS whse_fish.fiss_fish_obsrvtn_events_prelim1;
-- CREATE TABLE whse_fish.fiss_fish_obsrvtn_events_prelim1 AS

-- find nearest streams within 1500m, these are candidates for matching
CREATE TEMPORARY TABLE fiss_fish_obsrvtn_events_prelim1 AS
WITH candidates AS
 ( SELECT
    pt.fiss_fish_obsrvtn_distinct_id,
    nn.linear_feature_id,
    nn.wscode_ltree,
    nn.localcode_ltree,
    nn.blue_line_key,
    nn.waterbody_key,
    nn.length_metre,
    nn.downstream_route_measure,
    nn.distance_to_stream,
    ST_LineMerge(nn.geom) AS geom
  FROM whse_fish.fiss_fish_obsrvtn_distinct as pt
  CROSS JOIN LATERAL
  (SELECT
     str.linear_feature_id,
     str.wscode_ltree,
     str.localcode_ltree,
     str.blue_line_key,
     str.waterbody_key,
     str.length_metre,
     str.downstream_route_measure,
     str.geom,
     ST_Distance(str.geom, pt.geom) as distance_to_stream
    FROM whse_basemapping.fwa_stream_networks_sp AS str
    WHERE str.localcode_ltree IS NOT NULL
    AND NOT str.wscode_ltree <@ '999'
    ORDER BY str.geom <-> pt.geom
    LIMIT 100) as nn
  WHERE nn.distance_to_stream < 1500
),

-- find just the closest point for distinct blue_line_keys -
-- we don't want to match to all individual stream segments
bluelines AS
(SELECT * FROM
    (SELECT
      fiss_fish_obsrvtn_distinct_id,
      blue_line_key,
      min(distance_to_stream) AS distance_to_stream
    FROM candidates
    GROUP BY fiss_fish_obsrvtn_distinct_id, blue_line_key) as f
  ORDER BY distance_to_stream
)

-- from the selected blue lines, generate downstream_route_measure
SELECT
  bluelines.fiss_fish_obsrvtn_distinct_id,
  candidates.linear_feature_id,
  candidates.wscode_ltree,
  candidates.localcode_ltree,
  candidates.waterbody_key,
  bluelines.blue_line_key,
  (ST_LineLocatePoint(candidates.geom,
                       ST_ClosestPoint(candidates.geom, pts.geom))
     * candidates.length_metre) + candidates.downstream_route_measure
    AS downstream_route_measure,
  candidates.distance_to_stream
FROM bluelines
INNER JOIN candidates ON bluelines.fiss_fish_obsrvtn_distinct_id = candidates.fiss_fish_obsrvtn_distinct_id
AND bluelines.blue_line_key = candidates.blue_line_key
AND bluelines.distance_to_stream = candidates.distance_to_stream
INNER JOIN whse_fish.fiss_fish_obsrvtn_distinct pts ON bluelines.fiss_fish_obsrvtn_distinct_id = pts.fiss_fish_obsrvtn_distinct_id;

-- ---------------------------------------------
-- index the intermediate table
CREATE INDEX ON fiss_fish_obsrvtn_events_prelim1 (fiss_fish_obsrvtn_distinct_id);
-- CREATE INDEX ON whse_fish.fiss_fish_obsrvtn_events_prelim1 (fiss_fish_obsrvtn_distinct_id);


-- ---------------------------------------------

CREATE TEMPORARY TABLE fiss_fish_obsrvtn_events_prelim2
  (LIKE fiss_fish_obsrvtn_events_prelim1 INCLUDING ALL);
-- DROP TABLE IF EXISTS whse_fish.fiss_fish_obsrvtn_events_prelim2;
-- CREATE TABLE whse_fish.fiss_fish_obsrvtn_events_prelim2
--  (LIKE whse_fish.fiss_fish_obsrvtn_events_prelim1 INCLUDING ALL);

-- ---------------------------------------------
-- Insert events matched to waterbodies.
-- This is probably a lot more complicated than it has to be but we want to
-- ensure that observations in waterbodies are associated with waterbodies
-- rather than just the closest stream. We use a large 1500m tolerance (in above
-- query) because observations in lakes may well be quite far from a stream flow
-- line within larger lakes, or coordinates may be well away from the lake.
-- This query:
--   - joins the observations to the FWA via wbody_key (1:many via lookup)
--   - from the many possible matches, choose just the closest
--   - inserts these records into the output table

-- where observation is coded as a lake or wetland,
-- join to waterbody_key via wdic_waterbodies
WITH wb AS
(
  SELECT DISTINCT
    o.fiss_fish_obsrvtn_distinct_id,
    wb.waterbody_key
  FROM whse_fish.fiss_fish_obsrvtn_distinct o
  INNER JOIN whse_fish.wdic_waterbodies wdic ON o.wbody_id = wdic.id
  INNER JOIN whse_basemapping.fwa_waterbodies_20k_50k lut
     ON LTRIM(wdic.waterbody_identifier,'0') = lut.waterbody_key_50k::TEXT||lut.watershed_group_code_50k
  INNER JOIN
     (SELECT DISTINCT waterbody_key, watershed_group_code
      FROM whse_basemapping.fwa_lakes_poly
      UNION ALL
      SELECT DISTINCT waterbody_key, watershed_group_code
      FROM whse_basemapping.fwa_manmade_waterbodies_poly
      UNION ALL
      SELECT DISTINCT waterbody_key, watershed_group_code
      FROM whse_basemapping.fwa_wetlands_poly
      ) wb
  ON lut.waterbody_key_20k = wb.waterbody_key
  WHERE o.waterbody_type IN ('Lake', 'Wetland')
  ORDER BY o.fiss_fish_obsrvtn_distinct_id
),
-- from the candidate matches generated above, use the one closest to a stream
closest AS
(
  SELECT DISTINCT ON
   (e.fiss_fish_obsrvtn_distinct_id)
    e.fiss_fish_obsrvtn_distinct_id,
    e.distance_to_stream
  FROM fiss_fish_obsrvtn_events_prelim1 e
  INNER JOIN wb ON e.fiss_fish_obsrvtn_distinct_id = wb.fiss_fish_obsrvtn_distinct_id
  AND e.waterbody_key = wb.waterbody_key
  ORDER BY fiss_fish_obsrvtn_distinct_id, distance_to_stream
)
-- Insert the results into our output table
-- Note that there are duplicate records because observations can be equidistant from
-- several stream lines. Insert records with highest measure (though they should be the same)
INSERT INTO fiss_fish_obsrvtn_events_prelim2
SELECT DISTINCT ON (e.fiss_fish_obsrvtn_distinct_id)
  e.fiss_fish_obsrvtn_distinct_id,
  e.linear_feature_id,
  e.wscode_ltree,
  e.localcode_ltree,
  e.waterbody_key,
  e.blue_line_key,
  e.downstream_route_measure,
  e.distance_to_stream
FROM fiss_fish_obsrvtn_events_prelim1 e
INNER JOIN closest
ON e.fiss_fish_obsrvtn_distinct_id = closest.fiss_fish_obsrvtn_distinct_id
AND e.distance_to_stream = closest.distance_to_stream
WHERE e.waterbody_key is NOT NULL
ORDER BY e.fiss_fish_obsrvtn_distinct_id, e.downstream_route_measure;


-- ---------------------------------------------
-- Some observations in waterbodies do not get added above due to lookup quirks.
-- Insert these records simply based on the closest stream
-- ---------------------------------------------
WITH unmatched_wb AS
(    SELECT e.*
    FROM fiss_fish_obsrvtn_events_prelim1 e
    INNER JOIN whse_fish.fiss_fish_obsrvtn_distinct o
    ON e.fiss_fish_obsrvtn_distinct_id = o.fiss_fish_obsrvtn_distinct_id
    LEFT OUTER JOIN fiss_fish_obsrvtn_events_prelim2 p
    ON e.fiss_fish_obsrvtn_distinct_id = p.fiss_fish_obsrvtn_distinct_id
    WHERE o.wbody_id IS NOT NULL AND o.waterbody_type IN ('Lake','Wetland')
    AND p.fiss_fish_obsrvtn_distinct_id IS NULL
),

closest_unmatched AS
(
  SELECT DISTINCT ON (fiss_fish_obsrvtn_distinct_id)
    fiss_fish_obsrvtn_distinct_id,
    distance_to_stream
  FROM unmatched_wb
  ORDER BY fiss_fish_obsrvtn_distinct_id, distance_to_stream
)

INSERT INTO fiss_fish_obsrvtn_events_prelim2
SELECT DISTINCT ON (e.fiss_fish_obsrvtn_distinct_id)
  e.fiss_fish_obsrvtn_distinct_id,
  e.linear_feature_id,
  e.wscode_ltree,
  e.localcode_ltree,
  e.waterbody_key,
  e.blue_line_key,
  e.downstream_route_measure,
  e.distance_to_stream
FROM fiss_fish_obsrvtn_events_prelim1 e
INNER JOIN closest_unmatched
ON e.fiss_fish_obsrvtn_distinct_id = closest_unmatched.fiss_fish_obsrvtn_distinct_id
AND e.distance_to_stream = closest_unmatched.distance_to_stream
ORDER BY e.fiss_fish_obsrvtn_distinct_id, e.downstream_route_measure;



-- ---------------------------------------------
-- All observations in waterbodies should now be in the output.
-- Next, insert observations in streams.
-- We *could* use the 50k-20k lookup to restrict matches but matching to the
-- nearest stream is probably adequate for this exercise.
-- Note that our tolerance is much smaller than with waterbodies -
-- extract only records within 300m of a stream from the preliminary table.
-- ---------------------------------------------
WITH unmatched AS
(   SELECT e.*
    FROM fiss_fish_obsrvtn_events_prelim1 e
    INNER JOIN whse_fish.fiss_fish_obsrvtn_distinct o
    ON e.fiss_fish_obsrvtn_distinct_id = o.fiss_fish_obsrvtn_distinct_id
    WHERE o.waterbody_type NOT IN ('Lake', 'Wetland')
    AND e.distance_to_stream <= 300
),

closest_unmatched AS
(
  SELECT DISTINCT ON (fiss_fish_obsrvtn_distinct_id)
    fiss_fish_obsrvtn_distinct_id,
    distance_to_stream
  FROM unmatched
  ORDER BY fiss_fish_obsrvtn_distinct_id, distance_to_stream
)

INSERT INTO fiss_fish_obsrvtn_events_prelim2
SELECT DISTINCT ON (e.fiss_fish_obsrvtn_distinct_id)
  e.fiss_fish_obsrvtn_distinct_id,
  e.linear_feature_id,
  e.wscode_ltree,
  e.localcode_ltree,
  e.waterbody_key,
  e.blue_line_key,
  e.downstream_route_measure,
  e.distance_to_stream
FROM fiss_fish_obsrvtn_events_prelim1 e
INNER JOIN closest_unmatched
ON e.fiss_fish_obsrvtn_distinct_id = closest_unmatched.fiss_fish_obsrvtn_distinct_id
AND e.distance_to_stream = closest_unmatched.distance_to_stream;


-- create output table
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
  dstnct.obs_ids,
  dstnct.species_codes
FROM fiss_fish_obsrvtn_events_prelim2 p2
INNER JOIN whse_fish.fiss_fish_obsrvtn_distinct dstnct
ON p2.fiss_fish_obsrvtn_distinct_id = dstnct.fiss_fish_obsrvtn_distinct_id;

CREATE INDEX ON whse_fish.fiss_fish_obsrvtn_events USING gist (wscode_ltree);
CREATE INDEX ON whse_fish.fiss_fish_obsrvtn_events USING btree (wscode_ltree);
CREATE INDEX ON whse_fish.fiss_fish_obsrvtn_events USING gist (localcode_ltree) ;
CREATE INDEX ON whse_fish.fiss_fish_obsrvtn_events USING btree (localcode_ltree);
CREATE INDEX ON whse_fish.fiss_fish_obsrvtn_events (linear_feature_id);
CREATE INDEX ON whse_fish.fiss_fish_obsrvtn_events (blue_line_key);
CREATE INDEX ON whse_fish.fiss_fish_obsrvtn_events (waterbody_key);