-- find species upstream of pscis crossings.
-- about 5min to run

SELECT
  stream_crossing_id,
  array_agg(species_codes) as species_codes
FROM (

SELECT DISTINCT
  a.stream_crossing_id,
  unnest(o.species_codes) as species_codes
FROM
  fp_working.pscis_habitat_3 a
LEFT OUTER JOIN whse_fish.fiss_fish_obsrvtn_events b
ON
 -- conditional upstream join logic, based on whether watershed codes are equivalent
  CASE
    -- first, consider simple case - streams where wscode and localcode are equivalent
    -- this is all children of the given wscode, plus segments with equivalent bluelinekey
    -- and a larger measure
     WHEN
        a.wscode_ltree = a.localcode_ltree AND (
          b.wscode_ltree <@ a.wscode_ltree AND
            (b.blue_line_key <> a.blue_line_key OR
             b.downstream_route_measure > a.downstream_route_measure + .01)
         )
     THEN TRUE
     -- next, the more complicated case - where wscode and localcode are not equal
     WHEN
        a.wscode_ltree != a.localcode_ltree AND
        (
          -- b is child of a
          b.wscode_ltree <@ a.wscode_ltree AND
          (
          -- AND b is the same watershed code, with larger localcode
          -- (query on wscode rather than blkey + measure to capture side channels)
            (b.wscode_ltree = a.wscode_ltree AND b.localcode_ltree >= a.localcode_ltree)
             OR
          -- OR b wscode > a localcode and b wscode is not a child of a localcode (tribs)
            (b.wscode_ltree > a.localcode_ltree AND NOT b.wscode_ltree <@ a.localcode_ltree)
             OR
          -- OR blue lines are equivalent and measure is greater
            (b.blue_line_key = a.blue_line_key AND b.downstream_route_measure > a.downstream_route_measure)
          )
        )
      THEN TRUE
   END
LEFT OUTER JOIN whse_fish.fiss_fish_obsrvtn_distinct o
ON b.fiss_fish_obsrvtn_distinct_id = o.fiss_fish_obsrvtn_distinct_id

) as foo
GROUP BY stream_crossing_id
