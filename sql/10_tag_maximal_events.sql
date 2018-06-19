-- find and tag maximal observations for a given species
WITH maximal AS
(SELECT DISTINCT
  a.fish_obsrvtn_distinct_id,
  a.blue_line_key,
  a.downstream_route_measure
FROM whse_fish.fiss_fish_obsrvtn_events a
LEFT OUTER JOIN whse_fish.fiss_fish_obsrvtn_events b
ON
  (a.blue_line_key = b.blue_line_key AND
   a.downstream_route_measure < b.downstream_route_measure)
OR
(
    -- b is a child of a, always
    b.wscode_ltree <@ a.wscode_ltree
    -- never return the start segment, that is added above
  AND b.linear_feature_id != a.linear_feature_id
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
               b.downstream_route_measure > a.downstream_route_measure + .01)
          )
       THEN TRUE
       -- next, the more complicated case - where wscode and localcode are not equal
       WHEN
          a.wscode_ltree != a.localcode_ltree AND
          (
           -- higher up the blue line (plus fudge factor)
              (b.blue_line_key = a.blue_line_key AND
               b.downstream_route_measure > a.downstream_route_measure + .01)
              OR
           -- tributaries: b wscode > a localcode and b wscode is not a child of a localcode
              (b.wscode_ltree > a.localcode_ltree AND
               NOT b.wscode_ltree <@ a.localcode_ltree)
              OR
           -- capture side channels: b is the same watershed code, with larger localcode
              (b.wscode_ltree = a.wscode_ltree
               AND b.localcode_ltree >= a.localcode_ltree)
          )
        THEN TRUE
    END
)
WHERE b.fish_obsrvtn_distinct_id is null
AND a.species_codes @> ARRAY[:species]
ORDER BY blue_line_key, downstream_route_measure
)

UPDATE whse_fish.fiss_fish_obsrvtn_events
SET maximal_species = maximal_species||ARRAY[:species]
FROM maximal m
WHERE fiss_fish_obsrvtn_events.fish_obsrvtn_distinct_id = m.fish_obsrvtn_distinct_id


