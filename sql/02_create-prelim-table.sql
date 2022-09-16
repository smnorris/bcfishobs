-- ---------------------------------------------
-- Reference fish observations to the FWA stream network, creating output
-- event table fiss_fish_obsrvtn_events, which links the observation points
-- to blue_line_key routes.
-- ---------------------------------------------

-- ---------------------------------------------
-- First, create preliminary event table, with observation points matched to
-- all streams within 1500m. Use this for subsequent analysis. Since we are
-- using such a large search area and also calculating the measures, this may
-- take some time (~6min)
-- ---------------------------------------------


DROP TABLE IF EXISTS bcfishobs.fiss_fish_obsrvtn_events_prelim1;

CREATE TABLE bcfishobs.fiss_fish_obsrvtn_events_prelim1 AS
WITH candidates AS
 ( SELECT
    pt.fish_obsrvtn_pnt_distinct_id,
    nn.linear_feature_id,
    nn.wscode_ltree,
    nn.localcode_ltree,
    nn.blue_line_key,
    nn.waterbody_key,
    nn.length_metre,
    nn.downstream_route_measure,
    nn.distance_to_stream,
    ST_LineMerge(nn.geom) AS geom
  FROM bcfishobs.fiss_fish_obsrvtn_pnt_distinct as pt
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
    AND str.edge_type != 6010
    ORDER BY str.geom <-> pt.geom
    LIMIT 100) as nn
  WHERE nn.distance_to_stream < 1500
),

-- find just the closest point for distinct blue_line_keys -
-- we don't want to match to all individual stream segments
bluelines AS
(SELECT * FROM
    (SELECT
      fish_obsrvtn_pnt_distinct_id,
      blue_line_key,
      min(distance_to_stream) AS distance_to_stream
    FROM candidates
    GROUP BY fish_obsrvtn_pnt_distinct_id, blue_line_key) as f
  ORDER BY distance_to_stream
)

-- from the selected blue lines, generate downstream_route_measure
SELECT
  bluelines.fish_obsrvtn_pnt_distinct_id,
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
INNER JOIN candidates ON bluelines.fish_obsrvtn_pnt_distinct_id = candidates.fish_obsrvtn_pnt_distinct_id
AND bluelines.blue_line_key = candidates.blue_line_key
AND bluelines.distance_to_stream = candidates.distance_to_stream
INNER JOIN bcfishobs.fiss_fish_obsrvtn_pnt_distinct pts
ON bluelines.fish_obsrvtn_pnt_distinct_id = pts.fish_obsrvtn_pnt_distinct_id;

-- ---------------------------------------------
-- index the intermediate table
CREATE INDEX ON bcfishobs.fiss_fish_obsrvtn_events_prelim1 (fish_obsrvtn_pnt_distinct_id);

