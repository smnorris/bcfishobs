-- ---------------------------------------------
-- Reference fish observations to the FWA stream network, creating output
-- event table fiss_fish_obsrvtn_events, which links the observation points
-- to blue_line_key routes.
-- ---------------------------------------------

-- ---------------------------------------------
-- First, create preliminary event table, with observation points matched to
-- all streams within 1500m. Use this for subsequent analysis. Since we are
-- using such a large search area and also calculating the measures, this takes time
-- ---------------------------------------------
drop table if exists bcfishobs.fiss_fish_obsrvtn_events_prelim_a;
create table bcfishobs.fiss_fish_obsrvtn_events_prelim_a (
  fish_obsrvtn_pnt_distinct_id integer,
  linear_feature_id bigint,
  wscode_ltree ltree,
  localcode_ltree ltree,
  waterbody_key integer,
  blue_line_key integer,
  downstream_route_measure double precision,
  distance_to_stream double precision
);
create index on bcfishobs.fiss_fish_obsrvtn_events_prelim_a (fish_obsrvtn_pnt_distinct_id);


WITH candidates AS (
  select
    pt.fish_obsrvtn_pnt_distinct_id,
    nn.linear_feature_id,
    nn.blue_line_key,
    nn.distance_to_stream
  from bcfishobs.fiss_fish_obsrvtn_pnt_distinct as pt
  cross join lateral
  (select
     s.linear_feature_id,
     s.blue_line_key,
     ST_Distance(s.geom, pt.geom) as distance_to_stream
    from whse_basemapping.fwa_stream_networks_sp as s
    where s.localcode_ltree is not null
    and not s.wscode_ltree <@ '999'
    and s.edge_type != 6010
    order by s.geom <-> pt.geom
    limit 100) as nn
  where nn.distance_to_stream < 1500
),

-- find just the closest point for distinct blue_line_keys -
-- we don't want to match to all individual stream segments
bluelines AS (
  select distinct on (fish_obsrvtn_pnt_distinct_id, blue_line_key)
    fish_obsrvtn_pnt_distinct_id,
    blue_line_key,
    linear_feature_id,
    distance_to_stream
  from candidates
  order by fish_obsrvtn_pnt_distinct_id, blue_line_key, distance_to_stream
)

-- from the selected blue lines, generate downstream_route_measure
insert into bcfishobs.fiss_fish_obsrvtn_events_prelim_a
SELECT
  bl.fish_obsrvtn_pnt_distinct_id,
  c.linear_feature_id,
  s.wscode_ltree,
  s.localcode_ltree,
  s.waterbody_key,
  bl.blue_line_key,
  st_interpolatepoint(s.geom, pts.geom) AS downstream_route_measure,
  c.distance_to_stream
FROM bluelines bl
INNER JOIN candidates c ON bl.fish_obsrvtn_pnt_distinct_id = c.fish_obsrvtn_pnt_distinct_id
AND bl.blue_line_key = c.blue_line_key
AND bl.distance_to_stream = c.distance_to_stream
INNER JOIN bcfishobs.fiss_fish_obsrvtn_pnt_distinct pts ON bl.fish_obsrvtn_pnt_distinct_id = pts.fish_obsrvtn_pnt_distinct_id
inner join whse_basemapping.fwa_stream_networks_sp s on bl.linear_feature_id = s.linear_feature_id;