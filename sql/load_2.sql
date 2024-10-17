-- Insert observations on waterbodies, matching on wb_key, within 1500m
-- ---------------------------------------------
drop table if exists bcfishobs.obs_fwa;
create table bcfishobs.obs_fwa (
  observation_key text primary key,
  linear_feature_id bigint,
  wscode_ltree ltree,
  localcode_ltree ltree,
  waterbody_key integer,
  blue_line_key integer,
  downstream_route_measure double precision,
  distance_to_stream double precision,
  match_type text
);
create index on bcfishobs.obs_fwa (linear_feature_id);

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
    o.observation_key,
    wb.waterbody_key
  FROM bcfishobs.obs o
  INNER JOIN whse_fish.wdic_waterbodies wdic ON o.wbody_id = wdic.id
  INNER JOIN whse_basemapping.fwa_waterbodies_20k_50k lut
     ON LTRIM(wdic.waterbody_identifier,'0') = lut.waterbody_key_50k::TEXT||lut.watershed_group_code_50k
  INNER JOIN whse_basemapping.fwa_waterbodies wb
  ON lut.waterbody_key_20k = wb.waterbody_key
  WHERE o.waterbody_type IN ('Lake', 'Wetland')
  ORDER BY o.observation_key
),
-- from the candidate matches generated above, use the one closest to a stream
closest AS
(
  SELECT DISTINCT ON
   (e.observation_key)
    e.observation_key,
    e.distance_to_stream
  FROM bcfishobs.obs_streams1500m e
  INNER JOIN wb ON e.observation_key = wb.observation_key
  AND e.waterbody_key = wb.waterbody_key
  ORDER BY observation_key, distance_to_stream
)
-- Insert the results into our output table
-- Note that there are duplicate records because observations can be
-- equidistant from
-- several stream lines. Insert records with highest measure (though they
-- should be the same)
INSERT INTO bcfishobs.obs_fwa
SELECT DISTINCT ON (e.observation_key)
  e.observation_key,
  e.linear_feature_id,
  e.wscode_ltree,
  e.localcode_ltree,
  e.waterbody_key,
  e.blue_line_key,
  e.downstream_route_measure,
  e.distance_to_stream,
  'D. matched - waterbody; construction line within 1500m; lookup'
FROM bcfishobs.obs_streams1500m e
INNER JOIN closest
ON e.observation_key = closest.observation_key
AND e.distance_to_stream = closest.distance_to_stream
WHERE e.waterbody_key is NOT NULL
ORDER BY e.observation_key, e.downstream_route_measure;


-- ---------------------------------------------
-- Some observations in waterbodies do not get added above due to
-- lookup quirks.
-- Insert these records simply based on the closest stream
-- ---------------------------------------------
WITH unmatched_wb AS
(    SELECT e.*
    FROM bcfishobs.obs_streams1500m e
    INNER JOIN bcfishobs.obs o
    ON e.observation_key = o.observation_key
    LEFT OUTER JOIN bcfishobs.obs_fwa p
    ON e.observation_key = p.observation_key
    WHERE o.wbody_id IS NOT NULL AND o.waterbody_type IN ('Lake','Wetland')
    AND p.observation_key IS NULL
),

closest_unmatched AS
(
  SELECT DISTINCT ON (observation_key)
    observation_key,
    distance_to_stream
  FROM unmatched_wb
  ORDER BY observation_key, distance_to_stream
)

INSERT INTO bcfishobs.obs_fwa
SELECT DISTINCT ON (e.observation_key)
  e.observation_key,
  e.linear_feature_id,
  e.wscode_ltree,
  e.localcode_ltree,
  e.waterbody_key,
  e.blue_line_key,
  e.downstream_route_measure,
  e.distance_to_stream,
  'E. matched - waterbody; construction line within 1500m; closest'
FROM bcfishobs.obs_streams1500m e
INNER JOIN closest_unmatched
ON e.observation_key = closest_unmatched.observation_key
AND e.distance_to_stream = closest_unmatched.distance_to_stream
ORDER BY e.observation_key, e.downstream_route_measure;


-- 1.
-- Find points on streams that are within 100m of stream, but only
-- insert those with an exact match in the 20k-50k lookup.
-- This means that if we have multiple matches within 100m, we insert
-- the record with a match in the xref - if available.
WITH unmatched AS
(   SELECT e.*
    FROM bcfishobs.obs_streams1500m e
    INNER JOIN bcfishobs.obs o
    ON e.observation_key = o.observation_key
    INNER JOIN whse_basemapping.fwa_streams_20k_50k lut
    ON replace(o.new_watershed_code, '-', '') = lut.watershed_code_50k
    AND e.linear_feature_id = lut.linear_feature_id_20k
    WHERE o.waterbody_type NOT IN ('Lake', 'Wetland')
    AND e.distance_to_stream <= 100
    ORDER BY e.observation_key , e.distance_to_stream
),

