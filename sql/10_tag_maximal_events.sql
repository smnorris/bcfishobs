-- find and tag maximal observations for a given species
WITH maximal AS
(SELECT DISTINCT
  a.fish_obsrvtn_pnt_distinct_id,
  a.blue_line_key,
  a.downstream_route_measure
FROM whse_fish.fiss_fish_obsrvtn_events a
LEFT OUTER JOIN whse_fish.fiss_fish_obsrvtn_events b
ON
  -- first, the upstream observation has to be same spp
  b.species_ids @> ARRAY[%s] AND
  fwa_upstream(
    a.blue_line_key,
    a.downstream_route_measure,
    a.wscode_ltree,
    a.localcode_ltree,
    b.blue_line_key,
    b.downstream_route_measure,
    b.wscode_ltree,
    b.localcode_ltree
  )
WHERE b.fish_obsrvtn_pnt_distinct_id is null
AND a.species_ids @> ARRAY[%s]
ORDER BY blue_line_key, downstream_route_measure
)

-- When this update is applied via python, the conditional logic based on NULL
-- is required - otherwise no updates are applied.
-- When applied via psql it is not - very odd.
UPDATE whse_fish.fiss_fish_obsrvtn_events
SET maximal_species =
  CASE WHEN maximal_species IS NULL THEN ARRAY[%s]
  ELSE array_append(maximal_species, %s)
END
WHERE fish_obsrvtn_pnt_distinct_id IN
  (SELECT fish_obsrvtn_pnt_distinct_id FROM maximal)

