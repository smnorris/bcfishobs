-- ---------------------------------------------
-- Unpublished obstacles are loaded as utm coordinates - add geom type and load to main obstacle table
-- ---------------------------------------------
WITH pts AS
(SELECT DISTINCT  -- source may include duplicates
  featur_typ_code as feature_type_code,
  -- tweak codes to match those in existing table
  CASE
    WHEN featur_typ_code = 'F' THEN 'Falls'
    WHEN featur_typ_code = 'D' THEN 'Dam'
  END AS obstacle_name,
  point_id_field,
  utm_zone,
  utm_easting,
  utm_northing,
  height,
  length,
  sitesrvy_id,
  comments,
  ST_Transform(ST_PointFromText('POINT (' || utm_easting || ' ' || utm_northing || ')', 32600 + utm_zone::int), 3005) as geom
FROM whse_fish.fiss_obstacles_non_whse)

INSERT INTO whse_fish.fiss_obstacles_pnt_sp
(obstacle_code, obstacle_name, height, length, utm_zone, utm_easting, utm_northing, geom)
SELECT
  feature_type_code,
  obstacle_name,
  height,
  length,
  utm_zone,
  utm_easting,
  utm_northing,
  (ST_Dump(geom)).geom
FROM pts
-- not all data has geom (lots of null UTMs), filter those out
WHERE geom is not null;


-- ---------------------------------------------
-- With obstacles all loaded, extract distinct falls from the obstacle table.
-- Use the maximum height present in the db for the distinct location
-- ---------------------------------------------
DROP TABLE IF EXISTS whse_fish.fiss_falls_pnt_distinct;

CREATE TABLE whse_fish.fiss_falls_pnt_distinct
(
 falls_id                   serial primary key  ,
 fish_obstacle_point_ids    integer[]           ,
 height                     double precision    ,
 watershed_group_code       text                ,
 geom                       geometry(Point, 3005)
);

WITH height_cleaned AS
(
  SELECT
    fish_obstacle_point_id,
    CASE
      -- remove garbage from height values
      WHEN height = 999 THEN NULL
      WHEN height = 9999 THEN NULL
      WHEN height = -1000 THEN NULL
      ELSE height
    END as height,
    geom
  FROM whse_fish.fiss_obstacles_pnt_sp o
  WHERE o.obstacle_name = 'Falls'
),

agg AS
(
  SELECT
    array_agg(o.fish_obstacle_point_id) as fish_obstacle_point_ids,
    unnest(array_agg(o.height)) as height,
    geom
  FROM height_cleaned o
  GROUP BY o.geom
)

INSERT INTO whse_fish.fiss_falls_pnt_distinct
(fish_obstacle_point_ids, height, watershed_group_code, geom)
SELECT
  agg.fish_obstacle_point_ids,
  max(agg.height) as height,
  g.watershed_group_code,
  agg.geom
FROM agg
INNER JOin whse_basemapping.fwa_watershed_groups_subdivided g
ON ST_Intersects(agg.geom, g.geom)
GROUP BY agg.fish_obstacle_point_ids, g.watershed_group_code, agg.geom
ORDER BY agg.fish_obstacle_point_ids;


-- ---------------------------------------------
-- Next, reference the falls to the FWA stream network, creating output
-- event table fiss_falls_events. For now, simply join to closest stream.
-- ---------------------------------------------
DROP TABLE IF EXISTS whse_fish.fiss_falls_events;

CREATE TABLE whse_fish.fiss_falls_events
 (
 falls_id                 integer primary key,
 fish_obstacle_point_ids  integer[]        ,
 linear_feature_id        bigint           ,
 wscode_ltree             ltree            ,
 localcode_ltree          ltree            ,
 waterbody_key            integer          ,
 blue_line_key            integer          ,
 downstream_route_measure double precision ,
 distance_to_stream       double precision ,
 height                   double precision ,
 watershed_group_code     text
);

-- first, find up to 10 streams within 200m of the falls
WITH candidates AS
 ( SELECT
    pt.falls_id,
    pt.fish_obstacle_point_ids,
    nn.linear_feature_id,
    nn.wscode_ltree,
    nn.localcode_ltree,
    nn.blue_line_key,
    nn.waterbody_key,
    nn.length_metre,
    nn.downstream_route_measure,
    nn.upstream_route_measure,
    nn.distance_to_stream,
    pt.height,
    pt.watershed_group_code,
    ST_LineMerge(nn.geom) AS geom
  FROM whse_fish.fiss_falls_pnt_distinct as pt
  CROSS JOIN LATERAL
  (SELECT
     str.linear_feature_id,
     str.wscode_ltree,
     str.localcode_ltree,
     str.blue_line_key,
     str.waterbody_key,
     str.length_metre,
     str.downstream_route_measure,
     str.upstream_route_measure,
     str.geom,
     ST_Distance(str.geom, pt.geom) as distance_to_stream
    FROM whse_basemapping.fwa_stream_networks_sp AS str
    WHERE str.localcode_ltree IS NOT NULL
    AND NOT str.wscode_ltree <@ '999'
    ORDER BY str.geom <-> pt.geom
    LIMIT 10) as nn
  WHERE nn.distance_to_stream < 200
),