-- there can still potentially be multiple results, find the closest
closest_unmatched AS
(
  SELECT DISTINCT ON (observation_key)
    observation_key,
    distance_to_stream
  FROM unmatched
  ORDER BY observation_key, distance_to_stream
)

INSERT INTO bcfishobs.obs_fwa
SELECT DISTINCT ON (e.observation_key)
  e.observation_key,
  e.linear_feature_id,
  e.wscode_ltree,
  e.localcode_ltree,
  e.waterbody_key,
  e.blue_line_key,
  e.downstream_route_measure,
  e.distance_to_stream,
  'A. matched - stream; within 100m; lookup'
FROM bcfishobs.obs_streams1500m e
INNER JOIN closest_unmatched
ON e.observation_key = closest_unmatched.observation_key
AND e.distance_to_stream = closest_unmatched.distance_to_stream;


-- 2.
-- For records that we haven't yet inserted, insert those that are 100m
-- or less from a stream, based just on minimum distance to stream
WITH unmatched AS
(   SELECT e1.*
    FROM bcfishobs.obs_streams1500m e1
    LEFT OUTER JOIN bcfishobs.obs_fwa e2
    ON e1.observation_key = e2.observation_key
    INNER JOIN bcfishobs.obs o
    ON e1.observation_key = o.observation_key
    WHERE o.waterbody_type NOT IN ('Lake', 'Wetland')
    AND e1.distance_to_stream <= 100
    AND e2.observation_key IS NULL
    ORDER BY e1.observation_key , e1.distance_to_stream
),

-- there can still potentially be multiple results, find the closest
closest_unmatched AS
(
  SELECT DISTINCT ON (observation_key)
    observation_key,
    distance_to_stream
  FROM unmatched
  ORDER BY observation_key, distance_to_stream
)

INSERT INTO bcfishobs.obs_fwa
SELECT DISTINCT ON (e.observation_key)
  e.observation_key,
  e.linear_feature_id,
  e.wscode_ltree,
  e.localcode_ltree,
  e.waterbody_key,
  e.blue_line_key,
  e.downstream_route_measure,
  e.distance_to_stream,
  'B. matched - stream; within 100m; closest stream'
FROM bcfishobs.obs_streams1500m e
INNER JOIN closest_unmatched
ON e.observation_key = closest_unmatched.observation_key
AND e.distance_to_stream = closest_unmatched.distance_to_stream;


-- 3.
-- Finally, within records that still have not been inserted,
-- find those that are >100m and <500m from a stream and have a exact
-- (linear_feature_id) match in the xref lookup.
WITH unmatched AS
(   SELECT e1.*
    FROM bcfishobs.obs_streams1500m e1
    LEFT OUTER JOIN bcfishobs.obs_fwa e2
    ON e1.observation_key = e2.observation_key
    INNER JOIN bcfishobs.obs o
    ON e1.observation_key = o.observation_key
    INNER JOIN whse_basemapping.fwa_streams_20k_50k lut
    ON replace(o.new_watershed_code, '-', '') = lut.watershed_code_50k
    AND e1.linear_feature_id = lut.linear_feature_id_20k
    WHERE o.waterbody_type NOT IN ('Lake', 'Wetland')
    AND e1.distance_to_stream > 100 AND e1.distance_to_stream < 500
    AND e2.observation_key IS NULL
    ORDER BY e1.observation_key , e1.distance_to_stream
),

-- there can still potentially be multiple results, find the closest
closest_unmatched AS
(
  SELECT DISTINCT ON (observation_key)
    observation_key,
    distance_to_stream
  FROM unmatched
  ORDER BY observation_key, distance_to_stream
)

INSERT INTO bcfishobs.obs_fwa
SELECT DISTINCT ON (e.observation_key)
  e.observation_key,
  e.linear_feature_id,
  e.wscode_ltree,
  e.localcode_ltree,
  e.waterbody_key,
  e.blue_line_key,
  e.downstream_route_measure,
  e.distance_to_stream,
  'C. matched - stream; 100-500m; lookup'
FROM bcfishobs.obs_streams1500m e
INNER JOIN closest_unmatched
ON e.observation_key = closest_unmatched.observation_key
AND e.distance_to_stream = closest_unmatched.distance_to_stream
INNER JOIN bcfishobs.obs o
ON e.observation_key = o.observation_key;

