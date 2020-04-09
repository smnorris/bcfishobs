WITH upstr_obs AS
(SELECT
  a.dam_name,
  a.dam_date,
  a.watershed_group_code,
  unnest(b.obs_ids) as fish_observation_point_id
FROM
  cwf.large_dams a
LEFT OUTER JOIN
  whse_fish.fiss_fish_obsrvtn_events b
ON
  -- b is a child of a, always
  b.wscode_ltree <@ a.wscode_ltree
  AND
      -- conditional upstream join logic, based on whether watershed codes are equivalent
    CASE
      -- first, consider simple case - streams where wscode and localcode are equivalent
      -- this is all segments with equivalent bluelinekey and a larger measure
      -- (plus fudge factor)
       WHEN
          a.wscode_ltree = a.localcode_ltree AND
          (
              (b.blue_line_key <> a.blue_line_key OR
               a.downstream_route_measure < b.downstream_route_measure + .01)
          )
       THEN TRUE
       -- next, the more complicated case - where wscode and localcode are not equal
       WHEN
          a.wscode_ltree != a.localcode_ltree AND
          (
           -- higher up the blue line (plus fudge factor)
              (b.blue_line_key = a.blue_line_key AND
               a.downstream_route_measure < b.downstream_route_measure + .01 )
              OR
           -- tributaries: b wscode > a localcode and b wscode is not a child of a localcode
              (b.wscode_ltree > a.localcode_ltree AND
               NOT b.wscode_ltree <@ a.localcode_ltree)
              OR
           -- capture side channels: b is the same watershed code, with larger localcode
              (b.wscode_ltree = a.wscode_ltree
               AND b.localcode_ltree > a.localcode_ltree)
          )
        THEN TRUE
    END
WHERE b.species_codes && ARRAY['CH','SK','ST','CO','PK','CM']
AND a.barrier_ind = 'Y')

SELECT
 u.dam_name,
 u.dam_date,
 u.fish_observation_point_id,
 o.species_code,
 o.observation_date,
 o.source
FROM upstr_obs u
INNER JOIN
whse_fish.fiss_fish_obsrvtn_pnt_sp o
ON u.fish_observation_point_id = o.fish_observation_point_id
WHERE o.species_code IN ('CH','SK','ST','CO','PK','CM')
ORDER BY dam_name, species_code, observation_date;