-- find just the closest point for distinct blue_line_keys -
-- we don't want to match to all individual stream segments
bluelines AS
(SELECT * FROM
    (SELECT
      falls_id,
      blue_line_key,
      min(distance_to_stream) AS distance_to_stream
    FROM candidates
    GROUP BY falls_id, blue_line_key) as f
  ORDER BY distance_to_stream asc
)

-- from the selected blue lines, generate downstream_route_measure
-- and only return the closest match
INSERT INTO whse_fish.fiss_falls_events
 (falls_id,
 fish_obstacle_point_ids,
 linear_feature_id,
 wscode_ltree,
 localcode_ltree,
 waterbody_key,
 blue_line_key,
 downstream_route_measure,
 distance_to_stream,
 height,
 watershed_group_code)
SELECT DISTINCT ON (bluelines.falls_id)
  bluelines.falls_id,
  candidates.fish_obstacle_point_ids,
  candidates.linear_feature_id,
  candidates.wscode_ltree,
  candidates.localcode_ltree,
  candidates.waterbody_key,
  bluelines.blue_line_key,
  -- reference the point to the stream, making output measure an integer
  -- (ensuring point measure is between stream's downtream measure and upstream measure)
  CEIL(GREATEST(candidates.downstream_route_measure, FLOOR(LEAST(candidates.upstream_route_measure,
  (ST_LineLocatePoint(candidates.geom, ST_ClosestPoint(candidates.geom, pts.geom)) * candidates.length_metre) + candidates.downstream_route_measure
  )))) as downstream_route_measure,
  candidates.distance_to_stream,
  candidates.height,
  candidates.watershed_group_code
FROM bluelines
INNER JOIN candidates ON bluelines.falls_id = candidates.falls_id
AND bluelines.blue_line_key = candidates.blue_line_key
AND bluelines.distance_to_stream = candidates.distance_to_stream
INNER JOIN whse_fish.fiss_falls_pnt_distinct pts
ON bluelines.falls_id = pts.falls_id
ORDER BY bluelines.falls_id, candidates.distance_to_stream asc;

CREATE INDEX ON whse_fish.fiss_falls_events (falls_id);
CREATE INDEX ON whse_fish.fiss_falls_events (linear_feature_id);
CREATE INDEX ON whse_fish.fiss_falls_events (blue_line_key);
CREATE INDEX ON whse_fish.fiss_falls_events USING GIST (wscode_ltree);
CREATE INDEX ON whse_fish.fiss_falls_events USING BTREE (wscode_ltree);
CREATE INDEX ON whse_fish.fiss_falls_events USING GIST (localcode_ltree);
CREATE INDEX ON whse_fish.fiss_falls_events USING BTREE (localcode_ltree);
CREATE INDEX ON whse_fish.fiss_falls_events USING GIST (fish_obstacle_point_ids gist__intbig_ops);


-- and pull things back out into a spatial table that holds all input falls, not just distinct locations
-- this is very useful for visualization - it makes the source ids easier to get at.
DROP TABLE IF EXISTS whse_fish.fiss_falls_events_sp;

CREATE TABLE whse_fish.fiss_falls_events_sp
 (
 fish_obstacle_point_id  integer primary key,
 linear_feature_id        bigint           ,
 wscode_ltree             ltree            ,
 localcode_ltree          ltree            ,
 waterbody_key            integer          ,
 blue_line_key            integer          ,
 downstream_route_measure double precision ,
 distance_to_stream       double precision ,
 height                   double precision ,
 watershed_group_code     text,
 geom                     geometry(Point,3005)
);

INSERT INTO whse_fish.fiss_falls_events_sp
 (
 fish_obstacle_point_id,
 linear_feature_id,
 wscode_ltree,
 localcode_ltree,
 waterbody_key,
 blue_line_key,
 downstream_route_measure,
 distance_to_stream,
 height,
 watershed_group_code,
 geom
)
SELECT
 unnest(r.fish_obstacle_point_ids) as fish_obstacle_point_id,
 r.linear_feature_id,
 r.wscode_ltree,
 r.localcode_ltree,
 r.waterbody_key,
 r.blue_line_key,
 r.downstream_route_measure,
 r.distance_to_stream,
 r.height,
 r.watershed_group_code,
 (ST_Dump(ST_Force2D(ST_locateAlong(s.geom, r.downstream_route_measure)))).geom as geom
FROM whse_fish.fiss_falls_events r
INNER JOIN whse_basemapping.fwa_stream_networks_sp s
ON r.linear_feature_id = s.linear_feature_id;


CREATE INDEX ON whse_fish.fiss_falls_events_sp (linear_feature_id);
CREATE INDEX ON whse_fish.fiss_falls_events_sp (blue_line_key);
CREATE INDEX ON whse_fish.fiss_falls_events_sp USING GIST (wscode_ltree);
CREATE INDEX ON whse_fish.fiss_falls_events_sp USING BTREE (wscode_ltree);
CREATE INDEX ON whse_fish.fiss_falls_events_sp USING GIST (localcode_ltree);
CREATE INDEX ON whse_fish.fiss_falls_events_sp USING BTREE (localcode_ltree);
CREATE INDEX ON whse_fish.fiss_falls_events_sp USING GIST (geom);